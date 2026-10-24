/// Staff routes profile/history equivalent: complete-only cache and pagination.
import 'dart:convert';

import '../../../core/direct/coordinator.dart';
import '../../../core/direct/errors.dart';
import 'http_login.dart';
import 'http_auth.dart';
import 'http_read_bridge.dart';

class StaffReadService {
  StaffReadService({
    required this.registry,
    required this.coordinator,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now,
       bridge = StaffHttpReadBridge(registry);
  final StaffHttpAuth registry;
  final PortalCoordinator coordinator;
  final DateTime Function() now;
  final StaffHttpReadBridge bridge;
  int _epoch = 0;
  final _cache = <(String, int, int, String), (DateTime, List<dynamic>)>{};
  final _inflight =
      <(String, int, int, String), Future<Map<String, dynamic>>>{};
  void invalidateHistory() {
    _epoch++;
    _cache.clear();
    _inflight.clear();
  }

  Map<String, dynamic> _failure(String code, String message) => {
    'success': false,
    'code': code,
    'message': message,
    'records': <dynamic>[],
  };
  bool _owned(String user) =>
      staffLower(registry.current()?.user ?? '') == staffLower(user) &&
      user.isNotEmpty;
  bool _foreign(String user) =>
      user.isEmpty || (registry.current() != null && !_owned(user));
  bool get _connected =>
      registry.current()?.authenticated == true &&
      coordinator.health == Health.ready;
  (String, int, int, String) _key(String user, String filter) =>
      (user, coordinator.generation, _epoch, filter);
  List<dynamic> _copy(List<dynamic> rows) =>
      jsonDecode(jsonEncode(rows)) as List<dynamic>;
  Future<Map<String, dynamic>> fetchProfile(String user) async {
    if (_foreign(user))
      return _failure('ACCOUNT_CHANGED', 'Staff login changed.');
    try {
      final result = await coordinator.run(
        resource: 'staff.home',
        kind: Kind.read,
        worker: (_) => _owned(user)
            ? bridge.fetchProfile()
            : Future.value(_failure('ACCOUNT_CHANGED', 'Staff login changed.')),
        timeout: 45,
        label: 'staff_profile',
      );
      if (!_owned(user))
        return _failure('ACCOUNT_CHANGED', 'Staff login changed.');
      return result;
    } on CoordinatorError catch (e) {
      return _failure(e.kind.code, e.toString());
    }
  }

  Future<Map<String, dynamic>> _fetch(
    (String, int, int, String) key,
    String user,
    String filter,
  ) async {
    (String, int, int, String)? operationKey;
    final result = await coordinator.run(
      resource: 'staff.leave.history',
      kind: Kind.read,
      timeout: 90,
      label: 'leave_history',
      worker: (_) {
        if (!_owned(user))
          return Future.value(
            _failure('ACCOUNT_CHANGED', 'Staff login changed.'),
          );
        if (_epoch != key.$3)
          return Future.value(
            _failure(
              'CACHE_INVALIDATED',
              'Leave history changed during the request.',
            ),
          );
        operationKey = _key(user, filter);
        return bridge.fetchHistory(filter);
      },
    );
    if (result['success'] != true) return result;
    final rows = result['records'];
    if (rows is! List || rows.any((r) => r is! Map))
      return _failure('INVALID_RESULT', 'Invalid leave history response.');
    if (result['partial'] == true || result['complete'] == false)
      return _failure(
        'INCOMPLETE_HISTORY',
        'History could not be fetched completely.',
      );
    if (operationKey != _key(user, filter) || !_owned(user) || !_connected)
      return _failure(
        'CACHE_INVALIDATED',
        'Session or history changed during fetch. Fetch again.',
      );
    final copy = _copy(rows);
    _cache[operationKey!] = (now(), copy);
    return {'success': true, 'records': copy, 'key': operationKey};
  }

  Future<Map<String, dynamic>> fetchHistory(
    String user, {
    String filter = 'all',
    int? page,
    int? pageSize,
    bool refresh = false,
  }) async {
    filter = filter.trim().toLowerCase();
    if (!{'all', 'pending'}.contains(filter))
      return _failure(
        'INVALID_PAYLOAD',
        'History filter must be all or pending.',
      );
    if ((page == null) != (pageSize == null))
      return _failure('INVALID_PAYLOAD', 'Provide both page and page_size.');
    if ((page != null && page < 1) ||
        (pageSize != null && (pageSize < 1 || pageSize > 500)))
      return _failure('INVALID_PAYLOAD', 'Invalid history pagination.');
    if (_foreign(user))
      return _failure('ACCOUNT_CHANGED', 'Staff login changed.');
    try {
      await coordinator.ensureReady(Kind.read);
      if (!_owned(user))
        return _failure('ACCOUNT_CHANGED', 'Staff login changed.');
      final key = _key(user, filter), cached = _cache[_key(user, filter)];
      List<dynamic> rows;
      if (_connected &&
          !refresh &&
          cached != null &&
          !now().difference(cached.$1).isNegative &&
          now().difference(cached.$1) < const Duration(seconds: 45)) {
        rows = _copy(cached.$2);
      } else {
        var task = _inflight[key];
        if (task == null) {
          task = _fetch(key, user, filter);
          _inflight[key] = task;
          task.then(
            (_) {
              if (identical(_inflight[key], task)) _inflight.remove(key);
            },
            onError: (Object _, StackTrace __) {
              if (identical(_inflight[key], task)) _inflight.remove(key);
            },
          );
        }
        final snapshot = await task;
        if (snapshot['success'] != true) return snapshot;
        if (snapshot['key'] != _key(user, filter) ||
            !_owned(user) ||
            !_connected)
          return _failure(
            'CACHE_INVALIDATED',
            'Session or history changed during fetch. Fetch again.',
          );
        rows = _copy(snapshot['records'] as List);
      }
      if (!_owned(user) || key != _key(user, filter))
        return _failure(
          'CACHE_INVALIDATED',
          'Session or history changed during fetch. Fetch again.',
        );
      final start = page == null ? 0 : (page - 1) * pageSize!,
          end = pageSize == null ? rows.length : start + pageSize;
      return {
        'success': true,
        'records': start >= rows.length
            ? <dynamic>[]
            : rows.sublist(start, end > rows.length ? rows.length : end),
        'total': rows.length,
        'has_more': end < rows.length,
        'message': rows.isEmpty ? 'No leave history found.' : '',
      };
    } on CoordinatorError catch (e) {
      return _failure(e.kind.code, e.toString());
    }
  }
}
