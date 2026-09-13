import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'janaadharauth.dart';

const String kAppFont = 'PlusJakartaSans';

class StaffLoginView extends StatefulWidget {
  const StaffLoginView({super.key});

  @override
  State<StaffLoginView> createState() => _StaffLoginViewState();
}

class _StaffLoginViewState extends State<StaffLoginView> {
  int _selectedStaffModuleIndex = 0;
  final ScrollController _tabScrollController = ScrollController();

  final Map<String, String> _currentUser = {
    "name": "Ripudaman Singh Jhala",
    "designation": "Teacher Level-1",
    "nicId": "1553675",
    "staffLoginId": "RJ19882001",
  };

  final List<String> _staffModules = [
    "Leave Apply",
    "Profile (Format-10)",
    "Student Janaadhar Authentication"
  ];

  final List<Map<String, dynamic>> _leaveReasons = [
    {"code": "1", "label": "DOMESTIC / PERSONAL", "icon": CupertinoIcons.person_fill},
    {"code": "2", "label": "CASUAL / INCIDENTAL", "icon": CupertinoIcons.briefcase_fill},
    {"code": "3", "label": "HOSPITALISATION", "icon": CupertinoIcons.bandage_fill},
    {"code": "4", "label": "RECOVERY AFTER HOSPITALISATION", "icon": CupertinoIcons.heart_fill},
    {"code": "5", "label": "MEDICAL GROUND", "icon": CupertinoIcons.plus_circle_fill},
    {"code": "6", "label": "OFFICIAL / DEPARTMENTAL", "icon": CupertinoIcons.building_2_fill},
    {"code": "7", "label": "SPORTING EVENTS - GOVT RECOGNIZED", "icon": CupertinoIcons.sportscourt_fill},
    {"code": "8", "label": "FOR STUDY", "icon": CupertinoIcons.book_fill},
    {"code": "10", "label": "LEAVE FOR VOTE CASTING", "icon": CupertinoIcons.check_mark_circled_solid},
    {"code": "11", "label": "DEPARTMENTAL EXAMINATIONS", "icon": CupertinoIcons.doc_text_fill},
    {"code": "12", "label": "VISIT ABROAD", "icon": CupertinoIcons.airplane},
    {"code": "13", "label": "FAMILY WELFARE PROGRAM", "icon": CupertinoIcons.person_3_fill},
    {"code": "14", "label": "ABSENCE ON ACCOUNT OF BANDH", "icon": CupertinoIcons.exclamationmark_triangle_fill},
    {"code": "15", "label": "MISCARRIAGE, ABORTION", "icon": CupertinoIcons.heart_slash_fill},
    {"code": "16", "label": "CHILD BIRTH", "icon": CupertinoIcons.gift_fill},
    {"code": "17", "label": "DONATES BLOOD", "icon": CupertinoIcons.drop_fill},
    {"code": "18", "label": "LTC", "icon": CupertinoIcons.ticket_fill},
    {"code": "19", "label": "CARE OF MINOR CHILDREN NEEDS", "icon": CupertinoIcons.person_crop_circle_fill_badge_checkmark},
    {"code": "20", "label": "OTHER", "icon": CupertinoIcons.ellipsis_circle_fill},
    {"code": "21", "label": "Restricted Holiday", "icon": CupertinoIcons.star_fill},
  ];

  final List<Map<String, dynamic>> _leaveTypes = [
    {"code": "1", "label": "Casual Leave / आकस्मिक अवकाश (CL)", "short": "CL", "icon": CupertinoIcons.briefcase_fill},
    {"code": "2", "label": "Commuted Leave / रूपांतरित अवकाश", "short": "Commuted", "icon": CupertinoIcons.arrow_2_squarepath},
    {"code": "3", "label": "Half Pay Leave (HPL)", "short": "HPL", "icon": CupertinoIcons.circle_lefthalf_fill},
    {"code": "4", "label": "Maternity Leave / मातृत्व अवकाश (ML)", "short": "ML", "icon": CupertinoIcons.heart_fill},
    {"code": "5", "label": "Paternity Leave / पितृत्व अवकाश", "short": "PL", "icon": CupertinoIcons.person_fill},
    {"code": "6", "label": "Child Care Leave / संतान पालन अवकाश (CCL)", "short": "CCL", "icon": CupertinoIcons.person_crop_circle_fill},
    {"code": "7", "label": "Study Leave / अध्ययन अवकाश", "short": "Study", "icon": CupertinoIcons.book_fill},
    {"code": "8", "label": "Leave without Pay / अवैतनिक अवकाश (LWP)", "short": "LWP", "icon": CupertinoIcons.money_dollar},
    {"code": "9", "label": "Compensative Casual Leave (CCL)", "short": "Comp CCL", "icon": CupertinoIcons.plus_square_fill},
    {"code": "10", "label": "Priviledge Leave / उपार्जित अवकाश (PL)", "short": "PL", "icon": CupertinoIcons.star_circle_fill},
    {"code": "11", "label": "सवैतनिक अवकाश (सव. अव.)", "short": "Salaried", "icon": CupertinoIcons.checkmark_seal_fill},
    {"code": "12", "label": "Half CL (HCL)", "short": "HCL", "icon": CupertinoIcons.circle_lefthalf_fill},
    {"code": "96", "label": "On Headquarter Only", "short": "HQ Only", "icon": CupertinoIcons.location_fill},
    {"code": "97", "label": "On HQ with COVID-19 Duty", "short": "HQ Covid", "icon": CupertinoIcons.shield_lefthalf_fill},
    {"code": "98", "label": "Out of Headquarter", "short": "Out HQ", "icon": CupertinoIcons.compass_fill},
    {"code": "13", "label": "Quarantine Leave", "short": "Quarantine", "icon": CupertinoIcons.bandage_fill},
    {"code": "14", "label": "Restricted Holiday / ऐच्छिक अवकाश (RH)", "short": "RH", "icon": CupertinoIcons.calendar},
  ];

  final List<Map<String, dynamic>> _durationOptions = [
    {"code": "1", "label": "Full day", "icon": CupertinoIcons.sun_max_fill},
    {"code": "2", "label": "Half day", "icon": CupertinoIcons.circle_lefthalf_fill},
  ];

  final List<Map<String, dynamic>> _dayTypeOptions = [
    {"code": "1", "label": "Forenoon", "icon": CupertinoIcons.sunrise_fill},
    {"code": "2", "label": "Afternoon", "icon": CupertinoIcons.sunset_fill},
  ];

  final List<Map<String, dynamic>> _myLeaveHistory = [
    {
      "id": "ML-2026-01",
      "typeCode": "4",
      "reasonCode": "5",
      "short": "ML",
      "typeName": "Medical Leave",
      "days": 4.0,
      "dateRange": "15-02-2026 - 18-02-2026",
      "status": "Pending",
      "duration": "1",
      "dayType": "1",
      "headquarter": false,
      "address": "",
      "remark": "Doctor prescribed rest",
      "icon": CupertinoIcons.bandage_fill,
    },
    {
      "id": "CL-2026-02",
      "typeCode": "1",
      "reasonCode": "1",
      "short": "CL",
      "typeName": "Casual Leave",
      "days": 1.0,
      "dateRange": "20-01-2026 - 20-01-2026",
      "status": "Approved",
      "duration": "1",
      "dayType": "1",
      "headquarter": false,
      "address": "",
      "remark": "Family event",
      "icon": CupertinoIcons.briefcase_fill,
    },
  ];

  @override
  void dispose() {
    _tabScrollController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime date) {
    return "${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year}";
  }

  String _getInitials(String name) {
    List<String> parts = name.trim().split(' ');
    if (parts.isEmpty) return "";
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return "${parts[0][0]}${parts[parts.length - 1][0]}".toUpperCase();
  }

  void _showAppleToast(String message, {IconData icon = CupertinoIcons.checkmark_circle_fill}) {
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (context) => Positioned(
        top: 24,
        left: 20,
        right: 20,
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutBack,
              tween: Tween(begin: 0.0, end: 1.0),
              builder: (context, value, child) {
                return Opacity(
                  opacity: value.clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, -16 * (1 - value)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 16, offset: const Offset(0, 6))],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, color: const Color(0xFF34C759), size: 18),
                          const SizedBox(width: 8),
                          Flexible(child: Text(message, style: const TextStyle(fontFamily: kAppFont, fontSize: 12.0, fontWeight: FontWeight.w600, color: Colors.white), overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );

    overlay.insert(entry);
    Future.delayed(const Duration(milliseconds: 2000), () => entry.remove());
  }

  Future<DateTime?> _pickMinimalDate(BuildContext ctx, DateTime initial, DateTime first, DateTime last) async {
    DateTime displayedMonth = DateTime(initial.year, initial.month);
    DateTime selectedDate = initial;

    return await showDialog<DateTime>(
      context: ctx,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (context) {
        return Theme(
          data: ThemeData.light(useMaterial3: true).copyWith(
            splashFactory: NoSplash.splashFactory,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            hoverColor: Colors.transparent,
            focusColor: Colors.transparent,
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
                "", "January", "February", "March", "April", "May", "June",
                "July", "August", "September", "October", "November", "December"
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
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 20, offset: const Offset(0, 6))],
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
                                  displayedMonth = DateTime(year, val);
                                });
                              },
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    monthNames[month],
                                    style: const TextStyle(fontFamily: kAppFont, fontSize: 13.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
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
                                  displayedMonth = DateTime(val, month);
                                });
                              },
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    "$year",
                                    style: const TextStyle(fontFamily: kAppFont, fontSize: 13.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
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

                          final bool isDisabled = currentCellDate.isBefore(DateTime(first.year, first.month, first.day));
                          final bool isSelected = currentCellDate.year == selectedDate.year &&
                              currentCellDate.month == selectedDate.month &&
                              currentCellDate.day == selectedDate.day;

                          return GestureDetector(
                            onTap: isDisabled ? null : () {
                              setDialogState(() {
                                selectedDate = currentCellDate;
                              });
                            },
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
                                  color: isDisabled ? const Color(0xFFCBD5E1) : isSelected ? Colors.white : const Color(0xFF1E293B),
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
                              splashFactory: NoSplash.splashFactory,
                              surfaceTintColor: Colors.transparent,
                              overlayColor: Colors.transparent,
                            ),
                            child: const Text("Cancel", style: TextStyle(fontFamily: kAppFont, fontSize: 10.5, color: Color(0xFF64748B))),
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
                              splashFactory: NoSplash.splashFactory,
                              surfaceTintColor: Colors.transparent,
                              overlayColor: Colors.transparent,
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
          ),
        );
      },
    );
  }

  void _openFigmaSelectorDialog({required String title, required List<Map<String, dynamic>> items, required String? selectedCode, required Function(String code, String label) onSelect}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (context) {
        return Theme(
          data: ThemeData.light(useMaterial3: true).copyWith(
            splashFactory: NoSplash.splashFactory,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            hoverColor: Colors.transparent,
            focusColor: Colors.transparent,
          ),
          child: Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Container(
              width: 420,
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.65),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 24, offset: const Offset(0, 10))]),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(title, style: const TextStyle(fontFamily: kAppFont, fontSize: 14.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => Navigator.pop(context),
                          child: const Icon(CupertinoIcons.xmark, size: 16, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFF1F5F9)),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF8FAFC)),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final bool isSelected = item["code"] == selectedCode;
                        return InkWell(
                          onTap: () {
                            onSelect(item["code"]!, item["label"]!);
                            Navigator.pop(context);
                          },
                          borderRadius: BorderRadius.circular(8),
                          splashColor: Colors.transparent,
                          highlightColor: Colors.transparent,
                          hoverColor: Colors.transparent,
                          focusColor: Colors.transparent,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(color: isSelected ? const Color(0xFFF8FAFC) : Colors.transparent, borderRadius: BorderRadius.circular(8)),
                            child: Row(
                              children: [
                                Icon(item["icon"] as IconData, size: 15, color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF64748B)),
                                const SizedBox(width: 10),
                                Expanded(child: Text(item["label"]!, style: TextStyle(fontFamily: kAppFont, fontSize: 12.5, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500, color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF334155)))),
                                if (isSelected) const Icon(CupertinoIcons.checkmark_alt, size: 16, color: Color(0xFF0F172A)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _openRequestLeaveDialog({Map<String, dynamic>? existingRecord}) {
    String? selectedReasonCode = existingRecord?["reasonCode"];
    String selectedReasonLabel = selectedReasonCode != null
        ? _leaveReasons.firstWhere((r) => r["code"] == selectedReasonCode, orElse: () => {"label": "--Select leave reason--"})["label"]!
        : "--Select leave reason--";

    String? selectedTypeCode = existingRecord?["typeCode"];
    String selectedTypeLabel = selectedTypeCode != null
        ? _leaveTypes.firstWhere((t) => t["code"] == selectedTypeCode, orElse: () => {"label": "--Select leave type--"})["label"]!
        : "--Select leave type--";

    DateTime? fromDate = DateTime.now();
    DateTime? toDate = DateTime.now();
    String duration = existingRecord?["duration"] ?? "1";
    String dayType = existingRecord?["dayType"] ?? "1";
    bool headquarterLeaveReq = existingRecord?["headquarter"] ?? false;
    final TextEditingController addressController = TextEditingController(text: existingRecord?["address"] ?? "");
    final TextEditingController remarkController = TextEditingController(text: existingRecord?["remark"] ?? "");

    String? validationError;

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (context) {
        return Theme(
          data: ThemeData.light(useMaterial3: true).copyWith(
            splashFactory: NoSplash.splashFactory,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            hoverColor: Colors.transparent,
            focusColor: Colors.transparent,
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
            radioTheme: RadioThemeData(
              overlayColor: WidgetStateProperty.all(Colors.transparent),
              splashRadius: 0,
            ),
            textSelectionTheme: const TextSelectionThemeData(
              cursorColor: Color(0xFF0F172A),
              selectionColor: Color(0x330F172A),
              selectionHandleColor: Color(0xFF0F172A),
            ),
          ),
          child: StatefulBuilder(
            builder: (context, setModalState) {
              double calculateDays() {
                if (fromDate == null || toDate == null) return 0.0;
                if (toDate!.isBefore(fromDate!)) return 0.0;
                final int spanDays = toDate!.difference(fromDate!).inDays + 1;
                if (duration == "2") {
                  if (spanDays <= 1) return 0.5;
                  return (spanDays - 1) + 0.5;
                }
                return spanDays.toDouble();
              }
              final calculatedDays = calculateDays();

              return Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                child: Container(
                  width: 480,
                  constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 28, offset: const Offset(0, 14))
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 14, 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(existingRecord != null ? "Edit Leave Request" : "Request Leave", style: const TextStyle(fontFamily: kAppFont, fontSize: 16.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                                  const SizedBox(height: 2),
                                  Text(_currentUser["designation"]!, style: const TextStyle(fontFamily: kAppFont, fontSize: 11.5, fontWeight: FontWeight.w500, color: Color(0xFF64748B))),
                                  const SizedBox(height: 1),
                                  Text("NIC ID: ${_currentUser["nicId"]}", style: const TextStyle(fontFamily: kAppFont, fontSize: 11.0, fontWeight: FontWeight.w500, color: Color(0xFF64748B))),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(CupertinoIcons.xmark, size: 18, color: Color(0xFF64748B)),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              splashColor: Colors.transparent,
                              highlightColor: Colors.transparent,
                              hoverColor: Colors.transparent,
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: Color(0xFFE2E8F0)),
                      Flexible(
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (validationError != null) ...[
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEE2E2),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFFFCA5A5)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(CupertinoIcons.exclamationmark_circle_fill, color: Color(0xFFDC2626), size: 16),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          validationError!,
                                          style: const TextStyle(fontFamily: kAppFont, fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFFDC2626)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              _buildFieldLabel("Leave Reason *"),
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  _openFigmaSelectorDialog(
                                    title: "Select Leave Reason",
                                    items: _leaveReasons,
                                    selectedCode: selectedReasonCode,
                                    onSelect: (code, label) {
                                      setModalState(() {
                                        selectedReasonCode = code;
                                        selectedReasonLabel = label;
                                        validationError = null;
                                      });
                                    },
                                  );
                                },
                                child: Container(
                                  height: 42,
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: selectedReasonCode == null && validationError != null ? const Color(0xFFDC2626) : const Color(0xFFCBD5E1)),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(child: Text(selectedReasonLabel, style: TextStyle(fontFamily: kAppFont, fontSize: 12.5, color: selectedReasonCode == null ? const Color(0xFF94A3B8) : const Color(0xFF0F172A)), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                      const Icon(CupertinoIcons.chevron_down, size: 14, color: Color(0xFF64748B)),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              _buildFieldLabel("Leave Type *"),
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  _openFigmaSelectorDialog(
                                    title: "Select Leave Type",
                                    items: _leaveTypes,
                                    selectedCode: selectedTypeCode,
                                    onSelect: (code, label) {
                                      setModalState(() {
                                        selectedTypeCode = code;
                                        selectedTypeLabel = label;
                                        validationError = null;
                                      });
                                    },
                                  );
                                },
                                child: Container(
                                  height: 42,
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: selectedTypeCode == null && validationError != null ? const Color(0xFFDC2626) : const Color(0xFFCBD5E1)),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(child: Text(selectedTypeLabel, style: TextStyle(fontFamily: kAppFont, fontSize: 12.5, color: selectedTypeCode == null ? const Color(0xFF94A3B8) : const Color(0xFF0F172A)), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                      const Icon(CupertinoIcons.chevron_down, size: 14, color: Color(0xFF64748B)),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _buildFieldLabel("From *"),
                                        GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: () async {
                                            final picked = await _pickMinimalDate(context, fromDate ?? DateTime.now(), DateTime(2025), DateTime(2028));
                                            if (picked != null) {
                                              setModalState(() {
                                                fromDate = picked;
                                                if (toDate != null && toDate!.isBefore(fromDate!)) toDate = fromDate;
                                                validationError = null;
                                              });
                                            }
                                          },
                                          child: Container(
                                            height: 40,
                                            padding: const EdgeInsets.symmetric(horizontal: 10),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: fromDate == null && validationError != null ? const Color(0xFFDC2626) : const Color(0xFFCBD5E1)),
                                            ),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Flexible(child: Text(fromDate == null ? "dd--mm--yyyy" : _formatDate(fromDate!), style: const TextStyle(fontFamily: kAppFont, fontSize: 12.0, color: Color(0xFF0F172A)), overflow: TextOverflow.ellipsis)),
                                                Image.asset('assets/icons/leave.png', width: 14, height: 14, color: const Color(0xFF0F172A), errorBuilder: (c, e, s) => const Icon(CupertinoIcons.calendar_today, size: 14, color: Color(0xFF0F172A))),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _buildFieldLabel("To *"),
                                        GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: () async {
                                            final minAllowedDate = fromDate ?? DateTime(2025);
                                            final initialTarget = (toDate != null && !toDate!.isBefore(minAllowedDate)) ? toDate! : minAllowedDate;
                                            final picked = await _pickMinimalDate(context, initialTarget, minAllowedDate, DateTime(2028));
                                            if (picked != null) {
                                              setModalState(() {
                                                toDate = picked;
                                                validationError = null;
                                              });
                                            }
                                          },
                                          child: Container(
                                            height: 40,
                                            padding: const EdgeInsets.symmetric(horizontal: 10),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: toDate == null && validationError != null ? const Color(0xFFDC2626) : const Color(0xFFCBD5E1)),
                                            ),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Flexible(child: Text(toDate == null ? "dd--mm--yyyy" : _formatDate(toDate!), style: const TextStyle(fontFamily: kAppFont, fontSize: 12.0, color: Color(0xFF0F172A)), overflow: TextOverflow.ellipsis)),
                                                Image.asset('assets/icons/leave.png', width: 14, height: 14, color: const Color(0xFF0F172A), errorBuilder: (c, e, s) => const Icon(CupertinoIcons.calendar_today, size: 14, color: Color(0xFF0F172A))),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _buildFieldLabel("Duration *"),
                                        GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: () {
                                            _openFigmaSelectorDialog(
                                              title: "Select Duration",
                                              items: _durationOptions,
                                              selectedCode: duration,
                                              onSelect: (code, label) {
                                                setModalState(() {
                                                  duration = code;
                                                });
                                              },
                                            );
                                          },
                                          child: Container(
                                            height: 40,
                                            padding: const EdgeInsets.symmetric(horizontal: 10),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: const Color(0xFFCBD5E1)),
                                            ),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    duration == "2" ? "Half day" : "Full day",
                                                    style: const TextStyle(fontFamily: kAppFont, fontSize: 12.5, color: Color(0xFF0F172A)),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                const Icon(CupertinoIcons.chevron_down, size: 14, color: Color(0xFF64748B)),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _buildFieldLabel("No of Days"),
                                        Container(
                                          height: 40,
                                          alignment: Alignment.centerLeft,
                                          padding: const EdgeInsets.symmetric(horizontal: 12),
                                          decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFCBD5E1))),
                                          child: Text(calculatedDays % 1 == 0 ? calculatedDays.toInt().toString() : calculatedDays.toString(), style: const TextStyle(fontFamily: kAppFont, fontSize: 13.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              if (duration == "2") ...[
                                const SizedBox(height: 12),
                                _buildFieldLabel("Day Type *"),
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () {
                                    _openFigmaSelectorDialog(
                                      title: "Select Day Type",
                                      items: _dayTypeOptions,
                                      selectedCode: dayType,
                                      onSelect: (code, label) {
                                        setModalState(() {
                                          dayType = code;
                                        });
                                      },
                                    );
                                  },
                                  child: Container(
                                    height: 40,
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: const Color(0xFFCBD5E1)),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            dayType == "2" ? "Afternoon" : "Forenoon",
                                            style: const TextStyle(fontFamily: kAppFont, fontSize: 12.5, color: Color(0xFF0F172A)),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const Icon(CupertinoIcons.chevron_down, size: 14, color: Color(0xFF64748B)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 14),
                              _buildFieldLabel("Headquarter Leave Required *"),
                              Row(
                                children: [
                                  Row(
                                    children: [
                                      Radio<bool>(
                                        value: true,
                                        groupValue: headquarterLeaveReq,
                                        activeColor: const Color(0xFF0F172A),
                                        splashRadius: 0,
                                        onChanged: (val) => setModalState(() => headquarterLeaveReq = val ?? false),
                                      ),
                                      const Text("Yes", style: TextStyle(fontFamily: kAppFont, fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
                                    ],
                                  ),
                                  const SizedBox(width: 20),
                                  Row(
                                    children: [
                                      Radio<bool>(
                                        value: false,
                                        groupValue: headquarterLeaveReq,
                                        activeColor: const Color(0xFF0F172A),
                                        splashRadius: 0,
                                        onChanged: (val) => setModalState(() => headquarterLeaveReq = val ?? false),
                                      ),
                                      const Text("No", style: TextStyle(fontFamily: kAppFont, fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
                                    ],
                                  ),
                                ],
                              ),
                              if (headquarterLeaveReq) ...[
                                const SizedBox(height: 10),
                                _buildFieldLabel("Address During Leave Period *"),
                                TextField(
                                  controller: addressController,
                                  cursorColor: const Color(0xFF0F172A),
                                  style: const TextStyle(fontFamily: kAppFont, fontSize: 12.5, color: Color(0xFF0F172A)),
                                  decoration: InputDecoration(
                                    hintText: "Enter full out-of-station address...",
                                    hintStyle: const TextStyle(fontFamily: kAppFont, fontSize: 12.0, color: Color(0xFF94A3B8)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    filled: true,
                                    fillColor: Colors.white,
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(color: addressController.text.trim().isEmpty && validationError != null ? const Color(0xFFDC2626) : const Color(0xFFCBD5E1)),
                                    ),
                                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF0F172A))),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 14),
                              _buildFieldLabel("Remark (Optional)"),
                              TextField(
                                controller: remarkController,
                                cursorColor: const Color(0xFF0F172A),
                                maxLines: 2,
                                style: const TextStyle(fontFamily: kAppFont, fontSize: 12.5, color: Color(0xFF0F172A)),
                                decoration: const InputDecoration(
                                  hintText: "Please provide a reason or note for your leave request...",
                                  hintStyle: TextStyle(fontFamily: kAppFont, fontSize: 12.0, color: Color(0xFF94A3B8)),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide(color: Color(0xFFCBD5E1))),
                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide(color: Color(0xFFCBD5E1))),
                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide(color: Color(0xFF0F172A))),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Divider(height: 1, color: Color(0xFFE2E8F0)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFFCBD5E1)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                splashFactory: NoSplash.splashFactory,
                                surfaceTintColor: Colors.transparent,
                                overlayColor: Colors.transparent,
                              ),
                              child: const Text("Cancel", style: TextStyle(fontFamily: kAppFont, fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton(
                              onPressed: () {
                                if (selectedReasonCode == null) {
                                  setModalState(() => validationError = "Please select Leave Reason.");
                                  return;
                                }
                                if (selectedTypeCode == null) {
                                  setModalState(() => validationError = "Please select Leave Type.");
                                  return;
                                }
                                if (fromDate == null || toDate == null) {
                                  setModalState(() => validationError = "Please specify From and To dates.");
                                  return;
                                }
                                if (headquarterLeaveReq && addressController.text.trim().isEmpty) {
                                  setModalState(() => validationError = "Please enter Out-of-Station address.");
                                  return;
                                }

                                final String finalType = _leaveTypes.firstWhere((t) => t["code"] == selectedTypeCode)["short"];
                                final String finalFull = _leaveTypes.firstWhere((t) => t["code"] == selectedTypeCode)["label"];

                                setState(() {
                                  if (existingRecord != null) {
                                    existingRecord["typeCode"] = selectedTypeCode;
                                    existingRecord["reasonCode"] = selectedReasonCode;
                                    existingRecord["short"] = finalType;
                                    existingRecord["typeName"] = finalFull;
                                    existingRecord["days"] = calculatedDays;
                                    existingRecord["dateRange"] = "${_formatDate(fromDate!)} - ${_formatDate(toDate!)}";
                                    existingRecord["duration"] = duration;
                                    existingRecord["dayType"] = dayType;
                                    existingRecord["headquarter"] = headquarterLeaveReq;
                                    existingRecord["address"] = addressController.text.trim();
                                    existingRecord["remark"] = remarkController.text.trim();
                                  } else {
                                    _myLeaveHistory.insert(0, {
                                      "id": "LR-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}",
                                      "typeCode": selectedTypeCode,
                                      "reasonCode": selectedReasonCode,
                                      "short": finalType,
                                      "typeName": finalFull,
                                      "days": calculatedDays,
                                      "dateRange": "${_formatDate(fromDate!)} - ${_formatDate(toDate!)}",
                                      "status": "Pending",
                                      "duration": duration,
                                      "dayType": dayType,
                                      "headquarter": headquarterLeaveReq,
                                      "address": addressController.text.trim(),
                                      "remark": remarkController.text.trim(),
                                      "icon": CupertinoIcons.paperplane_fill,
                                    });
                                  }
                                });

                                Navigator.pop(context);
                                _showAppleToast("$finalType application applied successfully");
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0F172A),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                elevation: 0,
                                splashFactory: NoSplash.splashFactory,
                                surfaceTintColor: Colors.transparent,
                                overlayColor: Colors.transparent,
                              ),
                              child: Text(existingRecord != null ? "Update Request" : "Submit Request", style: const TextStyle(fontFamily: kAppFont, fontSize: 12.5, fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ),
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

  void _confirmCancelLeave(int index, String leaveShort) {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (BuildContext ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            width: 360,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 24, offset: const Offset(0, 10))],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Cancel Leave Request",
                  style: TextStyle(fontFamily: kAppFont, fontSize: 16.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                ),
                const SizedBox(height: 8),
                Text(
                  "Are you sure you want to cancel your $leaveShort leave application?",
                  style: const TextStyle(fontFamily: kAppFont, fontSize: 12.5, fontWeight: FontWeight.w500, color: Color(0xFF64748B), height: 1.4),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        splashFactory: NoSplash.splashFactory,
                        surfaceTintColor: Colors.transparent,
                        overlayColor: Colors.transparent,
                      ),
                      child: const Text("No", style: TextStyle(fontFamily: kAppFont, fontSize: 12.0, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        setState(() {
                          _myLeaveHistory.removeAt(index);
                        });
                        _showAppleToast("Leave Cancelled", icon: CupertinoIcons.xmark_circle_fill);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        elevation: 0,
                        splashFactory: NoSplash.splashFactory,
                        surfaceTintColor: Colors.transparent,
                        overlayColor: Colors.transparent,
                      ),
                      child: const Text("Yes, Cancel", style: TextStyle(fontFamily: kAppFont, fontSize: 12.0, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFieldLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text(label, style: const TextStyle(fontFamily: kAppFont, fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF334155))),
    );
  }

  void _openFormat10ViewerDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Container(
            width: 720,
            height: MediaQuery.of(context).size.height * 0.88,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 30, offset: const Offset(0, 10))
              ],
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: const [
                            Icon(CupertinoIcons.doc_fill, size: 17, color: Color(0xFF0F172A)),
                            SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                "Format-10 Preview",
                                style: TextStyle(fontFamily: kAppFont, fontSize: 14.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: () {
                              Navigator.pop(context);
                              _showAppleToast("Downloaded Format-10 PDF");
                            },
                            icon: const Icon(CupertinoIcons.arrow_down_to_line, size: 18, color: Color(0xFF0F172A)),
                            tooltip: "Download PDF",
                          ),
                          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(CupertinoIcons.xmark, size: 18, color: Color(0xFF64748B))),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                Expanded(
                  child: Container(
                    color: const Color(0xFFF8FAFC),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: const Color(0xFFE2E8F0))),
                            child: const Icon(CupertinoIcons.doc_text, size: 36, color: Color(0xFF64748B)),
                          ),
                          const SizedBox(height: 14),
                          const Text("Format-10 Service Book Document Loaded", style: TextStyle(fontFamily: kAppFont, fontSize: 14.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                          const SizedBox(height: 4),
                          const Text("Verified against Rajasthan Shala Darpan Records.", style: TextStyle(fontFamily: kAppFont, fontSize: 11.5, color: Color(0xFF64748B))),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFormat10Module() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE2E8F0))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(12)),
                      child: const Icon(CupertinoIcons.doc_text_fill, color: Color(0xFF0F172A), size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Staff Service Record (Format-10)",
                            style: TextStyle(fontFamily: kAppFont, fontSize: 14.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "Verified by School Head • NIC: ${_currentUser['nicId']}",
                            style: const TextStyle(fontFamily: kAppFont, fontSize: 11.0, color: Color(0xFF64748B)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                      decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(6)),
                      child: const Text("Active / Locked", style: TextStyle(fontFamily: kAppFont, fontSize: 9.5, fontWeight: FontWeight.w700, color: Color(0xFF16A34A))),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _buildMetaCol("EMPLOYEE NAME", _currentUser["name"]!)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildMetaCol("DESIGNATION", _currentUser["designation"]!)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildMetaCol("POSTING", "Govt. School (480481)")),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE2E8F0))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Service Book Document", style: TextStyle(fontFamily: kAppFont, fontSize: 13.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                const SizedBox(height: 4),
                const Text("Inspect academic qualifications, salary structure, and service records inside app or download PDF.", style: TextStyle(fontFamily: kAppFont, fontSize: 11.5, color: Color(0xFF64748B), height: 1.4)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _openFormat10ViewerDialog(),
                        icon: const Icon(CupertinoIcons.eye_fill, size: 15, color: Colors.white),
                        label: const Text("View Format-10", style: TextStyle(fontFamily: kAppFont, fontSize: 12.0, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                        style: ButtonStyle(
                          backgroundColor: WidgetStateProperty.all(const Color(0xFF0F172A)),
                          foregroundColor: WidgetStateProperty.all(Colors.white),
                          overlayColor: WidgetStateProperty.all(Colors.transparent),
                          surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
                          shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                          padding: WidgetStateProperty.all(const EdgeInsets.symmetric(vertical: 11)),
                          elevation: WidgetStateProperty.all(0),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          _showAppleToast("Downloaded Format-10 PDF");
                        },
                        icon: const Icon(CupertinoIcons.arrow_down_doc_fill, size: 15, color: Color(0xFF0F172A)),
                        label: const Text("Download PDF", style: TextStyle(fontFamily: kAppFont, fontSize: 12.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)), maxLines: 1, overflow: TextOverflow.ellipsis),
                        style: ButtonStyle(
                          side: WidgetStateProperty.all(const BorderSide(color: Color(0xFFCBD5E1))),
                          overlayColor: WidgetStateProperty.all(Colors.transparent),
                          surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
                          shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                          padding: WidgetStateProperty.all(const EdgeInsets.symmetric(vertical: 11)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaCol(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontFamily: kAppFont, fontSize: 9.0, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8)),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontFamily: kAppFont, fontSize: 11.0, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildStaffLeaveApplyModule() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE2E8F0))),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: const Color(0xFFF1F5F9), shape: BoxShape.circle, border: Border.all(color: const Color(0xFFE2E8F0))),
                  child: const Icon(CupertinoIcons.paperplane_fill, color: Color(0xFF0F172A), size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text("Apply New Leave", style: TextStyle(fontFamily: kAppFont, fontSize: 14.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                      SizedBox(height: 2),
                      Text("Submit casual, medical or special leaves.", style: TextStyle(fontFamily: kAppFont, fontSize: 11.0, color: Color(0xFF64748B)), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _openRequestLeaveDialog(),
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.all(const Color(0xFF0F172A)),
                    foregroundColor: WidgetStateProperty.all(Colors.white),
                    overlayColor: WidgetStateProperty.all(Colors.transparent),
                    surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
                    shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                    padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 12, vertical: 9)),
                    elevation: WidgetStateProperty.all(0),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(CupertinoIcons.add, size: 13, color: Colors.white),
                      SizedBox(width: 4),
                      Text("Request Leave", style: TextStyle(fontFamily: kAppFont, fontSize: 11.5, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE2E8F0))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Image.asset(
                            'assets/icons/leave.png',
                            width: 16,
                            height: 16,
                            color: const Color(0xFF64748B),
                            errorBuilder: (c, e, s) => const Icon(CupertinoIcons.calendar_today, size: 16, color: Color(0xFF64748B)),
                          ),
                          const SizedBox(width: 8),
                          const Text("Recent Leave Requests", style: TextStyle(fontFamily: kAppFont, fontSize: 13.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                        ],
                      ),
                      Text("${_myLeaveHistory.length} Recorded", style: const TextStyle(fontFamily: kAppFont, fontSize: 11.0, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8))),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                _myLeaveHistory.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(child: Text("No leave requests found.", style: TextStyle(fontFamily: kAppFont, fontSize: 12.5, color: Color(0xFF94A3B8)))),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        itemCount: _myLeaveHistory.length,
                        separatorBuilder: (_, __) => const Divider(
                          height: 1,
                          thickness: 1,
                          color: Color(0xFFE2E8F0),
                        ),
                        itemBuilder: (context, index) {
                          final item = _myLeaveHistory[index];
                          final String status = item["status"];
                          final bool isPending = status == "Pending";
                          final double daysVal = (item["days"] as num?)?.toDouble() ?? 1.0;
                          final String daysLabel = daysVal % 1 == 0 ? "${daysVal.toInt()} ${daysVal == 1 ? 'day' : 'days'}" : "$daysVal days";
                          final String durationTypeLabel = item["duration"] == "2" ? "Half day" : "Full day";

                          Color statusBg = const Color(0xFFFEF3C7);
                          Color statusFg = const Color(0xFFD97706);

                          if (status == "Approved") {
                            statusBg = const Color(0xFFDCFCE7);
                            statusFg = const Color(0xFF16A34A);
                          } else if (status == "Rejected") {
                            statusBg = const Color(0xFFFEE2E2);
                            statusFg = const Color(0xFFDC2626);
                          }

                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(10)),
                                  child: Center(
                                    child: Text(
                                      item["short"],
                                      style: const TextStyle(fontFamily: kAppFont, fontSize: 11.5, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(item["icon"] as IconData, size: 12, color: const Color(0xFF64748B)),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              item["typeName"],
                                              style: const TextStyle(fontFamily: kAppFont, fontSize: 12.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      Row(
                                        children: [
                                          Image.asset(
                                            'assets/icons/leave.png',
                                            width: 11,
                                            height: 11,
                                            color: const Color(0xFF64748B),
                                            errorBuilder: (context, error, stackTrace) => const Icon(
                                              CupertinoIcons.calendar,
                                              size: 11,
                                              color: Color(0xFF64748B),
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              item["dateRange"],
                                              style: const TextStyle(fontFamily: kAppFont, fontSize: 10.5, fontWeight: FontWeight.w500, color: Color(0xFF64748B)),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 5),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        crossAxisAlignment: WrapCrossAlignment.center,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.0),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF1F5F9),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: const Color(0xFFE2E8F0)),
                                            ),
                                            child: Text(
                                              "$daysLabel ($durationTypeLabel)",
                                              style: const TextStyle(
                                                fontFamily: kAppFont,
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF0F172A),
                                              ),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.0),
                                            decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(4)),
                                            child: Text(
                                              status,
                                              style: TextStyle(fontFamily: kAppFont, fontSize: 9.5, fontWeight: FontWeight.w700, color: statusFg),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isPending) ...[
                                      InkWell(
                                        onTap: () => _confirmCancelLeave(index, item["short"]),
                                        borderRadius: BorderRadius.circular(8),
                                        splashColor: Colors.transparent,
                                        highlightColor: Colors.transparent,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: const Color(0xFFCBD5E1)),
                                          ),
                                          child: const Text("Cancel", style: TextStyle(fontFamily: kAppFont, fontSize: 11.0, fontWeight: FontWeight.w600, color: Color(0xFFDC2626))),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      InkWell(
                                        onTap: () {
                                          _openRequestLeaveDialog(existingRecord: item);
                                        },
                                        borderRadius: BorderRadius.circular(8),
                                        splashColor: Colors.transparent,
                                        highlightColor: Colors.transparent,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF0F172A),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: const Text("Edit", style: TextStyle(fontFamily: kAppFont, fontSize: 11.0, fontWeight: FontWeight.w600, color: Colors.white)),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                    ],
                                    InkWell(
                                      onTap: () {
                                        _showAppleToast("Downloaded ${item["short"]} Application");
                                      },
                                      borderRadius: BorderRadius.circular(8),
                                      splashColor: Colors.transparent,
                                      highlightColor: Colors.transparent,
                                      child: Container(
                                        width: 30,
                                        height: 29,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF8FAFC),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: const Color(0xFFE2E8F0)),
                                        ),
                                        child: Image.asset(
                                          'assets/icons/download.png',
                                          width: 14,
                                          height: 14,
                                          color: const Color(0xFF0F172A),
                                          errorBuilder: (context, error, stackTrace) => const Icon(
                                            CupertinoIcons.arrow_down_to_line,
                                            size: 14,
                                            color: Color(0xFF0F172A),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStaffModuleCard(String title, String subtitle, IconData icon) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 16),
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(color: const Color(0xFFF1F5F9), shape: BoxShape.circle, border: Border.all(color: const Color(0xFFE2E8F0))),
              child: Icon(icon, color: const Color(0xFF0F172A), size: 24),
            ),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontFamily: kAppFont, fontSize: 15.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
            const SizedBox(height: 6),
            Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(fontFamily: kAppFont, fontSize: 11.5, fontWeight: FontWeight.w500, color: Color(0xFF64748B), height: 1.4)),
            const SizedBox(height: 20),
            Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(8)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text("Launch via Staff Portal", style: TextStyle(fontFamily: kAppFont, fontSize: 12.0, fontWeight: FontWeight.w700, color: Colors.white)),
                  SizedBox(width: 6),
                  Icon(CupertinoIcons.arrow_right, size: 14, color: Colors.white),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData(
        useMaterial3: true,
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
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
        textButtonTheme: TextButtonThemeData(
          style: ButtonStyle(
            overlayColor: WidgetStateProperty.all(Colors.transparent),
            surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ButtonStyle(
            overlayColor: WidgetStateProperty.all(Colors.transparent),
            surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: ButtonStyle(
            overlayColor: WidgetStateProperty.all(Colors.transparent),
            surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE2E8F0))),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(8)),
                    child: Center(child: Text(_getInitials(_currentUser["name"]!), style: const TextStyle(fontFamily: kAppFont, fontSize: 11.0, fontWeight: FontWeight.w700, color: Colors.white))),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_currentUser["name"]!, style: const TextStyle(fontFamily: kAppFont, fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 1),
                        Text(_currentUser["designation"]!, style: const TextStyle(fontFamily: kAppFont, fontSize: 10.5, fontWeight: FontWeight.w500, color: Color(0xFF64748B)), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(6)),
                    child: Text("NIC: ${_currentUser["nicId"]}", style: const TextStyle(fontFamily: kAppFont, fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            controller: _tabScrollController,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: List.generate(_staffModules.length, (index) {
                final bool isSelected = _selectedStaffModuleIndex == index;
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedStaffModuleIndex = index;
                      });
                      if (_tabScrollController.hasClients) {
                        _tabScrollController.animateTo(
                          (index * 110.0).clamp(0.0, _tabScrollController.position.maxScrollExtent),
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      }
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8.0),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF0F172A) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0)),
                      ),
                      child: Text(
                        _staffModules[index],
                        style: TextStyle(
                          fontFamily: kAppFont,
                          fontSize: 12.0,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          color: isSelected ? Colors.white : const Color(0xFF475569),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: _selectedStaffModuleIndex == 2 ? 0.0 : 16.0,
              ),
              child: _buildDynamicBody(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDynamicBody() {
    switch (_selectedStaffModuleIndex) {
      case 0:
        return _buildStaffLeaveApplyModule();
      case 1:
        return _buildFormat10Module();
      case 2:
        return const JanaadharAuthView();
      default:
        return _buildStaffModuleCard("Staff Portal", "Select a feature to continue.", CupertinoIcons.square_grid_2x2);
    }
  }
}