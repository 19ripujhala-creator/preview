import 'package:flutter_test/flutter_test.dart';
import 'package:shaladarpan/experiments/student_attendance_parity.dart';

void main() {
  test('duplicate row identity rejected when SR is missing', () {
    final current = <Map<String, Object?>>[
      {'serialNo': 1, 'name': 'A', 'status': 'Present'},
      {'serialNo': 2, 'name': 'B', 'status': 'Absent'},
    ];
    expect(() => StudentAttendanceParity.plan(current: current, requested: [
      {'serialNo': 1, 'name': 'A', 'status': 'Present'},
      {'serialNo': 1, 'name': 'A', 'status': 'Absent'},
    ]), throwsA(isA<AttendanceParityException>()));
  });
  test('unrecognized portal result is not a successful verification', () {
    final current = <Map<String, Object?>>[
      {'srNo': '101', 'status': 'Present'},
      {'srNo': '102', 'status': 'Absent'},
    ];
    final plan = StudentAttendanceParity.plan(current: current, requested: [
      {'srNo': '101', 'status': 'Absent'},
      {'srNo': '102', 'status': 'Present'},
    ]);
    expect(StudentAttendanceParity.readBackMatches(plan, [
      {'srNo': '101', 'status': null},
      {'srNo': '102', 'status': 'Present'},
    ]), false);
  });
  test('an incomplete actual register never verifies', () {
    final plan = StudentAttendanceParity.plan(current: [
      {'srNo': '101', 'status': 'Present'},
      {'srNo': '102', 'status': 'Absent'},
    ], requested: [
      {'srNo': '101', 'status': 'Present'},
      {'srNo': '102', 'status': 'Absent'},
    ]);
    expect(StudentAttendanceParity.readBackMatches(plan, [
      {'srNo': '101', 'status': 'Present'},
    ]), false);
  });
}
