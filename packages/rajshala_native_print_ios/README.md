# Rajshala native portal printing on iOS

This local plugin registers `rajshala/native_portal_print` automatically on iOS. Existing School/Staff workers and their method signatures are shared with Android. Android keeps its existing Java bridge.

The bridge installs the current session cookies into a non-persistent WKWebsiteDataStore, retains the original window.open popup created by portal JavaScript, and passes that live WKWebView to Apple's viewPrintFormatter and UIPrintPageRenderer. A4 geometry and original 5/10 mm source margins are retained. It does not reconstruct HTML, inject report CSS/fonts, use snapshots, or forward PDFs to a server. PDFKit combines the generated pages without bitmap reconstruction. Actual iPhone visual parity remains unverified.

Full/AJAX postbacks are observed independently of the original click; no duplicate click is dispatched when the JavaScript callback is lost. Cookies retain distinct paths and duplicate names. Portal alert text remains the original message. JavaScript confirmations are declined. Native requests use session tokens and bounded deadlines; cleanup removes the isolated browser and temporary in-memory PDFs.

Requirements: iOS 15+, Flutter 3.47+/Dart 3.13+. The provided source project has no iOS Runner directory. On a Mac, create the standard platform scaffolding in the existing Flutter project with `flutter create --platforms=ios .`, set the Runner deployment target to 15.0 or higher, and retain your own signing/bundle ID. Then run `flutter pub get` and build normally. This plugin needs no custom AppDelegate registration when standard GeneratedPluginRegistrant is used.

Validation in the Linux workspace: Swift syntax parser, channel-contract and worker regression checks. Xcode SDK type checking, signing, build and actual WKWebView rendering were not available here. Do not treat these checks as an iOS compilation pass.
