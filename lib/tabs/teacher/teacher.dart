import 'package:shaladarpan/widgets/adaptive_layout.dart';
// lib/tabs/teacher/teacher.dart
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'shaladarpan.dart';
import 'modules/stafflogin/staff_login_view.dart';
const String kAppFont = 'PlusJakartaSans';
class TeacherTabScreen extends StatefulWidget {
  final String? schoolId;
  final VoidCallback? onAttendanceUpdated;
  final int initialEngineIndex;
  final int subModuleIndex;
  final int resetTrigger;
  const TeacherTabScreen({
    super.key,
    this.schoolId,
    this.onAttendanceUpdated,
    this.initialEngineIndex = 0,
    this.subModuleIndex = 0,
    this.resetTrigger = 0,
  });
  @override
  State<TeacherTabScreen> createState() => _TeacherTabScreenState();
}
class _TeacherTabScreenState extends State<TeacherTabScreen>
    with AutomaticKeepAliveClientMixin {
  late int _selectedMainEngine;
  String _activeSchoolId = "";
  late int _activeSubIndex;
  @override
  bool get wantKeepAlive => true;
  @override
  void initState() {
    super.initState();
    _selectedMainEngine = widget.initialEngineIndex;
    _activeSubIndex = widget.subModuleIndex;
    _activeSchoolId = widget.schoolId ?? "";
    if (_activeSchoolId.isEmpty) {
      _loadSavedSchoolId();
    }
  }
  @override
  void didUpdateWidget(covariant TeacherTabScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 1. Dynamic School ID update from Auth/Parent
    if (widget.schoolId != null &&
        widget.schoolId!.isNotEmpty &&
        widget.schoolId != oldWidget.schoolId) {
      setState(() {
        _activeSchoolId = widget.schoolId!;
      });
    }
    // 2. Engine Switcher handling
    if (widget.initialEngineIndex != oldWidget.initialEngineIndex) {
      setState(() {
        _selectedMainEngine = widget.initialEngineIndex;
      });
    }
    // 3. Sub-module synchronization (Dashboard tile jump or direct tab click)
    if (widget.subModuleIndex != oldWidget.subModuleIndex ||
        widget.resetTrigger != oldWidget.resetTrigger) {
      setState(() {
        _selectedMainEngine = widget.initialEngineIndex;
        _activeSubIndex = widget.subModuleIndex;
      });
    }
  }
  // 4. Multi-key fallback for school ID to prevent dropping to dummy ID
  Future<void> _loadSavedSchoolId() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('saved_school_id') ??
        prefs.getString('saved_shala_id') ??
        prefs.getString('school_id') ??
        "480481";
    if (mounted) {
      setState(() => _activeSchoolId = saved);
    }
  }
  String _getTodayDate() {
    final now = DateTime.now();
    final months = [
      "Jan", "Feb", "Mar", "Apr", "May", "Jun",
      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    ];
    final dayStr = now.day.toString().padLeft(2, '0');
    return "$dayStr ${months[now.month - 1]}, ${now.year}";
  }
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return LayoutBuilder(builder: (context, viewport) => Align(alignment: Alignment.topCenter, child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: AppAdaptive.contentWidth(viewport.maxWidth)),
      child: Container(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          // 1. Header Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Teacher Desk",
                        style: TextStyle(
                          fontFamily: kAppFont,
                          fontSize: 16.0,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        "School NIC CODE : ${_activeSchoolId.isNotEmpty ? _activeSchoolId : '...'}",
                        style: const TextStyle(
                          fontFamily: kAppFont,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0F172A).withOpacity(0.02),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Image.asset(
                        'assets/icons/leave.png',
                        width: 14,
                        height: 14,
                        color: const Color(0xFF64748B),
                        errorBuilder: (c, e, s) => const Icon(
                          CupertinoIcons.calendar_today,
                          size: 14,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _getTodayDate(),
                        style: const TextStyle(
                          fontFamily: kAppFont,
                          fontSize: 12.0,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // 2. Engine Switcher (Shaladarpan vs Staff Login)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Container(
              height: 40,
              padding: const EdgeInsets.all(3.0),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (_selectedMainEngine != 0) {
                          HapticFeedback.selectionClick();
                          setState(() => _selectedMainEngine = 0);
                        }
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        decoration: BoxDecoration(
                          color: _selectedMainEngine == 0 ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: _selectedMainEngine == 0
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFF0F172A).withOpacity(0.06),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1.5),
                                  )
                                ]
                              : [],
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (_selectedMainEngine == 0)
                              Positioned(
                                left: 0, top: 6, bottom: 6,
                                child: Container(
                                  width: 3,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF22C55E),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                            Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Image.asset(
                                'assets/icons/shaladarpan.png',
                                width: 16,
                                height: 16,
                                errorBuilder: (c, e, s) => Icon(
                                  CupertinoIcons.building_2_fill,
                                  size: 15,
                                  color: _selectedMainEngine == 0
                                      ? const Color(0xFF0F172A)
                                      : const Color(0xFF64748B),
                                ),
                              ),
                              const SizedBox(width: 7),
                              Text(
                                "Shaladarpan",
                                style: TextStyle(
                                  fontFamily: kAppFont,
                                  fontSize: 12.5,
                                  fontWeight: _selectedMainEngine == 0
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                  color: _selectedMainEngine == 0
                                      ? const Color(0xFF0F172A)
                                      : const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (_selectedMainEngine != 1) {
                          HapticFeedback.selectionClick();
                          setState(() => _selectedMainEngine = 1);
                        }
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        decoration: BoxDecoration(
                          color: _selectedMainEngine == 1 ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: _selectedMainEngine == 1
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFF0F172A).withOpacity(0.06),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1.5),
                                  )
                                ]
                              : [],
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (_selectedMainEngine == 1)
                              Positioned(
                                left: 0, top: 6, bottom: 6,
                                child: Container(
                                  width: 3,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF22C55E),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                            Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Image.asset(
                                'assets/icons/staff.png',
                                width: 16,
                                height: 16,
                                errorBuilder: (c, e, s) => Icon(
                                  CupertinoIcons.person_crop_circle_fill,
                                  size: 15,
                                  color: _selectedMainEngine == 1
                                      ? const Color(0xFF0F172A)
                                      : const Color(0xFF64748B),
                                ),
                              ),
                              const SizedBox(width: 7),
                              Text(
                                "Staff Login",
                                style: TextStyle(
                                  fontFamily: kAppFont,
                                  fontSize: 12.5,
                                  fontWeight: _selectedMainEngine == 1
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                  color: _selectedMainEngine == 1
                                      ? const Color(0xFF0F172A)
                                      : const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 3. State-Preserving View (IndexedStack prevents wiping form state when switching engines)
          Expanded(
            child: IndexedStack(
              index: _selectedMainEngine,
              children: [
                ShaladarpanView(
                  key: ValueKey('shala_view_sub_${_activeSubIndex}_${widget.resetTrigger}'),
                  schoolId: _activeSchoolId.isNotEmpty ? _activeSchoolId : "480481",
                  initialSubIndex: _activeSubIndex,
                  onAttendanceUpdated: widget.onAttendanceUpdated,
                ),
                const StaffLoginView(),
              ],
            ),
          ),
        ],
      ),
    ))));
  }
}