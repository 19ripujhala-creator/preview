import 'package:shaladarpan/tabs/teacher/modules/shaladarpan/monthly_tasks_screen.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shaladarpan/services/portals/shaladarpan/shaladarpan_service.dart';
import 'package:shaladarpan/services/portals/shaladarpan/offline_attendance_queue.dart';
import 'package:shaladarpan/tabs/teacher/teacher.dart';
import 'package:shaladarpan/tabs/student/student.dart';
import 'package:shaladarpan/tabs/rajsims/rajsims.dart';
import 'package:shaladarpan/tabs/account/account.dart';
import 'package:shaladarpan/services/core/backend_config.dart';
import 'package:shaladarpan/services/core/ecosystem_service.dart';
import 'package:shaladarpan/services/portals/shaladarpan/dashboard_bootstrap.dart';

const String kAppFont = 'PlusJakartaSans';

class DashboardScreen extends StatefulWidget {
  final String schoolId;
  final VoidCallback onLogoutRequested;
  final Map<String, dynamic>? initialKpi;
  final String? startupNotice;

  const DashboardScreen({
    super.key,
    required this.schoolId,
    required this.onLogoutRequested,
    this.initialKpi,
    this.startupNotice,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  bool _isVerifyingLiveStatus = true;
  OverlayEntry? _activeToast;
  Timer? _toastTimer;
  bool? _rankingTaskDone;
  bool _monthlyScreenOpen = false;
  bool? _staffTaskDone;
  bool? _studentTaskDone;
  bool _studentStatusLoading = false;
  bool? _schoolHasUpperPrimary;
  bool? _schoolHasPrimary;
  String? _mdmError;
  String? _mdmDistributionNo;
  final Map<String, DateTime> _mdmDetailsAt = {};
  final Set<String> _mdmDetailReads = {};
  List<_DashboardTask> get _dashboardTasks => [
    _DashboardTask('Staff Attendance', 'assets/icons/employee.png', _staffTaskDone,
      () => _onNavTabTapped(1, teacherSubIndex: 0, subModuleIndex: 0, forceReset: true)),
    _DashboardTask('Student Attendance', 'assets/icons/student.png', _studentTaskDone,
      () => _onNavTabTapped(2)),
    _DashboardTask('Mid Day Meal (MDM)', 'assets/icons/mdm.png', _mdmLoaded ? _mdmStatusDone : null,
      () => _onNavTabTapped(3)),
    _DashboardTask('District Ranking', 'assets/icons/ranking.png', _rankingTaskDone,
      () => _openMonthlyTasks('ranking')),
    _DashboardTask('VIFFS Entry', 'assets/icons/viffs.png', null,
      () => _openMonthlyTasks('viffs')),
  ];
  int get _completedTasks => _dashboardTasks.where((task) => task.done == true).length;
  String _taskLabel(bool? done) => done == null ? 'Not synced' : (done ? 'Completed' : 'Pending');

  late final ValueNotifier<DateTime> _timeNotifier;
  late final Timer _clockTimer;
  Timer? _networkCheckTimer;
  bool _networkCheckInProgress = false;
  bool _mdmFetchInProgress = false;
  bool _appActive = true;
  final Set<int> _visitedTabs = {0};
  late final PageController _cardPageController;
  final ValueNotifier<int> _cardIndexNotifier = ValueNotifier<int>(0);

  int _currentNavIndex = 0;
  int _teacherInitialEngine = 0;
  int _teacherSubModuleIndex = 0;
  int _teacherResetTrigger = 0;

  late final AnimationController _syncRotateController;
  bool _isSyncing = false;
  bool _syncCompleted = false;
  bool _syncButtonPressed = false;
  String _lastSyncDisplay = "Never";

  bool _isOnline = true;
  bool _hasPendingOfflineAttendance = false;
  bool _isStaffVerifiedOnPortal = false;
  bool _isStudentVerifiedOnPortal = false;

  String _kpiSections = "--";
  String _kpiStudents = "--";
  String _kpiAttendance = "--";
  String _staffTotal = "--";
  String _staffPresent = "--";
  String _staffLeave = "--";
  String _staffOther = "--";
  double _staffRatio = 0.0;

  // 🚀 Dynamic RajSIMS MDM Tile State Variables
  int? _mdmBeneficiaries;
  int? _mdmPrimaryCount;
  int? _mdmUpperPrimaryCount;
  bool _mdmStatusDone = false;
  bool _mdmLoaded = false;
  bool _mdmEntryVerified = false;

  String get _todayStr {
    final now = DateTime.now();
    return "${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _cardPageController = PageController(viewportFraction: 0.89);
    _timeNotifier = ValueNotifier<DateTime>(DateTime.now());

    _syncRotateController = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));

    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _appActive) _timeNotifier.value = DateTime.now();
    });

    DashboardBootstrap.mdmStatus.addListener(_onMdmStatusChanged);
    _startNetworkTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.startupNotice != null) _showAppleToast(widget.startupNotice!);
      _startupSync();
    });
  }

  void _startNetworkTimer() {
    _networkCheckTimer?.cancel();
    _checkConnectivityAndQueue();
    _networkCheckTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _checkConnectivityAndQueue();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    if (_appActive) {
      _startNetworkTimer();
    } else {
      _networkCheckTimer?.cancel();
    }
  }

  void _onMdmStatusChanged() {
    final status = DashboardBootstrap.mdmStatus.value;
    final now = DateTime.now();
    final key = '${widget.schoolId}/${now.year}-${now.month}-${now.day}';
    if (!mounted || status == null || status['school_id'] != widget.schoolId || status['day_key'] != key) return;
    final data = status['result'];
    if (data is Map) _applyMdmResult(Map<String, dynamic>.from(data));
  }

  void _applyMdmResult(Map<String, dynamic> data) {
    if (!mounted) return;
    final schoolName = data['school_name']?.toString() ?? '';
    final reportedSchool = data['school_id']?.toString() ?? RegExp(r'\((\d{6})\)').firstMatch(schoolName)?.group(1);
    final confirmed = data['success'] == true && data['today_entry_exists'] is bool &&
        (reportedSchool == null || reportedSchool == widget.schoolId);
    setState(() {
      _mdmLoaded = confirmed;
      _mdmStatusDone = confirmed && data['today_entry_exists'] == true;
      _mdmEntryVerified = _mdmStatusDone;
      _mdmError = confirmed ? null : data['message']?.toString() ?? 'MDM status not confirmed';
      final distribution = confirmed ? data['distribution_no']?.toString() : null;
      final count = confirmed ? int.tryParse(data['beneficiary_count']?.toString() ?? '') : null;
      if (_mdmDistributionNo != distribution || _mdmBeneficiaries != count) {
        _mdmPrimaryCount = null;
        _mdmUpperPrimaryCount = null;
        _mdmDetailsAt.clear();
      }
      _mdmDistributionNo = distribution;
      _mdmBeneficiaries = count;
      _applyMdmCategoryFallback();
    });
    if (_mdmStatusDone && (_mdmDistributionNo ?? '').isNotEmpty) {
      unawaited(_fetchMdmCategoryCounts(_mdmDistributionNo!));
    }
  }

  Future<void> _fetchLiveRajsimsMdmTileData() async {
    if (_mdmFetchInProgress || !mounted) return;
    setState(() => _mdmFetchInProgress = true);
    try {
      _applyMdmResult(await DashboardBootstrap.loadMdm(widget.schoolId));
    } catch (_) {
      _applyMdmResult({'success': false, 'message': 'MDM data unavailable'});
    } finally {
      if (mounted) setState(() => _mdmFetchInProgress = false);
      else _mdmFetchInProgress = false;
    }
  }

  Future<void> _checkConnectivityAndQueue() async {
    if (_networkCheckInProgress || !mounted || !_appActive) return;
    _networkCheckInProgress = true;
    try {
      bool online = false;
      try {
        final response = await http.get(BackendConfig.uri('/health')).timeout(const Duration(seconds: 3));
        online = response.statusCode == 200;
      } catch (_) {}
      if (online && !_mdmLoaded && !_mdmFetchInProgress) unawaited(_fetchLiveRajsimsMdmTileData());
      final pending = await OfflineAttendanceQueue.hasPendingQueue();
      if (!mounted) return;
      setState(() {
        _isOnline = online;
        _hasPendingOfflineAttendance = pending;
      });
    } catch (_) {
      // Preserve queue state when local storage cannot be read.
    } finally {
      _networkCheckInProgress = false;
    }
  }

  Future<void> _processBackendPayload(Map<String, dynamic>? data) async {
    if (data == null || !mounted) return;

    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    final kpiData = data['kpi'];
    if (kpiData is Map && kpiData.isNotEmpty && kpiData['success'] != false) {
      _applyKpiData(Map<String, dynamic>.from(kpiData));
      if (kpiData['class_summary'] is Map) _applyStudentSummary(Map<String, dynamic>.from(kpiData['class_summary']));
      _isStudentVerifiedOnPortal = _studentTaskDone == true;
      await prefs.setString('cached_student_kpi', jsonEncode(kpiData));
    }

    final staffData = data['staff_attendance'];
    if (staffData is Map && staffData.isNotEmpty && staffData['success'] != false) {
      final isMarked = ShaladarpanService.isAttendanceConfirmed(staffData);
      if (isMarked) {
        await prefs.setString('attendance_verified_date', _todayStr);
        await prefs.setBool('attendance_already_marked', true);
      } else {
        await prefs.remove('attendance_already_marked');
      }
      await prefs.setString('cached_staff_attendance', jsonEncode(staffData));
      _updateStaffUIFromData(staffData, isMarked, _todayStr);
    }

    if (mounted) {
      final now = DateTime.now();
      setState(() {
        _isOnline = true;
        _lastSyncDisplay =
            "${now.hour % 12 == 0 ? 12 : now.hour % 12}:${now.minute < 10 ? '0${now.minute}' : now.minute} ${now.hour >= 12 ? 'PM' : 'AM'}";
      });
    }
  }

  Future<void> _startupSync() async {
    try {
      await _loadInitialMetrics();
      await _refreshStaffFromCache();
      unawaited(_fetchLiveRajsimsMdmTileData());
      final result = await DashboardBootstrap.load(widget.schoolId);
      if (mounted && result['success'] == true) {
        await _processBackendPayload(result['data'] is Map ? Map<String, dynamic>.from(result['data']) : result);
      }
      if (_studentTaskDone == null) unawaited(_fetchStudentTaskStatus());
    } catch (e) {
      debugPrint("Startup sync failed: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isVerifyingLiveStatus = false;
        });
      }
    }
  }

  Future<void> _triggerUniversalSync() async {
    if (_isSyncing || _isVerifyingLiveStatus || !mounted) return;
    setState(() {
      _isSyncing = true;
      _syncCompleted = false;
    });
    _syncRotateController.repeat();
    try {
      if (_hasPendingOfflineAttendance) await OfflineAttendanceQueue.syncNow();
      final result = await ShaladarpanService.loginAndSyncDashboard(forceRefresh: true);
      if (!mounted) return;
      if (result['success'] == true) {
        await _processBackendPayload(result['data'] is Map ? Map<String, dynamic>.from(result['data']) : result);
        await Future.wait([_fetchLiveRajsimsMdmTileData(), _fetchStudentTaskStatus()]);
        await _checkConnectivityAndQueue();
        if (!mounted) return;
        setState(() => _syncCompleted = true);
        _showAppleToast(
          'School data synced',
          icon: CupertinoIcons.checkmark_seal_fill,
          iconColor: const Color(0xFF10B981),
        );
      } else {
        _showAppleToast(result['message']?.toString() ?? 'Sync failed. Cached data remains available.');
      }
    } catch (_) {
      if (mounted) _showAppleToast('Could not sync. Cached data remains available.');
    } finally {
      if (mounted) {
        _syncRotateController.stop();
        _syncRotateController.reset();
        setState(() => _isSyncing = false);
      }
    }
    if (_syncCompleted) {
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      if (mounted) setState(() => _syncCompleted = false);
    }
  }

  Future<void> _fetchAndApplyLiveStaffData() async {
    final result = await ShaladarpanService.fetchStaffAttendance(schoolId: widget.schoolId);
    if (!mounted || result['success'] != true || result['data'] is! Map) return;
    final data = Map<String, dynamic>.from(result['data']);
    final marked = data['is_already_marked'] == true || data['already_marked'] == true;
    _updateStaffUIFromData(data, marked, _todayStr);
    await _checkConnectivityAndQueue();
  }

  Future<void> _loadInitialMetrics() async {
    if (widget.initialKpi != null && widget.initialKpi!.isNotEmpty) {
      _applyKpiData(widget.initialKpi!);
      _isStudentVerifiedOnPortal = false;
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString('dashboard_cache_school_id') != widget.schoolId ||
          prefs.getString('dashboard_cache_date') != _todayStr)
        return;
      final cachedJson = prefs.getString('cached_student_kpi');
      if (cachedJson != null && cachedJson.isNotEmpty) {
        final Map<String, dynamic> data = jsonDecode(cachedJson);
        _applyKpiData(data);
        _isStudentVerifiedOnPortal = false;
      }
    } catch (_) {}
  }

  void _applyKpiData(Map<String, dynamic> kpi) {
    if (!mounted) return;
    setState(() {
      _kpiSections = kpi['sections']?.toString() ?? "--";
      _kpiStudents = kpi['students']?.toString() ?? "--";

      String rawAtt = kpi['attendance']?.toString() ?? "--";
      if (rawAtt.contains("/")) {
        final parts = rawAtt.split("/");
        _kpiAttendance = parts[0].trim();
      } else {
        _kpiAttendance = kpi['percentage']?.toString() ?? kpi['present']?.toString() ?? rawAtt;
      }

      if (kpi.containsKey('sync_time')) {
        _lastSyncDisplay = kpi['sync_time'].toString();
      }
    });
  }

  void _updateStaffUIFromData(dynamic data, bool wasMarkedToday, String cachedDate) {
    if (!mounted) return;

    int total = 0;
    int present = 0;
    int leave = 0;
    int other = 0;
    bool isAlreadyMarked = false;

    if (data is Map) {
      final rawMarked = ShaladarpanService.isAttendanceConfirmed(data);
      isAlreadyMarked = cachedDate == _todayStr && (wasMarkedToday || rawMarked);

      if (data.containsKey('stats') && data['stats'] != null) {
        final stats = data['stats'];
        total = int.tryParse(stats['total']?.toString() ?? '0') ?? 0;
        present = int.tryParse(stats['present']?.toString() ?? '0') ?? 0;
        leave = int.tryParse(stats['leave']?.toString() ?? '0') ?? 0;
        other = int.tryParse(stats['other']?.toString() ?? '0') ?? 0;
      } else {
        List staffArr = data['staff'] ?? data['data'] ?? [];
        if (staffArr.isNotEmpty) {
          total = staffArr.length;
          for (var s in staffArr) {
            final code = s['status_code']?.toString() ?? s['attendanceCode']?.toString() ?? "0";
            if (code == "0")
              present++;
            else if (code == "88" || code == "89" || s['appliedLeave'] != null)
              leave++;
            else
              other++;
          }
        }
      }
    }

    setState(() {
      if (cachedDate == _todayStr) _staffTaskDone = isAlreadyMarked;
      _isStaffVerifiedOnPortal = isAlreadyMarked && !_hasPendingOfflineAttendance;
      _staffTotal = total.toString();
      _staffPresent = present.toString();
      _staffLeave = leave.toString();
      _staffOther = other.toString();
      _staffRatio = total > 0 ? (present / total) : 0.0;
    });
  }

  Future<void> _refreshStaffFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final queued = await OfflineAttendanceQueue.getQueuedAttendance();
      if (queued != null &&
          queued["school_id"] == widget.schoolId &&
          queued["date"] == _todayStr &&
          queued["staff_list"] is List) {
        final List qList = queued["staff_list"];
        int total = qList.length;
        int present = 0, leave = 0, other = 0;

        for (var s in qList) {
          final code = s['status_code']?.toString() ?? s['attendanceCode']?.toString() ?? "0";
          if (code == "0")
            present++;
          else if (code == "88" || code == "89")
            leave++;
          else
            other++;
        }

        if (mounted) {
          setState(() {
            _hasPendingOfflineAttendance = true;
            _isStaffVerifiedOnPortal = false;
            _staffTotal = total.toString();
            _staffPresent = present.toString();
            _staffLeave = leave.toString();
            _staffOther = other.toString();
            _staffRatio = total > 0 ? (present / total) : 0.0;
          });
        }
        return;
      }

      if (prefs.getString('dashboard_cache_school_id') != widget.schoolId ||
          prefs.getString('dashboard_cache_date') != _todayStr)
        return;

      final cached = prefs.getString('cached_staff_attendance');
      if (cached != null && cached.isNotEmpty) {
        final data = jsonDecode(cached);
        _updateStaffUIFromData(data, false, "");
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    _activeToast?.remove();
    _activeToast = null;
    DashboardBootstrap.mdmStatus.removeListener(_onMdmStatusChanged);
    WidgetsBinding.instance.removeObserver(this);
    _clockTimer.cancel();
    _networkCheckTimer?.cancel();
    _timeNotifier.dispose();
    _cardIndexNotifier.dispose();
    _cardPageController.dispose();
    _syncRotateController.dispose();
    super.dispose();
  }

  void _onNavTabTapped(int index, {int teacherSubIndex = 0, int? subModuleIndex, bool forceReset = false}) {
    final returningHome = index == 0 && _currentNavIndex != 0;
    HapticFeedback.selectionClick();
    setState(() {
      _visitedTabs.add(index);
      _currentNavIndex = index;
      if (index == 1) {
        _teacherInitialEngine = teacherSubIndex;
        if (subModuleIndex != null) {
          _teacherSubModuleIndex = subModuleIndex;
        }
        if (forceReset) {
          _teacherResetTrigger++;
        }
      }
    });
    if (returningHome) {
      unawaited(_fetchAndApplyLiveStaffData());
      unawaited(_fetchStudentTaskStatus());
      unawaited(_fetchLiveRajsimsMdmTileData());
    }
  }

  void _showAppleToast(
    String message, {
    IconData icon = CupertinoIcons.checkmark_alt,
    Color iconColor = const Color(0xFF10B981),
  }) {
    if (!mounted) return;
    _toastTimer?.cancel();
    _activeToast?.remove();
    _activeToast = null;
    HapticFeedback.lightImpact();
    final overlay = Overlay.of(context);
    final topInset = MediaQuery.of(context).padding.top;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => Positioned(
        top: topInset + 12,
        left: 20,
        right: 20,
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18.0, sigmaY: 18.0),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 420),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A).withOpacity(0.92),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withOpacity(0.14), width: 0.8),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 18, offset: const Offset(0, 5)),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, color: iconColor, size: 14),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: kAppFont,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    _activeToast = entry;
    overlay.insert(entry);
    _toastTimer = Timer(const Duration(milliseconds: 3000), () {
      if (identical(_activeToast, entry)) { entry.remove(); _activeToast = null; }
    });
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
      cacheWidth: 64,
      errorBuilder: (context, error, stackTrace) =>
          Icon(Icons.dashboard_customize_rounded, size: size, color: tintColor ?? const Color(0xFF0F172A)),
    );
  }

  Widget _buildSuccessCheckIcon() {
    return Image.asset(
      'assets/icons/check.png',
      width: 20,
      height: 20,
      fit: BoxFit.contain,
      cacheWidth: 48,
      errorBuilder: (context, error, stackTrace) => Container(
        width: 20,
        height: 20,
        decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle),
        child: const Center(child: Icon(Icons.check_rounded, color: Colors.white, size: 13)),
      ),
    );
  }

  Widget _buildCardVerificationBadge({required bool isVerified, bool isOfflineQueued = false}) {
    if (isOfflineQueued)
      return const Padding(
        padding: EdgeInsets.only(top: 2.0, right: 2.0),
        child: Icon(CupertinoIcons.cloud_upload_fill, size: 16, color: Color(0xFFF59E0B)),
      );
    if (isVerified)
      return const Padding(
        padding: EdgeInsets.only(top: 2.0, right: 2.0),
        child: Icon(CupertinoIcons.checkmark_seal_fill, size: 18, color: Color(0xFF10B981)),
      );
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        textSelectionTheme: const TextSelectionThemeData(
          selectionColor: Color(0x332563EB),
          cursorColor: Color(0xFF0F172A),
          selectionHandleColor: Color(0xFF2563EB),
        ),
      ),
      child: SelectionContainer.disabled(
        child: FocusScope(
          canRequestFocus: true,
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.dark,
              statusBarBrightness: Brightness.light,
              systemNavigationBarColor: Colors.transparent,
              systemNavigationBarIconBrightness: Brightness.dark,
            ),
            child: Scaffold(
              resizeToAvoidBottomInset: false,
              extendBody: true,
              extendBodyBehindAppBar: true,
              backgroundColor: const Color(0xFFF8FAFC),
              body: SizedBox.expand(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    RepaintBoundary(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                stops: [0.0, 0.45, 1.0],
                                colors: [Color(0xFFF8FAFC), Color(0xFFF1F5F9), Color(0xFFFEF3C7)],
                              ),
                            ),
                          ),
                          Positioned(
                            left: -50,
                            top: -40,
                            child: Container(
                              width: 270,
                              height: 270,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    const Color(0xFFBAE6FD).withOpacity(0.35),
                                    const Color(0xFFBAE6FD).withOpacity(0.0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            right: -50,
                            top: 40,
                            child: Container(
                              width: 260,
                              height: 260,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    const Color(0xFFFDE68A).withOpacity(0.35),
                                    const Color(0xFFFDE68A).withOpacity(0.0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SafeArea(
                      bottom: false,
                      child: IndexedStack(
                        index: _currentNavIndex,
                        children: [
                          _buildDashboardHome(),
                          if (_visitedTabs.contains(1))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 80.0),
                              child: TeacherTabScreen(
                                key: const ValueKey('teacher_tab_main'),
                                schoolId: widget.schoolId,
                                initialEngineIndex: _teacherInitialEngine,
                                subModuleIndex: _teacherSubModuleIndex,
                                resetTrigger: _teacherResetTrigger,
                                onAttendanceUpdated: () async {
                                  _checkConnectivityAndQueue();
                                  await _fetchAndApplyLiveStaffData();
                                },
                              ),
                            )
                          else
                            const SizedBox.shrink(),
                          if (_visitedTabs.contains(2))
                            const Padding(padding: EdgeInsets.only(bottom: 80.0), child: StudentDashboardView())
                          else
                            const SizedBox.shrink(),
                          if (_visitedTabs.contains(3))
                            const Padding(padding: EdgeInsets.only(bottom: 80.0), child: RajsimsTabView())
                          else
                            const SizedBox.shrink(),
                          if (_visitedTabs.contains(4))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 80.0),
                              child: AccountTabView(
                                schoolId: widget.schoolId,
                                onLogoutRequested: widget.onLogoutRequested,
                              ),
                            )
                          else
                            const SizedBox.shrink(),
                        ],
                      ),
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 12,
                      child: RepaintBoundary(child: _buildIosLiquidGlassDock()),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDashboardHome() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 110.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 6),

                  // 🚀 Instant Header (Visible immediately)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18.0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.96),
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
                      child: Row(
                        children: [
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              FocusManager.instance.primaryFocus?.unfocus();
                              _showLogoutSheet(context);
                            },
                            child: Container(
                              width: 42,
                              height: 42,
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
                                  width: 42,
                                  height: 42,
                                  fit: BoxFit.cover,
                                  cacheWidth: 96,
                                  errorBuilder: (c, e, s) =>
                                      const Icon(Icons.person_rounded, color: Color(0xFF0F172A), size: 20),
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
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        "${widget.schoolId} !",
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontFamily: kAppFont,
                                          fontSize: 15.5,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF0F172A),
                                          letterSpacing: -0.2,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    if (!_isOnline)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.0),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF1F5F9),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: const Color(0xFFCBD5E1), width: 0.9),
                                        ),
                                        child: const Text(
                                          "Offline Mode",
                                          style: TextStyle(
                                            fontFamily: kAppFont,
                                            fontSize: 9.0,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF475569),
                                          ),
                                        ),
                                      )
                                    else if (_hasPendingOfflineAttendance)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.0),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFEF3C7),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: const Color(0xFFF59E0B), width: 0.9),
                                        ),
                                        child: const Text(
                                          "Pending Sync",
                                          style: TextStyle(
                                            fontFamily: kAppFont,
                                            fontSize: 9.0,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFFB45309),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                ValueListenableBuilder<DateTime>(
                                  valueListenable: _timeNotifier,
                                  builder: (context, time, _) {
                                    return Row(
                                      children: [
                                        Text(
                                          "${_getFormattedDate(time)} • ${_getFormattedTime(time)}",
                                          style: const TextStyle(
                                            fontFamily: kAppFont,
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w500,
                                            color: Color(0xFF64748B),
                                          ),
                                        ),
                                        const SizedBox(width: 5),
                                        Container(
                                          width: 6.0,
                                          height: 6.0,
                                          decoration: BoxDecoration(
                                            color: !_isOnline
                                                ? const Color(0xFF94A3B8)
                                                : (_hasPendingOfflineAttendance
                                                      ? const Color(0xFFF59E0B)
                                                      : const Color(0xFF10B981)),
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
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Dashboard",
                          style: TextStyle(
                            fontFamily: kAppFont,
                            fontSize: 16.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                            letterSpacing: -0.2,
                          ),
                        ),
                        _buildFixedSleekSyncButton(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  // 🚀 The Magic Blur Wrapper Area
                  Stack(
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // KPI Tiles Row
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 18.0),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 9.5, horizontal: 8.0),
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
                                    Expanded(
                                      child: _buildCleanKpiWithIcon(
                                        "Sections",
                                        _kpiSections,
                                        'assets/icons/section.png',
                                      ),
                                    ),
                                    _buildCleanDivider(),
                                    Expanded(
                                      child: _buildCleanKpiWithIcon(
                                        "Students",
                                        _kpiStudents,
                                        'assets/icons/student.png',
                                      ),
                                    ),
                                    _buildCleanDivider(),
                                    Expanded(
                                      child: _buildCleanKpiWithIcon(
                                        "Attendance",
                                        _kpiAttendance,
                                        'assets/icons/chart.png',
                                      ),
                                    ),
                                    _buildCleanDivider(),
                                    Expanded(
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: _triggerUniversalSync,
                                        child: _buildCleanSyncWithIcon(
                                          "Sync",
                                          _isSyncing
                                              ? "Syncing..."
                                              : (_hasPendingOfflineAttendance
                                                    ? "Pending"
                                                    : (!_isOnline ? "Offline" : _lastSyncDisplay)),
                                          'assets/icons/recently.png',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Carousel Cards
                          RepaintBoundary(
                            child: SizedBox(
                              height: 198,
                              child: AnimatedBuilder(
                                animation: _cardPageController,
                                builder: (context, child) {
                                  double page = _cardIndexNotifier.value.toDouble();
                                  if (_cardPageController.hasClients &&
                                      _cardPageController.position.haveDimensions &&
                                      _cardPageController.page != null) {
                                    page = _cardPageController.page!;
                                  }

                                  return PageView.builder(
                                    controller: _cardPageController,
                                    clipBehavior: Clip.none,
                                    physics: const BouncingScrollPhysics(),
                                    itemCount: 3,
                                    onPageChanged: (index) => _cardIndexNotifier.value = index,
                                    itemBuilder: (context, index) {
                                      final double diff = (page - index).abs().clamp(0.0, 1.0);
                                      final double scale = 1.0 - (diff * 0.045);

                                      Widget cardChild;
                                      if (index == 0)
                                        cardChild = GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: () => _onNavTabTapped(1, forceReset: true),
                                          child: _buildAttendanceCard(),
                                        );
                                      else if (index == 1)
                                        cardChild = GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: () => _onNavTabTapped(3),
                                          child: _buildMdmCard(),
                                        );
                                      else
                                        cardChild = GestureDetector(behavior: HitTestBehavior.opaque,
                                          onTap: () => _openMonthlyTasks('ranking'), child: _buildMonthlyCard());

                                      return Transform.scale(
                                        scale: scale,
                                        alignment: Alignment.center,
                                        child: cardChild,
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
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
                          const SizedBox(height: 14),

                          if (!_isOnline || _hasPendingOfflineAttendance)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 2.0),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.92),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: _hasPendingOfflineAttendance
                                        ? const Color(0xFFF59E0B).withOpacity(0.45)
                                        : const Color(0xFFCBD5E1),
                                    width: 1.0,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          (_hasPendingOfflineAttendance
                                                  ? const Color(0xFFF59E0B)
                                                  : const Color(0xFF0F172A))
                                              .withOpacity(0.04),
                                      blurRadius: 10,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: _hasPendingOfflineAttendance
                                            ? const Color(0xFFFEF3C7)
                                            : const Color(0xFFF1F5F9),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        _hasPendingOfflineAttendance
                                            ? CupertinoIcons.cloud_upload_fill
                                            : Icons.cloud_off_rounded,
                                        color: _hasPendingOfflineAttendance
                                            ? const Color(0xFFD97706)
                                            : const Color(0xFF64748B),
                                        size: 15,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _hasPendingOfflineAttendance
                                                ? "Attendance Queued for Auto-Push"
                                                : "Working in Offline Mode",
                                            style: const TextStyle(
                                              fontFamily: kAppFont,
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF0F172A),
                                            ),
                                          ),
                                          const SizedBox(height: 1),
                                          Text(
                                            _hasPendingOfflineAttendance
                                                ? "Saved locally • Will push when connected"
                                                : "Using stored records • Reconnect to sync",
                                            style: const TextStyle(
                                              fontFamily: kAppFont,
                                              fontSize: 10.0,
                                              fontWeight: FontWeight.w500,
                                              color: Color(0xFF64748B),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          const SizedBox(height: 10),

                          SizedBox(height: 32,
                            child: (_isVerifyingLiveStatus || _mdmFetchInProgress || _studentStatusLoading)
                              ? const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 20),
                                  child: Row(children: [
                                    CupertinoActivityIndicator(radius: 7), SizedBox(width: 8),
                                    Text('Updating school data…', style: TextStyle(fontFamily: kAppFont,
                                      fontSize: 11, color: Color(0xFF64748B))),
                                  ]),
                                )
                              : const SizedBox.shrink(),
                          ),
                          Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: _buildTaskPanel()),
                        ],
                      ),


                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFixedSleekSyncButton() {
    final String buttonLabel = _syncCompleted
        ? "Synced"
        : (_isSyncing ? "Syncing..." : (_hasPendingOfflineAttendance ? "Push Offline" : "Sync Now"));

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _syncButtonPressed = true),
        onTapUp: (_) {
          setState(() => _syncButtonPressed = false);
          _triggerUniversalSync();
        },
        onTapCancel: () => setState(() => _syncButtonPressed = false),
        child: AnimatedScale(
          scale: _syncButtonPressed ? 0.94 : 1.0,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            height: 32,
            decoration: BoxDecoration(
              color: _syncCompleted
                  ? const Color(0xFF10B981)
                  : (_hasPendingOfflineAttendance
                        ? const Color(0xFFF59E0B)
                        : (_isSyncing ? const Color(0xFF1E293B) : const Color(0xFF0F172A))),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color:
                      (_syncCompleted
                              ? const Color(0xFF10B981)
                              : (_hasPendingOfflineAttendance ? const Color(0xFFF59E0B) : const Color(0xFF0F172A)))
                          .withOpacity(0.18),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_syncCompleted)
                  const Icon(CupertinoIcons.checkmark_alt, size: 14, color: Colors.white)
                else if (_hasPendingOfflineAttendance)
                  const Icon(CupertinoIcons.cloud_upload, size: 13, color: Colors.white)
                else
                  RotationTransition(
                    turns: _syncRotateController,
                    child: const Icon(CupertinoIcons.arrow_2_circlepath, size: 13, color: Colors.white),
                  ),
                const SizedBox(width: 5.5),
                Text(
                  buttonLabel,
                  style: const TextStyle(
                    fontFamily: kAppFont,
                    fontSize: 11.0,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.1,
                  ),
                ),
              ],
            ),
          ),
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
        if (value == '--' && _isVerifyingLiveStatus)
          const _DashboardSkeleton(width: 34, height: 15)
        else Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: kAppFont,
            fontSize: 13.0,
            fontWeight: FontWeight.w700,
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
    Color dotColor = const Color(0xFF10B981);
    if (_isSyncing)
      dotColor = const Color(0xFF0284C7);
    else if (_hasPendingOfflineAttendance)
      dotColor = const Color(0xFFF59E0B);
    else if (!_isOnline)
      dotColor = const Color(0xFF94A3B8);

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
              decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
            ),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: kAppFont,
                fontSize: 11.0,
                fontWeight: FontWeight.w700,
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
    return Container(width: 1.0, height: 20.0, color: const Color(0xFFE2E8F0));
  }

  Widget _build3DTactileCard({
    required Widget child,
    required Gradient surfaceGradient,
    required Color shadowColor,
    Color? borderColor,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 2.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 2)),
          BoxShadow(
            color: shadowColor.withOpacity(shadowColor.opacity * 0.32),
            blurRadius: 12,
            offset: const Offset(0, 4),
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
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0), child: child),
        ),
      ),
    );
  }

  Widget _buildTitlePill({required String title, required String iconPath, bool isBlackPill = false}) {
    final Color bgColor = isBlackPill ? const Color(0xFF0F172A) : Colors.white;
    final Color contentColor = isBlackPill ? Colors.white : const Color(0xFF0F172A);
    final Border border = isBlackPill
        ? Border.all(color: const Color(0xFF1E293B), width: 1.0)
        : Border.all(color: const Color(0xFFE2E8F0), width: 1.0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(16), border: border),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            iconPath,
            width: 14,
            height: 14,
            fit: BoxFit.contain,
            color: contentColor,
            cacheWidth: 48,
            errorBuilder: (context, error, stackTrace) => Icon(Icons.verified_outlined, size: 14, color: contentColor),
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
        colors: [Color(0xFF1C2028), Color(0xFF111318), Color(0xFF090B0E)],
      ),
      shadowColor: Colors.black.withOpacity(0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildTitlePill(
                title: "Staff Attendance",
                iconPath: 'assets/icons/verified-user.png',
                isBlackPill: false,
              ),
              _buildCardVerificationBadge(
                isVerified: _isStaffVerifiedOnPortal,
                isOfflineQueued: _hasPendingOfflineAttendance,
              ),
            ],
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
                      fontSize: 11.0,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withOpacity(0.72),
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    _staffTotal != "0" ? _staffTotal : "--",
                    style: const TextStyle(
                      fontFamily: kAppFont,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: -0.4,
                    ),
                  ),
                ],
              ),
              RoundedGaugeWidget(
                percentage: _staffRatio > 0.0 ? _staffRatio : 0.0,
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
              _buildPill("Present: $_staffPresent", const Color(0xFF34D399), textColor: Colors.white),
              _buildPill("Leave: $_staffLeave", const Color(0xFFEF4444), textColor: Colors.white),
              _buildPill("Other: $_staffOther", const Color(0xFF94A3B8), textColor: Colors.white),
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
        colors: [Color(0xFFFFFFFF), Color(0xFFF8FAFC), Color(0xFFF1F5F9)],
      ),
      borderColor: const Color(0xFFE2E8F0),
      shadowColor: const Color(0xFF0F172A).withOpacity(0.12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildTitlePill(title: "Mid Day Meal (MDM)", iconPath: 'assets/icons/mdm.png', isBlackPill: true),
              if (_mdmFetchInProgress) const CupertinoActivityIndicator(radius: 7)
              else _buildCardVerificationBadge(isVerified: _mdmEntryVerified),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Meals Served",
                      style: TextStyle(
                        fontFamily: kAppFont,
                        fontSize: 11.0,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 1),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          _mdmBeneficiaries?.toString() ?? '--',
                          style: const TextStyle(
                            fontFamily: kAppFont,
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Text(
                          "Students",
                          style: TextStyle(
                            fontFamily: kAppFont,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
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
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0), width: 1.0),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildMdmStatRow("Pri (1-5)", _mdmPrimaryCount?.toString() ?? '—'),
                      const SizedBox(height: 2),
                      _buildMdmStatRow("Up Pri (6-8)", _mdmUpperPrimaryCount?.toString() ?? '—'),
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
              _buildPill(
                _mdmLoaded ? (_mdmStatusDone ? "Status: Completed" : "Status: Pending") : (_mdmFetchInProgress ? 'Loading…' : (_mdmError ?? 'Not synced')),
                _mdmStatusDone ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                textColor: const Color(0xFF0F172A),
              ),
              _buildPill(
                _mdmEntryVerified ? "Entry: Verified" : "Entry: Unverified",
                _mdmEntryVerified ? const Color(0xFF2563EB) : const Color(0xFF94A3B8),
                textColor: const Color(0xFF0F172A),
              ),
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
        colors: [Color(0xFFFFFFFF), Color(0xFFDCE3EB), Color(0xFF232834), Color(0xFF0A0C11)],
      ),
      shadowColor: const Color(0xFF0F172A).withOpacity(0.32),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _TactileGridPatternPainter(dotColor: const Color(0xFF94A3B8).withOpacity(0.18)),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildTitlePill(title: "Monthly Tasks", iconPath: 'assets/icons/calendar (1).png', isBlackPill: true),
                  _buildCardVerificationBadge(isVerified: false),
                ],
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
                        "—",
                        style: TextStyle(
                          fontFamily: kAppFont,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        "",
                        style: TextStyle(
                          fontFamily: kAppFont,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withOpacity(0.85),
                        ),
                      ),
                    ],
                  ),
                  Container(width: 50, height: 50,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.18), width: 4)),
                    child: const Text('—', style: TextStyle(fontFamily: kAppFont, fontSize: 16, color: Colors.white))),
                ],
              ),
              Divider(height: 1, color: Colors.white.withOpacity(0.18)),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildPill("Ranking: —", const Color(0xFF10B981), textColor: Colors.white),
                  _buildPill("VIFFS: —", const Color(0xFF38BDF8), textColor: Colors.white),
                  _buildPill("Audit: —", const Color(0xFFFBBF24), textColor: Colors.white),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openMonthlyTasks(String task) async {
    if (_monthlyScreenOpen) return;
    _monthlyScreenOpen = true;
    try {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MonthlyTasksScreen(
        schoolId: widget.schoolId, initialTask: task,
        onStatus: (name, completed) {
          if (mounted && name == 'ranking') setState(() => _rankingTaskDone = completed);
        },
      )));
    } finally { _monthlyScreenOpen = false; }
  }

  void _showUnavailableTask(String title) {
    _showAppleToast('$title is not available yet.',
      icon: CupertinoIcons.info_circle, iconColor: const Color(0xFF93C5FD));
  }

  void _openPendingTask(_DashboardTask task) {
    if (task.done == true) return;
    if (task.unavailable) {
      _showUnavailableTask(task.title);
      return;
    }
    _showAppleToast('${task.title} • ${_taskLabel(task.done)}',
      icon: CupertinoIcons.info_circle,
      iconColor: task.done == false ? const Color(0xFFFBBF24) : const Color(0xFF93C5FD));
    task.onTap();
  }

  // A primary-only school can attribute the portal total to its only eligible category.
  // Never infer a mixed school's meal split from attendance or enrollment ratios.
  void _applyMdmCategoryFallback() {
    if (!_mdmLoaded) return;
    if (_schoolHasUpperPrimary == false && _schoolHasPrimary == true) {
      _mdmPrimaryCount = _mdmBeneficiaries;
      _mdmUpperPrimaryCount = null;
    } else if (_schoolHasPrimary == false && _schoolHasUpperPrimary == true) {
      _mdmPrimaryCount = null;
      _mdmUpperPrimaryCount = _mdmBeneficiaries;
    }
  }

  Future<void> _fetchMdmCategoryCounts(String distributionNo) async {
    final requestedDay = _todayStr;
    final detailKey = '$requestedDay/$distributionNo';
    final lastRead = _mdmDetailsAt[detailKey];
    if (_mdmDetailReads.contains(detailKey) || (lastRead != null && DateTime.now().difference(lastRead) < const Duration(seconds: 30))) return;
    _mdmDetailReads.add(detailKey);
    try {
      final uri = BackendConfig.uri('/api/rajsims/mdm/entry').replace(queryParameters: {'dist_no': distributionNo});
      final response = await http.get(uri).timeout(const Duration(seconds: 45));
      final decoded = EcosystemService.decode(response);
      final data = decoded['data'] is Map ? Map<String, dynamic>.from(decoded['data']) : decoded;
      if (!mounted || requestedDay != _todayStr || distributionNo != _mdmDistributionNo || response.statusCode != 200 || data['success'] != true || data['items'] is! List) return;
      final byGroup = <String, int>{};
      final categories = <String, String>{};
      var malformed = false;
      for (final item in data['items'] as List) {
        if (item is! Map) { malformed = true; break; }
        final name = item['groupName']?.toString().toLowerCase() ?? '';
        final category = RegExp(r'upper|6\s*(?:-|to)\s*8|vi\s*(?:-|to)\s*viii').hasMatch(name)
            ? 'upper' : (name.contains('primary') || RegExp(r'1\s*(?:-|to)\s*5').hasMatch(name) ? 'primary' : null);
        final count = int.tryParse(item['beneficiary']?.toString() ?? '');
        if (category == null || count == null || count < 0) { malformed = true; break; }
        final group = '${item['groupId'] ?? ''}/$name';
        if (byGroup.containsKey(group) && byGroup[group] != count) { malformed = true; break; }
        byGroup[group] = count; // Wheat/Rice rows contain the same beneficiaries; do not add twice.
        categories[group] = category;
      }
      if (malformed || byGroup.isEmpty) return;
      _mdmDetailsAt[detailKey] = DateTime.now();
      int? primary, upper;
      for (final group in byGroup.keys) {
        if (categories[group] == 'primary') primary = (primary ?? 0) + byGroup[group]!;
        else upper = (upper ?? 0) + byGroup[group]!;
      }
      if ((primary ?? 0) + (upper ?? 0) != _mdmBeneficiaries) return;
      setState(() {
        _mdmPrimaryCount = primary;
        _mdmUpperPrimaryCount = upper;
        _applyMdmCategoryFallback();
      });
    } catch (_) { /* Keep the verified total; unavailable split stays a dash. */ }
    finally { _mdmDetailReads.remove(detailKey); }
  }

  void _applyStudentSummary(Map<String, dynamic> data) {
    final classes = data['classes'];
      setState(() {
        _studentTaskDone = data['success'] == true && classes is List && classes.isNotEmpty
            ? classes.every((row) => row is Map && row['done'] == true && !RegExp(r'pending|unmarked|not[ _]marked|not[ _]done', caseSensitive: false).hasMatch(row['status']?.toString() ?? '')) : null;
        _isStudentVerifiedOnPortal = _studentTaskDone == true;
        if (data['success'] == true && classes is List && classes.isNotEmpty) {
          final grades = classes.map((row) => row is Map
              ? int.tryParse(RegExp(r'^(\d+)').firstMatch(row['section']?.toString().trim() ?? '')?.group(1) ?? '') : null).toList();
          if (grades.every((grade) => grade != null && grade >= 1 && grade <= 12)) {
            _schoolHasPrimary = grades.any((grade) => grade! <= 5);
            _schoolHasUpperPrimary = grades.any((grade) => grade! >= 6);
            _applyMdmCategoryFallback();
          }
        }
      });
  }

  Future<void> _fetchStudentTaskStatus() async {
    if (!mounted || _studentStatusLoading) return;
    setState(() => _studentStatusLoading = true);
    try {
      final response = await http.get(BackendConfig.uri('/api/student/summary')).timeout(const Duration(seconds: 45));
      final decoded = EcosystemService.decode(response);
      final data = decoded['data'] is Map ? Map<String, dynamic>.from(decoded['data']) : decoded;
      final classes = data['classes'];
      if (!mounted) return;
      if (response.statusCode == 200) _applyStudentSummary(data);

    } catch (_) {
      if (mounted) setState(() { _studentTaskDone = null; _isStudentVerifiedOnPortal = false; });
    } finally {
      if (mounted) setState(() => _studentStatusLoading = false);
    }
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
    double dotSize = 6.5,
    double textSize = 11.5,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: dotSize,
          height: dotSize,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5.0),
        Text(
          text,
          style: TextStyle(fontFamily: kAppFont, fontSize: textSize, fontWeight: FontWeight.w600, color: textColor),
        ),
      ],
    );
  }

  Widget _buildTaskPanel() {
    final tasks = _dashboardTasks;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white, width: 1.2),
        boxShadow: [
          BoxShadow(color: const Color(0xFF0F172A).withOpacity(0.055),
            blurRadius: 24, offset: const Offset(0, 8)),
          BoxShadow(color: const Color(0xFF64748B).withOpacity(0.035),
            blurRadius: 2, offset: const Offset(0, 1)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF3F5F8),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(18, 19, 18, 16), child: Row(children: [
          Container(width: 34, height: 34,
            decoration: BoxDecoration(color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(11)),
            child: const Icon(CupertinoIcons.list_bullet, size: 18, color: Colors.white)),
          const SizedBox(width: 10),
          const Expanded(child: Text('Task Checklist', style: TextStyle(fontFamily: kAppFont,
            fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: -0.2,
            color: Color(0xFF0F172A)))),
          const SizedBox(width: 12),
          Semantics(label: '$_completedTasks of ${tasks.length} tasks completed',
            child: ExcludeSemantics(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('$_completedTasks/${tasks.length}', style: const TextStyle(fontFamily: kAppFont,
                fontSize: 22, height: 1.1, fontWeight: FontWeight.w700,
                letterSpacing: -0.8, color: Color(0xFF0F172A))),
              const SizedBox(height: 3),
              const Text('Completed', style: TextStyle(fontFamily: kAppFont,
                fontSize: 9.5, fontWeight: FontWeight.w500, color: Color(0xFF64748B))),
            ]))),
        ])),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 18),
          child: Divider(height: 1, color: Color(0xFFE9EEF4))),
        Padding(padding: const EdgeInsets.fromLTRB(16, 3, 16, 10), child: Column(children: [
          for (var index = 0; index < tasks.length; index++)
            _buildUnifiedTaskRow(title: tasks[index].title,
              time: tasks[index].unavailable ? '—' : _taskLabel(tasks[index].done),
              iconPath: tasks[index].iconPath, done: tasks[index].done,
              onTap: () => _openPendingTask(tasks[index]), showDivider: index < tasks.length - 1),
        ])),
      ]),
    );
  }

  Widget _buildUnifiedTaskRow({required String title, required String time,
    required String iconPath, bool? done, VoidCallback? onTap, bool showDivider = true}) {
    final complete = done == true;
    final status = time == '—' ? 'Planned' : time;
    final category = title == 'Mid Day Meal (MDM)' ? 'Meal distribution'
        : title.contains('Attendance') ? 'Daily attendance' : 'Monthly compliance';
    return Column(children: [
      Material(color: Colors.transparent, child: InkWell(
        onTap: complete ? null : onTap, borderRadius: BorderRadius.circular(10),
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 13),
          child: Row(children: [
            SizedBox(width: 36, height: 36,
              child: Center(child: Image.asset(iconPath, width: 23, height: 23,
                fit: BoxFit.contain, color: const Color(0xFF334155), cacheWidth: 112,
                errorBuilder: (_, __, ___) => const Icon(CupertinoIcons.doc_text,
                  size: 23, color: Color(0xFF334155))))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: kAppFont, fontSize: 12.5,
                  fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
              const SizedBox(height: 4),
              Text(complete ? category : status, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: kAppFont, fontSize: 10,
                  fontWeight: FontWeight.w400,
                  color: done == false ? const Color(0xFF9A6700) : const Color(0xFF64748B))),
            ])),
            const SizedBox(width: 12),
            Tooltip(message: complete ? 'Completed' : status, child: Semantics(
              label: '$title ${complete ? 'completed' : status}',
              child: complete
                  ? Image.asset('assets/icons/check.png', width: 22, height: 22,
                      fit: BoxFit.contain, cacheWidth: 88,
                      errorBuilder: (_, __, ___) => const Icon(CupertinoIcons.checkmark_alt,
                        size: 22, color: Color(0xFF16A34A)))
                  : Container(width: 22, height: 22,
                      decoration: BoxDecoration(shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFCBD5E1), width: 1.4))),
            )),
          ]),
        ),
      )),
      if (showDivider) Padding(padding: const EdgeInsets.only(left: 50),
        child: Divider(height: 1, color: const Color(0xFF94A3B8).withOpacity(0.16))),
    ]);
  }

  Widget _buildIosLiquidGlassDock() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18.0, sigmaY: 18.0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 5.0),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.95),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
            boxShadow: [
              BoxShadow(color: const Color(0xFF0F172A).withOpacity(0.09), blurRadius: 18, offset: const Offset(0, 5)),
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
                  iconSize: 19.0,
                ),
              ),
              Expanded(
                child: _buildNavItem(
                  iconPath: 'assets/icons/employee.png',
                  fallbackIcon: Icons.badge_outlined,
                  label: "Teacher",
                  index: 1,
                  iconSize: 21.0,
                ),
              ),
              Expanded(
                child: _buildNavItem(
                  iconPath: 'assets/icons/student.png',
                  fallbackIcon: Icons.school_outlined,
                  label: "Student",
                  index: 2,
                  iconSize: 19.5,
                ),
              ),
              Expanded(
                child: _buildNavItem(
                  iconPath: 'assets/icons/rajsims.png',
                  fallbackIcon: Icons.business_rounded,
                  label: "Rajsims",
                  index: 3,
                  iconSize: 21.0,
                ),
              ),
              Expanded(
                child: _buildNavItem(
                  iconPath: 'assets/icons/user.png',
                  fallbackIcon: Icons.person_rounded,
                  label: "Account",
                  index: 4,
                  iconSize: 20.0,
                  isAccount: true,
                ),
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
    required double iconSize,
    bool isAccount = false,
  }) {
    final bool isSelected = _currentNavIndex == index;
    const Color activeColor = Color(0xFF0F172A);
    const Color inactiveColor = Color(0xFF64748B);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          FocusManager.instance.primaryFocus?.unfocus();
          _onNavTabTapped(index);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 3.5),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFF1F5F9) : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: 20,
                child: Center(
                  child: isAccount
                      ? Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? activeColor : inactiveColor,
                              width: isSelected ? 1.5 : 1.1,
                            ),
                          ),
                          child: ClipOval(
                            child: Image.asset(
                              'assets/icons/user.png',
                              width: 20,
                              height: 20,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  Icon(Icons.person_rounded, size: 13, color: isSelected ? activeColor : inactiveColor),
                            ),
                          ),
                        )
                      : Image.asset(
                          iconPath,
                          width: iconSize,
                          height: iconSize,
                          color: isSelected ? activeColor : inactiveColor,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              Icon(fallbackIcon, size: iconSize, color: isSelected ? activeColor : inactiveColor),
                        ),
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
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? activeColor : inactiveColor,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 2.0),
              Container(
                height: 2.0,
                width: isSelected ? 12.0 : 0.0,
                decoration: BoxDecoration(
                  color: isSelected ? activeColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
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
              decoration: BoxDecoration(color: const Color(0xFFCBD5E1), borderRadius: BorderRadius.circular(2)),
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
              style: TextStyle(fontFamily: kAppFont, fontSize: 12.0, color: Color(0xFF64748B)),
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
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, sweepAngle, false, progressPaint);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) => oldDelegate.percentage != percentage;
}

// Each placeholder animates only while its value is unknown.
class _DashboardSkeleton extends StatefulWidget {
  final double width, height;
  const _DashboardSkeleton({required this.width, required this.height});
  @override
  State<_DashboardSkeleton> createState() => _DashboardSkeletonState();
}
class _DashboardSkeletonState extends State<_DashboardSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) { _pulse.stop(); _pulse.value = 0.5; }
    else { _pulse.repeat(reverse: true); }
  }
  @override
  void dispose() { _pulse.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: _pulse, builder: (_, __) =>
    Opacity(opacity: 0.35 + _pulse.value * 0.4, child: Container(width: widget.width, height: widget.height,
      decoration: BoxDecoration(color: const Color(0xFF94A3B8), borderRadius: BorderRadius.circular(5)))));
}

class _DashboardTask {
  final String title, iconPath;
  final bool? done;
  final VoidCallback onTap;
  final bool unavailable;
  const _DashboardTask(this.title, this.iconPath, this.done, this.onTap, {this.unavailable = false});
}
