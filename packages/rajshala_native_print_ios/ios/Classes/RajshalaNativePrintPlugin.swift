import Flutter
import UIKit
import WebKit
import PDFKit

/// Implements the existing Android channel contract. Portal JavaScript builds
/// the popup; WKWebView's print formatter renders that same live document.
public final class RajshalaNativePrintPlugin: NSObject, FlutterPlugin, WKNavigationDelegate, WKUIDelegate {
    private weak var controller: UIViewController?
    private var token: String?
    private var base = ""
    private var staff = false
    private var dataStore: WKWebsiteDataStore?
    private var container: UIView?
    private var page: WKWebView?
    private var popup: WKWebView?
    private var pdfs: [String: Data] = [:]
    private var pending: FlutterResult?
    private var operation = UUID()
    private var deadline: DispatchWorkItem?
    private var portalMessage: String?
    private var pageFailure: String?
    private var loads = 0
    private var mainPosts = 0
    private var expectedFullPost: Int?
    private var setupStarted = Date()
    private static let host = "rajshaladarpan.rajasthan.gov.in"

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = RajshalaNativePrintPlugin()
        // View controller resolved dynamically at print time
        let channel = FlutterMethodChannel(name: "rajshala/native_portal_print", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.handle(call, result: result) }
            return
        }
        let args = call.arguments as? [String: Any] ?? [:]
        if call.method == "begin" {
            guard token == nil else {
                result(error("NATIVE_PRINT_BUSY", "A native print is already running.")); return
            }
            begin(args, result: result); return
        }
        guard let current = token, args["token"] as? String == current else {
            result(error("SESSION_CHANGED", "Native print session changed.")); return
        }
        if call.method == "close" {
            close(); result(nil); return
        }
        if call.method == "abort" {
            finishError("SESSION_CHANGED", "The print operation was cancelled.")
            page?.stopLoading(); popup?.stopLoading(); result(nil); return
        }
        guard pending == nil else {
            result(error("NATIVE_PRINT_BUSY", "A native browser operation is still running.")); return
        }
        let timeout: TimeInterval
        switch call.method {
        case "merge": timeout = 600
        case "pdf": timeout = 65
        case "postback": timeout = 60
        case "navigate":
            if staff && args["path"] as? String == "Home/Staff/StaffHome.aspx" {
                timeout = max(0.001, min(15, 25 - Date().timeIntervalSince(setupStarted)))
            } else if staff && args["path"] as? String == "Home/Staff/Staff_P10_DetailsV2.aspx" {
                timeout = 20
            } else { timeout = staff ? 30 : 45 }
        case "popup": timeout = 20
        default: timeout = 15
        }
        start(result, timeout: timeout)
        switch call.method {
        case "navigate": navigate(args)
        case "evaluate":
            let view = (args["popup"] as? Bool == true) ? popup : page
            guard let script = args["script"] as? String, let view = view else {
                finishError("PAGE_NOT_READY", "Portal print popup is unavailable."); return
            }
            evaluate(view, script) { self.finish($0) }
        case "postback": postback(args)
        case "popup":
            destroyPopup()
            guard let view = page, let script = args["script"] as? String else {
                finishError("PAGE_NOT_READY", "Portal print page is unavailable."); return
            }
            // The original click is sent once. Poll independently if navigation
            // discards WebKit's JavaScript completion callback.
            evaluate(view, script) { _ in }
            poll(view, "true", timeout: 10, ready: { self.popup != nil }) { self.finish(nil) }
        case "pdf":
            let margin = (args["marginMm"] as? NSNumber)?.intValue ?? 10
            guard margin == 10 || (staff && margin == 5) else {
                finishError("PAGE_NOT_READY", "Unsupported portal print margin."); return
            }
            render(margin: margin)
        case "staffCookies": exportStaffCookies()
        case "merge": merge(args)
        case "closePopup": destroyPopup(); finish(nil)
        default: finish(FlutterMethodNotImplemented)
        }
    }

    private func error(_ code: String, _ message: String) -> FlutterError {
        FlutterError(code: code, message: message, details: nil)
    }
    private func start(_ result: @escaping FlutterResult, timeout: TimeInterval, closeOnTimeout: Bool = false) {
        pending = result
        operation = UUID()
        let id = operation
        let session = token
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.operation == id, self.token == session, self.pending != nil else { return }
            self.finishError(self.portalMessage == nil ? "PORTAL_SLOW" : "PORTAL_MESSAGE",
                             self.portalMessage ?? "The native portal operation timed out.")
            if closeOnTimeout { self.close() }
        }
        deadline = work
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)
    }
    private func finish(_ value: Any?) {
        let result = pending
        pending = nil
        deadline?.cancel(); deadline = nil
        expectedFullPost = nil
        result?(value)
    }
    private func finishError(_ code: String, _ message: String) { finish(error(code, message)) }

    private func begin(_ args: [String: Any], result: @escaping FlutterResult) {
        guard let requested = args["base"] as? String,
              requested.range(of: "^https://rajshaladarpan\\.rajasthan\\.gov\\.in/SD[1-5]$", options: [.regularExpression, .caseInsensitive]) != nil,
              let rootView = (controller?.view ?? UIApplication.shared.connectedScenes
                  .compactMap { $0 as? UIWindowScene }
                  .flatMap { $0.windows }
                  .first(where: { $0.isKeyWindow })?.rootViewController?.view ?? UIApplication.shared.connectedScenes
                  .compactMap { $0 as? UIWindowScene }
                  .flatMap { $0.windows }
                  .first?.rootViewController?.view) else {
            result(error("SESSION_EXPIRED", "A verified portal session is required.")); return
        }
        let isStaff = args["portal"] as? String == "staff"
        var rows: [[String: Any]] = []
        if isStaff { rows = args["scopedCookies"] as? [[String: Any]] ?? [] }
        else if let values = args["cookies"] as? [String: String] {
            rows = values.map { ["name": $0.key, "value": $0.value, "domain": Self.host, "path": "/", "httpOnly": true] }
        }
        guard !rows.isEmpty else {
            result(error("SESSION_EXPIRED", "A verified portal session is required.")); return
        }
        var cookies: [HTTPCookie] = []
        for row in rows {
            guard let name = row["name"] as? String, let value = row["value"] as? String,
                  let domain = row["domain"] as? String, let path = row["path"] as? String,
                  domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased() == Self.host,
                  name.range(of: "^[!#$%&'*+.^_`|~0-9A-Za-z-]+$", options: .regularExpression) != nil,
                  value.rangeOfCharacter(from: CharacterSet(charactersIn: ";\r\n")) == nil,
                  path.hasPrefix("/"), path.rangeOfCharacter(from: CharacterSet(charactersIn: ";\r\n?#")) == nil else {
                result(error("SESSION_EXPIRED", "Portal session cookies are invalid.")); return
            }
            var properties: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .domain: domain, .path: path, .secure: "TRUE"]
            if row["httpOnly"] as? Bool == true { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
            if let expiry = row["expires"] as? NSNumber, expiry.doubleValue > 0 { properties[.expires] = Date(timeIntervalSince1970: expiry.doubleValue) }
            if let sameSite = row["sameSite"] as? String, ["Lax", "Strict", "None"].contains(sameSite) {
                properties[HTTPCookiePropertyKey("SameSite")] = sameSite
            }
            guard let cookie = HTTPCookie(properties: properties) else {
                result(error("SESSION_EXPIRED", "Portal session cookies could not be installed.")); return
            }
            cookies.append(cookie)
        }
        token = UUID().uuidString; base = requested; staff = isStaff
        portalMessage = nil; pageFailure = nil; setupStarted = Date(); loads = 0; mainPosts = 0
        let store = WKWebsiteDataStore.nonPersistent()
        dataStore = store
        let holder = UIView(frame: CGRect(x: -10000, y: 0, width: 1366, height: 900))
        holder.isUserInteractionEnabled = false
        rootView.addSubview(holder); container = holder
        start(result, timeout: isStaff ? 25 : 30, closeOnTimeout: true)
        let session = token
        let id = operation
        let group = DispatchGroup()
        for cookie in cookies {
            group.enter()
            store.httpCookieStore.setCookie(cookie) { group.leave() }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self = self, self.token == session, self.operation == id, self.pending != nil else { return }
            self.page = self.create(child: false)
            self.finish(self.token)
        }
    }

    private func create(child: Bool, supplied: WKWebViewConfiguration? = nil) -> WKWebView {
        let configuration = supplied ?? WKWebViewConfiguration()
        if let store = dataStore { configuration.websiteDataStore = store }
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: child ? 1280 : 1366, height: 900), configuration: configuration)
        view.navigationDelegate = self; view.uiDelegate = self
        view.scrollView.isScrollEnabled = false
        // Keep the original document and browser font settings. No viewport,
        // report fragment, font, CSS, header or footer is injected.
        container?.addSubview(view)
        return view
    }
    private func allowed(_ url: URL) -> Bool {
        url.scheme == "about" || (url.scheme?.lowercased() == "https" && url.host?.lowercased() == Self.host && (url.port == nil || url.port == 443))
    }
    private func navigate(_ args: [String: Any]) {
        let destinations = staff ? ["Home/Staff/StaffHome.aspx", "Home/Staff/Staff_P10_DetailsV2.aspx", "Home/Staff/Staff_LeaveApplication_Applied.aspx"] : ["Home/School/SchoolStudentProfiles_New.aspx", "Home/School/RMSA_Student_SchoolCertificate.aspx"]
        guard let path = args["path"] as? String, destinations.contains(path), let url = URL(string: base + "/" + path), let view = page else {
            finishError("PAGE_NOT_READY", "Native print destination blocked."); return
        }
        portalMessage = nil; pageFailure = nil
        let previous = loads
        view.load(URLRequest(url: url))
        poll(view, Self.settled, timeout: 30, ready: { self.loads > previous && !view.isLoading }) { self.finish(nil) }
    }
    private static let settled = "document.readyState !== 'loading' && !!document.body && (!window.Sys || !Sys.WebForms || !Sys.WebForms.PageRequestManager.getInstance().get_isInAsyncPostBack())"

    private func evaluate(_ view: WKWebView, _ expression: String, completion: @escaping (Any?) -> Void) {
        let id = operation; let session = token
        let script = "(() => {try {const body=document.body?.innerText || '';if(/Object reference not set to an instance|Server Error in|Runtime Error/.test(body))return {__rajError:body.slice(0,800)}; return (\(expression));} catch(e){return {__rajError:String(e.message||e)}}})()"
        view.evaluateJavaScript(script) { [weak self] value, failure in
            guard let self = self, self.operation == id, self.token == session, self.pending != nil else { return }
            if let message = self.portalMessage { self.finishError("PORTAL_MESSAGE", message); return }
            if let message = self.pageFailure { self.finishError("PAGE_NOT_READY", message); return }
            if let row = value as? [String: Any], let message = row["__rajError"] as? String {
                self.finishError("PAGE_NOT_READY", message); return
            }
            if let failure = failure {
                // A full postback destroys its originating JavaScript context.
                // Independent navigation/polling owns completion; no replay.
                if (failure as NSError).code == WKError.Code.javaScriptResultTypeIsUnsupported.rawValue { completion(nil) }
                else if view.isLoading || self.expectedFullPost != nil { completion(false) }
                else { self.finishError("PAGE_NOT_READY", "Portal script could not be evaluated.") }
                return
            }
            completion(value is NSNull ? nil : value)
        }
    }
    private func poll(_ view: WKWebView, _ expression: String, timeout: TimeInterval, ready: @escaping () -> Bool = { true }, done: @escaping () -> Void) {
        let id = operation; let session = token; let until = Date().addingTimeInterval(timeout)
        func check() {
            guard self.pending != nil, self.operation == id, self.token == session else { return }
            if let message = self.portalMessage { self.finishError("PORTAL_MESSAGE", message); return }
            if let message = self.pageFailure { self.finishError("PAGE_NOT_READY", message); return }
            if Date() >= until { self.finishError("PORTAL_SLOW", "The native portal operation timed out."); return }
            if !ready() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: check); return
            }
            self.evaluate(view, expression) { value in
                if value as? Bool == true { done() }
                else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: check) }
            }
        }
        DispatchQueue.main.async(execute: check)
    }
    private func postback(_ args: [String: Any]) {
        guard let view = page, let script = args["script"] as? String else {
            finishError("PAGE_NOT_READY", "Portal print page is unavailable."); return
        }
        expectedFullPost = mainPosts
        let instrumentation = "(() => { window.__rajPrintPost=null; window.__rajFullPost=false; if(!window.__rajPrintXHR){window.__rajPrintXHR=true; const open=XMLHttpRequest.prototype.open,send=XMLHttpRequest.prototype.send; XMLHttpRequest.prototype.open=function(m,u,...a){this.__rajMethod=m;this.__rajPath=new URL(u,location.href).pathname.toLowerCase();return open.call(this,m,u,...a)}; XMLHttpRequest.prototype.send=function(...a){if(String(this.__rajMethod).toUpperCase()==='POST'&&this.__rajPath===location.pathname.toLowerCase())this.addEventListener('loadend',()=>{window.__rajPrintPost={status:this.status,text:this.responseText}},{once:true});return send.apply(this,a)};}return true;})()"
        evaluate(view, instrumentation) { _ in
            self.evaluate(view, script) { _ in }
            let grid = self.jsonLiteral(args["grid"] as? String)
            let check = "(() => {const p=window.__rajPrintPost;if(p&&p.status>=400)throw new Error('Portal postback failed');const settled=!window.Sys||!Sys.WebForms||!Sys.WebForms.PageRequestManager.getInstance().get_isInAsyncPostBack();const grid=\(grid);if(grid&&((p&&p.status===200&&!p.text.includes(grid))||(!p&&window.__rajFullPost===true&&!document.getElementById(grid))))throw new Error('The portal did not return a fresh student profile table.');return document.readyState!=='loading'&&settled&&(p?p.status===200&&(!grid||p.text.includes(grid)):window.__rajFullPost===true&&(!grid||!!document.getElementById(grid)));})()"
            self.poll(view, check, timeout: 30, ready: { !view.isLoading }) { self.finish(nil) }
        }
    }
    private func jsonLiteral(_ value: String?) -> String {
        guard let value = value, let data = try? JSONSerialization.data(withJSONObject: [value]), let encoded = String(data: data, encoding: .utf8) else { return "null" }
        return String(encoded.dropFirst().dropLast())
    }

    public func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url, allowed(url) else {
            if action.targetFrame?.isMainFrame == true { pageFailure = "Portal navigation left the authenticated portal." }
            decisionHandler(.cancel); return
        }
        if webView === page && action.targetFrame?.isMainFrame == true && action.request.httpMethod?.uppercased() == "POST" { mainPosts += 1 }
        decisionHandler(.allow)
    }
    public func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if response.isForMainFrame, let http = response.response as? HTTPURLResponse, http.statusCode >= 400 {
            pageFailure = "The portal page is unavailable."
        }
        decisionHandler(.allow)
    }
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView === page {
            loads += 1
            if let before = expectedFullPost, mainPosts > before {
                webView.evaluateJavaScript("window.__rajFullPost=true", completionHandler: nil)
            }
        }
    }
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError failure: Error) { navigationFailed(failure) }
    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError failure: Error) { navigationFailed(failure) }
    private func navigationFailed(_ failure: Error) {
        if (failure as NSError).code != NSURLErrorCancelled { pageFailure = "The portal page could not be loaded." }
    }
    public func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard webView === page, popup == nil else { return nil }
        let view = create(child: true, supplied: configuration)
        popup = view
        return view
    }
    public func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        portalMessage = message; completionHandler()
    }
    public func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        portalMessage = message; completionHandler(false)
    }
    public func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        completionHandler(nil)
    }
    public func webViewDidClose(_ webView: WKWebView) {
        // Portal window.close() during CallPrint must not discard the original
        // print document before Dart requests export. Explicit closePopup owns it.
    }

    private func render(margin: Int) {
        guard let view = popup else { finishError("PAGE_NOT_READY", "Portal print popup is unavailable."); return }
        let readiness = "document.readyState!=='loading' && (!document.fonts || document.fonts.status==='loaded') && Array.from(document.images).every(i=>i.complete && i.naturalWidth>0)"
        poll(view, readiness, timeout: 60) {
            let renderer = PortalPageRenderer(marginMm: margin)
            renderer.addPrintFormatter(view.viewPrintFormatter(), startingAtPageAt: 0)
            let count = renderer.numberOfPages
            guard count > 0, count <= 1000 else {
                self.finishError("PRINT_CAPTURE_FAILED", "Portal print did not return PDF pages."); return
            }
            renderer.prepare(forDrawingPages: NSRange(location: 0, length: count))
            let data = UIGraphicsPDFRenderer(bounds: renderer.paperRect).pdfData { context in
                for index in 0..<count {
                    context.beginPage()
                    renderer.drawPage(at: index, in: renderer.paperRect)
                }
            }
            guard let document = PDFDocument(data: data), document.pageCount == count else {
                self.finishError("PRINT_CAPTURE_FAILED", "Portal print did not return a valid PDF."); return
            }
            let id = UUID().uuidString
            self.pdfs[id] = data; self.finish(id)
        }
    }
    private func exportStaffCookies() {
        guard staff, let store = dataStore else { finishError("SESSION_CHANGED", "Staff browser session is unavailable."); return }
        let id = operation; let session = token
        store.httpCookieStore.getAllCookies { cookies in
            guard self.pending != nil, self.operation == id, self.token == session else { return }
            let rows: [[String: Any]] = cookies.filter { $0.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased() == Self.host }.map { cookie in
                var row: [String: Any] = ["name": cookie.name, "value": cookie.value, "domain": Self.host, "path": cookie.path, "secure": cookie.isSecure, "httpOnly": cookie.isHTTPOnly]
                if let expiry = cookie.expiresDate { row["expires"] = expiry.timeIntervalSince1970 }
                if let sameSite = cookie.properties?[HTTPCookiePropertyKey("SameSite")] as? String { row["sameSite"] = sameSite }
                return row
            }
            self.finish(rows)
        }
    }
    private func merge(_ args: [String: Any]) {
        guard let ids = args["ids"] as? [String], !ids.isEmpty else { finishError("PAGE_NOT_READY", "Portal print did not return a PDF."); return }
        let inputs = ids.compactMap { pdfs[$0] }
        guard inputs.count == ids.count else { finishError("SESSION_CHANGED", "Native PDF page is unavailable."); return }
        let id = operation; let session = token
        DispatchQueue.global(qos: .userInitiated).async {
            let output = PDFDocument()
            var valid = true
            for data in inputs {
                guard let source = PDFDocument(data: data), source.pageCount > 0 else { valid = false; break }
                for index in 0..<source.pageCount {
                    guard let page = source.page(at: index) else { valid = false; break }
                    output.insert(page, at: output.pageCount)
                }
            }
            let bytes = valid ? output.dataRepresentation() : nil
            DispatchQueue.main.async {
                guard self.pending != nil, self.operation == id, self.token == session else { return }
                guard let data = bytes, data.starts(with: Data("%PDF-".utf8)) else {
                    self.finishError("PRINT_CAPTURE_FAILED", "Portal PDF merge failed."); return
                }
                self.finish(FlutterStandardTypedData(bytes: data))
            }
        }
    }
    private func destroyPopup() {
        popup?.stopLoading(); popup?.navigationDelegate = nil; popup?.uiDelegate = nil
        popup?.removeFromSuperview(); popup = nil
    }
    private func close() {
        finishError("SESSION_CHANGED", "Native print session closed.")
        token = nil; operation = UUID()
        destroyPopup()
        page?.stopLoading(); page?.navigationDelegate = nil; page?.uiDelegate = nil
        page?.removeFromSuperview(); page = nil
        container?.removeFromSuperview(); container = nil
        dataStore = nil; pdfs.removeAll(); portalMessage = nil; pageFailure = nil
    }
}

/// Only source page geometry is supplied. WebKit owns all document rendering.
private final class PortalPageRenderer: UIPrintPageRenderer {
    private let sheet = CGRect(x: 0, y: 0, width: 210 * 72 / 25.4, height: 297 * 72 / 25.4)
    private let inset: CGFloat
    init(marginMm: Int) {
        inset = CGFloat(marginMm) * 72 / 25.4
        super.init()
    }
    override var paperRect: CGRect { sheet }
    override var printableRect: CGRect { sheet.insetBy(dx: inset, dy: inset) }
}