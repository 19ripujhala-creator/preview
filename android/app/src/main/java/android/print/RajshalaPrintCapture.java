package android.print;

import android.os.Bundle;
import android.os.CancellationSignal;
import android.os.Handler;
import android.os.Looper;
import android.os.ParcelFileDescriptor;
import android.webkit.WebView;
import java.io.File;
import java.io.IOException;
import java.util.concurrent.atomic.AtomicBoolean;

/** Uses the original popup WebView's print adapter; does not create report HTML.
 * This package is required by the SDK's package-private callback constructors,
 * as with the existing printing plugin's Android PDF conversion helper. */
public final class RajshalaPrintCapture {
    public interface Completion {
        void success(File file);
        void error(String code, String message);
    }
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final AtomicBoolean finished = new AtomicBoolean(false);
    private final CancellationSignal cancellation = new CancellationSignal();
    private final PrintDocumentAdapter adapter;
    private final File destination;
    private final Completion callback;
    private final int marginMils;
    private ParcelFileDescriptor descriptor;
    private final Runnable timeout = () -> fail("PORTAL_SLOW", "Portal PDF rendering timed out.");

    public RajshalaPrintCapture(WebView popup, File destination, Completion callback) {
        this(popup, destination, callback, 10);
    }

    public RajshalaPrintCapture(WebView popup, File destination, Completion callback, int marginMm) {
        if (marginMm != 5 && marginMm != 10) throw new IllegalArgumentException("Unsupported portal margin");
        this.marginMils = marginMm == 5 ? 197 : 394;
        this.adapter = popup.createPrintDocumentAdapter("Rajshala portal native print");
        this.destination = destination;
        this.callback = callback;
    }

    public void start() {
        handler.postDelayed(timeout, 60000);
        // Source worker: A4, 10 mm on every side. 394 mils is Android's nearest
        // representation of 10 mm; browser headers/footers are not injected.
        PrintAttributes attributes = new PrintAttributes.Builder()
                .setMediaSize(PrintAttributes.MediaSize.ISO_A4)
                // PDF coordinates are points (72 per inch). Keep the export at
                // that resolution; these are vector pages, not 600-DPI bitmaps.
                .setResolution(new PrintAttributes.Resolution("portal", "Portal PDF", 72, 72))
                .setColorMode(PrintAttributes.COLOR_MODE_COLOR)
                .setMinMargins(new PrintAttributes.Margins(marginMils, marginMils, marginMils, marginMils)).build();
        try {
            adapter.onStart();
            adapter.onLayout(null, attributes, cancellation,
                    new PrintDocumentAdapter.LayoutResultCallback() {
                        @Override public void onLayoutFinished(PrintDocumentInfo info, boolean changed) {
                            handler.post(() -> write(info));
                        }
                        @Override public void onLayoutFailed(CharSequence error) {
                            handler.post(() -> fail("NATIVE_PRINT_FAILED", text(error)));
                        }
                        @Override public void onLayoutCancelled() {
                            handler.post(() -> fail("NATIVE_PRINT_FAILED", "Portal PDF layout was cancelled."));
                        }
                    }, new Bundle());
        } catch (Exception e) { fail("NATIVE_PRINT_FAILED", text(e.getMessage())); }
    }

    private void write(PrintDocumentInfo info) {
        if (finished.get()) return;
        if (info == null || info.getPageCount() == 0) {
            fail("PAGE_NOT_READY", "The portal print window produced no printable pages.");
            return;
        }
        try {
            descriptor = ParcelFileDescriptor.open(destination,
                    ParcelFileDescriptor.MODE_CREATE | ParcelFileDescriptor.MODE_TRUNCATE
                            | ParcelFileDescriptor.MODE_READ_WRITE);
            adapter.onWrite(new PageRange[]{PageRange.ALL_PAGES}, descriptor, cancellation,
                    new PrintDocumentAdapter.WriteResultCallback() {
                        @Override public void onWriteFinished(PageRange[] pages) {
                            handler.post(() -> succeed(pages));
                        }
                        @Override public void onWriteFailed(CharSequence error) {
                            handler.post(() -> fail("NATIVE_PRINT_FAILED", text(error)));
                        }
                        @Override public void onWriteCancelled() {
                            handler.post(() -> fail("NATIVE_PRINT_FAILED", "Portal PDF writing was cancelled."));
                        }
                    });
        } catch (Exception e) { fail("NATIVE_PRINT_FAILED", text(e.getMessage())); }
    }

    private void succeed(PageRange[] pages) {
        if (pages == null || pages.length == 0 || destination.length() < 5) {
            fail("PAGE_NOT_READY", "The portal print window did not produce a valid PDF.");
            return;
        }
        if (!finished.compareAndSet(false, true)) return;
        cleanup();
        callback.success(destination);
    }

    private void fail(String code, String message) {
        if (!finished.compareAndSet(false, true)) return;
        cancellation.cancel();
        cleanup();
        destination.delete();
        callback.error(code, message);
    }

    public void cancel() { fail("SESSION_CHANGED", "The native print session was closed."); }
    private void cleanup() {
        handler.removeCallbacks(timeout);
        if (descriptor != null) {
            try { descriptor.close(); } catch (IOException ignored) { }
            descriptor = null;
        }
        try { adapter.onFinish(); } catch (RuntimeException ignored) { }
    }
    private static String text(Object value) {
        return value == null ? "The portal PDF could not be rendered." : value.toString();
    }
}
