import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shaladarpan/tabs/teacher.dart';
import 'package:shaladarpan/tabs/student/student.dart';

const String kAppFont = 'PlusJakartaSans';

class DashboardScreen extends StatefulWidget {
  final String schoolId;
  final VoidCallback onLogoutRequested;
  const DashboardScreen({
    super.key,
    required this.schoolId,
    required this.onLogoutRequested,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final ValueNotifier<DateTime> _timeNotifier;
  late final Timer _clockTimer;
  late final PageController _cardPageController;
  final ValueNotifier<int> _cardIndexNotifier = ValueNotifier<int>(0);
  int _currentNavIndex = 0;

  @override
  void initState() {
    super.initState();
    _cardPageController = PageController(viewportFraction: 0.86);
    _timeNotifier = ValueNotifier<DateTime>(DateTime.now());

    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _timeNotifier.value = DateTime.now();
    });
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    _timeNotifier.dispose();
    _cardIndexNotifier.dispose();
    _cardPageController.dispose();
    super.dispose();
  }

  String _getFormattedDate(DateTime time) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    String day = time.day < 10 ? '0${time.day}' : '${time.day}';
    return "${days[time.weekday - 1]}, $day ${months[time.month - 1]}";
  }

  String _getFormattedTime(DateTime time) {
    int hour = time.hour;
    int minute = time.minute;
    String period = hour >= 12 ? 'PM' : 'AM';
    hour = hour % 12 == 0 ? 12 : hour % 12;
    String minStr = minute < 10 ? '0$minute' : '$minute';
    return "$hour:$minStr $period";
  }

  Widget _buildCleanAssetIcon(String path, {double size = 16, Color? tintColor}) {
    return Image.asset(
      path,
      width: size,
      height: size,
      color: tintColor,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => Icon(
        Icons.dashboard_customize_rounded,
        size: size,
        color: tintColor ?? const Color(0xFF0F172A),
      ),
    );
  }

  Widget _buildSuccessCheckIcon() {
    return Image.asset(
      'assets/icons/check.png',
      width: 20,
      height: 20,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => Container(
        width: 20,
        height: 20,
        decoration: const BoxDecoration(
          color: Color(0xFF10B981),
          shape: BoxShape.circle,
        ),
        child: const Center(
          child: Icon(
            Icons.check_rounded,
            color: Colors.white,
            size: 13,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        extendBody: true,
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            // Upgraded Atmospheric Ambient Mesh Background
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.0, 0.45, 1.0],
                    colors: [
                      Color(0xFFF8FAFC),
                      Color(0xFFF1F5F9),
                      Color(0xFFFEF3C7),
                    ],
                  ),
                ),
              ),
            ),

            Positioned(
              left: -50,
              top: -40,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 85, sigmaY: 85),
                child: Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFBAE6FD).withOpacity(0.42),
                  ),
                ),
              ),
            ),

            Positioned(
              right: -50,
              top: 40,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 90, sigmaY: 90),
                child: Container(
                  width: 240,
                  height: 240,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFDE68A).withOpacity(0.35),
                  ),
                ),
              ),
            ),

            // Tab Switching Body with proper bottom padding to prevent dock overlap
            SafeArea(
              bottom: false,
              child: _currentNavIndex == 1
                  ? const Padding(
                      padding: EdgeInsets.only(bottom: 90.0),
                      child: TeacherTabScreen(),
                    )
                  : _currentNavIndex == 2
                      ? const Padding(
                          padding: EdgeInsets.only(bottom: 90.0),
                          child: StudentDashboardView(),
                        )
                      : _currentNavIndex == 0
                          ? LayoutBuilder(
                              builder: (context, constraints) {
                                return SingleChildScrollView(
                                  physics: const BouncingScrollPhysics(),
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                                    child: Padding(
                                      padding: const EdgeInsets.only(bottom: 100.0),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const SizedBox(height: 4),

                                          // Top Bar Profile Island
                                          Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 18.0),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 9.0),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withOpacity(0.96),
                                                borderRadius: BorderRadius.circular(22),
                                                border: Border.all(color: Colors.white, width: 1.5),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: const Color(0xFF0F172A).withOpacity(0.04),
                                                    blurRadius: 12,
                                                    offset: const Offset(0, 3),
                                                  ),
                                                ],
                                              ),
                                              child: Row(
                                                children: [
                                                  InkWell(
                                                    onTap: () {
                                                      FocusManager.instance.primaryFocus?.unfocus();
                                                      _showLogoutSheet(context);
                                                    },
                                                    focusColor: Colors.transparent,
                                                    hoverColor: Colors.transparent,
                                                    highlightColor: Colors.transparent,
                                                    splashColor: Colors.transparent,
                                                    borderRadius: BorderRadius.circular(22),
                                                    child: Container(
                                                      width: 40,
                                                      height: 40,
                                                      decoration: BoxDecoration(
                                                        shape: BoxShape.circle,
                                                        color: Colors.white,
                                                        border: Border.all(color: const Color(0xFFF1F5F9), width: 1.5),
                                                        boxShadow: [
                                                          BoxShadow(
                                                            color: Colors.black.withOpacity(0.05),
                                                            blurRadius: 6,
                                                            offset: const Offset(0, 2),
                                                          ),
                                                        ],
                                                      ),
                                                      child: ClipOval(
                                                        child: Image.asset(
                                                          'assets/icons/user.png',
                                                          width: 40,
                                                          height: 40,
                                                          fit: BoxFit.cover,
                                                          errorBuilder: (c, e, s) => const Icon(
                                                            Icons.person_rounded,
                                                            color: Color(0xFF0F172A),
                                                            size: 20,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        const Text(
                                                          "Welcome back,",
                                                          style: TextStyle(
                                                            fontFamily: kAppFont,
                                                            fontSize: 11.0,
                                                            fontWeight: FontWeight.w500,
                                                            color: Color(0xFF64748B),
                                                            letterSpacing: -0.1,
                                                          ),
                                                        ),
                                                        const SizedBox(height: 1),
                                                        Text(
                                                          "${widget.schoolId} !",
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                          style: const TextStyle(
                                                            fontFamily: kAppFont,
                                                            fontSize: 15.5,
                                                            fontWeight: FontWeight.w600,
                                                            color: Color(0xFF0F172A),
                                                            letterSpacing: -0.2,
                                                          ),
                                                        ),
                                                        const SizedBox(height: 1),
                                                        ValueListenableBuilder<DateTime>(
                                                          valueListenable: _timeNotifier,
                                                          builder: (context, time, _) {
                                                            return Row(
                                                              children: [
                                                                Text(
                                                                  "${_getFormattedDate(time)} • ${_getFormattedTime(time)}",
                                                                  style: const TextStyle(
                                                                    fontFamily: kAppFont,
                                                                    fontSize: 10.0,
                                                                    fontWeight: FontWeight.w500,
                                                                    color: Color(0xFF64748B),
                                                                  ),
                                                                ),
                                                                const SizedBox(width: 5),
                                                                Container(
                                                                  width: 5.5,
                                                                  height: 5.5,
                                                                  decoration: const BoxDecoration(
                                                                    color: Color(0xFF10B981),
                                                                    shape: BoxShape.circle,
                                                                  ),
                                                                ),
                                                              ],
                                                            );
                                                          },
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  Stack(
                                                    clipBehavior: Clip.none,
                                                    children: [
                                                      Container(
                                                        width: 36,
                                                        height: 36,
                                                        decoration: BoxDecoration(
                                                          shape: BoxShape.circle,
                                                          color: const Color(0xFFF8FAFC),
                                                          border: Border.all(color: const Color(0xFFE2E8F0), width: 1.0),
                                                        ),
                                                        child: Center(
                                                          child: Image.asset(
                                                            'assets/icons/bell.png',
                                                            width: 17,
                                                            height: 17,
                                                            color: const Color(0xFF0F172A),
                                                            errorBuilder: (c, e, s) => const Icon(
                                                              Icons.notifications_none_rounded,
                                                              color: Color(0xFF0F172A),
                                                              size: 17,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      Positioned(
                                                        top: 6,
                                                        right: 7,
                                                        child: Container(
                                                          width: 6.5,
                                                          height: 6.5,
                                                          decoration: BoxDecoration(
                                                            color: const Color(0xFFFF3B30),
                                                            shape: BoxShape.circle,
                                                            border: Border.all(color: Colors.white, width: 1.2),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),

                                          const SizedBox(height: 10),

                                          // Dashboard Title
                                          const Padding(
                                            padding: EdgeInsets.symmetric(horizontal: 22.0),
                                            child: Text(
                                              "Dashboard",
                                              style: TextStyle(
                                                fontFamily: kAppFont,
                                                fontSize: 16.5,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFF0F172A),
                                                letterSpacing: -0.2,
                                              ),
                                            ),
                                          ),

                                          const SizedBox(height: 7),

                                          // KPI Capsule
                                          Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 18.0),
                                            child: Container(
                                              width: double.infinity,
                                              padding: const EdgeInsets.symmetric(vertical: 8.5, horizontal: 8.0),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withOpacity(0.96),
                                                borderRadius: BorderRadius.circular(16),
                                                border: Border.all(color: Colors.white, width: 1.2),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: const Color(0xFF0F172A).withOpacity(0.03),
                                                    blurRadius: 10,
                                                    offset: const Offset(0, 2),
                                                  ),
                                                ],
                                              ),
                                              child: IntrinsicHeight(
                                                child: Row(
                                                  children: [
                                                    Expanded(child: _buildCleanKpiWithIcon("Sections", "12", 'assets/icons/section.png')),
                                                    _buildCleanDivider(),
                                                    Expanded(child: _buildCleanKpiWithIcon("Students", "428", 'assets/icons/student.png')),
                                                    _buildCleanDivider(),
                                                    Expanded(child: _buildCleanKpiWithIcon("Attendance", "96%", 'assets/icons/chart.png')),
                                                    _buildCleanDivider(),
                                                    Expanded(child: _buildCleanSyncWithIcon("Sync", "10:15 AM", 'assets/icons/recently.png')),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),

                                          const SizedBox(height: 12),

                                          // 3D Carousel
                                          SizedBox(
                                            height: 196,
                                            child: AnimatedBuilder(
                                              animation: _cardPageController,
                                              builder: (context, child) {
                                                double page = 0.0;
                                                if (_cardPageController.hasClients && _cardPageController.page != null) {
                                                  page = _cardPageController.page!;
                                                }
                                                return PageView.builder(
                                                  controller: _cardPageController,
                                                  clipBehavior: Clip.none,
                                                  physics: const BouncingScrollPhysics(),
                                                  itemCount: 3,
                                                  onPageChanged: (index) {
                                                    _cardIndexNotifier.value = index;
                                                  },
                                                  itemBuilder: (context, index) {
                                                    final double position = page - index;
                                                    final double absDiff = position.abs();

                                                    final double scale = (1.0 - (absDiff * 0.07)).clamp(0.91, 1.0);
                                                    final double opacity = (1.0 - (absDiff * 0.22)).clamp(0.72, 1.0);

                                                    final Matrix4 matrix = Matrix4.identity()
                                                      ..setEntry(3, 2, 0.0018)
                                                      ..translate(0.0, absDiff * 4.0, 0.0)
                                                      ..rotateY(position.clamp(-1.0, 1.0) * -0.18)
                                                      ..scale(scale, scale);

                                                    Widget cardChild;
                                                    if (index == 0) {
                                                      cardChild = _buildAttendanceCard();
                                                    } else if (index == 1) {
                                                      cardChild = _buildMdmCard();
                                                    } else {
                                                      cardChild = _buildMonthlyCard();
                                                    }

                                                    return Transform(
                                                      alignment: position > 0 ? Alignment.centerRight : Alignment.centerLeft,
                                                      transform: matrix,
                                                      child: Opacity(
                                                        opacity: opacity,
                                                        child: cardChild,
                                                      ),
                                                    );
                                                  },
                                                );
                                              },
                                            ),
                                          ),

                                          const SizedBox(height: 10),

                                          // Swipe Indicator
                                          ValueListenableBuilder<int>(
                                            valueListenable: _cardIndexNotifier,
                                            builder: (context, activeIndex, _) {
                                              return Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: List.generate(3, (index) {
                                                  final bool isActive = activeIndex == index;
                                                  return AnimatedContainer(
                                                    duration: const Duration(milliseconds: 240),
                                                    curve: Curves.easeOutCubic,
                                                    margin: const EdgeInsets.symmetric(horizontal: 2.5),
                                                    height: 3.0,
                                                    width: isActive ? 16.0 : 5.0,
                                                    decoration: BoxDecoration(
                                                      color: isActive
                                                          ? const Color(0xFF0F172A)
                                                          : const Color(0xFF94A3B8).withOpacity(0.45),
                                                      borderRadius: BorderRadius.circular(2.0),
                                                    ),
                                                  );
                                                }),
                                              );
                                            },
                                          ),

                                          const SizedBox(height: 12),

                                          // Pending Tasks Card
                                          Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 18.0),
                                            child: Container(
                                              width: double.infinity,
                                              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withOpacity(0.95),
                                                borderRadius: BorderRadius.circular(22),
                                                border: Border.all(color: Colors.white, width: 1.5),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: const Color(0xFF0F172A).withOpacity(0.04),
                                                    blurRadius: 14,
                                                    offset: const Offset(0, 3),
                                                  ),
                                                ],
                                              ),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                    children: [
                                                      const Text(
                                                        "Pending Tasks",
                                                        style: TextStyle(
                                                          fontFamily: kAppFont,
                                                          fontSize: 15.0,
                                                          fontWeight: FontWeight.w600,
                                                          color: Color(0xFF0F172A),
                                                          letterSpacing: -0.2,
                                                        ),
                                                      ),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.0),
                                                        decoration: BoxDecoration(
                                                          color: const Color(0xFFF1F5F9),
                                                          borderRadius: BorderRadius.circular(12),
                                                        ),
                                                        child: const Text(
                                                          "5/5 Done",
                                                          style: TextStyle(
                                                            fontFamily: kAppFont,
                                                            fontSize: 10.5,
                                                            fontWeight: FontWeight.w600,
                                                            color: Color(0xFF475569),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 6),
                                                  _buildUnifiedTaskRow(
                                                    title: "Staff Attendance",
                                                    time: "08:30 AM",
                                                    iconPath: 'assets/icons/employee.png',
                                                  ),
                                                  _buildUnifiedTaskRow(
                                                    title: "Student Attendance",
                                                    time: "09:15 AM",
                                                    iconPath: 'assets/icons/student.png',
                                                  ),
                                                  _buildUnifiedTaskRow(
                                                    title: "Mid Day Meal (MDM)",
                                                    time: "12:45 PM",
                                                    iconPath: 'assets/icons/mdm.png',
                                                  ),
                                                  _buildUnifiedTaskRow(
                                                    title: "District Ranking",
                                                    time: "14:00 PM",
                                                    iconPath: 'assets/icons/ranking.png',
                                                  ),
                                                  _buildUnifiedTaskRow(
                                                    title: "VIFFS Entry",
                                                    time: "16:45 PM",
                                                    iconPath: 'assets/icons/viffs.png',
                                                    showDivider: false,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            )
                          : Container(),
            ),

            // Bottom Navigation Dock
            Positioned(
              left: 18,
              right: 18,
              bottom: 12,
              child: _buildIosLiquidGlassDock(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCleanKpiWithIcon(String title, String value, String iconPath) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildCleanAssetIcon(iconPath, size: 15, tintColor: const Color(0xFF334155)),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: kAppFont,
            fontSize: 13.0,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0F172A),
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: kAppFont,
            fontSize: 9.5,
            fontWeight: FontWeight.w500,
            color: Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  Widget _buildCleanSyncWithIcon(String title, String value, String iconPath) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildCleanAssetIcon(iconPath, size: 15, tintColor: const Color(0xFF334155)),
        const SizedBox(height: 3),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 5,
              height: 5,
              margin: const EdgeInsets.only(right: 3),
              decoration: const BoxDecoration(
                color: Color(0xFFF97316),
                shape: BoxShape.circle,
              ),
            ),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: kAppFont,
                fontSize: 11.0,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0F172A),
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 1),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: kAppFont,
            fontSize: 9.5,
            fontWeight: FontWeight.w500,
            color: Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  Widget _buildCleanDivider() {
    return Container(
      width: 1.0,
      height: 20.0,
      color: const Color(0xFFE2E8F0),
    );
  }

  Widget _build3DTactileCard({
    required Widget child,
    required Gradient surfaceGradient,
    required Color shadowColor,
    Color? borderColor,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 3.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: shadowColor.withOpacity(shadowColor.opacity * 0.38),
            blurRadius: 13,
            offset: const Offset(0, 5),
            spreadRadius: -2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            gradient: surfaceGradient,
            borderRadius: BorderRadius.circular(20),
            border: borderColor != null ? Border.all(color: borderColor, width: 1.2) : null,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15.0, vertical: 11.5),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildTitlePill({
    required String title,
    required String iconPath,
    bool isBlackPill = false,
  }) {
    final Color bgColor = isBlackPill ? const Color(0xFF0F172A) : Colors.white;
    final Color contentColor = isBlackPill ? Colors.white : const Color(0xFF0F172A);
    final Border border = isBlackPill
        ? Border.all(color: const Color(0xFF1E293B), width: 1.0)
        : Border.all(color: const Color(0xFFE2E8F0), width: 1.0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: border,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            iconPath,
            width: 14,
            height: 14,
            fit: BoxFit.contain,
            color: contentColor,
            errorBuilder: (context, error, stackTrace) => Icon(
              Icons.verified_outlined,
              size: 14,
              color: contentColor,
            ),
          ),
          const SizedBox(width: 5.5),
          Text(
            title,
            style: TextStyle(
              fontFamily: kAppFont,
              fontSize: 11.0,
              fontWeight: FontWeight.w600,
              color: contentColor,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceCard() {
    return _build3DTactileCard(
      surfaceGradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF2C2E35),
          Color(0xFF191A1E),
          Color(0xFF0C0D0F),
        ],
      ),
      shadowColor: Colors.black.withOpacity(0.24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildTitlePill(
            title: "Staff Attendance",
            iconPath: 'assets/icons/verified-user.png',
            isBlackPill: false,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Total Employees",
                    style: TextStyle(
                      fontFamily: kAppFont,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withOpacity(0.70),
                    ),
                  ),
                  const SizedBox(height: 1),
                  const Text(
                    "18",
                    style: TextStyle(
                      fontFamily: kAppFont,
                      fontSize: 23,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      letterSpacing: -0.4,
                    ),
                  ),
                ],
              ),
              RoundedGaugeWidget(
                percentage: 1.0,
                progressColor: const Color(0xFF10B981),
                backgroundColor: Colors.white.withOpacity(0.12),
                textColor: Colors.white,
                size: 50,
              ),
            ],
          ),
          Divider(height: 1, color: Colors.white.withOpacity(0.14)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildPill("Present: 18", const Color(0xFF10B981), textColor: Colors.white, dotSize: 6.0, textSize: 10.0),
              _buildPill("Leave: 0", const Color(0xFFEF4444), textColor: Colors.white, dotSize: 6.0, textSize: 10.0),
              _buildPill("Other: 0", const Color(0xFF94A3B8), textColor: Colors.white, dotSize: 6.0, textSize: 10.0),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMdmCard() {
    return _build3DTactileCard(
      surfaceGradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        stops: [0.0, 0.50, 1.0],
        colors: [
          Color(0xFFFFFFFF),
          Color(0xFFF8FAFC),
          Color(0xFFF1F5F9),
        ],
      ),
      borderColor: const Color(0xFFE2E8F0),
      shadowColor: const Color(0xFF0F172A).withOpacity(0.12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildTitlePill(
            title: "Mid Day Meal (MDM)",
            iconPath: 'assets/icons/mdm.png',
            isBlackPill: true,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      "Meals Served",
                      style: TextStyle(
                        fontFamily: kAppFont,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    SizedBox(height: 1),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          "385",
                          style: TextStyle(
                            fontFamily: kAppFont,
                            fontSize: 23,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF0F172A),
                            letterSpacing: -0.4,
                          ),
                        ),
                        SizedBox(width: 5),
                        Text(
                          "Students",
                          style: TextStyle(
                            fontFamily: kAppFont,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF475569),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7.5, vertical: 4.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0), width: 1.0),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildMdmStatRow("Pri (1-5)", "215"),
                      const SizedBox(height: 2),
                      _buildMdmStatRow("Up Pri (6-8)", "170"),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildPill("Status: Done", const Color(0xFF10B981), textColor: const Color(0xFF0F172A), dotSize: 6.0, textSize: 10.0),
              _buildPill("Entry: Verified", const Color(0xFF2563EB), textColor: const Color(0xFF0F172A), dotSize: 6.0, textSize: 10.0),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMonthlyCard() {
    return _build3DTactileCard(
      borderColor: const Color(0xFF94A3B8).withOpacity(0.35),
      surfaceGradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: [0.0, 0.32, 0.65, 1.0],
        colors: [
          Color(0xFFFFFFFF),
          Color(0xFFDCE3EB),
          Color(0xFF232834),
          Color(0xFF0A0C11),
        ],
      ),
      shadowColor: const Color(0xFF0F172A).withOpacity(0.32),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _TactileGridPatternPainter(
                  dotColor: const Color(0xFF94A3B8).withOpacity(0.18),
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildTitlePill(
                title: "Monthly Tasks",
                iconPath: 'assets/icons/calendar (1).png',
                isBlackPill: true,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      const Text(
                        "2/2",
                        style: TextStyle(
                          fontFamily: kAppFont,
                          fontSize: 23,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        "Done",
                        style: TextStyle(
                          fontFamily: kAppFont,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withOpacity(0.85),
                        ),
                      ),
                    ],
                  ),
                  RoundedGaugeWidget(
                    percentage: 1.0,
                    progressColor: const Color(0xFF10B981),
                    backgroundColor: Colors.white.withOpacity(0.18),
                    textColor: Colors.white,
                    size: 50,
                  ),
                ],
              ),
              Divider(height: 1, color: Colors.white.withOpacity(0.18)),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildPill("Ranking: Done", const Color(0xFF10B981), textColor: Colors.white, dotSize: 6.0, textSize: 10.0),
                  _buildPill("VIFFS: Done", const Color(0xFF38BDF8), textColor: Colors.white, dotSize: 6.0, textSize: 10.0),
                  _buildPill("Audit: OK", const Color(0xFFFBBF24), textColor: Colors.white, dotSize: 6.0, textSize: 10.0),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMdmStatRow(String label, String count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          "$label: ",
          style: const TextStyle(
            fontFamily: kAppFont,
            fontSize: 9.5,
            fontWeight: FontWeight.w500,
            color: Color(0xFF64748B),
          ),
        ),
        Text(
          count,
          style: const TextStyle(
            fontFamily: kAppFont,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }

  Widget _buildPill(
    String text,
    Color dotColor, {
    Color textColor = const Color(0xFF334155),
    double dotSize = 6.0,
    double textSize = 10.0,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: dotSize,
          height: dotSize,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4.0),
        Text(
          text,
          style: TextStyle(
            fontFamily: kAppFont,
            fontSize: textSize,
            fontWeight: FontWeight.w500,
            color: textColor,
          ),
        ),
      ],
    );
  }

  Widget _buildUnifiedTaskRow({
    required String title,
    required String time,
    required String iconPath,
    bool showDivider = true,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFE2E8F0), width: 1.0),
                ),
                child: Center(
                  child: Image.asset(
                    iconPath,
                    width: 17,
                    height: 17,
                    fit: BoxFit.contain,
                    color: const Color(0xFF1E293B),
                    errorBuilder: (context, error, stackTrace) => Image.asset(
                      'assets/icons/viffs.png',
                      width: 17,
                      height: 17,
                      fit: BoxFit.contain,
                      color: const Color(0xFF1E293B),
                      errorBuilder: (c, e, s) => const Icon(
                        Icons.check_circle_outline,
                        size: 17,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontFamily: kAppFont,
                        fontSize: 12.8,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 1.5),
                    Text(
                      time,
                      style: const TextStyle(
                        fontFamily: kAppFont,
                        fontSize: 10.5,
                        fontWeight: FontWeight.normal,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              _buildSuccessCheckIcon(),
            ],
          ),
        ),
        if (showDivider)
          const Padding(
            padding: EdgeInsets.only(left: 48.0, right: 2.0),
            child: Divider(height: 1, color: Color(0xFFF1F5F9)),
          ),
      ],
    );
  }

  Widget _buildIosLiquidGlassDock() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16.0, sigmaY: 16.0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 6.5),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.88),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withOpacity(0.05),
                blurRadius: 16,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: _buildNavItem(
                  iconPath: 'assets/icons/home.png',
                  fallbackIcon: Icons.home_rounded,
                  label: "Home",
                  index: 0,
                ),
              ),
              Expanded(
                child: _buildNavItem(
                  iconPath: 'assets/icons/employee.png',
                  fallbackIcon: Icons.badge_outlined,
                  label: "Teacher",
                  index: 1,
                ),
              ),
              Expanded(
                child: _buildNavItem(
                  iconPath: 'assets/icons/student.png',
                  fallbackIcon: Icons.school_outlined,
                  label: "Student",
                  index: 2,
                ),
              ),
              Expanded(
                child: _buildAccountNavItem(index: 3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required String iconPath,
    required IconData fallbackIcon,
    required String label,
    required int index,
  }) {
    final bool isSelected = _currentNavIndex == index;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() => _currentNavIndex = index);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 5.0),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 5,
                    offset: const Offset(0, 1.5),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              iconPath,
              width: 19,
              height: 19,
              color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF64748B),
              errorBuilder: (context, error, stackTrace) => Icon(
                fallbackIcon,
                size: 19,
                color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 2.0),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: kAppFont,
                fontSize: 9.5,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountNavItem({required int index}) {
    final bool isSelected = _currentNavIndex == index;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        FocusManager.instance.primaryFocus?.unfocus();
        setState(() => _currentNavIndex = index);
        _showLogoutSheet(context);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 5.0),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 5,
                    offset: const Offset(0, 1.5),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 19,
              height: 19,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                  width: 1.2,
                ),
              ),
              child: ClipOval(
                child: Image.asset(
                  'assets/icons/user.png',
                  width: 19,
                  height: 19,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Icon(
                    Icons.person_rounded,
                    size: 15,
                    color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2.0),
            Text(
              "Account",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: kAppFont,
                fontSize: 9.5,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLogoutSheet(BuildContext context) {
    FocusManager.instance.primaryFocus?.unfocus();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(22.0),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              "${widget.schoolId} !",
              style: const TextStyle(
                fontFamily: kAppFont,
                fontSize: 16.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              "Shaladarpan Automation Engine",
              style: TextStyle(
                fontFamily: kAppFont,
                fontSize: 12.0,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 22),
            ListTile(
              leading: const Icon(Icons.logout_rounded, color: Color(0xFFEF4444)),
              title: const Text(
                "Sign Out",
                style: TextStyle(
                  fontFamily: kAppFont,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFEF4444),
                ),
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              tileColor: const Color(0xFFFEF2F2),
              onTap: () async {
                FocusManager.instance.primaryFocus?.unfocus();
                Navigator.of(context, rootNavigator: true).pop();
                await Future.delayed(const Duration(milliseconds: 100));
                widget.onLogoutRequested();
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

class _TactileGridPatternPainter extends CustomPainter {
  final Color dotColor;
  const _TactileGridPatternPainter({required this.dotColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = dotColor
      ..style = PaintingStyle.fill;

    const double spacing = 13.5;
    const double dotRadius = 0.95;

    for (double x = 6.0; x < size.width; x += spacing) {
      for (double y = 6.0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), dotRadius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class RoundedGaugeWidget extends StatelessWidget {
  final double percentage;
  final Color progressColor;
  final Color backgroundColor;
  final Color textColor;
  final double size;

  const RoundedGaugeWidget({
    super.key,
    required this.percentage,
    required this.progressColor,
    required this.backgroundColor,
    required this.textColor,
    this.size = 50,
  });

  @override
  Widget build(BuildContext context) {
    final double stroke = size * 0.082;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _GaugePainter(
              percentage: percentage,
              progressColor: progressColor,
              backgroundColor: backgroundColor,
              strokeWidth: stroke,
            ),
          ),
          Padding(
            padding: EdgeInsets.all(stroke + 3.0),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                "${(percentage * 100).toInt()}%",
                style: TextStyle(
                  fontFamily: kAppFont,
                  fontSize: size * 0.22,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                  letterSpacing: -0.6,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double percentage;
  final Color progressColor;
  final Color backgroundColor;
  final double strokeWidth;

  _GaugePainter({
    required this.percentage,
    required this.progressColor,
    required this.backgroundColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    final bgPaint = Paint()
      ..color = backgroundColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, radius, bgPaint);

    final progressPaint = Paint()
      ..color = progressColor
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    const startAngle = -math.pi / 2;
    final sweepAngle = 2 * math.pi * percentage.clamp(0.0, 1.0);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) =>
      oldDelegate.percentage != percentage;
}