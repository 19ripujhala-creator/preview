// Python student_attendance_worker.py parity (Android native HTTP).
// A save is made only after explicit confirmation; an uncertain result is NEVER retried.
import '../services/core/direct/coordinator.dart';
import '../services/core/direct/errors.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../services/portals/shaladarpan/direct/gender_master.dart';
import '../services/portals/shaladarpan/direct/school_report_worker.dart';
import '../services/portals/shaladarpan/direct/student_attendance_worker.dart';
import 'direct_portal_auth.dart';

class AttendancePortalException implements Exception {
  const AttendancePortalException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => '$code: $message';
}

class AttendanceSection {
  const AttendanceSection({
    required this.classId,
    required this.section,
    required this.rowIndex,
    required this.total,
    required this.status,
    required this.done,
    required this.entryId,
    this.present,
    this.absent,
  });
  final String classId, section, status, entryId;
  final int rowIndex;
  final int? total, present, absent;
  final bool done;
}

class AttendanceSnapshot {
  const AttendanceSnapshot({
    required this.date,
    required this.section,
    required this.students,
    required this.verified,
    required this.warning,
  });
  final String date;
  final AttendanceSection section;
  final List<Map<String, Object?>> students;
  final bool verified;
  final String? warning;
}

class AttendanceSaveResult {
  const AttendanceSaveResult({
    required this.success,
    required this.code,
    required this.message,
    required this.submissionAttempted,
    required this.verified,
    required this.updatedCount,
    this.response = const {},
  });
  final bool success, submissionAttempted, verified;
  final String code, message;
  final int updatedCount;
  final Map<String, dynamic> response;
}

class DirectStudentAttendanceService {
  DirectStudentAttendanceService(this.auth);
  final DirectPortalAuth auth;
  static const _host = 'rajshaladarpan.rajasthan.gov.in';
  static const _pageName = 'StudentdailyAttendanceStatus_Web_NewVersion.aspx';
  bool _busy = false;
  SchoolReportWorker? _reportWorker;

  Uri get _endpoint {
    if (!auth.isVerified) {
      throw const AttendancePortalException('SESSION_EXPIRED', 'Login first');
    }
    return Uri.https(_host, '/${auth.verifiedNode}/Home/School/$_pageName');
  }

  Future<T> _exclusive<T>(
    Future<T> Function() fn, {
    bool mutation = false,
    double? timeout,
    int? maxAttempts,
  }) async {
    Future<T> execute() async {
      if (_busy) {
        throw const AttendancePortalException(
          'BUSY',
          'Attendance operation already running',
        );
      }
      _busy = true;
      try {
        return await fn();
      } finally {
        _busy = false;
      }
    }

    final coordinator = auth.coordinator;
    if (coordinator == null) return execute();
    final expectedSchool = auth.authenticatedSchoolId;
    final preMutationCodes = <String>{'BAD_DATE', 'BAD_CLASS', 'NO_CLASSES'};
    try {
      final result = await coordinator.run(
        resource: 'sd.student',
        kind: mutation ? Kind.mutation : Kind.read,
        timeout: timeout ?? (mutation ? 75 : 60),
        maxAttempts: maxAttempts ?? (mutation ? 1 : 3),
        preMutationCodes: mutation ? preMutationCodes : {},
        label: mutation ? 'student_save' : 'student_fetch',
        worker: (_) async {
          if (auth.authenticatedSchoolId != expectedSchool ||
              !coordinator.contextIsCurrent()) {
            return {
              'success': false,
              'code': 'ACCOUNT_CHANGED',
              'message': 'School session changed. Fetch the data again.',
              'submission_attempted': false,
              'attendance_verified': false,
            };
          }
          final generation = coordinator.generation;
          T value;
          try {
            value = await execute();
          } on AttendancePortalException catch (error) {
            return {
              'success': false,
              'code': error.code,
              'message': error.message,
            };
          }
          final attempted =
              value is AttendanceSaveResult && value.submissionAttempted;
          if (auth.authenticatedSchoolId != expectedSchool ||
              coordinator.generation != generation ||
              !coordinator.contextIsCurrent()) {
            return {
              'success': false,
              'code': attempted ? 'SAVE_UNCONFIRMED' : 'ACCOUNT_CHANGED',
              'message': attempted
                  ? 'School session changed after attendance submission. '
                        'Verify on portal before retrying.'
                  : 'School session changed. Fetch the data again.',
              'submission_attempted': attempted,
              'attendance_verified': false,
            };
          }
          if (value is AttendanceSaveResult) {
            // The worker's dispatch tracker proved no Submit reached transport.
            // Do not let a preflight timeout become a false ambiguous SAVE.
            if (!value.submissionAttempted && !value.success) {
              preMutationCodes.add(value.code);
            }
            return {
              ...value.response,
              'success': value.success,
              'code': value.code,
              'message': value.message,
              'submission_attempted': value.submissionAttempted,
              'attendance_verified': value.verified,
              '_direct_value': value,
            };
          }
          if (value is Map<String, dynamic>) {
            return {...value, '_direct_value': value};
          }
          return {'success': true, '_direct_value': value};
        },
      );
      if (result.containsKey('_direct_value'))
        return result['_direct_value'] as T;
      throw AttendancePortalException(
        result['code']?.toString() ?? 'INVALID_RESULT',
        result['message']?.toString() ?? 'Portal data is missing or invalid.',
      );
    } on CoordinatorError catch (error) {
      if (mutation) {
        final ambiguous = error.kind == ErrorKind.mutationAmbiguous;
        final upstream = error.extra['upstream_response'] is Map
            ? Map<String, dynamic>.from(error.extra['upstream_response'] as Map)
            : <String, dynamic>{};
        upstream.remove('_direct_value');
        return AttendanceSaveResult(
          success: false,
          code: ambiguous ? 'SAVE_UNCONFIRMED' : error.kind.code,
          message: error.message,
          submissionAttempted: ambiguous,
          verified: false,
          updatedCount: 0,
          response: {
            ...error.asDetail(),
            if (upstream.isNotEmpty) 'upstream_response': upstream,
            ...upstream,
            'success': false,
            'submission_attempted': ambiguous,
            'attendance_verified': false,
          },
        ) as T;
      }
      throw AttendancePortalException(error.kind.code, error.message);
    } on AttendancePortalException catch (error) {
      if (!mutation) rethrow;
      return AttendanceSaveResult(
        success: false,
        code: error.code,
        message: error.message,
        submissionAttempted: false,
        verified: false,
        updatedCount: 0,
      ) as T;
    }
  }

  late final StudentAttendanceWorker _worker = StudentAttendanceWorker(
    baseUrl: () => _endpoint.resolve('../../'),
    observeUrl: auth.observeAttendanceUrl,
    sessionIdentity: () => auth.schoolSessionIdentity,
    request: (url, {fields, referer, mutation = false}) {
      if (mutation) {
        return auth.submitStudentAttendanceOnce(
          url,
          fields: fields!,
          referer: referer!,
          userConfirmed: true,
        );
      }
      return auth.attendanceRequest(
        url,
        navigationFields: fields,
        referer: referer,
      );
    },
  );

  AttendanceSection _section(Map<String, dynamic> row) => AttendanceSection(
    classId: '${row['classId'] ?? ''}',
    section: '${row['section'] ?? ''}',
    rowIndex: row['rowIndex'] as int? ?? 0,
    total: row['total'] as int?,
    present: row['present'] as int?,
    absent: row['absent'] as int?,
    status: '${row['status'] ?? ''}',
    done: row['done'] == true,
    entryId: '${row['entryLinkId'] ?? ''}',
  );

  Future<SchoolReportWorker> _getReportWorker() async {
    if (_reportWorker != null) return _reportWorker!;
    final prefs = await SharedPreferences.getInstance();
    const prefix = 'rajshala.direct.sd.data.';
    final cache = SchoolReportCache(
      read: (key) async => prefs.getString('$prefix$key'),
      write: (key, value) async {
        if (!await prefs.setString('$prefix$key', value)) {
          throw StateError('School report cache could not be written.');
        }
      },
    );
    Uri base() => _endpoint.resolve('../../');
    String school() => auth.authenticatedSchoolId ?? '';
    final gender = GenderMaster(
      request: auth.schoolReportRequest,
      baseUrl: base,
      schoolId: school,
      cache: cache,
    );
    return _reportWorker = SchoolReportWorker(
      attendance: _worker,
      gender: gender,
      request: auth.schoolReportRequest,
      logoRequest: auth.schoolReportLogo,
      baseUrl: base,
      schoolId: school,
      cache: cache,
    );
  }

  Future<Map<String, dynamic>> fetchSchoolReport({
    required String date,
    void Function(int completed, int total)? onProgress,
  }) async {
    try {
      return await _exclusive(
        () async {
          final worker = await _getReportWorker();
          return worker.fetchSchoolReport(
            attendanceDate: date,
            onProgress: onProgress,
          );
        },
        timeout: 240,
        maxAttempts: 1,
      );
    } catch (error) {
      return _failure(error);
    }
  }

  Future<Map<String, dynamic>> fetchClassSummaryResponse({String? date}) async {
    try {
      return await _exclusive(
        () => _worker.fetchClassSummary(attendanceDate: date),
      );
    } catch (error) {
      return _failure(error);
    }
  }

  Future<List<AttendanceSection>> fetchClassSummary({String? date}) async {
    final result = await fetchClassSummaryResponse(date: date);
    _requireSuccess(result);
    return (result['classes'] as List)
        .map((row) => _section(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  Future<Map<String, dynamic>> fetchStudentsResponse({
    required String classId,
    String? date,
    String? section,
  }) async {
    try {
      return await _exclusive(
        () => _worker.fetchStudentAttendanceList(
          classId: classId,
          attendanceDate: date,
          section: section,
        ),
      );
    } catch (error) {
      return {..._failure(error), 'students': []};
    }
  }

  Future<AttendanceSnapshot> fetchStudents({
    required String classId,
    String? date,
    String? section,
  }) async {
    final result = await fetchStudentsResponse(
      classId: classId,
      date: date,
      section: section,
    );
    _requireSuccess(result);
    return AttendanceSnapshot(
      date: '${result['date'] ?? ''}',
      section: _section(Map<String, dynamic>.from(result['summary'] as Map)),
      students: (result['students'] as List)
          .map((row) => Map<String, Object?>.from(row as Map))
          .toList(),
      verified: result['data_verified'] == true,
      warning: result['warning'] as String?,
    );
  }

  Map<String, dynamic> _failure(Object error) {
    if (error is AttendancePortalException) {
      return {'success': false, 'code': error.code, 'message': error.message};
    }
    return StudentAttendanceWorker.failure(error);
  }

  void _requireSuccess(Map<String, dynamic> result) {
    if (result['success'] != true) {
      throw AttendancePortalException(
        '${result['code'] ?? 'UNEXPECTED'}',
        '${result['message'] ?? 'Portal data is missing or invalid.'}',
      );
    }
  }

  Future<AttendanceSaveResult> save({
    required String classId,
    required String date,
    String? section,
    required List<Map<String, Object?>> students,
    required bool userConfirmed,
  }) async {
    final owner = auth.authenticatedSchoolId;
    final initial = await _exclusive(() async {
      final response = await _worker.saveStudentAttendance(
        classId: classId,
        attendanceDate: date,
        section: section,
        students: students,
        userConfirmed: userConfirmed,
      );
      return AttendanceSaveResult(
        success: response['success'] == true,
        code:
            '${response['code'] ?? (response['action'] == 'unchanged' ? 'UNCHANGED' : 'VERIFIED')}',
        message: '${response['message'] ?? ''}',
        submissionAttempted: response['submission_attempted'] == true,
        verified: response['attendance_verified'] == true,
        updatedCount: response['updatedCount'] as int? ?? 0,
        response: response,
      );
    }, mutation: true);
    // Recheck only after the mutation owner has settled. This is one READ,
    // never a second SAVE. A real native portal message remains authoritative.
    if (initial.success ||
        !initial.submissionAttempted ||
        initial.response['pending'] == true ||
        (initial.response['portal_message']?.toString().isNotEmpty ?? false) ||
        auth.authenticatedSchoolId != owner)
      return initial;
    try {
      final fresh = await _exclusive(
        () => _worker.fetchStudentAttendanceList(
          classId: classId,
          attendanceDate: date,
          section: section,
        ),
        timeout: 45,
        maxAttempts: 1,
      );
      if (auth.authenticatedSchoolId != owner ||
          fresh['success'] != true ||
          fresh['data_verified'] != true ||
          fresh['attendance_verified'] != true ||
          fresh['students'] is! List ||
          !StudentAttendanceWorker.savedStudentsMatch(
            students,
            (fresh['students'] as List).cast<Map<String, Object?>>(),
          ))
        return initial;
      const message =
          'Attendance verified on the portal after the interrupted response.';
      return AttendanceSaveResult(
        success: true,
        code: 'VERIFIED_AFTER_RECHECK',
        message: message,
        submissionAttempted: true,
        verified: true,
        updatedCount: initial.updatedCount,
        response: {
          ...fresh,
          'success': true,
          'code': 'VERIFIED_AFTER_RECHECK',
          'message': message,
          'message_source': 'verification',
          'submission_attempted': true,
          'attendance_verified': true,
          'verifiedAfterAmbiguity': true,
          'updatedCount': initial.updatedCount,
          'updatedCount_known': false,
          'original_response': initial.response,
        },
      );
    } catch (_) {
      return initial;
    }
  }
}
