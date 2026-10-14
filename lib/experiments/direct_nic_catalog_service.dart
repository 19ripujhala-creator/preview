import '../services/core/direct/coordinator.dart';
import '../services/core/direct/errors.dart';
import '../services/portals/shaladarpan/direct/nic_catalog_worker.dart';
import 'direct_portal_auth.dart';

/// Shared-session NIC catalog prerequisite. PDF/UI routing is not switched
/// until the original portal print workflow has a verified native renderer.
class DirectNicCatalogService {
  DirectNicCatalogService(this.auth);
  final DirectPortalAuth auth;

  Future<Map<String, dynamic>> catalog(String schoolId) async {
    var identity = auth.schoolSessionIdentity;
    final school = auth.authenticatedSchoolId;
    void check() {
      if (!auth.isVerified || auth.authenticatedSchoolId != school) {
        throw const NicError(
          'SESSION_EXPIRED',
          'School portal session expired.',
        );
      }
      if (identity.isEmpty || identity != auth.schoolSessionIdentity) {
        throw const NicError(
          'SESSION_CHANGED',
          'School login session changed. Open the NIC directory again.',
        );
      }
    }

    Future<Map<String, dynamic>> execute() async {
      if (auth.authenticatedSchoolId == school)
        identity = auth.schoolSessionIdentity;
      return NicCatalogWorker(
        request: auth.nicCatalogRequest,
        baseUrl: () => Uri.https(
          'rajshaladarpan.rajasthan.gov.in',
          '/${auth.verifiedNode}/',
        ),
        schoolId: () => auth.authenticatedSchoolId ?? '',
        check: check,
      ).catalog(schoolId);
    }

    try {
      final coordinator = auth.coordinator;
      if (coordinator == null) return await execute();
      return await coordinator.run(
        resource: 'sd.student_nic',
        kind: Kind.read,
        timeout: 60,
        maxAttempts: 3,
        label: 'student_nic_catalog',
        worker: (_) => execute(),
      );
    } on CoordinatorError catch (e) {
      return NicCatalogWorker.failure(e.kind.code, e.message);
    }
  }
}
