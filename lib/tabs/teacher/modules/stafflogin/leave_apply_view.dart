import 'package:shaladarpan/widgets/adaptive_layout.dart';
// lib/tabs/teacher/modules/stafflogin/leave_apply_view.dart
import 'dart:async';
import 'dart:ui';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:shaladarpan/services/portals/staff_login/staff_login_service.dart';

const String kAppFont = 'PlusJakartaSans';

class LeaveApplyView extends StatefulWidget {
  final Map<String, String> currentUser;
  const LeaveApplyView({super.key, required this.currentUser});

  @override
  State<LeaveApplyView> createState() => _LeaveApplyViewState();
}

class _LeaveApplyViewState extends State<LeaveApplyView> {
  bool _isLoadingHistory = true;
  List<Map<String, dynamic>> _myLeaveHistory = [];
  String _activeFilter = "pending"; // 🚀 'pending' is the fast default tab now
  String? _generatingPdfId;
  double _downloadProgress = 0.0;
  bool _showAllLeaves = false;
  int _historyRequest = 0;
  String? _historyError;
  bool _isSubmittingLeave = false;
  final Map<String, Map<String, dynamic>> _acceptedLeaveTiming = {};
  String _leaveTimingKey(dynamic type, dynamic from, dynamic to) =>
      '${type ?? ""}|${from ?? ""}|${to ?? ""}';
  final Set<OverlayEntry> _toastEntries = {};
  final Set<Timer> _toastTimers = {};
  StreamSubscription<int>? _pdfProgressSubscription;

  @override
  void dispose() {
    _historyRequest++;
    unawaited(_pdfProgressSubscription?.cancel());
    for (final timer in _toastTimers) {
      timer.cancel();
    }
    for (final entry in _toastEntries) {
      entry.remove();
      entry.dispose();
    }
    _toastTimers.clear();
    _toastEntries.clear();
    super.dispose();
  }

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

  @override
  void initState() {
    super.initState();
    _loadLiveLeaveHistory(filter: "pending"); // 🚀 fast default load
  }

  Widget _buildLeaveAssetIcon({required double size, Color? color}) {
    return Image.asset(
      'assets/icons/leave.png', // ✅ Seedha sahi path jo aapke paas available hai
      width: size,
      height: size,
      fit: BoxFit.contain,
      color: color,
      errorBuilder: (_, _, _) => Icon(CupertinoIcons.doc_text_fill, size: size, color: color ?? const Color(0xFF64748B)),
    );
  }

  String _getResolvedNicId() {
    final u = widget.currentUser;
    final keys = ["nicId", "nic_id", "staffLoginId", "staffId", "username", "id"];
    for (final k in keys) {
      final val = (u[k] ?? "").trim();
      if (val.isNotEmpty && val != "--") return val;
    }
    return "--";
  }

  DateTime? _parseDmyDate(String? str) {
    if (str == null) return null;
    final match = RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{4})$').firstMatch(str.trim());
    if (match == null) return null;
    final day = int.parse(match[1]!);
    final month = int.parse(match[2]!);
    final year = int.parse(match[3]!);
    final date = DateTime(year, month, day);
    return date.year == year && date.month == month && date.day == day ? date : null;
  }

  Future<void> _loadLiveLeaveHistory({String filter = "pending", bool refresh = false}) async {
    if (!mounted) return;
    final request = ++_historyRequest;
    setState(() {
      _isLoadingHistory = true;
      _historyError = null;
      if (_activeFilter != filter) _myLeaveHistory = [];
      _activeFilter = filter;
      _showAllLeaves = false;
    });
    try {
      final res = await StaffLoginService.fetchLeaveHistory(filter: filter, refresh: refresh);
      if (!mounted || request != _historyRequest) return;
      if (res['success'] != true) {
        final message = res['message']?.toString().trim() ?? '';
        setState(() => _historyError = message);
        return;
      }
      final records = res['records'];
      if (records is! List || records.any((record) => record is! Map)) {
        throw const FormatException('Invalid leave history response.');
      }
      final mapped = records.map((record) => _mapPortalRecordToUi(Map<String, dynamic>.from(record))).toList();
      setState(() => _myLeaveHistory = mapped);
    } catch (e) {
      if (!mounted || request != _historyRequest) return;
      final message = e is FormatException ? e.message : e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      setState(() => _historyError = message.trim());
    } finally {
      if (mounted && request == _historyRequest) {
        setState(() => _isLoadingHistory = false);
      }
    }
  }

  Map<String, dynamic>? _resolveLeaveReason(dynamic code, dynamic label) {
    final id = code?.toString().trim();
    String normalize(dynamic value) => value?.toString().toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9\u0900-\u097F]'), '') ?? '';
    if (id != null && id.isNotEmpty) {
      for (final reason in _leaveReasons) {
        if (reason["code"].toString() == id) return reason;
      }
    }
    final text = normalize(label);
    if (text.isEmpty) return null;
    for (final reason in _leaveReasons) {
      if (normalize(reason["label"]) == text || reason["code"].toString() == text) return reason;
    }
    return null;
  }

  Map<String, dynamic> _mapPortalRecordToUi(Map<String, dynamic> raw) {
    final String rawType =
        ((raw["type"] ?? raw["leave_type"])?.toString().trim().isNotEmpty == true ? (raw["type"] ?? raw["leave_type"]) : "--")
            .toString()
            .trim();

    final matchedType = _leaveTypes.firstWhere(
      (t) =>
          t["short"].toString().toLowerCase() == rawType.toLowerCase() ||
          t["label"].toString().toLowerCase().contains(rawType.toLowerCase()),
      orElse: () => {
        "short": rawType.length > 5 ? rawType.substring(0, 5) : rawType,
        "label": rawType,
        "icon": CupertinoIcons.briefcase_fill,
      },
    );

    final String fromStr = (raw["from_date"] ?? "").toString().trim();
    final String toStr = (raw["to_date"] ?? "").toString().trim();
    final String dateRange = (fromStr.isNotEmpty && toStr.isNotEmpty) ? "$fromStr - $toStr" : (fromStr.isNotEmpty ? fromStr : "--");

    String status = (raw["status"] ?? "Unknown").toString().trim();
    final statusLower = status.toLowerCase();

    if (!statusLower.contains("not") &&
        !statusLower.contains("unapproved") &&
        !statusLower.contains("unprocessed") &&
        (statusLower.contains("processed") || statusLower.contains("approved"))) {
      status = "Approved";
    } else if (statusLower.contains("reject")) {
      status = "Rejected";
    } else if (statusLower.contains("cancel") || statusLower.contains("withdrawn")) {
      status = "Cancelled";
    }

    double? days = double.tryParse((raw["days"] ?? raw["total_days"] ?? raw["TotalDays"] ?? "").toString());
    if (days != null && (!days.isFinite || days <= 0)) days = null;

    final acceptedTiming = _acceptedLeaveTiming[_leaveTimingKey(
        raw["leave_type_id"] ?? matchedType["code"], fromStr, toStr)];
    if (days == null && acceptedTiming != null) {
      days = (acceptedTiming["days"] as num).toDouble();
    }
    final bool daysFromPortal = days != null;
    double? calendarDays;
    final startDate = _parseDmyDate(fromStr);
    final endDate = _parseDmyDate(toStr);
    if (startDate != null && endDate != null) {
      final span = DateTime.utc(endDate.year, endDate.month, endDate.day)
          .difference(DateTime.utc(startDate.year, startDate.month, startDate.day)).inDays + 1;
      if (span > 0) calendarDays = span.toDouble();
    }
    final durationRaw = raw["duration"]?.toString().trim().toLowerCase();
    final durationCode = ["2", "half", "half day"].contains(durationRaw) ? "2"
        : ["1", "full", "full day"].contains(durationRaw) ? "1" : null;

    final rawReason = (raw["reason"] ?? raw["leave_reason"] ?? raw["reason_name"] ?? "--").toString().trim();
    final matchedReason = _resolveLeaveReason(raw["reason_id"] ?? raw["reasonCode"], rawReason);

    return {
      "id": raw["record_id"] ?? raw["id"] ?? raw["sNo"] ?? "$fromStr|$toStr|$rawType",
      "sNo": raw["sNo"],
      "typeCode": raw["leave_type_id"]?.toString() ?? matchedType["code"],
      "reasonCode": matchedReason?["code"]?.toString(),
      "short": matchedType["short"] ?? rawType,
      "typeName": matchedType["label"] ?? rawType,
      "from_date": fromStr,
      "to_date": toStr,
      "days": days ?? calendarDays,
      "daysFromPortal": daysFromPortal,
      "dateRange": dateRange,
      "status": status,
      "duration": durationCode ?? acceptedTiming?["duration"],
      "dayType": raw["dayType"]?.toString() ?? acceptedTiming?["dayType"]?.toString(),
      "from_duration": raw["from_duration"],
      "to_duration": raw["to_duration"],
      "from_day_type": raw["from_day_type"],
      "to_day_type": raw["to_day_type"],
      "headquarter": raw["station_leave"] == "Y",
      "address": raw["address"]?.toString() ?? "",
      "reason": rawReason,
      "remark": raw["remark"]?.toString() ?? "",
      "icon": matchedType["icon"] ?? CupertinoIcons.briefcase_fill,
    };
  }

  Future<void> _openInAppPdfViewer(Map<String, dynamic> item) async {
    final String itemId = item["id"]?.toString() ?? "";
    if (!mounted || _generatingPdfId != null) return;

    setState(() {
      _generatingPdfId = itemId;
      _downloadProgress = 0.06;
    });
    HapticFeedback.mediumImpact();

    final progressSubscription = Stream.periodic(const Duration(milliseconds: 100), (i) => i).listen((tick) {
      if (!mounted || _generatingPdfId != itemId) return;
      setState(() {
        if (_downloadProgress < 0.35) {
          _downloadProgress += 0.04;
        } else if (_downloadProgress < 0.70) {
          _downloadProgress += 0.025;
        } else if (_downloadProgress < 0.90) {
          _downloadProgress += 0.012;
        }
      });
    });

    _pdfProgressSubscription = progressSubscription;
    try {
      final Uint8List? pdfBytes = await StaffLoginService.downloadLeavePdf(
        sNo: item["sNo"]?.toString(),
        name: widget.currentUser["name"],
        designation: widget.currentUser["designation"],
        school: widget.currentUser["schoolName"],
        leaveType: item["typeName"] ?? item["short"],
        fromDate: item["from_date"],
        toDate: item["to_date"],
        days: item["days"]?.toString(),
        reason: item["reason"],
        remark: item["remark"],
      );

      await progressSubscription.cancel();

      if (pdfBytes == null || pdfBytes.length < 5 || String.fromCharCodes(pdfBytes.take(5)) != '%PDF-') {
        throw Exception("The portal did not return a valid PDF.");
      }

      if (mounted) {
        setState(() => _downloadProgress = 1.0);
        HapticFeedback.lightImpact();
        await Future.delayed(const Duration(milliseconds: 220));
      }

      if (!mounted) return;

      Navigator.push(
        context,
        CupertinoPageRoute(
          builder: (context) => ModernLeavePdfPreviewScreen(pdfBytes: pdfBytes, item: item),
        ),
      );
    } catch (e) {
      await progressSubscription.cancel();
      _showAppleToast(
        "${e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '')}",
        icon: CupertinoIcons.exclamationmark_triangle_fill,
      );
    } finally {
      await progressSubscription.cancel();
      if (identical(_pdfProgressSubscription, progressSubscription)) _pdfProgressSubscription = null;
      if (mounted) {
        setState(() {
          _generatingPdfId = null;
          _downloadProgress = 0.0;
        });
      }
    }
  }

  void _showAppleToast(String message, {IconData icon = CupertinoIcons.checkmark_circle_fill}) {
    if (!mounted) return;
    HapticFeedback.lightImpact();
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (context) => Positioned(
        top: 24,
        left: 20,
        right: 20,
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(30),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 16, offset: const Offset(0, 6))],
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
        ),
      ),
    );

    overlay.insert(entry);
    _toastEntries.add(entry);
    late final Timer timer;
    timer = Timer(const Duration(seconds: 2), () {
      _toastTimers.remove(timer);
      if (_toastEntries.remove(entry)) {
        entry.remove();
        entry.dispose();
      }
    });
    _toastTimers.add(timer);
  }

  Future<DateTime?> _pickMinimalDate(BuildContext ctx, DateTime initial, DateTime first, DateTime last) async {
    DateTime displayedMonth = DateTime(initial.year, initial.month);
    DateTime selectedDate = initial;

    return await showDialog<DateTime>(
      context: ctx,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (context) {
        return Theme(
          data: ThemeData.light(useMaterial3: true).copyWith(
            splashFactory: NoSplash.splashFactory,
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
                "",
                "January",
                "February",
                "March",
                "April",
                "May",
                "June",
                "July",
                "August",
                "September",
                "October",
                "November",
                "December",
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
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 20, offset: const Offset(0, 6))],
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
                              onSelected: (val) => setDialogState(() => displayedMonth = DateTime(year, val)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    monthNames[month],
                                    style: const TextStyle(
                                      fontFamily: kAppFont,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF0F172A),
                                    ),
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
                              onSelected: (val) => setDialogState(() => displayedMonth = DateTime(val, month)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    "$year",
                                    style: const TextStyle(
                                      fontFamily: kAppFont,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF0F172A),
                                    ),
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
                          Text(
                            "Mo",
                            style: TextStyle(fontFamily: kAppFont, fontSize: 10.0, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8)),
                          ),
                          Text(
                            "Tu",
                            style: TextStyle(fontFamily: kAppFont, fontSize: 10.0, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8)),
                          ),
                          Text(
                            "We",
                            style: TextStyle(fontFamily: kAppFont, fontSize: 10.0, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8)),
                          ),
                          Text(
                            "Th",
                            style: TextStyle(fontFamily: kAppFont, fontSize: 10.0, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8)),
                          ),
                          Text(
                            "Fr",
                            style: TextStyle(fontFamily: kAppFont, fontSize: 10.0, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8)),
                          ),
                          Text(
                            "Sa",
                            style: TextStyle(fontFamily: kAppFont, fontSize: 10.0, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8)),
                          ),
                          Text(
                            "Su",
                            style: TextStyle(fontFamily: kAppFont, fontSize: 10.0, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8)),
                          ),
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
                          final bool isDisabled =
                              currentCellDate.isBefore(DateTime(first.year, first.month, first.day)) ||
                              currentCellDate.isAfter(DateTime(last.year, last.month, last.day));
                          final bool isSelected =
                              currentCellDate.year == selectedDate.year &&
                              currentCellDate.month == selectedDate.month &&
                              currentCellDate.day == selectedDate.day;

                          return GestureDetector(
                            onTap: isDisabled ? null : () => setDialogState(() => selectedDate = currentCellDate),
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
                                  color: isDisabled
                                      ? const Color(0xFFCBD5E1)
                                      : isSelected
                                      ? Colors.white
                                      : const Color(0xFF1E293B),
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
                            ),
                            child: const Text(
                              "Cancel",
                              style: TextStyle(fontFamily: kAppFont, fontSize: 10.5, color: Color(0xFF64748B)),
                            ),
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
                            ),
                            child: const Text(
                              "OK",
                              style: TextStyle(fontFamily: kAppFont, fontSize: 10.5, fontWeight: FontWeight.w700),
                            ),
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

  void _openFigmaSelectorDialog({
    required String title,
    required List<Map<String, dynamic>> items,
    required String? selectedCode,
    required Function(String code, String label) onSelect,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Container(
            width: 420,
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.65),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 10))],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontFamily: kAppFont, fontSize: 14.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                      ),
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
                    separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0xFFF8FAFC)),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final bool isSelected = item["code"] == selectedCode;
                      return InkWell(
                        onTap: () {
                          onSelect(item["code"]!, item["label"]!);
                          Navigator.pop(context);
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFFF8FAFC) : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                item["icon"] as IconData,
                                size: 15,
                                color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  item["label"]!,
                                  style: TextStyle(
                                    fontFamily: kAppFont,
                                    fontSize: 12.5,
                                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                    color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF334155),
                                  ),
                                ),
                              ),
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
        );
      },
    );
  }

  Future<void> _openRequestLeaveDialog({Map<String, dynamic>? existingRecord}) async {
    if (!mounted || _isSubmittingLeave) return;
    if (existingRecord != null &&
        (_parseDmyDate(existingRecord['from_date']?.toString()) == null || _parseDmyDate(existingRecord['to_date']?.toString()) == null)) {
      _showAppleToast(
        'Original leave dates are unavailable. Refresh the history.',
        icon: CupertinoIcons.exclamationmark_triangle_fill,
      );
      return;
    }
    final existingReason = _resolveLeaveReason(existingRecord?["reasonCode"] ?? existingRecord?["reason_id"],
        existingRecord?["reason"] ?? existingRecord?["leave_reason"]);
    String? selectedReasonCode = existingReason?["code"]?.toString();
    final originalReasonLabel = existingRecord?["reason"]?.toString().trim() ?? "";
    String selectedReasonLabel = existingReason?["label"]?.toString()
        ?? (originalReasonLabel.isNotEmpty && originalReasonLabel != "--"
            ? originalReasonLabel : "--Select leave reason--");

    String? selectedTypeCode = existingRecord?["typeCode"];
    String selectedTypeLabel = selectedTypeCode != null
        ? _leaveTypes.firstWhere((t) => t["code"] == selectedTypeCode, orElse: () => {"label": "--Select leave type--"})["label"]!
        : "--Select leave type--";

    DateTime? fromDate = _parseDmyDate(existingRecord?["from_date"]) ?? DateTime.now();
    DateTime? toDate = _parseDmyDate(existingRecord?["to_date"]) ?? fromDate;

    final String originalFromDateStr = existingRecord?["from_date"] ?? _formatDate(fromDate);
    final String originalToDateStr = existingRecord?["to_date"] ?? _formatDate(toDate);

    String duration = existingRecord?["duration"] ?? (selectedTypeCode == "12" ? "2" : "1");
    String dayType = existingRecord?["dayType"] ?? "1";
    bool headquarterLeaveReq = existingRecord?["headquarter"] ?? false;
    final TextEditingController addressController = TextEditingController(text: existingRecord?["address"] ?? "");
    final TextEditingController remarkController = TextEditingController(text: existingRecord?["remark"] ?? "");

    String? validationError;

    try {
      await showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.4),
        builder: (context) {
          return Theme(
            data: ThemeData.light(useMaterial3: true).copyWith(
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
              builder: (context, setModalState) {
                double calculateDays() {
                  if (fromDate == null || toDate == null) return 0.0;
                  final start = DateTime.utc(fromDate!.year, fromDate!.month, fromDate!.day);
                  final end = DateTime.utc(toDate!.year, toDate!.month, toDate!.day);
                  final span = end.difference(start).inDays + 1;
                  if (span <= 0 || (selectedTypeCode == "12" && span != 1)) return 0.0;
                  return span.toDouble() - (duration == "2" || selectedTypeCode == "12" ? 0.5 : 0.0);
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
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 28, offset: const Offset(0, 14))],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 18, 14, 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      existingRecord != null ? "Edit Leave Request" : "Request Leave",
                                      style: const TextStyle(
                                        fontFamily: kAppFont,
                                        fontSize: 16.0,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      widget.currentUser["designation"] ?? "Teacher",
                                      style: const TextStyle(
                                        fontFamily: kAppFont,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      "NIC ID: ${_getResolvedNicId()}",
                                      style: const TextStyle(
                                        fontFamily: kAppFont,
                                        fontSize: 11.0,
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(CupertinoIcons.xmark, size: 18, color: Color(0xFF64748B)),
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
                                            style: const TextStyle(
                                              fontFamily: kAppFont,
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFFDC2626),
                                            ),
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
                                      border: Border.all(
                                        color: selectedReasonCode == null && validationError != null
                                            ? const Color(0xFFDC2626)
                                            : const Color(0xFFCBD5E1),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            selectedReasonLabel,
                                            style: TextStyle(
                                              fontFamily: kAppFont,
                                              fontSize: 12.5,
                                              color: selectedReasonCode == null ? const Color(0xFF94A3B8) : const Color(0xFF0F172A),
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
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
                                          if (code == "12") {
                                            duration = "2";
                                            toDate = fromDate;
                                          }
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
                                      border: Border.all(
                                        color: selectedTypeCode == null && validationError != null
                                            ? const Color(0xFFDC2626)
                                            : const Color(0xFFCBD5E1),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            selectedTypeLabel,
                                            style: TextStyle(
                                              fontFamily: kAppFont,
                                              fontSize: 12.5,
                                              color: selectedTypeCode == null ? const Color(0xFF94A3B8) : const Color(0xFF0F172A),
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
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
                                              final picked = await _pickMinimalDate(
                                                context,
                                                fromDate ?? DateTime.now(),
                                                DateTime(2025),
                                                DateTime(2028),
                                              );
                                              if (picked != null && context.mounted) {
                                                setModalState(() {
                                                  fromDate = picked;
                                                  if (selectedTypeCode == "12") {
                                                    toDate = fromDate;
                                                  } else if (toDate != null && toDate!.isBefore(fromDate!)) {
                                                    toDate = fromDate;
                                                  }
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
                                                border: Border.all(color: const Color(0xFFCBD5E1)),
                                              ),
                                              child: Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Flexible(
                                                    child: Text(
                                                      fromDate == null ? "dd--mm--yyyy" : _formatDate(fromDate!),
                                                      style: const TextStyle(
                                                        fontFamily: kAppFont,
                                                        fontSize: 12.0,
                                                        color: Color(0xFF0F172A),
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  _buildLeaveAssetIcon(size: 15, color: const Color(0xFF0F172A)),
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
                                            onTap: selectedTypeCode == "12"
                                                ? null
                                                : () async {
                                                    final minAllowed = fromDate ?? DateTime(2025);
                                                    final picked = await _pickMinimalDate(
                                                      context,
                                                      toDate ?? minAllowed,
                                                      minAllowed,
                                                      DateTime(2028),
                                                    );
                                                    if (picked != null && context.mounted) {
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
                                                color: selectedTypeCode == "12" ? const Color(0xFFF1F5F9) : Colors.white,
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: const Color(0xFFCBD5E1)),
                                              ),
                                              child: Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Flexible(
                                                    child: Text(
                                                      toDate == null ? "dd--mm--yyyy" : _formatDate(toDate!),
                                                      style: TextStyle(
                                                        fontFamily: kAppFont,
                                                        fontSize: 12.0,
                                                        color: selectedTypeCode == "12" ? const Color(0xFF94A3B8) : const Color(0xFF0F172A),
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  _buildLeaveAssetIcon(
                                                    size: 15,
                                                    color: selectedTypeCode == "12" ? const Color(0xFF94A3B8) : const Color(0xFF0F172A),
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
                                                    if (selectedTypeCode == "12") {
                                                      duration = "2";
                                                      toDate = fromDate;
                                                    }
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
                                                      style: const TextStyle(
                                                        fontFamily: kAppFont,
                                                        fontSize: 12.5,
                                                        color: Color(0xFF0F172A),
                                                      ),
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
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF8FAFC),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: const Color(0xFFCBD5E1)),
                                            ),
                                            child: Text(
                                              calculatedDays % 1 == 0 ? calculatedDays.toInt().toString() : calculatedDays.toString(),
                                              style: const TextStyle(
                                                fontFamily: kAppFont,
                                                fontSize: 13.0,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF0F172A),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                if (duration == "2" || selectedTypeCode == "12") ...[
                                  const SizedBox(height: 12),
                                  _buildFieldLabel("Day Type *"),
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      _openFigmaSelectorDialog(
                                        title: "Select Day Type",
                                        items: _dayTypeOptions,
                                        selectedCode: dayType,
                                        onSelect: (code, label) => setModalState(() => dayType = code),
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
                                RadioGroup<bool>(
                                  groupValue: headquarterLeaveReq,
                                  onChanged: (value) => setModalState(() => headquarterLeaveReq = value ?? false),
                                  child: Row(
                                    children: [
                                      Row(
                                        children: [
                                          Radio<bool>(value: true, activeColor: const Color(0xFF0F172A)),
                                          const Text(
                                            "Yes",
                                            style: TextStyle(
                                              fontFamily: kAppFont,
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF0F172A),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(width: 20),
                                      Row(
                                        children: [
                                          Radio<bool>(value: false, activeColor: const Color(0xFF0F172A)),
                                          const Text(
                                            "No",
                                            style: TextStyle(
                                              fontFamily: kAppFont,
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF0F172A),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
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
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                          color: addressController.text.trim().isEmpty && validationError != null
                                              ? const Color(0xFFDC2626)
                                              : const Color(0xFFCBD5E1),
                                        ),
                                      ),
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
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.all(Radius.circular(8)),
                                      borderSide: BorderSide(color: Color(0xFFCBD5E1)),
                                    ),
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
                                ),
                                child: const Text(
                                  "Cancel",
                                  style: TextStyle(
                                    fontFamily: kAppFont,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              ElevatedButton(
                                onPressed: () async {
                                  if (_isSubmittingLeave) return;
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

                                  if (toDate!.isBefore(fromDate!)) {
                                    setModalState(() => validationError = "To date cannot precede From date.");
                                    return;
                                  }
                                  if (existingRecord != null && !RegExp(r'^\d+$').hasMatch((existingRecord['sNo'] ?? '').toString())) {
                                    setModalState(
                                      () => validationError = "This leave has no valid portal serial number. Refresh history first.",
                                    );
                                    return;
                                  }

                                  if (calculatedDays <= 0) {
                                    setModalState(() => validationError = "Check the leave dates. HCL must use one date.");
                                    return;
                                  }
                                  final String finalType = _leaveTypes.firstWhere((t) => t["code"] == selectedTypeCode)["short"];
                                  final String finalFull = _leaveTypes.firstWhere((t) => t["code"] == selectedTypeCode)["label"];
                                  final String formattedDays = calculatedDays % 1 == 0
                                      ? calculatedDays.toInt().toString()
                                      : calculatedDays.toString();

                                  bool? confirmAction = await showDialog<bool>(
                                    context: context,
                                    barrierDismissible: false,
                                    builder: (BuildContext ctx) {
                                      return Dialog(
                                        backgroundColor: Colors.transparent,
                                        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
                                        child: Container(
                                          width: 380,
                                          padding: const EdgeInsets.all(22),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(16),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withValues(alpha: 0.15),
                                                blurRadius: 24,
                                                offset: const Offset(0, 10),
                                              ),
                                            ],
                                          ),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: const [
                                                  Icon(CupertinoIcons.exclamationmark_triangle_fill, color: Color(0xFFF59E0B), size: 20),
                                                  SizedBox(width: 8),
                                                  Text(
                                                    "Confirm Leave Apply",
                                                    style: TextStyle(
                                                      fontFamily: kAppFont,
                                                      fontSize: 16.0,
                                                      fontWeight: FontWeight.w800,
                                                      color: Color(0xFF0F172A),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 14),
                                              const Text(
                                                "Please review your leave details carefully. Once submitted, it will be forwarded to your reporting officer.",
                                                style: TextStyle(fontFamily: kAppFont, fontSize: 12.0, color: Color(0xFF475569)),
                                              ),
                                              const SizedBox(height: 14),
                                              Container(
                                                padding: const EdgeInsets.all(12),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFF8FAFC),
                                                  borderRadius: BorderRadius.circular(8),
                                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                                ),
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      "Type: $finalFull",
                                                      style: const TextStyle(
                                                        fontFamily: kAppFont,
                                                        fontSize: 12.0,
                                                        fontWeight: FontWeight.w600,
                                                        color: Color(0xFF0F172A),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      "Date: ${_formatDate(fromDate!)} to ${_formatDate(toDate!)}",
                                                      style: const TextStyle(
                                                        fontFamily: kAppFont,
                                                        fontSize: 12.0,
                                                        fontWeight: FontWeight.w600,
                                                        color: Color(0xFF0F172A),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      "Total: $formattedDays Days",
                                                      style: const TextStyle(
                                                        fontFamily: kAppFont,
                                                        fontSize: 12.0,
                                                        fontWeight: FontWeight.w800,
                                                        color: Color(0xFF16A34A),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(height: 22),
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.end,
                                                children: [
                                                  OutlinedButton(
                                                    onPressed: () => Navigator.pop(ctx, false),
                                                    style: OutlinedButton.styleFrom(
                                                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                                    ),
                                                    child: const Text(
                                                      "Review",
                                                      style: TextStyle(
                                                        fontFamily: kAppFont,
                                                        fontSize: 12.0,
                                                        fontWeight: FontWeight.w600,
                                                        color: Color(0xFF0F172A),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  ElevatedButton(
                                                    onPressed: () => Navigator.pop(ctx, true),
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor: const Color(0xFF0F172A),
                                                      foregroundColor: Colors.white,
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                                      elevation: 0,
                                                    ),
                                                    child: const Text(
                                                      "Confirm & Apply",
                                                      style: TextStyle(fontFamily: kAppFont, fontSize: 12.0, fontWeight: FontWeight.w700),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  );

                                  if (!context.mounted || !mounted || confirmAction != true || _isSubmittingLeave) return;
                                  _isSubmittingLeave = true;

                                  final navigator = Navigator.of(context, rootNavigator: true);
                                  final formRoute = ModalRoute.of(context);
                                  final loaderRoute = DialogRoute<void>(
                                    context: context,
                                    barrierDismissible: false,
                                    builder: (_) => const PopScope(
                                      canPop: false,
                                      child: Center(child: CircularProgressIndicator(color: Colors.white)),
                                    ),
                                  );
                                  void closeLoader() {
                                    if (navigator.mounted && loaderRoute.isActive) navigator.removeRoute(loaderRoute);
                                  }

                                  try {
                                    unawaited(navigator.push(loaderRoute));
                                    final payload = <String, dynamic>{
                                      "reason_id": selectedReasonCode,
                                      "leave_type_id": selectedTypeCode,
                                      "from_date": _formatDate(fromDate!),
                                      "to_date": _formatDate(toDate!),
                                      "from_duration": duration == "2" && (DateUtils.isSameDay(fromDate, toDate) || dayType == "2") ? "Half" : "Full",
                                      "to_duration": duration == "2" && (DateUtils.isSameDay(fromDate, toDate) || dayType == "1") ? "Half" : "Full",
                                      "day_type": duration == "2" || selectedTypeCode == "12" ? dayType : null,
                                      "station_leave": headquarterLeaveReq ? "Y" : "N",
                                      "address": addressController.text.trim().isEmpty ? "At Home" : addressController.text.trim(),
                                      "remark": remarkController.text.trim().isEmpty ? "Leave Application" : remarkController.text.trim(),
                                      "confirmed": true,
                                    };

                                    if (existingRecord != null) {
                                      final String recordId = (existingRecord["sNo"] ?? "").toString().trim();
                                      payload["record_id"] = recordId;
                                      payload["sNo"] = recordId;
                                      payload["original_from_date"] = originalFromDateStr;
                                      payload["original_to_date"] = originalToDateStr;
                                    }

                                    final response = await StaffLoginService.applyLeave(payload);

                                    closeLoader();
                                    if (!context.mounted || !mounted) return;

                                    if (response['success'] == true) {
                                      if (existingRecord != null) {
                                        _acceptedLeaveTiming.remove(_leaveTimingKey(
                                            existingRecord["typeCode"], originalFromDateStr, originalToDateStr));
                                      }
                                      // Retain the acknowledged submission count when the history grid omits it.
                                      _acceptedLeaveTiming[_leaveTimingKey(selectedTypeCode,
                                          _formatDate(fromDate!), _formatDate(toDate!))] = {
                                        "days": calculatedDays,
                                        "duration": duration,
                                        "dayType": duration == "2" ? dayType : null,
                                      };
                                      if (navigator.mounted && formRoute?.isCurrent == true) navigator.pop();
                                      _showAppleToast(
                                        response['message'] ??
                                            (existingRecord != null ? "Leave updated successfully" : "$finalType applied successfully"),
                                      );
                                      // 🚀 FIX: Stay on whichever tab (Pending/All) the user is currently
                                      // viewing instead of always forcing a full "all" reload — keeps the
                                      // fast Pending tab fast even right after an apply/edit action.
                                      await _loadLiveLeaveHistory(filter: _activeFilter, refresh: true);
                                    } else {
                                      setModalState(() => validationError = response['message'] ?? "Leave request failed on server.");
                                    }
                                  } catch (e) {
                                    closeLoader();
                                    if (!context.mounted || !mounted) return;
                                    setModalState(
                                      () => validationError = "Request result could not be confirmed. Refresh history before retrying.",
                                    );
                                  } finally {
                                    closeLoader();
                                    _isSubmittingLeave = false;
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0F172A),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                  elevation: 0,
                                ),
                                child: Text(
                                  existingRecord != null ? "Update Request" : "Submit Request",
                                  style: const TextStyle(fontFamily: kAppFont, fontSize: 12.5, fontWeight: FontWeight.w700),
                                ),
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
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      addressController.dispose();
      remarkController.dispose();
    }
  }

  Widget _buildFieldLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text(
        label,
        style: const TextStyle(fontFamily: kAppFont, fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF334155)),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return "${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year}";
  }

  @override
  Widget build(BuildContext context) {
    // 🚀 Backend already returns records for whichever filter was fetched
    // (pending-only vs full "all"), so no extra client-side status filtering
    // is needed here anymore — just render whatever _myLeaveHistory holds.
    final List<Map<String, dynamic>> filteredList = _myLeaveHistory;

    final displayedLeaves = _showAllLeaves ? filteredList : filteredList.take(3).toList();

    return RefreshIndicator(
      color: const Color(0xFF0F172A),
      backgroundColor: Colors.white,
      onRefresh: () => _loadLiveLeaveHistory(filter: _activeFilter, refresh: true),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: const Icon(CupertinoIcons.paperplane_fill, color: Color(0xFF0F172A), size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                "Apply New Leave",
                                style: TextStyle(
                                  fontFamily: kAppFont,
                                  fontSize: 14.0,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                "Submit casual, medical or special leaves.",
                                style: TextStyle(fontFamily: kAppFont, fontSize: 11.0, color: Color(0xFF64748B)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => _openRequestLeaveDialog(),
                          style: ButtonStyle(
                            backgroundColor: WidgetStateProperty.all(const Color(0xFF0F172A)),
                            foregroundColor: WidgetStateProperty.all(Colors.white),
                            shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                            padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 12, vertical: 9)),
                            elevation: WidgetStateProperty.all(0),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(CupertinoIcons.add, size: 13, color: Colors.white),
                              SizedBox(width: 4),
                              Text(
                                "Request Leave",
                                style: TextStyle(fontFamily: kAppFont, fontSize: 11.5, fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
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
                                  _buildLeaveAssetIcon(size: 18, color: const Color(0xFF0F172A)),
                                  const SizedBox(width: 8),
                                  const Text(
                                    "Recent leave requests",
                                    style: TextStyle(
                                      fontFamily: kAppFont,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.all(2.5),
                                decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8)),
                                child: Row(
                                  children: [
                                    // 🚀 FIX: "All" tab now actually triggers the full,
                                    // multi-page "All Applications" portal scrape (with
                                    // the existing _isLoadingHistory spinner) instead of
                                    // just relabelling the already-loaded Pending list.
                                    GestureDetector(
                                      onTap: () {
                                        if (_activeFilter != "pending") {
                                          _loadLiveLeaveHistory(filter: "pending"); // fast fetch (cache/portal default)
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: _activeFilter == "pending" ? Colors.white : Colors.transparent,
                                          borderRadius: BorderRadius.circular(6),
                                          boxShadow: _activeFilter == "pending"
                                              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4)]
                                              : null,
                                        ),
                                        child: Text(
                                          "Pending",
                                          style: TextStyle(
                                            fontFamily: kAppFont,
                                            fontSize: 11,
                                            fontWeight: _activeFilter == "pending" ? FontWeight.w700 : FontWeight.w500,
                                            color: _activeFilter == "pending" ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                                          ),
                                        ),
                                      ),
                                    ),
                                    // All ab baad me (right side)
                                    GestureDetector(
                                      onTap: () {
                                        if (_activeFilter != "all") {
                                          _loadLiveLeaveHistory(filter: "all"); // Full history; reuse fresh cache when available.
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: _activeFilter == "all" ? Colors.white : Colors.transparent,
                                          borderRadius: BorderRadius.circular(6),
                                          boxShadow: _activeFilter == "all"
                                              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4)]
                                              : null,
                                        ),
                                        child: Text(
                                          "All",
                                          style: TextStyle(
                                            fontFamily: kAppFont,
                                            fontSize: 11,
                                            fontWeight: _activeFilter == "all" ? FontWeight.w700 : FontWeight.w500,
                                            color: _activeFilter == "all" ? const Color(0xFF0F172A) : const Color(0xFF64748B),
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
                        const Divider(height: 1, color: Color(0xFFF1F5F9)),
                        _isLoadingHistory
                            ? const Padding(
                                padding: EdgeInsets.symmetric(vertical: 36),
                                child: Center(child: CupertinoActivityIndicator()),
                              )
                            : _historyError != null
                            ? Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  children: [
                                    Text(
                                      _historyError!,
                                      style: const TextStyle(fontFamily: kAppFont, color: Color(0xFFDC2626)),
                                    ),
                                    TextButton(
                                      onPressed: () => _loadLiveLeaveHistory(filter: _activeFilter, refresh: true),
                                      child: const Text('Retry'),
                                    ),
                                  ],
                                ),
                              )
                            : displayedLeaves.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (_activeFilter == "pending") ...[
                                        Container(
                                          width: 52,
                                          height: 52,
                                          decoration: const BoxDecoration(color: Color(0xFFECFDF5), shape: BoxShape.circle),
                                          child: const Icon(CupertinoIcons.checkmark_alt, size: 28, color: Color(0xFF10B981)),
                                        ),
                                        const SizedBox(height: 12),
                                      ],
                                      Text(
                                        _activeFilter == "pending" ? "No pending leaves" : "No leave records found.",
                                        style: const TextStyle(fontFamily: kAppFont, fontSize: 12.5,
                                            fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : Column(
                                children: [
                                  LayoutBuilder(builder: (context, box) {
                                    Widget leaveItem(BuildContext context, int index) {
                                      final item = displayedLeaves[index];
                                      final String status = item["status"];
                                      final bool isPending = status.toLowerCase() == "pending";
                                      final double daysVal = (item["days"] as num?)?.toDouble() ?? 0.0;
                                      final String daysLabel = daysVal <= 0
                                          ? "--"
                                          : daysVal % 1 == 0
                                          ? "${daysVal.toInt()} ${daysVal == 1 ? 'day' : 'days'}"
                                          : "$daysVal days";
                                      final String durationTypeLabel = daysVal > 0
                                          ? (daysVal % 1 != 0 ? "Half day" : "Full day")
                                          : item["duration"] == "2" ? "Half day"
                                          : item["duration"] == "1" ? "Full day" : "";

                                      Color statusBg = const Color(0xFFFEF3C7);
                                      Color statusFg = const Color(0xFFD97706);

                                      if (status == "Approved") {
                                        statusBg = const Color(0xFFDCFCE7);
                                        statusFg = const Color(0xFF16A34A);
                                      } else if (status.toLowerCase().contains("reject")) {
                                        statusBg = const Color(0xFFFEE2E2);
                                        statusFg = const Color(0xFFDC2626);
                                      } else if (status.toLowerCase().contains("cancel")) {
                                        statusBg = const Color(0xFFF1F5F9);
                                        statusFg = const Color(0xFF64748B);
                                      }

                                      final String itemId = item["id"]?.toString() ?? "";
                                      final bool isDownloading = _generatingPdfId == itemId;

                                      return Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          children: [
                                            Container(
                                              width: 38,
                                              height: 38,
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF1F5F9),
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: Center(
                                                child: Text(
                                                  item["short"],
                                                  style: const TextStyle(
                                                    fontFamily: kAppFont,
                                                    fontSize: 11.5,
                                                    fontWeight: FontWeight.w800,
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
                                                  Row(
                                                    children: [
                                                      Icon(item["icon"] as IconData, size: 12, color: const Color(0xFF64748B)),
                                                      const SizedBox(width: 4),
                                                      Expanded(
                                                        child: Text(
                                                          item["typeName"],
                                                          style: const TextStyle(
                                                            fontFamily: kAppFont,
                                                            fontSize: 12.0,
                                                            fontWeight: FontWeight.w700,
                                                            color: Color(0xFF0F172A),
                                                          ),
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 3),
                                                  Row(
                                                    children: [
                                                      _buildLeaveAssetIcon(size: 13, color: const Color(0xFF64748B)),
                                                      const SizedBox(width: 5),
                                                      Expanded(
                                                        child: Text(
                                                          item["dateRange"],
                                                          style: const TextStyle(
                                                            fontFamily: kAppFont,
                                                            fontSize: 10.5,
                                                            fontWeight: FontWeight.w500,
                                                            color: Color(0xFF64748B),
                                                          ),
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
                                                        child: Text.rich(
                                                          TextSpan(children: [
                                                            TextSpan(text: daysLabel),
                                                            if (durationTypeLabel.isNotEmpty) ...[
                                                              const TextSpan(text: "  •  ", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Color(0xFF94A3B8))),
                                                              TextSpan(text: durationTypeLabel),
                                                            ],
                                                          ]),
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
                                                          style: TextStyle(
                                                            fontFamily: kAppFont,
                                                            fontSize: 9.5,
                                                            fontWeight: FontWeight.w700,
                                                            color: statusFg,
                                                          ),
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
                                                    onTap: () => _openRequestLeaveDialog(existingRecord: item),
                                                    borderRadius: BorderRadius.circular(8),
                                                    child: Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFF0F172A),
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                      child: const Text(
                                                        "Edit",
                                                        style: TextStyle(
                                                          fontFamily: kAppFont,
                                                          fontSize: 11.0,
                                                          fontWeight: FontWeight.w600,
                                                          color: Colors.white,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                ],
                                                InkWell(
                                                  onTap: isDownloading ? null : () => _openInAppPdfViewer(item),
                                                  borderRadius: BorderRadius.circular(8),
                                                  child: Container(
                                                    width: 32,
                                                    height: 31,
                                                    alignment: Alignment.center,
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFFF1F5F9),
                                                      borderRadius: BorderRadius.circular(8),
                                                      border: Border.all(
                                                        color: isDownloading ? const Color(0xFF0F172A) : const Color(0xFFCBD5E1),
                                                      ),
                                                    ),
                                                    child: isDownloading
                                                        ? IosDownloadProgressIndicator(
                                                            size: 16,
                                                            progress: _downloadProgress,
                                                            color: const Color(0xFF007AFF),
                                                          )
                                                        : const Icon(CupertinoIcons.arrow_down_to_line, size: 15, color: Color(0xFF0F172A)),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      );
                                    }
                                    return ListView.separated(shrinkWrap: true,
                                      physics: const NeverScrollableScrollPhysics(),
                                      padding: const EdgeInsets.symmetric(vertical: 2),
                                      itemCount: displayedLeaves.length,
                                      separatorBuilder: (_, __) => const Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),
                                      itemBuilder: leaveItem);
                                  }),
                                  if (filteredList.length > 3)
                                    Container(
                                      width: double.infinity,
                                      decoration: const BoxDecoration(
                                        border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
                                      ),
                                      child: TextButton(
                                        onPressed: () => setState(() => _showAllLeaves = !_showAllLeaves),
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                          shape: const RoundedRectangleBorder(
                                            borderRadius: BorderRadius.only(
                                              bottomLeft: Radius.circular(14),
                                              bottomRight: Radius.circular(14),
                                            ),
                                          ),
                                        ),
                                        child: Text(
                                          _showAllLeaves ? "Show Less" : "View All ${filteredList.length} Leaves",
                                          style: const TextStyle(
                                            fontFamily: kAppFont,
                                            fontSize: 12.0,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF2563EB),
                                          ),
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
            ),
          ),
        ],
      ),
    );
  }
}

// 🍏 iOS 18 Safari Style Clockwise Filling Progress Ring with Downward Arrow
class IosDownloadProgressIndicator extends StatelessWidget {
  final double size;
  final double progress; // 0.0 to 1.0 (Clockwise fill)
  final Color color;
  final Color? trackColor;

  const IosDownloadProgressIndicator({
    super.key,
    this.size = 17.0,
    required this.progress,
    this.color = const Color(0xFF007AFF), // Official Apple Blue
    this.trackColor,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: progress.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      builder: (context, animatedValue, _) {
        return SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _IosProgressRingPainter(
              progress: animatedValue,
              color: color,
              trackColor: trackColor ?? color.withValues(alpha: 0.18),
            ),
          ),
        );
      },
    );
  }
}

class _IosProgressRingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color trackColor;

  _IosProgressRingPainter({required this.progress, required this.color, required this.trackColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final strokeWidth = size.width * 0.125;
    final radius = (size.width - strokeWidth) / 2;

    // 1. Faint Outer Full Track Ring
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, trackPaint);

    // 2. Real Clockwise Progress Arc (Starts exactly at 12 o'clock)
    if (progress > 0.02) {
      final progressPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = strokeWidth;

      const double startAngle = -1.5707963267948966; // -pi / 2 (Top 12 o'clock)
      final double sweepAngle = progress * 6.283185307179586; // progress * 2 * pi

      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, sweepAngle, false, progressPaint);
    }

    // 3. Static Center iOS Downward Download Arrow
    final arrowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = strokeWidth * 0.95;

    final arrowTop = center.dy - (size.height * 0.20);
    final arrowBottom = center.dy + (size.height * 0.20);
    final wingSpanX = size.width * 0.16;
    final wingSpanY = size.height * 0.14;

    final arrowPath = Path();
    arrowPath.moveTo(center.dx, arrowTop);
    arrowPath.lineTo(center.dx, arrowBottom);

    arrowPath.moveTo(center.dx - wingSpanX, arrowBottom - wingSpanY);
    arrowPath.lineTo(center.dx, arrowBottom);
    arrowPath.lineTo(center.dx + wingSpanX, arrowBottom - wingSpanY);

    canvas.drawPath(arrowPath, arrowPaint);
  }

  @override
  bool shouldRepaint(covariant _IosProgressRingPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color || oldDelegate.trackColor != trackColor;
  }
}

// 📄 Ultra-Modern iOS Style PDF Preview Screen (Matched with App Dashboard Theme)
class ModernLeavePdfPreviewScreen extends StatelessWidget {
  final Uint8List pdfBytes;
  final Map<String, dynamic> item;

  const ModernLeavePdfPreviewScreen({super.key, required this.pdfBytes, required this.item});

  @override
  Widget build(BuildContext context) {
    final String leaveName = item["typeName"]?.toString() ?? "Leave Application";
    final String dateRange = item["dateRange"]?.toString() ?? "";
    final String shortType = item["short"]?.toString() ?? "Leave";

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
        backgroundColor: const Color(0xFFF8FAFC),
        // 🛑 FIX 1: AppBar ko bilkul transparent kar diya taaki gradient top tak flow ho
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          leadingWidth: 54,
          leading: Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Center(
              child: InkWell(
                onTap: () => Navigator.pop(context),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: [
                      BoxShadow(color: const Color(0xFF0F172A).withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2)),
                    ],
                  ),
                  child: const Icon(CupertinoIcons.chevron_back, size: 18, color: Color(0xFF0F172A)),
                ),
              ),
            ),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                leaveName,
                style: const TextStyle(fontFamily: kAppFont, fontSize: 14.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 1),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(4)),
                    child: const Text(
                      "Official Proforma",
                      style: TextStyle(fontFamily: kAppFont, fontSize: 9.5, fontWeight: FontWeight.w700, color: Color(0xFF2563EB)),
                    ),
                  ),
                  if (dateRange.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(
                      dateRange,
                      style: const TextStyle(fontFamily: kAppFont, fontSize: 10.5, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                    ),
                  ],
                ],
              ),
            ],
          ),
          actions: const [SizedBox(width: 14)],
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(height: 1, thickness: 0.8, color: Color(0xFFE2E8F0)),
          ),
        ),
        body: AdaptiveWorkspace(background: true, child: Stack(
          fit: StackFit.expand,
          children: [
            // 🎨 Exact Dashboard Linear Gradient & Ambient Glow Spheres
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
                          colors: [const Color(0xFFBAE6FD).withValues(alpha: 0.35), const Color(0xFFBAE6FD).withValues(alpha: 0.0)],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: -50,
                    top: 120,
                    child: Container(
                      width: 260,
                      height: 260,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [const Color(0xFFFDE68A).withValues(alpha: 0.35), const Color(0xFFFDE68A).withValues(alpha: 0.0)],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 📄 PDF Preview with Transparent Scroll View
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 74.0),
                child: PdfPreview(
                  build: (format) async => pdfBytes,
                  allowSharing: false,
                  allowPrinting: false,
                  canChangeOrientation: false,
                  canChangePageFormat: false,
                  useActions: false,
                  initialPageFormat: PdfPageFormat.a4,
                  pdfFileName: "Leave_Application_${item['short']}_${item['id']}.pdf",
                  loadingWidget: const Center(child: CupertinoActivityIndicator(radius: 14, color: Color(0xFF0F172A))),
                  scrollViewDecoration: const BoxDecoration(color: Colors.transparent),
                  pdfPreviewPageDecoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(color: const Color(0xFF0F172A).withValues(alpha: 0.12), blurRadius: 16, offset: const Offset(0, 4)),
                    ],
                  ),
                ),
              ),
            ),

            // 🛑 FIX 2: Zero Container for Buttons (No outer white box, direct floating buttons)
            Positioned(
              left: 20,
              right: 20,
              bottom: 16,
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    // 🖨️ Print — Pure Black Button with White Circle Badge
                    Expanded(
                      child: _IosActionButton(
                        label: "Print",
                        iconAsset: 'assets/icons/print.png',
                        fallbackIcon: CupertinoIcons.printer,
                        isBlack: true,
                        onTap: () async {
                          HapticFeedback.lightImpact();
                          await Printing.layoutPdf(onLayout: (_) async => pdfBytes, name: "Leave_Application_$shortType.pdf");
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    // 🚀 Share — Pure White Button with Vibrant Apple Blue Content
                    Expanded(
                      child: _IosActionButton(
                        label: "Share",
                        iconAsset: 'assets/icons/share.png',
                        fallbackIcon: CupertinoIcons.share,
                        isBlack: false,
                        onTap: () async {
                          HapticFeedback.lightImpact();
                          await Printing.sharePdf(bytes: pdfBytes, filename: "Leave_Application_$shortType.pdf");
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        )),
      ),
    );
  }
}

class _IosActionButton extends StatefulWidget {
  final String label;
  final String iconAsset;
  final IconData fallbackIcon;
  final bool isBlack;
  final VoidCallback onTap;

  const _IosActionButton({
    required this.label,
    required this.iconAsset,
    required this.fallbackIcon,
    required this.isBlack,
    required this.onTap,
  });

  @override
  State<_IosActionButton> createState() => _IosActionButtonState();
}

class _IosActionButtonState extends State<_IosActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    // 🎨 Button Background
    final Color bg = widget.isBlack ? const Color(0xFF000000) : Colors.white;

    // 🔵 Share button ke liye exact Apple Blue (#007AFF), Black button ke liye White
    final Color fg = widget.isBlack ? Colors.white : const Color(0xFF007AFF);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _pressed ? (widget.isBlack ? const Color(0xFF1C1C1E) : const Color(0xFFF0F7FF)) : bg,
            borderRadius: BorderRadius.circular(10),
            // White button par subtle crisp border
            border: widget.isBlack ? null : Border.all(color: _pressed ? const Color(0xFF007AFF) : const Color(0xFFE2E8F0), width: 1.0),
            boxShadow: [
              BoxShadow(
                color: widget.isBlack ? Colors.black.withValues(alpha: 0.12) : const Color(0xFF007AFF).withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 🖨️ Print button ke liye white circle badge
              if (widget.isBlack) ...[
                Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Image.asset(
                    widget.iconAsset,
                    width: 13,
                    height: 13,
                    fit: BoxFit.contain,
                    color: const Color(0xFF000000),
                    errorBuilder: (_, _, _) => const Icon(CupertinoIcons.printer, size: 13, color: Color(0xFF000000)),
                  ),
                ),
              ] else ...[
                // 🚀 Share button ke liye exact Apple Blue Icon
                Image.asset(
                  widget.iconAsset,
                  width: 18,
                  height: 18,
                  fit: BoxFit.contain,
                  color: fg,
                  errorBuilder: (_, _, _) => Icon(widget.fallbackIcon, size: 18, color: fg),
                ),
              ],
              const SizedBox(width: 7),
              // 📝 Text Label (Blue for Share, White for Print)
              Text(
                widget.label,
                style: TextStyle(fontFamily: kAppFont, fontSize: 12.5, fontWeight: FontWeight.w600, color: fg, letterSpacing: -0.2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
