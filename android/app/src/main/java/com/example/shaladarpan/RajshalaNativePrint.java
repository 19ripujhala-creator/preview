package com.example.shaladarpan;

import android.app.Activity;
import android.graphics.Bitmap;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.os.Message;
import android.print.RajshalaPrintCapture;
import android.util.Log;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.CookieManager;
import android.webkit.ConsoleMessage;
import android.webkit.JsResult;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import androidx.webkit.CookieManagerCompat;
import androidx.webkit.WebViewFeature;
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader;
import com.tom_roush.pdfbox.io.MemoryUsageSetting;
import com.tom_roush.pdfbox.multipdf.PDFMergerUtility;
import com.tom_roush.pdfbox.pdmodel.PDDocument;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import java.io.ByteArrayInputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.ByteArrayOutputStream;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import org.json.JSONObject;
import org.json.JSONTokener;

/** Dedicated local browser for the existing NIC/Study Certificate print flows.
 * Portal scripts build their own popup. This bridge never rebuilds report HTML. */
public final class RajshalaNativePrint implements MethodChannel.MethodCallHandler {
    private final Activity activity;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final ExecutorService files = Executors.newSingleThreadExecutor();
    private final MethodChannel channel;
    private final Map<String, File> pdfs = new LinkedHashMap<>();
    private final List<WebView> views = new ArrayList<>();
    private String token;
    private String base;
    private boolean staff;
    private long setupStarted;
    private final List<Map<String, Object>> scopedCookies = new ArrayList<>();
    private final java.util.Set<String> cookieUrls = new java.util.LinkedHashSet<>();
    private String portalMessage;
    private String pageFailure;
    private FrameLayout container;
    private WebView page;
    private WebView popup;
    private boolean pageLoading;
    private volatile long mainPosts;
    private long loads;
    private volatile long expectedFullPost = -1;
    private RajshalaPrintCapture capture;
    private MethodChannel.Result pending;
    private Runnable polling;
    private Runnable operationTimeout;

    public RajshalaNativePrint(Activity activity, BinaryMessenger messenger) {
        this.activity = activity;
        channel = new MethodChannel(messenger, "rajshala/native_portal_print");
        channel.setMethodCallHandler(this);
    }

    @Override public void onMethodCall(MethodCall call, MethodChannel.Result result) {
        if (call.method.equals("begin")) {
            if (token != null) { result.error("NATIVE_PRINT_BUSY", "A native print is already running.", null); return; }
            begin(call, result); return;
        }
        if (token == null || !token.equals(call.argument("token"))) {
            result.error("SESSION_CHANGED", "Native print session changed.", null); return;
        }
        if (call.method.equals("close")) { close(); result.success(null); return; }
        if (call.method.equals("abort") && staff) {
            fail("SESSION_CHANGED", "The Staff print operation was cancelled.");
            if (capture != null) { capture.cancel(); capture = null; }
            if (page != null) page.stopLoading();
            if (popup != null) popup.stopLoading();
            result.success(null); return;
        }
        if (pending != null) { result.error("NATIVE_PRINT_BUSY", "A native browser operation is still running.", null); return; }
        pending = result;
        // A navigation can discard an evaluateJavascript callback. Keep a
        // deadline independent of the callback-driven DOM polling.
        final String operationSession = token;
        long deadline = call.method.equals("merge") ? 600000
                : call.method.equals("pdf") ? 65000
                : call.method.equals("postback") ? 60000
                : call.method.equals("navigate") ? 45000
                : call.method.equals("popup") ? 20000 : 15000;
        operationTimeout = () -> {
            if (pending == result && operationSession.equals(token)) {
                fail(portalMessage == null ? "PORTAL_SLOW" : "PORTAL_MESSAGE",
                        portalMessage == null ? "The native portal operation timed out." : portalMessage);
            }
        };
        if (staff && call.method.equals("navigate")) {
            String destination = call.argument("path");
            deadline = "Home/Staff/StaffHome.aspx".equals(destination)
                    ? Math.max(1, Math.min(15000, 25000 - (android.os.SystemClock.uptimeMillis() - setupStarted)))
                    : "Home/Staff/Staff_P10_DetailsV2.aspx".equals(destination) ? 20000 : 30000;
        }
        handler.postDelayed(operationTimeout, deadline);
        try {
            switch (call.method) {
                case "navigate":
                    String path = call.argument("path");
                    boolean destinationAllowed = staff
                            ? "Home/Staff/StaffHome.aspx".equals(path)
                                || "Home/Staff/Staff_P10_DetailsV2.aspx".equals(path)
                                || "Home/Staff/Staff_LeaveApplication_Applied.aspx".equals(path)
                            : "Home/School/SchoolStudentProfiles_New.aspx".equals(path)
                                || "Home/School/RMSA_Student_SchoolCertificate.aspx".equals(path);
                    if (!destinationAllowed) {
                        fail("PAGE_NOT_READY", "Native print destination blocked."); return;
                    }
                    portalMessage = null; pageFailure = null;
                    long previous = loads;
                    page.loadUrl(base + "/" + path);
                    poll(page, "document.readyState !== 'loading' && !!document.body && "
                            + "(!window.Sys || !Sys.WebForms || !Sys.WebForms.PageRequestManager.getInstance().get_isInAsyncPostBack())",
                            30000, () -> loads > previous && !pageLoading, () -> complete(null));
                    break;
                case "evaluate":
                    WebView target = Boolean.TRUE.equals(call.argument("popup")) ? popup : page;
                    if (target == null) { fail("PAGE_NOT_READY", "Portal print popup is unavailable."); return; }
                    evaluate(target, call.argument("script"), this::complete);
                    break;
                case "postback": postback(call); break;
                case "popup":
                    destroyPopup();
                    evaluate(page, call.argument("script"), ignored -> {
                        if (pending != null) poll(page, "true", 10000, () -> popup != null, () -> complete(null));
                    });
                    break;
                case "pdf":
                    Integer margin = call.argument("marginMm");
                    if (margin != null && (!staff || (margin != 5 && margin != 10))) {
                        fail("PAGE_NOT_READY", "Unsupported portal print margin."); return;
                    }
                    render(margin == null ? 10 : margin); break;
                case "staffCookies":
                    if (!staff) { fail("SESSION_CHANGED", "Staff browser session is unavailable."); return; }
                    complete(exportStaffCookies()); break;
                case "merge": merge(call); break;
                case "closePopup": destroyPopup(); complete(null); break;
                default: pending = null; result.notImplemented();
            }
        } catch (Exception e) { fail("NATIVE_PRINT_FAILED", "The native portal operation could not be completed."); }
    }

    private void begin(MethodCall call, MethodChannel.Result result) {
        String requestedBase = call.argument("base");
        Map<String, String> cookies = call.argument("cookies");
        staff = "staff".equals(call.argument("portal"));
        List<Map<String, Object>> requested = call.argument("scopedCookies");
        if (requestedBase == null || !requestedBase.matches("(?i)https://rajshaladarpan\\.rajasthan\\.gov\\.in/SD[1-5]")
                || (staff ? requested == null || requested.isEmpty() : cookies == null || cookies.isEmpty())) {
            result.error("SESSION_EXPIRED", "A verified portal session is required.", null); return;
        }
        if (staff && !WebViewFeature.isFeatureSupported(WebViewFeature.GET_COOKIE_INFO)) {
            result.error("NATIVE_PRINT_UNAVAILABLE", "Update Android System WebView to enable scoped Staff session handoff.", null); return;
        }
        scopedCookies.clear(); cookieUrls.clear();
        cookieUrls.add("https://rajshaladarpan.rajasthan.gov.in/");
        if (staff) {
            for (Map<String, Object> cookie : requested) {
                String name = String.valueOf(cookie.get("name"));
                String value = String.valueOf(cookie.get("value"));
                String domain = String.valueOf(cookie.get("domain")).replaceFirst("^\\.", "");
                String path = String.valueOf(cookie.get("path"));
                if (!validCookie(name, value) || !"rajshaladarpan.rajasthan.gov.in".equals(domain)
                        || !path.startsWith("/") || path.matches("(?s).*[;\\r\\n?#].*")) {
                    result.error("SESSION_EXPIRED", "Staff session cookies are invalid.", null); return;
                }
                scopedCookies.add(new HashMap<>(cookie));
                cookieUrls.add("https://rajshaladarpan.rajasthan.gov.in" + path);
            }
        } else {
            for (Map.Entry<String, String> cookie : cookies.entrySet()) {
                if (!validCookie(cookie.getKey(), cookie.getValue())) {
                    result.error("SESSION_EXPIRED", "School session cookies are invalid.", null); return;
                }
                Map<String, Object> row = new HashMap<>();
                row.put("name", cookie.getKey()); row.put("value", cookie.getValue());
                row.put("path", "/"); row.put("httpOnly", true);
                scopedCookies.add(row);
            }
        }
        token = UUID.randomUUID().toString(); base = requestedBase;
        setupStarted = android.os.SystemClock.uptimeMillis();
        final String beginSession = token;
        pending = result;
        polling = () -> {
            if (beginSession.equals(token) && pending == result) {
                fail("PORTAL_SLOW", "School browser session setup timed out."); close();
            }
        };
        handler.postDelayed(polling, staff ? 25000 : 30000);
        container = new FrameLayout(activity);
        // Attached but offscreen: no user can operate the government form.
        container.setTranslationX(-10000);
        activity.addContentView(container, new ViewGroup.LayoutParams(cssPixels(1366), cssPixels(900)));
        CookieManager manager = CookieManager.getInstance();
        manager.setAcceptCookie(true);
        manager.removeAllCookies(ignored -> {
            if (!beginSession.equals(token)) return;
            final int[] remaining = {scopedCookies.size()};
            for (Map<String, Object> cookie : scopedCookies) {
                manager.setCookie("https://rajshaladarpan.rajasthan.gov.in/",
                        cookieHeader(cookie),
                        accepted -> {
                            if (!beginSession.equals(token)) return;
                            if (!accepted) { fail("SESSION_EXPIRED", "School session cookies could not be installed."); close(); return; }
                            if (--remaining[0] == 0) {
                                page = create(false);
                                complete(token);
                            }
                        });
            }
        });
    }

    private static boolean validCookie(String name, String value) {
        return name != null && name.matches("[!#$%&'*+.^_`|~0-9A-Za-z-]+")
                && value != null && !value.matches("(?s).*[;\\r\\n].*");
    }

    private static String cookieHeader(Map<String, Object> cookie) {
        String header = cookie.get("name") + "=" + cookie.get("value") + "; Path=" + cookie.get("path") + "; Secure";
        if (Boolean.TRUE.equals(cookie.get("httpOnly"))) header += "; HttpOnly";
        Object sameSite = cookie.get("sameSite");
        if (sameSite != null && ("Lax".equals(sameSite) || "Strict".equals(sameSite) || "None".equals(sameSite)))
            header += "; SameSite=" + sameSite;
        // Dart's persisted jar uses epoch seconds (or no expires for session cookies).
        Object expires = cookie.get("expires");
        if (expires instanceof Number && ((Number) expires).longValue() > 0) {
            java.text.SimpleDateFormat format = new java.text.SimpleDateFormat("EEE, dd MMM yyyy HH:mm:ss 'GMT'", java.util.Locale.US);
            format.setTimeZone(java.util.TimeZone.getTimeZone("GMT"));
            header += "; Expires=" + format.format(new java.util.Date(Math.round(((Number) expires).doubleValue() * 1000)));
        }
        return header;
    }

    private List<Map<String, Object>> exportStaffCookies() {
        Map<String, Map<String, Object>> collected = new LinkedHashMap<>();
        CookieManager manager = CookieManager.getInstance();
        // CookieInfo supplies Path/Domain for both new and rotated cookies;
        // never flatten duplicate names from separate Staff paths.
        for (String url : cookieUrls) {
            for (String info : CookieManagerCompat.getCookieInfo(manager, url)) {
                String[] parts = info.split(";");
                int split = parts[0].indexOf('=');
                if (split < 1) continue;
                Map<String, Object> cookie = new HashMap<>();
                cookie.put("name", parts[0].substring(0, split).trim());
                cookie.put("value", parts[0].substring(split + 1).trim());
                cookie.put("domain", "rajshaladarpan.rajasthan.gov.in");
                String defaultPath = Uri.parse(url).getPath();
                int slash = defaultPath == null ? -1 : defaultPath.lastIndexOf('/');
                cookie.put("path", slash <= 0 ? "/" : defaultPath.substring(0, slash));
                for (int i = 1; i < parts.length; i++) {
                    int equals = parts[i].indexOf('=');
                    if (equals < 1) continue;
                    String key = parts[i].substring(0, equals).trim();
                    String value = parts[i].substring(equals + 1).trim();
                    if (key.equalsIgnoreCase("domain")) cookie.put("domain", value.replaceFirst("^\\.", "").toLowerCase(java.util.Locale.ROOT));
                    if (key.equalsIgnoreCase("path")) cookie.put("path", value);
                }
                if (!"rajshaladarpan.rajasthan.gov.in".equals(cookie.get("domain"))) continue;
                collected.put(cookie.get("name") + "\n" + cookie.get("domain") + "\n" + cookie.get("path"), cookie);
            }
        }
        return new ArrayList<>(collected.values());
    }

    private WebView create(boolean child) {
        WebView view = new WebView(activity);
        views.add(view);
        WebSettings settings = view.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setSupportMultipleWindows(true);
        settings.setJavaScriptCanOpenWindowsAutomatically(true);
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(false);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        // Playwright's viewport dimensions are CSS pixels, not Android pixels.
        // The original print popup has no dependable mobile viewport metadata.
        // Give it the source desktop width rather than WebView's mobile/980px fallback.
        settings.setUseWideViewPort(!child);
        settings.setLoadWithOverviewMode(true);
        settings.setTextZoom(100);
        if (child) {
            // Restore Chromium's common-script standard-family preference.
            // Blink WebPreferences initializes it to Times New Roman; Android
            // AwSettings otherwise overwrites it with sans-serif. CallPrint's
            // original unstyled document therefore inherits a different default
            // even though its HTML and print media are unchanged.
            // This is a browser preference, not injected report CSS/@font-face.
            // Explicit portal families still win; platform font resolution is
            // unchanged. Do not install desktop font files or rebuild the popup.
            // Source: third_party/blink/common/web_preferences/web_preferences.cc
            settings.setStandardFontFamily("Times New Roman");
        }
        settings.setCacheMode(WebSettings.LOAD_NO_CACHE);
        settings.setUserAgentString("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36");
        CookieManager.getInstance().setAcceptThirdPartyCookies(view, false);
        int width = cssPixels(child ? 1280 : 1366);
        int height = cssPixels(child ? 900 : 768);
        container.addView(view, new FrameLayout.LayoutParams(width, height));
        view.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY));
        view.layout(0, 0, width, height);
        view.setWebViewClient(new WebViewClient() {
            @Override public boolean shouldOverrideUrlLoading(WebView v, WebResourceRequest request) {
                if (allowed(request.getUrl())) return false;
                if (request.isForMainFrame()) pageFailure = "Portal navigation left the authenticated school portal.";
                return true;
            }
            @Override public WebResourceResponse shouldInterceptRequest(WebView v, WebResourceRequest request) {
                Uri uri = request.getUrl();
                if (!"https".equalsIgnoreCase(uri.getScheme()) && !"data".equalsIgnoreCase(uri.getScheme())
                        && !"about".equalsIgnoreCase(uri.getScheme())) {
                    return new WebResourceResponse("text/plain", "UTF-8", new ByteArrayInputStream(new byte[0]));
                }
                if (!child && request.isForMainFrame() && "POST".equals(request.getMethod())) mainPosts++;
                return null;
            }
            @Override public void onPageStarted(WebView v, String url, Bitmap icon) {
                if (!child) pageLoading = true;
            }
            @Override public void onPageFinished(WebView v, String url) {
                if (staff && allowed(Uri.parse(url)) && url.startsWith("https://")) cookieUrls.add(url);
                if (!child) {
                    pageLoading = false; loads++;
                    if (expectedFullPost >= 0 && mainPosts > expectedFullPost) {
                        v.evaluateJavascript("window.__rajFullPost = true", null);
                    }
                }
            }
            @Override public void onReceivedError(WebView v, WebResourceRequest request, WebResourceError error) {
                if (request.isForMainFrame()) pageFailure = "The school portal page could not be loaded.";
            }
            @Override public void onReceivedHttpError(WebView v, WebResourceRequest request, WebResourceResponse response) {
                if (request.isForMainFrame() && response.getStatusCode() >= 400) pageFailure = "The school portal page is unavailable.";
            }
        });
        view.setWebChromeClient(new WebChromeClient() {
            @Override public boolean onConsoleMessage(ConsoleMessage message) {
                // Only numeric readiness and fixed lifecycle labels are logged.
                // Never forward arbitrary portal console text or document data.
                String prefix = "__rajPrintLifecycle:";
                if (!child || !message.message().startsWith(prefix)) return false;
                try {
                    JSONObject state = new JSONObject(message.message().substring(prefix.length()));
                    String event = state.getString("event");
                    if (!event.matches("beforeprint|afterprint|media-change|fonts-loading|fonts-loaded")) return false;
                    JSONObject safe = new JSONObject();
                    safe.put("event", event);
                    safe.put("printMedia", state.getBoolean("printMedia"));
                    String fonts = state.getString("fonts");
                    safe.put("fonts", fonts.matches("loading|loaded|unavailable") ? fonts : "unavailable");
                    safe.put("pendingImages", Math.max(0, state.getInt("pendingImages")));
                    safe.put("brokenImages", Math.max(0, state.getInt("brokenImages")));
                    Log.i("RajshalaNativePrint", "print lifecycle: " + safe);
                } catch (Exception ignored) { }
                return true;
            }
            @Override public boolean onCreateWindow(WebView v, boolean dialog, boolean gesture, Message message) {
                if (child || popup != null) return false;
                popup = create(true);
                WebView.WebViewTransport transport = (WebView.WebViewTransport) message.obj;
                transport.setWebView(popup); message.sendToTarget(); return true;
            }
            @Override public boolean onJsAlert(WebView v, String url, String message, JsResult result) {
                portalMessage = message; result.confirm(); return true;
            }
            @Override public boolean onJsConfirm(WebView v, String url, String message, JsResult result) {
                // No print/read flow is allowed to accept a mutation confirmation.
                portalMessage = message; result.cancel(); return true;
            }
        });
        return view;
    }

    private int cssPixels(int pixels) {
        return Math.round(pixels * activity.getResources().getDisplayMetrics().density);
    }

    private static boolean allowed(Uri uri) {
        return "about".equalsIgnoreCase(uri.getScheme()) || ("https".equalsIgnoreCase(uri.getScheme())
                && "rajshaladarpan.rajasthan.gov.in".equalsIgnoreCase(uri.getHost())
                && (uri.getPort() == -1 || uri.getPort() == 443));
    }

    private void postback(MethodCall call) {
        String script = call.argument("script");
        String grid = call.argument("grid");
        expectedFullPost = mainPosts;
        String instrumentation = "(() => { window.__rajPrintPost = null; window.__rajFullPost = false; if (!window.__rajPrintXHR) {"
                + "window.__rajPrintXHR = true; const open=XMLHttpRequest.prototype.open, send=XMLHttpRequest.prototype.send;"
                + "XMLHttpRequest.prototype.open=function(m,u,...a){this.__rajMethod=m;this.__rajPath=new URL(u,location.href).pathname.toLowerCase();return open.call(this,m,u,...a)};"
                + "XMLHttpRequest.prototype.send=function(...a){if(String(this.__rajMethod).toUpperCase()==='POST' && this.__rajPath===location.pathname.toLowerCase())"
                + "this.addEventListener('loadend',()=>{window.__rajPrintPost={status:this.status,text:this.responseText}}, {once:true});"
                + "return send.apply(this,a)};} return true;})()";
        evaluate(page, instrumentation, ignored -> {
            // Full WebForms navigation can discard the click's JS callback.
            // Observe the original POST independently; never dispatch again.
            evaluate(page, script, value -> { });
            String check = "(() => { const p=window.__rajPrintPost; if(p && p.status>=400) throw new Error('Portal postback failed');"
                    + "const settled=!window.Sys || !Sys.WebForms || !Sys.WebForms.PageRequestManager.getInstance().get_isInAsyncPostBack();"
                    + "const grid=" + (grid == null ? "null" : JSONObject.quote(grid)) + ";"
                    + "if(grid && ((p && p.status===200 && !p.text.includes(grid)) || (!p && window.__rajFullPost===true && !document.getElementById(grid))))"
                    + "throw new Error('The portal did not return a fresh student profile table.');"
                    + "return document.readyState!=='loading' && settled && "
                    + "(p ? p.status===200 && (!grid || p.text.includes(grid)) : "
                    + "window.__rajFullPost===true && (!grid || !!document.getElementById(grid)));})()";
            poll(page, check, 30000, () -> !pageLoading, () -> {
                expectedFullPost = -1;
                complete(null);
            });
        });
    }

    private interface Value { void accept(Object value); }
    private interface Ready { boolean ready(); }
    private void evaluate(WebView view, String expression, Value callback) {
        if (pending == null) return;
        final String requestSession = token;
        final MethodChannel.Result operation = pending;
        String script = "(() => {try {const body=document.body?.innerText || '';"
                + "if(/Object reference not set to an instance|Server Error in|Runtime Error/.test(body))return {__rajError:body.slice(0,800)};"
                + "return (" + expression + ");} catch(e){return {__rajError:String(e.message||e)}}})()";
        view.evaluateJavascript(script, encoded -> {
            if (pending != operation || !requestSession.equals(token)) return;
            try {
                Object value = new JSONTokener(encoded).nextValue();
                if (value instanceof JSONObject && ((JSONObject)value).has("__rajError")) {
                    fail("PAGE_NOT_READY", ((JSONObject)value).getString("__rajError")); return;
                }
                if (portalMessage != null) { fail("PORTAL_MESSAGE", portalMessage); return; }
                if (pageFailure != null) { fail("PAGE_NOT_READY", pageFailure); return; }
                // Return JSON, not org.json containers, through StandardMessageCodec.
                if (value == JSONObject.NULL) callback.accept(null);
                else if (value instanceof JSONObject || value instanceof org.json.JSONArray) callback.accept(encoded);
                else callback.accept(value);
            } catch (Exception e) { fail("PAGE_NOT_READY", "Portal script result was invalid."); }
        });
    }

    private void poll(WebView view, String expression, int timeoutMs, Ready ready, Runnable done) {
        final long deadline = android.os.SystemClock.uptimeMillis() + timeoutMs;
        final MethodChannel.Result operation = pending;
        polling = new Runnable() {
            @Override public void run() {
                if (pending != operation) return;
                if (portalMessage != null) { fail("PORTAL_MESSAGE", portalMessage); return; }
                if (android.os.SystemClock.uptimeMillis() >= deadline) {
                    fail("PORTAL_SLOW", "The native portal operation timed out."); return;
                }
                if (!ready.ready()) { handler.postDelayed(this, 100); return; }
                evaluate(view, expression, value -> {
                    if (Boolean.TRUE.equals(value)) { polling = null; done.run(); }
                    else if (pending != null) handler.postDelayed(this, 100);
                });
            }
        };
        handler.post(polling);
    }

    private void render(int marginMm) throws Exception {
        if (popup == null) { fail("PAGE_NOT_READY", "Portal print popup is unavailable."); return; }
        String session = token;
        File file = File.createTempFile("rajshala-native-", ".pdf", activity.getCacheDir());
        capture = new RajshalaPrintCapture(popup, file, new RajshalaPrintCapture.Completion() {
            @Override public void success(File completed) {
                capture = null;
                if (!session.equals(token)) { completed.delete(); return; }
                String id = UUID.randomUUID().toString(); pdfs.put(id, completed); complete(id);
            }
            @Override public void error(String code, String message) {
                if (!session.equals(token)) return;
                capture = null; fail(code, message);
            }
        }, marginMm);
        final RajshalaPrintCapture rendering = capture;
        final WebView document = popup;
        final java.util.concurrent.atomic.AtomicBoolean started = new java.util.concurrent.atomic.AtomicBoolean();
        Runnable start = () -> {
            if (!started.compareAndSet(false, true)) return;
            if (document == popup && session.equals(token) && capture == rendering) rendering.start();
        };
        // Install observations before printing. A lost JS callback must never
        // prevent export; the existing PDF operation deadline still applies.
        Runnable fallback = () -> {
            Log.i("RajshalaNativePrint", "print lifecycle observer callback unavailable");
            start.run();
        };
        handler.postDelayed(fallback, 1500);
        tracePrintPopup(marginMm, () -> { handler.removeCallbacks(fallback); start.run(); });
    }

    /** Read-only evidence for native-print parity. Never log report text, IDs,
     * cookies or asset URLs, and never change the portal's document/styles. */
    private void tracePrintPopup(int marginMm, Runnable ready) {
        WebView document = popup;
        String session = token;
        WebSettings settings = document.getSettings();
        Log.i("RajshalaNativePrint", "capture boundary: portal=" + (staff ? "staff" : "school")
                + ", marginMm=" + marginMm
                + ", viewportPx=" + document.getWidth() + "x" + document.getHeight()
                + ", density=" + activity.getResources().getDisplayMetrics().density
                + ", standardFamily=" + settings.getStandardFontFamily()
                + ", serifFamily=" + settings.getSerifFontFamily()
                + ", layout=" + settings.getLayoutAlgorithm()
                + ", minimumFontSize=" + settings.getMinimumFontSize()
                + ", minimumLogicalFontSize=" + settings.getMinimumLogicalFontSize()
                + ", textZoom=" + settings.getTextZoom());
        String observation = "(() => {try {"
                + "if(!window.__rajPrintLifecycleInstalled){window.__rajPrintLifecycleInstalled=true;"
                + "const media=matchMedia('print');let count=0;"
                + "const record=event=>{if(count++>=12)return;const images=Array.from(document.images);"
                + "console.info('__rajPrintLifecycle:'+JSON.stringify({event,printMedia:media.matches,"
                + "fonts:document.fonts?document.fonts.status:'unavailable',"
                + "pendingImages:images.filter(i=>!i.complete).length,"
                + "brokenImages:images.filter(i=>i.complete&&(!i.naturalWidth||!i.naturalHeight)).length}));};"
                + "addEventListener('beforeprint',()=>record('beforeprint'));"
                + "addEventListener('afterprint',()=>record('afterprint'));"
                + "media.addEventListener('change',()=>record('media-change'));"
                + "if(document.fonts){document.fonts.addEventListener('loading',()=>record('fonts-loading'));"
                + "document.fonts.addEventListener('loadingdone',()=>record('fonts-loaded'));}}"
                + "const families=new Set();const elements=document.body?document.body.querySelectorAll('*'):[];"
                + "for(let n=0;n<elements.length&&n<2000;n++){"
                + "const e=elements[n];if(/^(SCRIPT|STYLE|INPUT|TEXTAREA|SELECT)$/.test(e.tagName))continue;"
                + "const s=getComputedStyle(e);if(s.display!=='none'&&s.visibility!=='hidden'&&e.getClientRects().length)families.add(s.fontFamily);}"
                + "const images=Array.from(document.images);"
                + "return {readyState:document.readyState,printMedia:matchMedia('print').matches,"
                + "viewport:{width:innerWidth,height:innerHeight},"
                + "fontStatus:document.fonts?document.fonts.status:'unavailable',"
                + "declaredFamilies:Array.from(families).slice(0,20),"
                + "fontFaces:document.fonts?Array.from(document.fonts).slice(0,20).map(f=>({family:f.family,status:f.status})):[],"
                + "stylesheets:document.styleSheets.length,"
                + "images:{total:images.length,pending:images.filter(i=>!i.complete).length,"
                + "broken:images.filter(i=>i.complete&&(!i.naturalWidth||!i.naturalHeight)).length}};"
                + "}catch(e){return {observationFailed:true};}})()";
        try {
            document.evaluateJavascript(observation, value -> {
                if (document == popup && session.equals(token))
                    Log.i("RajshalaNativePrint", "original popup at PDF export: " + value);
                ready.run();
            });
        } catch (RuntimeException ignored) {
            // Observations must not turn a working print into a failure.
            ready.run();
        }
    }

    private void merge(MethodCall call) {
        List<String> ids = call.argument("ids");
        if (ids == null || ids.isEmpty()) { fail("NO_STUDENT_TABLE", "The portal produced no printable pages."); return; }
        List<File> sources = new ArrayList<>();
        for (String id : ids) {
            File file = pdfs.get(id);
            if (file == null) { fail("SESSION_CHANGED", "Portal PDF pages are no longer available."); return; }
            sources.add(file);
        }
        String session = token;
        files.execute(() -> {
            File combined = null;
            try {
                PDFBoxResourceLoader.init(activity.getApplicationContext());
                int expected = 0;
                for (File file : sources) {
                    try (PDDocument document = PDDocument.load(file)) { expected += document.getNumberOfPages(); }
                }
                if (expected == 0) throw new IllegalStateException("No PDF pages");
                combined = File.createTempFile("rajshala-merged-", ".pdf", activity.getCacheDir());
                PDFMergerUtility merger = new PDFMergerUtility();
                for (File file : sources) merger.addSource(file);
                merger.setDestinationFileName(combined.getAbsolutePath());
                merger.mergeDocuments(MemoryUsageSetting.setupTempFileOnly());
                ByteArrayOutputStream output = new ByteArrayOutputStream();
                try (FileInputStream input = new FileInputStream(combined)) {
                    byte[] buffer = new byte[16384]; int read;
                    while ((read = input.read(buffer)) != -1) output.write(buffer, 0, read);
                }
                byte[] bytes = output.toByteArray();
                try (PDDocument document = PDDocument.load(bytes)) {
                    if (document.getNumberOfPages() != expected) throw new IllegalStateException("PDF page count mismatch");
                }
                if (bytes.length < 5 || bytes[0] != '%' || bytes[1] != 'P' || bytes[2] != 'D' || bytes[3] != 'F' || bytes[4] != '-') {
                    throw new IllegalStateException("Invalid PDF");
                }
                handler.post(() -> { if (session.equals(token)) complete(bytes); });
            } catch (Exception e) {
                handler.post(() -> { if (session.equals(token)) fail("NATIVE_PRINT_FAILED", "Could not assemble the portal PDF pages."); });
            } finally { if (combined != null) combined.delete(); }
        });
    }

    private void complete(Object value) {
        MethodChannel.Result result = pending; pending = null;
        if (operationTimeout != null) { handler.removeCallbacks(operationTimeout); operationTimeout = null; }
        if (polling != null) { handler.removeCallbacks(polling); polling = null; }
        if (result != null) result.success(value);
    }
    private void fail(String code, String message) {
        MethodChannel.Result result = pending; pending = null;
        if (operationTimeout != null) { handler.removeCallbacks(operationTimeout); operationTimeout = null; }
        if (polling != null) { handler.removeCallbacks(polling); polling = null; }
        if (result != null) result.error(code, message, null);
    }
    private void destroyPopup() {
        if (popup == null) return;
        container.removeView(popup); views.remove(popup);
        popup.stopLoading(); popup.destroy(); popup = null;
    }
    private void close() {
        fail("SESSION_CHANGED", "The native print session was closed.");
        token = null;
        if (capture != null) { capture.cancel(); capture = null; }
        for (WebView view : views) { view.stopLoading(); view.destroy(); }
        views.clear(); page = null; popup = null;
        if (container != null && container.getParent() instanceof ViewGroup) ((ViewGroup)container.getParent()).removeView(container);
        container = null;
        for (File file : pdfs.values()) file.delete();
        pdfs.clear(); scopedCookies.clear(); cookieUrls.clear(); CookieManager.getInstance().removeAllCookies(null);
    }
    public void dispose() { close(); channel.setMethodCallHandler(null); files.shutdown(); }
}
