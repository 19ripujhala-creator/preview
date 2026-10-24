import 'category_enrolment_service.dart';
import '../../../experiments/direct_school_session.dart';
import 'student_service.dart';
import 'ranking_status_service.dart';

// lib/services/portals/shaladarpan/shaladarpan_service.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shaladarpan/services/core/secure_storage_service.dart';
import 'package:shaladarpan/services/core/backend_config.dart';
import 'package:shaladarpan/services/core/ecosystem_service.dart';

class ShaladarpanService {
  static Future<Map<String, dynamic>> fetchCategoryEnrolment({
    String? schoolId,
    String? session,
  }) => CategoryEnrolmentService.fetch(schoolId: schoolId, session: session);

  static String get _baseUrl => BackendConfig.baseUrl;
  static Future<Map<String, dynamic>>? _dashboardSync;
  static Future<Map<String, dynamic>>? _directDashboardSync;
  static Object? _directDashboardSession;
  static bool _staffMutationInFlight = false;
  static int _staffEpoch = 0;
  static bool _staffCacheDirectMode = false;
  static Object? _staffCacheDirectSession;
  static final Map<String, Map<String, dynamic>> _staffSnapshots = {};
  static final Map<String, DateTime> _staffSnapshotAt = {};
  static final Map<String, Future<Map<String, dynamic>>> _staffReads = {};
  static void invalidateStaffSnapshot() {
    _staffEpoch++;
    _staffSnapshots.clear();
    _staffSnapshotAt.clear();
  }

  static Map<String, dynamic> _copyStaffDocument(Map data) =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(data)) as Map);

  static void _rememberStaff(String school, Map data) {
    final key = '$school/$_todayStr';
    _staffSnapshots[key] = _copyStaffDocument(data);
    _staffSnapshotAt[key] = DateTime.now();
  }

  static bool _isCurrentStaffDocument(Map data, String school, String date) {
    if (data['success'] != true ||
        data['school_id']?.toString() != school ||
        data['date']?.toString() != date ||
        data['staff'] is! List ||
        data['is_already_marked'] is! bool ||
        data['attendance_verified'] is! bool)
      return false;
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
    if (data['attendance_verified'] == false ||
        data['is_already_marked'] == false ||
        data['attendance_status'] == 'pending')
      return false;
    return data['attendance_verified'] == true &&
        data['is_already_marked'] == true;
  }

  static bool isSubmissionConfirmed(Map data) =>
      data['success'] == true &&
      isAttendanceConfirmed(data) &&
      data['data'] is Map &&
      isAttendanceConfirmed(data['data'] as Map);

  static String get _todayStr {
    final now = DateTime.now().toUtc().add(
      const Duration(hours: 5, minutes: 30),
    );
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
    if (StudentService.directAttendanceEnabled) {
      final session = DirectSchoolSession.studentKpi;
      if (session != null &&
          identical(session, _directDashboardSession) &&
          _directDashboardSync != null) {
        return _directDashboardSync!;
      }
      final task = _syncDirectDashboard(onProgress);
      _directDashboardSession = session;
      _directDashboardSync = task;
      try {
        return await task;
      } finally {
        if (identical(_directDashboardSync, task)) {
          _directDashboardSync = null;
          _directDashboardSession = null;
        }
      }
    }
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

  static Future<Map<String, dynamic>> _syncDirectDashboard(
    void Function(double, String)? onProgress,
  ) async {
    final creds = await SecureStorageService.getShaladarpanCreds();
    final school = creds['id']?.trim() ?? '';
    final kpi = DirectSchoolSession.studentKpi,
        staff = DirectSchoolSession.staffAttendance,
        monthly = DirectSchoolSession.monthlyTasks;
    if (!DirectSchoolSession.available ||
        kpi == null ||
        staff == null ||
        monthly == null) {
      return {
        'success': false,
        'code': 'SESSION_EXPIRED',
        'message': 'Direct school session unavailable.',
      };
    }
    if (school.isEmpty || DirectSchoolSession.schoolId != school) {
      return {
        'success': false,
        'code': 'ACCOUNT_MISMATCH',
        'message': 'Requested school differs from the logged-in school.',
      };
    }
    void notify(double progress, String message) {
      try {
        onProgress?.call(progress, message);
      } catch (_) {}
    }

    notify(0.2, 'Opening Student Attendance metrics...');
    final results = await Future.wait([
      kpi.fetchDashboard(),
      fetchStaffAttendance(schoolId: school, forceRefresh: true),
      monthly.collectRankingStatus(school),
    ]);
    final current = await SecureStorageService.getShaladarpanCreds();
    if (!StudentService.directAttendanceEnabled ||
        current['id']?.trim() != school ||
        DirectSchoolSession.schoolId != school ||
        !identical(kpi, DirectSchoolSession.studentKpi) ||
        !identical(staff, DirectSchoolSession.staffAttendance) ||
        !identical(monthly, DirectSchoolSession.monthlyTasks)) {
      return {
        'success': false,
        'code': 'ACCOUNT_CHANGED',
        'message': 'Account changed during sync.',
      };
    }
    final data = <String, dynamic>{'school_id': school, ...results[2]};
    await RankingStatusService.store(school, data['ranking_status']);
    RankingStatusService.rememberForm(school, data['ranking_form']);
    final errors = <String, dynamic>{};
    for (final entry in {
      'kpi': results[0],
      'staff_attendance': results[1],
    }.entries) {
      final result = entry.value;
      final payload = result['payload'] ?? result['data'] ?? result;
      data[entry.key] = payload;
      if (result['success'] != true) errors[entry.key] = result;
    }
    if (errors.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_student_kpi', jsonEncode(data['kpi']));
      await prefs.setString('dashboard_cache_school_id', school);
      await prefs.setString('dashboard_cache_date', _todayStr);
    }
    notify(1, 'School data synced.');
    return {
      'success': errors.isEmpty,
      'partial': errors.isNotEmpty,
      'data': data,
      'errors': errors,
      'message': errors.isEmpty
          ? ''
          : errors.values.first['message'] ??
                'Some portal modules could not be fetched.',
    };
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
        return {
          'success': false,
          'code': 'EMPTY_CREDENTIALS',
          'message': 'Please enter School ID and password.',
        };
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
            if (response.statusCode == 200 &&
                (data['dashboard_progress'] ?? data['progress']) is num) {
              notify(
                (((data['dashboard_progress'] ?? data['progress']) as num)
                            .toDouble() /
                        100)
                    .clamp(0.0, 1.0)
                    .toDouble(),
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
            body: jsonEncode({
              'school_id': schoolId,
              'password': password,
              'force_refresh': forceRefresh,
              'force_login': forceLogin,
              'dashboard_only': true,
            }),
          )
          .timeout(const Duration(seconds: 310));
      final result = EcosystemService.decode(response);
      if (response.statusCode != 200) return result;
      final payload = result['data'] is Map
          ? Map<String, dynamic>.from(result['data'])
          : result;
      final prefs = await SharedPreferences.getInstance();
      final current = await SecureStorageService.getShaladarpanCreds();
      if (current['id']?.trim() != schoolId) {
        return {
          'success': false,
          'code': 'ACCOUNT_CHANGED',
          'message': 'Account changed during sync.',
        };
      }
      await RankingStatusService.store(schoolId, payload['ranking_status']);
      RankingStatusService.rememberForm(schoolId, payload['ranking_form']);
      if (result['success'] != true) return result;
      for (final entry in {
        'kpi': 'cached_student_kpi',
        'staff_attendance': 'cached_staff_attendance',
        'pending_leaves': 'cached_pending_leaves',
      }.entries) {
        if (payload[entry.key] is Map &&
            (payload[entry.key] as Map)['success'] != false) {
          await prefs.setString(entry.value, jsonEncode(payload[entry.key]));
        }
      }
      final staff = payload['staff_attendance'];
      if (staff is Map && staff['success'] != false)
        _rememberStaff(schoolId, staff);
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
      return {
        'success': false,
        'code': 'SYNC_TIMEOUT',
        'message': 'School sync is taking longer than expected.',
      };
    } catch (_) {
      return {
        'success': false,
        'code': 'CONNECTION_ERROR',
        'message': 'Could not sync School data.',
      };
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
  static Future<Map<String, dynamic>> fetchStaffAttendance({
    String? schoolId,
    bool forceRefresh = false,
  }) async {
    final direct = StudentService.directAttendanceEnabled;
    final session = direct ? DirectSchoolSession.staffAttendance : null;
    if (_staffCacheDirectMode != direct ||
        !identical(_staffCacheDirectSession, session)) {
      invalidateStaffSnapshot();
      _staffCacheDirectMode = direct;
      _staffCacheDirectSession = session;
    }
    if (direct && session == null) {
      return {
        'success': false,
        'code': 'SESSION_EXPIRED',
        'message': 'Direct School login is required.',
      };
    }
    final school = await _getEffectiveSchoolId(schoolId);
    final current = await SecureStorageService.getShaladarpanCreds();
    if (current['id']?.trim() != school)
      return {
        'success': false,
        'code': 'ACCOUNT_CHANGED',
        'message': 'School account changed.',
      };
    final key = '$school/$_todayStr';
    final prefs = await SharedPreferences.getInstance();
    final held =
        prefs.getBool('attendance_submission_hold_${school}_$_todayStr') ==
        true;
    final at = _staffSnapshotAt[key];
    // A negative age means the device clock moved backwards: never trust it.
    final snapshotAge = at == null ? null : DateTime.now().difference(at);
    if (!forceRefresh &&
        !held &&
        !_staffMutationInFlight &&
        snapshotAge != null &&
        !snapshotAge.isNegative &&
        snapshotAge < const Duration(seconds: 30) &&
        _isCurrentStaffDocument(
          _staffSnapshots[key] ?? {},
          school,
          _todayStr,
        )) {
      return {
        'success': true,
        'data': _copyStaffDocument(_staffSnapshots[key]!),
      };
    }
    final readKey = '$key/$forceRefresh/$_staffEpoch';
    final existing = _staffReads[readKey];
    if (existing != null) return existing;
    final task = _fetchStaffAttendance(
      schoolId: school,
      forceRefresh: forceRefresh || held,
    );
    _staffReads[readKey] = task;
    try {
      return await task;
    } finally {
      if (identical(_staffReads[readKey], task)) _staffReads.remove(readKey);
    }
  }

  static Future<Map<String, dynamic>> _fetchStaffAttendance({
    String? schoolId,
    bool forceRefresh = false,
  }) async {
    final readEpoch = _staffEpoch;
    final requestedDate = _todayStr;
    final direct = StudentService.directAttendanceEnabled;
    final directSession = DirectSchoolSession.staffAttendance;
    try {
      final prefs = await SharedPreferences.getInstance();
      final effectiveSchoolId = await _getEffectiveSchoolId(schoolId);
      if (effectiveSchoolId.isEmpty)
        return {
          'success': false,
          'code': 'EMPTY_SCHOOL_ID',
          'message': 'School ID is required.',
        };

      late Map<String, dynamic> data;
      late int responseStatus;
      if (direct) {
        if (!DirectSchoolSession.available ||
            DirectSchoolSession.schoolId != effectiveSchoolId ||
            DirectSchoolSession.staffAttendance == null) {
          return {
            'success': false,
            'code': 'SESSION_EXPIRED',
            'message': 'Direct School login is required.',
          };
        }
        final raw = await directSession!.fetch();
        data = raw['success'] == true ? {'success': true, 'data': raw} : raw;
        responseStatus = 200;
      } else {
        final res = await http
            .post(
              Uri.parse("$_baseUrl/api/shaladarpan/staff/fetch"),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'school_id': effectiveSchoolId,
                'force_refresh': forceRefresh,
              }),
            )
            .timeout(const Duration(seconds: 90));
        data = EcosystemService.decode(res);
        responseStatus = res.statusCode;
      }
      if (responseStatus == 200) {
        if (data['success'] == true && data['data'] is Map) {
          final current = await SecureStorageService.getShaladarpanCreds();
          if (current['id']?.trim() != effectiveSchoolId) {
            return {
              'success': false,
              'code': 'ACCOUNT_CHANGED',
              'message': 'School account changed during fetch.',
            };
          }
          if (StudentService.directAttendanceEnabled != direct ||
              (direct &&
                  !identical(
                    directSession,
                    DirectSchoolSession.staffAttendance,
                  ))) {
            return {
              'success': false,
              'code': 'ACCOUNT_CHANGED',
              'message': 'School session changed during fetch.',
            };
          }
          final staffData = Map<String, dynamic>.from(data['data']);
          if (readEpoch != _staffEpoch ||
              _staffMutationInFlight ||
              requestedDate != _todayStr) {
            return {
              'success': false,
              'code': 'STALE_ATTENDANCE_READ',
              'message': 'Attendance changed during refresh. Refresh after submission has finished.',
            };
          }
          if (!_isCurrentStaffDocument(
            staffData,
            effectiveSchoolId,
            requestedDate,
          )) {
            return {
              'success': false,
              'code': 'INVALID_ATTENDANCE_DOCUMENT',
              'message': 'Portal school, date or employee identities could not be verified.',
            };
          }
          // force_refresh bypasses both frontend snapshots and the backend cache.
          // The backend reads under the attendance resource lease, after mutations settle.
          final verifiedPending =
              forceRefresh &&
              staffData['is_already_marked'] == false &&
              staffData['attendance_verified'] == false &&
              staffData['attendance_status'] == 'pending' &&
              (staffData['marked_at'] == null ||
                  staffData['marked_at'].toString().trim().isEmpty) &&
              (staffData['portal_marking_text'] ?? '')
                  .toString()
                  .trim()
                  .isEmpty;
          if (verifiedPending) {
            await prefs.remove(
              'attendance_submission_hold_${effectiveSchoolId}_$requestedDate',
            );
          }
          _rememberStaff(effectiveSchoolId, staffData);
          await prefs.setString(
            'cached_staff_attendance',
            jsonEncode(staffData),
          );
          await prefs.setString('dashboard_cache_school_id', effectiveSchoolId);
          await prefs.setString('dashboard_cache_date', _todayStr);

          if (isAttendanceConfirmed(staffData)) {
            await prefs.remove(
              'attendance_submission_hold_${effectiveSchoolId}_$_todayStr',
            );
            await prefs.setString('attendance_verified_date', _todayStr);
            await prefs.setBool('attendance_already_marked', true);
          } else {
            await prefs.remove('attendance_verified_date');
            await prefs.remove('attendance_already_marked');
          }
        }
        return data;
      }
      return data;
    } catch (e) {
      debugPrint('Staff attendance fetch failed: $e');
      return {
        'success': false,
        'message': 'Staff attendance could not be loaded. Please try again.',
      };
    }
  }

  static Map<String, dynamic> _unconfirmedStaffSubmission(
    Map<String, dynamic> source,
    String code,
    String backendMessage,
  ) {
    final portal =
        source['portal_message']?.toString() ??
        (source['message_source'] == 'portal'
            ? source['message']?.toString()
            : null);
    final hasPortal = portal?.isNotEmpty == true;
    return {
      ...source,
      'success': false,
      'code': code,
      'attendance_verified': false,
      'submission_attempted': source['submission_attempted'] != false,
      'requires_verification': source['submission_attempted'] != false,
      'message': hasPortal ? portal : backendMessage,
      'message_source': hasPortal ? 'portal' : 'backend',
      if (hasPortal) ...{
        'portal_message': portal,
        'backend_message': backendMessage,
      },
    };
  }

  static Future<Map<String, dynamic>> submitStaffAttendance(
    List<Map<String, dynamic>> staffList, {
    String? schoolId,
    String? attendanceDate,
  }) async {
    if (_staffMutationInFlight)
      return {
        'success': false,
        'code': 'SUBMISSION_BUSY',
        'message': 'Attendance submission is already in progress.',
      };
    _staffMutationInFlight = true;
    invalidateStaffSnapshot();
    var dispatched = false;
    try {
      // Freeze the reviewed payload before any storage/network await.
      staffList = (jsonDecode(jsonEncode(staffList)) as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      final prefs = await SharedPreferences.getInstance();
      final effectiveSchoolId = await _getEffectiveSchoolId(schoolId);
      if (effectiveSchoolId.isEmpty)
        return {
          'success': false,
          'code': 'EMPTY_SCHOOL_ID',
          'message': 'School ID is required.',
        };

      final currentAccount = await SecureStorageService.getShaladarpanCreds();
      if (currentAccount['id']?.trim() != effectiveSchoolId) {
        return {
          'success': false,
          'code': 'ACCOUNT_CHANGED',
          'message': 'School account does not match this attendance.',
        };
      }
      final date = attendanceDate ?? _todayStr;
      if (date != _todayStr) {
        return {
          'success': false,
          'code': 'STALE_ATTENDANCE',
          'submission_attempted': false,
          'message': 'Attendance belongs to a different date. Refresh before submitting.',
        };
      }
      final holdKey = 'attendance_submission_hold_${effectiveSchoolId}_$date';
      if (prefs.getBool(holdKey) == true)
        return {
          'success': false,
          'code': 'MUTATION_AMBIGUOUS',
          'message': 'Verify the previous attendance submission on the portal before retrying.',
        };
      // Persist before POST: a closed app must never blindly replay an uncertain lock.
      if (!await prefs.setBool(holdKey, true)) {
        await prefs.remove(holdKey);
        return {
          'success': false,
          'code': 'LOCAL_STORAGE_ERROR',
          'submission_attempted': false,
          'message':
              'Submission safety state could not be stored. Nothing was sent.',
        };
      }
      if (date != _todayStr) {
        await prefs.remove(holdKey);
        return {
          'success': false,
          'code': 'STALE_ATTENDANCE',
          'submission_attempted': false,
          'message': 'Attendance date changed. Refresh before submitting.',
        };
      }
      late Map<String, dynamic> data;
      late int responseStatus;
      if (StudentService.directAttendanceEnabled) {
        if (!DirectSchoolSession.available ||
            DirectSchoolSession.schoolId != effectiveSchoolId ||
            DirectSchoolSession.staffAttendance == null) {
          await prefs.remove(holdKey);
          return {
            'success': false,
            'code': 'SESSION_EXPIRED',
            'submission_attempted': false,
            'message': 'Direct School login is required.',
          };
        }
        dispatched = true;
        data = await DirectSchoolSession.staffAttendance!.submit(
          staffList,
          attendanceDate: date,
          userConfirmed: true,
        );
        responseStatus = 200;
      } else {
        dispatched = true;
        final res = await http
            .post(
              Uri.parse("$_baseUrl/api/shaladarpan/staff/submit"),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'school_id': effectiveSchoolId,
                'staff_list': staffList,
                'attendance_date': date,
              }),
            )
            .timeout(const Duration(seconds: 180));
        data = EcosystemService.decode(res);
        responseStatus = res.statusCode;
      }
      final detail = data['detail'];
      if (data['submission_attempted'] == false ||
          (detail is Map && detail['submission_attempted'] == false))
        await prefs.remove(holdKey);
      final current = await SecureStorageService.getShaladarpanCreds();
      if (current['id']?.trim() != effectiveSchoolId) {
        return _unconfirmedStaffSubmission(
          data,
          'ACCOUNT_CHANGED',
          'School account changed. Verify the previous school attendance separately.',
        );
      }
      if (responseStatus == 200) {
        if (isSubmissionConfirmed(data)) {
          final readback = data['data'] as Map;
          final expected = staffList
              .map((row) => row['staffId']?.toString().trim())
              .toSet();
          final actual = readback['staff'] is List
              ? (readback['staff'] as List)
                    .whereType<Map>()
                    .map((row) => row['staffId']?.toString().trim())
                    .toSet()
              : <String?>{};
          if (!_isCurrentStaffDocument(readback, effectiveSchoolId, date) ||
              expected.length != staffList.length ||
              expected.length != actual.length ||
              !expected.containsAll(actual)) {
            return _unconfirmedStaffSubmission(
              data,
              'SAVE_UNCONFIRMED',
              'Submitted school, date or staff identities did not match portal readback. Refresh and verify before retrying.',
            );
          }
          await prefs.remove(holdKey);
          await prefs.setString('attendance_verified_date', date);
          await prefs.setBool('attendance_already_marked', true);

          if (data['success'] == true && data['data'] is Map) {
            final freshData = Map<String, dynamic>.from(data['data']);
            await prefs.setString(
              'cached_staff_attendance',
              jsonEncode(freshData),
            );
            await prefs.setString(
              'dashboard_cache_school_id',
              effectiveSchoolId,
            );
            await prefs.setString('dashboard_cache_date', _todayStr);
          }
        }
        if (data['success'] == true && !isSubmissionConfirmed(data)) {
          return _unconfirmedStaffSubmission(
            data,
            'SAVE_UNCONFIRMED',
            'Portal attendance has not been confirmed. Refresh before retrying.',
          );
        }
        return data;
      }
      return data;
    } catch (_) {
      return {
        'success': false,
        'code': dispatched ? 'MUTATION_AMBIGUOUS' : 'LOCAL_STORAGE_ERROR',
        'submission_attempted': dispatched,
        'requires_verification': dispatched,
        'message': dispatched
            ? 'Submission result is unknown. Verify portal attendance before retrying.'
            : 'Submission could not be prepared. Nothing was sent.',
      };
    } finally {
      // Reject a read admitted during this mutation even if its response arrives
      // after the mutation settled. It must not replace verified saved state.
      invalidateStaffSnapshot();
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
