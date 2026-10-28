/// Calendar clock used by the Shala Darpan attendance portal (IST).
DateTime attendanceIndiaNow() =>
    DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));

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
