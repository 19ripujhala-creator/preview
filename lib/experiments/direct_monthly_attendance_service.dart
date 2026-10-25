import '../services/core/direct/coordinator.dart';
import '../services/core/direct/errors.dart';
import '../services/portals/shaladarpan/direct/monthly_attendance_worker.dart';
import 'direct_portal_auth.dart';

/// Independent Monthly Attendance service; shares login transport only, never another
/// worker's stored WebForms page, selections or form tokens.
class DirectMonthlyAttendanceService {
  DirectMonthlyAttendanceService(this.auth)
    : worker = MonthlyAttendanceWorker(
        request: auth.monthlyAttendanceRequest,
        baseUrl: () => Uri.https(
          'rajshaladarpan.rajasthan.gov.in',
          '/${auth.verifiedNode}/',
        ),
        schoolId: () => auth.authenticatedSchoolId ?? '',
        identity: () => auth.schoolSessionIdentity,
        check: () {
          if (!auth.isVerified) {
            throw const MonthlyAttendanceError('School session expired.');
          }
        },
      );

  final DirectPortalAuth auth;
  final MonthlyAttendanceWorker worker;
  bool _busy = false;

  Future<Map<String, dynamic>> _run(
    Future<Map<String, dynamic>> Function() action, {
    bool mutation = false,
    required String label,
  }) async {
    Future<Map<String, dynamic>> execute() async {
      if (_busy) {
        return const {
          'success': false,
          'code': 'BUSY',
          'message': 'Monthly Attendance operation is running.',
        };
      }
      _busy = true;
      try {
        return await action();
      } on MonthlyAttendanceError catch (e) {
        return {
          'success': false,
          'message': e.message,
          'submission_attempted': e.attempted,
        };
      } finally {
        _busy = false;
      }
    }

    final coordinator = auth.coordinator;
    if (coordinator == null) return execute();
    try {
      return await coordinator.run(
        resource: 'sd.student_monthly_attendance',
        kind: mutation ? Kind.mutation : Kind.read,
        timeout: mutation ? 180 : 65,
        maxAttempts: 1, // Stateful WebForms; never replay even navigation.
        label: label,
        worker: (_) => execute(),
      );
    } on CoordinatorError catch (e) {
      return {
        'success': false,
        'code': e.kind.code,
        'message': e.message,
        'submission_attempted': mutation,
      };
    }
  }

  Future<Map<String, dynamic>> open() =>
      _run(worker.open, label: 'monthly_attendance_open');
  Future<Map<String, dynamic>> load(
    String session,
    String klass,
    String section,
    String month,
  ) => _run(
    () => worker.load(session, klass, section, month),
    label: 'monthly_attendance_load',
  );
  Future<Map<String, dynamic>> save(
    String session,
    String klass,
    String section,
    String month,
    Map<String, String> changes,
    List<Map<String, dynamic>> expected,
  ) => _run(
    () => worker.save(session, klass, section, month, changes, expected),
    mutation: true,
    label: 'monthly_attendance_save',
  );
}
