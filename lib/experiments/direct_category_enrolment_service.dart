import '../services/core/direct/coordinator.dart';
import '../services/core/direct/errors.dart';
import '../services/portals/shaladarpan/direct/category_enrolment_worker.dart';
import 'direct_portal_auth.dart';

class DirectCategoryEnrolmentService {
  DirectCategoryEnrolmentService(this.auth);
  final DirectPortalAuth auth;
  Future<Map<String, dynamic>> fetch({
    String? schoolId,
    String? session,
    bool mprBundle = false,
  }) async {
    final school = auth.authenticatedSchoolId;
    Future<Map<String, dynamic>> execute() async {
      if (!auth.isVerified)
        return CategoryEnrolmentWorker.failure(
          'SESSION_EXPIRED',
          'School portal session expired.',
        );
      return CategoryEnrolmentWorker(
        request: auth.categoryEnrolmentRequest,
        baseUrl: () => Uri.https(
          'rajshaladarpan.rajasthan.gov.in',
          '/${auth.verifiedNode}/',
        ),
        schoolId: () => auth.authenticatedSchoolId ?? '',
        check: () {
          if (!auth.isVerified)
            throw const EnrolmentReportError(
              'SESSION_EXPIRED',
              'School portal session expired.',
            );
          if (auth.authenticatedSchoolId != school)
            throw const EnrolmentReportError(
              'ACCOUNT_CHANGED',
              'School account changed while fetching the report.',
            );
        },
      ).fetch(requestedSchoolId: schoolId, session: session);
    }

    try {
      final co = auth.coordinator;
      if (co == null) return await execute();
      return await co.run(
        resource: mprBundle ? 'mpr.enrolment' : 'school.category_enrolment',
        kind: Kind.read,
        timeout: mprBundle ? 60 : 75,
        maxAttempts: mprBundle ? 1 : 3,
        label: mprBundle ? 'mpr_enrolment_http' : 'category_enrolment_fetch',
        worker: (_) => execute(),
      );
    } on CoordinatorError catch (e) {
      return CategoryEnrolmentWorker.failure(e.kind.code, e.message);
    }
  }
}
