// lib/tabs/teacher/modules/shaladarpan/attendance_view.dart
import 'dart:async';
import 'dart:convert';

import 'staff_leave_icon_data.dart';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shaladarpan/services/portals/shaladarpan/shaladarpan_service.dart';
import 'package:shaladarpan/services/portals/shaladarpan/offline_attendance_queue.dart';

final _staffLeaveIconBytes = base64Decode(staffLeaveIconBase64);

const String kAppFont = 'PlusJakartaSans';

class AttendanceView extends StatefulWidget {
  final VoidCallback? onAttendanceUpdated;
  const AttendanceView({super.key, this.onAttendanceUpdated});

  @override
  State<AttendanceView> createState() => _AttendanceViewState();
}

class _AttendanceViewState extends State<AttendanceView> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode(
    debugLabel: 'staff_attendance_search',
  );
  Timer? _toastTimer;
  Timer? _attendanceClockTimer;

  static const String _attendanceTimeMessage =
      'Attendance can only be marked between 8:00 AM - 5:00 PM.';

  bool get _attendanceHoursOpen {
    // Submission display rule; the authenticated worker enforces writes. READ remains available.
    final ist = DateTime.now().toUtc().add(
      const Duration(hours: 5, minutes: 30),
    );
    return ist.hour >= 8 && ist.hour < 17;
  }

  void _showTimeRestriction() => _showAppleToast(
    _attendanceTimeMessage,
    icon: CupertinoIcons.exclamationmark_circle,
    iconColor: const Color(0xFFF59E0B),
  );
  String _searchQuery = '';
  String _statusFilter = 'all';
  String? _loadError;
  bool _requiresVerification = false;
  String? _portalMarkedAt;
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _isAlreadyMarked = false;
  bool _hasOfflineQueue = false;
  bool _isSyncingQueue = false;
  bool _isRefreshing = false;

  OverlayEntry? _currentToastEntry;

  List<Map<String, String>> _attendanceOptions = [];

  List<Map<String, dynamic>> _staffList = [];

  String get _todayStr {
    final now = DateTime.now().toUtc().add(
      const Duration(hours: 5, minutes: 30),
    );
    return "${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
  }

  @override
  void initState() {
    super.initState();
    // Repaint at window boundaries; resume a fetch when access opens.
    bool previousOpen = _attendanceHoursOpen;
    _attendanceClockTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      final isOpen = _attendanceHoursOpen;
      if (isOpen != previousOpen) {
        previousOpen = isOpen;
        setState(() {});
        if (isOpen && !_isAlreadyMarked && !_isSubmitting) {
          _loadCachedOrFetchStaff(forceRefresh: true);
        }
      }
    });
    _loadCachedOrFetchStaff();
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    _attendanceClockTimer?.cancel();
    _currentToastEntry?.remove();
    _searchFocus.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _checkOfflineQueue() async {
    final hasPending = await OfflineAttendanceQueue.hasPendingQueue();
    if (mounted) setState(() => _hasOfflineQueue = hasPending);

    // Attendance cannot be updated after lock. Stored drafts never auto-submit.
  }

  Future<void> _triggerQueueSync({bool silent = false}) async {
    if (!_attendanceHoursOpen) {
      if (!silent) _showTimeRestriction();
      return;
    }
    if (_isSyncingQueue || _isAlreadyMarked || _requiresVerification) return;
    setState(() => _isSyncingQueue = true);

    final res = await OfflineAttendanceQueue.syncNow();
    if (mounted) {
      setState(() => _isSyncingQueue = false);
      if (ShaladarpanService.isSubmissionConfirmed(res)) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('attendance_verified_date', _todayStr);
        await prefs.setBool('attendance_already_marked', true);

        if (!mounted) return;
        setState(() {
          _hasOfflineQueue = false;
          _isAlreadyMarked = true;
        });

        _showAppleToast(
          res["already_locked"] == true
              ? "Attendance locked on Shala Darpan"
              : "Synced with Shala Darpan",
          icon: CupertinoIcons.checkmark_seal_fill,
          iconColor: const Color(0xFF10B981),
        );
        widget.onAttendanceUpdated?.call();
      } else if (!silent) {
        _showAppleToast(
          res['message']?.toString() ??
              'Stored attendance needs portal verification',
          icon: Icons.cloud_off_rounded,
          iconColor: const Color(0xFFF59E0B),
        );
      }
    }
  }

  Future<void> _loadCachedOrFetchStaff({bool forceRefresh = false}) async {
    // Local flags from older versions are not portal confirmation. Fetch live.
    await _fetchLiveStaff(forceRefresh: forceRefresh);
  }

  Future<void> _fetchLiveStaff({bool forceRefresh = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedSchoolId =
          prefs.getString('saved_school_id') ??
          prefs.getString('saved_shala_id') ??
          prefs.getString('school_id') ??
          "";

      if (mounted &&
          prefs.getBool(
                'attendance_submission_hold_${savedSchoolId}_$_todayStr',
              ) ==
              true) {
        setState(() => _requiresVerification = true);
      }
      final res = await ShaladarpanService.fetchStaffAttendance(
        schoolId: savedSchoolId,
        forceRefresh: forceRefresh,
      );
      if (res['success'] == true && res['data'] != null) {
        final bool isMarked = ShaladarpanService.isAttendanceConfirmed(
          res['data'] as Map,
        );

        if (isMarked) {
          await prefs.setString('attendance_verified_date', _todayStr);
          await prefs.setBool('attendance_already_marked', true);
        }

        if (!mounted) return;
        _requiresVerification =
            prefs.getBool(
              'attendance_submission_hold_${savedSchoolId}_$_todayStr',
            ) ==
            true;
        _loadError = null;
        _applyStaffPayload(res['data'], enforceMarked: isMarked);
        await prefs.setString(
          'cached_staff_attendance',
          jsonEncode(res['data']),
        );
      } else {
        if (mounted)
          setState(() {
            _staffList = [];
            _isAlreadyMarked = false;
            _loadError =
                res['message']?.toString() ??
                'Could not fetch portal attendance.';
          });
        if (mounted)
          _showAppleToast(
            res['message']?.toString() ?? 'Could not fetch portal attendance.',
            icon: CupertinoIcons.exclamationmark_circle,
            iconColor: const Color(0xFFF59E0B),
          );
      }
    } catch (_) {
      if (mounted)
        setState(() {
          _staffList = [];
          _isAlreadyMarked = false;
          _loadError = 'Could not fetch portal attendance.';
        });
      if (mounted)
        _showAppleToast(
          'Could not fetch portal attendance.',
          icon: CupertinoIcons.exclamationmark_circle,
          iconColor: const Color(0xFFF59E0B),
        );
    }
    if (mounted) {
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
      });
    }
    if (mounted) _checkOfflineQueue();
  }

  void _applyStaffPayload(dynamic data, {bool? enforceMarked}) {
    if (!mounted || data == null) return;

    List rawList = [];
    bool marked = enforceMarked ?? false;

    if (data is Map) {
      if (enforceMarked == null) {
        marked = ShaladarpanService.isAttendanceConfirmed(data);
      }
      rawList = data['staff'] ?? data['data'] ?? [];
    } else if (data is List) {
      rawList = data;
    }

    final nativeOptions = <String, String>{};
    for (final raw in rawList) {
      if (raw is Map && raw['options'] is List) {
        for (final option in raw['options'] as List) {
          if (option is Map)
            nativeOptions['${option['code']}'] = '${option['label']}';
        }
      }
    }
    setState(() {
      _attendanceOptions = nativeOptions.entries
          .map((e) => {'code': e.key, 'label': e.value})
          .toList();
      _isAlreadyMarked = marked;
      _portalMarkedAt = data is Map ? data['marked_at']?.toString() : null;
      if (marked) _requiresVerification = false;
      _staffList = [];

      if (rawList.isNotEmpty) {
        _staffList = rawList.map((item) {
          final m = Map<String, dynamic>.from(item);
          final String teacherName = m["name"]?.toString() ?? "Employee";

          final bool isApprovedToday = m['isApprovedLeave'] == true;
          final String effectiveCode = m['status_code']?.toString() ?? '';
          return {
            "sno": m["sno"]?.toString() ?? "1",
            "staffId": m["staffId"]?.toString() ?? "",
            "employeeId": m["employeeId"]?.toString() ?? "--",
            "name": teacherName,
            "designation":
                m["post"]?.toString() ??
                m["designation"]?.toString() ??
                "Staff",
            "attendanceCode": effectiveCode,
            "editable": m['editable'] == true,
            "original_status": m['original_status'],
            "options": m['options'] is List ? m['options'] : [],
            "portalStatus": m['status']?.toString() ?? '',
            "category": m['category'],
            "appliedLeave": m["appliedLeave"],
            "isApprovedLeave": isApprovedToday,
          };
        }).toList();
      }
      _isLoading = false;
    });
  }

  String _rowCategory(Map row) {
    final options = row['options'] is List ? row['options'] as List : [];
    final selected = options.where(
      (o) => o is Map && o['code']?.toString() == row['attendanceCode'],
    );
    final text =
        (selected.isNotEmpty ? selected.first['label'] : row['portalStatus'])
            ?.toString()
            .toLowerCase() ??
        '';
    if (text.contains('absent') || text.contains('अनुपस्थित')) return 'absent';
    if (text.contains('leave') ||
        text.contains('अवकाश') ||
        row['appliedLeave'] != null)
      return 'leave';
    if (text.contains('present') || text.contains('उपस्थित')) return 'present';
    return 'other';
  }

  int get _presentCount =>
      _staffList.where((s) => _rowCategory(s) == 'present').length;
  int get _onLeaveCount =>
      _staffList.where((s) => _rowCategory(s) == 'leave').length;
  int get _otherCount =>
      _staffList.where((s) => _rowCategory(s) == 'other').length;
  int get _absentCount =>
      _staffList.where((s) => _rowCategory(s) == 'absent').length;

  String _getInitials(String name) {
    List<String> parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return "${parts[0][0]}${parts[parts.length - 1][0]}".toUpperCase();
  }

  String _getStatusLabel(String code) {
    return _attendanceOptions.firstWhere(
      (o) => o["code"] == code,
      orElse: () => {"code": code, "label": "Portal status"},
    )["label"]!;
  }

  void _haptic() => HapticFeedback.selectionClick();

  void _showAppleToast(
    String message, {
    IconData icon = CupertinoIcons.checkmark_alt,
    Color iconColor = const Color(0xFF34C759),
  }) {
    if (!mounted) return;
    _toastTimer?.cancel();
    _currentToastEntry?.remove();
    final overlay = Overlay.of(context);
    final inset = MediaQuery.of(context).padding.top;
    final entry = OverlayEntry(
      builder: (_) => Positioned(
        top: inset + 12,
        left: 24,
        right: 24,
        // A notification must never intercept search taps or other page controls.
        child: IgnorePointer(
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF182538).withOpacity(0.95),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: iconColor, size: 16),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        message,
                        style: const TextStyle(
                          fontFamily: kAppFont,
                          fontSize: 12,
                          color: Colors.white,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    _currentToastEntry = entry;
    overlay.insert(entry);
    _toastTimer = Timer(const Duration(seconds: 3), () {
      if (identical(_currentToastEntry, entry)) {
        entry.remove();
        _currentToastEntry = null;
      }
    });
  }

  // 🛡️ SAFEGURAD: Pre-Submit Detailed Review Modal (Fixed RenderFlex Layout Crash)
  void _showAttendanceConfirmationSheet() {
    if (!_attendanceHoursOpen) {
      _showTimeRestriction();
      return;
    }
    if (_staffList.isEmpty ||
        _isSubmitting ||
        _isSyncingQueue ||
        _isLoading ||
        _isAlreadyMarked ||
        _requiresVerification ||
        _isRefreshing)
      return;
    _haptic();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        padding: const EdgeInsets.all(22.0),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min, // Essential for bottom sheet
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xFFDC2626),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Review Final Attendance",
                        style: TextStyle(
                          fontFamily: kAppFont,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        "Final lock cannot be edited. Review every employee.",
                        style: TextStyle(
                          fontFamily: kAppFont,
                          fontSize: 11.0,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Detailed Staff List Review (Flexible + shrinkWrap prevents layout crash)
            Flexible(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: ListView.separated(
                  shrinkWrap:
                      true, // Prevents "unbounded height" error inside Flexible
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  itemCount: _staffList.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  itemBuilder: (context, index) {
                    final s = _staffList[index];
                    final code = s["attendanceCode"];
                    final label = _rowStatus(s);
                    final isPresent = code == "0";
                    final isCustom = code != "0" && code != "89";

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s["name"],
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontFamily: kAppFont,
                                    fontSize: 12.0,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                Text(
                                  "NIC ${s["staffId"]} · ${s["employeeId"]}",
                                  style: const TextStyle(
                                    fontFamily: kAppFont,
                                    fontSize: 9.5,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: isPresent
                                      ? const Color(0xFFDCFCE7)
                                      : (isCustom
                                            ? const Color(0xFFFEF3C7)
                                            : const Color(0xFFFEE2E2)),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    fontFamily: kAppFont,
                                    fontSize: 10.0,
                                    fontWeight: FontWeight.w700,
                                    color: isPresent
                                        ? const Color(0xFF16A34A)
                                        : (isCustom
                                              ? const Color(0xFFD97706)
                                              : const Color(0xFFDC2626)),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),

            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text(
                      "Edit",
                      style: TextStyle(
                        fontFamily: kAppFont,
                        color: Color(0xFF475569),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      if (!_attendanceHoursOpen) {
                        _showTimeRestriction();
                        return;
                      }
                      _executeSubmit();
                    },
                    child: const Text(
                      "Confirm & Submit",
                      style: TextStyle(
                        fontFamily: kAppFont,
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _executeSubmit() async {
    if (!_attendanceHoursOpen) {
      _showTimeRestriction();
      return;
    }
    if (_isSubmitting ||
        _isSyncingQueue ||
        _isLoading ||
        _isAlreadyMarked ||
        _requiresVerification ||
        _isRefreshing)
      return;
    HapticFeedback.mediumImpact();
    setState(() => _isSubmitting = true);

    // 🛡️ FIXED: Passing 'staffId' strictly for robust backend identity matching
    final payload = _staffList
        .map(
          (s) => {
            "sno": s["sno"],
            "staffId": s["staffId"],
            "status_code": s['editable'] == true || s['attendanceCode'] != ''
                ? s['attendanceCode']
                : null,
            "original_status": s['original_status'],
          },
        )
        .toList();

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedSchoolId =
          prefs.getString('saved_school_id') ??
          prefs.getString('saved_shala_id') ??
          prefs.getString('school_id') ??
          "";

      final res = await ShaladarpanService.submitStaffAttendance(
        payload,
        schoolId: savedSchoolId,
      );

      if (!mounted) return;

      if (ShaladarpanService.isSubmissionConfirmed(res)) {
        HapticFeedback.lightImpact();
        await prefs.setString('attendance_verified_date', _todayStr);
        await prefs.setBool('attendance_already_marked', true);

        if (res['data'] != null) {
          final freshData = Map<String, dynamic>.from(res['data']);
          _applyStaffPayload(freshData, enforceMarked: true);
          await prefs.setString(
            'cached_staff_attendance',
            jsonEncode(freshData),
          );
        }

        if (!mounted) return;
        setState(() {
          _hasOfflineQueue = false;
          _isAlreadyMarked = true;
        });

        widget.onAttendanceUpdated?.call();
        _showAppleToast(
          res['submission_attempted'] == false
              ? (res['message']?.toString() ??
                    'Attendance already marked on Shala Darpan')
              : (res['portal_message']?.toString() ??
                    res['message']?.toString() ??
                    'Attendance verified on Shala Darpan'),
        );
      } else {
        if (prefs.getBool(
                  'attendance_submission_hold_${savedSchoolId}_$_todayStr',
                ) ==
                true ||
            res['submission_attempted'] == true ||
            [
              'SAVE_UNCONFIRMED',
              'MUTATION_AMBIGUOUS',
              'MUTATION_TIMEOUT',
            ].contains(res['code'])) {
          setState(() => _requiresVerification = true);
        }
        _showAppleToast(
          res['message']?.toString() ??
              'Attendance could not be confirmed. Refresh before retrying.',
          icon: CupertinoIcons.exclamationmark_circle,
          iconColor: const Color(0xFFF59E0B),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _requiresVerification = true);
      if (mounted)
        _showAppleToast(
          'Submission result is unknown. Verify portal attendance before retrying.',
          icon: CupertinoIcons.exclamationmark_circle,
          iconColor: const Color(0xFFF59E0B),
        );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showStatusPicker(Map<String, dynamic> teacher) {
    if (!_canEdit || teacher['editable'] != true) return;
    final options = (teacher['options'] as List)
        .map((o) => Map<String, dynamic>.from(o as Map))
        .toList();
    if (options.isEmpty) return;

    if (_isAlreadyMarked) return;
    _haptic();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.65,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        "Update Status: ${teacher['name']}",
                        style: const TextStyle(
                          fontFamily: kAppFont,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  itemCount: options.length,
                  itemBuilder: (context, idx) {
                    final opt = options[idx];
                    final bool isSelected =
                        teacher["attendanceCode"] == opt["code"];

                    Color optBg = const Color(0xFFE2E8F0);
                    Color optText = const Color(0xFF1E293B);

                    if (opt["code"] == "0") {
                      optBg = const Color(0xFF34C759);
                      optText = Colors.white;
                    } else if (opt["code"] == "88" || opt["code"] == "89") {
                      optBg = const Color(0xFFFFF59D);
                      optText = const Color(0xFF0F172A);
                    } else if (opt["code"] == "90") {
                      optBg = const Color(0xFFFFF5F5);
                      optText = const Color(0xFFE03131);
                    } else if (opt["code"] != "0") {
                      optBg = const Color(0xFFFEF3C7);
                      optText = const Color(0xFFB45309);
                    }

                    return GestureDetector(
                      onTap: () {
                        if (!_canEdit) return;
                        _haptic();
                        setState(() {
                          teacher["attendanceCode"] = opt["code"];
                          if (opt["code"] != "89")
                            teacher["isApprovedLeave"] = false;
                        });
                        Navigator.pop(context);
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected ? optBg : Colors.transparent,
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
                                  fontSize: 12.5,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: isSelected
                                      ? optText
                                      : const Color(0xFF334155),
                                ),
                              ),
                            ),
                            if (isSelected)
                              Icon(
                                Icons.check_circle_rounded,
                                color: optText,
                                size: 17,
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

  bool get _canEdit =>
      _attendanceHoursOpen &&
      !_isAlreadyMarked &&
      !_isSubmitting &&
      !_isLoading &&
      !_isRefreshing &&
      !_isSyncingQueue &&
      !_requiresVerification &&
      _loadError == null;

  String _rowStatus(Map row) {
    final options = row['options'] is List ? row['options'] as List : [];
    for (final option in options) {
      if (option is Map &&
          option['code']?.toString() == row['attendanceCode']?.toString()) {
        return option['label']?.toString() ?? 'Unknown portal status';
      }
    }
    return row['portalStatus']?.toString().isNotEmpty == true
        ? row['portalStatus'].toString()
        : 'Unknown portal status';
  }

  String _normalizeSearch(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  List<Map<String, dynamic>> get _visibleStaff {
    final words = _normalizeSearch(_searchQuery)
        .split(' ')
        .where((s) => s.isNotEmpty)
        .toList();
    return _staffList.where((row) {
      final text = _normalizeSearch(
        [
          row['name'],
          row['staffId'],
          row['employeeId'],
          row['sno'],
          row['designation'],
        ].map((v) => v?.toString() ?? '').join(' '),
      );
      final matchesSearch = words.every((word) => text.contains(word));
      final matchesStatus =
          _statusFilter == 'all' ||
          (_statusFilter == 'locked'
              ? (_isAlreadyMarked || row['editable'] != true)
              : _rowCategory(row) == _statusFilter);
      return matchesSearch && matchesStatus;
    }).toList();
  }

  Color _statusColor(Map row) {
    switch (_rowCategory(row)) {
      case 'present':
        return const Color(0xFF16845B);
      case 'absent':
        return const Color(0xFFC54C4C);
      case 'leave':
        return const Color(0xFFAD7428);
      default:
        return const Color(0xFF54647D);
    }
  }

  void _markAllPresent() {
    if (!_canEdit) return;
    _haptic();
    setState(() {
      // Apply to the whole roster, including rows hidden by search. Locked rows stay unchanged.
      for (final row in _staffList) {
        if (row['editable'] != true) continue;
        final options = (row['options'] as List).where((option) {
          final label = '${option['label']}'.toLowerCase();
          return !label.contains('absent') &&
              !label.contains('अनुपस्थित') &&
              (label.contains('present') || label.contains('उपस्थित'));
        }).toList();
        if (options.length == 1)
          row['attendanceCode'] = options.single['code'].toString();
      }
    });
  }

  String _markedAtDisplay(String value) {
    return value
        .replaceAllMapped(
          RegExp(r'(\d{1,2}:\d{2}):\d{2}(?:[:.]\d+)?'),
          (match) => match.group(1)!,
        )
        .replaceAllMapped(
          RegExp(r'(\d{1,2}:\d{2})\s*(AM|PM)', caseSensitive: false),
          (match) => '${match.group(1)} ${match.group(2)!.toUpperCase()}',
        )
        .trim();
  }

  Widget _attendanceSummary() {
    final items = <(String, int, Color, IconData)>[
      (
        'Present',
        _presentCount,
        const Color(0xFF059669),
        Icons.person_outline_rounded,
      ),
      (
        'Absent',
        _absentCount,
        const Color(0xFFE34D65),
        Icons.person_off_outlined,
      ),
      (
        'Leave',
        _onLeaveCount,
        const Color(0xFFD18A19),
        Icons.event_available_rounded,
      ),
      ('Other', _otherCount, const Color(0xFF64748B), Icons.category_outlined),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        final compact = box.maxWidth < 600;
        final gap = compact ? 5.0 : 8.0;
        final badge = compact ? 22.0 : 30.0;
        return Row(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) SizedBox(width: gap),
              Expanded(
                child: Semantics(
                  label: '${items[i].$1}: ${items[i].$2}',
                  excludeSemantics: true,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 6 : 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: const Color(0xFFE8ECF1)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            items[i].$1,
                            maxLines: 1,
                            style: const TextStyle(
                              fontFamily: kAppFont,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  '${items[i].$2}',
                                  style: const TextStyle(
                                    fontFamily: kAppFont,
                                    fontSize: 20,
                                    height: 1.2,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 3),
                            Container(
                              width: badge,
                              height: badge,
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: items[i].$3.withOpacity(0.09),
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: i < 2
                                  ? CustomPaint(
                                      painter: _AttendancePersonIcon(
                                        color: items[i].$3,
                                        present: i == 0,
                                      ),
                                    )
                                  : i == 2
                                  ? Image.memory(
                                      _staffLeaveIconBytes,
                                      fit: BoxFit.contain,
                                      color: items[i].$3,
                                      colorBlendMode: BlendMode.srcIn,
                                      gaplessPlayback: true,
                                      errorBuilder: (_, __, ___) => Icon(
                                        Icons.event_note_rounded,
                                        size: badge - 6,
                                        color: items[i].$3,
                                      ),
                                    )
                                  : Icon(
                                      items[i].$4,
                                      size: badge - 6,
                                      color: items[i].$3,
                                    ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading)
      return const Center(child: CupertinoActivityIndicator(radius: 12));

    final filteredStaff = _visibleStaff;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 420;
        final statusWidth = compact ? 100.0 : 120.0;
        return Column(
          children: [
            _attendanceSummary(),
            const SizedBox(height: 10),
            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0),
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  enabled: true,
                  readOnly: false,
                  onTap: () {
                    if (kDebugMode)
                      debugPrint('[Staff attendance] Search received tap');
                  },
                  onChanged: (val) =>
                      setState(() => _searchQuery = val.trim().toLowerCase()),
                  style: const TextStyle(
                    fontFamily: kAppFont,
                    fontSize: 13.0,
                    color: Color(0xFF0F172A),
                  ),
                  decoration: InputDecoration(
                    hintText: "Search employee by name, NIC or ID...",
                    hintStyle: TextStyle(
                      fontFamily: kAppFont,
                      fontSize: 12.0,
                      color: Color(0xFF94A3B8),
                    ),
                    prefixIcon: IconButton(
                      tooltip: 'Search employees',
                      onPressed: () => _searchFocus.requestFocus(),
                      icon: const Icon(
                        CupertinoIcons.search,
                        size: 18,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    suffixIcon: _searchQuery.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                              _searchFocus.requestFocus();
                            },
                            icon: const Icon(
                              CupertinoIcons.clear_circled_solid,
                              size: 16,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 11.0),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 10),

            if (!_isAlreadyMarked && _hasOfflineQueue) ...[
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12.0),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14.0,
                  vertical: 11.0,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFFF59E0B).withOpacity(0.4),
                    width: 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFF59E0B).withOpacity(0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFEF3C7),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.cloud_off_rounded,
                        color: Color(0xFFD97706),
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Stored Attendance Draft",
                            style: TextStyle(
                              fontFamily: kAppFont,
                              fontSize: 12.0,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 1),
                          const Text(
                            "Draft retained • Review before submitting",
                            style: TextStyle(
                              fontFamily: kAppFont,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _showAppleToast(
                        'Review current portal attendance before submitting a stored draft.',
                        icon: CupertinoIcons.exclamationmark_circle,
                        iconColor: const Color(0xFFF59E0B),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6.5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: _isSyncingQueue
                            ? const CupertinoActivityIndicator(
                                radius: 6,
                                color: Colors.white,
                              )
                            : const Text(
                                "Review",
                                style: TextStyle(
                                  fontFamily: kAppFont,
                                  fontSize: 11.0,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10.0),
              padding: const EdgeInsets.symmetric(
                horizontal: 14.0,
                vertical: 8.5,
              ),
              decoration: BoxDecoration(
                color: _isAlreadyMarked
                    ? const Color(0xFFECFDF5)
                    : const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isAlreadyMarked
                      ? const Color(0xFFA7F3D0)
                      : const Color(0xFFFDE68A),
                  width: 1.0,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _isAlreadyMarked
                        ? Icons.check_circle_rounded
                        : Icons.access_time_filled_rounded,
                    color: _isAlreadyMarked
                        ? const Color(0xFF10B981)
                        : const Color(0xFFF59E0B),
                    size: 15,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _requiresVerification
                          ? 'Submission needs portal verification'
                          : _isAlreadyMarked
                          ? 'Attendance locked & verified on Shala Darpan${_portalMarkedAt?.isNotEmpty == true ? '\nMarked: ${_markedAtDisplay(_portalMarkedAt!)}' : ''}'
                          : _loadError != null
                          ? _loadError!
                          : !_attendanceHoursOpen && _staffList.isNotEmpty
                          ? 'Attendance loaded • Submission hours: 8:00 AM - 5:00 PM'
                          : "Today's Attendance pending submission",
                      style: TextStyle(
                        fontFamily: kAppFont,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: _isAlreadyMarked
                            ? const Color(0xFF065F46)
                            : const Color(0xFF92400E),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: (_isRefreshing || _isSubmitting || _isSyncingQueue)
                        ? null
                        : () {
                            setState(() => _isRefreshing = true);
                            _loadCachedOrFetchStaff(forceRefresh: true);
                          },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _isRefreshing
                          ? const CupertinoActivityIndicator(radius: 6)
                          : Icon(
                              CupertinoIcons.arrow_clockwise,
                              size: 13,
                              color: _isAlreadyMarked
                                  ? const Color(0xFF059669)
                                  : const Color(0xFFD97706),
                            ),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(11),
                        ),
                        border: Border(
                          bottom: BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 22,
                            child: Text(
                              "#",
                              style: TextStyle(
                                fontFamily: kAppFont,
                                fontSize: 11.0,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Row(
                              children: [
                                const Flexible(
                                  child: Text(
                                    "EMPLOYEE DETAILS",
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: kAppFont,
                                      fontSize: 11.0,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF64748B),
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F172A),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    filteredStaff.length.toString().padLeft(
                                      2,
                                      '0',
                                    ),
                                    style: const TextStyle(
                                      fontFamily: kAppFont,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: statusWidth,
                            child: const Text(
                              "ATTENDANCE",
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontFamily: kAppFont,
                                fontSize: 11.0,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF64748B),
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    Expanded(
                      child: filteredStaff.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  _loadError ??
                                      (_staffList.isEmpty
                                          ? 'No employees received from portal.'
                                          : 'No matching employees.'),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontFamily: kAppFont,
                                    fontSize: 12,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ),
                            )
                          : ListView.separated(
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              physics: const BouncingScrollPhysics(),
                              padding: const EdgeInsets.only(bottom: 4),
                              itemCount: filteredStaff.length,
                              separatorBuilder: (_, __) => const Divider(
                                height: 1,
                                color: Color(0xFFF1F5F9),
                              ),
                              itemBuilder: (context, index) {
                                final teacher = filteredStaff[index];
                                final String currentCode =
                                    teacher["attendanceCode"];
                                final bool hasAppliedLeave =
                                    teacher["appliedLeave"] != null;
                                final bool isApprovedToday =
                                    teacher["isApprovedLeave"] == true;

                                Color dropdownBgColor = const Color(0xFFE2E8F0);
                                Color dropdownTextColor = const Color(
                                  0xFF1E293B,
                                );
                                Color dropdownBorderColor = const Color(
                                  0xFFCBD5E1,
                                );

                                if (currentCode == "0") {
                                  dropdownBgColor = const Color(0xFFDCFCE7);
                                  dropdownTextColor = const Color(0xFF16A34A);
                                  dropdownBorderColor = const Color(0xFF86EFAC);
                                } else if (currentCode == "88" ||
                                    currentCode == "89") {
                                  dropdownBgColor = const Color(0xFFFFFBEB);
                                  dropdownTextColor = const Color(0xFFD97706);
                                  dropdownBorderColor = const Color(0xFFFDE68A);
                                } else if (currentCode == "90") {
                                  dropdownBgColor = const Color(0xFFFEE2E2);
                                  dropdownTextColor = const Color(0xFFDC2626);
                                  dropdownBorderColor = const Color(0xFFFCA5A5);
                                } else {
                                  dropdownBgColor = const Color(0xFFFEF3C7);
                                  dropdownTextColor = const Color(0xFFB45309);
                                  dropdownBorderColor = const Color(0xFFFCD34D);
                                }

                                final String fullStatusLabel = _rowStatus(
                                  teacher,
                                );
                                final String serialNumber = teacher['sno']
                                    .toString()
                                    .padLeft(2, '0');

                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 22,
                                        child: Text(
                                          serialNumber,
                                          style: const TextStyle(
                                            fontFamily: kAppFont,
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF94A3B8),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Row(
                                          children: [
                                            if (!compact)
                                              Container(
                                                width: 30,
                                                height: 30,
                                                decoration: BoxDecoration(
                                                  color: const Color(
                                                    0xFFF1F5F9,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Center(
                                                  child: Text(
                                                    _getInitials(
                                                      teacher["name"],
                                                    ),
                                                    style: const TextStyle(
                                                      fontFamily: kAppFont,
                                                      fontSize: 11.0,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: Color(0xFF0F172A),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            if (!compact)
                                              const SizedBox(width: 8),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Flexible(
                                                        child: Text(
                                                          teacher["name"],
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: TextStyle(
                                                            fontFamily:
                                                                kAppFont,
                                                            fontSize: compact
                                                                ? 11.5
                                                                : 13.0,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            color: const Color(
                                                              0xFF0F172A,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      if (isApprovedToday) ...[
                                                        const SizedBox(
                                                          width: 5,
                                                        ),
                                                        Container(
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 5,
                                                                vertical: 1,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color: const Color(
                                                              0xFFDCFCE7,
                                                            ),
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  4,
                                                                ),
                                                            border: Border.all(
                                                              color:
                                                                  const Color(
                                                                    0xFF86EFAC,
                                                                  ),
                                                              width: 0.8,
                                                            ),
                                                          ),
                                                          child: const Text(
                                                            "Locked",
                                                            style: TextStyle(
                                                              fontFamily:
                                                                  kAppFont,
                                                              fontSize: 8.5,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                              color: Color(
                                                                0xFF16A34A,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                  const SizedBox(height: 1.5),
                                                  Text(
                                                    "${teacher["staffId"]} • ${teacher["designation"]}",
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontFamily: kAppFont,
                                                      fontSize: 10.0,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      color: Color(0xFF64748B),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      SizedBox(
                                        width: statusWidth,
                                        child: hasAppliedLeave
                                            ? Container(
                                                height: 32,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: const Color(
                                                    0xFFF8FAFC,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  border: Border.all(
                                                    color: const Color(
                                                      0xFFE2E8F0,
                                                    ),
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        teacher["appliedLeave"],
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                          fontFamily: kAppFont,
                                                          fontSize: 10.0,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: Color(
                                                            0xFF64748B,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 2),
                                                    const Icon(
                                                      CupertinoIcons.lock,
                                                      size: 11,
                                                      color: Color(0xFF94A3B8),
                                                    ),
                                                  ],
                                                ),
                                              )
                                            : GestureDetector(
                                                onTap:
                                                    _canEdit &&
                                                        teacher['editable'] ==
                                                            true
                                                    ? () {
                                                        _searchFocus.unfocus();
                                                        _showStatusPicker(
                                                          teacher,
                                                        );
                                                      }
                                                    : null,
                                                behavior:
                                                    HitTestBehavior.opaque,
                                                child: Container(
                                                  height: 32,
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: dropdownBgColor,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                    border: Border.all(
                                                      color:
                                                          dropdownBorderColor,
                                                      width: 0.8,
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .spaceBetween,
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          fullStatusLabel,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: TextStyle(
                                                            fontFamily:
                                                                kAppFont,
                                                            fontSize: 10.5,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            color:
                                                                dropdownTextColor,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 2),
                                                      Icon(
                                                        _isAlreadyMarked ||
                                                                teacher['editable'] !=
                                                                    true
                                                            ? Icons
                                                                  .lock_outline_rounded
                                                            : CupertinoIcons
                                                                  .chevron_down,
                                                        size: 11,
                                                        color:
                                                            dropdownTextColor,
                                                      ),
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
                    ),

                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.vertical(
                          bottom: Radius.circular(11),
                        ),
                        border: Border(
                          top: BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Showing ${filteredStaff.length.toString().padLeft(2, '0')} of ${_staffList.length.toString().padLeft(2, '0')} employees",
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
                  ],
                ),
              ),
            ),

            // Bottom Action Bar
            // Native portal does not offer attendance actions in its restricted window.
            if (!_isAlreadyMarked && _attendanceHoursOpen && _loadError == null)
              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.only(top: 6, bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 44.0,
                          child: OutlinedButton(
                            onPressed: _canEdit && _staffList.isNotEmpty
                                ? _markAllPresent
                                : null,
                            style: ButtonStyle(
                              side: WidgetStateProperty.all(
                                const BorderSide(
                                  color: Color(0xFFCBD5E1),
                                  width: 1.0,
                                ),
                              ),
                              backgroundColor: WidgetStateProperty.all(
                                Colors.white,
                              ),
                              shape: WidgetStateProperty.all(
                                RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                            child: const FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    CupertinoIcons.check_mark_circled,
                                    size: 16,
                                    color: Color(0xFF0F172A),
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    "Mark All Present",
                                    style: TextStyle(
                                      fontFamily: kAppFont,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF0F172A),
                                    ),
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
                            ),
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF0F172A)
                                    .withOpacity(0.15),
                                blurRadius: 6,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: _canEdit && _staffList.isNotEmpty
                                ? () {
                                    _searchFocus.unfocus();
                                    _showAttendanceConfirmationSheet();
                                  }
                                : null,
                            style: ButtonStyle(
                              backgroundColor: WidgetStateProperty.all(
                                Colors.transparent,
                              ),
                              shadowColor: WidgetStateProperty.all(
                                Colors.transparent,
                              ),
                              shape: WidgetStateProperty.all(
                                RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                            child: _isSubmitting
                                ? const CupertinoActivityIndicator(
                                    color: Colors.white,
                                    radius: 8,
                                  )
                                : const FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          CupertinoIcons.cloud_upload,
                                          size: 16,
                                          color: Colors.white,
                                        ),
                                        SizedBox(width: 6),
                                        Text(
                                          "Submit Attendance",
                                          style: TextStyle(
                                            fontFamily: kAppFont,
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                          ),
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
      },
    );
  }
}

// Resolution-independent person icons with explicit attendance marks.
class _AttendancePersonIcon extends CustomPainter {
  final Color color;
  final bool present;
  const _AttendancePersonIcon({required this.color, required this.present});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    canvas.drawCircle(const Offset(8, 6), 3.2, pen);
    canvas.drawPath(
      Path()
        ..moveTo(2, 20)
        ..lineTo(2, 17)
        ..cubicTo(2, 12, 14, 12, 14, 17)
        ..lineTo(14, 20),
      pen,
    );
    if (present) {
      canvas.drawPath(
        Path()
          ..moveTo(16, 10)
          ..lineTo(18.2, 12.2)
          ..lineTo(22, 7.8),
        pen,
      );
    } else {
      canvas.drawLine(const Offset(17, 8), const Offset(22, 13), pen);
      canvas.drawLine(const Offset(22, 8), const Offset(17, 13), pen);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AttendancePersonIcon oldDelegate) =>
      oldDelegate.color != color || oldDelegate.present != present;
}
