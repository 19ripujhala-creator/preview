import '../services/core/direct/coordinator.dart';
import '../services/core/direct/errors.dart';
import '../services/portals/shaladarpan/direct/working_days_worker.dart';
import 'direct_portal_auth.dart';

/// Independent Working Days service; shares login transport only, never another
/// worker's stored WebForms page, selections or form tokens.
class DirectWorkingDaysService {
  DirectWorkingDaysService(this.auth)
    : worker = WorkingDaysWorker(
        request: auth.workingDaysRequest,
        baseUrl: () => Uri.https(
          'rajshaladarpan.rajasthan.gov.in',
          '/${auth.verifiedNode}/',
        ),
        schoolId: () => auth.authenticatedSchoolId ?? '',
        identity: () => auth.schoolSessionIdentity,
        check: () {
          if (!auth.isVerified) {
            throw const WorkingDaysError('School session expired.');
          }
        },
      );

  final DirectPortalAuth auth;
  final WorkingDaysWorker worker;
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
          'message': 'Working Days operation is running.',
        };
      }
      _busy = true;
      try {
        return await action();
      } on WorkingDaysError catch (e) {
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
        resource: 'sd.student_working_days',
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
      _run(worker.open, label: 'working_days_open');
  Future<Map<String, dynamic>> load(String session) =>
      _run(() => worker.load(session), label: 'working_days_load');
  Future<Map<String, dynamic>> save(
    String session,
    String month,
    Map<String, String> changes,
    Map<String, String> expected,
  ) => _run(
    () => worker.save(session, month, changes, expected),
    mutation: true,
    label: 'working_days_save',
  );
}
