/// Complete native-browser equivalent of Staff format10_worker.py.
import 'dart:convert';

import '../../../core/direct/async_primitives.dart';
import '../../shaladarpan/direct/nic_catalog_worker.dart' show NicError;

import 'native_print_worker.dart';
import 'portal_state.dart';

const format10RequiredStrings = [
  'कार्मिक व्यक्तिगत विवरण प्रपत्र',
  'प्रपत्र - 10',
];
const format10PrintSelector =
    "#ContentPlaceHolder1_ucP10Print_ImageButton1, "
    "input[onclick*='dvReport'], input[onclick*='printdiv'], img[title='Print']";
bool format10PopupHasOfficialContent(String text) =>
    format10RequiredStrings.any(text.contains);

class Format10StageError extends StaffPortalError {
  const Format10StageError(super.code, super.message, this.stage);
  final String stage;
}

class Format10Worker extends StaffNativePrintWorker {
  Format10Worker({required super.browser, required super.check});

  String _quoted(String value) => jsonEncode(value);
  String _clickSelector(String selector, String message) =>
      '''(() => {
    const el=document.querySelector(${jsonEncode(selector)});
    if(!el) throw new Error('The official portal control is unavailable.');
    if(el.disabled || el.matches(':disabled')) throw new Error(${jsonEncode(message)});
    el.click(); return true;
  })()''';

  Future<Map<String, dynamic>> generate({String? nicId}) async {
    var stage = 'open_profile';
    try {
      // Python nic_id is informational; it must not replace the logged-in profile.
      await browser.navigate('Home/Staff/Staff_P10_DetailsV2.aspx');
      await requireDocument(
        'the Format-10 page',
        path: 'Staff_P10_DetailsV2.aspx',
      );
      await protectPopup();
      stage = 'open_view_lock_tab';
      const tabSelector =
          '#ContentPlaceHolder1_ImageButton18, #ContentPlaceHolder1_divViewLockProfile input';
      if (await evaluate("!!document.querySelector('$tabSelector')") == true) {
        await browser.postback(
          _clickSelector(tabSelector, 'View and Lock tab is disabled.'),
        );
        await waitFor(
          '''(() => {
        const el=document.querySelector("$format10PrintSelector");
        return !!(el && el.getClientRects().length);
      })()''',
          const Duration(seconds: 10),
          'The official print control did not appear after opening View and Lock.',
        );
      }
      // Python prefers the exact ID before checking fallback controls.
      const primary = '#ContentPlaceHolder1_ucP10Print_ImageButton1';
      const fallback =
          "input[onclick*='dvReport'], input[onclick*='printdiv'], img[title='Print']";
      final selector =
          await evaluate("!!document.querySelector('$primary')") == true
          ? primary
          : fallback;
      if (await evaluate('!!document.querySelector(${_quoted(selector)})') !=
          true) {
        throw const StaffPortalError(
          'PAGE_NOT_READY',
          'The official Format-10 print icon is unavailable on View and Lock.',
        );
      }
      stage = 'capture_native_popup';
      await browser.openPopup(
        _clickSelector(selector, 'Format-10 print control is disabled.'),
      );
      try {
        await optionalWait(
          "document.readyState === 'complete'",
          const Duration(seconds: 8),
          popup: true,
        );
        stage = 'validate_native_content';
        final watch = Stopwatch()..start();
        var valid = false;
        while (watch.elapsed <= const Duration(seconds: 8)) {
          if (format10PopupHasOfficialContent(
            (await document(popup: true)).text,
          )) {
            valid = true;
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }
        if (!valid) {
          throw const StaffPortalError(
            'PRINT_CAPTURE_FAILED',
            "Captured popup is missing the expected official Format-10 text ('कार्मिक व्यक्तिगत विवरण प्रपत्र', 'प्रपत्र - 10') after waiting 8000ms — refusing to generate a PDF from unverified/possibly blank content.",
          );
        }
        stage = 'render_pdf';
        await optionalWait(
          "!document.fonts || document.fonts.status === 'loaded'",
          const Duration(seconds: 6),
          popup: true,
        );
        return result(await capture(5), 'format10.pdf');
      } finally {
        try {
          await browser.closePopup();
        } catch (_) {}
      }
    } on OperationCancelled {
      rethrow;
    } on StaffPortalError catch (e) {
      throw Format10StageError(e.code, e.message, stage);
    } on NicError catch (e) {
      throw Format10StageError(
        e.code == 'PORTAL_SLOW' ? 'PAGE_NOT_READY' : e.code,
        e.code == 'PORTAL_SLOW'
            ? 'The Staff portal timed out while opening Format-10.'
            : e.message,
        stage,
      );
    }
  }
}
