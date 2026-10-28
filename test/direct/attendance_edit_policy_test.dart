import 'package:flutter_test/flutter_test.dart';
import 'package:shaladarpan/tabs/student/modules/student_attendance/attendance_edit_policy.dart';

void main() {
  final today = DateTime(2026, 10, 28, 23, 59);
  test('today stays editable regardless of time of day', () {
    expect(
      isHistoricalAttendanceUpdateLocked(DateTime(2026, 10, 28), today),
      isFalse,
    );
  });
  test('yesterday is view-only', () {
    expect(
      isHistoricalAttendanceUpdateLocked(DateTime(2026, 10, 27, 23, 59), today),
      isTrue,
    );
  });
  test('older dates are view-only', () {
    expect(
      isHistoricalAttendanceUpdateLocked(DateTime(2026, 9, 1), today),
      isTrue,
    );
  });
  for (final dates in [
    (DateTime(2026, 10, 28, 23, 59), DateTime(2026, 10, 29)),
    (DateTime(2026, 12, 31), DateTime(2027, 1, 1)),
    (DateTime(2028, 2, 29), DateTime(2028, 3, 1)),
  ]) {
    test('entry locks across calendar boundary ${dates.$2}', () {
      expect(isHistoricalAttendanceUpdateLocked(dates.$1, dates.$2), isTrue);
    });
  }
}
