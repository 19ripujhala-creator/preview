// lib/services/portals/shaladarpan/shaladarpan_service.dart
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shaladarpan/services/core/secure_storage_service.dart';
import 'package:shaladarpan/services/core/backend_config.dart';
import 'package:shaladarpan/services/core/ecosystem_service.dart';

class ShaladarpanService {
  static String get _baseUrl => BackendConfig.baseUrl;
  static Future<Map<String, dynamic>>? _dashboardSync;
  static bool _staffMutationInFlight = false;
  static int _staffEpoch = 0;
  static final Map<String, Map<String, dynamic>> _staffSnapshots = {};
  static final Map<String, DateTime> _staffSnapshotAt = {};
  static final Map<String, Future<Map<String, dynamic>>> _staffReads = {};
  static void invalidateStaffSnapshot() { _staffEpoch++; _staffSnapshots.clear(); _staffSnapshotAt.clear(); }
  static void _rememberStaff(String school, Map data) {
    final key = '$school/$_todayStr';
    _staffSnapshots[key] = Map<String, dynamic>.from(data);
    _staffSnapshotAt[key] = DateTime.now();
  }

  static bool _isCurrentStaffDocument(Map data, String school, String date) {
    if (data['success'] != true || data['school_id']?.toString() != school ||
        data['date']?.toString() != date || data['staff'] is! List ||
        data['is_already_marked'] is! bool || data['attendance_verified'] is! bool) return false;
    final rows = data['staff'] as List;
    if (rows.isEmpty) return false;
    final ids = <String>{};
    for (final row in rows) {
      if (row is! Map) return false;
      final id = (row['staffId'] ?? '').toString().trim();
      if (!RegExp(r'^\d+$').hasMatch(id) || !ids.add(id)) return false;
    }
    return true;
  }

  static bool isAttendanceConfirmed(Map data) {
    if (data['attendance_verified'] == false || data['is_already_marked'] == false ||
        data['attendance_status'] == 'pending') return false;
    return data['attendance_verified'] == true && data['is_already_marked'] == true;
  }

  static bool isSubmissionConfirmed(Map data) => data['success'] == true &&
      isAttendanceConfirmed(data) && data['data'] is Map && isAttendanceConfirmed(data['data'] as Map);

  static String get _todayStr {
    final now = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    return "${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
  }

  static Future<String> _getEffectiveSchoolId(String? passedId) async {
    if (passedId != null && passedId.trim().isNotEmpty) {
      return passedId.trim();
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('saved_school_id') ??
        prefs.getString('saved_shala_id') ??
        prefs.getString('school_id') ??
        "";
  }

  // =========================================================================
  // 1. LOGIN & UNIVERSAL DASHBOARD SYNC (KPIs + Staff + Leaves)
  // =========================================================================
  static Future<Map<String, dynamic>> loginAndSyncDashboard({
    bool forceRefresh = false,
    bool forceLogin = false,
    void Function(double progress, String message)? onProgress,
  }) async {
    final existing = _dashboardSync;
    if (existing != null) return existing;
    final task = _syncDashboard(forceRefresh, forceLogin, onProgress);
    _dashboardSync = task;
    try {
      return await task;
    } finally {
      if (identical(_dashboardSync, task)) _dashboardSync = null;
    }
  }

  static Future<Map<String, dynamic>> _syncDashboard(
    bool forceRefresh,
    bool forceLogin,
    void Function(double, String)? onProgress,
  ) async {
    Timer? poller;
    bool polling = false;
    bool finished = false;
    final client = http.Client();
    final progressClient = http.Client();
    void notify(double progress, String message) {
      if (finished || onProgress == null) return;
      try {
        onProgress(progress, message);
      } catch (_) {}
    }

    try {
      final creds = await SecureStorageService.getShaladarpanCreds();
      final schoolId = creds['id']?.trim() ?? '';
      final password = creds['pass'] ?? '';
      if (schoolId.isEmpty || password.isEmpty) {
        return {'success': false, 'code': 'EMPTY_CREDENTIALS', 'message': 'Please enter School ID and password.'};
      }
      // Poll only when a screen requested progress; at most one request at a time.
      if (onProgress != null) {
        poller = Timer.periodic(const Duration(seconds: 1), (_) async {
          if (polling || finished) return;
          polling = true;
          try {
            final response = await progressClient
                .get(BackendConfig.uri('/api/shaladarpan/status'))
                .timeout(const Duration(seconds: 2));
            final data = EcosystemService.decode(response);
            if (response.statusCode == 200 && (data['dashboard_progress'] ?? data['progress']) is num) {
              notify(
                (((data['dashboard_progress'] ?? data['progress']) as num).toDouble() / 100).clamp(0.0, 1.0).toDouble(),
                data['message']?.toString() ?? 'Syncing school data...',
              );
            }
          } catch (_) {
          } finally {
            polling = false;
          }
        });
      }
      final response = await client
          .post(
            BackendConfig.uri('/api/shaladarpan/login-sync'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'school_id': schoolId, 'password': password, 'force_refresh': forceRefresh, 'force_login': forceLogin, 'dashboard_only': true}),
          )
          .timeout(const Duration(seconds: 310));
      final result = EcosystemService.decode(response);
      if (response.statusCode != 200 || result['success'] != true) return result;
      final payload = result['data'] is Map ? Map<String, dynamic>.from(result['data']) : result;
      final prefs = await SharedPreferences.getInstance();
      final current = await SecureStorageService.getShaladarpanCreds();
      if (current['id']?.trim() != schoolId) {
        return {'success': false, 'code': 'ACCOUNT_CHANGED', 'message': 'Account changed during sync.'};
      }
      for (final entry in {
        'kpi': 'cached_student_kpi',
        'staff_attendance': 'cached_staff_attendance',
        'pending_leaves': 'cached_pending_leaves',
      }.entries) {
        if (payload[entry.key] is Map && (payload[entry.key] as Map)['success'] != false) {
          await prefs.setString(entry.value, jsonEncode(payload[entry.key]));
        }
      }
      final staff = payload['staff_attendance'];
      if (staff is Map && staff['success'] != false) _rememberStaff(schoolId, staff);
      if (staff is Map && isAttendanceConfirmed(staff)) {
        await prefs.setString('attendance_verified_date', _todayStr);
        await prefs.setBool('attendance_already_marked', true);
      } else {
        await prefs.remove('attendance_already_marked');
        await prefs.remove('attendance_verified_date');
      }
      await prefs.setString('dashboard_cache_school_id', schoolId);
      await prefs.setString('dashboard_cache_date', _todayStr);
      notify(1.0, 'School data synced.');
      return {'success': true, 'data': payload};
    } on TimeoutException {
      return {'success': false, 'code': 'SYNC_TIMEOUT', 'message': 'School sync is taking longer than expected.'};
    } catch (_) {
      return {'success': false, 'code': 'CONNECTION_ERROR', 'message': 'Could not sync School data.'};
    } finally {
      finished = true;
      poller?.cancel();
      progressClient.close();
      client.close();
    }
  }

  // =========================================================================
  // 2. STAFF ATTENDANCE MODULE APIs
  // =========================================================================
  static Future<Map<String, dynamic>> fetchStaffAttendance({String? schoolId, bool forceRefresh = false}) async {
    final school = await _getEffectiveSchoolId(schoolId);
    final current = await SecureStorageService.getShaladarpanCreds();
    if (current['id']?.trim() != school) return {'success': false, 'code': 'ACCOUNT_CHANGED', 'message': 'School account changed.'};
    final key = '$school/$_todayStr';
    final prefs = await SharedPreferences.getInstance();
    final held = prefs.getBool('attendance_submission_hold_${school}_$_todayStr') == true;
    final at = _staffSnapshotAt[key];
    if (!forceRefresh && !held && !_staffMutationInFlight && at != null && DateTime.now().difference(at) < const Duration(seconds: 30) &&
        _isCurrentStaffDocument(_staffSnapshots[key] ?? {}, school, _todayStr)) {
      return {'success': true, 'data': Map<String, dynamic>.from(_staffSnapshots[key]!)};
    }
    final readKey = '$key/$forceRefresh/$_staffEpoch';
    final existing = _staffReads[readKey];
    if (existing != null) return existing;
    final task = _fetchStaffAttendance(schoolId: school, forceRefresh: forceRefresh || held);
    _staffReads[readKey] = task;
    try { return await task; }
    finally { if (identical(_staffReads[readKey], task)) _staffReads.remove(readKey); }
  }

  static Future<Map<String, dynamic>> _fetchStaffAttendance({String? schoolId, bool forceRefresh = false}) async {
    final readEpoch = _staffEpoch;
    final requestedDate = _todayStr;
    try {
      final prefs = await SharedPreferences.getInstance();
      final effectiveSchoolId = await _getEffectiveSchoolId(schoolId);
      if (effectiveSchoolId.isEmpty)
        return {'success': false, 'code': 'EMPTY_SCHOOL_ID', 'message': 'School ID is required.'};

      final res = await http
          .post(
            Uri.parse("$_baseUrl/api/shaladarpan/staff/fetch"),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'school_id': effectiveSchoolId, 'force_refresh': forceRefresh}),
          )
          .timeout(const Duration(seconds: 90));

      if (res.statusCode == 200) {
        final data = EcosystemService.decode(res);
        if (data['success'] == true && data['data'] is Map) {
          final current = await SecureStorageService.getShaladarpanCreds();
          if (current['id']?.trim() != effectiveSchoolId) {
            return {'success': false, 'code': 'ACCOUNT_CHANGED', 'message': 'School account changed during fetch.'};
          }
          final staffData = Map<String, dynamic>.from(data['data']);
          if (readEpoch != _staffEpoch || _staffMutationInFlight || requestedDate != _todayStr) {
            return {'success': false, 'code': 'STALE_ATTENDANCE_READ',
              'message': 'Attendance changed during refresh. Refresh after submission has finished.'};
          }
          if (!_isCurrentStaffDocument(staffData, effectiveSchoolId, requestedDate)) {
            return {'success': false, 'code': 'INVALID_ATTENDANCE_DOCUMENT',
              'message': 'Portal school, date or employee identities could not be verified.'};
          }
          // force_refresh bypasses both frontend snapshots and the backend cache.
          // The backend reads under the attendance resource lease, after mutations settle.
          final verifiedPending = forceRefresh && staffData['is_already_marked'] == false &&
              staffData['attendance_verified'] == false && staffData['attendance_status'] == 'pending' &&
              (staffData['marked_at'] == null || staffData['marked_at'].toString().trim().isEmpty) &&
              (staffData['portal_marking_text'] ?? '').toString().trim().isEmpty;
          if (verifiedPending) {
            await prefs.remove('attendance_submission_hold_${effectiveSchoolId}_$requestedDate');
          }
          _rememberStaff(effectiveSchoolId, staffData);
          await prefs.setString('cached_staff_attendance', jsonEncode(staffData));
          await prefs.setString('dashboard_cache_school_id', effectiveSchoolId);
          await prefs.setString('dashboard_cache_date', _todayStr);

          if (isAttendanceConfirmed(staffData)) {
            await prefs.remove('attendance_submission_hold_${effectiveSchoolId}_$_todayStr');
            await prefs.setString('attendance_verified_date', _todayStr);
            await prefs.setBool('attendance_already_marked', true);
          } else {
            await prefs.remove('attendance_verified_date');
            await prefs.remove('attendance_already_marked');
          }
        }
        return data;
      }
      return EcosystemService.decode(res);
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> submitStaffAttendance(
    List<Map<String, dynamic>> staffList, {
    String? schoolId,
  }) async {
    if (_staffMutationInFlight) return {'success': false, 'code': 'SUBMISSION_BUSY',
      'message': 'Attendance submission is already in progress.'};
    _staffMutationInFlight = true;
    invalidateStaffSnapshot();
    try {
      final prefs = await SharedPreferences.getInstance();
      final effectiveSchoolId = await _getEffectiveSchoolId(schoolId);
      if (effectiveSchoolId.isEmpty)
        return {'success': false, 'code': 'EMPTY_SCHOOL_ID', 'message': 'School ID is required.'};

      final currentAccount = await SecureStorageService.getShaladarpanCreds();
      if (currentAccount['id']?.trim() != effectiveSchoolId) {
        return {'success': false, 'code': 'ACCOUNT_CHANGED', 'message': 'School account does not match this attendance.'};
      }
      final date = _todayStr;
      final holdKey = 'attendance_submission_hold_${effectiveSchoolId}_$date';
      if (prefs.getBool(holdKey) == true) return {'success': false, 'code': 'MUTATION_AMBIGUOUS',
        'message': 'Verify the previous attendance submission on the portal before retrying.'};
      // Persist before POST: a closed app must never blindly replay an uncertain lock.
      await prefs.setBool(holdKey, true);
      final res = await http
          .post(
            Uri.parse("$_baseUrl/api/shaladarpan/staff/submit"),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'school_id': effectiveSchoolId, 'staff_list': staffList, 'attendance_date': date}),
          )
          .timeout(const Duration(seconds: 180));

      final data = EcosystemService.decode(res);
      final detail = data['detail'];
      if (data['submission_attempted'] == false || (detail is Map && detail['submission_attempted'] == false)) await prefs.remove(holdKey);
      final current = await SecureStorageService.getShaladarpanCreds();
      if (current['id']?.trim() != effectiveSchoolId) return {'success': false, 'code': 'ACCOUNT_CHANGED',
        'message': 'School account changed. Verify the previous school attendance separately.'};
      if (res.statusCode == 200) {
        if (isSubmissionConfirmed(data)) {
          await prefs.remove(holdKey);
          await prefs.setString('attendance_verified_date', date);
          await prefs.setBool('attendance_already_marked', true);

          if (data['success'] == true && data['data'] is Map) {
            final freshData = Map<String, dynamic>.from(data['data']);
            await prefs.setString('cached_staff_attendance', jsonEncode(freshData));
            await prefs.setString('dashboard_cache_school_id', effectiveSchoolId);
            await prefs.setString('dashboard_cache_date', _todayStr);
          }
        }
        if (data['success'] == true && !isSubmissionConfirmed(data)) {
          return {'success': false, 'code': 'SAVE_UNCONFIRMED', 'submission_attempted': true,
            'message': 'Portal attendance has not been confirmed. Refresh before retrying.'};
        }
        return data;
      }
      return data;
    } catch (_) {
      return {
        'success': false,
        'code': 'MUTATION_AMBIGUOUS',
        'message': 'Submission result is unknown. Verify portal attendance before retrying.',
      };
    } finally {
      _staffMutationInFlight = false;
    }
  }

  // =========================================================================
  // 3. OFFLINE / FALLBACK COMPLIANCE
  // =========================================================================
  static Future<bool> submitAttendance({
    required Map<String, dynamic> attendancePayload,
    required bool isOnline,
  }) async {
    return false; // No successful submission can be claimed by this unimplemented API.
  }
}
