import '../services/core/direct/coordinator.dart';
import '../services/core/direct/errors.dart';
import '../services/portals/shaladarpan/direct/incharge_mapping.dart';
import 'direct_portal_auth.dart';

class DirectInchargeService {
  DirectInchargeService(this.auth);
  final DirectPortalAuth auth;
  InchargeMappingWorker? _worker;
  bool _confirmed = false;
  InchargeMappingWorker get _portal => _worker ??= InchargeMappingWorker(
    baseUrl: () =>
        Uri.https('rajshaladarpan.rajasthan.gov.in', '/${auth.verifiedNode}/'),
    schoolId: () => auth.authenticatedSchoolId ?? '',
    sessionKey: () => auth.schoolSessionIdentity,
    check: () {
      if (!auth.isVerified)
        throw const InchargeError(
          'ACCOUNT_CHANGED',
          'School login changed; refresh first.',
        );
    },
    request:
        (
          url, {
          fields,
          referer,
          action,
          control,
          controlId,
          mutation = false,
          timeout = const Duration(seconds: 25),
        }) => auth.inchargeRequest(
          url,
          fields: fields,
          referer: referer,
          control: control,
          controlId: controlId,
          action: action,
          mutation: mutation,
          timeout: timeout,
          userConfirmed: _confirmed,
        ),
  );
  Future<Map<String, dynamic>> _run(
    Future<Map<String, dynamic>> Function() operation, {
    bool mutation = false,
    bool confirmed = false,
  }) async {
    var key = auth.schoolSessionIdentity;
    final school = auth.authenticatedSchoolId;
    Map<String, dynamic>? result;
    Future<Map<String, dynamic>> execute() async {
      if (!mutation && auth.authenticatedSchoolId == school)
        key = auth.schoolSessionIdentity;
      if (!auth.isVerified ||
          auth.authenticatedSchoolId != school ||
          key.isEmpty ||
          key != auth.schoolSessionIdentity)
        return InchargeMappingWorker.failure(
          const InchargeError(
            'ACCOUNT_CHANGED',
            'School login changed; refresh first.',
          ),
        );
      _confirmed = confirmed;
      try {
        result = await operation();
        if (!auth.isVerified || key != auth.schoolSessionIdentity)
          return InchargeMappingWorker.failure(
            const InchargeError(
              'ACCOUNT_CHANGED',
              'School login changed; refresh first.',
            ),
            attempted: result?['submission_attempted'] == true,
          );
        return result!;
      } finally {
        _confirmed = false;
      }
    }

    try {
      final co = auth.coordinator;
      if (co == null) return await execute();
      return await co.run(
        resource: 'sd.mapping',
        kind: mutation ? Kind.mutation : Kind.read,
        timeout: 60,
        maxAttempts: mutation ? 1 : 3,
        preMutationCodes: {'ACCOUNT_CHANGED'},
        label: mutation ? 'incharge_action' : 'incharge_fetch',
        worker: (_) => execute(),
      );
    } on CoordinatorError catch (error) {
      if (result?['submission_attempted'] == true) return result!;
      final ambiguous = mutation && error.kind == ErrorKind.mutationAmbiguous;
      return {
        'success': false,
        'code': ambiguous ? 'SAVE_UNCONFIRMED' : error.kind.code,
        'message': error.message,
        'submission_attempted': ambiguous,
        'verified': false,
      };
    } catch (error) {
      return InchargeMappingWorker.failure(error, attempted: mutation);
    }
  }

  Future<Map<String, dynamic>> fetch() => _run(() => _portal.fetch());
  Future<Map<String, dynamic>> execute(
    String type, {
    String roleId = '',
    String teacherId = '',
    String buttonId = '',
    required bool userConfirmed,
  }) => _run(
    () => _portal.execute(
      type,
      roleId: roleId,
      teacherId: teacherId,
      buttonId: buttonId,
      userConfirmed: userConfirmed,
    ),
    mutation: true,
    confirmed: userConfirmed,
  );
}
