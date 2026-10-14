/// Native-browser conversion of nic_sheet_worker.py and study_certificate_worker.py.
/// Portal preview/CallPrint constructs the document; validation never rebuilds it.
import 'dart:async';
import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import 'native_print_browser.dart';
import 'nic_catalog_worker.dart';

part 'nic_sheet_worker.dart';
part 'study_certificate_worker.dart';

typedef NicIdentity = (String, String, String);

String _stripped(dom.Node node, [String separator = '']) {
  final parts = <String>[];
  void visit(dom.Node n) {
    if (n is dom.Element && ['script', 'style'].contains(n.localName)) return;
    if (n is dom.Text) {
      final value = n.data.trim();
      if (value.isNotEmpty) parts.add(value);
    } else {
      for (final child in n.nodes) visit(child);
    }
  }

  visit(node);
  return parts.join(separator);
}

abstract class NativePrintWorker {
  NativePrintWorker({required this.browser, required this.check});
  final NativePrintBrowser browser;
  final void Function() check;
  static const protectPopup = '''(() => {
    if (window.__nicNativeOpenProtected) return;
    window.__nicNativeOpenProtected = true;
    const nativeOpen = window.open;
    window.open = function(...args) {
      const child = nativeOpen.apply(window, args);
      if (child) { child.print = function() {}; child.close = function() {}; }
      return child;
    };
  })()''';

  Future<Object?> _eval(String script, {bool popup = false}) async {
    check();
    final result = await browser.evaluate(script, popup: popup);
    check();
    return result;
  }

  Future<void> _ready() async {
    final state = await _eval('''(() => ({url:location.href,
      ready:document.readyState !== 'loading' && (!window.Sys || !Sys.WebForms ||
        !Sys.WebForms.PageRequestManager.getInstance().get_isInAsyncPostBack()),
      text:document.body?.innerText || ''}))()''') as Map;
    final path = Uri.parse(state['url'] as String).path.toLowerCase();
    if (path.contains('/public') ||
        RegExp(r'/(?:officelogin|stafflogin|login|default)(?:new)?\.aspx$')
            .hasMatch(path)) {
      throw const NicError('SESSION_EXPIRED', 'School portal session expired.');
    }
    final text = state['text'] as String;
    if (RegExp(
      r'Object reference not set to an instance|Server Error in|Runtime Error',
    ).hasMatch(text)) {
      throw NicError(
        'PAGE_NOT_READY',
        text.substring(0, text.length.clamp(0, 800)),
      );
    }
    if (state['ready'] != true)
      throw const NicError(
        'PAGE_NOT_READY',
        'The school portal page is not ready.',
      );
  }

  Future<void> _wait(
    String condition,
    Duration duration, {
    bool popup = false,
    String code = 'PORTAL_SLOW',
    String message = 'The native portal operation timed out.',
  }) async {
    final clock = Stopwatch()..start();
    while (clock.elapsed < duration) {
      if (await _eval(condition, popup: popup) == true) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw NicError(code, message);
  }

  Future<List<Map<String, dynamic>>> _options(String id) async => (await _eval(
    '''(() => Array.from(document.getElementById(${jsonEncode(id)})?.options || [])
      .filter(o => o.value.trim() && !o.disabled)
      .map(o => ({id:o.value,label:o.text.trim(),selected:o.selected})))()''',
  ) as List).map((value) => Map<String, dynamic>.from(value as Map)).toList();

  Future<void> _select(String id, String value) async {
    if (!(await _options(id)).any((o) => o['id'] == value)) {
      throw const NicError(
        'BAD_CLASS',
        'The requested reporting selection is not available on the portal.',
      );
    }
    final automatic =
        await _eval(
          '''!!document.getElementById(${jsonEncode(id)})?.getAttribute('onchange')''',
        ) ==
        true;
    final action =
        '''(() => { const e=document.getElementById(${jsonEncode(id)});
      e.value=${jsonEncode(value)}; e.dispatchEvent(new Event('input',{bubbles:true}));
      e.dispatchEvent(new Event('change',{bubbles:true})); return null; })()''';
    if (automatic) {
      check();
      await browser.postback(action);
      check();
      await _ready();
    } else {
      await _eval(action);
    }
  }

  Future<String> _html({bool popup = false}) async =>
      ((await _eval(
            '[document.documentElement.outerHTML]',
            popup: popup,
          )) as List).single
          as String;

  Future<void> _assets(int minimum, {bool certificate = false}) async {
    await _wait(
      "!!document.body && document.body.innerText.trim().length > $minimum",
      const Duration(seconds: 15),
      popup: true,
    );
    await _eval('document.body.getBoundingClientRect().height', popup: true);
    await _wait(
      "(!document.fonts || document.fonts.status==='loaded') && Array.from(document.images).every(i=>i.complete)",
      const Duration(seconds: 30),
      popup: true,
      code: certificate ? 'PORTAL_SLOW' : 'PRINT_ASSETS_NOT_READY',
      message: certificate
          ? 'Portal print images or fonts did not finish loading.'
          : 'Portal print images or fonts did not finish loading.',
    );
    if (await _eval(
          'Array.from(document.images).some(i=>!i.naturalWidth || !i.naturalHeight)',
          popup: true,
        ) ==
        true) {
      throw NicError(
        'PRINT_ASSET_MISSING',
        certificate ? 'Portal certificate print image could not be loaded.' : 'The portal print header image could not be loaded. Retry after the portal page finishes loading.',
      );
    }
  }
}
