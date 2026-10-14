import '../services/core/direct/coordinator.dart';
import '../services/core/direct/errors.dart';
import '../services/portals/shaladarpan/direct/staff_attendance.dart';
import 'direct_portal_auth.dart';

/// One shared authenticated School session, the original staff resource and
/// unchanged Python worker results. A mutation is never replayed.
class DirectStaffAttendanceService {
  DirectStaffAttendanceService(this.auth, {DateTime Function()? now})
    : now = now ?? DateTime.now;
  final DirectPortalAuth auth;
  final DateTime Function() now;
  StaffAttendanceWorker _worker({bool userConfirmed = false}) {
    final expectedSchool = auth.authenticatedSchoolId;
    final expectedGeneration = auth.coordinator?.generation;
    return StaffAttendanceWorker(
      baseUrl: () => Uri.https(
        'rajshaladarpan.rajasthan.gov.in',
        '/${auth.verifiedNode}/',
      ),
      schoolId: () => auth.authenticatedSchoolId ?? '',
      now: now,
      observeUrl: auth.observeAttendanceUrl,
      check: () {
        if (auth.authenticatedSchoolId != expectedSchool ||
            auth.coordinator?.generation != expectedGeneration) {
          throw const StaffAttendanceError(
            'ACCOUNT_CHANGED',
            'School session changed. Fetch attendance again.',
          );
        }
        if (!auth.isVerified)
          throw const StaffAttendanceError(
            'SESSION_EXPIRED',
            'School portal session expired.',
          );
      },
      request:
          (
            url, {
            fields,
            referer,
            action,
            mutation = false,
            timeout = const Duration(seconds: 25),
          }) => auth.staffAttendanceRequest(
            url,
            fields: fields,
            referer: referer,
            action: action,
            mutation: mutation,
            timeout: timeout,
            userConfirmed: userConfirmed,
          ),
    );
  }

  Future<Map<String, dynamic>> _run(
    Future<Map<String, dynamic>> Function() operation, {
    bool mutation = false,
  }) async {
    final expectedSchool = auth.authenticatedSchoolId;
    final coordinator = auth.coordinator;
    Map<String, dynamic>? upstream;
    Future<Map<String, dynamic>> execute() async {
      if (!auth.isVerified ||
          expectedSchool == null ||
          expectedSchool.isEmpty ||
          auth.authenticatedSchoolId != expectedSchool)
        return StaffAttendanceWorker.errorResult(
          const StaffAttendanceError(
            'ACCOUNT_CHANGED',
            'School session changed. Fetch attendance again.',
          ),
        );
      final generation = coordinator?.generation;
      final result = await operation();
      if (auth.authenticatedSchoolId != expectedSchool ||
          !auth.isVerified ||
          coordinator?.generation != generation)
        return StaffAttendanceWorker.errorResult(
          const StaffAttendanceError(
            'ACCOUNT_CHANGED',
            'School session changed. Fetch attendance again.',
          ),
          result['submission_attempted'] == true,
        );
      upstream = result;
      return result;
    }

    try {
      if (coordinator == null) return await execute();
      return await coordinator.run(
        resource: 'sd.staff_attendance',
        kind: mutation ? Kind.mutation : Kind.read,
        timeout: mutation ? 120 : 90,
        maxAttempts: mutation ? 1 : 3,
        preMutationCodes: mutation
            ? {
                'PAGE_NOT_READY',
                'NETWORK_ERROR',
                'PORTAL_SLOW',
                'SESSION_EXPIRED',
              }
            : {},
        label: mutation ? 'staff_submit' : 'staff_fetch',
        worker: (_) => execute(),
      );
    } on CoordinatorError catch (error) {
      if (upstream?['submission_attempted'] == true) return upstream!;
      final ambiguous = mutation && error.kind == ErrorKind.mutationAmbiguous;
      return {
        'success': false,
        'code': ambiguous ? 'SAVE_UNCONFIRMED' : error.kind.code,
        'message': error.message,
        'submission_attempted': ambiguous,
        'attendance_verified': false,
        if (ambiguous) 'requires_verification': true,
      };
    } catch (error) {
      return StaffAttendanceWorker.errorResult(error, mutation);
    }
  }

  Future<Map<String, dynamic>> fetch() => _run(() => _worker().fetch());
  Future<Map<String, dynamic>> submit(
    List<Map<String, dynamic>> rows, {
    required String attendanceDate,
    required bool userConfirmed,
  }) async {
    final worker = _worker(userConfirmed: userConfirmed);
    if (!worker.hoursOpen)
      return StaffAttendanceWorker.errorResult(
        const StaffAttendanceError(
          'PORTAL_TIME_RESTRICTED',
          StaffAttendanceWorker.timeMessage,
        ),
      );
    if (attendanceDate != worker.today)
      return StaffAttendanceWorker.errorResult(
        const StaffAttendanceError(
          'STALE_ATTENDANCE',
          'Teacher attendance belongs to a different date. Refresh before submitting.',
        ),
      );
    final seen = <String>{};
    for (final row in rows) {
      final id = '${row['staffId'] ?? ''}'.trim(),
          serial = '${row['sno'] ?? ''}'.trim();
      final code = row['status_code'];
      if (!RegExp(r'^\d+$').hasMatch(id) ||
          !seen.add(id) ||
          !RegExp(r'^\d+$').hasMatch(serial) ||
          (code != null && !RegExp(r'^\d+$').hasMatch(code.toString())) ||
          (code == null && '${row['original_status'] ?? ''}'.isEmpty))
        return StaffAttendanceWorker.errorResult(
          const StaffAttendanceError(
            'INVALID_PAYLOAD',
            'Provide unique Staff IDs, valid serial numbers and portal attendance options.',
          ),
        );
    }
    return _run(
      () => worker.submit(rows, userConfirmed: userConfirmed),
      mutation: true,
    );
  }
}
