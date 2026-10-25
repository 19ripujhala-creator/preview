import '../../../experiments/direct_school_session.dart';
import 'student_service.dart';
import 'direct/leave_result_messages.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shaladarpan/services/core/backend_config.dart';
import 'package:shaladarpan/services/core/ecosystem_service.dart';
import 'package:shaladarpan/services/core/secure_storage_service.dart';

import 'shaladarpan_service.dart';

class LeaveApprovalService {
  static Future<Map<String, dynamic>>? _fetching;
  static String? _fetchSchool;
  static bool _submitting = false;
  static bool _snapshotDirectMode = false;
  static Object? _snapshotSession;
  static Object? _fetchSession;
  static final ValueNotifier<Map<String, dynamic>?> liveStatus = ValueNotifier(
    null,
  );
  static DateTime? _confirmedAt;
  static Map<String, dynamic>? _snapshot;
  static String? _snapshotSchool;
  static String? _snapshotDay;
  static Map<String, dynamic>? confirmedSnapshot(String school) {
    if (_snapshotDirectMode != StudentService.directAttendanceEnabled ||
        (_snapshotDirectMode &&
            !identical(_snapshotSession, DirectSchoolSession.leaveApprovals)))
      return null;
    if (_snapshotSchool != school ||
        _snapshotDay != _day ||
        _confirmedAt == null ||
        _snapshot == null ||
        DateTime.now().difference(_confirmedAt!) >= const Duration(minutes: 1))
      return null;
    return _snapshot;
  }

  static void _invalidateLive(String school) {
    _snapshot = null;
    _confirmedAt = null;
    liveStatus.value = {
      'school_id': school,
      'loading': false,
      'success': false,
      'message': 'Leave status needs to be refreshed.',
    };
  }

  static String get _day {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static bool valid(Map data) {
    final apps = data['applications'];
    final count = data['pending_count'];
    return data['success'] != false &&
        apps is List &&
        count is int &&
        count >= 0 &&
        count == apps.length &&
        apps.every(
          (row) => row is Map && (row['leave_id']?.toString() ?? '').isNotEmpty,
        );
  }

  static Future<Map<String, dynamic>?> getCachedLeaves() async {
    try {
      final school = (await SecureStorageService.getShaladarpanCreds())['id'];
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString('leave_cache_school') != school ||
          prefs.getString('leave_cache_day') != _day)
        return null;
      final raw = prefs.getString('cached_pending_leaves');
      if (raw == null) return null;
      final data = jsonDecode(raw);
      return data is Map && valid(data)
          ? Map<String, dynamic>.from(data)
          : null;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>> fetchLeaveApprovals({
    bool fresh = true,
  }) async {
    final school =
        (await SecureStorageService.getShaladarpanCreds())['id']?.trim() ?? '';
    if (school.isEmpty)
      return {'success': false, 'message': 'School login is required.'};
    final direct = StudentService.directAttendanceEnabled;
    final session = direct ? DirectSchoolSession.leaveApprovals : null;
    if (direct && (session == null || DirectSchoolSession.schoolId != school))
      return {
        'success': false,
        'code': 'SESSION_EXPIRED',
        'message': 'Direct School login is required.',
      };
    if (_fetching != null &&
        _fetchSchool == school &&
        identical(_fetchSession, session))
      return _fetching!;
    if (!fresh) {
      final snapshot = confirmedSnapshot(school);
      if (snapshot != null) return snapshot;
    }
    _snapshot = null;
    _confirmedAt = null;
    liveStatus.value = {'school_id': school, 'loading': true, 'success': false};
    _fetchSchool = school;
    _fetchSession = session;
    final task = _read(school);
    _fetching = task;
    try {
      final result = await task;
      if ((await SecureStorageService.getShaladarpanCreds())['id']?.trim() ==
              school &&
          identical(_fetching, task)) {
        if (result['success'] == true &&
            result['data'] is Map &&
            valid(result['data'])) {
          _snapshotDirectMode = direct;
          _snapshotSession = session;
          _snapshotSchool = school;
          _snapshotDay = _day;
          _snapshot = result;
          _confirmedAt = DateTime.now();
        }
        liveStatus.value = {...result, 'school_id': school, 'loading': false};
      }
      return result;
    } finally {
      if (identical(_fetching, task)) {
        _fetching = null;
        _fetchSchool = null;
      }
    }
  }

  static Future<Map<String, dynamic>> _read(String school) async {
    try {
      final direct = StudentService.directAttendanceEnabled;
      final session = DirectSchoolSession.leaveApprovals;
      late Map<String, dynamic> result;
      if (direct) {
        if (session == null || DirectSchoolSession.schoolId != school)
          return {
            'success': false,
            'code': 'SESSION_EXPIRED',
            'message': 'Direct School login is required.',
          };
        final raw = await session.fetch();
        result = raw['success'] == true ? {'success': true, 'data': raw} : raw;
      } else {
        final response = await http
            .post(
              BackendConfig.uri('/api/shaladarpan/leaves/fetch'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'school_id': school, 'force_refresh': true}),
            )
            .timeout(const Duration(seconds: 90));
        result = _decode(response);
      }
      if (StudentService.directAttendanceEnabled != direct ||
          (direct && !identical(session, DirectSchoolSession.leaveApprovals)))
        return {
          'success': false,
          'code': 'ACCOUNT_CHANGED',
          'message': 'School session changed during leave fetch.',
        };
      if (result['success'] != true) return result;
      final data = result['data'];
      if (data is! Map || !valid(data))
        return {
          'success': false,
          'code': 'INVALID_RESULT',
          'message': 'Portal leave count and records could not be verified.',
        };
      if ((await SecureStorageService.getShaladarpanCreds())['id']?.trim() !=
          school)
        return {
          'success': false,
          'message': 'School account changed during leave fetch.',
        };
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_pending_leaves', jsonEncode(data));
      await prefs.setString('leave_cache_school', school);
      await prefs.setString('leave_cache_day', _day);
      return result;
    } on TimeoutException {
      return {
        'success': false,
        'code': 'LEAVE_FETCH_TIMEOUT',
        'message':
            'Leave approval status could not be confirmed. Please retry.',
      };
    } catch (_) {
      return {
        'success': false,
        'message': 'Could not load leave approvals from the portal.',
      };
    }
  }

  static Map<String, dynamic> _decode(http.Response response) {
    final data = EcosystemService.decode(response);
    if (data['success'] != true && data['detail'] is Map) {
      return {...Map<String, dynamic>.from(data['detail']), 'success': false};
    }
    return data;
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
    if (_submitting)
      return {
        'success': false,
        'message': 'A leave action is already in progress.',
      };
    _submitting = true;
    final school = _snapshotSchool ?? '';
    _invalidateLive(school);
    try {
      final direct = StudentService.directAttendanceEnabled;
      final session = DirectSchoolSession.leaveApprovals;
      late Map<String, dynamic> result;
      if (direct) {
        final account = (await SecureStorageService.getShaladarpanCreds())['id']
            ?.trim();
        if (session == null ||
            DirectSchoolSession.schoolId != account ||
            school != account)
          return {
            'success': false,
            'code': 'ACCOUNT_CHANGED',
            'submission_attempted': false,
            'message':
                'Fetch and review leaves for the current School login first.',
          };
        result = await session.submit(actions, userConfirmed: true);
        if (!identical(session, DirectSchoolSession.leaveApprovals) ||
            (await SecureStorageService.getShaladarpanCreds())['id']?.trim() !=
                account)
          return LeaveResultMessages.attach({
            'success': false,
            'code': result['submission_attempted'] == true
                ? 'SAVE_UNCONFIRMED'
                : 'ACCOUNT_CHANGED',
            'submission_attempted': result['submission_attempted'] == true,
            'message': 'School session changed. Verify leave actions on the portal before retrying.',
          }, LeaveResultMessages.portalTexts(result));
      } else {
        final response = await http
            .post(
              BackendConfig.uri('/api/shaladarpan/leaves/action'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'actions': actions}),
            )
            .timeout(const Duration(seconds: 90));
        result = _decode(response);
      }
      // A local cache cleanup failure must not replace the portal result.
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('leave_cache_school');
      } catch (_) {}
      ShaladarpanService.invalidateStaffSnapshot();
      return result;
    } on TimeoutException {
      return {
        'success': false,
        'code': 'MUTATION_AMBIGUOUS',
        'message': 'Leave action result is unconfirmed. Refresh the portal before retrying.',
      };
    } catch (_) {
      return {
        'success': false,
        'message': 'Leave action result could not be confirmed. Refresh before retrying.',
      };
    } finally {
      ShaladarpanService.invalidateStaffSnapshot();
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('leave_cache_school');
      } catch (_) {}
      _submitting = false;
    }
  }
}
