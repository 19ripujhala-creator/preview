import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shaladarpan/services/core/backend_config.dart';
import 'package:shaladarpan/services/core/ecosystem_service.dart';
import 'package:shaladarpan/services/core/secure_storage_service.dart';

import '../../../experiments/direct_school_session.dart';
import '../../core/direct/async_primitives.dart';
import 'direct/leave_result_messages.dart';
import 'shaladarpan_service.dart';
import 'student_service.dart';

class LeaveApprovalService {
  static Future<Map<String, dynamic>>? _fetching;
  static String? _fetchSchool, _fetchDay;
  static Object? _fetchSession;
  static bool _fetchDirect = false;
  static int _epoch = 0, _fetchEpoch = -1;
  static bool _submitting = false;
  static final _cacheMutex = AsyncMutex();
  static bool _snapshotDirectMode = false;
  static Object? _snapshotSession;
  static final ValueNotifier<Map<String, dynamic>?> liveStatus = ValueNotifier(
    null,
  );
  static DateTime? _confirmedAt;
  static Map<String, dynamic>? _snapshot;
  static String? _snapshotSchool, _snapshotDay;

  @visibleForTesting
  static DateTime Function()? clock;
  static DateTime get _now => (clock?.call() ?? DateTime.now()).toUtc();
  static String get _day {
    final d = _now.add(const Duration(hours: 5, minutes: 30));
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static Map<String, dynamic> _copy(Map result) =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(result)) as Map);

  static bool _sameSession(bool direct, Object? session, String school) =>
      direct == StudentService.directAttendanceEnabled &&
      (!direct ||
          (DirectSchoolSession.schoolId == school &&
              identical(session, DirectSchoolSession.leaveApprovals)));

  static Map<String, dynamic>? confirmedSnapshot(String school) {
    final age = _confirmedAt == null ? null : _now.difference(_confirmedAt!);
    if (_submitting ||
        _fetching != null ||
        !_sameSession(_snapshotDirectMode, _snapshotSession, school) ||
        _snapshotSchool != school ||
        _snapshotDay != _day ||
        _snapshot == null ||
        age == null ||
        age.isNegative ||
        age >= const Duration(minutes: 1))
      return null;
    return _copy(_snapshot!);
  }

  static void _invalidateLive(String school) {
    _epoch++;
    _snapshot = null;
    _confirmedAt = null;
    liveStatus.value = {
      'school_id': school,
      'loading': false,
      'success': false,
      'message': 'Leave status needs to be refreshed.',
    };
  }

  static bool valid(Map data) {
    final apps = data['applications'], count = data['pending_count'];
    if (data['success'] == false ||
        apps is! List ||
        count is! int ||
        count < 0 ||
        count != apps.length)
      return false;
    final ids = <String>{};
    for (final row in apps) {
      if (row is! Map) return false;
      final id = row['leave_id']?.toString() ?? '';
      if (!RegExp(r'^\d+$').hasMatch(id) || !ids.add(id)) return false;
    }
    return true;
  }

  static Future<Map<String, dynamic>?> getCachedLeaves() async {
    try {
      final school = (await SecureStorageService.getShaladarpanCreds())['id']
          ?.trim();
      final day = _day;
      final prefs = await SharedPreferences.getInstance();
      if (school == null ||
          school.isEmpty ||
          prefs.getString('leave_cache_school') != school ||
          prefs.getString('leave_cache_day') != day)
        return null;
      final raw = prefs.getString('cached_pending_leaves');
      if (raw == null) return null;
      final data = jsonDecode(raw);
      if ((await SecureStorageService.getShaladarpanCreds())['id']?.trim() !=
              school ||
          day != _day)
        return null;
      return data is Map && valid(data) ? _copy(data) : null;
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _staleRead() => {
    'success': false,
    'code': 'STALE_LEAVE_READ',
    'message': 'School leave status changed during this read. Refresh again.',
  };

  static Future<Map<String, dynamic>> fetchLeaveApprovals({
    bool fresh = true,
  }) async {
    final school =
        (await SecureStorageService.getShaladarpanCreds())['id']?.trim() ?? '';
    if (school.isEmpty)
      return {'success': false, 'message': 'School login is required.'};
    final direct = StudentService.directAttendanceEnabled;
    final session = direct ? DirectSchoolSession.leaveApprovals : null;
    final day = _day;
    if (direct && (session == null || !_sameSession(direct, session, school))) {
      _invalidateLive(school);
      return {
        'success': false,
        'code': 'SESSION_EXPIRED',
        'message': 'Direct School login is required.',
      };
    }
    if (_fetching != null &&
        _fetchSchool == school &&
        _fetchDay == day &&
        _fetchDirect == direct &&
        _fetchEpoch == _epoch &&
        identical(_fetchSession, session))
      return _copy(await _fetching!);
    if (!fresh) {
      final snapshot = confirmedSnapshot(school);
      if (snapshot != null) return snapshot;
    }
    final epoch = ++_epoch;
    // Retain the prior review while a refresh is in flight; a failed refresh
    // disarms it. Confirmed counts remain unavailable until this read settles.
    liveStatus.value = {'school_id': school, 'loading': true, 'success': false};
    _fetchSchool = school;
    _fetchSession = session;
    _fetchDay = day;
    _fetchDirect = direct;
    _fetchEpoch = epoch;
    final task = _readAndPublish(school, direct, session, day, epoch);
    _fetching = task;
    try {
      return _copy(await task);
    } finally {
      if (identical(_fetching, task)) {
        _fetching = null;
        _fetchSchool = null;
      }
    }
  }

  static Future<Map<String, dynamic>> _readAndPublish(
    String school,
    bool direct,
    dynamic session,
    String day,
    int epoch,
  ) async {
    bool current() =>
        epoch == _epoch &&
        !_submitting &&
        day == _day &&
        _sameSession(direct, session, school);
    Future<bool> owned() async =>
        (await SecureStorageService.getShaladarpanCreds())['id']?.trim() ==
            school &&
        current();
    Map<String, dynamic> result;
    try {
      if (direct) {
        final Map<String, dynamic> raw = await session.fetch();
        result = raw['success'] == true ? {'success': true, 'data': raw} : raw;
      } else {
        result = _decode(
          await http
              .post(
                BackendConfig.uri('/api/shaladarpan/leaves/fetch'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({'school_id': school, 'force_refresh': true}),
              )
              .timeout(const Duration(seconds: 90)),
        );
      }
      if (!await owned()) return _staleRead();
      if (result['success'] == true &&
          (result['data'] is! Map || !valid(result['data']))) {
        result = {
          'success': false,
          'code': 'INVALID_RESULT',
          'message': 'Portal leave count and records could not be verified.',
        };
      }
      if (result['success'] == true) {
        final release = await _cacheMutex.acquire();
        try {
          if (!await owned()) return _staleRead();
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('leave_cache_school');
          await prefs.setString(
            'cached_pending_leaves',
            jsonEncode(result['data']),
          );
          await prefs.setString('leave_cache_day', day);
          if (!await owned()) return _staleRead();
          await prefs.setString('leave_cache_school', school);
          if (!await owned()) {
            await prefs.remove('leave_cache_school');
            return _staleRead();
          }
        } finally {
          release();
        }
      }
    } on TimeoutException {
      result = {
        'success': false,
        'code': 'LEAVE_FETCH_TIMEOUT',
        'message':
            'Leave approval status could not be confirmed. Please retry.',
      };
    } catch (_) {
      result = {
        'success': false,
        'message': 'Could not load leave approvals from the portal.',
      };
    }
    if (!await owned()) return _staleRead();
    if (result['success'] == true) {
      _snapshotDirectMode = direct;
      _snapshotSession = session;
      _snapshotSchool = school;
      _snapshotDay = day;
      _snapshot = _copy(result);
      _confirmedAt = _now;
    } else {
      _snapshot = null;
      _confirmedAt = null;
    }
    liveStatus.value = {
      ..._copy(result),
      'school_id': school,
      'loading': false,
    };
    return result;
  }

  static Map<String, dynamic> _decode(http.Response response) {
    final data = EcosystemService.decode(response);
    if (data['success'] != true && data['detail'] is Map) {
      return {...Map<String, dynamic>.from(data['detail']), 'success': false};
    }
    return data;
  }

  /// A success flag or disappearance from Pending is not saved-status proof.
  static bool isActionConfirmed(
    Map result,
    List<Map<String, dynamic>> actions,
  ) {
    final statuses = result['verified_statuses'];
    if (result['success'] != true ||
        result['verified'] != true ||
        result['verification_source'] != 'all_applications' ||
        statuses is! Map ||
        actions.isEmpty ||
        statuses.length != actions.length)
      return false;
    final ids = <String>{};
    for (final action in actions) {
      final id = action['leave_id']?.toString().trim() ?? '';
      final code = action['status']?.toString().trim();
      if (!ids.add(id) ||
          !{'1', '2'}.contains(code) ||
          statuses[id] != (code == '1' ? 'Processed' : 'Rejected'))
        return false;
    }
    return true;
  }

  static Future<Map<String, dynamic>> submitLeaveAction({
    required String leaveId,
    required String status,
    String remark = '',
  }) => submitBatchLeaveActions([
    {'leave_id': leaveId, 'status': status, 'remark': remark},
  ]);

  static Future<Map<String, dynamic>> submitBatchLeaveActions(
    List<Map<String, dynamic>> actions,
  ) async {
    Map<String, dynamic> blocked(String code, String message) => {
      'success': false,
      'verified': false,
      'submission_attempted': false,
      'code': code,
      'message': message,
    };
    if (_submitting)
      return blocked('ACTION_BUSY', 'A leave action is already in progress.');
    // Freeze caller-owned collections before any await.
    final frozen = actions
        .map(
          (a) => <String, dynamic>{
            'leave_id': a['leave_id']?.toString().trim() ?? '',
            'status': a['status']?.toString().trim() ?? '',
            'remark': a['remark']?.toString().trim() ?? '',
          },
        )
        .toList();
    final ids = <String>{};
    if (frozen.isEmpty ||
        frozen.any(
          (a) =>
              !RegExp(r'^\d+$').hasMatch(a['leave_id']) ||
              !ids.add(a['leave_id']) ||
              !{'1', '2'}.contains(a['status']),
        )) {
      return blocked(
        'INVALID_PAYLOAD',
        'Provide unique leave IDs and an explicit Approve (1) or Reject (2) status.',
      );
    }
    final school = _snapshotSchool ?? '';
    final reviewed = _snapshot;
    final reviewedAt = _confirmedAt;
    final reviewedDay = _snapshotDay;
    final direct = StudentService.directAttendanceEnabled;
    final session = direct ? DirectSchoolSession.leaveApprovals : null;
    final reviewMode = _snapshotDirectMode, reviewSession = _snapshotSession;
    _submitting = true;
    _invalidateLive(school);
    var attempted = false;
    try {
      final account = (await SecureStorageService.getShaladarpanCreds())['id']
          ?.trim();
      if (account != school ||
          !_sameSession(direct, session, school) ||
          direct != reviewMode ||
          !identical(reviewSession, session)) {
        return blocked(
          'ACCOUNT_CHANGED',
          'Fetch and review leaves for the current School login first.',
        );
      }
      final age = reviewedAt == null ? null : _now.difference(reviewedAt);
      if (reviewed == null ||
          reviewedDay != _day ||
          age == null ||
          age.isNegative ||
          age > const Duration(seconds: 180) ||
          !(reviewed['data']['applications'] as List)
              .map((r) => r['leave_id'].toString())
              .toSet()
              .containsAll(ids)) {
        return blocked(
          'STALE_FORM',
          'Fetch and review the pending leaves before processing them.',
        );
      }
      Map<String, dynamic> result;
      if (direct) {
        attempted = true;
        result = await session!.submit(frozen, userConfirmed: true);
        attempted = result['submission_attempted'] == true;
      } else {
        attempted = true;
        result = _decode(
          await http
              .post(
                BackendConfig.uri('/api/shaladarpan/leaves/action'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({'actions': frozen}),
              )
              .timeout(const Duration(seconds: 90)),
        );
      }
      if ((await SecureStorageService.getShaladarpanCreds())['id']?.trim() !=
              account ||
          !_sameSession(direct, session, school) ||
          reviewedDay != _day) {
        return LeaveResultMessages.attach({
          ...result,
          'success': false,
          'verified': false,
          'code': attempted ? 'SAVE_UNCONFIRMED' : 'ACCOUNT_CHANGED',
          'submission_attempted': attempted,
          'message': 'School session or date changed. Verify leave actions on the portal before retrying.',
        }, LeaveResultMessages.portalTexts(result));
      }
      if (result['success'] == true && !isActionConfirmed(result, frozen)) {
        return LeaveResultMessages.attach({
          ...result,
          'success': false,
          'verified': false,
          'code': 'SAVE_UNCONFIRMED',
          'submission_attempted': attempted,
          'message': 'Exact leave action statuses were not verified in All Applications. Check the portal before retrying.',
        }, LeaveResultMessages.portalTexts(result));
      }
      return _copy(result);
    } on TimeoutException {
      return {
        'success': false,
        'verified': false,
        'submission_attempted': attempted,
        'code': attempted ? 'MUTATION_AMBIGUOUS' : 'LEAVE_ACTION_FAILED',
        'message': 'Leave action result is unconfirmed. Refresh the portal before retrying.',
      };
    } catch (_) {
      return {
        'success': false,
        'verified': false,
        'submission_attempted': attempted,
        'message': 'Leave action result could not be confirmed. Refresh before retrying.',
      };
    } finally {
      // Reads admitted before or during this action must not re-arm old rows.
      _invalidateLive(school);
      ShaladarpanService.invalidateStaffSnapshot();
      final release = await _cacheMutex.acquire();
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('leave_cache_school');
      } catch (_) {
      } finally {
        release();
      }
      _invalidateLive(school);
      _submitting = false;
    }
  }
}
