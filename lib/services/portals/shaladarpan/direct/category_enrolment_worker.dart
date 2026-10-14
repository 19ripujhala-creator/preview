/// Complete conversion of category_enrolment_worker.py. Read-only WebForms report.
import 'dart:async';
import 'dart:io';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import '../../../core/direct/async_primitives.dart';
import 'student_attendance_worker.dart';

typedef CategoryEnrolmentRequest = Future<AttendanceHttpReply> Function(
  Uri url, {
  Map<String, Object?>? fields,
  Uri? referer,
  String? sessionControl,
  Duration timeout,
});

class EnrolmentReportError implements Exception {
  const EnrolmentReportError(this.code, this.message);
  final String code, message;
  @override
  String toString() => message;
}

class _ReportHtml {
  _ReportHtml(String source) : document = html.parse(source) {
    // HTMLParser records span/a text on closing tags: inner nodes close first.
    void visit(dom.Node n) {
      for (final child in n.nodes) {
        visit(child);
      }
      if (n is dom.Element &&
          ['span', 'a'].contains(n.localName) &&
          n.id.isNotEmpty) {
        text[n.id] = n.text.trim().replaceAll(RegExp(r'\s+'), ' ');
      }
    }

    visit(document);
    for (final input in document.querySelectorAll('input[name]')) {
      if ((input.attributes['type'] ?? '').toLowerCase() == 'hidden') {
        hidden[input.attributes['name']!] = input.attributes['value'] ?? '';
      }
    }
    for (final select in document.querySelectorAll(
      'select#ContentPlaceHolder1_ddlSession',
    )) {
      for (final option in select.querySelectorAll('option')) {
        final value = option.attributes['value'] ?? '';
        sessions.add(value);
        if (option.attributes.containsKey('selected')) selectedSession = value;
      }
    }
  }
  final dom.Document document;
  final text = <String, String>{}, hidden = <String, String>{};
  final sessions = <String>[];
  String selectedSession = '';
}

class CategoryEnrolmentWorker {
  CategoryEnrolmentWorker({
    required this.request,
    required this.baseUrl,
    required this.schoolId,
    this.check,
  });
  final CategoryEnrolmentRequest request;
  final Uri Function() baseUrl;
  final String Function() schoolId;
  final void Function()? check;
  static const path = 'Home/School/GenderWiseSchoolStudentReport.aspx';
  static const prefix = 'ContentPlaceHolder1_rptSchoolReport_';
  static const mappings = <String, List<String>>{
    'general': ['lblTotalGeneralBoys', 'lblTotalGeneralGirls', 'Label26'],
    'st': ['lblTotalSTBoys', 'lblTotalSTGirls', 'Label27'],
    'sc': ['lblTotalSCBoys', 'lblTotalSCGirls', 'Label28'],
    'obc': ['lblTotalOBCBoys', 'lblTotalOBCGirls', 'Label29'],
    'sbc': ['lblTotalSBCBoys', 'lblTotalSBCGirls', 'Label31'],
    'total': ['lblTotalClassStudent', 'Label35', 'Label36'],
    'minority': ['Label41', 'Label42', 'Label43'],
  };
  static Never _invalid(String message) =>
      throw EnrolmentReportError('ENROLMENT_REPORT_INCOMPLETE', message);
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
  static int _count(_ReportHtml doc, String id) {
    final value = doc.text[id];
    if (value == null || !RegExp(r'^[0-9]+$').hasMatch(_decimal(value))) {
      _invalid('Missing/invalid enrolment count: $id.');
    }
    return int.parse(_decimal(value));
  }

  static Map<String, int> _trio(_ReportHtml doc, List<String> ids) {
    final result = {
      'boys': _count(doc, ids[0]),
      'girls': _count(doc, ids[1]),
      'total': _count(doc, ids[2]),
    };
    if (result['boys']! + result['girls']! != result['total']) {
      _invalid('Portal enrolment Boys/Girls/Total do not reconcile.');
    }
    return result;
  }

  static Map<String, dynamic> parse(
    String source,
    String schoolId, {
    String? session,
  }) {
    final doc = _ReportHtml(source);
    final header = doc.text['ContentPlaceHolder1_spn_SCHName'] ?? '';
    final match = RegExp(r'^(.+?)\s*\(([^()]+)\)\s*\(([^()]+)\)$')
        .firstMatch(header);
    if (match == null ||
        !RegExp(r'^[0-9]+$').hasMatch(_decimal(match.group(2)!)) ||
        !RegExp(r'^[0-9]{11}$').hasMatch(_decimal(match.group(3)!)) ||
        match.group(2) != schoolId) {
      _invalid(
        'Report school identity is missing or does not match the logged-in school.',
      );
    }
    final selected = doc.selectedSession;
    if (selected.isEmpty ||
        (session != null && session.isNotEmpty && selected != session)) {
      _invalid(
        'Report academic session is missing or does not match the request.',
      );
    }
    final indices = <int>[];
    final pattern = RegExp('^${prefix}lblBlockCode_([0-9]+)\$');
    for (final key in doc.text.keys) {
      final m = pattern.firstMatch(key);
      if (m != null) indices.add(int.parse(m.group(1)!));
    }
    indices.sort();
    if (indices.isEmpty) _invalid('Class-wise category rows are unavailable.');
    final groups = <String, Map<String, Map<String, int>>>{
      for (final group in [
        'pre_primary',
        'primary',
        'upper_primary',
        'secondary',
      ])
        group: {
          for (final category in mappings.keys)
            category: {'boys': 0, 'girls': 0, 'total': 0},
        },
    };
    final rows = <Map<String, dynamic>>[], classes = <String>{};
    for (final index in indices) {
      final className = doc.text['${prefix}lblBlockCode_$index']!;
      if (!classes.add(className))
        _invalid('Duplicate class rows in enrolment report.');
      late String group;
      if (['nursery', 'lkg', 'ukg'].contains(className.toLowerCase()))
        group = 'pre_primary';
      else {
        final normal = _decimal(className);
        final grade = RegExp(r'^[0-9]+$').hasMatch(normal)
            ? int.tryParse(normal)
            : null;
        if (grade == null || grade < 1 || grade > 12)
          _invalid('Unrecognized portal class: $className.');
        group = grade <= 5
            ? 'primary'
            : grade <= 8
            ? 'upper_primary'
            : 'secondary';
      }
      final values = {
        for (final entry in mappings.entries)
          entry.key: _trio(
            doc,
            entry.value.map((label) => '$prefix${label}_$index').toList(),
          ),
      };
      for (final field in ['boys', 'girls', 'total']) {
        final sum = [
          'general',
          'st',
          'sc',
          'obc',
          'sbc',
        ].fold<int>(0, (n, c) => n + values[c]![field]!);
        if (sum != values['total']![field])
          _invalid('Category counts do not reconcile with class enrolment.');
        if (values['minority']![field]! > values['total']![field]!)
          _invalid('Minority count exceeds class enrolment.');
        for (final cat in mappings.keys) {
          groups[group]![cat]![field] =
              groups[group]![cat]![field]! + values[cat]![field]!;
        }
      }
      rows.add({'class_name': className, 'group': group, 'categories': values});
    }
    final totals = {
      for (final cat in mappings.keys)
        cat: {
          for (final field in ['boys', 'girls', 'total'])
            field: groups.values.fold<int>(0, (n, g) => n + g[cat]![field]!),
        },
    };
    final footer = _trio(doc, [
      'ContentPlaceHolder1_lbltotal_Boys',
      'ContentPlaceHolder1_lbltotal_Girls',
      'ContentPlaceHolder1_lbltotal_Stu',
    ]);
    if (footer.keys.any((field) => totals['total']![field] != footer[field])) {
      _invalid('Class rows do not reconcile with portal grand total.');
    }
    return {
      'success': true,
      'complete': true,
      'school_id': match.group(2),
      'udise': match.group(3),
      'school_name': match.group(1)!.trim(),
      'session': selected,
      'classes': rows,
      'groups': groups,
      'totals': totals,
    };
  }

  static String _responseHtml(AttendanceHttpReply reply) {
    final soup = html.parse(reply.html), path = reply.url.path.toLowerCase();
    if (RegExp(r'(officelogin|login\.aspx|default\.aspx|/public)')
            .hasMatch(path) ||
        soup.querySelector('#bodyContent_txtUName, #txtUserId') != null ||
        reply.status == 401) {
      throw const EnrolmentReportError(
        'SESSION_EXPIRED',
        'School portal session expired.',
      );
    }
    if (reply.status < 200 || reply.status >= 300) {
      throw EnrolmentReportError(
        'PORTAL_RESPONSE_ERROR',
        'Enrolment report HTTP status ${reply.status}.',
      );
    }
    if (reply.url.scheme != 'https' ||
        reply.url.host != 'rajshaladarpan.rajasthan.gov.in' ||
        !RegExp(
          r'^/SD[0-9]+/Home/School/GenderWiseSchoolStudentReport\.aspx$',
          caseSensitive: false,
        ).hasMatch(reply.url.path)) {
      _invalid('Report request redirected away from the authenticated report.');
    }
    return reply.html;
  }

  static ({Uri action, Map<String, Object?> fields, String control})
  sessionPostback(String source, Uri url, String session) {
    final soup = html.parse(source);
    // Select and its form are from the same parsed DOM.
    final control = soup.getElementById('ContentPlaceHolder1_ddlSession');
    final form = control == null ? null : AttendanceForm.enclosing(control);
    if (control == null ||
        form == null ||
        (control.attributes['name'] ?? '').isEmpty ||
        control.attributes.containsKey('disabled')) {
      _invalid('Academic session form is missing or disabled.');
    }
    if (!control
        .querySelectorAll('option')
        .any(
          (o) =>
              !o.attributes.containsKey('disabled') &&
              (o.attributes['value'] ?? '') == session,
        )) {
      _invalid('Requested academic session is unavailable.');
    }
    final action = url.resolve(form.attributes['action'] ?? url.toString());
    if (action.scheme != 'https' ||
        action.authority != url.authority ||
        action.path.toLowerCase() != url.path.toLowerCase()) {
      _invalid('Unexpected academic session form destination.');
    }
    final fields = <String, Object?>{};
    for (final field in form.querySelectorAll(
      'input[name],select[name],textarea[name]',
    )) {
      if (field.attributes.containsKey('disabled')) continue;
      final name = field.attributes['name']!;
      Object value;
      if (field.localName == 'input') {
        final kind = (field.attributes['type'] ?? 'text').toLowerCase();
        if (['submit', 'button', 'image', 'file', 'reset'].contains(kind))
          continue;
        if (['radio', 'checkbox'].contains(kind) &&
            !field.attributes.containsKey('checked'))
          continue;
        value =
            field.attributes['value'] ??
            (['radio', 'checkbox'].contains(kind) ? 'on' : '');
      } else if (field.localName == 'select') {
        final options = field
            .querySelectorAll('option')
            .where((o) => !o.attributes.containsKey('disabled'))
            .toList();
        var selected = options
            .where((o) => o.attributes.containsKey('selected'))
            .toList();
        if (selected.isEmpty &&
            options.isNotEmpty &&
            !field.attributes.containsKey('multiple'))
          selected = [options.first];
        value = selected.map((o) => o.attributes['value'] ?? o.text).toList();
      } else {
        value = field.text;
      }
      if (fields.containsKey(name)) {
        final old = fields[name];
        fields[name] = [
          if (old is List) ...old else old,
          if (value is List) ...value else value,
        ];
      } else {
        fields[name] = value;
      }
    }
    if (fields['__VIEWSTATE'] == null ||
        fields['__VIEWSTATE'] == '' ||
        (fields['__VIEWSTATE'] is List &&
            (fields['__VIEWSTATE'] as List).isEmpty)) {
      _invalid('ASP.NET form state is unavailable.');
    }
    final name = control.attributes['name']!;
    fields.addAll({
      '__EVENTTARGET': name,
      '__EVENTARGUMENT': '',
      name: session,
    });
    fields.remove('__ASYNCPOST');
    return (action: action, fields: fields, control: name);
  }

  static Map<String, dynamic> failure(String code, String message) => {
    'success': false,
    'complete': false,
    'code': code,
    'message': message,
  };
  void _check() {
    OperationCancellation.current?.check();
    check?.call();
  }

  Future<Map<String, dynamic>> fetch({
    String? requestedSchoolId,
    Object? session,
  }) async {
    try {
      final base = baseUrl(),
          school =
              (requestedSchoolId == null || requestedSchoolId.isEmpty
                      ? schoolId()
                      : requestedSchoolId)
                  .trim();
      if (session != null &&
          session != '' &&
          (session is! String ||
              !RegExp(r'^[0-9]{4}-[0-9]{2}$').hasMatch(_decimal(session)))) {
        _invalid('Academic session must use YYYY-YY.');
      }
      if (base.scheme != 'https' ||
          base.host != 'rajshaladarpan.rajasthan.gov.in' ||
          base.port != 443 ||
          base.userInfo.isNotEmpty ||
          base.hasQuery ||
          base.hasFragment ||
          !RegExp(r'^/SD[0-9]+/?$', caseSensitive: false).hasMatch(base.path))
        _invalid('Active ShalaDarpan server base is invalid.');
      if (school.isEmpty || school != schoolId().trim()) {
        throw const EnrolmentReportError(
          'ACCOUNT_CHANGED',
          'Requested school does not match the active login. Fetch again after login.',
        );
      }
      _check();
      final url = Uri.parse(
        '${base.toString().replaceFirst(RegExp(r'/+$'), '')}/$path',
      );
      var response = await request(url, timeout: const Duration(seconds: 30));
      _check();
      var source = _responseHtml(response);
      if (session is String &&
          session.isNotEmpty &&
          _ReportHtml(source).selectedSession != session) {
        final post = sessionPostback(source, response.url, session);
        _check();
        response = await request(
          post.action,
          fields: post.fields,
          referer: response.url,
          sessionControl: post.control,
          timeout: const Duration(seconds: 30),
        );
        _check();
        source = _responseHtml(response);
      }
      if (school != schoolId().trim())
        throw const EnrolmentReportError(
          'ACCOUNT_CHANGED',
          'School account changed while fetching the report.',
        );
      return parse(source, school, session: session is String ? session : null);
    } on EnrolmentReportError catch (e) {
      return failure(e.code, e.message);
    } on TimeoutException {
      return failure('PORTAL_SLOW', 'Enrolment report request timed out.');
    } on IOException {
      return failure(
        'NETWORK_ERROR',
        'Could not connect to the enrolment report.',
      );
    }
  }
}
