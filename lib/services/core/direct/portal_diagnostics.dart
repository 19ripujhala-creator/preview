/// Bounded, on-device timing evidence. Never records HTML, identity, payloads,
/// query strings, cookies, tokens, credentials or exception messages.
import 'dart:convert';

enum PortalPhase {
  httpRequest,
  studentRead,
  studentParse,
  studentPreflight,
  studentSubmit,
  studentVerify,
  sessionProbe,
}

class PortalDiagnostics {
  static final _events = <Map<String, Object?>>[];
  static int _sequence = 0;
  static const capacity = 80;
  static const _pages = {
    'studentdailyattendancestatus_web_newversion.aspx',
    'home_new.aspx',
    'officeloginnew.aspx',
  };
  static String _page(String? path) {
    final name = path?.split('/').last.toLowerCase();
    return _pages.contains(name) ? name! : 'other';
  }

  static Future<T> measure<T>(
    PortalPhase phase,
    Future<T> Function() operation, {
    String? method,
    String? path,
    int? Function(T)? status,
  }) async {
    final sequence = ++_sequence, timer = Stopwatch()..start();
    int? httpStatus;
    var outcome = 'complete';
    try {
      final result = await operation();
      httpStatus = status?.call(result);
      if (httpStatus != null && httpStatus >= 400) outcome = 'http_error';
      return result;
    } catch (_) {
      outcome = 'exception';
      rethrow;
    } finally {
      timer.stop();
      _events.add({
        'sequence': sequence,
        'phase': phase.name,
        'elapsed_ms': timer.elapsedMilliseconds,
        'outcome': outcome,
        if (phase == PortalPhase.httpRequest)
          'method': ['GET', 'POST', 'HEAD'].contains(method?.toUpperCase())
              ? method!.toUpperCase()
              : 'other',
        if (phase == PortalPhase.httpRequest) 'page': _page(path),
        if (httpStatus != null) 'status': httpStatus,
      });
      if (_events.length > capacity)
        _events.removeRange(0, _events.length - capacity);
    }
  }

  static String export() => const JsonEncoder.withIndent('  ').convert({
    'format': 'rajshala.portal.timings.v1',
    'events': List<Map<String, Object?>>.of(_events),
  });
  static void clear() => _events.clear();
}
