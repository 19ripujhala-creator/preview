/// One identity format for MDM producers and dashboard listeners.
String dashboardMdmDayKey(
  String school,
  DateTime day, {
  required bool direct,
}) =>
    '${direct ? "direct" : "backend"}/$school/${day.year}-${day.month}-${day.day}';
