import 'package:shaladarpan/experiments/direct_school_session.dart';
import 'package:shaladarpan/services/core/backend_config.dart';
// lib/tabs/student/student_service.dart

import 'dart:convert';

import '../../../experiments/student_attendance_parity.dart';
import '../../core/direct/mutation_dispatch.dart';
import '../../core/direct/attendance_read_scope.dart';

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
  static int _attendanceEpoch = 0;
  static const Duration _reportTimeout = Duration(seconds: 240);
  static const Duration _saveTimeout = Duration(seconds: 180);

  static final Object _backendReadSession = Object();
  static final Map<(AttendanceReadScope, String), Future<Map<String, dynamic>>>
  _attendanceReads = {};
  static final Map<(AttendanceReadScope, String), List<bool Function()>>
  _attendanceReadWaiters = {};

  static dynamic _cloneValue(dynamic value) {
    if (value is Map) {
      return <String, dynamic>{
        for (final entry in value.entries)
          entry.key.toString(): _cloneValue(entry.value),
      };
    }
    if (value is List) {
      return [for (final item in value) _cloneValue(item)];
    }
    return value;
  }

  static Map<String, dynamic> _cloneMap(Map<String, dynamic> source) =>
      Map<String, dynamic>.from(_cloneValue(source) as Map);

  static String _scopeIdentity(String? sessionIdentity) =>
      '${sessionIdentity ?? ''}/credentials/${SecureStorageService.schoolIdentityRevision}';

  /// Local identity only. One cold storage read; warm guards use memory.
  static ({int revision, String? date, List<Map<String, dynamic>> classes})?
  get lastSummarySnapshot => directAttendanceEnabled
      ? DirectSchoolSession.attendance?.lastSummarySnapshot
      : null;

  static AttendanceReadScope? captureReadScopeNow() {
    final school = SecureStorageService.schoolIdentityNow;
    if (school == null || school.isEmpty || _saving) return null;
    if (!directAttendanceEnabled) {
      return AttendanceReadScope(
        school: school,
        session: _backendReadSession,
        identity: _scopeIdentity(baseUrl),
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
      identity: _scopeIdentity(service.auth.schoolSessionIdentity),
      revision: _attendanceEpoch,
    );
  }

  static Future<AttendanceReadScope?> captureReadScope() async {
    try {
      await SecureStorageService.getShaladarpanIdentity();
      return captureReadScopeNow();
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

  static String _classNumberKey(String classId) {
    final cls = classId.trim();
    return RegExp(r'\d+').firstMatch(cls)?.group(0) ?? cls.toLowerCase();
  }

  static String _sectionSuffix(String classId, String? section) {
    final cls = classId.trim();
    final sectionText = (section ?? '').trim();
    final suffix =
        RegExp(r'[A-Za-z]+$').firstMatch(sectionText)?.group(0) ??
        RegExp(r'[A-Za-z]+$').firstMatch(cls)?.group(0) ??
        '';
    return suffix.toLowerCase();
  }

  // "2A" and class="2", section="A" must have the SAME hold key.
  static String _classKey(String classId, String? section) =>
      '${_classNumberKey(classId)}${_sectionSuffix(classId, section)}';

  static String _holdPrefix(String school, String date) =>
      'student_submission_hold/${school.trim()}/${_dateKey(date)}/';

  static String _holdKey(
    String school,
    String date,
    String cls,
    String? section,
  ) => '${_holdPrefix(school, date)}${_classKey(cls, section)}';

  static List<String> _relatedHoldKeys(
    SharedPreferences prefs,
    String school,
    String date,
    String cls,
    String? section, {
    String? resolvedClassId,
    String? resolvedSection,
  }) {
    final prefix = _holdPrefix(school, date);
    final number = _classNumberKey(cls);
    final classOnlyKey = '$prefix$number';
    final exactKey = _holdKey(school, date, cls, section);
    final suffix = _sectionSuffix(cls, section);
    final resolvedSuffix = resolvedClassId == null
        ? ''
        : _sectionSuffix(resolvedClassId, resolvedSection);
    final keys = <String>{exactKey, classOnlyKey};
    if (resolvedClassId != null && resolvedClassId.trim().isNotEmpty) {
      keys.add(_holdKey(school, date, resolvedClassId, resolvedSection));
    }
    if (suffix.isEmpty && resolvedSuffix.isEmpty) {
      final pattern = RegExp(
        '^${RegExp.escape(prefix)}${RegExp.escape(number)}[a-z]+\$',
      );
      for (final k in prefs.getKeys()) {
        if (pattern.hasMatch(k)) keys.add(k);
      }
    }
    return [
      for (final k in keys)
        if (_hold(prefs, k) != null) k,
    ];
  }

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

  static Set<String>? _rosterKeys(dynamic students) {
    if (students is! List || students.isEmpty) return null;
    final keys = <String>{};
    for (final item in students) {
      if (item is! Map) return null;
      final row = Map<String, dynamic>.from(item);
      final identity = _studentKey(row).trim();
      if (identity.isEmpty || !keys.add(identity)) return null;
    }
    return keys;
  }

  static bool _sameRoster(dynamic left, dynamic right) {
    final a = _rosterKeys(left);
    final b = _rosterKeys(right);
    if (a == null || b == null || a.length != b.length) return false;
    return a.containsAll(b);
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

  static const Duration _manualReviewDelay = Duration(seconds: 180);

  /// Read current class attendance. Never clear a previous uncertain mutation
  /// just because the GET succeeded: data_verified verifies the READ, not SAVE.
  static Future<Map<String, dynamic>> fetchAttendance({
    required String classId,
    required String date,
    String? section,
    bool Function()? shouldContinue,
  }) async {
    final waiter = shouldContinue ?? () => true;
    if (!waiter()) {
      return {
        'success': false,
        'code': 'STALE_ATTENDANCE_READ',
        'message': 'Attendance read superseded by a newer class selection.',
      };
    }
    // Only simultaneous identical READs share work. Completed results are not
    // retained here, and SAVE/reconciliation calls are never coalesced.
    final scope = captureReadScopeNow() ?? await captureReadScope();
    if (!waiter()) {
      return {
        'success': false,
        'code': 'STALE_ATTENDANCE_READ',
        'message': 'Attendance read superseded by a newer class selection.',
      };
    }
    if (scope == null) {
      return _fetchAttendance(
        classId: classId,
        date: date,
        section: section,
        shouldContinue: shouldContinue,
      );
    }
    final key = (scope, '${_dateKey(date)}/${_classKey(classId, section)}');
    final waiters = _attendanceReadWaiters.putIfAbsent(key, () => []);
    waiters.add(waiter);
    final flight = _attendanceReads.putIfAbsent(
      key,
      () => _fetchAttendance(
        classId: classId,
        date: date,
        section: section,
        shouldContinue: () {
          final active = _attendanceReadWaiters[key];
          return active == null || active.isEmpty || active.any((fn) => fn());
        },
      ),
    );
    try {
      final result = await flight;
      if (!waiter()) {
        return {
          'success': false,
          'code': 'STALE_ATTENDANCE_READ',
          'message': 'Attendance read superseded by a newer class selection.',
        };
      }
      if (result['success'] == true && await captureReadScope() != scope) {
        return {
          'success': false,
          'code': 'STALE_ATTENDANCE_READ',
          'message': 'School session changed during fetch. Refresh class data.',
        };
      }
      // Each screen owns its editable copy; sharing a Future must never share
      // mutable student maps between callers.
      return _cloneMap(result);
    } finally {
      waiters.remove(waiter);
      if (identical(_attendanceReads[key], flight)) {
        _attendanceReads.remove(key);
        _attendanceReadWaiters.remove(key);
      }
    }
  }

  static Future<Map<String, dynamic>> _fetchAttendance({
    required String classId,
    required String date,
    String? section,
    bool Function()? shouldContinue,
  }) async {
    try {
      if (shouldContinue != null && !shouldContinue()) {
        return {
          'success': false,
          'code': 'STALE_ATTENDANCE_READ',
          'message': 'Attendance read superseded by a newer class selection.',
        };
      }
      final readEpoch = _attendanceEpoch;
      final school = await SecureStorageService.getShaladarpanIdentity();
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
          shouldContinue: shouldContinue,
        );
        if (data['success'] != true) return data;
      } else {
        final response = await http.get(uri).timeout(_timeout);
        statusCode = response.statusCode;
        data = _parseResponseBody(response.body);
      }
      if (shouldContinue != null && !shouldContinue()) {
        return {
          'success': false,
          'code': 'STALE_ATTENDANCE_READ',
          'message': 'Attendance read superseded by a newer class selection.',
        };
      }
      final after = await SecureStorageService.getShaladarpanIdentity();
      if (readEpoch != _attendanceEpoch || _saving) {
        return {
          'success': false,
          'code': 'STALE_ATTENDANCE_READ',
          'message': 'Attendance changed during fetch. Refresh after submission settles.',
        };
      }
      if (after != school) {
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
              data['data_verified'] != true &&
                  data['warning'] is String &&
                  (data['warning'] as String).trim().isNotEmpty
              ? 'Attendance data could not be verified: ${data['warning']}'
              : 'Portal class/date/student data did not match this request.',
        };
      }

      final prefs = await SharedPreferences.getInstance();
      // This second epoch check covers asynchronous preference access.
      if (readEpoch != _attendanceEpoch || _saving) {
        return {
          'success': false,
          'code': 'STALE_ATTENDANCE_READ',
          'message': 'Attendance changed during fetch. Refresh after submission settles.',
        };
      }
      final held = _relatedHoldKeys(
        prefs,
        school,
        date,
        classId,
        section,
        resolvedClassId: '${data['classId']}',
        resolvedSection: '${data['section'] ?? ''}',
      ).isNotEmpty;
      return {...data, 'submission_on_hold': held};
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
    if (_saving) {
      return {
        'success': false,
        'code': 'SUBMISSION_BUSY',
        'message': 'An attendance submission is still running.',
      };
    }
    final epoch = _attendanceEpoch;
    final school = await SecureStorageService.getShaladarpanIdentity();
    if (school.isEmpty) {
      return {
        'success': false,
        'code': 'ACCOUNT_NOT_READY',
        'message': 'School login is required.',
      };
    }
    final prefs = await SharedPreferences.getInstance();
    final activeKeys = _relatedHoldKeys(prefs, school, date, classId, section);
    if (activeKeys.isEmpty) {
      return {
        'success': true,
        'resolved': 'not_held',
        'message': 'There is no unresolved submission for this class.',
      };
    }
    final initialHolds = <String, Map<String, dynamic>>{
      for (final k in activeKeys) k: _hold(prefs, k)!,
    };

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
        'message':
            'Portal verification failed. Previous submission is still on hold.',
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
    final after = await SecureStorageService.getShaladarpanIdentity();
    if (_saving || epoch != _attendanceEpoch || after != school) {
      return {
        'success': false,
        'code': 'ACCOUNT_CHANGED',
        'message': 'Session changed during verification. Previous submission remains on hold.',
      };
    }
    // Re-read metadata: never clear a different/newer outstanding operation.
    for (final entry in initialHolds.entries) {
      final latest = _hold(prefs, entry.key);
      if (latest == null || jsonEncode(latest) != jsonEncode(entry.value)) {
        return {
          'success': false,
          'code': 'STALE_ATTENDANCE_READ',
          'message': 'Submission state changed while checking. Refresh again.',
        };
      }
    }
    final candidateKeys = _relatedHoldKeys(
      prefs,
      school,
      date,
      classId,
      section,
      resolvedClassId: '${first['classId'] ?? classId}',
      resolvedSection: '${first['section'] ?? section ?? ''}',
    );
    final matchingKeys = <String>[
      for (final k in candidateKeys)
        if (initialHolds[k] != null &&
            _holdMatches(initialHolds[k]!, first) &&
            _holdMatches(initialHolds[k]!, second))
          k,
    ];
    if (matchingKeys.isNotEmpty) {
      for (final k in matchingKeys) {
        await prefs.remove(k);
      }
      _attendanceEpoch++;
      return {
        'success': true,
        'resolved': 'applied',
        'message': 'Previous attendance submission is verified on the portal.',
        'cache_transition': {'before': epoch, 'after': _attendanceEpoch},
      };
    }

    // A prior marked attendance can remain marked when an UPDATE failed.
    // Therefore 'marked' alone must NEVER unlock a retry.
    final exactKey = _holdKey(school, date, classId, section);
    final resolvedKey = _holdKey(
      school,
      date,
      '${first['classId'] ?? classId}',
      '${first['section'] ?? section ?? ''}',
    );
    final releasableKeys = <String>[];
    var anyRosterMatches = false;
    for (final k in candidateKeys) {
      final metadata = initialHolds[k];
      if (metadata == null) continue;
      final sameRoster = metadata['expected'] != null
          ? _sameRoster(metadata['expected'], first['students'])
          : (metadata['legacy'] == true && (k == exactKey || k == resolvedKey));
      if (!sameRoster) continue;
      anyRosterMatches = true;
      final started = metadata['created_at'];
      final ageMs = started is int
          ? DateTime.now().millisecondsSinceEpoch - started
          : 0;
      final oldEnough =
          metadata['legacy'] == true ||
          ageMs >= _manualReviewDelay.inMilliseconds;
      if (oldEnough) releasableKeys.add(k);
    }
    final manualAllowed = anyRosterMatches && releasableKeys.isNotEmpty;
    if (!acknowledgeManualRetry || !manualAllowed) {
      return {
        'success': false,
        'code': 'REVIEW_REQUIRED',
        'manual_retry_allowed': manualAllowed,
        'message': manualAllowed
            ? 'Portal statuses differ from the attempted Save. Review the recorded attendance before authorizing a new attempt.'
            : 'Save outcome is unresolved. Check again later; do not submit a second time.',
      };
    }
    // Explicitly authorized manual recovery after two identical verified reads,
    // never an automatic retry. The caller MUST show a warning/confirmation.
    for (final k in releasableKeys) {
      await prefs.remove(k);
    }
    _attendanceEpoch++;
    return {
      'success': true,
      'resolved': 'manual_review',
      'message': 'Submission hold released after your explicit review. Check portal statuses before a new Save.',
      'cache_transition': {'before': epoch, 'after': _attendanceEpoch},
    };
  }

  /// Dashboard READ admission only. Explicit user actions never use this gate.
  /// Wait outside coordinator resources and do not carry work to a new account.
  static Future<bool> waitForAttendanceIdle(String school) async {
    if (!directAttendanceEnabled) return true;
    final service = DirectSchoolSession.attendance;
    if (service == null || DirectSchoolSession.schoolId != school) return false;
    final identity = service.auth.schoolSessionIdentity;
    await service.waitForForeground();
    return directAttendanceEnabled &&
        identical(service, DirectSchoolSession.attendance) &&
        DirectSchoolSession.schoolId == school &&
        service.auth.schoolSessionIdentity == identity &&
        !service.foregroundActive;
  }

  static void Function() beginAttendanceInteraction() =>
      DirectSchoolSession.attendance?.acquireForeground() ?? () {};

  /// A Save and an Update share the same one-POST flow.
  /// The hold stores EXPECTED student identities/statuses before any network I/O.
  /// Best-effort read preparation only; failures retain normal Save preflight.
  static Future<void> prepareAttendanceSave({
    required String classId,
    required String date,
    String? section,
    required AttendanceReadScope expectedScope,
  }) async {
    if (!directAttendanceEnabled ||
        _saving ||
        captureReadScopeNow() != expectedScope)
      return;
    final service = DirectSchoolSession.attendance;
    if (service == null) return;
    final release = service.acquireForeground();
    try {
      await service.prepareSave(classId: classId, date: date, section: section);
    } catch (_) {
      // Advisory read only. The confirmed Save owns errors and fresh fallback.
    } finally {
      release();
    }
  }

  static Future<Map<String, dynamic>> saveAttendance(
    Map<String, dynamic> payload, {
    AttendanceReadScope? expectedScope,
  }) async {
    if (expectedScope != null && await captureReadScope() != expectedScope) {
      return {
        'success': false,
        'code': 'ACCOUNT_CHANGED',
        'submission_attempted': false,
        'message': 'School session changed. Refresh class data before Save.',
      };
    }
    if (_saving) {
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
      final school = await SecureStorageService.getShaladarpanIdentity();
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
                        _scopeIdentity(
                              DirectSchoolSession
                                  .attendance
                                  ?.auth
                                  .schoolSessionIdentity,
                            ) !=
                            expectedScope.identity
                  : !identical(expectedScope.session, _backendReadSession) ||
                        _scopeIdentity(baseUrl) != expectedScope.identity))) {
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
      if (date.isEmpty || cls.trim().isEmpty || expected == null) {
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
      if (_relatedHoldKeys(prefs, school, date, cls, section).isNotEmpty) {
        return {
          'success': false,
          'code': 'MUTATION_AMBIGUOUS',
          'submission_attempted': false,
          'submission_on_hold': true,
          'message': 'Previous Save/Update is unresolved. Verify its result before another submission.',
        };
      }
      final stored = await prefs.setString(
        key,
        jsonEncode({
          'created_at': DateTime.now().millisecondsSinceEpoch,
          'expected': payload['students'],
        }),
      );
      if (!stored) {
        return {
          'success': false,
          'code': 'SAVE_PREPARATION_FAILED',
          'submission_attempted': false,
          'message': 'Could not register the submission safety hold. Nothing was sent.',
        };
      }
      holdPrefs = prefs;
      registeredHoldKey = key;
      if (expectedScope != null &&
          (directAttendanceEnabled
              ? !identical(
                      expectedScope.session,
                      DirectSchoolSession.attendance,
                    ) ||
                    _scopeIdentity(
                          DirectSchoolSession
                              .attendance
                              ?.auth
                              .schoolSessionIdentity,
                        ) !=
                        expectedScope.identity
              : !identical(expectedScope.session, _backendReadSession) ||
                    _scopeIdentity(baseUrl) != expectedScope.identity)) {
        await prefs.remove(key);
        return {
          'success': false,
          'code': 'ACCOUNT_CHANGED',
          'submission_attempted': false,
          'message': 'School session changed. Refresh class data before Save.',
        };
      }
      Map<String, dynamic> result;
      if (directAttendanceEnabled) {
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
          () => DirectSchoolSession.attendance!.save(
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
      if (result['success'] == true && result['attendance_verified'] != true) {
        result = {
          ...result,
          'success': false,
          'code': 'SAVE_UNCONFIRMED',
          'submission_attempted': true,
          'attendance_verified': false,
          'message': 'Save response did not verify attendance on the portal.',
        };
      }
      final after = await SecureStorageService.getShaladarpanIdentity();
      if (after != school) {
        return {
          'success': false,
          'code': 'ACCOUNT_CHANGED',
          'submission_attempted': true,
          'attendance_verified': false,
          'message': 'School changed during Save. Verify the previous school separately.',
        };
      }
      if (result['submission_attempted'] == false ||
          (result['success'] == true &&
              result['attendance_verified'] == true)) {
        await prefs.remove(key);
      }
      final onHold = _relatedHoldKeys(
        prefs,
        school,
        date,
        cls,
        section,
        resolvedClassId: result['classId']?.toString(),
        resolvedSection: result['section']?.toString(),
      ).isNotEmpty;
      return {
        ...result,
        'submission_on_hold': onHold,
        if (expectedScope != null &&
            result['success'] == true &&
            result['attendance_verified'] == true)
          'cache_transition': {
            'before': expectedScope.revision,
            'after': _attendanceEpoch + 1,
          },
      };
    } catch (_) {
      requestMayHaveStarted =
          directDispatch?.mayHaveStarted ?? requestMayHaveStarted;
      if (!requestMayHaveStarted &&
          registeredHoldKey != null &&
          holdPrefs != null) {
        try {
          await holdPrefs.remove(registeredHoldKey);
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
        'submission_on_hold': requestMayHaveStarted,
        'message': requestMayHaveStarted
            ? 'Save outcome is uncertain. Verify recorded attendance before retrying.'
            : 'Could not prepare attendance request. Nothing was sent.',
      };
    } finally {
      _saving = false;
      _attendanceEpoch++;
    }
  }

  /// 3. Fetch summary of all classes for the day
  static Future<Map<String, dynamic>> fetchClassSummary({String? date}) async {
    try {
      final queryParams = <String, String>{
        if (date != null && date.isNotEmpty) 'date': date,
      };

      final uri = Uri.parse(
        "$baseUrl/summary",
      ).replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

      if (directAttendanceEnabled) {
        if (!DirectSchoolSession.available) {
          return {
            'success': false,
            'code': 'DIRECT_SESSION_EXPIRED',
            'message': 'Direct school session unavailable.',
          };
        }
        return await DirectSchoolSession.attendance!.fetchClassSummaryResponse(
          date: date,
        );
      }
      final response = await http.get(uri).timeout(_timeout);
      final Map<String, dynamic> data = _parseResponseBody(response.body);

      if (response.statusCode == 200) {
        return data;
      } else {
        return {
          "success": false,
          "message": _extractErrorMessage(data, response.statusCode),
        };
      }
    } catch (e) {
      return {"success": false, "message": "Connection error: $e"};
    }
  }

  /// 4. School-wide report (class/section wise Boys, Girls, Absent, Leave, Total)
  /// Response: { success, date, schoolName, rows: [...], unknownGender, failedSections }
  static Future<Map<String, dynamic>> fetchSchoolReport({
    required String date,
    void Function(int completed, int total)? onProgress,
  }) async {
    if (directAttendanceEnabled) {
      try {
        final epoch = _attendanceEpoch;
        final school = await SecureStorageService.getShaladarpanIdentity();
        if (school.isEmpty ||
            !DirectSchoolSession.available ||
            DirectSchoolSession.schoolId != school) {
          return {
            'success': false,
            'code': 'DIRECT_SESSION_EXPIRED',
            'message': 'Direct school session unavailable. Log in again.',
          };
        }
        final result = await DirectSchoolSession.attendance!.fetchSchoolReport(
          date: date,
          onProgress: onProgress,
        );
        final after = await SecureStorageService.getShaladarpanIdentity();
        if (after != school ||
            !DirectSchoolSession.available ||
            DirectSchoolSession.schoolId != school) {
          return {
            'success': false,
            'code': 'ACCOUNT_CHANGED',
            'message': 'School account changed during report fetch.',
          };
        }
        if (epoch != _attendanceEpoch || _saving) {
          return {
            'success': false,
            'code': 'STALE_ATTENDANCE_READ',
            'message': 'Attendance changed during report fetch. Refresh after submission settles.',
          };
        }
        if (result['success'] == true &&
            _dateKey('${result['date'] ?? ''}') != _dateKey(date)) {
          return {
            'success': false,
            'code': 'DATE_MISMATCH',
            'message': 'Portal report date did not match this request.',
          };
        }
        return result;
      } catch (error) {
        return {
          'success': false,
          'code': 'NETWORK_ERROR',
          'message': 'Connection error: $error',
        };
      }
    }
    if (onProgress == null) {
      try {
        final uri = Uri.parse('$baseUrl/school-report')
            .replace(queryParameters: {'date': date});
        final response = await http.get(uri).timeout(_reportTimeout);
        final data = _parseResponseBody(response.body);
        if (response.statusCode == 200) return data;
        return {
          'success': false,
          'code': data['code'] ?? '${response.statusCode}',
          'message': _extractErrorMessage(data, response.statusCode),
        };
      } catch (e) {
        return {'success': false, 'message': 'Connection error: $e'};
      }
    }
    final client = http.Client();
    try {
      return await _readReportStream(
        client,
        date,
        onProgress,
      ).timeout(_reportTimeout);
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    } finally {
      // Closes the request on success, timeout, incomplete stream or errors.
      client.close();
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
      return {
        'success': false,
        'code': '${response.statusCode}',
        'message': _extractErrorMessage(data, response.statusCode),
      };
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
          return {
            'success': false,
            'code': '$statusCode',
            'message': _extractErrorMessage({
              'detail': event['detail'],
            }, statusCode),
          };
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
