/// Shared browser helpers for the existing Staff Playwright print workers.
/// The government page supplies the print document and its own click handlers.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../shaladarpan/direct/native_print_browser.dart';
import '../../shaladarpan/direct/native_print_worker.dart'
    show NativePrintWorker;
import 'portal_state.dart';

abstract class StaffNativePrintWorker {
  StaffNativePrintWorker({required this.browser, required this.check});
  final StaffPrintBrowser browser;
  final void Function() check;

  Future<Object?> evaluate(String expression, {bool popup = false}) async {
    check();
    final value = await browser.evaluate(expression, popup: popup);
    check();
    return value;
  }

  Future<({String url, String text})> document({bool popup = false}) async {
    final value = await evaluate(
      '({url:location.href,text:document.documentElement.outerHTML})',
      popup: popup,
    ) as Map;
    return (url: value['url'] as String, text: value['text'] as String);
  }

  Future<void> requireDocument(String label, {String? path}) async {
    final doc = await document();
    final failure = staffDocumentFailure(doc.url, doc.text);
    if (failure != null) {
      throw StaffPortalError(
        failure,
        failure == 'SESSION_EXPIRED'
            ? 'Staff session expired.'
            : 'The Staff portal could not open $label.',
      );
    }
    if (staffServerBase(doc.url).isEmpty ||
        (path != null && !doc.url.toLowerCase().contains(path.toLowerCase()))) {
      throw StaffPortalError(
        'PAGE_NOT_READY',
        'The Staff portal did not open $label.',
      );
    }
  }

  Future<void> waitFor(
    String expression,
    Duration budget,
    String message, {
    bool popup = false,
    Duration interval = const Duration(milliseconds: 100),
  }) async {
    final watch = Stopwatch()..start();
    while (watch.elapsed <= budget) {
      if (await evaluate(expression, popup: popup) == true) return;
      await Future<void>.delayed(interval);
    }
    throw StaffPortalError('PAGE_NOT_READY', message);
  }

  String clickId(String id, String disabledMessage) =>
      '''(() => {
    const el=document.getElementById(${jsonEncode(id)});
    if(!el) throw new Error('The official portal control is unavailable.');
    if(el.disabled || el.matches(':disabled')) throw new Error(${jsonEncode(disabledMessage)});
    el.click(); return true;
  })()''';

  Future<void> protectPopup() => evaluate(NativePrintWorker.protectPopup);

  Future<void> optionalWait(
    String expression,
    Duration budget, {
    bool popup = false,
  }) async {
    try {
      await waitFor(
        expression,
        budget,
        'Portal asset load timed out.',
        popup: popup,
      );
    } on StaffPortalError catch (_) {
      check();
    }
  }

  Future<Uint8List> capture(int marginMm) async {
    check();
    final id = await browser.renderStaffPopup(marginMm: marginMm);
    check();
    final bytes = await browser.merge([id]);
    check();
    if (bytes.length < 5 ||
        ascii.decode(bytes.sublist(0, 5), allowInvalid: true) != '%PDF-') {
      throw const StaffPortalError(
        'PRINT_CAPTURE_FAILED',
        'Portal print did not return a valid PDF.',
      );
    }
    return bytes;
  }

  Map<String, dynamic> result(Uint8List bytes, String filename) => {
    'success': true,
    'path': filename,
    'size_bytes': bytes.length,
    'pdf_bytes': bytes,
  };
}
