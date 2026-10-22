import 'package:flutter_test/flutter_test.dart';
import 'package:shaladarpan/experiments/student_attendance_parity.dart';

void main() {
  final current = <Map<String, Object?>>[
    {'srNo': '00123', 'name': 'Student A', 'serialNo': 1, 'status': 'Present'},
    {'srNo': '00456', 'name': 'Student B', 'serialNo': 2, 'status': 'Absent'},
  ];
  test('SR normalization and strict real date', () {
    expect(StudentAttendanceParity.normalizeSr(' 000123 '), '123');
    expect(StudentAttendanceParity.normalizeSr('000'), '0');
    expect(StudentAttendanceParity.normalizeDate('1-2-2026'), '01/02/2026');
    expect(() => StudentAttendanceParity.normalizeDate('31/02/2026'), throwsA(isA<AttendanceParityException>()));
  });
  test('P/A/L/M and unselected radio', () {
    expect(StudentAttendanceParity.normalizeStatus('On Medical', 0), 'OnMedical');
    expect(StudentAttendanceParity.normalizeStatus('अवकाश', 0), 'OnLeave');
    expect(StudentAttendanceParity.normalizeStatus('', -1), isNull);
  });
  test('same roster generates expected update plan', () {
    final desired = <Map<String, Object?>>[
      {'srNo': '123', 'status': 'Present'},
      {'srNo': '456', 'status': 'OnLeave'},
    ];
    final plan = StudentAttendanceParity.plan(current: current, requested: desired);
    expect(plan.changedCount, 1);
    expect(StudentAttendanceParity.readBackMatches(plan, [
      {'srNo': '123', 'status': 'Present'},
      {'srNo': '456', 'status': 'OnLeave'},
    ]), true);
    expect(StudentAttendanceParity.readBackMatches(plan, current), false);
  });
  test('rejects missing students, duplicate ids and wrong status', () {
    expect(() => StudentAttendanceParity.plan(current: current, requested: [
      {'srNo': '123', 'status': 'Present'},
    ]), throwsA(isA<AttendanceParityException>()));
    expect(() => StudentAttendanceParity.plan(current: current, requested: [
      {'srNo': '123', 'status': 'Present'},
      {'srNo': '00123', 'status': 'Absent'},
    ]), throwsA(isA<AttendanceParityException>()));
    expect(() => StudentAttendanceParity.plan(current: current, requested: [
      {'srNo': '123', 'status': 'Unknown'},
      {'srNo': '456', 'status': 'Absent'},
    ]), throwsA(isA<AttendanceParityException>()));
  });
  test('finalized correction must be same Rajasthan date', () {
    final today = DateTime(2026, 10, 10);
    expect(StudentAttendanceParity.canCorrectMarkedAttendance(portalDate: '10/10/2026', indiaToday: today), true);
    expect(StudentAttendanceParity.canCorrectMarkedAttendance(portalDate: '09/10/2026', indiaToday: today), false);
  });
}
