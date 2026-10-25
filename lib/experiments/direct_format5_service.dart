import '../services/core/direct/coordinator.dart';
import '../services/core/direct/errors.dart';
import '../services/portals/shaladarpan/direct/format5_worker.dart';
import 'direct_portal_auth.dart';

/// Independent Format-5 service; shares login transport only, never another
/// worker's stored WebForms page, selections or form tokens.
class DirectFormat5Service {
  DirectFormat5Service(this.auth)
      : worker = Format5Worker(
          request: auth.format5Request,
          baseUrl: () => Uri.https('rajshaladarpan.rajasthan.gov.in', '/${auth.verifiedNode}/'),
          schoolId: () => auth.authenticatedSchoolId ?? '',
          sessionIdentity: () => auth.schoolSessionIdentity,
          check: () {
            if (!auth.isVerified) {
              throw const Format5Error('SESSION_EXPIRED', 'School session expired.');
            }
          },
        );

  final DirectPortalAuth auth;
  final Format5Worker worker;
  bool _busy = false;

  Future<Map<String, dynamic>> _run(
    Future<Map<String, dynamic>> Function() action, {
    bool mutation = false,
    required String label,
  }) async {
    Future<Map<String, dynamic>> execute() async {
      if (_busy) return const {'success': false, 'code': 'BUSY', 'message': 'Format-5 operation is running.'};
      _busy = true;
      try {
        return await action();
      } on Format5Error catch (e) {
        return Format5Worker.fail(e);
      } finally {
        _busy = false;
      }
    }

    final coordinator = auth.coordinator;
    if (coordinator == null) return execute();
    try {
      return await coordinator.run(
        resource: 'sd.student_format5',
        kind: mutation ? Kind.mutation : Kind.read,
        timeout: mutation ? 65 : 45,
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

  Future<Map<String, dynamic>> open() => _run(worker.open, label: 'format5_open');
  Future<Map<String, dynamic>> list(String session, String classId, String section) =>
      _run(() => worker.list(session, classId, section), label: 'format5_list');
  Future<Map<String, dynamic>> edit(String nicId) =>
      _run(() => worker.edit(nicId), label: 'format5_edit');
  Future<Map<String, dynamic>> save(String nicId, {
    required String srNo,
    required String category,
    required String mobile,
  }) => _run(
    () => worker.save(nicId, sr: srNo, category: category, mobile: mobile),
    mutation: true,
    label: 'format5_save',
  );
}
