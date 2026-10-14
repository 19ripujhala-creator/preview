import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'nic_catalog_worker.dart';
import '../../../core/direct/async_primitives.dart';

// Android CookieManager is process-wide; School and Staff capture share this lease.
final nativePrintLease = AsyncMutex();

/// Only a local browser boundary. Government pages construct the print popup;
/// neither Dart nor Android supplies a replacement report document.
abstract class NativePrintBrowser {
  Future<void> begin(Uri base, Map<String, String> cookies);
  Future<void> navigate(String path);
  Future<Object?> evaluate(String expression, {bool popup = false});
  Future<void> postback(String expression, {String? grid});
  Future<void> openPopup(String expression);
  Future<String> renderPopup();
  Future<Uint8List> merge(List<String> pdfIds);
  Future<void> closePopup();
  Future<void> close();
}

abstract class StaffPrintBrowser implements NativePrintBrowser {
  Future<void> beginStaff(Uri base, List<Map<String, dynamic>> cookies);
  Future<void> abort() async {}
  Future<List<Map<String, dynamic>>> staffCookies();
  Future<String> renderStaffPopup({required int marginMm});
}

class PlatformNativePrintBrowser implements StaffPrintBrowser {
  PlatformNativePrintBrowser({MethodChannel? channel})
    : channel = channel ?? const MethodChannel('rajshala/native_portal_print');
  final MethodChannel channel;
  String? _token;
  Future<T?> _call<T>(
    String method, [
    Map<String, Object?> args = const {},
  ]) async {
    try {
      return await channel.invokeMethod<T>(method, {
        if (_token != null) 'token': _token,
        ...args,
      });
    } on PlatformException catch (e) {
      throw NicError(
        e.code,
        e.message ?? 'The native portal print could not be completed.',
      );
    } on MissingPluginException {
      throw const NicError(
        'NATIVE_PRINT_UNAVAILABLE',
        'Native portal printing is not installed for this platform.',
      );
    }
  }

  @override
  Future<void> begin(Uri base, Map<String, String> cookies) async {
    _token = await _call<String>('begin', {
      'base': base.toString().replaceFirst(RegExp(r'/$'), ''),
      'cookies': cookies,
    });
    if (_token == null || _token!.isEmpty)
      throw const NicError(
        'SESSION_EXPIRED',
        'Native school session is unavailable.',
      );
  }

  @override
  Future<void> beginStaff(Uri base, List<Map<String, dynamic>> cookies) async {
    _token = await _call<String>('begin', {
      'base': base.toString().replaceFirst(RegExp(r'/$'), ''),
      'portal': 'staff',
      'scopedCookies': cookies,
    });
    if (_token == null || _token!.isEmpty) {
      throw const NicError(
        'SESSION_EXPIRED',
        'Native Staff session is unavailable.',
      );
    }
  }

  @override
  Future<void> abort() async {
    if (_token != null) await _call<void>('abort');
  }

  @override
  Future<List<Map<String, dynamic>>> staffCookies() async {
    final rows = await _call<List<dynamic>>('staffCookies');
    return [
      for (final row in rows ?? []) Map<String, dynamic>.from(row as Map),
    ];
  }

  @override
  Future<String> renderStaffPopup({required int marginMm}) async {
    if (marginMm != 5 && marginMm != 10) {
      throw ArgumentError.value(marginMm, 'marginMm');
    }
    final id = await _call<String>('pdf', {'marginMm': marginMm});
    if (id == null || id.isEmpty) {
      throw const NicError(
        'PRINT_CAPTURE_FAILED',
        'Portal print did not return a PDF page.',
      );
    }
    return id;
  }

  @override
  Future<void> navigate(String path) => _call<void>('navigate', {'path': path});
  @override
  Future<Object?> evaluate(String expression, {bool popup = false}) async {
    final value = await _call<Object?>('evaluate', {
      'script': expression,
      'popup': popup,
    });
    // Android wraps JSON containers as a JSON string; iOS returns native containers. scalar strings are passed
    // directly. Workers request containers explicitly and strings via arrays.
    if (value is String && (value.startsWith('{') || value.startsWith('[')))
      return jsonDecode(value);
    return value;
  }

  @override
  Future<void> postback(String expression, {String? grid}) => _call<void>(
    'postback',
    {'script': expression, if (grid != null) 'grid': grid},
  );
  @override
  Future<void> openPopup(String expression) =>
      _call<void>('popup', {'script': expression});
  @override
  Future<String> renderPopup() async {
    final id = await _call<String>('pdf');
    if (id == null || id.isEmpty)
      throw const NicError(
        'PAGE_NOT_READY',
        'Portal print did not return a PDF page.',
      );
    return id;
  }

  @override
  Future<Uint8List> merge(List<String> pdfIds) async {
    final bytes = await _call<Uint8List>('merge', {'ids': pdfIds});
    if (bytes == null ||
        bytes.length < 5 ||
        ascii.decode(bytes.sublist(0, 5), allowInvalid: true) != '%PDF-') {
      throw const NicError(
        'PAGE_NOT_READY',
        'Portal print did not return a PDF.',
      );
    }
    return bytes;
  }

  @override
  Future<void> closePopup() => _call<void>('closePopup');
  @override
  Future<void> close() async {
    if (_token == null) return;
    try {
      await _call<void>('close');
    } finally {
      _token = null;
    }
  }
}

/// Compatibility for existing callers and tests. Both platforms share the channel.
typedef AndroidNativePrintBrowser = PlatformNativePrintBrowser;
