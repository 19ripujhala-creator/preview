// lib/tabs/student/modules/student_attendance/widgets/custom_calendar_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../screens/school_report_screen.dart';

const String kAppFont = 'PlusJakartaSans';

/// Top-Right Mini iOS Calendar Badge + "View" label.
/// Tap karne par school attendance report (PDF) app me khulti hai.
class IosCalendarBadgeWidget extends StatelessWidget {
  final DateTime date;
  final VoidCallback? onTap;
  const IosCalendarBadgeWidget({super.key, required this.date, this.onTap});

  @override
  Widget build(BuildContext context) {
    const dayNames = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    final String currentDayName = dayNames[date.weekday - 1];
    final String currentDayNum = '${date.day}';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        if (onTap != null) {
          onTap!();
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => SchoolReportScreen(date: date)),
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: const Color(0xFFE2E8F0), width: 1.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  currentDayName,
                  style: const TextStyle(
                    fontFamily: kAppFont,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFEF4444),
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  currentDayNum,
                  style: const TextStyle(
                    fontFamily: kAppFont,
                    fontSize: 16.0,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 3),
          const Text(
            'View',
            style: TextStyle(
              fontFamily: kAppFont,
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF475569),
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom Interactive Calendar Dialog with Month/Year Selection
Future<DateTime?> showCustomCalendarDialog({
  required BuildContext context,
  required DateTime initialDate,
}) {
  DateTime tempDate = initialDate;

  return showDialog<DateTime>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withOpacity(0.4),
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          final int year = tempDate.year;
          final int month = tempDate.month;
          final int daysInMonth = DateUtils.getDaysInMonth(year, month);
          final int firstWeekday = DateTime(year, month, 1).weekday;
          const List<String> monthNames = [
            "", "January", "February", "March", "April", "May", "June",
            "July", "August", "September", "October", "November", "December"
          ];
          final List<int> yearsList = List.generate(31, (i) => 2015 + i);

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              width: 290,
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  )
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Month & Year Selector
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      PopupMenuButton<int>(
                        initialValue: month,
                        color: Colors.white,
                        elevation: 3,
                        offset: const Offset(0, 30),
                        constraints: const BoxConstraints(maxHeight: 200, maxWidth: 130),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        itemBuilder: (context) => [
                          for (int i = 1; i <= 12; i++)
                            PopupMenuItem<int>(
                              value: i,
                              height: 35,
                              child: Text(
                                monthNames[i],
                                style: TextStyle(
                                  fontFamily: kAppFont,
                                  fontSize: 12.5,
                                  fontWeight: i == month ? FontWeight.w700 : FontWeight.w500,
                                  color: i == month ? const Color(0xFFEF4444) : const Color(0xFF0F172A),
                                ),
                              ),
                            ),
                        ],
                        onSelected: (val) {
                          setDialogState(() {
                            final maxDays = DateUtils.getDaysInMonth(year, val);
                            tempDate = DateTime(year, val, tempDate.day > maxDays ? maxDays : tempDate.day);
                          });
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              monthNames[month],
                              style: const TextStyle(
                                fontFamily: kAppFont,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(width: 2),
                            const Icon(Icons.arrow_drop_down_rounded, size: 22, color: Color(0xFFEF4444)),
                          ],
                        ),
                      ),
                      PopupMenuButton<int>(
                        initialValue: year,
                        color: Colors.white,
                        elevation: 3,
                        offset: const Offset(0, 30),
                        constraints: const BoxConstraints(maxHeight: 200, maxWidth: 95),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        itemBuilder: (context) => [
                          for (final y in yearsList)
                            PopupMenuItem<int>(
                              value: y,
                              height: 35,
                              child: Text(
                                "$y",
                                style: TextStyle(
                                  fontFamily: kAppFont,
                                  fontSize: 12.5,
                                  fontWeight: y == year ? FontWeight.w700 : FontWeight.w500,
                                  color: y == year ? const Color(0xFFEF4444) : const Color(0xFF0F172A),
                                ),
                              ),
                            ),
                        ],
                        onSelected: (val) {
                          setDialogState(() {
                            final maxDays = DateUtils.getDaysInMonth(val, month);
                            tempDate = DateTime(val, month, tempDate.day > maxDays ? maxDays : tempDate.day);
                          });
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              "$year",
                              style: const TextStyle(
                                fontFamily: kAppFont,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(width: 2),
                            const Icon(Icons.arrow_drop_down_rounded, size: 22, color: Color(0xFFEF4444)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Week Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: const [
                      Text("Mo", style: TextStyle(fontFamily: kAppFont, fontSize: 10.0, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8))),
                      Text("Tu", style: TextStyle(fontFamily: kAppFont, fontSize: 10.0, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8))),
                      Text("We", style: TextStyle(fontFamily: kAppFont, fontSize: 10.0, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8))),
                      Text("Th", style: TextStyle(fontFamily: kAppFont, fontSize: 10.0, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8))),
                      Text("Fr", style: TextStyle(fontFamily: kAppFont, fontSize: 10.0, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8))),
                      Text("Sa", style: TextStyle(fontFamily: kAppFont, fontSize: 10.0, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8))),
                      Text("Su", style: TextStyle(fontFamily: kAppFont, fontSize: 10.0, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8))),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Days Grid
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      mainAxisSpacing: 2.5,
                      crossAxisSpacing: 2.5,
                    ),
                    itemCount: daysInMonth + (firstWeekday - 1),
                    itemBuilder: (context, index) {
                      if (index < firstWeekday - 1) return const SizedBox.shrink();
                      final int day = index - (firstWeekday - 2);
                      final DateTime currentCellDate = DateTime(year, month, day);

                      final bool isDisabled = currentCellDate.isAfter(DateTime.now());
                      final bool isSelected = currentCellDate.year == tempDate.year &&
                          currentCellDate.month == tempDate.month &&
                          currentCellDate.day == tempDate.day;

                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: isDisabled
                            ? null
                            : () => setDialogState(() => tempDate = currentCellDate),
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFFEF4444) : Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            "$day",
                            style: TextStyle(
                              fontFamily: kAppFont,
                              fontSize: 11.0,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                              color: isDisabled
                                  ? const Color(0xFFCBD5E1)
                                  : isSelected
                                      ? Colors.white
                                      : const Color(0xFF1E293B),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  // Action Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: () => Navigator.pop(context, null),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          minimumSize: const Size(48, 28),
                        ),
                        child: const Text("Cancel", style: TextStyle(fontFamily: kAppFont, fontSize: 10.5, color: Color(0xFF64748B))),
                      ),
                      const SizedBox(width: 6),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, tempDate),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F172A),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          minimumSize: const Size(38, 28),
                          elevation: 0,
                        ),
                        child: const Text("OK", style: TextStyle(fontFamily: kAppFont, fontSize: 10.5, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}