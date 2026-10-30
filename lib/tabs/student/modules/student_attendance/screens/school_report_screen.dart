import 'package:shaladarpan/widgets/page_content_motion.dart';
import 'package:shaladarpan/widgets/adaptive_layout.dart';

// lib/tabs/student/modules/student_attendance/screens/school_report_screen.dart
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../attendance_pdf_icons.dart';
import '../widgets/attendance_page_header.dart';

import 'package:printing/printing.dart';
import 'package:shaladarpan/services/portals/shaladarpan/student_service.dart';

const String _font = 'PlusJakartaSans';
const List<String> _monthsShort = [
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
String _prettyDate(String portal) {
  final p = portal.split('/');
  if (p.length != 3) return portal;
  final d = int.tryParse(p[0]);
  final m = int.tryParse(p[1]);
  final y = int.tryParse(p[2]);
  if (d == null || m == null || y == null || m < 1 || m > 12) {
    return portal;
  }
  return '${d.toString().padLeft(2, '0')} '
      '${_monthsShort[m - 1]} $y';
}

class _ReportRow {
  final String className;
  final String section;
  final int boys;
  final int girls;
  final int absent;
  final int leave;
  const _ReportRow(
    this.className,
    this.section,
    this.boys,
    this.girls,
    this.absent,
    this.leave,
  );
  int get total => boys + girls + absent + leave;
  factory _ReportRow.fromJson(Map<String, dynamic> j) {
    int n(dynamic value) {
      final number = value is num ? value : num.tryParse('$value');
      if (number == null ||
          !number.isFinite ||
          number < 0 ||
          number != number.round()) {
        throw FormatException('Invalid attendance count: $value');
      }
      return number.toInt();
    }

    return _ReportRow(
      '${j['className'] ?? ''}',
      '${j['section'] ?? ''}',
      n(j['boys']),
      n(j['girls']),
      n(j['absent']),
      n(j['leave']),
    );
  }
}

class SchoolReportScreen extends StatefulWidget {
  final DateTime date;
  final Color? backgroundColor;
  const SchoolReportScreen({
    super.key,
    required this.date,
    this.backgroundColor,
  });

  @override
  State<SchoolReportScreen> createState() => _SchoolReportScreenState();
}

class _SchoolReportScreenState extends State<SchoolReportScreen> {
  bool _loading = true;
  String _error = '';
  double _progress = 0;
  String _loadingMessage = 'Fetching attendance records…';
  int _backendUnits = 0;
  Uint8List? _bytes;
  Map<String, dynamic>? _cachedReport;
  bool _loadInFlight = false;
  String get _portalDate {
    final d = widget.date;
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/'
        '${d.year}';
  }

  String get _fileName =>
      'attendance_report_'
      '${_portalDate.replaceAll('/', '-')}.pdf';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Uint8List?> _loadFirstAsset(List<String> paths) async {
    for (final path in paths) {
      try {
        final data = await rootBundle.load(path);
        final bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        // Optional decoration must be decodable by the PDF image provider.
        pw.MemoryImage(bytes);
        return bytes;
      } catch (error) {
        debugPrint('[SchoolReport] Optional asset skipped: $path ($error)');
      }
    }
    return null;
  }

  Uint8List? _portalImage(dynamic raw) {
    final value = raw?.toString().trim() ?? '';
    if (value.isEmpty) return null;
    try {
      final encoded = value.startsWith('data:')
          ? value.substring(value.indexOf(',') + 1)
          : value;
      final bytes = base64Decode(encoded.replaceAll(RegExp(r'\s+'), ''));
      pw.MemoryImage(bytes);
      return bytes;
    } catch (error) {
      debugPrint('[SchoolReport] Portal header image skipped: $error');
      return null;
    }
  }

  Future<void> _load() async {
    if (!mounted || _loadInFlight) return;
    _loadInFlight = true;
    var stage = 'report request';
    setState(() {
      _loading = true;
      _error = '';
      _progress = 0;
      _backendUnits = 0;
      _loadingMessage = 'Fetching attendance records…';
      _bytes = null;
    });
    try {
      final res =
          _cachedReport ??
          await StudentService.fetchSchoolReport(
            date: _portalDate,
            onProgress: (completed, total) {
              if (!mounted) return;
              setState(() {
                _backendUnits = total;
                _loadingMessage = total > 0
                    ? 'Preparing attendance report • $completed/$total'
                    : 'Fetching attendance records…';
                _progress = math.max(_progress, completed / (total + 3));
              });
            },
          );
      if (!mounted) return;
      if (res['success'] != true) {
        setState(() {
          _error =
              res['message']?.toString() ??
              'Could not load the attendance report.';
          _loading = false;
        });
        return;
      }
      stage = 'report data';
      final failedSections = res['failedSections'];
      if (failedSections is List && failedSections.isNotEmpty) {
        throw FormatException(
          'Incomplete portal report: ${failedSections.join(', ')}',
        );
      }
      final rawRows = res['rows'];
      if (rawRows is! List || rawRows.isEmpty) {
        throw const FormatException(
          'The report response contains no class rows.',
        );
      }
      final rows = rawRows.map((entry) {
        if (entry is! Map) {
          throw const FormatException(
            'The report contains an invalid class row.',
          );
        }
        return _ReportRow.fromJson(Map<String, dynamic>.from(entry));
      }).toList();
      _cachedReport = Map<String, dynamic>.from(res);
      stage = 'report images';
      setState(() {
        // Cached or legacy responses can skip streamed progress events.
        if (_backendUnits == 0) _backendUnits = rows.length + 4;
        _progress = _backendUnits / (_backendUnits + 3);
        _loadingMessage = 'Preparing report layout…';
      });
      Uint8List? leaveIcon;
      Uint8List? dateIcon;
      Uint8List? integratedLogo;
      Uint8List? schoolLogo;
      leaveIcon = await _loadFirstAsset(['assets/icons/report.png']);
      dateIcon = await _loadFirstAsset(['assets/icons/leave.png']);
      // Header logos intentionally omitted: retain readable school identity.
      if (!mounted) return;
      stage = 'PDF generation';
      setState(() {
        _progress = (_backendUnits + 1) / (_backendUnits + 3);
        _loadingMessage = 'Creating attendance PDF…';
      });
      final bytes = await _buildPdf(
        schoolName: '${res['schoolName'] ?? ''}'.trim(),
        village: '${res['village'] ?? ''}'.trim(),
        udise: '${res['udise'] ?? ''}'.trim(),
        nic: '${res['nic'] ?? ''}'.trim(),
        officeId: '${res['officeId'] ?? ''}'.trim(),
        peeoCode: '${res['peeoCode'] ?? ''}'.trim(),
        date: _prettyDate('${res['date'] ?? _portalDate}'),
        rows: rows,
        attendanceVerified:
            res['attendance_status'] == 'marked' &&
            res['attendance_verified'] == true &&
            (res['pendingSections'] is List &&
                (res['pendingSections'] as List).isEmpty),
        unknownPresent: int.tryParse('${res['unknownPresent'] ?? 0}') ?? 0,
        leaveIcon: leaveIcon,
        dateIcon: dateIcon,
        integratedLogo: integratedLogo,
        schoolLogo: schoolLogo,
      );
      if (!mounted) return;
      setState(() {
        // Reserve one operation for preview rasterization. The loader disappears
        // only when PdfPreview has renderable pages; PDF bytes alone are not ready.
        _progress = (_backendUnits + 2) / (_backendUnits + 3);
        _loadingMessage = 'Opening report preview…';
        _bytes = bytes;
        _loading = false;
      });
    } catch (error, stack) {
      debugPrint('[SchoolReport] Failed at $stage: $error');
      debugPrintStack(stackTrace: stack);
      if (!mounted) return;
      final detail = error.toString().trim();
      setState(() {
        _error = '$stage failed: $detail';
        _bytes = null;
        _loading = false;
      });
    } finally {
      _loadInFlight = false;
    }
  }

  Future<Uint8List> _buildPdf({
    required String schoolName,
    required String village,
    required String udise,
    required String nic,
    required String officeId,
    required String peeoCode,
    required String date,
    required List<_ReportRow> rows,
    required int unknownPresent,
    bool attendanceVerified = false,
    Uint8List? leaveIcon,
    Uint8List? dateIcon,
    Uint8List? integratedLogo,
    Uint8List? schoolLogo,
  }) async {
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(
        base: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
        italic: pw.Font.helveticaOblique(),
        boldItalic: pw.Font.helveticaBoldOblique(),
      ),
    );
    int sum(int Function(_ReportRow r) f) {
      return rows.fold(0, (a, r) => a + f(r));
    }

    final tBoys = sum((r) => r.boys);
    final tGirls = sum((r) => r.girls);
    final tAbsent = sum((r) => r.absent);
    final tLeave = sum((r) => r.leave);
    final tPresent = tBoys + tGirls + unknownPresent;
    final tTotal = tBoys + tGirls + tAbsent + tLeave;
    final attPct = tTotal == 0
        ? '0.0%'
        : '${(tPresent * 100.0 / tTotal).toStringAsFixed(1)}%';

    // Consistent, Sober Slate & Ink Palette
    const cInk = PdfColor.fromInt(0xFF0F172A);
    const cSlate = PdfColor.fromInt(0xFF475569);
    const cMuted = PdfColor.fromInt(0xFF64748B);
    const cLine = PdfColor.fromInt(0xFFCBD5E1);
    const cSoftLine = PdfColor.fromInt(0xFFE2E8F0);
    const cSurface = PdfColor.fromInt(0xFFF8FAFC);
    const cHeaderFill = PdfColor.fromInt(0xFFF1F5F9);
    const cTotalFill = PdfColor.fromInt(0xFFE2E8F0);

    // Crisp Vector SVG Icons (Never blurry on zoom or print)
    const registerSvgIcon =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">'
        '<rect width="24" height="24" rx="6" fill="#e2e8f0"/>'
        '<path d="M9 5H7a2 2 0 0 0-2 2v10a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V7a2 2 0 0 0-2-2h-2" fill="none" stroke="#0f172a" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/>'
        '<rect x="9" y="3" width="6" height="4" rx="1" fill="none" stroke="#0f172a" stroke-width="1.7"/>'
        '<path d="M9 13l2 2 4-4" fill="none" stroke="#059669" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/>'
        '</svg>';

    const calendarSvgIcon =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" width="20" height="20">'
        '<rect x="2.5" y="4" width="15" height="13.5" rx="2.5" fill="none" stroke="#475569" stroke-width="1.6"/>'
        '<path d="M2.5 8h15M6.5 2.5v3M13.5 2.5v3" fill="none" stroke="#475569" stroke-width="1.6" stroke-linecap="round"/>'
        '</svg>';

    const enrolledSvgIcon =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32" width="32" height="32">'
        '<rect width="32" height="32" rx="9" fill="#f1f5f9"/>'
        '<g transform="translate(5 5) scale(0.9166666667)" fill="none" stroke="#334155" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">'
        '<circle cx="9" cy="7" r="3.2"/>'
        '<path d="M3 20v-2.5C3 13.5 15 13.5 15 17.5V20"/>'
        '<circle cx="17.5" cy="8.5" r="2.5"/>'
        '<path d="M16 14.2c2.5.4 5 1.8 5 4.3V20"/>'
        '</g></svg>';

    const headers = [
      'Class',
      'Section',
      'Boys',
      'Girls',
      'Absent',
      'Leave',
      'Total',
    ];
    final border = pw.TableBorder.all(color: cLine, width: 0.55);

    pw.Widget cell(
      String text, {
      bool bold = false,
      PdfColor? color,
      double size = 10.0,
      double horizontal = 6,
      double vertical = 7.5,
    }) {
      return pw.Padding(
        padding: pw.EdgeInsets.symmetric(
          horizontal: horizontal,
          vertical: vertical,
        ),
        child: pw.Text(
          text,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize: size,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: color ?? cInk,
          ),
        ),
      );
    }

    pw.TableRow dataRow(_ReportRow r, int index) {
      return pw.TableRow(
        decoration: pw.BoxDecoration(
          color: index.isOdd ? cSurface : PdfColors.white,
        ),
        children: [
          cell(r.className, bold: true),
          cell(r.section.isEmpty ? '-' : r.section, color: cSlate),
          cell('${r.boys}'),
          cell('${r.girls}'),
          cell('${r.absent}'),
          cell('${r.leave}'),
          cell('${r.total}', bold: true),
        ],
      );
    }

    // Merged Total Row (6 columns matching the 7-column geometry above)
    final totalTable = pw.Table(
      border: border,
      columnWidths: {
        0: const pw.FlexColumnWidth(2.4),
        1: const pw.FlexColumnWidth(1),
        2: const pw.FlexColumnWidth(1),
        3: const pw.FlexColumnWidth(1),
        4: const pw.FlexColumnWidth(1),
        5: const pw.FlexColumnWidth(1),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: cTotalFill),
          children: [
            cell('Total', bold: true, size: 10.5),
            cell('$tBoys', bold: true, size: 10.5),
            cell('$tGirls', bold: true, size: 10.5),
            cell('$tAbsent', bold: true, size: 10.5),
            cell('$tLeave', bold: true, size: 10.5),
            cell('$tTotal', bold: true, size: 10.5),
          ],
        ),
      ],
    );

    final schoolTitle = nic.isEmpty || schoolName.contains('($nic)')
        ? schoolName
        : '$schoolName ($nic)';

    pw.Widget metaColumn(
      String label,
      String value, {
      bool showRightBorder = false,
    }) {
      return pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 5.5, horizontal: 8),
          decoration: showRightBorder
              ? const pw.BoxDecoration(
                  border: pw.Border(
                    right: pw.BorderSide(color: cSoftLine, width: 0.7),
                  ),
                )
              : null,
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.Text(
                '$label: ',
                style: const pw.TextStyle(fontSize: 8.5, color: cSlate),
              ),
              pw.Text(
                value.isEmpty ? '-' : value,
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: cInk,
                ),
              ),
            ],
          ),
        ),
      );
    }

    pw.Widget summaryItem(
      String label,
      String value,
      PdfColor color,
      pw.Widget icon, {
      bool showRightDivider = false,
    }) {
      return pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 11, vertical: 10),
          decoration: showRightDivider
              ? const pw.BoxDecoration(
                  border: pw.Border(
                    right: pw.BorderSide(color: cSoftLine, width: 0.7),
                  ),
                )
              : null,
          child: pw.Row(
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      label,
                      style: const pw.TextStyle(
                        fontSize: 8.5,
                        color: cSlate,
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      value,
                      style: pw.TextStyle(
                        fontSize: 13.5,
                        fontWeight: pw.FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 6),
              pw.SizedBox(width: 24, height: 24, child: icon),
            ],
          ),
        ),
      );
    }

    final verifiedBadge = attendanceVerified
        ? pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
            decoration: pw.BoxDecoration(
              color: const PdfColor.fromInt(0xFFECFDF5),
              borderRadius: pw.BorderRadius.circular(5),
              border: pw.Border.all(
                color: const PdfColor.fromInt(0xFFA7F3D0),
                width: 0.6,
              ),
            ),
            child: pw.Row(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.SvgImage(
                  svg:
                      '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 20 20"><path d="M10.00 1.00 L11.99 2.56 L14.50 2.21 L15.44 4.56 L17.79 5.50 L17.44 8.01 L19.00 10.00 L17.44 11.99 L17.79 14.50 L15.44 15.44 L14.50 17.79 L11.99 17.44 L10.00 19.00 L8.01 17.44 L5.50 17.79 L4.56 15.44 L2.21 14.50 L2.56 11.99 L1.00 10.00 L2.56 8.01 L2.21 5.50 L4.56 4.56 L5.50 2.21 L8.01 2.56 Z" fill="#10b981"/><path d="M5.7 10l2.8 2.8 5.8-5.8" fill="none" stroke="#ffffff" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>',
                  width: 12,
                  height: 12,
                ),
                pw.SizedBox(width: 4),
                pw.Text(
                  'Verified',
                  style: pw.TextStyle(
                    fontSize: 8.5,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.green700,
                  ),
                ),
              ],
            ),
          )
        : pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
            decoration: pw.BoxDecoration(
              color: const PdfColor.fromInt(0xFFFFFBEB),
              borderRadius: pw.BorderRadius.circular(5),
              border: pw.Border.all(
                color: const PdfColor.fromInt(0xFFFDE68A),
                width: 0.6,
              ),
            ),
            child: pw.Row(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Container(
                  width: 5,
                  height: 5,
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.orange700,
                    shape: pw.BoxShape.circle,
                  ),
                ),
                pw.SizedBox(width: 5),
                pw.Text(
                  'Pending',
                  style: pw.TextStyle(
                    fontSize: 8.5,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.orange700,
                  ),
                ),
              ],
            ),
          );

    try {
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 32),
          build: (ctx) => [
            // -----------------------------------------------------------
            // 1. INTEGRATED SCHOOL HEADER CARD
            // -----------------------------------------------------------
            pw.Container(
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                borderRadius: pw.BorderRadius.circular(7),
                border: pw.Border.all(color: cLine, width: 0.7),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  // Top Header Strip: Portal Tag + Verified Badge
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: const pw.BoxDecoration(
                      color: cSurface,
                      borderRadius: pw.BorderRadius.vertical(
                        top: pw.Radius.circular(6.5),
                      ),
                      border: pw.Border(
                        bottom: pw.BorderSide(color: cSoftLine, width: 0.6),
                      ),
                    ),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text(
                          'SHALA DARPAN  •  SCHOOL ATTENDANCE STATEMENT',
                          style: pw.TextStyle(
                            fontSize: 7.5,
                            fontWeight: pw.FontWeight.bold,
                            color: cMuted,
                            letterSpacing: 0.5,
                          ),
                        ),
                        verifiedBadge,
                      ],
                    ),
                  ),
                  // Center: School Name & Village
                  pw.Padding(
                    padding: const pw.EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: pw.Column(
                      children: [
                        pw.SizedBox(
                          height: 19,
                          child: pw.FittedBox(
                            fit: pw.BoxFit.scaleDown,
                            alignment: pw.Alignment.center,
                            child: pw.Text(
                              schoolTitle.isEmpty ? '-' : schoolTitle,
                              style: pw.TextStyle(
                                fontSize: 14.5,
                                fontWeight: pw.FontWeight.bold,
                                color: cInk,
                              ),
                            ),
                          ),
                        ),
                        if (village.isNotEmpty) ...[
                          pw.SizedBox(height: 4),
                          pw.SizedBox(
                            height: 14,
                            child: pw.FittedBox(
                              fit: pw.BoxFit.scaleDown,
                              alignment: pw.Alignment.center,
                              child: pw.Text(
                                village,
                                style: const pw.TextStyle(
                                  fontSize: 10.5,
                                  color: cSlate,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Bottom Strip: 3-Column Metadata Grid
                  pw.Container(
                    decoration: const pw.BoxDecoration(
                      color: cSurface,
                      borderRadius: pw.BorderRadius.vertical(
                        bottom: pw.Radius.circular(6.5),
                      ),
                      border: pw.Border(
                        top: pw.BorderSide(color: cSoftLine, width: 0.6),
                      ),
                    ),
                    child: pw.Row(
                      children: [
                        metaColumn('UDISE', udise, showRightBorder: true),
                        metaColumn('NIC', nic, showRightBorder: true),
                        metaColumn('Office ID', officeId),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 12),
            if (!attendanceVerified) ...[
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: pw.BoxDecoration(
                  color: const PdfColor.fromInt(0xFFFFFBEB),
                  borderRadius: pw.BorderRadius.circular(5),
                  border: pw.Border.all(
                    color: const PdfColor.fromInt(0xFFFDE68A),
                    width: 0.6,
                  ),
                ),
                child: pw.Text(
                  'Attendance is not verified as submitted on the portal. Counts below are provisional.',
                  style: const pw.TextStyle(
                    fontSize: 8.5,
                    color: PdfColors.orange700,
                  ),
                ),
              ),
              pw.SizedBox(height: 10),
            ],
            // -----------------------------------------------------------
            // 2. REPORT TITLE + DATE BAR (With Crisp Vector SVG Icons)
            // -----------------------------------------------------------
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 7.5,
              ),
              decoration: pw.BoxDecoration(
                color: cHeaderFill,
                borderRadius: pw.BorderRadius.circular(6),
                border: pw.Border.all(color: cLine, width: 0.6),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Row(
                    mainAxisSize: pw.MainAxisSize.min,
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.SvgImage(
                        svg: registerSvgIcon,
                        width: 15,
                        height: 15,
                      ),
                      pw.SizedBox(width: 7),
                      pw.Text(
                        'Daily Attendance Record',
                        style: pw.TextStyle(
                          fontSize: 11.5,
                          fontWeight: pw.FontWeight.bold,
                          color: cInk,
                        ),
                      ),
                    ],
                  ),
                  pw.Row(
                    mainAxisSize: pw.MainAxisSize.min,
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.SvgImage(
                        svg: calendarSvgIcon,
                        width: 11.5,
                        height: 11.5,
                      ),
                      pw.SizedBox(width: 5),
                      pw.Text(
                        date,
                        style: pw.TextStyle(
                          fontSize: 10.5,
                          fontWeight: pw.FontWeight.bold,
                          color: cInk,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 8),
            // -----------------------------------------------------------
            // 3. ATTENDANCE TABLE
            // -----------------------------------------------------------
            pw.Table(
              border: border,
              columnWidths: {
                0: const pw.FlexColumnWidth(1.2),
                1: const pw.FlexColumnWidth(1.2),
                for (var i = 2; i <= 6; i++) i: const pw.FlexColumnWidth(1),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: cHeaderFill),
                  children: [
                    for (final h in headers)
                      cell(h, bold: true, size: 10.0, vertical: 8),
                  ],
                ),
                for (var i = 0; i < rows.length; i++) dataRow(rows[i], i),
              ],
            ),
            // -----------------------------------------------------------
            // 4. MERGED TOTAL ROW
            // -----------------------------------------------------------
            totalTable,
            pw.SizedBox(height: 12),
            // -----------------------------------------------------------
            // 5. 4-COLUMN SUMMARY CARD (Enrolled + Present + Absent + Leave)
            // -----------------------------------------------------------
            pw.Container(
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                borderRadius: pw.BorderRadius.circular(6),
                border: pw.Border.all(color: cLine, width: 0.6),
              ),
              child: pw.Column(
                children: [
                  pw.Row(
                    children: [
                      summaryItem(
                        'Total Students',
                        '$tTotal',
                        cInk,
                        pw.SvgImage(svg: enrolledSvgIcon),
                        showRightDivider: true,
                      ),
                      summaryItem(
                        'Present ($attPct)',
                        '$tPresent',
                        const PdfColor.fromInt(0xFF059669),
                        pw.SvgImage(svg: attendancePresentPdfIcon),
                        showRightDivider: true,
                      ),
                      summaryItem(
                        'Absent',
                        '$tAbsent',
                        const PdfColor.fromInt(0xFFE11D48),
                        pw.SvgImage(svg: attendanceAbsentPdfIcon),
                        showRightDivider: true,
                      ),
                      summaryItem(
                        'Leave / Medical',
                        '$tLeave',
                        const PdfColor.fromInt(0xFFB77915),
                        pw.SvgImage(svg: attendanceLeavePdfIcon),
                      ),
                    ],
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5.5,
                    ),
                    decoration: const pw.BoxDecoration(
                      color: cSurface,
                      borderRadius: pw.BorderRadius.vertical(
                        bottom: pw.Radius.circular(5.5),
                      ),
                      border: pw.Border(
                        top: pw.BorderSide(color: cSoftLine, width: 0.6),
                      ),
                    ),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'Present Breakdown: $tBoys Boys + $tGirls Girls${unknownPresent > 0 ? ' + $unknownPresent Unclassified' : ''} = $tPresent Students',
                          style: pw.TextStyle(
                            fontSize: 8.5,
                            fontWeight: pw.FontWeight.bold,
                            color: cSlate,
                          ),
                        ),
                        pw.Text(
                          'Attendance Rate: $attPct',
                          style: pw.TextStyle(
                            fontSize: 8.5,
                            fontWeight: pw.FontWeight.bold,
                            color: cInk,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              'Boys / Girls represent present students. '
              'Leave includes On Leave and On Medical. '
              'Total = Boys + Girls + Absent + Leave.',
              style: const pw.TextStyle(
                fontSize: 8,
                color: cMuted,
              ),
            ),
            if (unknownPresent > 0) ...[
              pw.SizedBox(height: 3),
              pw.Text(
                'Note: $unknownPresent present student(s) '
                'could not be assigned a gender from the '
                'portal master. They are included in the Present summary '
                'and excluded from the Boys/Girls breakdown.',
                style: const pw.TextStyle(
                  fontSize: 8,
                  color: cMuted,
                ),
              ),
            ],
          ],
        ),
      );
      return await doc.save();
    } catch (error, stack) {
      if (leaveIcon == null &&
          dateIcon == null &&
          integratedLogo == null &&
          schoolLogo == null)
        rethrow;
      debugPrint(
        '[SchoolReport] PDF with optional images failed: $error; retrying without images.',
      );
      debugPrintStack(stackTrace: stack);
      return _buildPdf(
        schoolName: schoolName,
        village: village,
        udise: udise,
        nic: nic,
        officeId: officeId,
        peeoCode: peeoCode,
        date: date,
        rows: rows,
        unknownPresent: unknownPresent,
        attendanceVerified: attendanceVerified,
      );
    }
  }

  Future<void> _share() async {
    final b = _bytes;
    if (b == null) return;
    HapticFeedback.selectionClick();
    await Printing.sharePdf(bytes: b, filename: _fileName);
  }

  Color get _background =>
      widget.backgroundColor ?? Theme.of(context).scaffoldBackgroundColor;

  PreferredSizeWidget _buildReportHeader(Color foreground) =>
      AttendancePageHeader(
        title: 'Attendance Report',
        foreground: foreground,
        actions: [
          IconButton(
            tooltip: 'Share PDF',
            onPressed: _bytes == null || _loading ? null : _share,
            icon: const Icon(CupertinoIcons.share, size: 20),
            color: foreground,
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = dark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
    return Scaffold(
      backgroundColor: _background,
      appBar: _buildReportHeader(foreground),
      body: AdaptiveWorkspace(
        background: true,
        child: PageContentMotion(
          child: SafeArea(
            top: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(54, 0, 16, 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Image.asset(
                        'assets/icons/leave.png',
                        width: 15,
                        height: 15,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Icon(
                          CupertinoIcons.calendar,
                          size: 15,
                          color: foreground.withOpacity(0.65),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _prettyDate(_portalDate),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: _font,
                            fontSize: 12,
                            color: foreground.withOpacity(0.65),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(child: _body()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading)
      return _ReportLoadingView(progress: _progress, message: _loadingMessage);
    if (_error.isNotEmpty || _bytes == null) return _errorView(_error);
    return PdfPreview(
      build: (_) async => _bytes!,
      useActions: false,
      allowPrinting: false,
      allowSharing: false,
      canChangePageFormat: false,
      canChangeOrientation: false,
      canDebug: false,
      pdfFileName: _fileName,
      loadingWidget: _ReportLoadingView(
        progress: _progress,
        message: _loadingMessage,
      ),
      onError: (_, error) => _errorView('Could not display the PDF: $error'),
      maxPageWidth: 900,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
      previewPageMargin: const EdgeInsets.only(bottom: 16),
      scrollViewDecoration: const BoxDecoration(color: Colors.transparent),
      pdfPreviewPageDecoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
    );
  }

  Widget _errorView(String message) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            CupertinoIcons.exclamationmark_circle,
            color: Color(0xFFEF4444),
            size: 32,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: _font, fontSize: 12.5),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _load, child: const Text('Try again')),
        ],
      ),
    ),
  );
}

/// The ring advances only after completed operations, never on a timer.
class _ReportLoadingView extends StatelessWidget {
  final double progress;
  final String message;
  const _ReportLoadingView({required this.progress, required this.message});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = theme.colorScheme.onSurface;
    final reducedMotion = MediaQuery.of(context).disableAnimations;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                label: 'Preparing attendance document',
                child: SizedBox(
                  width: 42,
                  height: 50.4,
                  child: TweenAnimationBuilder<double>(
                    // New preview loader starts at the current completed value, not zero.
                    tween: Tween<double>(
                      begin: progress.clamp(0.0, 1.0).toDouble(),
                      end: progress.clamp(0.0, 1.0).toDouble(),
                    ),
                    duration: Duration(milliseconds: reducedMotion ? 0 : 180),
                    curve: Curves.easeOutCubic,
                    builder: (_, value, __) => CustomPaint(
                      painter: _AttendanceDocumentPainter(
                        progress: value,
                        paper: theme.colorScheme.surface,
                        ink: ink,
                        blue: const Color(0xFF007AFF),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CupertinoActivityIndicator(
                    radius: 7,
                    color: ink.withOpacity(0.55),
                    animating: !reducedMotion,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Semantics(
                      liveRegion: true,
                      child: AnimatedSwitcher(
                        duration: Duration(
                          milliseconds: reducedMotion ? 0 : 160,
                        ),
                        child: Text(
                          message,
                          key: ValueKey(message),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: _font,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w400,
                            color: ink.withOpacity(0.75),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Original iOS-style clockwise filling ring with a stationary download arrow.
class _AttendanceDocumentPainter extends CustomPainter {
  final double progress;
  final Color paper;
  final Color ink;
  final Color blue;
  const _AttendanceDocumentPainter({
    required this.progress,
    required this.paper,
    required this.ink,
    required this.blue,
  });
  @override
  void paint(Canvas canvas, Size size) {
    // Scale all geometry together, preserving the original 0.125 ring width.
    canvas.save();
    canvas.scale(size.width / 90, size.height / 108);
    const w = 90.0;
    const h = 108.0;
    final fold = w * 0.23;
    final document = Path()
      ..moveTo(10, 2)
      ..lineTo(w - fold, 2)
      ..lineTo(w - 2, fold)
      ..lineTo(w - 2, h - 10)
      ..quadraticBezierTo(w - 2, h - 2, w - 10, h - 2)
      ..lineTo(10, h - 2)
      ..quadraticBezierTo(2, h - 2, 2, h - 10)
      ..lineTo(2, 10)
      ..quadraticBezierTo(2, 2, 10, 2)
      ..close();
    canvas.drawShadow(document, Colors.black.withOpacity(0.12), 5, false);
    canvas.drawPath(document, Paint()..color = paper);
    canvas.drawPath(
      document,
      Paint()
        ..color = ink.withOpacity(0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    final corner = Path()
      ..moveTo(w - fold, 2)
      ..lineTo(w - fold, fold - 4)
      ..quadraticBezierTo(w - fold, fold, w - fold + 4, fold)
      ..lineTo(w - 2, fold)
      ..close();
    canvas.drawPath(corner, Paint()..color = ink.withOpacity(0.07));
    canvas.drawPath(
      corner,
      Paint()
        ..color = ink.withOpacity(0.13)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    final line = Paint()
      ..color = ink.withOpacity(0.18)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(17, 24), Offset(w - fold - 10, 24), line);
    canvas.drawLine(const Offset(17, 34), Offset(w - 22, 34), line);
    final center = Offset(w / 2, h * 0.67);
    const ringSize = 36.0;
    const stroke = ringSize * 0.125;
    const radius = (ringSize - stroke) / 2;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = blue.withOpacity(0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    final arc = Paint()
      ..color = blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        progress * 2 * math.pi,
        false,
        arc,
      );
    }
    final arrow = Paint()
      ..color = blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * 0.95
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final arrowY = center.dy;
    final path = Path()
      ..moveTo(center.dx, arrowY - ringSize * 0.20)
      ..lineTo(center.dx, arrowY + ringSize * 0.20)
      ..moveTo(center.dx - ringSize * 0.16, arrowY + ringSize * 0.06)
      ..lineTo(center.dx, arrowY + ringSize * 0.20)
      ..lineTo(center.dx + ringSize * 0.16, arrowY + ringSize * 0.06);
    canvas.drawPath(path, arrow);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AttendanceDocumentPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.paper != paper ||
      oldDelegate.ink != ink ||
      oldDelegate.blue != blue;
}
