import '../services/core/direct/coordinator.dart';
import '../services/core/direct/errors.dart';
import '../services/portals/shaladarpan/direct/class_mapping_worker.dart';
import '../services/portals/shaladarpan/direct/student_kpi.dart';
import 'direct_portal_auth.dart';
import 'direct_student_attendance_service.dart';

class DirectStudentKpiService {
  DirectStudentKpiService(this.auth, this.attendance);
  final DirectPortalAuth auth;
  final DirectStudentAttendanceService attendance;
  Future<Map<String, dynamic>> fetch() async {
    var key = auth.schoolSessionIdentity;
    final school = auth.authenticatedSchoolId;
    Future<Map<String, dynamic>> execute() async {
      if (auth.authenticatedSchoolId == school)
        key = auth.schoolSessionIdentity;
      return StudentKpiWorker(
        request: auth.studentKpiRequest,
        baseUrl: () => Uri.https(
          'rajshaladarpan.rajasthan.gov.in',
          '/${auth.verifiedNode}/',
        ),
        schoolId: () => auth.authenticatedSchoolId ?? '',
        sessionKey: () => auth.schoolSessionIdentity,
        check: () {
          if (!auth.isVerified ||
              auth.authenticatedSchoolId != school ||
              key.isEmpty ||
              key != auth.schoolSessionIdentity) {
            throw const MappingError(
              'ACCOUNT_CHANGED',
              'School login session changed. Fetch class mapping again.',
            );
          }
        },
      ).fetch();
    }

    try {
      final co = auth.coordinator;
      if (co == null) return await execute();
      return await co.run(
        resource: 'sd.student',
        kind: Kind.read,
        timeout: 60,
        maxAttempts: 3,
        label: 'student_kpi',
        worker: (_) => execute(),
      );
    } on CoordinatorError catch (e) {
      return {'success': false, 'code': e.kind.code, 'message': e.message};
    }
  }

  Future<Map<String, dynamic>> fetchDashboard() async {
    final school = auth.authenticatedSchoolId;
    try {
      await auth.coordinator?.ensureReady(Kind.read);
    } on CoordinatorError catch (e) {
      return {'success': false, 'code': e.kind.code, 'message': e.message};
    }
    if (auth.authenticatedSchoolId != school)
      return {
        'success': false,
        'code': 'ACCOUNT_CHANGED',
        'message': 'School account changed during sync.',
      };
    final key = auth.schoolSessionIdentity;
    if (!auth.isVerified || key.isEmpty)
      return {
        'success': false,
        'code': 'SESSION_EXPIRED',
        'message': 'Direct school session unavailable.',
      };
    final now = DateTime.now().toUtc().add(
      const Duration(hours: 5, minutes: 30),
    );
    final date =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    final summary = await attendance.fetchClassSummaryResponse(date: date);
    if (!auth.isVerified ||
        school != auth.authenticatedSchoolId ||
        key != auth.schoolSessionIdentity) {
      return {
        'success': false,
        'code': 'ACCOUNT_CHANGED',
        'message': 'Account changed during sync.',
      };
    }
    try {
      return StudentKpiWorker.dashboard(summary);
    } catch (_) {
      return {
        'success': false,
        'code': 'INVALID_RESULT',
        'message': 'Student class summary is invalid.',
      };
    }
  }
}
