import 'package:flutter/material.dart';

// Calendar retained from Leave Apply, with the same layout and controls.
Future<DateTime?> showPortalCalendar(BuildContext ctx, DateTime initial, DateTime first, DateTime last) async {
    DateTime displayedMonth = DateTime(initial.year, initial.month);
    DateTime selectedDate = initial;

    return await showDialog<DateTime>(
      context: ctx,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (context) {
        return Theme(
          data: ThemeData.light(useMaterial3: true).copyWith(
            splashFactory: NoSplash.splashFactory,
            colorScheme: const ColorScheme(
              brightness: Brightness.light,
              primary: Color(0xFF0F172A),
              onPrimary: Colors.white,
              secondary: Color(0xFF0F172A),
              onSecondary: Colors.white,
              error: Color(0xFFDC2626),
              onError: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xFF0F172A),
              surfaceTint: Colors.transparent,
            ),
          ),
          child: StatefulBuilder(
            builder: (context, setDialogState) {
              final int year = displayedMonth.year;
              final int month = displayedMonth.month;
              final int daysInMonth = DateUtils.getDaysInMonth(year, month);
              final int firstWeekday = DateTime(year, month, 1).weekday;
              const List<String> monthNames = [
                "",
                "January",
                "February",
                "March",
                "April",
                "May",
                "June",
                "July",
                "August",
                "September",
                "October",
                "November",
                "December",
              ];
              final List<int> yearsList = List.generate(31, (i) => 2015 + i);

              return Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  width: 285,
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 20, offset: const Offset(0, 6))],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: Row(
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
                                        fontFamily: 'PlusJakartaSans',
                                        fontSize: 12.5,
                                        fontWeight: i == month ? FontWeight.w700 : FontWeight.w500,
                                        color: i == month ? const Color(0xFFEF4444) : const Color(0xFF0F172A),
                                      ),
                                    ),
                                  ),
                              ],
                              onSelected: (val) => setDialogState(() => displayedMonth = DateTime(year, val)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    monthNames[month],
                                    style: const TextStyle(
                                      fontFamily: 'PlusJakartaSans',
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  const Icon(Icons.arrow_drop_down_rounded, size: 21, color: Color(0xFFEF4444)),
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
                                        fontFamily: 'PlusJakartaSans',
                                        fontSize: 12.5,
                                        fontWeight: y == year ? FontWeight.w700 : FontWeight.w500,
                                        color: y == year ? const Color(0xFFEF4444) : const Color(0xFF0F172A),
                                      ),
                                    ),
                                  ),
                              ],
                              onSelected: (val) => setDialogState(() => displayedMonth = DateTime(val, month)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    "$year",
                                    style: const TextStyle(
                                      fontFamily: 'PlusJakartaSans',
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  const Icon(Icons.arrow_drop_down_rounded, size: 21, color: Color(0xFFEF4444)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: const [
                          Text(
                            "Mo",
                            style: TextStyle(fontFamily: 'PlusJakartaSans', fontSize: 10.0, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8)),
                          ),
                          Text(
                            "Tu",
                            style: TextStyle(fontFamily: 'PlusJakartaSans', fontSize: 10.0, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8)),
                          ),
                          Text(
                            "We",
                            style: TextStyle(fontFamily: 'PlusJakartaSans', fontSize: 10.0, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8)),
                          ),
                          Text(
                            "Th",
                            style: TextStyle(fontFamily: 'PlusJakartaSans', fontSize: 10.0, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8)),
                          ),
                          Text(
                            "Fr",
                            style: TextStyle(fontFamily: 'PlusJakartaSans', fontSize: 10.0, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8)),
                          ),
                          Text(
                            "Sa",
                            style: TextStyle(fontFamily: 'PlusJakartaSans', fontSize: 10.0, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8)),
                          ),
                          Text(
                            "Su",
                            style: TextStyle(fontFamily: 'PlusJakartaSans', fontSize: 10.0, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
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
                          final bool isDisabled =
                              currentCellDate.isBefore(DateTime(first.year, first.month, first.day)) ||
                              currentCellDate.isAfter(DateTime(last.year, last.month, last.day));
                          final bool isSelected =
                              currentCellDate.year == selectedDate.year &&
                              currentCellDate.month == selectedDate.month &&
                              currentCellDate.day == selectedDate.day;

                          return GestureDetector(
                            onTap: isDisabled ? null : () => setDialogState(() => selectedDate = currentCellDate),
                            child: Container(
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFFEF4444) : Colors.transparent,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                "$day",
                                style: TextStyle(
                                  fontFamily: 'PlusJakartaSans',
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
                      const SizedBox(height: 10),
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
                            child: const Text(
                              "Cancel",
                              style: TextStyle(fontFamily: 'PlusJakartaSans', fontSize: 10.5, color: Color(0xFF64748B)),
                            ),
                          ),
                          const SizedBox(width: 6),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context, selectedDate),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0F172A),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              minimumSize: const Size(38, 28),
                              elevation: 0,
                            ),
                            child: const Text(
                              "OK",
                              style: TextStyle(fontFamily: 'PlusJakartaSans', fontSize: 10.5, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
