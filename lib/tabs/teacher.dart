import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'teacher/shaladarpan.dart';
import 'teacher/stafflogin.dart';

const String kAppFont = 'PlusJakartaSans';

class TeacherTabScreen extends StatefulWidget {
  const TeacherTabScreen({super.key});

  @override
  State<TeacherTabScreen> createState() => _TeacherTabScreenState();
}

class _TeacherTabScreenState extends State<TeacherTabScreen> {
  int _selectedMainEngine = 0; // 0: Shaladarpan, 1: Staff Login

  String _getTodayDate() {
    final now = DateTime.now();
    final months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    return "${now.day} ${months[now.month - 1]}, ${now.year}";
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),

          // 1. Common Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        "Teacher Desk",
                        style: TextStyle(fontFamily: kAppFont, fontSize: 16.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A), letterSpacing: -0.2),
                      ),
                      SizedBox(height: 1),
                      Text(
                        "School NIC CODE : 480481",
                        style: TextStyle(fontFamily: kAppFont, fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE2E8F0))),
                  child: Row(
                    children: [
                      Image.asset(
                        'assets/icons/leave.png',
                        width: 14, height: 14, color: const Color(0xFF64748B),
                        errorBuilder: (c, e, s) => const Icon(CupertinoIcons.calendar_today, size: 14, color: Color(0xFF64748B)),
                      ),
                      const SizedBox(width: 6),
                      Text(_getTodayDate(), style: const TextStyle(fontFamily: kAppFont, fontSize: 12.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
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
              decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE2E8F0))),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedMainEngine = 0),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        decoration: BoxDecoration(
                          color: _selectedMainEngine == 0 ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: _selectedMainEngine == 0 ? [BoxShadow(color: const Color(0xFF0F172A).withOpacity(0.06), blurRadius: 4, offset: const Offset(0, 1.5))] : [],
                        ),
                        child: Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Image.asset(
                                'assets/icons/shaladarpan.png',
                                width: 16, height: 16,
                                errorBuilder: (c, e, s) => Icon(CupertinoIcons.building_2_fill, size: 15, color: _selectedMainEngine == 0 ? const Color(0xFF0F172A) : const Color(0xFF64748B)),
                              ),
                              const SizedBox(width: 7),
                              Text("Shaladarpan", style: TextStyle(fontFamily: kAppFont, fontSize: 12.5, fontWeight: _selectedMainEngine == 0 ? FontWeight.w700 : FontWeight.w600, color: _selectedMainEngine == 0 ? const Color(0xFF0F172A) : const Color(0xFF64748B))),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedMainEngine = 1),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        decoration: BoxDecoration(
                          color: _selectedMainEngine == 1 ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: _selectedMainEngine == 1 ? [BoxShadow(color: const Color(0xFF0F172A).withOpacity(0.06), blurRadius: 4, offset: const Offset(0, 1.5))] : [],
                        ),
                        child: Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Image.asset(
                                'assets/icons/staff.png',
                                width: 16, height: 16,
                                errorBuilder: (c, e, s) => Icon(CupertinoIcons.person_crop_circle_fill, size: 15, color: _selectedMainEngine == 1 ? const Color(0xFF0F172A) : const Color(0xFF64748B)),
                              ),
                              const SizedBox(width: 7),
                              Text("Staff Login", style: TextStyle(fontFamily: kAppFont, fontSize: 12.5, fontWeight: _selectedMainEngine == 1 ? FontWeight.w700 : FontWeight.w600, color: _selectedMainEngine == 1 ? const Color(0xFF0F172A) : const Color(0xFF64748B))),
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

          const SizedBox(height: 12),

          // 3. Moduler View Load
          Expanded(
            child: _selectedMainEngine == 0 ? const ShaladarpanView() : const StaffLoginView(),
          ),
        ],
      ),
    );
  }
}