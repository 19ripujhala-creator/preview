/// Calendar clock used by the Shala Darpan attendance portal (IST).
DateTime attendanceIndiaTimeAt(DateTime instant) =>
    instant.toUtc().add(const Duration(hours: 5, minutes: 30));

DateTime attendanceIndiaNow() => attendanceIndiaTimeAt(DateTime.now());

/// A portal calendar date, represented at local midnight for date pickers.
/// Convert the instant to IST before taking its year/month/day fields.
DateTime attendanceDateAt(DateTime instant) {
  final india = attendanceIndiaTimeAt(instant);
  return DateTime(india.year, india.month, india.day);
}

DateTime attendanceToday() => attendanceDateAt(DateTime.now());

/// Past attendance is view-only, including a previously pending entry.
bool isHistoricalAttendanceUpdateLocked(DateTime selectedDate, DateTime now) {
  final selected = DateTime(
    selectedDate.year,
    selectedDate.month,
    selectedDate.day,
  );
  final today = DateTime(now.year, now.month, now.day);
  return selected.isBefore(today);
}
