import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

const String kAppFont = 'PlusJakartaSans';

class ShaladarpanView extends StatefulWidget {
  const ShaladarpanView({super.key});

  @override
  State<ShaladarpanView> createState() => _ShaladarpanViewState();
}

class _ShaladarpanViewState extends State<ShaladarpanView> {
  int _selectedModuleIndex = 0;
  String _searchQuery = "";

  final List<String> _shalaModules = [
    "Attendance",
    "Leave Approvals",
    "Class Mapping",
    "Incharge Roles"
  ];

  final List<Map<String, String>> _attendanceOptions = [
    {"code": "0", "label": "Present"},
    {"code": "90", "label": "स्वैच्छिक अनुपस्थित"},
    {"code": "91", "label": "Work Arrangement (Other School)"},
    {"code": "92", "label": "Work Arrangement (Other Office)"},
    {"code": "93", "label": "On Training"},
    {"code": "94", "label": "On Official Travel"},
    {"code": "89", "label": "On Leave"},
    {"code": "88", "label": "सवैतनिक अवकाश"},
    {"code": "95", "label": "Election Duty"},
    {"code": "99", "label": "Other Reason"},
    {"code": "100", "label": "2nd Saturday / Holiday"},
    {"code": "101", "label": "Summer Vacations"},
    {"code": "102", "label": "मध्यावधि अवकाश"},
    {"code": "103", "label": "शीतकालीन अवकाश"},
    {"code": "104", "label": "राज्य सरकार द्वारा घोषित अवकाश"},
    {"code": "105", "label": "स्थानीय अवकाश (Collector)"},
    {"code": "106", "label": "संस्था प्रधान अधिकृत अवकाश"},
    {"code": "107", "label": "शैक्षिक सम्मेलन"},
  ];

  final List<Map<String, dynamic>> _staffList = [
    {
      "staffId": "1487701",
      "employeeId": "RJPG201730010127",
      "name": "Rekha Kumari Meena",
      "designation": "Teacher Level-1",
      "attendanceCode": "89",
      "appliedLeave": "Leave (ML Applied)",
    },
    {
      "staffId": "1553675",
      "employeeId": "RJPG201830008276",
      "name": "Ripudaman Singh Jhala",
      "designation": "Teacher Level-1",
      "attendanceCode": "0",
      "appliedLeave": null,
    },
    {
      "staffId": "1429810",
      "employeeId": "RJPG201524009122",
      "name": "Rajesh Sharma",
      "designation": "Sr. Teacher (Science)",
      "attendanceCode": "0",
      "appliedLeave": null,
    },
    {
      "staffId": "1672341",
      "employeeId": "RJPG201911003450",
      "name": "Sunita Verma",
      "designation": "Teacher Level-2 (Math)",
      "attendanceCode": "93",
      "appliedLeave": null,
    },
    {
      "staffId": "1389012",
      "employeeId": "RJPG201402008819",
      "name": "Anil Kumar",
      "designation": "PTI (Physical Education)",
      "attendanceCode": "90",
      "appliedLeave": null,
    },
  ];

  final List<Map<String, dynamic>> _classMappings = [
    {"class": "Class 6 - Section A", "teacher": "Rekha Kumari Meena"},
    {"class": "Class 7 - Section B", "teacher": "Ripudaman Singh Jhala"},
    {"class": "Class 8 - Section A", "teacher": "Rajesh Sharma"},
  ];

  final List<Map<String, dynamic>> _leaveRequests = [
    {
      "id": "LR-01",
      "staffId": "1487701",
      "name": "Rekha Kumari Meena",
      "type": "Medical Leave",
      "duration": "4 days",
      "date": "2/15/2026 - 2/18/2026",
      "reason": "Hospital recovery and prescription",
      "status": "Pending",
      "icon": CupertinoIcons.bandage,
    },
    {
      "id": "LR-02",
      "staffId": "1672341",
      "name": "Sunita Verma",
      "type": "Casual Leave",
      "duration": "1 day",
      "date": "3/01/2026 - 3/01/2026",
      "reason": "Family obligation in native town",
      "status": "Pending",
      "icon": CupertinoIcons.calendar_today,
    }
  ];

  final List<Map<String, dynamic>> _inchargeDuties = [
    {"duty": "Mid-Day Meal (MDM)", "incharge": "Rekha Kumari Meena"},
    {"duty": "Sports & Youth Affairs", "incharge": "Anil Kumar"},
  ];

  int get _presentCount => _staffList.where((s) => s["attendanceCode"] == "0").length;
  int get _onLeaveCount => _staffList.where((s) => s["attendanceCode"] == "89" || s["attendanceCode"] == "88" || s["appliedLeave"] != null).length;
  int get _otherCount => _staffList.where((s) => !["0", "90", "89", "88"].contains(s["attendanceCode"]) && s["appliedLeave"] == null).length;
  int get _absentCount => _staffList.where((s) => s["attendanceCode"] == "90").length;

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
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.18),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          )
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, color: const Color(0xFF34C759), size: 18),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              message,
                              style: const TextStyle(fontFamily: kAppFont, fontSize: 12.0, fontWeight: FontWeight.w600, color: Colors.white),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
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

  void _showStatusPicker(Map<String, dynamic> teacher) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.65),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFFCBD5E1), borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        "Update Status: ${teacher['name']}",
                        style: const TextStyle(fontFamily: kAppFont, fontSize: 16.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
              Expanded(
                child: ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: _attendanceOptions.length,
                  itemBuilder: (context, idx) {
                    final opt = _attendanceOptions[idx];
                    final bool isSelected = teacher["attendanceCode"] == opt["code"];

                    Color themeColor;
                    if (opt["code"] == "0") {
                      themeColor = const Color(0xFF34C759);
                    } else if (opt["code"] == "88" || opt["code"] == "89") {
                      themeColor = const Color(0xFFFFF59D);
                    } else {
                      themeColor = const Color(0xFF0F172A);
                    }

                    return GestureDetector(
                      onTap: () {
                        setState(() => teacher["attendanceCode"] = opt["code"]);
                        Navigator.pop(context);
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected && opt["code"] != "88" && opt["code"] != "89"
                              ? themeColor.withOpacity(0.08)
                              : isSelected ? const Color(0xFFFFF59D) : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                opt["label"]!,
                                style: TextStyle(
                                  fontFamily: kAppFont,
                                  fontSize: 13.0,
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                  color: isSelected && (opt["code"] == "88" || opt["code"] == "89")
                                      ? const Color(0xFF0F172A)
                                      : isSelected ? themeColor : const Color(0xFF334155),
                                ),
                              ),
                            ),
                            if (isSelected)
                              Icon(Icons.check_circle_rounded,
                                color: (opt["code"] == "88" || opt["code"] == "89") ? const Color(0xFF0F172A) : themeColor,
                                size: 18,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showStaffPicker(Map<String, dynamic> item, String key2) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.60),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFFCBD5E1), borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        "Assign to: ${item['class'] ?? item['duty']}",
                        style: const TextStyle(fontFamily: kAppFont, fontSize: 15.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
              Expanded(
                child: ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: _staffList.length,
                  itemBuilder: (context, idx) {
                    final staff = _staffList[idx];
                    final bool isSelected = item[key2] == staff["name"];

                    return GestureDetector(
                      onTap: () {
                        setState(() => item[key2] = staff["name"]);
                        Navigator.pop(context);
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF0F172A).withOpacity(0.08) : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                staff["name"]!,
                                style: TextStyle(
                                  fontFamily: kAppFont,
                                  fontSize: 13.0,
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                  color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF334155),
                                ),
                              ),
                            ),
                            if (isSelected) const Icon(Icons.check_circle_rounded, color: Color(0xFF0F172A), size: 18),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search Bar for Shaladarpan
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: TextField(
              onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
              style: const TextStyle(fontFamily: kAppFont, fontSize: 13.0, color: Color(0xFF0F172A)),
              decoration: const InputDecoration(
                hintText: "Search employee by name, NIC or ID...",
                hintStyle: TextStyle(fontFamily: kAppFont, fontSize: 12.0, color: Color(0xFF94A3B8)),
                prefixIcon: Icon(CupertinoIcons.search, size: 18, color: Color(0xFF64748B)),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 11.0),
              ),
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Sub-module Horizontal Tabs
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            children: List.generate(_shalaModules.length, (index) {
              final bool isSelected = _selectedModuleIndex == index;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedModuleIndex = index;
                    });
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
                      _shalaModules[index],
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

        // Main Content Wrapper
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: _buildDynamicBody(),
          ),
        ),
      ],
    );
  }

  Widget _buildDynamicBody() {
    switch (_selectedModuleIndex) {
      case 0: return _buildAttendanceEngine();
      case 1: return _buildFigmaLeaveApprovals();
      case 2: return _buildEnterpriseList(_classMappings, "Class", "class", "teacher");
      case 3: return _buildEnterpriseList(_inchargeDuties, "Committee", "duty", "incharge");
      default: return _buildAttendanceEngine();
    }
  }

  // =========================================================================
  // ATTENDANCE ENGINE (KPI Tiles shown directly above employee list)
  // =========================================================================
  Widget _buildAttendanceEngine() {
    final filteredStaff = _staffList.where((teacher) {
      final name = teacher["name"].toString().toLowerCase();
      final staffId = teacher["staffId"].toString().toLowerCase();
      final employeeId = teacher["employeeId"].toString().toLowerCase();
      return name.contains(_searchQuery) || staffId.contains(_searchQuery) || employeeId.contains(_searchQuery);
    }).toList();

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 12.0),
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [BoxShadow(color: const Color(0xFF0F172A).withOpacity(0.015), blurRadius: 4, offset: const Offset(0, 2))],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildVerticalKpiCustom("Present", "$_presentCount", 'assets/icons/present.png', CupertinoIcons.checkmark_circle),
              _buildDivider(),
              _buildVerticalKpiCustom("Leave", "$_onLeaveCount", 'assets/icons/leave.png', CupertinoIcons.person_crop_circle_badge_minus),
              _buildDivider(),
              _buildVerticalKpiIcon("Other", "$_otherCount", CupertinoIcons.briefcase),
              _buildDivider(),
              _buildVerticalKpiIcon("Absent", "$_absentCount", CupertinoIcons.xmark_circle),
            ],
          ),
        ),

        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
                      border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                    ),
                    child: Row(
                      children: const [
                        Expanded(child: Text("EMPLOYEE DETAILS", style: TextStyle(fontFamily: kAppFont, fontSize: 11.0, fontWeight: FontWeight.w700, color: Color(0xFF64748B), letterSpacing: 0.3))),
                        SizedBox(width: 135, child: Text("ATTENDANCE", style: TextStyle(fontFamily: kAppFont, fontSize: 11.0, fontWeight: FontWeight.w700, color: Color(0xFF64748B), letterSpacing: 0.3))),
                      ],
                    ),
                  ),

                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: filteredStaff.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                    itemBuilder: (context, index) {
                      final teacher = filteredStaff[index];
                      final String currentCode = teacher["attendanceCode"];
                      final bool hasAppliedLeave = teacher["appliedLeave"] != null;

                      Color dropdownBgColor;
                      Color dropdownTextColor = Colors.white;

                      if (currentCode == "0") {
                        dropdownBgColor = const Color(0xFF34C759);
                      } else if (currentCode == "88" || currentCode == "89") {
                        dropdownBgColor = const Color(0xFFFFF59D);
                        dropdownTextColor = const Color(0xFF0F172A);
                      } else {
                        dropdownBgColor = const Color(0xFF0F172A);
                      }

                      final String fullStatusLabel = _attendanceOptions.firstWhere((o) => o["code"] == currentCode)["label"]!;

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Container(
                                    width: 32, height: 32,
                                    decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8)),
                                    child: Center(
                                      child: Text(
                                        _getInitials(teacher["name"]),
                                        style: const TextStyle(fontFamily: kAppFont, fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          teacher["name"],
                                          maxLines: 1, overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontFamily: kAppFont, fontSize: 13.0, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                                        ),
                                        const SizedBox(height: 1.5),
                                        Text(
                                          "ID: ${teacher["staffId"]} • ${teacher["designation"]}",
                                          maxLines: 1, overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontFamily: kAppFont, fontSize: 10.0, fontWeight: FontWeight.w500, color: Color(0xFF64748B)),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),

                            SizedBox(
                              width: 135,
                              child: hasAppliedLeave
                                  ? Container(
                                      height: 32,
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: const Color(0xFFE2E8F0)),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              teacher["appliedLeave"],
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontFamily: kAppFont, fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          const Icon(CupertinoIcons.lock, size: 12, color: Color(0xFF94A3B8)),
                                        ],
                                      ),
                                    )
                                  : GestureDetector(
                                      onTap: () => _showStatusPicker(teacher),
                                      behavior: HitTestBehavior.opaque,
                                      child: Container(
                                        height: 32,
                                        padding: const EdgeInsets.symmetric(horizontal: 10),
                                        decoration: BoxDecoration(
                                          color: dropdownBgColor,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                fullStatusLabel,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(fontFamily: kAppFont, fontSize: 11.0, fontWeight: FontWeight.w700, color: dropdownTextColor),
                                              ),
                                            ),
                                            const SizedBox(width: 2),
                                            Icon(CupertinoIcons.chevron_down, size: 12, color: dropdownTextColor),
                                          ],
                                        ),
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),

        // Bottom Action Bar
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44.0,
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() {
                          for (var s in _staffList) {
                            if (s["appliedLeave"] == null) s["attendanceCode"] = "0";
                          }
                        });
                      },
                      style: ButtonStyle(
                        overlayColor: WidgetStateProperty.all(Colors.transparent),
                        side: WidgetStateProperty.all(const BorderSide(color: Color(0xFFCBD5E1), width: 1.0)),
                        backgroundColor: WidgetStateProperty.all(Colors.white),
                        elevation: WidgetStateProperty.all(0),
                        shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(CupertinoIcons.check_mark_circled, size: 16, color: Color(0xFF0F172A)),
                            SizedBox(width: 6),
                            Text(
                              "Mark All Present",
                              style: TextStyle(fontFamily: kAppFont, fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                Expanded(
                  child: Container(
                    height: 44.0,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2E3545), Color(0xFF0F172A)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(color: const Color(0xFF0F172A).withOpacity(0.15), blurRadius: 6, offset: const Offset(0, 3))
                      ]
                    ),
                    child: ElevatedButton(
                      onPressed: () => _showAppleToast("Staff attendance submitted successfully"),
                      style: ButtonStyle(
                        overlayColor: WidgetStateProperty.all(Colors.transparent),
                        backgroundColor: WidgetStateProperty.all(Colors.transparent),
                        shadowColor: WidgetStateProperty.all(Colors.transparent),
                        foregroundColor: WidgetStateProperty.all(Colors.white),
                        elevation: WidgetStateProperty.all(0),
                        shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Image.asset(
                              'assets/icons/submit.png',
                              width: 16, height: 16, color: Colors.white,
                              errorBuilder: (context, error, stackTrace) => const Icon(CupertinoIcons.cloud_upload, size: 16, color: Colors.white),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              "Submit Attendance",
                              style: TextStyle(fontFamily: kAppFont, fontSize: 12.5, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // FIGMA LEAVE APPROVALS (Shaladarpan Admin Side)
  // =========================================================================
  Widget _buildFigmaLeaveApprovals() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
              ),
              child: Row(
                children: const [
                  Icon(CupertinoIcons.calendar_today, size: 16, color: Color(0xFF64748B)),
                  SizedBox(width: 6),
                  Text("Leave Requests", style: TextStyle(fontFamily: kAppFont, fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
                ],
              ),
            ),

            _leaveRequests.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(CupertinoIcons.check_mark_circled, color: Color(0xFF34C759), size: 36),
                      SizedBox(height: 8),
                      Text("All Caught Up", style: TextStyle(fontFamily: kAppFont, fontSize: 14.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                    ],
                  ),
                ),
              )
            : ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                itemCount: _leaveRequests.length,
                separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                itemBuilder: (context, index) {
                  final leave = _leaveRequests[index];
                  final bool isPending = leave["status"] == "Pending";

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 38, height: 38,
                          decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(10)),
                          child: Center(
                            child: Text(
                              _getInitials(leave["name"]),
                              style: const TextStyle(fontFamily: kAppFont, fontSize: 13.0, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(leave["name"], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: kAppFont, fontSize: 13.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(leave["icon"], size: 12, color: const Color(0xFF64748B)),
                                  const SizedBox(width: 4),
                                  Expanded(child: Text("${leave["type"]} • ${leave["duration"]}", maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: kAppFont, fontSize: 11.0, color: Color(0xFF64748B)))),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(leave["date"], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: kAppFont, fontSize: 11.0, color: Color(0xFF94A3B8))),

                              const SizedBox(height: 14),

                              isPending
                              ? Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(4)),
                                      child: Text(leave["status"], style: const TextStyle(fontFamily: kAppFont, fontSize: 9.5, fontWeight: FontWeight.w700, color: Color(0xFFD97706))),
                                    ),
                                    const Spacer(),
                                    GestureDetector(
                                      onTap: (){
                                        setState(() => leave["status"] = "Rejected");
                                      },
                                      behavior: HitTestBehavior.opaque,
                                      child: const Text("Reject", style: TextStyle(fontFamily: kAppFont, fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
                                    ),
                                    const SizedBox(width: 14),
                                    GestureDetector(
                                      onTap: (){
                                        setState(() {
                                          leave["status"] = "Approved";
                                          final staff = _staffList.firstWhere((s) => s["staffId"] == leave["staffId"], orElse: () => {});
                                          if (staff.isNotEmpty) {
                                            staff["attendanceCode"] = "89";
                                            staff["appliedLeave"] = "Leave (${leave["type"]})";
                                          }
                                        });
                                      },
                                      behavior: HitTestBehavior.opaque,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                        decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(6)),
                                        child: const Text("Approve", style: TextStyle(fontFamily: kAppFont, fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.white)),
                                      ),
                                    ),
                                  ],
                                )
                              : Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: leave["status"] == "Approved" ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        leave["status"],
                                        style: TextStyle(fontFamily: kAppFont, fontSize: 10.5, fontWeight: FontWeight.w700,
                                          color: leave["status"] == "Approved" ? const Color(0xFF16A34A) : const Color(0xFFDC2626)
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
                },
              ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // CLASS MAPPING & INCHARGE
  // =========================================================================
  Widget _buildEnterpriseList(List<Map<String, dynamic>> data, String col1Name, String key1, String key2) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
                border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Row(
                children: [
                  Expanded(flex: 3, child: Text(col1Name.toUpperCase(), style: const TextStyle(fontFamily: kAppFont, fontSize: 11.0, fontWeight: FontWeight.w700, color: Color(0xFF64748B)))),
                  Expanded(flex: 2, child: Text("ASSIGNED TO", style: const TextStyle(fontFamily: kAppFont, fontSize: 11.0, fontWeight: FontWeight.w700, color: Color(0xFF64748B)))),
                ],
              ),
            ),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: data.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
              itemBuilder: (context, index) {
                final item = data[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(flex: 3, child: Text(item[key1], style: const TextStyle(fontFamily: kAppFont, fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)))),

                      Expanded(
                        flex: 2,
                        child: GestureDetector(
                          onTap: () => _showStaffPicker(item, key2),
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            height: 32,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    item[key2],
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontFamily: kAppFont, fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                                  ),
                                ),
                                const Icon(CupertinoIcons.chevron_down, size: 12, color: Color(0xFF64748B)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerticalKpiCustom(String label, String value, String assetPath, IconData fallbackIcon) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Image.asset(
              assetPath,
              width: 15, height: 15,
              color: const Color(0xFF64748B),
              errorBuilder: (context, error, stack) => Icon(fallbackIcon, size: 15, color: const Color(0xFF64748B)),
            ),
            const SizedBox(width: 6),
            Text(
              value,
              style: const TextStyle(fontFamily: kAppFont, fontSize: 18.0, fontWeight: FontWeight.w800, color: Color(0xFF0F172A), letterSpacing: -0.5),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontFamily: kAppFont, fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
        ),
      ],
    );
  }

  Widget _buildVerticalKpiIcon(String label, String value, IconData icon) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: const Color(0xFF64748B)),
            const SizedBox(width: 6),
            Text(
              value,
              style: const TextStyle(fontFamily: kAppFont, fontSize: 18.0, fontWeight: FontWeight.w800, color: Color(0xFF0F172A), letterSpacing: -0.5),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontFamily: kAppFont, fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
        ),
      ],
    );
  }

  Widget _buildDivider() {
    return Container(width: 1.0, height: 24.0, color: const Color(0xFFE2E8F0));
  }
}