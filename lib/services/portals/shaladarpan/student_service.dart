import 'package:shaladarpan/experiments/direct_school_session.dart';
import 'package:shaladarpan/services/core/backend_config.dart';
// lib/tabs/student/student_service.dart

import 'dart:convert';

import '../../../experiments/student_attendance_parity.dart';
import '../../core/direct/mutation_dispatch.dart';
import '../../core/direct/attendance_read_scope.dart';
import 'direct/leave_result_messages.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:shaladarpan/services/core/secure_storage_service.dart';

import 'package:http/http.dart' as http;

class StudentService {
  // Direct mode is explicitly enabled only after a verified on-device login.
  static bool directAttendanceEnabled = false;
  // FastAPI backend base URL
  static String get baseUrl => '${BackendConfig.baseUrl}/api/student';

  // Standard request timeout
  static const Duration _timeout = Duration(seconds: 45);

  // A mutation stays guarded even if the HTTP caller times out. A fresh
  // verified read must settle the hold before another Save can be attempted.
  static bool _saving = false;
  static bool _checkingSubmission = false;
  static int _attendanceEpoch = 0;
  static const Duration _reportTimeout = Duration(seconds: 240);
  static const Duration _saveTimeout = Duration(seconds: 180);

  static final Object _backendReadSession = Object();
  static final Map<(AttendanceReadScope, String), Future<Map<String, dynamic>>>
  _attendanceReads = {};

  /// Local identity check only: this never probes the portal or logs in.
  static Future<AttendanceReadScope?> captureReadScope() async {
    try {
      final credentials = await SecureStorageService.getShaladarpanCreds();
      final school = credentials['id']?.trim() ?? '';
      if (school.isEmpty || _saving) return null;
      if (!directAttendanceEnabled) {
        return AttendanceReadScope(
          school: school,
          session: _backendReadSession,
          identity: baseUrl,
          revision: _attendanceEpoch,
        );
      }
      final service = DirectSchoolSession.attendance;
      if (!DirectSchoolSession.ready ||
          DirectSchoolSession.schoolId != school ||
          service == null)
        return null;
      return AttendanceReadScope(
        school: school,
        session: service,
        identity: service.auth.schoolSessionIdentity,
        revision: _attendanceEpoch,
      );
    } catch (_) {
      return null;
    }
  }

  static String _dateKey(String raw) {
    final value = raw.trim();
    final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(value);
    if (iso != null) {
      return '${iso[3]!.padLeft(2, '0')}/${iso[2]!.padLeft(2, '0')}/${iso[1]}';
    }
    final match = RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{4})$')
        .firstMatch(value);
    if (match == null) return value;
    return '${match[1]!.padLeft(2, '0')}/${match[2]!.padLeft(2, '0')}/${match[3]}';
  }

  // "2A" and class="2", section="A" must have the SAME hold key.
  static String _classKey(String classId, String? section) {
    final cls = classId.trim();
    final number =
        RegExp(r'\d+').firstMatch(cls)?.group(0) ?? cls.toLowerCase();
    final sectionText = (section ?? '').trim();
    final suffix =
        RegExp(r'[A-Za-z]+$').firstMatch(sectionText)?.group(0) ??
        RegExp(r'[A-Za-z]+$').firstMatch(cls)?.group(0) ??
        '';
    return '$number${suffix.toLowerCase()}';
  }

  static String _holdKey(
    String school,
    String date,
    String cls,
    String? section,
  ) =>
      'student_submission_hold/${school.trim()}/${_dateKey(date)}/${_classKey(cls, section)}';

  static Map<String, dynamic> _error(Map<String, dynamic> data, int status) {
    final detail = data['detail'];
    final source = detail is Map ? Map<String, dynamic>.from(detail) : data;
    return {
      ...source,
      'success': false,
      'code': source['code'] ?? '$status',
      'message': _extractErrorMessage(data, status),
    };
  }

  static bool _validRead(
    Map<String, dynamic> data,
    String classId,
    String date,
    String? section,
  ) {
    if (data['success'] != true ||
        data['data_verified'] != true ||
        data['students'] is! List ||
        ((data['students'] as List).isEmpty && !isVerifiedEmptyClass(data))) {
      return false;
    }
    final students = data['students'] as List;
    if (data['total'] != students.length ||
        (data['summary'] is Map &&
            data['summary']['total'] != null &&
            data['summary']['total'] != students.length))
      return false;
    final identities = <String>{};
    for (final value in students) {
      if (value is! Map) return false;
      final row = Map<String, dynamic>.from(value);
      final key = _studentKey(row);
      if (key == 'row::' || !identities.add(key)) return false;
      if (_markedOnPortal(data) && _status(row) == null) return false;
    }
    final requestedNumber = RegExp(r'\d+').firstMatch(classId)?.group(0);
    final receivedNumber = RegExp(r'\d+')
        .firstMatch('${data['classId']}')
        ?.group(0);
    if (requestedNumber == null ||
        requestedNumber != receivedNumber ||
        _dateKey('${data['date']}') != _dateKey(date)) {
      return false;
    }
    final requested = _classKey(classId, section);
    final hasSection = RegExp(r'[A-Za-z]$').hasMatch(requested);
    return !hasSection ||
        requested ==
            _classKey('${data['classId']}', '${data['section'] ?? ''}');
  }

  static bool _markedOnPortal(Map<String, dynamic> data) =>
      data['is_already_marked'] == true &&
      data['attendance_verified'] == true &&
      '${data['attendance_status']}'.toLowerCase() == 'marked';

  static String _studentKey(Map<String, dynamic> row) =>
      StudentAttendanceParity.identity(row);

  /// Empty roster is valid only when the authoritative summary also says zero.
  static bool isVerifiedEmptyClass(Map<String, dynamic> data) =>
      data['success'] == true &&
      data['data_verified'] == true &&
      data['students'] is List &&
      (data['students'] as List).isEmpty &&
      data['total'] == 0 &&
      data['summary'] is Map &&
      (data['summary'] as Map)['total'] == 0;

  static String? _status(Map<String, dynamic> row) {
    final raw = '${row['status'] ?? ''}'.toLowerCase().replaceAll(' ', '');
    if (raw == 'p' || raw == 'present') return 'Present';
    if (raw == 'a' || raw == 'absent') return 'Absent';
    if (raw == 'l' || raw == 'onleave') return 'OnLeave';
    if (raw == 'm' || raw == 'onmedical') return 'OnMedical';
    return null;
  }

  static Map<String, String>? _snapshot(dynamic students) {
    if (students is! List || students.isEmpty) return null;
    final snapshot = <String, String>{};
    for (final item in students) {
      if (item is! Map) return null;
      final row = Map<String, dynamic>.from(item);
      final identity = _studentKey(row);
      final status = _status(row);
      if (status == null || snapshot.containsKey(identity)) return null;
      snapshot[identity] = status;
    }
    return snapshot;
  }

  static bool _sameStudents(dynamic left, dynamic right) {
    final a = _snapshot(left);
    final b = _snapshot(right);
    if (a == null || b == null || a.length != b.length) return false;
    for (final key in a.keys) {
      if (a[key] != b[key]) return false;
    }
    return true;
  }

  static Map<String, dynamic>? _hold(SharedPreferences prefs, String key) {
    final raw = prefs.get(key);
    if (raw == null) return null;
    if (raw is String) {
      try {
        final data = jsonDecode(raw);
        if (data is Map) return Map<String, dynamic>.from(data);
      } catch (_) {}
    }
    // Old boolean holds or malformed metadata must not be automatically cleared.
    return {'legacy': true, 'created_at': 0};
  }

  static bool _holdMatches(
    Map<String, dynamic> hold,
    Map<String, dynamic> portal,
  ) {
    return _markedOnPortal(portal) &&
        _sameStudents(hold['expected'], portal['students']);
  }

  static bool _calendarDate(String date) {
    try {
      StudentAttendanceParity.normalizeDate(_dateKey(date));
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _clearHold(SharedPreferences prefs, String key) async {
    final raw = prefs.getString(key);
    try {
      if (await prefs.remove(key)) return true;
    } catch (_) {}
    // SharedPreferences updates its memory before a platform write completes.
    // Restore the guard if deletion was not acknowledged by durable storage.
    if (raw != null) {
      try {
        await prefs.setString(key, raw);
      } catch (_) {}
    }
    return false;
  }

  static Map<String, dynamic> _unconfirmed(
    Map<String, dynamic> result,
    String code,
    String note, {
    required bool attempted,
  }) => LeaveResultMessages.attach({
    ...result,
    'success': false,
    'code': code,
    'message': note,
    'attendance_verified': false,
    'submission_attempted': attempted,
  }, LeaveResultMessages.portalTexts(result));

  static const Duration _manualReviewDelay = Duration(seconds: 180);

  /// Read current class attendance. Never clear a previous uncertain mutation
  /// just because the GET succeeded: data_verified verifies the READ, not SAVE.
  static Future<Map<String, dynamic>> fetchAttendance({
    required String classId,
    required String date,
    String? section,
  }) async {
    // Only simultaneous identical READs share work. Completed results are not
    // retained here, and SAVE/reconciliation calls are never coalesced.
    final scope = await captureReadScope();
    if (scope == null) {
      return _fetchAttendance(classId: classId, date: date, section: section);
    }
    final key = (scope, '${_dateKey(date)}/${_classKey(classId, section)}');
    final flight = _attendanceReads.putIfAbsent(
      key,
      () => _fetchAttendance(classId: classId, date: date, section: section),
    );
    try {
      final result = await flight;
      if (result['success'] == true && await captureReadScope() != scope) {
        return {
          'success': false,
          'code': 'STALE_ATTENDANCE_READ',
          'message': 'School session changed during fetch. Refresh class data.',
        };
      }
      // Each screen owns its editable copy; sharing a Future must never share
      // mutable student maps between callers.
      return Map<String, dynamic>.from(jsonDecode(jsonEncode(result)) as Map);
    } finally {
      if (identical(_attendanceReads[key], flight))
        _attendanceReads.remove(key);
    }
  }

  static Future<Map<String, dynamic>> _fetchAttendance({
    required String classId,
    required String date,
    String? section,
  }) async {
    try {
      final readEpoch = _attendanceEpoch;
      final before = await SecureStorageService.getShaladarpanCreds();
      final school = before['id']?.trim() ?? '';
      if (school.isEmpty) {
        return {
          'success': false,
          'code': 'ACCOUNT_NOT_READY',
          'message': 'Log in to the school first.',
        };
      }
      final uri = Uri.parse('$baseUrl/attendance/fetch').replace(
        queryParameters: {
          'class_id': classId,
          'date': date,
          if (section != null && section.trim().isNotEmpty) 'section': section,
        },
      );
      Map<String, dynamic> data;
      int statusCode = 200;
      if (directAttendanceEnabled) {
        if (!DirectSchoolSession.available ||
            DirectSchoolSession.schoolId != school) {
          return {
            'success': false,
            'code': 'DIRECT_SESSION_EXPIRED',
            'message': 'Direct school session unavailable. Log in again.',
          };
        }
        data = await DirectSchoolSession.attendance!.fetchStudentsResponse(
          classId: classId,
          date: _dateKey(date),
          section: section,
        );
        if (data['success'] != true) return data;
      } else {
        final response = await http.get(uri).timeout(_timeout);
        statusCode = response.statusCode;
        data = _parseResponseBody(response.body);
      }
      final after = await SecureStorageService.getShaladarpanCreds();
      if (readEpoch != _attendanceEpoch || _saving) {
        return {
          'success': false,
          'code': 'STALE_ATTENDANCE_READ',
          'message': 'Attendance changed during fetch. Refresh after submission settles.',
        };
      }
      if (after['id']?.trim() != school) {
        return {
          'success': false,
          'code': 'ACCOUNT_CHANGED',
          'message': 'School account changed during attendance fetch.',
        };
      }
      if (statusCode != 200) {
        return _error(data, statusCode);
      }
      if (!_validRead(data, classId, date, section)) {
        return {
          'success': false,
          'code': 'INVALID_ATTENDANCE_READ',
          'message':
              'Portal class/date/student data did not match this request.',
        };
      }

      final prefs = await SharedPreferences.getInstance();
      final key = _holdKey(
        school,
        date,
        '${data['classId']}',
        '${data['section'] ?? ''}',
      );
      // This second epoch check covers asynchronous preference access.
      if (readEpoch != _attendanceEpoch || _saving) {
        return {
          'success': false,
          'code': 'STALE_ATTENDANCE_READ',
          'message': 'Attendance changed during fetch. Refresh after submission settles.',
        };
      }
      return {...data, 'submission_on_hold': _hold(prefs, key) != null};
    } catch (e) {
      return {
        'success': false,
        'code': 'NETWORK_ERROR',
        'message': 'Connection error: $e',
      };
    }
  }

  /// User-triggered read-only reconciliation; NEVER submits a Save.
  /// Confirm a successful Save/Update by matching every student status.
  /// When portal state differs, retain the hold until a separate informed review.
  static Future<Map<String, dynamic>> checkPreviousSubmission({
    required String classId,
    required String date,
    String? section,
    bool acknowledgeManualRetry = false,
  }) async {
    if (_saving || _checkingSubmission) {
      return {
        'success': false,
        'code': 'SUBMISSION_BUSY',
        'message': 'An attendance submission is still running.',
      };
    }
    _checkingSubmission = true;
    try {
      final epoch = _attendanceEpoch;
      final before = await SecureStorageService.getShaladarpanCreds();
      final school = before['id']?.trim() ?? '';
      if (school.isEmpty) {
        return {
          'success': false,
          'code': 'ACCOUNT_NOT_READY',
          'message': 'School login is required.',
        };
      }
      final prefs = await SharedPreferences.getInstance();
      final key = _holdKey(school, date, classId, section);
      final metadata = _hold(prefs, key);
      if (metadata == null) {
        return {
          'success': true,
          'resolved': 'not_held',
          'message': 'There is no unresolved submission for this class.',
        };
      }

      // Fetch twice: single transient portal response must never release the hold.
      final first = await _fetchAttendance(
        classId: classId,
        date: date,
        section: section,
      );
      if (!_validRead(first, classId, date, section)) {
        return {
          'success': false,
          'code': 'RECHECK_FAILED',
          'message': 'Portal verification failed. Previous submission is still on hold.',
        };
      }
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      final second = await _fetchAttendance(
        classId: classId,
        date: date,
        section: section,
      );
      if (!_validRead(second, classId, date, section) ||
          !_sameStudents(first['students'], second['students']) ||
          first['is_already_marked'] != second['is_already_marked']) {
        return {
          'success': false,
          'code': 'RECHECK_FAILED',
          'message': 'Portal results are inconsistent. Previous submission remains on hold.',
        };
      }
      final after = await SecureStorageService.getShaladarpanCreds();
      if (_saving ||
          epoch != _attendanceEpoch ||
          after['id']?.trim() != school) {
        return {
          'success': false,
          'code': 'ACCOUNT_CHANGED',
          'message': 'Session changed during verification. Previous submission remains on hold.',
        };
      }
      // Re-read metadata: never clear a different/newer outstanding operation.
      final latest = _hold(prefs, key);
      if (latest == null || jsonEncode(latest) != jsonEncode(metadata)) {
        return {
          'success': false,
          'code': 'STALE_ATTENDANCE_READ',
          'message': 'Submission state changed while checking. Refresh again.',
        };
      }
      if (_holdMatches(metadata, first) && _holdMatches(metadata, second)) {
        if (!await _clearHold(prefs, key)) {
          return {
            'success': false,
            'code': 'LOCAL_STORAGE_ERROR',
            'submission_on_hold': true,
            'attendance_verified': true,
            'message': 'Portal attendance is verified, but the local submission guard could not be cleared. Check again before another Save.',
          };
        }
        return {
          'success': true,
          'resolved': 'applied',
          'message':
              'Previous attendance submission is verified on the portal.',
        };
      }

      // A prior marked attendance can remain marked when an UPDATE failed.
      // Therefore 'marked' alone must NEVER unlock a retry.
      final started = metadata['created_at'];
      final ageMs = started is int
          ? DateTime.now().millisecondsSinceEpoch - started
          : 0;
      final oldEnough =
          metadata['legacy'] == true ||
          ageMs >= _manualReviewDelay.inMilliseconds;
      if (!acknowledgeManualRetry || !oldEnough) {
        return {
          'success': false,
          'code': 'REVIEW_REQUIRED',
          'manual_retry_allowed': oldEnough,
          'message': oldEnough
              ? 'Portal statuses differ from the attempted Save. Review the recorded attendance before authorizing a new attempt.'
              : 'Save outcome is unresolved. Check again later; do not submit a second time.',
        };
      }
      // Explicitly authorized manual recovery after two identical verified reads,
      // never an automatic retry. The caller MUST show a warning/confirmation.
      if (!await _clearHold(prefs, key)) {
        return {
          'success': false,
          'code': 'LOCAL_STORAGE_ERROR',
          'submission_on_hold': true,
          'message': 'The local submission guard could not be cleared. No new Save is authorized.',
        };
      }
      return {
        'success': true,
        'resolved': 'manual_review',
        'message': 'Submission hold released after your explicit review. Check portal statuses before a new Save.',
      };
    } finally {
      _checkingSubmission = false;
    }
  }

  /// A Save and an Update share the same one-POST flow.
  /// The hold stores EXPECTED student identities/statuses before any network I/O.
  static Future<Map<String, dynamic>> saveAttendance(
    Map<String, dynamic> payload, {
    AttendanceReadScope? expectedScope,
  }) async {
    try {
      payload = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(payload)) as Map,
      );
    } catch (_) {
      return {
        'success': false,
        'code': 'INVALID_PAYLOAD',
        'submission_attempted': false,
        'message': 'Attendance payload could not be read. Nothing was sent.',
      };
    }
    if (expectedScope != null && await captureReadScope() != expectedScope) {
      return {
        'success': false,
        'code': 'ACCOUNT_CHANGED',
        'submission_attempted': false,
        'message': 'School session changed. Refresh class data before Save.',
      };
    }
    if (_saving || _checkingSubmission) {
      return {
        'success': false,
        'code': 'SUBMISSION_BUSY',
        'submission_attempted': false,
        'message': 'Attendance submission is already in progress.',
      };
    }
    _saving = true;
    _attendanceEpoch++;
    bool requestMayHaveStarted = false;
    MutationDispatch? directDispatch;
    SharedPreferences? holdPrefs;
    String? registeredHoldKey;
    try {
      final credentials = await SecureStorageService.getShaladarpanCreds();
      final school = credentials['id']?.trim() ?? '';
      final direct = directAttendanceEnabled;
      final boundService = direct ? DirectSchoolSession.attendance : null;
      final boundIdentity = boundService?.auth.schoolSessionIdentity;
      final boundBase = baseUrl;
      Future<bool> sameOwner() async {
        final current = await SecureStorageService.getShaladarpanCreds();
        return current['id']?.trim() == school &&
            current['pass'] == credentials['pass'] &&
            directAttendanceEnabled == direct &&
            (direct
                ? identical(boundService, DirectSchoolSession.attendance) &&
                      boundService?.auth.schoolSessionIdentity ==
                          boundIdentity &&
                      DirectSchoolSession.schoolId == school
                : baseUrl == boundBase);
      }

      if (school.isEmpty) {
        return {
          'success': false,
          'code': 'ACCOUNT_NOT_READY',
          'submission_attempted': false,
          'message': 'Log in to the school first.',
        };
      }
      if (expectedScope != null &&
          (school != expectedScope.school ||
              (directAttendanceEnabled
                  ? !identical(
                          expectedScope.session,
                          DirectSchoolSession.attendance,
                        ) ||
                        DirectSchoolSession
                                .attendance
                                ?.auth
                                .schoolSessionIdentity !=
                            expectedScope.identity
                  : !identical(expectedScope.session, _backendReadSession) ||
                        baseUrl != expectedScope.identity))) {
        return {
          'success': false,
          'code': 'ACCOUNT_CHANGED',
          'submission_attempted': false,
          'message': 'School session changed. Refresh class data before Save.',
        };
      }
      final date = _dateKey('${payload['date'] ?? ''}');
      final cls = '${payload['class_id'] ?? ''}';
      final section = payload['section']?.toString();
      final expected = _snapshot(payload['students']);
      if (!_calendarDate(date) || cls.trim().isEmpty || expected == null) {
        return {
          'success': false,
          'code': 'INVALID_PAYLOAD',
          'submission_attempted': false,
          'message': 'Valid class, date and student statuses are required.',
        };
      }
      final body = jsonEncode({...payload, 'school_id': school});
      final prefs = await SharedPreferences.getInstance();
      final key = _holdKey(school, date, cls, section);
      if (_hold(prefs, key) != null) {
        return {
          'success': false,
          'code': 'MUTATION_AMBIGUOUS',
          'submission_attempted': false,
          'submission_on_hold': true,
          'message': 'Previous Save/Update is unresolved. Verify its result before another submission.',
        };
      }
      holdPrefs = prefs;
      registeredHoldKey = key;
      final stored = await prefs.setString(
        key,
        jsonEncode({
          'created_at': DateTime.now().millisecondsSinceEpoch,
          'expected': payload['students'],
        }),
      );
      if (!stored) {
        await _clearHold(prefs, key);
        return {
          'success': false,
          'code': 'SAVE_PREPARATION_FAILED',
          'submission_attempted': false,
          'message': 'Could not register the submission safety hold. Nothing was sent.',
        };
      }
      if (!await sameOwner()) {
        final cleared = await _clearHold(prefs, key);
        return {
          'success': false,
          'code': 'ACCOUNT_CHANGED',
          'submission_attempted': false,
          'submission_on_hold': !cleared,
          'message': 'School session changed before Save. Nothing was sent.',
        };
      }
      if (expectedScope != null &&
          (directAttendanceEnabled
              ? !identical(
                      expectedScope.session,
                      DirectSchoolSession.attendance,
                    ) ||
                    DirectSchoolSession
                            .attendance
                            ?.auth
                            .schoolSessionIdentity !=
                        expectedScope.identity
              : !identical(expectedScope.session, _backendReadSession) ||
                    baseUrl != expectedScope.identity)) {
        await prefs.remove(key);
        return {
          'success': false,
          'code': 'ACCOUNT_CHANGED',
          'submission_attempted': false,
          'message': 'School session changed. Refresh class data before Save.',
        };
      }
      Map<String, dynamic> result;
      if (direct) {
        if (!DirectSchoolSession.available ||
            DirectSchoolSession.schoolId != school) {
          await prefs.remove(key);
          return {
            'success': false,
            'code': 'DIRECT_SESSION_EXPIRED',
            'submission_attempted': false,
            'message': 'Direct school session unavailable. Log in again.',
          };
        }
        directDispatch = MutationDispatch();
        final requested = (payload['students'] as List)
            .map((row) => Map<String, Object?>.from(row as Map))
            .toList();
        final outcome = await directDispatch.run(
          () => boundService!.save(
            classId: cls,
            date: date,
            section: section,
            students: requested,
            userConfirmed: true,
          ),
        );
        requestMayHaveStarted = directDispatch.mayHaveStarted;
        result = outcome.response.isNotEmpty
            ? outcome.response
            : <String, dynamic>{
                'success': outcome.success,
                'code': outcome.code,
                'message': outcome.message,
                'submission_attempted': outcome.submissionAttempted,
                'attendance_verified': outcome.verified,
                'updatedCount': outcome.updatedCount,
              };
      } else {
        requestMayHaveStarted = true;
        final response = await http
            .post(
              Uri.parse('$baseUrl/attendance/save'),
              headers: {'Content-Type': 'application/json'},
              body: body,
            )
            .timeout(_saveTimeout);
        final data = _parseResponseBody(response.body);
        result = response.statusCode == 200
            ? data
            : _error(data, response.statusCode);
      }
      final attempted = result['submission_attempted'] is bool
          ? result['submission_attempted'] == true
          : requestMayHaveStarted;
      if (result['success'] == true &&
          (!_validRead(result, cls, date, section) ||
              !_markedOnPortal(result) ||
              !_sameStudents(payload['students'], result['students']) ||
              (result['school_id'] != null &&
                  '${result['school_id']}'.trim() != school))) {
        result = _unconfirmed(
          result,
          'SAVE_UNCONFIRMED',
          'Exact class, date and student statuses were not verified on the portal. Check the recorded attendance before retrying.',
          attempted: attempted,
        );
      }
      if (!await sameOwner()) {
        return {
          ..._unconfirmed(
            result,
            attempted ? 'SAVE_UNCONFIRMED' : 'ACCOUNT_CHANGED',
            'School session changed during Save. Verify the previous school separately.',
            attempted: attempted,
          ),
          'submission_on_hold': true,
        };
      }
      var cleanupFailed = false;
      if (result['submission_attempted'] == false ||
          (result['success'] == true &&
              result['attendance_verified'] == true)) {
        cleanupFailed = !await _clearHold(prefs, key);
      }
      return {
        ...result,
        'submission_on_hold': cleanupFailed || _hold(prefs, key) != null,
        if (cleanupFailed) 'verification_message': 'Portal result is retained, but the local submission guard could not be cleared. Use Verify Previous Save before another attempt.',
      };
    } catch (_) {
      requestMayHaveStarted =
          directDispatch?.mayHaveStarted ?? requestMayHaveStarted;
      if (!requestMayHaveStarted &&
          registeredHoldKey != null &&
          holdPrefs != null) {
        try {
          await _clearHold(holdPrefs, registeredHoldKey);
        } catch (_) {
          // Storage failure cannot change the factual dispatch state.
        }
      }
      return {
        'success': false,
        'code': requestMayHaveStarted
            ? 'MUTATION_AMBIGUOUS'
            : 'SAVE_PREPARATION_FAILED',
        'submission_attempted': requestMayHaveStarted,
        'attendance_verified': false,
        'message': requestMayHaveStarted
            ? 'Save outcome is uncertain. Verify recorded attendance before retrying.'
            : 'Could not prepare attendance request. Nothing was sent.',
      };
    } finally {
      _saving = false;
      _attendanceEpoch++;
    }
  }

  /// Summary belongs to the same local session/revision as the register.
  static Future<Map<String, dynamic>> fetchClassSummary({String? date}) async {
    try {
      final scope = await captureReadScope();
      if (scope == null)
        return {
          'success': false,
          'code': 'ACCOUNT_NOT_READY',
          'message': 'Refresh the school login before loading attendance.',
        };
      Map<String, dynamic> result;
      if (directAttendanceEnabled) {
        result = await DirectSchoolSession.attendance!
            .fetchClassSummaryResponse(date: date);
      } else {
        final uri = Uri.parse('$baseUrl/summary').replace(
          queryParameters: {if (date != null && date.isNotEmpty) 'date': date},
        );
        final reply = await http.get(uri).timeout(_timeout);
        final data = _parseResponseBody(reply.body);
        result = reply.statusCode == 200
            ? data
            : _error(data, reply.statusCode);
      }
      if (await captureReadScope() != scope) return _staleReport();
      if (result['success'] == true &&
          date != null &&
          _dateKey('${result['date'] ?? ''}') != _dateKey(date)) {
        return {
          'success': false,
          'code': 'DATE_MISMATCH',
          'message': 'Portal summary date did not match this request.',
        };
      }
      return result;
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  static Map<String, dynamic> _staleReport() => {
    'success': false,
    'code': 'STALE_ATTENDANCE_READ',
    'message':
        'School session or attendance changed during this read. Refresh again.',
  };

  static bool _validReport(Map<String, dynamic> report, String date) {
    if (_dateKey('${report['date'] ?? ''}') != _dateKey(date) ||
        !_calendarDate(date) ||
        report['rows'] is! List ||
        (report['rows'] as List).isEmpty ||
        (report['failedSections'] is List &&
            (report['failedSections'] as List).isNotEmpty) ||
        (report['attendance_verified'] == true &&
            report['pendingSections'] is List &&
            (report['pendingSections'] as List).isNotEmpty))
      return false;
    int? count(dynamic value) {
      final n = value is num ? value : num.tryParse('$value');
      return n != null && n.isFinite && n >= 0 && n == n.round()
          ? n.toInt()
          : null;
    }

    final labels = <String>{};
    for (final row in report['rows'] as List) {
      if (row is! Map) return false;
      final cls = '${row['className'] ?? ''}'.trim();
      final label = '$cls/${row['section'] ?? ''}'.trim().toLowerCase();
      if (cls.isEmpty || !labels.add(label)) return false;
      final values = [
        for (final k in ['boys', 'girls', 'absent', 'leave']) count(row[k]),
      ];
      if (values.any((n) => n == null)) return false;
      final sum = values.fold<int>(0, (a, n) => a + n!);
      final unknown = count(row['presentUnknown'] ?? 0),
          unselected = count(row['unselected'] ?? 0);
      if (unknown == null ||
          unselected == null ||
          (row['total'] != null && count(row['total']) != sum) ||
          (row['enrolled'] != null &&
              count(row['enrolled']) != sum + unknown + unselected) ||
          (report['attendance_verified'] == true && unselected > 0))
        return false;
    }
    return count(report['unknownPresent'] ?? 0) != null;
  }

  static Future<Map<String, dynamic>> fetchSchoolReport({
    required String date,
    void Function(int completed, int total)? onProgress,
  }) async {
    try {
      final scope = await captureReadScope();
      if (scope == null)
        return {
          'success': false,
          'code': 'ACCOUNT_NOT_READY',
          'message': 'Refresh the school login before loading the report.',
        };
      Map<String, dynamic> result;
      if (directAttendanceEnabled) {
        result = await DirectSchoolSession.attendance!.fetchSchoolReport(
          date: date,
          onProgress: onProgress,
        );
      } else if (onProgress == null) {
        final uri = Uri.parse('$baseUrl/school-report')
            .replace(queryParameters: {'date': date});
        final reply = await http.get(uri).timeout(_reportTimeout);
        final data = _parseResponseBody(reply.body);
        result = reply.statusCode == 200
            ? data
            : _error(data, reply.statusCode);
      } else {
        final client = http.Client();
        try {
          result = await _readReportStream(
            client,
            date,
            onProgress,
          ).timeout(_reportTimeout);
        } finally {
          client.close();
        }
      }
      if (await captureReadScope() != scope) return _staleReport();
      if (result['success'] == true && !_validReport(result, date)) {
        return {
          'success': false,
          'code': 'INVALID_REPORT',
          'message': 'Report date, class sections or attendance totals could not be verified completely.',
        };
      }
      return Map<String, dynamic>.from(jsonDecode(jsonEncode(result)) as Map);
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> _readReportStream(
    http.Client client,
    String date,
    void Function(int completed, int total) onProgress,
  ) async {
    final uri = Uri.parse('$baseUrl/school-report')
        .replace(queryParameters: {'date': date, 'stream': 'true'});
    final response = await client.send(http.Request('GET', uri));
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      final data = _parseResponseBody(body);
      return _error(data, response.statusCode);
    }
    if (!(response.headers['content-type'] ?? '').contains(
      'application/x-ndjson',
    )) {
      // Compatibility with the previous backend, which only returns final JSON.
      return _parseResponseBody(await response.stream.bytesToString());
    }
    await for (final line
        in response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      if (line.trim().isEmpty) continue;
      final event = _parseResponseBody(line);
      switch (event['type']) {
        case 'progress':
          final completed = event['completed'];
          final total = event['total'];
          if (completed is int &&
              total is int &&
              total > 0 &&
              completed >= 0 &&
              completed <= total) {
            onProgress(completed, total);
          }
          break;
        case 'result':
          final data = event['data'];
          if (data is! Map)
            throw const FormatException('Invalid report response.');
          return Map<String, dynamic>.from(data);
        case 'error':
          final statusCode = event['status'] is int
              ? event['status'] as int
              : 500;
          return _error({'detail': event['detail']}, statusCode);
        case 'started':
        case 'heartbeat':
          break;
        default:
          throw const FormatException('Invalid report progress response.');
      }
    }
    throw const FormatException('Report connection ended before completion.');
  }

  // Helper: Safely parses JSON response
  static Map<String, dynamic> _parseResponseBody(String body) {
    try {
      if (body.isEmpty) return {};
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      return {"data": decoded};
    } catch (_) {
      return {"raw": body};
    }
  }

  // Helper: Extracts clean error message from FastAPI HTTPException responses
  static String _extractErrorMessage(
    Map<String, dynamic> data,
    int statusCode,
  ) {
    if (data.containsKey('detail')) {
      final detail = data['detail'];
      if (detail is Map && detail.containsKey('message')) {
        return detail['message'].toString();
      } else if (detail is String) {
        return detail;
      }
    }
    if (data.containsKey('message')) {
      return data['message'].toString();
    }
    return "Server returned error (Code: $statusCode)";
  }
}
