import 'package:flutter_test/flutter_test.dart';
import 'package:shaladarpan/tabs/student/modules/student_attendance/attendance_edit_policy.dart';

void main() {
  for (final c in [
    ('2026-10-28T18:29:59Z', DateTime(2026, 10, 28)),
    ('2026-10-28T18:30:00Z', DateTime(2026, 10, 29)),
    ('2026-10-28T21:48:00Z', DateTime(2026, 10, 29)),
    ('2026-12-31T18:30:00Z', DateTime(2027, 1, 1)),
    ('2028-02-28T18:30:00Z', DateTime(2028, 2, 29)),
    ('2028-02-29T18:30:00Z', DateTime(2028, 3, 1)),
  ]) {
    test('portal date at ${c.$1} is ${c.$2}', () {
      final instant = DateTime.parse(c.$1);
      final selected = attendanceDateAt(instant);
      final portalNow = attendanceIndiaTimeAt(instant);
      expect(selected, c.$2);
      expect(isHistoricalAttendanceUpdateLocked(selected, portalNow), isFalse);
      expect(
        isHistoricalAttendanceUpdateLocked(
          DateTime(selected.year, selected.month, selected.day - 1),
          portalNow,
        ),
        isTrue,
      );
    });
  }
  test(
    'same instant in UTC, IST and negative-offset notation selects same date',
    () {
      final expected = DateTime(2026, 10, 29);
      for (final value in [
        '2026-10-28T21:48:00Z',
        '2026-10-29T03:18:00+05:30',
        '2026-10-28T14:48:00-07:00',
      ]) {
        expect(attendanceDateAt(DateTime.parse(value)), expected);
      }
    },
  );
  test(
    'calendar permits IST today while the runner is on the previous UTC date',
    () {
      final instant = DateTime.parse('2026-10-28T21:48:00Z');
      final today = attendanceDateAt(instant);
      expect(DateTime(2026, 10, 29).isAfter(today), isFalse);
      expect(DateTime(2026, 10, 30).isAfter(today), isTrue);
    },
  );
}
