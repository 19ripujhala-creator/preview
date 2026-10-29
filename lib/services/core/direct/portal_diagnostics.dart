/// Bounded, on-device timing evidence. Never records HTML, identity, payloads,
/// query strings, cookies, tokens, credentials or exception messages.
import 'dart:convert';
import 'dart:async';

import 'async_primitives.dart';

enum PortalPhase {
  httpRequest,
  httpClientAcquire,
  httpOpen,
  httpResponseHeaders,
  httpCookiePersistence,
  httpStorageQueue,
  httpStorageWrite,
  httpResponseBody,
  studentRead,
  studentView,
  studentReadOperation,
  studentSaveOperation,
  studentParse,
  studentPreflight,
  studentPrepare,
  studentSubmit,
  studentVerify,
  sessionProbe,
}

class PortalDiagnostics {
  /// Preserve debug/test logging; production builds collect only by explicit opt-in.
  static const enabled = bool.fromEnvironment(
    'PORTAL_DIAGNOSTICS',
    defaultValue: !bool.fromEnvironment('dart.vm.product'),
  );
  static final _events = <Map<String, Object?>>[];
  static int _sequence = 0;
  static const capacity = 960;
  static final _clock = Stopwatch()..start();
  static final _parentKey = Object(), _actionKey = Object();
  static final _requestKey = Object(), _requestMetadataKey = Object();
  static const _httpPhases = {
    PortalPhase.httpRequest,
    PortalPhase.httpOpen,
    PortalPhase.httpResponseHeaders,
    PortalPhase.httpCookiePersistence,
    PortalPhase.httpResponseBody,
  };
  static int _generation = 0;
  static const _actions = {'GET_PAGE', 'SHOW', 'BACK', 'CLASS_ENTRY', 'SUBMIT'};
  static const _sources = {'school', 'rajsims', 'sso', 'other'};
  static const _codes = {
    'PORTAL_SLOW',
    'READ_SUPERSEDED',
    'STALE_ATTENDANCE_READ',
    'ACCOUNT_CHANGED',
    'SESSION_EXPIRED',
    'SESSION_UNVERIFIED',
    'PAGE_BUSY',
    'NETWORK_ERROR',
    'PORTAL_HTTP',
    'PORTAL_RESPONSE_ERROR',
    'SAVE_UNCONFIRMED',
    'NAVIGATION_RACE',
    'INVALID_ATTENDANCE_READ',
    'DATE_MISMATCH',
    'MATCH_MISMATCH',
    'PAGE_NOT_READY',
    'NO_STUDENT_TABLE',
    'PORTAL_MESSAGE',
  };
  static Future<T> withAction<T>(
    String action,
    Future<T> Function() operation,
  ) => !enabled
      ? operation()
      : runZoned(
          operation,
          zoneValues: {
            _actionKey: _actions.contains(action) ? action : 'other',
          },
        );
  static String sourceForHost(String host) => switch (host.toLowerCase()) {
    'rajshaladarpan.rajasthan.gov.in' => 'school',
    'rajsims.rajasthan.gov.in' || 'rajsims-mdm.rajasthan.gov.in' => 'rajsims',
    'sso.rajasthan.gov.in' => 'sso',
    _ => 'other',
  };
  static const _pages = {
    'studentdailyattendancestatus_web_newversion.aspx',
    'home_new.aspx',
    'officeloginnew.aspx',
    'rmsa_schoolmonthly_np_tablets.aspx',
    'studentdetails.aspx',
    'getssologin',
    'getdata',
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
    String? source,
    int? deadlineMs,
    int? hop,
    String? transport,
    int? Function(T)? status,
  }) async {
    if (!enabled) return await operation();
    final sequence = ++_sequence, timer = Stopwatch()..start();
    final generation = _generation, started = _clock.elapsedMilliseconds;
    final parent = Zone.current[_parentKey];
    final action = Zone.current[_actionKey];
    final request = phase == PortalPhase.httpRequest
        ? sequence
        : Zone.current[_requestKey];
    final inherited = Zone.current[_requestMetadataKey];
    final metadata = <String, Object?>{
      if (inherited is Map<String, Object?>) ...inherited,
      if (method != null) 'method': method,
      if (path != null) 'path': path,
      if (source != null) 'source': source,
      if (transport != null) 'transport': transport,
    };
    final tagged = _httpPhases.contains(phase);
    int? httpStatus;
    bool? success;
    String? resultCode;
    var outcome = 'complete';
    try {
      final result = await runZoned(
        operation,
        zoneValues: {
          _parentKey: sequence,
          if (phase == PortalPhase.httpRequest) _requestKey: sequence,
          if (phase == PortalPhase.httpRequest) _requestMetadataKey: metadata,
        },
      );
      httpStatus = status?.call(result);
      if (result is Map) {
        if (result['success'] is bool) success = result['success'] as bool;
        final code = result['code'];
        if (_codes.contains(code)) resultCode = code as String;
      }
      if (httpStatus != null && httpStatus >= 400) outcome = 'http_error';
      return result;
    } catch (error) {
      outcome = error is TimeoutException
          ? 'timeout'
          : error is OperationCancelled
          ? 'cancelled'
          : 'exception';
      rethrow;
    } finally {
      timer.stop();
      if (generation == _generation)
        _events.add({
          'sequence': sequence,
          'phase': phase.name,
          'started_ms': started,
          'ended_ms': _clock.elapsedMilliseconds,
          if (parent is int) 'parent_sequence': parent,
          if (request is int) 'request_sequence': request,
          if (hop != null && hop >= 0 && hop <= 20) 'hop': hop,
          if (action is String) 'action': action,
          'source': _sources.contains(metadata['source'])
              ? metadata['source']
              : 'other',
          if (const {'pooled', 'direct'}.contains(metadata['transport']))
            'transport': metadata['transport'],
          'elapsed_ms': timer.elapsedMilliseconds,
          if (deadlineMs != null && deadlineMs > 0) 'deadline_ms': deadlineMs,
          'outcome': outcome,
          if (success != null) 'success': success,
          if (resultCode != null) 'result_code': resultCode,
          if (tagged)
            'method':
                [
                  'GET',
                  'POST',
                  'HEAD',
                ].contains((metadata['method'] as String?)?.toUpperCase())
                ? (metadata['method'] as String).toUpperCase()
                : 'other',
          if (tagged) 'page': _page(metadata['path'] as String?),
          if (httpStatus != null) 'status': httpStatus,
        });
      if (_events.length > capacity)
        _events.removeRange(0, _events.length - capacity);
    }
  }

  static int get monotonicMilliseconds => _clock.elapsedMilliseconds;
  static void recordStudentView({
    required int startedMs,
    required String cache,
    required String outcome,
    bool viewOnly = false,
  }) {
    if (!enabled) return;
    const caches = {
      'hit',
      'notFound',
      'expired',
      'scopeChanged',
      'forced',
      'scopeUnavailable',
      'preview',
    };
    const outcomes = {'rendered', 'failed', 'superseded', 'disposed'};
    final ended = _clock.elapsedMilliseconds;
    final started = startedMs < 0
        ? 0
        : startedMs > ended
        ? ended
        : startedMs;
    final duration = ended - started;
    _events.add({
      'sequence': ++_sequence,
      'phase': PortalPhase.studentView.name,
      'started_ms': started,
      'ended_ms': ended,
      'elapsed_ms': duration,
      'cache': caches.contains(cache) ? cache : 'other',
      'outcome': outcomes.contains(outcome) ? outcome : 'other',
      'view_only': viewOnly,
    });
    if (_events.length > capacity)
      _events.removeRange(0, _events.length - capacity);
  }

  static String export() => const JsonEncoder.withIndent('  ').convert({
    'format': 'rajshala.portal.timings.v1',
    'enabled': enabled,
    'events': List<Map<String, Object?>>.of(_events),
  });
  static void clear() {
    _generation++;
    _events.clear();
  }
}
