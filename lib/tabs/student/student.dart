import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

const String kAppFont = 'PlusJakartaSans';

class StudentDashboardView extends StatefulWidget {
  const StudentDashboardView({super.key});

  @override
  State<StudentDashboardView> createState() => _StudentDashboardViewState();
}

class _StudentDashboardViewState extends State<StudentDashboardView> {
  // Clean, Monochrome Student Modules List (9 Functions)
  final List<Map<String, dynamic>> _studentModules = [
    {
      "id": "1",
      "title": "Student Daily Attendance",
      "subtitle": "Mark & track daily present/absent status",
      "icon": CupertinoIcons.calendar_badge_plus,
      "badge": "Daily"
    },
    {
      "id": "2",
      "title": "New Admission Entry",
      "subtitle": "Register new student enrollment data",
      "icon": CupertinoIcons.person_badge_plus_fill,
      "badge": "Portal"
    },
    {
      "id": "3",
      "title": "Study Certificate",
      "subtitle": "Generate bonafide study certificates",
      "icon": CupertinoIcons.doc_checkmark_fill,
      "badge": "Doc"
    },
    {
      "id": "4",
      "title": "Transfer Certificate (TC)",
      "subtitle": "Issue official school leaving certificates",
      "icon": CupertinoIcons.doc_text_fill,
      "badge": "Official"
    },
    {
      "id": "5",
      "title": "Format-5",
      "subtitle": "View and verify student basic profile details",
      "icon": CupertinoIcons.profile_circled,
      "badge": "Form 5"
    },
    {
      "id": "6",
      "title": "Format-9",
      "subtitle": "Manage student academic history & records",
      "icon": CupertinoIcons.folder_solid,
      "badge": "Form 9"
    },
    {
      "id": "7",
      "title": "Character Certificate",
      "subtitle": "Generate student conduct & behavior report",
      "icon": CupertinoIcons.shield_lefthalf_fill,
      "badge": "Certificate"
    },
    {
      "id": "8",
      "title": "Monthly Attendance Entry",
      "subtitle": "Compile and submit monthly attendance sheets",
      "icon": CupertinoIcons.table_badge_more_fill,
      "badge": "Monthly"
    },
    {
      "id": "9",
      "title": "Student NIC Code",
      "subtitle": "View national identification portal codes",
      "icon": CupertinoIcons.barcode,
      "badge": "ID Code"
    },
  ];

  void _showAppleToast(String message, {IconData icon = CupertinoIcons.checkmark_circle_fill, Color color = const Color(0xFF0F172A)}) {
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
                          Icon(icon, color: Colors.white, size: 18),
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

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData(
        useMaterial3: true,
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF0F172A),
          onPrimary: Colors.white,
          surfaceTint: Colors.transparent,
        ),
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Header Card matching Teacher Tab style precisely
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withOpacity(0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Center(
                      child: Image.asset(
                        'assets/icons/student.png',
                        width: 24,
                        height: 24,
                        fit: BoxFit.contain,
                        errorBuilder: (c, e, s) => const Icon(
                          CupertinoIcons.person_3_fill,
                          color: Color(0xFF0F172A),
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          "Student Desk",
                          style: TextStyle(fontFamily: kAppFont, fontSize: 15.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                        ),
                        SizedBox(height: 2),
                        Text(
                          "Govt. Upper Primary School • School NIC: 480481",
                          style: TextStyle(fontFamily: kAppFont, fontSize: 11.5, color: Color(0xFF64748B)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 2. Section Heading
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Student Services & Modules",
                  style: TextStyle(fontFamily: kAppFont, fontSize: 14.5, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                ),
                Text(
                  "${_studentModules.length} Available",
                  style: const TextStyle(fontFamily: kAppFont, fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 3. Clean Monochrome Grid View for 9 Student Modules
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.25,
              ),
              itemCount: _studentModules.length,
              itemBuilder: (context, index) {
                final module = _studentModules[index];
                return GestureDetector(
                  onTap: () {
                    _showAppleToast("Opening ${module['title']}...", icon: CupertinoIcons.doc_text_fill, color: const Color(0xFF0F172A));
                  },
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0F172A).withOpacity(0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Center(
                                child: Icon(
                                  module["icon"] as IconData,
                                  size: 18,
                                  color: const Color(0xFF0F172A),
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                module["badge"],
                                style: const TextStyle(
                                  fontFamily: kAppFont,
                                  fontSize: 9.0,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF475569),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              module["title"],
                              style: const TextStyle(
                                fontFamily: kAppFont,
                                fontSize: 13.0,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F172A),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              module["subtitle"],
                              style: const TextStyle(
                                fontFamily: kAppFont,
                                fontSize: 10.5,
                                color: Color(0xFF64748B),
                                height: 1.3,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}