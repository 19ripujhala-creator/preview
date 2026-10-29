/// Conversion of student/school_report_worker.py, including Home header/logos.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import '../../../core/direct/async_primitives.dart';
import 'gender_master.dart';
import 'student_attendance_worker.dart';

typedef SchoolLogoReply = ({
  Uri url,
  int status,
  Uint8List bytes,
  String contentType,
});
typedef SchoolLogoRequest = Future<SchoolLogoReply> Function(Uri url);

class SchoolReportWorker {
  SchoolReportWorker({
    required this.attendance,
    required this.gender,
    required this.request,
    required this.logoRequest,
    required this.baseUrl,
    required this.schoolId,
    required this.cache,
    Future<void> Function(Duration)? delay,
  }) : delay = delay ?? Future<void>.delayed;
  final StudentAttendanceWorker attendance;
  final GenderMaster gender;
  final AttendanceHttpRequest request;
  final SchoolLogoRequest logoRequest;
  final Uri Function() baseUrl;
  final String Function() schoolId;
  final SchoolReportCache cache;
  final Future<void> Function(Duration) delay;
  static const retryWait = Duration(milliseconds: 1500);
  static const infoKeys = [
    'name',
    'village',
    'udise',
    'nic',
    'officeId',
    'leftLogoBase64',
    'rightLogoBase64',
  ];

  static (int, String) naturalKey(String label) {
    final match = RegExp(r'^\s*(\d+)\s*(.*)$').firstMatch(label);
    return match == null
        ? (999, label.toLowerCase())
        : (int.parse(match.group(1)!), match.group(2)!.toLowerCase());
  }

  static (String, String) splitLabel(String label) {
    final match = RegExp(r'^\s*(\d+)\s*[-_ ]?\s*(.*)$').firstMatch(label);
    return match == null
        ? (label.trim(), '')
        : (match.group(1)!, match.group(2)!.trim().toUpperCase());
  }

  static Map<String, String> parseSchoolInfo(dom.Document doc) {
    String text(dom.Element? element) {
      final content = StudentAttendanceWorker.text(element);
      return (content.isEmpty ? element?.attributes['value'] ?? '' : content)
          .trim()
          .replaceAll(RegExp(r'\s+'), ' ');
    }

    String nested(String id) {
      final element = doc.getElementById(id);
      if (element == null) return '';
      for (final child in element.querySelectorAll('span')) {
        if (text(child).isNotEmpty) return text(child);
      }
      return text(element);
    }

    final body = text(doc.body ?? doc.documentElement);
    final info = {
      'name': nested('lblschoolname'),
      'village': nested('lblvillage'),
    };
    const patterns = {
      'udise': ('lblUDISE', r'UDISE\s*Code\s*:\s*([0-9A-Za-z_-]+)'),
      'nic': ('lblSchcd', r'NIC[-\s]*SD\s*ID\s*:\s*([0-9A-Za-z_-]+)'),
      'officeId': ('lblIFMSOfficeID', r'OFFICE\s*ID\s*:\s*([0-9A-Za-z_-]+)'),
    };
    for (final entry in patterns.entries) {
      final pattern = RegExp(entry.value.$2, caseSensitive: false);
      final match =
          pattern.firstMatch(text(doc.getElementById(entry.value.$1))) ??
          pattern.firstMatch(body);
      info[entry.key] = match?.group(1) ?? '';
    }
    return info;
  }

  Future<String> _logo(dom.Element? image, Uri page) async {
    if (image == null) return '';
    final src = image.attributes['src'] ?? '';
    if (src.startsWith('data:image/') && src.contains(';base64,')) {
      final encoded = src.split(';base64,').last;
      if (!RegExp(
        r'^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$',
      ).hasMatch(encoded))
        return '';
      try {
        base64Decode(encoded);
        return encoded;
      } catch (_) {
        return '';
      }
    }
    final url = page.resolve(src);
    if (src.isEmpty ||
        !['http', 'https'].contains(url.scheme) ||
        url.authority != page.authority)
      return '';
    try {
      final reply = await logoRequest(url);
      if (reply.status < 200 ||
          reply.status >= 300 ||
          !reply.contentType.toLowerCase().startsWith('image/'))
        return '';
      return base64Encode(reply.bytes);
    } catch (_) {
      return '';
    }
  }

  Future<Map<String, String>> getSchoolInfo(String school) async {
    final file = 'school_info_$school.json';
    final stored = await cache.load(file);
    final info = stored.data.isEmpty
        ? <String, String>{}
        : {for (final key in infoKeys) key: '${stored.data[key] ?? ''}'};
    if (infoKeys.every((k) => (info[k] ?? '').isNotEmpty)) return info;
    OperationCancellation.current?.check();
    final response = await request(
      baseUrl().resolve('Home/School/Home_New.aspx'),
      mutation: false,
    );
    OperationCancellation.current?.check();
    final doc = html.parse(response.html);
    if (StudentAttendanceWorker.isLoginRedirect(response.url) ||
        doc.querySelector('#bodyContent_txtUName, #txtUserId') != null) {
      throw const AttendanceWorkerError(
        'SESSION_EXPIRED',
        'School portal session expired.',
      );
    }
    final title = StudentAttendanceWorker.text(doc.querySelector('title'));
    final heading = StudentAttendanceWorker.text(doc.querySelector('h1'));
    if ([
      'server error',
      'runtime error',
      'nullreference',
      'object reference',
    ].any((s) => '$title $heading'.toLowerCase().contains(s))) {
      throw AttendanceWorkerError(
        'PORTAL_RESPONSE_ERROR',
        title.isEmpty ? heading : title,
      );
    }
    if (response.status < 200 || response.status >= 300) {
      throw AttendanceWorkerError('PORTAL_HTTP', 'HTTP ${response.status}');
    }
    final found = parseSchoolInfo(doc);
    found['leftLogoBase64'] = await _logo(
      doc.querySelector("img.adminLogo, img[src*='Integrated-ShalaDarpan']"),
      response.url,
    );
    found['rightLogoBase64'] = await _logo(
      doc.querySelector("img#imgheader, img[src*='SCHLogo']"),
      response.url,
    );
    for (final key in infoKeys) {
      if ((info[key] ?? '').isEmpty && (found[key] ?? '').isNotEmpty)
        info[key] = found[key]!.trim();
    }
    if (info.values.any((v) => v.isNotEmpty)) {
      try {
        await cache.save(file, info, DateTime.now());
      } catch (_) {}
    }
    return info;
  }

  static bool _stop(Map<String, dynamic> result) =>
      const {
        'SESSION_EXPIRED',
        'PAGE_NOT_READY',
        'BAD_DATE',
        'BAD_CLASS',
        'DATE_MISMATCH',
        'MATCH_MISMATCH',
        'PORTAL_MESSAGE',
      }.contains(result['code']) ||
      '${result['message'] ?? ''}'.toLowerCase().contains('closed');

  Future<Map<String, dynamic>> readSection(String label, String? date) async {
    Map<String, dynamic> last = {};
    for (var attempt = 1; attempt <= 3; attempt++) {
      OperationCancellation.current?.check();
      final result = await attendance.fetchStudentAttendanceList(
        classId: label,
        attendanceDate: date,
        section: label,
      );
      if (result['success'] == true || _stop(result)) return result;
      last = result;
      if (attempt < 3) await delay(retryWait);
    }
    return last;
  }

  Future<Map<String, dynamic>> fetchSchoolReport({
    String? attendanceDate,
    void Function(int completed, int total)? onProgress,
  }) async {
    try {
      final summary = await attendance.fetchClassSummary(
        attendanceDate: attendanceDate,
      );
      if (summary['success'] != true) return summary;
      final date = (summary['date'] ?? attendanceDate) as String?;
      var classes = (summary['classes'] as List)
          .cast<Map<String, dynamic>>()
          .where((c) => c['total'] != 0)
          .toList();
      if (classes.isEmpty)
        return {
          'success': false,
          'code': 'NO_CLASSES',
          'message': 'No class rows were found for this date.',
        };
      classes = classes
          .where((c) => '${c['section'] ?? ''}'.isNotEmpty)
          .toList();
      if (classes.isEmpty)
        return {
          'success': false,
          'code': 'NO_CLASSES',
          'message': 'No valid sections were found.',
        };
      final progressTotal = classes.length + 4;
      onProgress?.call(1, progressTotal);
      final collected = <Map<String, dynamic>>[];
      final failed = <String>[];
      Map<String, dynamic> lastFail = {};
      final submitted = <String>[];
      final pending = <String>[];
      var consistent = true;
      classes.sort((a, b) {
        final x = naturalKey('${a['section']}'),
            y = naturalKey('${b['section']}');
        final n = x.$1.compareTo(y.$1);
        return n == 0 ? x.$2.compareTo(y.$2) : n;
      });
      for (final c in classes) {
        final label = '${c['section']}';
        final result = await readSection(label, date);
        if (result['success'] != true) {
          failed.add(label);
          lastFail = result;
          if (_stop(result)) break;
          continue;
        }
        final readSummary = result['summary'] is Map
            ? result['summary'] as Map
            : c;
        (readSummary['done'] == true && c['done'] == true ? submitted : pending)
            .add(label);
        if (result['warning'] != null && '${result['warning']}'.isNotEmpty ||
            result['verified'] == false)
          consistent = false;
        collected.add({'section': label, 'students': result['students'] ?? []});
        onProgress?.call(1 + collected.length, progressTotal);
      }
      if (failed.isNotEmpty) {
        final closed = '${lastFail['message'] ?? ''}'.toLowerCase().contains(
          'closed',
        );
        return {
          'success': false,
          'code': closed
              ? 'SESSION_EXPIRED'
              : lastFail['code'] ?? 'PARTIAL_REPORT',
          'message': _stop(lastFail) && lastFail['message'] != null
              ? lastFail['message']
              : 'The following sections could not be read from the portal: ${failed.join(', ')}. Please wait for the portal session synchronization to complete and try again.',
          if (lastFail['portal_message'] != null)
            'portal_message': lastFail['portal_message'],
          if (lastFail['message_source'] != null)
            'message_source': lastFail['message_source'],
          'failedSections': failed,
        };
      }
      OperationCancellation.current?.check();
      final school = schoolId().isEmpty ? 'default' : schoolId();
      Map<String, String> info = {};
      try {
        info = await getSchoolInfo(school);
      } catch (_) {}
      onProgress?.call(2 + collected.length, progressTotal);
      final allSr = [
        for (final section in collected)
          for (final student in section['students'] as List)
            if ((student as Map)['srNo'] != null) student['srNo'],
      ];
      Map<String, String> genders = {};
      try {
        genders = await gender.getGenderMap(
          school: school,
          base: baseUrl(),
          neededSr: allSr,
        );
      } catch (_) {}
      if (genders.isEmpty) {
        await delay(retryWait);
        try {
          genders = await gender.getGenderMap(
            school: school,
            base: baseUrl(),
            neededSr: allSr,
            force: true,
          );
        } catch (_) {}
      }
      OperationCancellation.current?.check();
      onProgress?.call(3 + collected.length, progressTotal);
      final rows = <Map<String, dynamic>>[];
      var unknownTotal = 0;
      for (final section in collected) {
        final label = '${section['section']}';
        final students = section['students'] as List;
        var boys = 0, girls = 0, absent = 0, leave = 0, unknown = 0;
        for (final value in students) {
          final student = value as Map;
          if (student['status'] == 'Absent') {
            absent++;
            continue;
          }
          if (['OnLeave', 'OnMedical'].contains(student['status'])) {
            leave++;
            continue;
          }
          switch (genders[GenderMaster.normSr(student['srNo'])] ?? '') {
            case 'B':
              boys++;
              break;
            case 'G':
              girls++;
              break;
            default:
              unknown++;
          }
        }
        final labelParts = splitLabel(label);
        rows.add({
          'className': labelParts.$1,
          'section': labelParts.$2,
          'label': label,
          'boys': boys,
          'girls': girls,
          'absent': absent,
          'leave': leave,
          'total': boys + girls + absent + leave,
          'enrolled': students.length,
          'presentUnknown': unknown,
        });
        unknownTotal += unknown;
      }
      onProgress?.call(progressTotal, progressTotal);
      return {
        'success': true,
        'date': date,
        'schoolName': info['name'] ?? '',
        for (final key in infoKeys.where((k) => k != 'name'))
          key: info[key] ?? '',
        'rows': rows,
        'attendance_status': pending.isEmpty ? 'marked' : 'pending',
        'attendance_verified':
            collected.isNotEmpty && pending.isEmpty && consistent,
        'pendingSections': pending,
        'submittedSections': submitted,
        'unknownPresent': unknownTotal,
        'failedSections': [],
        'message': '',
      };
    } catch (error) {
      return {
        'success': false,
        'code': error.toString().toLowerCase().contains('closed')
            ? 'SESSION_EXPIRED'
            : 'UNEXPECTED',
        'message': error.toString(),
      };
    }
  }
}
