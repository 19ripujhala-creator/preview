import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const String kAppFont = 'PlusJakartaSans';

// Custom ScrollBehavior to completely eliminate overscroll glow / tint
class _NoGlowScrollBehavior extends ScrollBehavior {
  const _NoGlowScrollBehavior();

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) {
    return child;
  }
}

// ==========================================
// 1. DATA MODEL
// ==========================================
class StudentRecord {
  final String srNo;
  final String nicCode;
  final String name;
  final String rollNo;
  final String className;
  final String gender;
  String attendanceStatus; // 'P', 'A', 'L'

  StudentRecord({
    required this.srNo,
    required this.nicCode,
    required this.name,
    required this.rollNo,
    required this.className,
    required this.gender,
    this.attendanceStatus = 'P',
  });
}

// ==========================================
// 2. LUXURY CREDIT CARD S-WAVE DOT MESH PAINTER
// ==========================================
class LuxuryCardWaveMeshPainter extends CustomPainter {
  final Color dotColor;
  LuxuryCardWaveMeshPainter({required this.dotColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final double scale = math.min(size.width * 0.46, size.height);
    final double originX = size.width - (scale * 0.96);
    final double originY = size.height * 0.48;

    const int lines = 24;
    const int pointsPerLine = 36;

    for (int l = 0; l < lines; l++) {
      final double depth = l / (lines - 1);
      final double z = 0.38 + (depth * 0.62);

      for (int p = 0; p < pointsPerLine; p++) {
        final double u = p / (pointsPerLine - 1);
        final double wave1 = math.sin((u * math.pi * 1.85) - 0.42);
        final double wave2 = math.cos(u * math.pi * 3.1) * 0.16;

        final double x = originX + (u * scale * 1.1) + (depth * scale * 0.16);
        final double y = originY + ((wave1 + wave2) * scale * 0.40 * z) + ((depth - 0.5) * scale * 0.50);

        if (x >= size.width * 0.28 && x <= size.width + 4 && y >= 0 && y <= size.height) {
          final double fade = math.sin(u * math.pi).clamp(0.0, 1.0);
          final double dotRadius = (0.35 + (z * 1.05)).clamp(0.35, 1.45);
          final double alpha = (0.02 + (depth * 0.28 * fade)).clamp(0.0, 0.75);

          paint.color = dotColor.withOpacity(alpha);
          canvas.drawCircle(Offset(x, y), dotRadius, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ==========================================
// 3. MAIN STUDENT DASHBOARD VIEW
// ==========================================
class StudentDashboardView extends StatefulWidget {
  const StudentDashboardView({super.key});

  @override
  State<StudentDashboardView> createState() => _StudentDashboardViewState();
}

class _StudentDashboardViewState extends State<StudentDashboardView> {
  final PageController _cardPageController = PageController(viewportFraction: 0.92);
  int _activeCardIndex = 0;
  int _selectedClassIndex = 0;

  final List<String> _classList = [
    'All Classes',
    'Class 1',
    'Class 2',
    'Class 3',
    'Class 4',
    'Class 5',
    'Class 6',
    'Class 7',
    'Class 8',
  ];

  void _haptic() => HapticFeedback.selectionClick();

  void _showNotice(String message, {IconData icon = CupertinoIcons.checkmark_alt}) {
    _haptic();
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        margin: const EdgeInsets.only(bottom: 20, left: 20, right: 20),
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF101216),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.16),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 15),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    fontFamily: kAppFont,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _downloadNicSheet() {
    _haptic();
    final selectedClass = _classList[_selectedClassIndex];
    _showNotice("Downloading NIC Code Registry ($selectedClass)...", icon: CupertinoIcons.arrow_down_circle_fill);
  }

  @override
  void dispose() {
    _cardPageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const double hPad = 18.0;

    return Container(
      color: Colors.transparent,
      child: ScrollConfiguration(
        behavior: const _NoGlowScrollBehavior(),
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Sleek Top Bar
              Padding(
                padding: const EdgeInsets.fromLTRB(hPad, 8, hPad, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      "Student Desk",
                      style: TextStyle(
                        fontFamily: kAppFont,
                        fontSize: 16.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      "School NIC CODE : 480481",
                      style: TextStyle(
                        fontFamily: kAppFont,
                        fontSize: 11.0,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),

              // 2. Obsidian & Ceramic Style Cards
              SizedBox(
                height: 168,
                child: PageView(
                  controller: _cardPageController,
                  physics: const ClampingScrollPhysics(),
                  onPageChanged: (idx) {
                    _haptic();
                    setState(() => _activeCardIndex = idx);
                  },
                  children: [
                    // Daily Attendance Card
                    _buildLuxuryCard(
                      isDark: true,
                      badge: "DAILY REGISTER",
                      title: "Student Daily Attendance",
                      subtitle: "Daily roll-call & live verification",
                      buttonText: "Open Attendance Register",
                      showCalendarWidget: true,
                      painter: LuxuryCardWaveMeshPainter(dotColor: Colors.white),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const DailyAttendanceSheetScreen(),
                          ),
                        );
                      },
                    ),
                    // Monthly Card
                    _buildLuxuryCard(
                      isDark: false,
                      badge: "MONTHLY COMPILED",
                      title: "Monthly Attendance Roll",
                      subtitle: "Consolidated monthly audit register",
                      buttonText: "View Monthly Sheet",
                      showCalendarWidget: false,
                      painter: LuxuryCardWaveMeshPainter(dotColor: const Color(0xFF0F172A)),
                      onTap: () => _showNotice("Opening Monthly Attendance Sheet"),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 7),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(2, (index) {
                  final isActive = _activeCardIndex == index;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.symmetric(horizontal: 2.5),
                    width: isActive ? 16 : 5,
                    height: 4.5,
                    decoration: BoxDecoration(
                      color: isActive ? const Color(0xFF0F172A) : const Color(0xFFDEE2E6),
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  );
                }),
              ),

              const SizedBox(height: 14),

              // 3. Student NIC Code Directory
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: hPad),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader("STUDENT NIC CODE"),
                    const SizedBox(height: 7),
                    Container(
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.015),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(CupertinoIcons.barcode_viewfinder, size: 15, color: Color(0xFF64748B)),
                              SizedBox(width: 7),
                              Text(
                                "Filter by Class:",
                                style: TextStyle(
                                  fontFamily: kAppFont,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 31,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              physics: const ClampingScrollPhysics(),
                              itemCount: _classList.length,
                              itemBuilder: (context, idx) {
                                final isSelected = _selectedClassIndex == idx;
                                return GestureDetector(
                                  onTap: () {
                                    _haptic();
                                    setState(() => _selectedClassIndex = idx);
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 130),
                                    margin: const EdgeInsets.only(right: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 13),
                                    decoration: BoxDecoration(
                                      color: isSelected ? const Color(0xFF101216) : const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: isSelected ? const Color(0xFF101216) : const Color(0xFFE2E8F0),
                                      ),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      _classList[idx],
                                      style: TextStyle(
                                        fontFamily: kAppFont,
                                        fontSize: 11,
                                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                        color: isSelected ? Colors.white : const Color(0xFF475569),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 11),
                          _ScaleTouch(
                            onTap: _downloadNicSheet,
                            child: Container(
                              width: double.infinity,
                              height: 38,
                              decoration: BoxDecoration(
                                color: const Color(0xFF101216),
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(CupertinoIcons.arrow_down_to_line, size: 14, color: Colors.white),
                                  const SizedBox(width: 7),
                                  Flexible(
                                    child: Text(
                                      "Download NIC Sheet (${_classList[_selectedClassIndex]})",
                                      style: const TextStyle(
                                        fontFamily: kAppFont,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: -0.2,
                                        color: Colors.white,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // 4. Core Operations (New Admission & TC)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: hPad),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader("ADMISSIONS & CLEARANCES"),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Expanded(
                          child: _buildActionTile(
                            title: "New Admission",
                            desc: "Student enrollment entry",
                            icon: CupertinoIcons.person_badge_plus,
                            onTap: () => _showNotice("Opening Admission Entry Form"),
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: _buildActionTile(
                            title: "Transfer Cert. (TC)",
                            desc: "School leaving certificate",
                            icon: CupertinoIcons.arrow_up_doc,
                            onTap: () => _showNotice("Opening Transfer Certificate Module"),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // 5. Certificates Issuances
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: hPad),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader("CERTIFICATE ISSUANCES"),
                    const SizedBox(height: 7),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.015),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          _buildListRow(
                            title: "Study Certificate",
                            subtitle: "Academic validation credential",
                            icon: CupertinoIcons.doc_checkmark,
                            onTap: () => _showNotice("Opening Study Certificate"),
                          ),
                          const Divider(height: 1, thickness: 0.5, color: Color(0xFFF1F3F5), indent: 44, endIndent: 14),
                          _buildListRow(
                            title: "Character Certificate",
                            subtitle: "Conduct and behavior memo",
                            icon: CupertinoIcons.shield_lefthalf_fill,
                            onTap: () => _showNotice("Opening Character Certificate"),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // 6. State Formats & Dossiers
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: hPad),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader("STATE FORMATS & DOSSIERS"),
                    const SizedBox(height: 7),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.015),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          _buildListRow(
                            title: "Format - 5 (Profile Ledger)",
                            subtitle: "Student verification record",
                            icon: CupertinoIcons.doc_plaintext,
                            onTap: () => _showNotice("Opening Format 5 Sheet"),
                          ),
                          const Divider(height: 1, thickness: 0.5, color: Color(0xFFF1F3F5), indent: 44, endIndent: 14),
                          _buildListRow(
                            title: "Format - 9 (Academic Record)",
                            subtitle: "Cumulative academic dossier",
                            icon: CupertinoIcons.folder,
                            onTap: () => _showNotice("Opening Format 9 Record"),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIosCalendarWidget() {
    final now = DateTime.now();
    const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    String currentDayName = dayNames[now.weekday - 1];
    String currentDayNum = '${now.day}';

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            currentDayName.toUpperCase(),
            style: const TextStyle(
              fontFamily: kAppFont,
              fontSize: 9.0,
              fontWeight: FontWeight.w800,
              color: Color(0xFFEF4444),
              letterSpacing: 0.2,
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
    );
  }

  Widget _buildSectionHeader(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 3),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: kAppFont,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: Color(0xFF64748B),
        ),
      ),
    );
  }

  Widget _buildLuxuryCard({
    required bool isDark,
    required String badge,
    required String title,
    required String subtitle,
    required String buttonText,
    required bool showCalendarWidget,
    required CustomPainter painter,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: isDark
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF1B1E24),
                    Color(0xFF101216),
                    Color(0xFF090A0C),
                  ],
                )
              : const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFFFFFFF),
                    Color(0xFFF8FAFC),
                  ],
                ),
          border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.08) : const Color(0xFFE2E8F0),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isDark ? Colors.black.withOpacity(0.18) : Colors.black.withOpacity(0.03),
              blurRadius: 16,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: [
              Positioned.fill(child: CustomPaint(painter: painter)),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: TextStyle(
                                  fontFamily: kAppFont,
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.4,
                                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                subtitle,
                                style: TextStyle(
                                  fontFamily: kAppFont,
                                  fontSize: 11,
                                  letterSpacing: -0.2,
                                  color: isDark ? Colors.white.withOpacity(0.65) : const Color(0xFF64748B),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white.withOpacity(0.10) : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: isDark ? Colors.white.withOpacity(0.06) : const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Text(
                                badge,
                                style: TextStyle(
                                  fontFamily: kAppFont,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                  color: isDark ? const Color(0xFFE9ECEF) : const Color(0xFF475569),
                                ),
                              ),
                            ),
                            if (showCalendarWidget) ...[
                              const SizedBox(height: 6),
                              _buildIosCalendarWidget(),
                            ],
                          ],
                        ),
                      ],
                    ),
                    _ScaleTouch(
                      onTap: onTap,
                      child: Container(
                        width: double.infinity,
                        height: 36,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white : const Color(0xFF101216),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.06),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            buttonText,
                            style: TextStyle(
                              fontFamily: kAppFont,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                              color: isDark ? const Color(0xFF0F172A) : Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionTile({
    required String title,
    required String desc,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return _ScaleTouch(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.015),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFF1F5F9)),
              ),
              child: Icon(icon, size: 16, color: const Color(0xFF0F172A)),
            ),
            const SizedBox(height: 11),
            Text(
              title,
              style: const TextStyle(
                fontFamily: kAppFont,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 1),
            Text(
              desc,
              style: const TextStyle(
                fontFamily: kAppFont,
                fontSize: 10.5,
                color: Color(0xFF64748B),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListRow({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return _ScaleTouch(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 17, color: const Color(0xFF0F172A)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: kAppFont,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.3,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontFamily: kAppFont,
                      fontSize: 10.5,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(CupertinoIcons.chevron_forward, size: 12, color: Color(0xFFCBD5E1)),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 4. ATTENDANCE REGISTER SCREEN (With Student Search Bar & Clean UI)
// ==========================================
class DailyAttendanceSheetScreen extends StatefulWidget {
  const DailyAttendanceSheetScreen({super.key});

  @override
  State<DailyAttendanceSheetScreen> createState() => _DailyAttendanceSheetScreenState();
}

class _DailyAttendanceSheetScreenState extends State<DailyAttendanceSheetScreen> {
  String _activeClass = 'Class 1';
  final List<String> _classes = ['Class 1', 'Class 2', 'Class 3', 'Class 4', 'Class 5', 'Class 6', 'Class 7', 'Class 8'];
  late List<StudentRecord> _students;
  DateTime _selectedDate = DateTime.now();
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _loadClassData(_activeClass);
  }

  void _loadClassData(String className) {
    setState(() {
      _students = List.generate(
        15,
        (i) => StudentRecord(
          srNo: '${1001 + i}',
          nicCode: '24080${i.toString().padLeft(3, '0')}',
          name: 'Student ${String.fromCharCode(65 + i)} Sharma',
          rollNo: '${i + 1}',
          className: className,
          gender: i % 2 == 0 ? 'M' : 'F',
          attendanceStatus: 'P',
        ),
      );
      _searchQuery = ""; // Reset search on class change
    });
  }

  List<StudentRecord> get _filteredStudents {
    if (_searchQuery.isEmpty) return _students;
    final q = _searchQuery.toLowerCase();
    return _students.where((s) =>
      s.name.toLowerCase().contains(q) ||
      s.srNo.toLowerCase().contains(q) ||
      s.nicCode.toLowerCase().contains(q) ||
      s.rollNo.toLowerCase().contains(q)
    ).toList();
  }

  void _haptic() => HapticFeedback.selectionClick();

  void _showCustomCalendarPicker() {
    _haptic();
    DateTime tempDate = _selectedDate;

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
          ),
          child: StatefulBuilder(
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
                                  tempDate = DateTime(year, val, tempDate.day);
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
                                  tempDate = DateTime(val, month, tempDate.day);
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
                        physics: const ClampingScrollPhysics(),
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
                            onTap: isDisabled ? null : () {
                              setDialogState(() {
                                tempDate = currentCellDate;
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
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFFCBD5E1)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              minimumSize: const Size(48, 28),
                              splashFactory: NoSplash.splashFactory,
                            ),
                            child: const Text("Cancel", style: TextStyle(fontFamily: kAppFont, fontSize: 10.5, color: Color(0xFF64748B))),
                          ),
                          const SizedBox(width: 6),
                          ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _selectedDate = tempDate;
                              });
                              Navigator.pop(context);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0F172A),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              minimumSize: const Size(38, 28),
                              elevation: 0,
                              splashFactory: NoSplash.splashFactory,
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

  int get _presentCount => _students.where((s) => s.attendanceStatus == 'P').length;
  int get _absentCount => _students.where((s) => s.attendanceStatus == 'A').length;
  int get _leaveCount => _students.where((s) => s.attendanceStatus == 'L').length;

  @override
  Widget build(BuildContext context) {
    String formattedDate = "${_selectedDate.day.toString().padLeft(2, '0')}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.year}";
    final listToDisplay = _filteredStudents;

    return ScrollConfiguration(
      behavior: const _NoGlowScrollBehavior(),
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(CupertinoIcons.back, color: Color(0xFF0F172A)),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text(
            "Attendance Register",
            style: TextStyle(
              fontFamily: kAppFont,
              color: Color(0xFF0F172A),
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          centerTitle: true,
        ),
        body: Column(
          children: [
            // Date Picker Banner using leave.png
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
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
                        errorBuilder: (c, e, s) => const Icon(CupertinoIcons.calendar, size: 16, color: Color(0xFF64748B)),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "Attendance Date: $formattedDate",
                        style: const TextStyle(
                          fontFamily: kAppFont,
                          fontSize: 12.0,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  TextButton.icon(
                    onPressed: _showCustomCalendarPicker,
                    style: TextButton.styleFrom(
                      backgroundColor: const Color(0xFFF1F5F9),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: Image.asset(
                      'assets/icons/leave.png',
                      width: 13,
                      height: 13,
                      color: const Color(0xFF0F172A),
                      errorBuilder: (c, e, s) => const Icon(CupertinoIcons.calendar, size: 13, color: Color(0xFF0F172A)),
                    ),
                    label: const Text(
                      "Change Date",
                      style: TextStyle(fontFamily: kAppFont, fontSize: 11.0, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),

            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(
                height: 29,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  itemCount: _classes.length,
                  itemBuilder: (context, idx) {
                    final isSelected = _activeClass == _classes[idx];
                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _activeClass = _classes[idx];
                          _loadClassData(_activeClass);
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 130),
                        margin: const EdgeInsets.only(right: 5),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF101216) : const Color(0xFFF8F9FA),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected ? const Color(0xFF101216) : const Color(0xFFE2E8F0),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          _classes[idx],
                          style: TextStyle(
                            fontFamily: kAppFont,
                            fontSize: 10.5,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            color: isSelected ? Colors.white : const Color(0xFF475569),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            
            // Student Search Bar
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Container(
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: TextField(
                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
                  style: const TextStyle(fontFamily: kAppFont, fontSize: 12.5, color: Color(0xFF0F172A)),
                  decoration: const InputDecoration(
                    hintText: "Search student by name, roll, SR or NIC...",
                    hintStyle: TextStyle(fontFamily: kAppFont, fontSize: 11.5, color: Color(0xFF94A3B8)),
                    prefixIcon: Icon(CupertinoIcons.search, size: 16, color: Color(0xFF64748B)),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 10.0),
                  ),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
              child: Row(
                children: [
                  _buildStatPill("Total", "${_students.length}", const Color(0xFF475569)),
                  const SizedBox(width: 6),
                  _buildStatPill("Present", "$_presentCount", const Color(0xFF2B8A3E)),
                  const SizedBox(width: 6),
                  _buildStatPill("Absent", "$_absentCount", const Color(0xFFE03131)),
                  const SizedBox(width: 6),
                  _buildStatPill("Leave", "$_leaveCount", const Color(0xFFF59F00)),
                ],
              ),
            ),
            Expanded(
              child: listToDisplay.isEmpty
                  ? Center(
                      child: Text(
                        "No student found matching '$_searchQuery'",
                        style: const TextStyle(fontFamily: kAppFont, fontSize: 12.5, color: Color(0xFF94A3B8)),
                      ),
                    )
                  : ListView.separated(
                      physics: const ClampingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      itemCount: listToDisplay.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, idx) {
                        final student = listToDisplay[idx];
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 29,
                                height: 29,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8F9FA),
                                  borderRadius: BorderRadius.circular(7),
                                ),
                                child: Center(
                                  child: Text(
                                    student.rollNo,
                                    style: const TextStyle(
                                      fontFamily: kAppFont,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      student.name,
                                      style: const TextStyle(
                                        fontFamily: kAppFont,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.2,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                    Text(
                                      "SR: ${student.srNo} • NIC: ${student.nicCode}",
                                      style: const TextStyle(
                                        fontFamily: kAppFont,
                                        fontSize: 10.5,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Direct 1-Tap Inline Selector for P, A, L
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildInlineStatusButton(student, 'P', 'P', const Color(0xFF2B8A3E), const Color(0xFFEBFBEE)),
                                  const SizedBox(width: 4),
                                  _buildInlineStatusButton(student, 'A', 'A', const Color(0xFFE03131), const Color(0xFFFFF5F5)),
                                  const SizedBox(width: 4),
                                  _buildInlineStatusButton(student, 'L', 'L', const Color(0xFFF59F00), const Color(0xFFFFF9DB)),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFE2E8F0), width: 0.5)),
              ),
              child: _ScaleTouch(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  Navigator.pop(context);
                },
                child: Container(
                  width: double.infinity,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFF101216),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Center(
                    child: Text(
                      "Save & Sync Register",
                      style: TextStyle(
                        fontFamily: kAppFont,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        letterSpacing: -0.2,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInlineStatusButton(StudentRecord student, String label, String code, Color fgColor, Color activeBg) {
    final bool isSelected = student.attendanceStatus == code;
    return GestureDetector(
      onTap: () {
        _haptic();
        setState(() => student.attendanceStatus = code);
      },
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: isSelected ? activeBg : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? fgColor.withOpacity(0.5) : const Color(0xFFE2E8F0),
            width: isSelected ? 1.2 : 1.0,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontFamily: kAppFont,
              fontWeight: FontWeight.w800,
              fontSize: 11.5,
              color: isSelected ? fgColor : const Color(0xFF94A3B8),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatPill(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontFamily: kAppFont,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontFamily: kAppFont,
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 5. PRESS SCALE FEEDBACK WIDGET
// ==========================================
class _ScaleTouch extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const _ScaleTouch({required this.child, required this.onTap});

  @override
  State<_ScaleTouch> createState() => _ScaleTouchState();
}

class _ScaleTouchState extends State<_ScaleTouch> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) {
        setState(() => _down = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}