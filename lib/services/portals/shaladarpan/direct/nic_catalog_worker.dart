/// NIC directory catalog conversion from student/nic_sheet_worker.py.
/// Native PDF capture remains a separate browser operation; no report is rebuilt.
import 'dart:async';
import 'dart:io';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import 'monthly_tasks_worker.dart';
import 'ranking_http.dart';
import 'student_attendance_worker.dart';

typedef NicCatalogRequest = Future<AttendanceHttpReply> Function(
  Uri url, {
  Map<String, Object?>? fields,
  Uri? referer,
  Duration timeout,
});

class NicError implements Exception {
  const NicError(this.code, this.message);
  final String code, message;
  @override
  String toString() => message;
}

class NicCatalogWorker {
  NicCatalogWorker({
    required this.request,
    required this.baseUrl,
    required this.schoolId,
    required this.check,
  });
  final NicCatalogRequest request;
  final Uri Function() baseUrl;
  final String Function() schoolId;
  final void Function() check;
  static const path = 'Home/School/SchoolStudentProfiles_New.aspx';
  static const sessionId = 'ddlSession';
  static const classId = 'ContentPlaceHolder1_ddlClass';
  static const sessionName = r'ctl00$ContentPlaceHolder1$ddlSession';

  static Map<String, dynamic> failure(String code, String message) => {
    'success': false,
    'code': code,
    'message': message,
  };

  /// Browser option.selected includes the first option of a single select when
  /// the markup has no explicit selection. IDs are retained verbatim.
  static List<Map<String, dynamic>> options(dom.Element? select) {
    if (select == null) return [];
    final items = select.querySelectorAll('option');
    final explicit = items.where((o) => o.attributes.containsKey('selected'));
    final selected = explicit.isEmpty
        ? (items.isEmpty ? null : items.first)
        : explicit.last;
    return [
      for (final o in items)
        if ((o.attributes['value'] ?? o.text).trim().isNotEmpty &&
            !o.attributes.containsKey('disabled'))
          {
            'id': o.attributes['value'] ?? o.text,
            'label': o.text.trim(),
            'selected': identical(o, selected),
          },
    ];
  }

  static Map<String, dynamic>? sessionOption(
    List<Map<String, dynamic>> sessions,
  ) {
    for (final s in sessions) {
      if (s['selected'] == true) return s;
    }
    Map<String, dynamic>? newest;
    var year = -1;
    for (final s in sessions) {
      final match = RegExp(r'^(\d{4})[-/]\d{2,4}$')
          .firstMatch((s['id'] as String).trim());
      if (match != null && int.parse(match[1]!) > year) {
        newest = s;
        year = int.parse(match[1]!);
      }
    }
    return newest;
  }

  void _account(String school) {
    check();
    if (school.isEmpty || schoolId().trim() != school) {
      throw const NicError(
        'ACCOUNT_CHANGED',
        'School account changed. Open the NIC directory again.',
      );
    }
  }

  static dom.Document _response(
    AttendanceHttpReply reply,
    Uri expected, {
    dom.Document? previous,
  }) {
    final actual = reply.url;
    if (reply.status == 401 ||
        actual.path.toLowerCase().contains('/public') ||
        RegExp(
          r'/(?:officelogin|stafflogin|login|default)(?:new)?\.aspx$',
          caseSensitive: false,
        ).hasMatch(actual.path)) {
      throw const NicError('SESSION_EXPIRED', 'School portal session expired.');
    }
    if (reply.status != 200 ||
        actual.scheme != 'https' ||
        actual.authority.toLowerCase() != expected.authority.toLowerCase() ||
        actual.path.toLowerCase() != expected.path.toLowerCase()) {
      throw const NicError(
        'PAGE_NOT_READY',
        'The authenticated student profile page was not returned.',
      );
    }
    dom.Document document;
    if (RegExp(r'^\d+\|').hasMatch(reply.html)) {
      if (previous == null) {
        throw const NicError(
          'PAGE_NOT_READY',
          'Portal response is incomplete.',
        );
      }
      document = html.parse(previous.outerHtml);
      List<(String, String, String)> records;
      try {
        records = RankingHttp.parseDelta(reply.html);
      } on FormatException {
        throw const NicError(
          'PAGE_NOT_READY',
          'Portal response is incomplete.',
        );
      }
      var updated = false;
      for (final record in records) {
        if (record.$1 == 'error') {
          throw NicError('PORTAL_MESSAGE', record.$3);
        }
        if (record.$1 == 'pageRedirect') {
          throw const NicError(
            'SESSION_EXPIRED',
            'School portal session expired.',
          );
        }
        if (record.$1 == 'updatePanel') {
          final node = document.getElementById(record.$2);
          if (node == null) {
            throw const NicError(
              'PAGE_NOT_READY',
              'Portal response is incomplete.',
            );
          }
          node.innerHtml = record.$3;
          updated = true;
        } else if (record.$1 == 'hiddenField') {
          for (final node in document.querySelectorAll('input[name]')) {
            if (node.attributes['name'] == record.$2) {
              node.attributes['value'] = record.$3;
            }
          }
        } else if (record.$1 == 'scriptStartupBlock' ||
            record.$1 == 'scriptBlock') {
          final script = dom.Element.tag('script')..text = record.$3;
          document.body?.append(script);
        }
      }
      if (!updated) {
        throw const NicError(
          'PAGE_NOT_READY',
          'Portal response is incomplete.',
        );
      }
    } else {
      document = html.parse(reply.html);
    }
    final body = document.body?.text ?? '';
    if (RegExp(
      r'Object reference not set to an instance|Server Error in|Runtime Error',
    ).hasMatch(body)) {
      throw NicError(
        'PAGE_NOT_READY',
        body.substring(0, body.length.clamp(0, 800)),
      );
    }
    final message = MonthlyTasksWorker.portalRejection(document);
    if (message.isNotEmpty) throw NicError('PORTAL_MESSAGE', message);
    if (document.getElementById(classId) == null) {
      throw const NicError(
        'PAGE_NOT_READY',
        'Portal classes are not available for the selected session.',
      );
    }
    return document;
  }

  Future<Map<String, dynamic>> catalog(String requestedSchool) async {
    final school = requestedSchool.trim();
    try {
      _account(school);
      final base = baseUrl();
      if (!RegExp(
        r'^https://rajshaladarpan\.rajasthan\.gov\.in/SD[1-5]/?$',
        caseSensitive: false,
      ).hasMatch(base.toString())) {
        throw const NicError(
          'PAGE_NOT_READY',
          'Active school server base is invalid.',
        );
      }
      final url = Uri.parse(
        '${base.toString().replaceFirst(RegExp(r'/$'), '')}/$path',
      );
      var document = _response(
        await request(url, timeout: const Duration(seconds: 30)),
        url,
      );
      _account(school);
      final select = document.getElementById(sessionId);
      final session = sessionOption(options(select));
      if (session == null) {
        throw const NicError(
          'PAGE_NOT_READY',
          'Portal academic sessions are not available.',
        );
      }
      if (session['selected'] != true) {
        // The source performs no request when this selector has no onchange.
        if ((select!.attributes['onchange'] ?? '').isNotEmpty) {
          final name = select.attributes['name'];
          final postback = RegExp(
            r'''__doPostBack\s*\(\s*['"]([^'"]+)['"]\s*,\s*['"]['"]\s*\)''',
          ).firstMatch(select.attributes['onchange']!);
          if (name != sessionName || postback?.group(1) != name) {
            throw const NicError(
              'PAGE_NOT_READY',
              'Portal academic session postback could not be verified.',
            );
          }
          final form = AttendanceForm.enclosing(select);
          if (form == null)
            throw const NicError(
              'PAGE_NOT_READY',
              'Portal form is unavailable.',
            );
          final event = dom.Element.tag('a')
            ..attributes['href'] = "javascript:__doPostBack('$name','')";
          final fields = AttendanceForm.payload(form, event);
          fields[name!] = session['id'];
          // Request a complete WebForms document; do not send an async manager
          // field without the browser's MS-Ajax protocol headers.
          fields.removeWhere(
            (key, _) => key.toLowerCase().contains('scriptmanager'),
          );
          if (fields['__VIEWSTATE'] == null ||
              fields['__EVENTVALIDATION'] == null) {
            throw const NicError(
              'PAGE_NOT_READY',
              'Portal form state is incomplete.',
            );
          }
          // Browser select_option changes the selected DOM value before the
          // postback. An UpdatePanel may replace only the dependent classes.
          for (final option in select.querySelectorAll('option')) {
            option.attributes.remove('selected');
            if ((option.attributes['value'] ?? option.text) == session['id']) {
              option.attributes['selected'] = 'selected';
            }
          }
          _account(school);
          document = _response(
            await request(
              url,
              fields: fields,
              referer: url,
              timeout: const Duration(seconds: 30),
            ),
            url,
            previous: document,
          );
          _account(school);
          if (!options(document.getElementById(sessionId))
              .any((s) => s['selected'] == true && s['id'] == session['id'])) {
            throw const NicError(
              'MATCH_MISMATCH',
              'Portal academic session does not match the NIC request.',
            );
          }
        }
      }
      final classes = options(document.getElementById(classId));
      if (classes.isEmpty) {
        throw const NicError(
          'PAGE_NOT_READY',
          'Portal classes are not available for the selected session.',
        );
      }
      _account(school);
      return {
        'success': true,
        'school_id': school,
        'classes': classes,
        'session': session['id'],
        'session_label': session['label'],
      };
    } on NicError catch (e) {
      return failure(e.code, e.message);
    } on AttendanceWorkerError catch (e) {
      return failure(e.code, e.message);
    } on TimeoutException {
      return failure(
        'PORTAL_SLOW',
        'The native NIC portal operation timed out.',
      );
    } on IOException {
      return failure(
        'NETWORK_ERROR',
        'Could not connect to the school portal.',
      );
    }
  }
}
