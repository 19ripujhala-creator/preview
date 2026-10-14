/// Complete conversion of student_kpi.py and the dashboard route's KPI adapter.
import 'dart:async';
import 'dart:io';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import '../portal_state.dart';
import '../../../core/direct/async_primitives.dart';
import 'class_mapping_worker.dart';
import 'student_attendance_worker.dart';

typedef StudentKpiRequest = Future<AttendanceHttpReply> Function(
  Uri url, {
  Map<String, Object?>? fields,
  Uri? referer,
  String? showControl,
  String? showControlId,
  Duration timeout,
});

class StudentKpiWorker {
  StudentKpiWorker({
    required this.request,
    required this.baseUrl,
    required this.schoolId,
    required this.sessionKey,
    this.check,
    this.clock,
  });
  final StudentKpiRequest request;
  final Uri Function() baseUrl;
  final String Function() schoolId, sessionKey;
  final void Function()? check;
  final DateTime Function()? clock;
  static const path =
      'Home/School/StudentdailyAttendanceStatus_Web_NewVersion.aspx';
  static const gridId = 'ContentPlaceHolder1_grd_Student';
  static Never _fail(String code, String message) =>
      throw MappingError(code, message);
  static String _text(dom.Element? element) {
    final parts = <String>[];
    void visit(dom.Node node) {
      if (node is dom.Text) {
        final text = node.data.trim();
        if (text.isNotEmpty) parts.add(text);
      } else {
        if (node is dom.Element &&
            ['script', 'style', 'template'].contains(node.localName))
          return;
        for (final child in node.nodes) {
          visit(child);
        }
      }
    }

    if (element != null) visit(element);
    return parts.join(' ');
  }

  // Python regex \d and int() accept Unicode decimal digits.
  static String _decimal(String value) => String.fromCharCodes(
    value.runes.map((rune) {
      for (final start in const <int>[
        0x30,
        0x660,
        0x6f0,
        0x7c0,
        0x966,
        0x9e6,
        0xa66,
        0xae6,
        0xb66,
        0xbe6,
        0xc66,
        0xce6,
        0xd66,
        0xde6,
        0xe50,
        0xed0,
        0xf20,
        0x1040,
        0x1090,
        0x17e0,
        0x1810,
        0x1946,
        0x19d0,
        0x1a80,
        0x1a90,
        0x1b50,
        0x1bb0,
        0x1c40,
        0x1c50,
        0xa620,
        0xa8d0,
        0xa900,
        0xa9d0,
        0xa9f0,
        0xaa50,
        0xabf0,
        0xff10,
        0x104a0,
        0x10d30,
        0x11066,
        0x110f0,
        0x11136,
        0x111d0,
        0x112f0,
        0x11450,
        0x114d0,
        0x11650,
        0x116c0,
        0x11730,
        0x118e0,
        0x11950,
        0x11c50,
        0x11d50,
        0x11da0,
        0x11f50,
        0x16a60,
        0x16ac0,
        0x16b50,
        0x1d7ce,
        0x1d7d8,
        0x1d7e2,
        0x1d7ec,
        0x1d7f6,
        0x1e140,
        0x1e2f0,
        0x1e4f0,
        0x1e950,
        0x1fbf0,
      ]) {
        if (rune >= start && rune < start + 10) return 48 + rune - start;
      }
      return rune;
    }),
  );
  static int _number(dom.Element? element) {
    final text = _decimal(_text(element));
    if (!RegExp(r'^(?:[0-9]+|[0-9]{1,3}(?:,[0-9]{3})+)$').hasMatch(text)) {
      _fail(
        'INVALID_RESULT',
        'A student attendance count is missing or invalid.',
      );
    }
    return int.parse(text.replaceAll(',', ''));
  }

  static dom.Element? _find(dom.Element grid, String id) {
    for (final node in grid.querySelectorAll('[id]')) {
      if (node.id == id) return node;
    }
    return null;
  }

  static int _present(dom.Element grid, String suffix) => _number(
    _find(grid, '${gridId}_lbl_P_Web_$suffix') ??
        _find(grid, '${gridId}_lbl_P_App_$suffix'),
  );
  static Map<String, dynamic> _metrics(
    int sections,
    int total,
    int present,
    DateTime now, {
    bool rounded = false,
  }) {
    final ist = now.toUtc().add(const Duration(hours: 5, minutes: 30));
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = [
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
    final rate = total == 0 ? 0.0 : present * 100 / total;
    final floor = rate.floor();
    final percent = !rounded
        ? rate.toInt()
        : rate - floor == 0.5
        ? (floor.isEven ? floor : floor + 1)
        : rate.round();
    return {
      'sections': sections == 0 ? '--' : '$sections',
      'students': '$total',
      'present': '$present',
      'attendance': '$present / $total',
      'percentage': '$percent%',
      'sync_time':
          '${(ist.hour % 12 == 0 ? 12 : ist.hour % 12).toString().padLeft(2, '0')}:${ist.minute.toString().padLeft(2, '0')} ${ist.hour < 12 ? 'AM' : 'PM'}',
      'sync_date':
          '${weekdays[ist.weekday - 1]}, ${months[ist.month - 1]} ${ist.day.toString().padLeft(2, '0')}',
    };
  }

  static Map<String, dynamic> parse(String source, {DateTime? now}) {
    final grid = html.parse(source).querySelector('table#$gridId');
    if (grid == null)
      _fail('PAGE_NOT_READY', 'Student attendance grid was not returned.');
    if (grid
        .querySelectorAll('a[href]')
        .any((n) => n.attributes['href']!.contains('Page\$'))) {
      _fail(
        'PAGE_NOT_READY',
        'Paginated student counts cannot be verified as a complete summary.',
      );
    }
    final rows = <String, (int, int)>{};
    final pattern = RegExp('^${gridId}_lbl_TotStudent_([0-9]+)\$');
    for (final node in grid.querySelectorAll('[id]')) {
      final match = pattern.firstMatch(node.id);
      if (match == null) continue;
      final suffix = match.group(1)!;
      if (rows.containsKey(suffix))
        _fail('INVALID_RESULT', 'Duplicate student attendance row.');
      final total = _number(node), present = _present(grid, suffix);
      if (present > total)
        _fail('INVALID_RESULT', 'Present count exceeds student count.');
      rows[suffix] = (total, present);
    }
    final seen = <String>{};
    final links = RegExp('^${gridId}_btn_Entry_([0-9]+)\$');
    for (final link in grid.querySelectorAll('a[id]')) {
      final match = links.firstMatch(link.id);
      if (match == null) continue;
      final suffix = match.group(1)!;
      if (!seen.add(suffix) || !rows.containsKey(suffix)) {
        _fail('INVALID_RESULT', 'Section counts are incomplete or duplicated.');
      }
    }
    final rowTotal = rows.values.fold<int>(0, (n, r) => n + r.$1);
    final rowPresent = rows.values.fold<int>(0, (n, r) => n + r.$2);
    final footer = _find(grid, '${gridId}_lbl_TotStudent_F');
    late int total, present;
    if (footer != null) {
      total = _number(footer);
      present = _present(grid, 'F');
      if (rows.isNotEmpty && (total != rowTotal || present != rowPresent)) {
        _fail('INVALID_RESULT', 'Attendance rows do not match portal totals.');
      }
    } else if (rows.isNotEmpty) {
      total = rowTotal;
      present = rowPresent;
    } else {
      _fail('INVALID_RESULT', 'Student attendance counts are unavailable.');
    }
    if (present > total)
      _fail('INVALID_RESULT', 'Present count exceeds student count.');
    return _metrics(seen.length, total, present, now ?? DateTime.now());
  }

  /// Existing login-sync route derives counts/status from one fresh class summary.
  static Map<String, dynamic> dashboard(
    Map<String, dynamic> summary, {
    DateTime? now,
  }) {
    final classes = summary['classes'];
    if (summary['success'] != true || classes is! List || classes.isEmpty) {
      return summary['success'] == false
          ? summary
          : {
              'success': false,
              'code': 'INVALID_RESULT',
              'message': 'No class attendance rows were returned.',
            };
    }
    var total = 0, present = 0;
    for (final row in classes) {
      if (row is! Map)
        _fail('INVALID_RESULT', 'Student class summary is invalid.');
      total += int.parse('${row['total'] ?? 0}');
      present += int.parse('${row['present'] ?? 0}');
    }
    return {
      'success': true,
      'payload': {
        ..._metrics(
          classes.length,
          total,
          present,
          now ?? DateTime.now(),
          rounded: true,
        ),
        'class_summary': summary,
      },
    };
  }

  void _check(String key, String school) {
    OperationCancellation.current?.check();
    check?.call();
    if (schoolId().trim() != school || sessionKey() != key || key.isEmpty) {
      _fail(
        'ACCOUNT_CHANGED',
        'School login session changed. Fetch class mapping again.',
      );
    }
  }

  dom.Document _document(AttendanceHttpReply reply, String key, String school) {
    _check(key, school);
    final text = validateSchoolDocument(reply.url, reply.html, reply.status);
    if (reply.url.scheme != 'https' ||
        reply.url.host != 'rajshaladarpan.rajasthan.gov.in' ||
        !RegExp(
          r'^/SD[1-5]/Home/School/StudentdailyAttendanceStatus_Web_NewVersion\.aspx$',
          caseSensitive: false,
        ).hasMatch(reply.url.path)) {
      _fail(
        'PAGE_NOT_READY',
        'Expected school attendance document was not returned.',
      );
    }
    return html.parse(text);
  }

  Future<Map<String, dynamic>> fetch() async {
    try {
      final base = baseUrl(), school = schoolId().trim(), key = sessionKey();
      if (base.scheme != 'https' ||
          base.host != 'rajshaladarpan.rajasthan.gov.in' ||
          base.port != 443 ||
          base.userInfo.isNotEmpty ||
          base.hasQuery ||
          base.hasFragment ||
          !RegExp(r'^/SD[1-5]/?$', caseSensitive: false).hasMatch(base.path)) {
        _fail('PAGE_NOT_READY', 'Active school server base is invalid.');
      }
      if (school.isEmpty || key.isEmpty)
        _fail(
          'ACCOUNT_CHANGED',
          'School account changed. Fetch class mapping again.',
        );
      _check(key, school);
      final url = Uri.parse(
        '${base.toString().replaceFirst(RegExp(r'/+$'), '')}/$path',
      );
      var response = await request(url, timeout: const Duration(seconds: 25));
      final soup = _document(response, key, school);
      final buttons = soup
          .querySelectorAll('input[id]')
          .where(
            (b) =>
                RegExp(r'(?:^|_)btn_Show$').hasMatch(b.id) &&
                !b.attributes.containsKey('disabled'),
          )
          .toList();
      if (buttons.length != 1)
        _fail(
          'PAGE_NOT_READY',
          'A unique attendance Show button was not found.',
        );
      final button = buttons.single, form = AttendanceForm.enclosing(button);
      if (form == null) _fail('PAGE_NOT_READY', 'Attendance form is missing.');
      final payload = AttendanceForm.payload(form, button);
      if (payload['__VIEWSTATE'] == null ||
          payload['__VIEWSTATE'] == '' ||
          payload['__EVENTVALIDATION'] == null ||
          payload['__EVENTVALIDATION'] == '') {
        _fail('PAGE_NOT_READY', 'Attendance form tokens are missing.');
      }
      payload.removeWhere(
        (key, value) => key.toLowerCase().endsWith('scriptmanager1'),
      );
      final action = response.url.resolve(
        form.attributes['action'] ?? response.url.toString(),
      );
      if (action.scheme != response.url.scheme ||
          action.authority != response.url.authority ||
          action.path != response.url.path) {
        _fail('PAGE_NOT_READY', 'Unexpected attendance form destination.');
      }
      _check(key, school);
      response = await request(
        action,
        fields: payload,
        referer: response.url,
        showControl:
            button.attributes['name'] ?? payload['__EVENTTARGET']?.toString(),
        showControlId: button.id,
        timeout: const Duration(seconds: 30),
      );
      _document(response, key, school);
      final result = parse(response.html, now: clock?.call());
      _check(key, school);
      return result;
    } on SchoolDocumentError catch (e) {
      return Map<String, dynamic>.from(e.result);
    } on MappingError catch (e) {
      return {'success': false, 'code': e.code, 'message': e.message};
    } on TimeoutException {
      return {
        'success': false,
        'code': 'PORTAL_SLOW',
        'message': 'Student KPI request timed out.',
      };
    } on IOException {
      return {
        'success': false,
        'code': 'NETWORK_ERROR',
        'message': 'Student KPI portal could not be reached.',
      };
    } catch (_) {
      return {
        'success': false,
        'code': 'PAGE_NOT_READY',
        'message': 'Student KPI data could not be read.',
      };
    }
  }
}
