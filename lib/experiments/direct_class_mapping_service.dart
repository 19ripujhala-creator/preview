import '../services/core/direct/coordinator.dart';
import '../services/core/direct/errors.dart';
import '../services/portals/shaladarpan/direct/class_mapping_worker.dart';
import 'direct_portal_auth.dart';

class DirectClassMappingService {
  DirectClassMappingService(this.auth);
  final DirectPortalAuth auth;
  ClassMappingWorker? _worker;
  bool _confirmed = false;
  ClassMappingWorker get _portal => _worker ??= ClassMappingWorker(
    baseUrl: () =>
        Uri.https('rajshaladarpan.rajasthan.gov.in', '/${auth.verifiedNode}/'),
    schoolId: () => auth.authenticatedSchoolId ?? '',
    sessionKey: () => auth.schoolSessionIdentity,
    check: () {
      if (!auth.isVerified)
        throw const MappingError(
          'ACCOUNT_CHANGED',
          'School login session changed. Fetch class mapping again.',
        );
    },
    request:
        (
          url, {
          fields,
          referer,
          saveControl,
          timeout = const Duration(seconds: 25),
        }) => auth.classMappingRequest(
          url,
          fields: fields,
          referer: referer,
          saveControl: saveControl,
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
        return ClassMappingWorker.failure(
          const MappingError(
            'ACCOUNT_CHANGED',
            'School login session changed. Fetch class mapping again.',
          ),
        );
      _confirmed = confirmed;
      try {
        result = await operation();
        if (!auth.isVerified || key != auth.schoolSessionIdentity)
          return ClassMappingWorker.failure(
            const MappingError(
              'ACCOUNT_CHANGED',
              'School login session changed. Fetch class mapping again.',
            ),
            result?['submission_attempted'] == true,
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
        label: mutation ? 'class_mapping_save' : 'class_mapping_fetch',
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
      return ClassMappingWorker.failure(error, mutation);
    }
  }

  Future<Map<String, dynamic>> fetch() => _run(() => _portal.fetch());
  Future<Map<String, dynamic>> save(
    List<Map<String, dynamic>> updates, {
    required bool userConfirmed,
  }) => _run(
    () => _portal.save(updates, userConfirmed: userConfirmed),
    mutation: true,
    confirmed: userConfirmed,
  );
}
