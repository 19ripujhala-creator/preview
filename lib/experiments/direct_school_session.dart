import '../services/core/direct/coordinator.dart';
import 'direct_portal_auth.dart';
import 'direct_student_attendance_service.dart';
import 'direct_staff_attendance_service.dart';
import 'direct_leave_approval_service.dart';
import 'direct_class_mapping_service.dart';
import 'direct_incharge_service.dart';
import 'direct_student_kpi_service.dart';
import 'direct_category_enrolment_service.dart';
import 'direct_monthly_task_service.dart';
import 'direct_nic_catalog_service.dart';
import 'direct_format5_service.dart';
import 'direct_working_days_service.dart';
import 'direct_monthly_attendance_service.dart';
import 'direct_native_print_service.dart';

/// Keeps the already authenticated HTTP session alive across screens.
/// Nothing is persisted or shared with the Python backend.
class DirectSchoolSession {
  DirectSchoolSession._();
  static DirectPortalAuth? _auth;
  static DirectStudentAttendanceService? _service;
  static DirectStaffAttendanceService? _staff;
  static DirectLeaveApprovalService? _leave;
  static DirectClassMappingService? _mapping;
  static DirectInchargeService? _incharge;
  static DirectStudentKpiService? _kpi;
  static DirectCategoryEnrolmentService? _enrolment;
  static DirectMonthlyTaskService? _monthly;
  static DirectNativePrintService? _nativePrint;
  static DirectNativePrintService? get nativePrint =>
      available ? _nativePrint : null;
  static DirectMonthlyAttendanceService? _monthlyAttendance;
  static DirectMonthlyAttendanceService? get monthlyAttendance => available ? _monthlyAttendance : null;
  static DirectWorkingDaysService? _workingDays;
  static DirectWorkingDaysService? get workingDays => available ? _workingDays : null;
  static DirectFormat5Service? _format5;
  static DirectFormat5Service? get format5 => available ? _format5 : null;
  static DirectNicCatalogService? _nicCatalog;
  static DirectNicCatalogService? get nicCatalog =>
      available ? _nicCatalog : null;
  static DirectMonthlyTaskService? get monthlyTasks =>
      available ? _monthly : null;
  static String _schoolId = '';

  static bool get ready => _auth?.isVerified == true && _service != null;
  static bool get available =>
      _auth != null &&
      _service != null &&
      _schoolId.isNotEmpty &&
      (_auth!.isVerified || _auth!.canRecover);
  static PortalCoordinator? get coordinator => _auth?.coordinator;

  static String get schoolId => _schoolId;
  static DirectStudentAttendanceService? get attendance =>
      available ? _service : null;
  static DirectStaffAttendanceService? get staffAttendance =>
      available ? _staff : null;
  static DirectLeaveApprovalService? get leaveApprovals =>
      available ? _leave : null;

  static DirectClassMappingService? get classMappings =>
      available ? _mapping : null;

  static DirectInchargeService? get incharge => available ? _incharge : null;

  static DirectStudentKpiService? get studentKpi => available ? _kpi : null;

  static DirectCategoryEnrolmentService? get categoryEnrolment =>
      available ? _enrolment : null;

  static void attach(DirectPortalAuth auth, String schoolId) {
    if (!auth.isVerified || schoolId.trim().isEmpty) {
      throw StateError('A verified direct login and school ID are required.');
    }
    if (_auth?.sharesSessionWith(auth) == true) {
      _auth?.detachSharedView();
    } else {
      reset();
    }
    _auth = auth;
    _schoolId = schoolId.trim();
    _service = DirectStudentAttendanceService(auth);
    _staff = DirectStaffAttendanceService(auth);
    _leave = DirectLeaveApprovalService(auth);
    _mapping = DirectClassMappingService(auth);
    _incharge = DirectInchargeService(auth);
    _kpi = DirectStudentKpiService(auth, _service!);
    _enrolment = DirectCategoryEnrolmentService(auth);
    _monthly = DirectMonthlyTaskService(auth);
    _nicCatalog = DirectNicCatalogService(auth);
    _format5 = DirectFormat5Service(auth);
    _workingDays = DirectWorkingDaysService(auth);
    _monthlyAttendance = DirectMonthlyAttendanceService(auth);
    _nativePrint = DirectNativePrintService(auth);
  }

  static void reset() {
    _auth?.close();
    _auth = null;
    _service = null;
    _staff = null;
    _leave = null;
    _mapping = null;
    _incharge = null;
    _kpi = null;
    _enrolment = null;
    _monthly = null;
    _nicCatalog = null;
    _format5 = null;
    _workingDays = null;
    _monthlyAttendance = null;
    _nativePrint = null;
    _schoolId = '';
  }
}
