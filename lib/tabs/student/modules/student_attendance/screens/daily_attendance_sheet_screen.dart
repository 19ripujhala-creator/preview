import 'package:shaladarpan/widgets/adaptive_layout.dart';
// lib/tabs/student/modules/student_attendance/screens/daily_attendance_sheet_screen.dart
//
// Needs Flutter 3.22+ (PopScope.onPopInvokedWithResult).
// NOTE: progress ring ab CustomPainter se bana hai, isliye
// CircularProgressIndicator.strokeCap (Flutter 3.27+) ki zaroorat nahi.

import 'dart:async';

import 'package:shaladarpan/services/core/direct/portal_diagnostics.dart';
import 'package:shaladarpan/services/core/direct/latest_read_queue.dart';
import 'package:shaladarpan/services/core/direct/attendance_read_scope.dart';

import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shaladarpan/services/portals/shaladarpan/student_service.dart';
import 'package:shaladarpan/services/portals/shaladarpan/direct/leave_result_messages.dart';

import '../widgets/custom_calendar_dialog.dart';

const String kAppFont = 'PlusJakartaSans';

/// Hero card theme: true = black card, false = white card.
const bool kDarkHero = false;

/// Submit button icon (pubspec me `assets/icons/` declared hona chahiye).
const String kSubmitIcon = 'assets/icons/student_Attendance.png';

/// true  = icon ko white tint karo (dark button par hamesha dikhega)
/// false = icon apne original colours me dikhega
const bool kSubmitIconTint = true;

// ==========================================
// DESIGN TOKENS
// ==========================================
class _C {
  static const ink = Color(0xFF0F172A);
  static const inkDeep = Color(0xFF0A0C10);
  static const slate = Color(0xFF475569);
  static const muted = Color(0xFF94A3B8);
  static const line = Color(0xFFE2E8F0);
  static const chip = Color(0xFFF1F5F9);
  static const fillLight = Color(0xFFF8FAFC);
  static const pinnedBg = Color(0xFFF3F5F8);

  static const green = Color(0xFF10B981);
  static const greenBg = Color(0xFFECFDF5);
  static const rose = Color(0xFFEF4444);
  static const roseBg = Color(0xFFFEF2F2);
  static const roseDeep = Color(0xFFDC2626);
  static const amber = Color(0xFFF59E0B);
  static const amberBg = Color(0xFFFFFBEB);
  static const medicalGrey = Color(0xFF64748B);
  static const medicalBg = Color(0xFFF1F5F9);

  static const boy = Color(0xFF3B82F6);
  static const girl = Color(0xFFEC4899);
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _fmtPortal(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

String _fmtDisplayDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')} ${_months[d.month - 1]} ${d.year}';

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _secLetter(String label) {
  final t = label.trim().toUpperCase();
  final stripped = t.replaceFirst(RegExp(r'^\d+\s*[-_ ]?\s*'), '');
  return stripped.isEmpty ? t : stripped;
}

String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

// ==========================================
// 1. DATA MODEL
// ==========================================
class StudentRecord {
  final String serialNo;
  final String srNo;
  final String name;
  final String className;
  final String section;
  final String gender; // 'B' = boy, 'G' = girl, '' = unknown
  String attendanceStatus;
  String originalStatus;

  StudentRecord({
    required this.serialNo,
    required this.srNo,
    required this.name,
    required this.className,
    required this.section,
    this.gender = '',
    this.attendanceStatus = '?',
  }) : originalStatus = attendanceStatus;

  bool get isChanged => attendanceStatus != originalStatus;

  static String _code(Map<String, dynamic> j) {
    final st = (j['status'] ?? '').toString().toLowerCase().replaceAll(' ', '');
    switch (st) {
      case 'p': case 'present': return 'P';
      case 'a': case 'absent': return 'A';
      case 'l': case 'leave': case 'onleave': return 'L';
      case 'm': case 'ml': case 'medical': case 'onmedical': return 'M';
    }
    if (st.isEmpty && j['present'] is bool) return j['present'] == true ? 'P' : 'A';
    return '?';
  }

  /// Portal/backend ke alag-alag gender formats ko 'B' / 'G' me badalta hai.
  static String _genderCode(dynamic v) {
    final g = (v ?? '').toString().toLowerCase().replaceAll(' ', '');
    if (g.isEmpty) return '';
    if (g == 'm' ||
        g == 'b' ||
        g.startsWith('male') ||
        g.startsWith('boy') ||
        g.contains('लड़का') ||
        g.contains('बालक') ||
        g.contains('पुरुष')) {
      return 'B';
    }
    if (g == 'f' ||
        g == 'g' ||
        g.startsWith('female') ||
        g.startsWith('girl') ||
        g.contains('लड़की') ||
        g.contains('बालिका') ||
        g.contains('महिला')) {
      return 'G';
    }
    return '';
  }

  factory StudentRecord.fromJson(
    Map<String, dynamic> j,
    String className,
    String section,
    int fallbackSerial,
  ) {
    String s(dynamic v) => (v ?? '').toString().trim();

    return StudentRecord(
      serialNo: s(j['serialNo']).isNotEmpty
          ? s(j['serialNo'])
          : '$fallbackSerial',
      srNo: s(j['srNo']).isEmpty ? '-' : s(j['srNo']),
      name: s(j['name']).isEmpty ? 'Student' : s(j['name']),
      className: className,
      section: section,
      gender: _genderCode(j['gender'] ?? j['sex']),
      attendanceStatus: _code(j),
    );
  }

  Map<String, dynamic> toJson() {
    const map = {
      'P': 'Present',
      'A': 'Absent',
      'L': 'OnLeave',
      'M': 'OnMedical',
    };

    return {
      'srNo': srNo,
      'serialNo': serialNo,
      'name': name,
      'section': section,
      'status': map[attendanceStatus],
      'present': map.containsKey(attendanceStatus) ? attendanceStatus == 'P' : null,
    };
  }
}

/// Ek class+section+date ka poora cached snapshot
/// (pehle sirf students cache hote the -> sections/letter kho jaate the).
class _Entry {
  final List<StudentRecord> students;
  final String letter;
  final List<String> sections;
  bool marked;
  bool verified;
  bool dataVerified;
  bool held;

  _Entry({
    required this.students,
    required this.letter,
    required this.sections,
    required this.marked,
    required this.verified,
    required this.dataVerified,
    required this.held,
  });
}

// ==========================================
// 2. SCREEN
// ==========================================
class DailyAttendanceSheetScreen extends StatefulWidget {
  const DailyAttendanceSheetScreen({super.key, this.clock});
  final DateTime Function()? clock;

  @override
  State<DailyAttendanceSheetScreen> createState() =>
      _DailyAttendanceSheetScreenState();
}

class _DailyAttendanceSheetScreenState
    extends State<DailyAttendanceSheetScreen> with WidgetsBindingObserver {
  String _activeClass = 'Class 1';
  String _activeSection = '';

  List<String> _classes = [
    'Class 1',
    'Class 2',
    'Class 3',
    'Class 4',
    'Class 5',
  ];

  List<String> _sections = [];

  final _cache = AttendanceReadCache<_Entry>();
  AttendanceReadScope? _loadedScope;

  int _currentLoadId = 0;
  final _classReads = LatestReadQueue();
  bool _isAutoRetrying = false;

  final ScrollController _classScroll = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();

  List<StudentRecord> _students = [];

  // FIX: initial true, warna pehle frame me "No students found" flash hota tha
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isConfirming = false;
  bool _isAlreadyMarked = false;
  bool _isPortalVerified = false;
  bool _portalDataVerified = false;
  bool _submissionHold = false;

  String _errorMessage = '';

  late DateTime _selectedDate;
  late DateTime _observedDay;
  AttendanceReadScope? _observedScope;
  Timer? _boundaryTimer;
  bool _checkingBoundary = false;
  Route<dynamic>? _confirmationRoute;
  DateTime get _indiaToday {
    final now = (widget.clock?.call() ?? DateTime.now()).toUtc().add(const Duration(hours: 5, minutes: 30));
    return DateTime(now.year, now.month, now.day);
  }
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selectedDate = _observedDay = _indiaToday;
    WidgetsBinding.instance.addObserver(this);
    _boundaryTimer = Timer.periodic(const Duration(seconds: 15), (_) => _checkBoundary());
    _init();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_checkBoundary());
  }

  void _closeConfirmation() {
    final route = _confirmationRoute;
    _confirmationRoute = null;
    final navigator = route?.navigator;
    if (route != null && route.isActive && navigator != null && navigator.mounted) navigator.removeRoute(route);
  }

  Future<void> _checkBoundary() async {
    if (!mounted || _isSaving || _checkingBoundary) return;
    _checkingBoundary = true;
    try {
      final today = _indiaToday, previousDay = _observedDay;
      final scope = await StudentService.captureReadScope();
      if (!mounted || _isSaving) return;
      final changedDay = !_sameDay(today, previousDay);
      final changedSession = _observedScope != null && scope != _observedScope;
      _observedDay = today;
      if (!changedDay && !changedSession) return;
      final followToday = changedDay && _sameDay(_selectedDate, previousDay);
      if (!followToday && !changedSession) return;
      _observedScope = scope;
      _cache.clear();
      _closeConfirmation();
      if (followToday) _selectedDate = today;
      if (changedSession) {
        _activeSection = '';
        _sections = [];
        _query = '';
        _searchCtrl.clear();
      }
      if (scope == null) {
        _currentLoadId++;
        _classReads.discardPending();
        setState(() {
          _students = [];
          _portalDataVerified = _isPortalVerified = _isAlreadyMarked = false;
          _loadedScope = null;
          _isLoading = false;
          _errorMessage = 'App: School session changed. Refresh the school login.';
        });
        return;
      }
      await _loadClassData(forceRefresh: true);
    } finally { _checkingBoundary = false; }
  }

  Future<void> _init() async {
    await _loadCachedPortalClasses();
    if (mounted) _loadClassData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _boundaryTimer?.cancel();
    final route = _confirmationRoute;
    if (route != null) WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = route.navigator;
      if (route.isActive && navigator != null && navigator.mounted) navigator.removeRoute(route);
    });
    _currentLoadId++; // Discard stale UI completions.
    _classReads.discardPending();
    _classScroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _haptic() => HapticFeedback.selectionClick();

  Future<void> _loadCachedPortalClasses() async {
    try {
      final scope = await StudentService.captureReadScope();
      if (scope == null) return;
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getStringList(
        'portal_available_classes/${scope.school}',
      );
      if (await StudentService.captureReadScope() != scope) return;

      if (cached != null && cached.isNotEmpty && mounted) {
        _classes = cached;
        if (!_classes.contains(_activeClass)) {
          _activeClass = _classes.first;
        }
      }
    } catch (_) {}
  }

  // ==========================================
  // STRICT PORTAL VERIFICATION
  // ==========================================
  bool _parsePortalVerification(Map<String, dynamic> result) {
    // Generic data_verified ONLY confirms scraping, not submission.
    // Never infer "marked" from loosely related summary fields.
    return result['is_already_marked'] == true &&
        result['attendance_verified'] == true &&
        (result['attendance_status'] ?? '').toString().trim().toLowerCase() ==
            'marked';
  }

  // ==========================================
  // DERIVED METRICS
  // ==========================================
  int _count(String c) =>
      _students.where((s) => s.attendanceStatus == c).length;

  int get _present => _count('P');
  int get _absent => _count('A');
  int get _leave => _count('L');
  int get _medical => _count('M');
  int get _pending => _students.where((s) => !{'P', 'A', 'L', 'M'}.contains(s.attendanceStatus)).length;
  int get _changes => _students.where((s) => s.isChanged).length;
  bool get _dirty => _changes > 0;

  // Boys / Girls breakdown (sirf tab jab portal se gender data mile)
  bool get _hasGender => _students.any((s) => s.gender.isNotEmpty);
  int _gTotal(String g) => _students.where((s) => s.gender == g).length;
  int _gCount(String g, String st) =>
      _students.where((s) => s.gender == g && s.attendanceStatus == st).length;

  List<StudentRecord> get _visible {
    if (_query.isEmpty) return _students;

    final q = _query.toLowerCase();

    return _students
        .where(
          (s) =>
              s.name.toLowerCase().contains(q) ||
              s.srNo.toLowerCase().contains(q) ||
              s.serialNo == q,
        )
        .toList();
  }

  String get _classTitle {
    final n = _digits(_activeClass);
    final base = n.isNotEmpty ? 'Class $n' : _activeClass;
    return _activeSection.isNotEmpty ? '$base $_activeSection' : base;
  }

  String get _classNum =>
      _digits(_activeClass).isNotEmpty ? _digits(_activeClass) : '1';

  String get _portalSectionLabel =>
      _activeSection.isNotEmpty ? '$_classNum$_activeSection' : '';

  String _cacheKey(String cls, String sec) =>
      '${cls}_${sec}_${_fmtPortal(_selectedDate)}';

  // ==========================================
  // LOAD DATA WITH RESILIENT SESSION RETRY
  // ==========================================
  void _applyEntry(_Entry e) {
    _students = e.students;
    _activeSection = e.letter;
    _sections = e.sections;
    _isAlreadyMarked = e.marked;
    _isPortalVerified = e.verified;
    _portalDataVerified = e.dataVerified;
    _submissionHold = e.held;
    _isLoading = false;
    _errorMessage = '';
    _isAutoRetrying = false;
  }

  Future<void> _loadClassData({
    bool forceRefresh = false,
    int retryAttempt = 0,
  }) {
    final loadId = ++_currentLoadId;
    // Switching classes must not queue every intermediate selection behind
    // the shared WebForms resource. Clear old editable data immediately.
    setState(() {
      _isLoading = true;
      _portalDataVerified = false;
      _isPortalVerified = false;
      _students = [];
      _loadedScope = null;
    });
    return _classReads.request(() async {
      if (!mounted || loadId != _currentLoadId) return;
      await _performClassLoad(
        loadId,
        forceRefresh: forceRefresh,
        retryAttempt: retryAttempt,
      );
    });
  }

  Future<void> _performClassLoad(
    int loadId, {
    bool forceRefresh = false,
    int retryAttempt = 0,
  }) async {
    final scope = await StudentService.captureReadScope();
    if (!mounted || loadId != _currentLoadId) return;
    if (scope != null) _observedScope = scope;
    final key = _cacheKey(_activeClass, _activeSection);

    // 1. Instant cache render
    // FIX: ab section + sections list bhi restore hoti hai
    // (pehle cache hit par section '' reh jaata tha -> galat section submit ho sakta tha)
    if (!forceRefresh && scope != null) {
      final hit = _cache.read(scope, key);
      if (hit != null) {
        _loadedScope = scope;
        setState(() => _applyEntry(hit));
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _isPortalVerified = false;
      _isAlreadyMarked = false;
      _portalDataVerified = false;
      _submissionHold = false;
      _isAutoRetrying = retryAttempt > 0;
      // FIX: loading ke dauran purani class ke students dikhte the aur
      // Submit dabane par nayi class ke naam se save ho jaate the.
      _students = [];
    });

    final classId = _portalSectionLabel.isNotEmpty
        ? _portalSectionLabel
        : _classNum;

    try {
      final result = await StudentService.fetchAttendance(
        classId: classId,
        date: _fmtPortal(_selectedDate),
      );

      final completedScope = await StudentService.captureReadScope();
      if (!mounted || loadId != _currentLoadId) return;
      if (result['success'] == true &&
          (completedScope == null ||
              (scope != null && scope != completedScope))) {
        _cache.clear();
        await _retryOrFail(
          loadId,
          retryAttempt,
          'School session changed. Refresh class data.',
        );
        return;
      }

      if (completedScope != null &&
          result['success'] == true &&
          result['data_verified'] == true &&
          result['students'] is List &&
          ((result['students'] as List).isNotEmpty ||
              StudentService.isVerifiedEmptyClass(result))) {
        final portalVerified = _parsePortalVerification(result);
        final portalSection = (result['section'] ?? '').toString().trim();
        final letter = portalSection.isNotEmpty
            ? _secLetter(portalSection)
            : _activeSection;

        final rawList = result['students'] as List<dynamic>? ?? [];
        var i = 0;

        final loaded = rawList
            .map(
              (e) => StudentRecord.fromJson(
                Map<String, dynamic>.from(e as Map),
                _activeClass,
                letter,
                ++i,
              ),
            )
            .toList();

        final dynClasses = result['classes'];
        if (dynClasses is List && dynClasses.isNotEmpty) {
          final parsed = dynClasses
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList();

          if (parsed.contains(_activeClass)) {
            _classes = parsed;
            SharedPreferences.getInstance()
                .then(
                  (p) => p.setStringList(
                    'portal_available_classes/${completedScope.school}',
                    parsed,
                  ),
                )
                .catchError((_) => false);
          }
        }

        final found = <String>{};
        final dynSections = result['sections'];
        if (dynSections is List) {
          for (final e in dynSections) {
            final l = _secLetter(e.toString());
            if (l.isNotEmpty) found.add(l);
          }
        }

        if (found.isEmpty) found.addAll(_sections);
        if (letter.isNotEmpty) found.add(letter);

        final marked = portalVerified;

        final entry = _Entry(
          students: loaded,
          letter: letter,
          sections: found.toList()..sort(),
          marked: marked,
          verified: portalVerified,
          dataVerified: true,
          held: result['submission_on_hold'] == true,
        );

        _cache.write(completedScope, _cacheKey(_activeClass, letter), entry);
        _cache.write(completedScope, key, entry);
        _loadedScope = completedScope;

        setState(() => _applyEntry(entry));
      } else {
        await _retryOrFail(
          loadId,
          retryAttempt,
          result['message']?.toString() ??
              'Portal session is busy syncing. Please retry.',
        );
      }
    } catch (_) {
      await _retryOrFail(
        loadId,
        retryAttempt,
        'Portal sync busy. Tap Try again.',
      );
    }
  }

  Future<void> _retryOrFail(int loadId, int attempt, String message) async {
    if (!mounted || loadId != _currentLoadId) return;

    // Coordinator owns retry/recovery. Do not repeat its entire request chain
    // for every failure (including deterministic portal errors and validation).
    // FIX: pehle yahan mounted/loadId check nahi tha -> stale setState
    setState(() {
      _students = [];
      _errorMessage = message;
      _isLoading = false;
      _isAutoRetrying = false;
    });
  }

  // ==========================================
  // EDITS / GUARDS
  // ==========================================
  void _revertAll() {
    for (final s in _students) {
      s.attendanceStatus = s.originalStatus;
    }
  }

  Future<void> _guardedChange(VoidCallback action) async {
    if (_isSaving || _isConfirming) return;
    if (_dirty) {
      final ok = await _confirmDiscard();
      if (ok != true || !mounted || _isSaving || _isConfirming) return;
      _revertAll();
    }
    if (!mounted || _isSaving || _isConfirming) return;
    action();
  }

  Future<bool?> _showConfirmDialog({
    required IconData icon,
    required String title,
    required String message,
    required String cancelLabel,
    required String confirmLabel,
    bool barrierDismissible = false,
  }) {
    Widget btn(
      String label,
      Color bg,
      Color fg,
      FontWeight w,
      bool result,
      BuildContext ctx,
    ) {
      return Expanded(
        child: GestureDetector(
          onTap: () => Navigator.pop(ctx, result),
          child: Container(
            height: 38,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: kAppFont,
                fontSize: 12.5,
                fontWeight: w,
                color: fg,
              ),
            ),
          ),
        ),
      );
    }

    return showDialog<bool>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 26),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                  color: Color(0xFFFEE2E2),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: _C.roseDeep, size: 22),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: const TextStyle(
                  fontFamily: kAppFont,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _C.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: kAppFont,
                  fontSize: 12,
                  color: _C.slate,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  btn(
                    cancelLabel,
                    _C.chip,
                    _C.slate,
                    FontWeight.w600,
                    false,
                    ctx,
                  ),
                  const SizedBox(width: 10),
                  btn(
                    confirmLabel,
                    _C.roseDeep,
                    Colors.white,
                    FontWeight.w700,
                    true,
                    ctx,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool?> _confirmDiscard() {
    return _showConfirmDialog(
      icon: CupertinoIcons.exclamationmark_triangle_fill,
      title: 'Discard Changes?',
      message:
          'You have $_changes unsaved edit(s). Discarding will revert all modified student attendance records.',
      cancelLabel: 'Keep Editing',
      confirmLabel: 'Discard',
    );
  }

  void _setStatus(StudentRecord s, String code) {
    if (_isSaving ||
        _isConfirming ||
        _isLoading ||
        _submissionHold ||
        s.attendanceStatus == code)
      return;
    _haptic();
    setState(() {
      s.attendanceStatus = code;
    });
  }

  Future<void> _markAll(String code) async {
    if (_students.isEmpty ||
        _isSaving ||
        _isConfirming ||
        _isLoading ||
        _submissionHold)
      return;
    HapticFeedback.mediumImpact();

    if (code == 'A') {
      final ok = await _showConfirmDialog(
        icon: CupertinoIcons.xmark_circle_fill,
        title: 'Mark Everyone Absent?',
        message: 'This will set attendance status of all students to Absent.',
        cancelLabel: 'Cancel',
        confirmLabel: 'Mark Absent',
        barrierDismissible: true,
      );
      if (ok != true ||
          !mounted ||
          _isSaving ||
          _isConfirming ||
          _submissionHold)
        return;
    }

    setState(() {
      for (final s in _students) {
        s.attendanceStatus = code;
      }
    });
  }

  void _resetChanges() {
    if (_isSaving || _isConfirming || _submissionHold) return;
    HapticFeedback.selectionClick();
    setState(_revertAll);
  }

  Future<void> _pickDate() async {
    if (_isSaving || _isConfirming) return;
    _haptic();

    final picked = await showCustomCalendarDialog(
      context: context,
      initialDate: _selectedDate,
    );

    if (!mounted) return;

    if (picked != null && !_sameDay(picked, _selectedDate)) {
      _guardedChange(() {
        setState(() {
          _selectedDate = picked;
          _activeSection = '';
          _sections = [];
          _isPortalVerified = false;
          _query = '';
          _searchCtrl.clear();
        });

        _cache.clear();
        _loadClassData();
      });
    }
  }

  Future<void> _checkPreviousSave() async {
    if (_isSaving || _isConfirming || _isLoading || _students.isEmpty) return;

    setState(() => _isConfirming = true);
    bool? proceed;
    try {
      proceed = await _showConfirmDialog(
        icon: CupertinoIcons.exclamationmark_triangle_fill,
        title: 'Check Previous Save?',
        message: 'The previous submission result is uncertain. Two fresh portal checks will be performed. No attendance will be submitted.',
        cancelLabel: 'Cancel',
        confirmLabel: 'Verify Portal',
      );
    } finally {
      if (mounted) setState(() => _isConfirming = false);
    }
    if (proceed != true || !mounted || _isSaving || _isConfirming) return;
    final cls = _portalSectionLabel.isNotEmpty
        ? _portalSectionLabel
        : _classNum;
    final date = _fmtPortal(_selectedDate);
    setState(() => _isSaving = true);
    try {
      final outcome = await StudentService.checkPreviousSubmission(
        classId: cls,
        date: date,
        section: _portalSectionLabel.isNotEmpty ? _portalSectionLabel : null,
      );
      if (!mounted) return;
      if (outcome['success'] == true) {
        _cache.clear();
        // Force a new authoritative snapshot; never silently re-submit.
        await _loadClassData(forceRefresh: true);
        if (!mounted) return;
        _snack(
          outcome['message']?.toString() ?? 'Portal status refreshed.',
          success: true,
        );
      } else {
        if (outcome['code'] == 'REVIEW_REQUIRED' &&
            outcome['manual_retry_allowed'] == true) {
          // Never silently retry a POST. This is an explicit second decision.
          final approved = await _showConfirmDialog(
            icon: CupertinoIcons.exclamationmark_triangle_fill,
            title: 'Release Previous Hold?',
            message: 'Two verified portal reads differ from the previous Save. The earlier outcome is not confirmed. Release its safety hold only after manually reviewing portal statuses. This does NOT send attendance.',
            cancelLabel: 'Keep Hold',
            confirmLabel: 'I Reviewed',
          );
          if (approved == true && mounted) {
            final review = await StudentService.checkPreviousSubmission(
              classId: cls,
              date: date,
              section: _portalSectionLabel.isNotEmpty
                  ? _portalSectionLabel
                  : null,
              acknowledgeManualRetry: true,
            );
            if (!mounted) return;
            if (review['success'] == true) {
              _cache.clear();
              await _loadClassData(forceRefresh: true);
              if (!mounted) return;
              _snack(
                review['message']?.toString() ?? 'Portal status refreshed.',
                success: true,
              );
              return;
            }
            _snack(
              review['message']?.toString() ??
                  'Previous submission remains on hold.',
              error: true,
            );
          }
        } else {
          _snack(
            outcome['message']?.toString() ??
                'Previous submission is still unresolved. Do not submit again.',
            error: true,
          );
        }
      }
    } catch (_) {
      if (mounted) {
        _snack(
          'Verification failed. Previous submission is still on hold.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _onSubmitTap() async {
    if (_isSaving || _isLoading || _isConfirming) return;
    if (_submissionHold) {
      await _checkPreviousSave();
      return;
    }
    if (_students.isEmpty) {
      _snack('No student records to submit.', error: true);
      return;
    }
    if (_pending > 0) {
      _snack('App: Select attendance for all $_pending pending student(s) before review.', error: true);
      return;
    }
    // Portal supports genuine same-day updates. No-change updates waste a POST.
    if ((_isAlreadyMarked || _isPortalVerified) && !_dirty) {
      _snack('No changes to update.');
      return;
    }
    if (!_portalDataVerified) {
      _snack('Refresh and verify class data before submitting.', error: true);
      return;
    }

    final scope = await StudentService.captureReadScope();
    if (!mounted || _isSaving || _isLoading || _isConfirming) return;
    if (scope == null || scope != _loadedScope) {
      _cache.clear();
      await _loadClassData(forceRefresh: true);
      return;
    }
    final confirmingLoadId = _currentLoadId;
    HapticFeedback.mediumImpact();
    setState(() => _isConfirming = true);
    bool? confirmed;
    try {
      confirmed = await showModalBottomSheet<bool>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (sheetContext) {
          _confirmationRoute = ModalRoute.of(sheetContext);
          return _ConfirmSheet(
          className: _classTitle,
          date: _fmtDisplayDate(_selectedDate),
          present: _present,
          absent: _absent,
          leave: _leave,
          medical: _medical,
        );
        },
      );
    } finally {
      _confirmationRoute = null;
      if (mounted) setState(() => _isConfirming = false);
    }
    if (confirmed != true ||
        !mounted ||
        confirmingLoadId != _currentLoadId ||
        _isSaving ||
        _isLoading ||
        _submissionHold ||
        !_portalDataVerified)
      return;

    if (await StudentService.captureReadScope() != scope) {
      if (!mounted) return;
      _cache.clear();
      await _loadClassData(forceRefresh: true);
      return;
    }
    if (!mounted ||
        _isSaving ||
        _isLoading ||
        confirmingLoadId != _currentLoadId ||
        _submissionHold ||
        !_portalDataVerified)
      return;
    setState(() => _isSaving = true);
    final payload = {
      'class_id': _portalSectionLabel.isNotEmpty
          ? _portalSectionLabel
          : _classNum,
      'class': _classNum,
      'class_num': _classNum,
      'className': _activeClass,
      'class_name': _activeClass,
      'section': _portalSectionLabel,
      'section_name': _activeSection,
      'date': _fmtPortal(_selectedDate),
      'attendance_date': _fmtPortal(_selectedDate),
      'students': _students.map((s) => s.toJson()).toList(),
    };

    try {
      final result = await StudentService.saveAttendance(
        payload,
        expectedScope: scope,
      );
      final savedScope = await StudentService.captureReadScope();
      if (!mounted) return;
      _cache.clear();
      _loadedScope = savedScope;
      _observedScope = savedScope;
      if (savedScope == null ||
          savedScope.school != scope.school ||
          !identical(savedScope.session, scope.session) ||
          savedScope.identity != scope.identity) {
        await _loadClassData(forceRefresh: true);
        return;
      }

      if (result['success'] == true && _parsePortalVerification(result)) {
        HapticFeedback.heavyImpact();
        setState(() {
          _isAlreadyMarked = true;
          _isPortalVerified = true;
          _submissionHold = result['submission_on_hold'] == true;
          for (final s in _students) {
            s.originalStatus = s.attendanceStatus;
          }
        });
        _snack(
          LeaveResultMessages.display(result, fallback: 'Attendance saved and verified on the portal.'),
          success: true,
        );
      } else {
        final attempted = result['submission_attempted'] != false;
        final code = '${result['code'] ?? ''}';
        final ambiguous =
            attempted ||
            code == 'SAVE_UNCONFIRMED' ||
            code == 'MUTATION_AMBIGUOUS';
        if (ambiguous) {
          // Do not make another POST until a user-initiated independent check.
          _cache.clear();
          setState(() => _submissionHold = true);
        }
        if (code == 'ALREADY_MARKED') {
          _cache.clear();
          // The portal is authoritative: fetch its actual recorded statuses.
          await _loadClassData(forceRefresh: true);
        }
        if (!mounted) return;
        _snack(
          LeaveResultMessages.display(result, fallback: ambiguous
            ? 'Save outcome is uncertain. Use Verify Previous Save before trying again.' : 'Submission failed.'),
          error: true,
        );
      }
    } catch (_) {
      if (!mounted) return;
      _cache.clear();
      setState(() => _submissionHold = true);
      _snack(
        'Submission outcome unknown. Verify the portal before retrying.',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _snack(String msg, {bool error = false, bool success = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: error ? _C.rose : _C.ink,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          content: Row(
            children: [
              if (success)
                const Padding(
                  padding: EdgeInsets.only(right: 10),
                  child: Icon(
                    CupertinoIcons.checkmark_alt_circle_fill,
                    color: _C.green,
                    size: 18,
                  ),
                ),
              Expanded(
                child: Text(
                  msg,
                  style: const TextStyle(
                    fontFamily: kAppFont,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final list = _visible;

    return PopScope(
      canPop: !_dirty && !_isSaving && !_isConfirming,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _isSaving || _isConfirming) return;
        final discard = await _confirmDiscard();
        if (discard == true && context.mounted) {
          _revertAll(); // cache me edited state na bache
          Navigator.pop(context);
        }
      },
      child: Stack(
        children: [
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
            child: IgnorePointer(
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
          ),
          Positioned(
            right: -50,
            top: 40,
            child: IgnorePointer(
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
          ),
          Scaffold(
            backgroundColor: Colors.transparent,
            appBar: _buildAppBar(),
            body: LayoutBuilder(
              builder: (context, box) {
                return Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: AppAdaptive.contentWidth(box.maxWidth),
                    height: box.maxHeight,
                    child: Column(
                      children: [
                        Expanded(
                          child: RefreshIndicator(
                            color: _C.ink,
                            onRefresh: () async {
                              if (_isSaving || _isConfirming) return;
                              if (_dirty) {
                                final ok = await _confirmDiscard();
                                if (ok != true) return;
                                _revertAll();
                              }
                              await _loadClassData(forceRefresh: true);
                            },
                            child: CustomScrollView(
                              physics: const AlwaysScrollableScrollPhysics(
                                parent: ClampingScrollPhysics(),
                              ),
                              slivers: [
                                SliverToBoxAdapter(
                                  child: _buildDailyAttendanceHeader(),
                                ),
                                SliverToBoxAdapter(
                                  child: _buildClassAndSectionSelectors(),
                                ),
                                SliverToBoxAdapter(child: _buildHeroCard()),
                                if (_pending > 0 && !_isLoading) SliverToBoxAdapter(child: Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                  child: Text('Selection pending: $_pending', style: const TextStyle(
                                    fontFamily: kAppFont, fontSize: 12, color: _C.slate)),
                                )),
                                if (_hasGender && !_isLoading)
                                  SliverToBoxAdapter(
                                    child: _buildGenderStrip(),
                                  ),
                                SliverPersistentHeader(
                                  pinned: true,
                                  delegate: _PinnedHeaderDelegate(
                                    // FIX: 80 tight tha (overflow risk) + ab solid bg hai
                                    height: 88 * MediaQuery.textScalerOf(context).scale(1),
                                    child: _buildSearchAndTableHeaders(),
                                  ),
                                ),
                                ..._buildListSlivers(list),
                              ],
                            ),
                          ),
                        ),
                        _buildSubmitButton(),
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
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      leading: IconButton(
        icon: const Icon(CupertinoIcons.back, color: _C.ink, size: 21),
        onPressed: () => Navigator.maybePop(context),
      ),
      centerTitle: true,
      title: const Text(
        'Attendance Register',
        style: TextStyle(
          fontFamily: kAppFont,
          color: _C.ink,
          fontSize: 15.5,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      actions: [
        PopupMenuButton<String>(
          enabled: true,
          icon: const Icon(
            CupertinoIcons.ellipsis_circle,
            color: _C.ink,
            size: 20,
          ),
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          onSelected: (v) async {
            if (v == 'D') {
              await Clipboard.setData(
                ClipboardData(text: PortalDiagnostics.export()),
              );
              if (mounted) _snack('Technical timings copied.');
              return;
            }
            if (_isLoading ||
                _isSaving ||
                _isConfirming ||
                _submissionHold ||
                _students.isEmpty)
              return;
            if (v == 'P') _markAll('P');
            if (v == 'A') _markAll('A');
            if (v == 'R') _resetChanges();
          },
          itemBuilder: (_) => [
            _menuItem(
              'D',
              CupertinoIcons.doc_on_clipboard,
              'Copy technical timings',
              _C.slate,
            ),
            if (!_isLoading &&
                !_isSaving &&
                !_isConfirming &&
                !_submissionHold &&
                _students.isNotEmpty) ...[
              _menuItem(
                'P',
                CupertinoIcons.checkmark_circle,
                'Mark all present',
                _C.green,
              ),
              _menuItem(
                'A',
                CupertinoIcons.xmark_circle,
                'Mark all absent',
                _C.rose,
              ),
              if (_dirty)
                _menuItem(
                  'R',
                  CupertinoIcons.arrow_counterclockwise,
                  'Undo changes',
                  _C.slate,
                ),
            ],
          ],
        ),
        const SizedBox(width: 4),
      ],
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(height: 1, thickness: 0.8, color: _C.line),
      ),
    );
  }

  PopupMenuItem<String> _menuItem(
    String v,
    IconData icon,
    String label,
    Color color,
  ) {
    return PopupMenuItem<String>(
      value: v,
      height: 40,
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(
              fontFamily: kAppFont,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: _C.ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyAttendanceHeader() {
    final isToday = _sameDay(_selectedDate, _indiaToday);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween, spacing: 12, runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/icons/calendar_attendance.png',
                width: 16,
                height: 16,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  CupertinoIcons.calendar_badge_plus,
                  size: 16,
                  color: _C.ink,
                ),
              ),
              const SizedBox(width: 8),
              const Flexible(child: Text(
                'Daily Attendance',
                style: TextStyle(
                  fontFamily: kAppFont,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _C.ink,
                  letterSpacing: -0.2,
                )),
              ),
            ],
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _pickDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.85),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _C.line),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 4,
                    offset: const Offset(0, 1.5),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isToday) ...[
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: _C.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                  ],
                  Text(
                    _fmtDisplayDate(_selectedDate),
                    style: const TextStyle(
                      fontFamily: kAppFont,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: _C.ink,
                      letterSpacing: -0.1,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Image.asset(
                    'assets/icons/leave.png',
                    width: 13,
                    height: 13,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      CupertinoIcons.calendar,
                      size: 13,
                      color: _C.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClassAndSectionSelectors() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 30,
            child: ListView.builder(
              controller: _classScroll,
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              itemCount: _classes.length,
              itemBuilder: (context, idx) {
                final selected = _activeClass == _classes[idx];

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (selected || _isSaving || _isConfirming) return;

                    _guardedChange(() {
                      _haptic();

                      setState(() {
                        _activeClass = _classes[idx];
                        _activeSection = '';
                        _sections = [];
                        _query = '';
                        _searchCtrl.clear();
                        _isPortalVerified = false;
                      });

                      _loadClassData();
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 13),
                    decoration: BoxDecoration(
                      color: selected ? _C.ink : Colors.white.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(
                        color: selected ? _C.ink : _C.line,
                        width: 0.9,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _classes[idx],
                      style: TextStyle(
                        fontFamily: kAppFont,
                        fontSize: 11,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w600,
                        color: selected ? Colors.white : _C.slate,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_sections.isNotEmpty) ...[
            const SizedBox(height: 7),
            // FIX: bahut sections hone par Row overflow karti thi -> scrollable
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              child: Row(
                children: [
                  const Text(
                    'Section: ',
                    style: TextStyle(
                      fontFamily: kAppFont,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _C.slate,
                    ),
                  ),
                  const SizedBox(width: 4),
                  ..._sections.map((sec) {
                    final sel = _activeSection == sec;

                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (sel || _isSaving || _isConfirming) return;

                        _guardedChange(() {
                          _haptic();

                          setState(() {
                            _activeSection = sec;
                            _query = '';
                            _searchCtrl.clear();
                            _isPortalVerified = false;
                          });

                          _loadClassData();
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3.5,
                        ),
                        decoration: BoxDecoration(
                          color: sel ? _C.ink : Colors.white.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: sel ? _C.ink : _C.line,
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          'Sec-$sec',
                          style: TextStyle(
                            fontFamily: kAppFont,
                            fontSize: 10.5,
                            fontWeight: sel ? FontWeight.w700 : FontWeight.w600,
                            color: sel ? Colors.white : _C.slate,
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ==========================================
  // GENDER BREAKDOWN (Boys / Girls)
  // ==========================================
  Widget _genderTile(String label, String code, Color color) {
    final total = _gTotal(code);
    final present = _gCount(code, 'P');
    final absent = _gCount(code, 'A');
    final leave = _gCount(code, 'L') + _gCount(code, 'M');

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _C.line, width: 0.9),
        ),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 28,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$label  \u2022  $total',
                    style: const TextStyle(
                      fontFamily: kAppFont,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _C.slate,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '$present / $total present',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: kAppFont,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: _C.ink,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
            ),
            if (absent > 0 || leave > 0)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (absent > 0)
                    Text(
                      'A $absent',
                      style: const TextStyle(
                        fontFamily: kAppFont,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: _C.rose,
                      ),
                    ),
                  if (leave > 0)
                    Text(
                      'L $leave',
                      style: const TextStyle(
                        fontFamily: kAppFont,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: _C.amber,
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGenderStrip() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          _genderTile('Boys', 'B', _C.boy),
          const SizedBox(width: 8),
          _genderTile('Girls', 'G', _C.girl),
        ],
      ),
    );
  }

  // ==========================================
  // HERO CARD
  // ==========================================
  Widget _statusBadge(bool verified) {
    final color = verified ? _C.green : _C.amber;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withOpacity(0.35), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            verified
                ? CupertinoIcons.checkmark_seal_fill
                : CupertinoIcons.clock_fill,
            color: color,
            size: verified ? 11 : 10,
          ),
          const SizedBox(width: 3.5),
          Text(
            verified ? 'Verified' : 'Pending',
            style: TextStyle(
              fontFamily: kAppFont,
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLargeTextCounters() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
    child: Container(padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: _C.line)),
      child: LayoutBuilder(builder: (context, box) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(_classTitle, style: const TextStyle(fontFamily: kAppFont, fontSize: 13.5, fontWeight: FontWeight.w700)),
          _statusBadge((_isPortalVerified || _isAlreadyMarked) && !_dirty),
          Text('${_students.length} students', style: const TextStyle(fontFamily: kAppFont, fontSize: 10.5)),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 10, children: [
          for (final item in [('Present', _present), ('Absent', _absent), ('Leave', _leave), ('Medical', _medical)])
            SizedBox(width: (box.maxWidth - 8) / 2, child: Text('${item.$1}: ${item.$2}',
              style: const TextStyle(fontFamily: kAppFont, fontSize: 11, fontWeight: FontWeight.w600))),
        ]),
      ])),
    ),
  );

  Widget _buildHeroCard() {
    if (MediaQuery.textScalerOf(context).scale(1) > 1.1) return _buildLargeTextCounters();
    const dark = kDarkHero;

    final total = _students.length;
    final ratio = total == 0 ? 0.0 : _present / total;
    final pct = total == 0 ? 0 : (_present * 100 / total).round();

    final fg = dark ? Colors.white : _C.ink;
    final sub = dark ? Colors.white.withOpacity(0.58) : _C.slate;
    final cardBg = dark ? _C.inkDeep : Colors.white;
    final border = dark ? const Color(0xFF262A34) : _C.line;
    final divColor = dark ? Colors.white.withOpacity(0.10) : _C.line;

    final bool showVerified =
        (_isPortalVerified || _isAlreadyMarked) && !_dirty;

    Widget stat(String label, int value, Color dot) {
      return Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$value',
              style: TextStyle(
                fontFamily: kAppFont,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: fg,
                height: 1,
              ),
            ),
            const SizedBox(height: 3),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: kAppFont,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w600,
                      color: sub,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    Widget divider() => Container(width: 1, height: 27, color: divColor);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: Container(
        height: 94,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border, width: 0.9),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(dark ? 0.18 : 0.035),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            // LEFT: Ring (CustomPainter -> koi Flutter version dependency nahi)
            SizedBox(
              width: 68,
              height: 68,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 62,
                    height: 62,
                    child: CustomPaint(
                      painter: _RingPainter(
                        ratio: ratio,
                        track: dark
                            ? Colors.white.withOpacity(0.10)
                            : const Color(0xFFE8EDF3),
                        color: _C.green,
                        stroke: 5.5,
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$pct%',
                        style: TextStyle(
                          fontFamily: kAppFont,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          height: 1,
                          color: fg,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Present',
                        style: TextStyle(
                          fontFamily: kAppFont,
                          fontSize: 7.5,
                          fontWeight: FontWeight.w600,
                          color: sub,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // FIX: lamba title overflow karta tha
                            Flexible(
                              child: Text(
                                _classTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: kAppFont,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.25,
                                  color: fg,
                                ),
                              ),
                            ),
                            const SizedBox(width: 7),
                            _statusBadge(showVerified),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$total students',
                        style: TextStyle(
                          fontFamily: kAppFont,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: sub,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      stat('Present', _present, _C.green),
                      divider(),
                      stat('Absent', _absent, _C.rose),
                      divider(),
                      stat('Leave', _leave, _C.amber),
                      divider(),
                      stat('Medical', _medical, _C.medicalGrey),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // PINNED SEARCH + TABLE HEADER
  // ==========================================
  Widget _buildSearchAndTableHeaders() {
    const hStyle = TextStyle(
      fontFamily: kAppFont,
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: _C.slate,
    );

    // FIX: pehle transparent tha -> scroll hote rows search bar ke peeche dikhte the
    return Container(
      color: _C.pinnedBg,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
            child: Container(
              height: 36 * MediaQuery.textScalerOf(context).scale(1),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _C.line, width: 0.9),
              ),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) {
                  setState(() {
                    _query = v.trim();
                  });
                },
                style: const TextStyle(
                  fontFamily: kAppFont,
                  fontSize: 12,
                  color: _C.ink,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: 'Search by student name or SR NO...',
                  hintStyle: const TextStyle(
                    fontFamily: kAppFont,
                    fontSize: 11,
                    color: _C.muted,
                    fontWeight: FontWeight.w500,
                  ),
                  prefixIcon: const Icon(
                    CupertinoIcons.search,
                    size: 14,
                    color: _C.muted,
                  ),
                  suffixIcon: _query.isEmpty
                      ? null
                      : GestureDetector(
                          onTap: () {
                            _searchCtrl.clear();
                            setState(() {
                              _query = '';
                            });
                          },
                          child: const Icon(
                            CupertinoIcons.clear_circled_solid,
                            size: 14,
                            color: _C.muted,
                          ),
                        ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 9),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(10),
                ),
                border: Border.all(color: _C.line, width: 0.8),
              ),
              child: const Row(
                children: [
                  SizedBox(width: 32, child: Text('S.No', style: hStyle)),
                  SizedBox(width: 8),
                  Expanded(child: Text('Student Info', style: hStyle)),
                  SizedBox(
                    width: 148,
                    child: Text(
                      'Status',
                      textAlign: TextAlign.center,
                      style: hStyle,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // LIST
  // ==========================================
  List<Widget> _buildListSlivers(List<StudentRecord> list) {
    if (_isLoading) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CupertinoActivityIndicator(radius: 12),
                  if (_isAutoRetrying) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Portal busy. Restoring session...',
                      style: TextStyle(
                        fontFamily: kAppFont,
                        fontSize: 11.5,
                        color: _C.slate,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ];
    }

    if (_errorMessage.isNotEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                const Icon(
                  CupertinoIcons.exclamationmark_circle,
                  color: _C.rose,
                  size: 32,
                ),
                const SizedBox(height: 10),
                Text(
                  _errorMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _C.rose,
                    fontFamily: kAppFont,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: () => _loadClassData(forceRefresh: true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _C.inkDeep,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Try again',
                      style: TextStyle(
                        fontFamily: kAppFont,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ];
    }

    if (list.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Center(
              child: Text(
                _query.isNotEmpty
                    ? 'No match for "$_query".'
                    : 'No students found.',
                style: const TextStyle(color: _C.muted, fontFamily: kAppFont),
              ),
            ),
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.only(bottom: 24),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, idx) => _buildRow(list[idx], idx + 1, list.length),
            childCount: list.length,
          ),
        ),
      ),
    ];
  }

  Widget _buildRow(StudentRecord s, int index, int totalCount) {
    final st = s.attendanceStatus;
    final isAbsent = st == 'A';
    final bool isLast = index == totalCount;

    Color rowBg = Colors.white.withOpacity(0.92);
    Color dot = st == '?' ? _C.muted : _C.green;

    if (st == 'A') {
      rowBg = _C.roseBg;
      dot = _C.rose;
    } else if (st == 'L') {
      rowBg = _C.amberBg;
      dot = _C.amber;
    } else if (st == 'M') {
      rowBg = _C.medicalBg;
      dot = _C.medicalGrey;
    }

    final sno = s.serialNo.length == 1
        ? s.serialNo.padLeft(2, '0')
        : s.serialNo;

    return Padding(
      key: ValueKey('${s.srNo}_${s.serialNo}'),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: rowBg,
          borderRadius: isLast
              ? const BorderRadius.vertical(bottom: Radius.circular(10))
              : BorderRadius.zero,
          border: Border(
            left: const BorderSide(color: _C.line, width: 0.8),
            right: const BorderSide(color: _C.line, width: 0.8),
            bottom: BorderSide(color: _C.line, width: isLast ? 0.8 : 0.6),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8.5),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Text(
                sno,
                style: TextStyle(
                  fontFamily: kAppFont,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: isAbsent ? _C.rose : _C.muted,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: dot,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: kAppFont,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                            color: isAbsent ? const Color(0xFF991B1B) : _C.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'SR NO : ${s.srNo}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: kAppFont,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: isAbsent
                                ? const Color(0xFFB91C1C)
                                : _C.slate,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 148,
              child: _StatusSelector(
                status: st,
                isSaving:
                    _isSaving || _isConfirming || _isLoading || _submissionHold,
                onChanged: (c) => _setStatus(s, c),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // SUBMIT / UPDATE BUTTON
  // ==========================================
  Widget _buildSubmitButton() {
    // FIX: loading ke dauran bhi disabled (purana data submit hone ka bug)
    final disabled =
        _students.isEmpty ||
        _isSaving ||
        _isConfirming ||
        _isLoading ||
        (!_submissionHold && !_portalDataVerified);

    final title = _submissionHold
        ? 'Verify Previous Save'
        : (_isAlreadyMarked || _isPortalVerified)
        ? 'Update Attendance'
        : 'Submit Attendance';

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: disabled ? null : _onSubmitTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            constraints: const BoxConstraints(minHeight: 42),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: disabled ? _C.muted : _C.ink,
              borderRadius: BorderRadius.circular(8),
              boxShadow: disabled
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.18),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Center(
              child: _isSaving
                  ? const CupertinoActivityIndicator(
                      color: Colors.white,
                      radius: 8.5,
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset(
                          kSubmitIcon,
                          width: 17,
                          height: 17,
                          fit: BoxFit.contain,
                          color: kSubmitIconTint ? Colors.white : null,
                          errorBuilder: (_, __, ___) => const Icon(
                            CupertinoIcons.checkmark_seal,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(child: Text(
                          title, textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: kAppFont,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            letterSpacing: -0.1,
                            color: Colors.white,
                          )),
                        ),
                        if (_dirty) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: _C.amber,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '$_changes',
                              style: const TextStyle(
                                fontFamily: kAppFont,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// RING PAINTER
// ==========================================
class _RingPainter extends CustomPainter {
  final double ratio;
  final Color track;
  final Color color;
  final double stroke;

  _RingPainter({
    required this.ratio,
    required this.track,
    required this.color,
    required this.stroke,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    paint.color = track;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint);

    if (ratio > 0) {
      paint.color = color;
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * ratio.clamp(0.0, 1.0),
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.ratio != ratio || old.track != track || old.color != color;
}

// ==========================================
// 3. STATUS SELECTOR (P, A, L, ML)
// ==========================================
class _StatusSelector extends StatelessWidget {
  final String status;
  final ValueChanged<String> onChanged;
  final bool isSaving;

  const _StatusSelector({
    required this.status,
    required this.onChanged,
    this.isSaving = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget item(String code, String label, Color color) {
      final sel = status == code;

      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (isSaving) return;
            onChanged(code);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(
              color: sel ? color : Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: sel ? color : _C.line,
                width: sel ? 1 : 0.8,
              ),
              boxShadow: sel
                  ? [
                      BoxShadow(
                        color: color.withOpacity(0.24),
                        blurRadius: 4,
                        offset: const Offset(0, 1.5),
                      ),
                    ]
                  : null,
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: kAppFont,
                fontSize: label == 'ML' ? 9.5 : 10.5,
                fontWeight: FontWeight.w800,
                color: sel ? Colors.white : _C.slate,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      height: 30,
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        color: _C.fillLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _C.line, width: 0.8),
      ),
      child: Row(
        children: [
          item('P', 'P', _C.green),
          item('A', 'A', _C.rose),
          item('L', 'L', _C.amber),
          item('M', 'ML', _C.medicalGrey),
        ],
      ),
    );
  }
}

// ==========================================
// 4. CONFIRM SHEET
// ==========================================
class _ConfirmSheet extends StatelessWidget {
  final String className;
  final String date;
  final int present;
  final int absent;
  final int leave;
  final int medical;

  const _ConfirmSheet({
    required this.className,
    required this.date,
    required this.present,
    required this.absent,
    required this.leave,
    required this.medical,
  });

  @override
  Widget build(BuildContext context) {
    Widget stat(String label, int v, Color fg, Color bg) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: fg.withOpacity(0.2), width: 0.8),
          ),
          child: Column(
            children: [
              Text(
                '$v',
                style: TextStyle(
                  fontFamily: kAppFont,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: fg,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                label,
                style: TextStyle(
                  fontFamily: kAppFont,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: _C.line,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Confirm Attendance',
            style: TextStyle(
              fontFamily: kAppFont,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: _C.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$className  •  $date',
            style: const TextStyle(
              fontFamily: kAppFont,
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: _C.slate,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              stat('Present', present, _C.green, _C.greenBg),
              const SizedBox(width: 6),
              stat('Absent', absent, _C.rose, _C.roseBg),
              const SizedBox(width: 6),
              stat('Leave', leave, _C.amber, _C.amberBg),
              const SizedBox(width: 6),
              stat('Medical', medical, _C.medicalGrey, _C.medicalBg),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.pop(context, false),
                  child: Container(
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: _C.line),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          fontFamily: kAppFont,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: _C.slate,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context, true),
                  child: Container(
                    height: 42,
                    decoration: BoxDecoration(
                      color: _C.inkDeep,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Text(
                        'Confirm & Save',
                        style: TextStyle(
                          fontFamily: kAppFont,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 5. SLIVER DELEGATE
// ==========================================
class _PinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Widget child;

  _PinnedHeaderDelegate({required this.height, required this.child});

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return SizedBox(height: height, child: child);
  }

  @override
  bool shouldRebuild(covariant _PinnedHeaderDelegate old) => true;
}
