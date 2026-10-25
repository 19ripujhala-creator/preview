import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import 'ranking_http.dart';
import 'student_attendance_worker.dart';
import 'portal_messages.dart';

typedef MonthlyAttendanceRequest = Future<AttendanceHttpReply> Function(
  Uri url, {
  Map<String, Object?>? fields,
  Uri? referer,
  bool mutation,
  Duration timeout,
});

class MonthlyAttendanceError implements Exception {
  const MonthlyAttendanceError(this.message, {this.attempted = false});
  final String message;
  final bool attempted;
  @override
  String toString() => message;
}

class MonthlyAttendanceWorker {
  MonthlyAttendanceWorker({
    required this.request,
    required this.baseUrl,
    required this.schoolId,
    required this.identity,
    required this.check,
  });
  final MonthlyAttendanceRequest request;
  final Uri Function() baseUrl;
  final String Function() schoolId, identity;
  final void Function() check;
  static const path = 'Home/School/StudentAttendence.aspx';
  static const prefix = 'ContentPlaceHolder1_footer2_';
  static const sessionId = '${prefix}ddlsession';
  static const gridId = '${prefix}gvattendence';
  static const classId = '${prefix}ddlclass';
  static const sectionId = '${prefix}ddlsection';
  static const monthId = '${prefix}ddlmonth';
  dom.Document? _document;
  String? _owner, _identity;
  bool _attempted = false;
  final _responseScripts = <String>[];

  void _guard() {
    check();
    if (schoolId().isEmpty || identity().isEmpty) {
      throw const MonthlyAttendanceError('School login is required.');
    }
    _owner ??= schoolId();
    _identity ??= identity();
    if (_owner != schoolId() || _identity != identity()) {
      _document = null;
      throw const MonthlyAttendanceError(
        'School login has changed. Reopen Monthly Attendance.',
      );
    }
  }

  Uri get _endpoint {
    final base = baseUrl();
    if (base.scheme != 'https' ||
        base.host != 'rajshaladarpan.rajasthan.gov.in' ||
        !RegExp(r'^/SD[1-5]/$').hasMatch(base.path) ||
        base.hasQuery ||
        base.hasFragment) {
      throw const MonthlyAttendanceError('Invalid School portal destination.');
    }
    return base.resolve(path);
  }

  static String selected(dom.Element? select) {
    final options = select?.querySelectorAll('option') ?? <dom.Element>[];
    return (options
                    .where((e) => e.attributes.containsKey('selected'))
                    .firstOrNull ??
                options.firstOrNull)
            ?.attributes['value'] ??
        '';
  }

  List<String> _messages() {
    final copy = html.parse(_document!.outerHtml);
    for (final close in copy.querySelectorAll(
      '[data-dismiss="alert"], [data-bs-dismiss="alert"], .alert .close',
    )) {
      close.remove();
    }
    for (final value in _responseScripts) {
      copy.body?.append(dom.Element.tag('script')..text = value);
    }
    return SchoolPortalMessages.fromDocument(copy);
  }

  Future<void> _send({
    Map<String, Object?>? fields,
    bool mutation = false,
    bool freshOpen = false,
  }) async {
    _guard();
    final endpoint = _endpoint;
    final reply = await request(
      endpoint,
      fields: fields,
      referer: fields == null ? null : endpoint,
      mutation: mutation,
      timeout: Duration(seconds: mutation ? 45 : 30),
    );
    if (freshOpen && fields == null && !mutation) {
      check();
      if (schoolId() != _owner || identity().isEmpty) _guard();
    } else {
      _guard();
    }
    if (reply.status != 200 ||
        reply.url.scheme != endpoint.scheme ||
        reply.url.authority != endpoint.authority ||
        reply.url.path.toLowerCase() != endpoint.path.toLowerCase()) {
      throw MonthlyAttendanceError(
        'Monthly Attendance portal response could not be verified.',
        attempted: mutation,
      );
    }
    _responseScripts.clear();
    if (RegExp(r'^\d+\|').hasMatch(reply.html)) {
      if (_document == null) {
        throw const MonthlyAttendanceError(
          'Missing Monthly Attendance form state.',
        );
      }
      final merged = html.parse(_document!.outerHtml);
      var panel = false;
      for (final (type, name, value) in RankingHttp.parseDelta(reply.html)) {
        if (type == 'error') {
          throw MonthlyAttendanceError(value, attempted: mutation);
        }
        if (type == 'pageRedirect') {
          throw MonthlyAttendanceError(
            'School session expired.',
            attempted: mutation,
          );
        }
        if ((type == 'scriptStartupBlock' || type == 'scriptBlock') &&
            name == 'ScriptContentNoTags') {
          _responseScripts.add(value);
        }
        if (type == 'updatePanel') {
          final target = merged.getElementById(name);
          if (target == null) {
            throw const MonthlyAttendanceError(
              'Portal update panel is missing.',
            );
          }
          target.innerHtml = value;
          panel = true;
        } else if (type == 'hiddenField') {
          var target = merged.getElementById(name);
          if (target == null) {
            target = dom.Element.tag('input')
              ..attributes.addAll({'type': 'hidden', 'id': name, 'name': name});
            merged.querySelector('form')?.append(target);
          }
          target.attributes['value'] = value;
        } else if (type == 'expando') {
          final match = RegExp(
            r'''document\.getElementById\(['"]([^'"]+)['"]\)\[['"]([^'"]+)['"]\]''',
          ).firstMatch(name);
          if (match != null) {
            final decoded = jsonDecode(value);
            merged.getElementById(match[1]!)?.attributes[match[2]!
                    .toLowerCase()] =
                '$decoded';
          }
        } else if (type == 'formAction') {
          merged.querySelector('form')?.attributes['action'] = value;
        }
      }
      if (!panel) {
        throw MonthlyAttendanceError(
          'Incomplete Monthly Attendance response.',
          attempted: mutation,
        );
      }
      _document = merged;
    } else {
      _document = html.parse(reply.html);
    }
    final form = _document!.querySelector('form');
    final action = endpoint.resolve(
      form?.attributes['action'] ?? endpoint.toString(),
    );
    if (form == null ||
        action.scheme != endpoint.scheme ||
        action.authority != endpoint.authority ||
        action.path.toLowerCase() != endpoint.path.toLowerCase() ||
        action.hasQuery ||
        action.hasFragment ||
        [
          sessionId,
          classId,
          sectionId,
          monthId,
        ].any((id) => _document!.getElementById(id) == null)) {
      throw MonthlyAttendanceError(
        'Monthly Attendance form is unavailable. Reopen the module.',
        attempted: mutation,
      );
    }
    if (freshOpen) _identity = identity();
  }

  Map<String, Object?> _payload(String action) {
    final doc = _document!;
    final button = doc.getElementById('$prefix$action');
    if (button == null || button.attributes.containsKey('disabled')) {
      throw const MonthlyAttendanceError('Portal action is unavailable.');
    }
    final fields = AttendanceForm.payload(
      AttendanceForm.enclosing(button)!,
      button,
    );
    if (fields['__VIEWSTATE'] is! String ||
        fields['__EVENTVALIDATION'] is! String) {
      throw const MonthlyAttendanceError(
        'Portal form tokens are missing. Reload Monthly Attendance.',
      );
    }
    fields['__EVENTTARGET'] = '';
    fields['__EVENTARGUMENT'] = '';
    fields['__ASYNCPOST'] = 'true';
    fields[r'ctl00$ScriptManager1'] =
        'ctl00\$ContentPlaceHolder1\$footer2\$UpdPanel|${button.attributes['name']}';
    return fields;
  }

  static bool enabled(dom.Element? e) {
    if (e == null ||
        e.attributes.containsKey('disabled') ||
        e.attributes.containsKey('readonly')) {
      return false;
    }
    for (var parent = e.parent; parent != null; parent = parent.parent) {
      if (parent.localName == 'fieldset' &&
          parent.attributes.containsKey('disabled')) {
        return false;
      }
    }
    return true;
  }

  List<Map<String, String>> _options(String id) => [
    for (final e in _document!.getElementById(id)!.querySelectorAll('option'))
      if ((e.attributes['value'] ?? '').isNotEmpty && enabled(e))
        {'id': e.attributes['value']!, 'label': e.text.trim()},
  ];

  Map<String, dynamic> _snapshot({bool loaded = false}) {
    final rows = <Map<String, dynamic>>[];
    for (final row
        in _document!.getElementById(gridId)?.querySelectorAll('tr') ??
            <dom.Element>[]) {
      final input = row.querySelector('input[id*="_txtatt_"]');
      if (input == null) continue;
      String hidden(String suffix) =>
          row.querySelector('input[id*="_${suffix}_"]')?.attributes['value'] ??
          '';
      final yearly = hidden('hdnyearlyprofileid'),
          student = hidden('hdnstudentprofileid');
      final id = '$yearly/$student';
      final maximum = int.tryParse(
        row.querySelector('[id*="_lblmaxatt_"]')?.text.trim() ?? '',
      );
      final field = input.attributes['name'];
      if (['hdnyearlyprofileid', 'hdnstudentprofileid', 'hdnStuAttID'].any(
            (key) => row.querySelector('input[id*="_${key}_"][name]') == null,
          ) ||
          yearly.isEmpty ||
          student.isEmpty ||
          field == null ||
          maximum == null ||
          maximum < 0 ||
          rows.any((r) => r['id'] == id || r['field'] == field)) {
        throw const MonthlyAttendanceError(
          'Student attendance data is incomplete or duplicated. Reload the list.',
        );
      }
      rows.add({
        'id': id,
        'field': field,
        'yearly_id': yearly,
        'student_id': student,
        'attendance_id': hidden('hdnStuAttID'),
        'sr_no': row.querySelector('[id*="_lblsrno_"]')?.text.trim() ?? '',
        'name': row.querySelector('[id*="_lblname_"]')?.text.trim() ?? '',
        'working_days': maximum,
        'value': input.attributes['value'] ?? '',
        'max_length': int.tryParse(input.attributes['maxlength'] ?? '') ?? 2,
        'enabled': enabled(input) && maximum > 0,
      });
    }
    return {
      'success': true,
      'loaded': loaded,
      'rows': rows,
      'messages': _messages(),
      'sessions': _options(sessionId),
      'classes': _options(classId),
      'sections': _options(sectionId),
      'months': _options(monthId),
      'session': selected(_document!.getElementById(sessionId)),
      'class_id': selected(_document!.getElementById(classId)),
      'section': selected(_document!.getElementById(sectionId)),
      'month': selected(_document!.getElementById(monthId)),
      'can_save': enabled(_document!.getElementById('${prefix}btnsave')),
    };
  }

  Future<Map<String, dynamic>> open() async {
    final result = await _open();
    _attempted = false;
    return result;
  }

  Future<Map<String, dynamic>> _open() async {
    check();
    final owner = schoolId();
    if (owner.isEmpty || identity().isEmpty) {
      throw const MonthlyAttendanceError('School login is required.');
    }
    if (_owner != null && _owner != owner) _guard();
    _owner = owner;
    _identity = identity();
    _document = null;
    await _send(freshOpen: true);
    return _snapshot();
  }

  Future<Map<String, dynamic>> load(
    String session,
    String klass,
    String section,
    String month,
  ) async {
    final result = await _load(session, klass, section, month);
    _attempted = false;
    return result;
  }

  Future<Map<String, dynamic>> _load(
    String session,
    String klass,
    String section,
    String month,
  ) async {
    await _open();
    final choices = {
      sessionId: session,
      classId: klass,
      sectionId: section,
      monthId: month,
    };
    for (final entry in choices.entries) {
      final select = _document!.getElementById(entry.key)!;
      if (entry.value.isEmpty ||
          !enabled(select) ||
          !_options(entry.key).any((o) => o['id'] == entry.value)) {
        throw const MonthlyAttendanceError(
          'Select the session, class, section and month offered by the portal.',
        );
      }
      // The captured form has independent selectors and one Show postback.
      // Do not invent dependent postbacks if the portal changes this contract.
      if ((select.attributes['onchange'] ?? '').contains('__doPostBack')) {
        throw const MonthlyAttendanceError(
          'Portal selection flow changed. Reopen the module and report this page.',
        );
      }
      for (final option in select.querySelectorAll('option')) {
        option.attributes.remove('selected');
        if (option.attributes['value'] == entry.value) {
          option.attributes['selected'] = 'selected';
        }
      }
    }
    await _send(fields: _payload('btnshow'));
    if (choices.entries.any(
      (e) => selected(_document!.getElementById(e.key)) != e.value,
    )) {
      throw const MonthlyAttendanceError(
        'Portal returned a different class, section, month or session. Reload the list.',
      );
    }
    if (_document!.getElementById(gridId) == null && _messages().isEmpty) {
      throw const MonthlyAttendanceError(
        'Student attendance list was not returned.',
      );
    }
    return _snapshot(loaded: true);
  }

  Future<Map<String, dynamic>> save(
    String session,
    String klass,
    String section,
    String month,
    Map<String, String> changes,
    List<Map<String, dynamic>> expected,
  ) async {
    _guard();
    if (_attempted) {
      throw const MonthlyAttendanceError(
        'A save was already attempted. Reload and verify attendance before submitting again.',
        attempted: true,
      );
    }
    if (changes.isEmpty ||
        expected.isEmpty ||
        changes.keys.any((id) => !expected.any((r) => r['id'] == id))) {
      throw const MonthlyAttendanceError(
        'No valid attendance changes were selected.',
      );
    }
    final fresh = await _load(session, klass, section, month);
    final rows = (fresh['rows'] as List).cast<Map<String, dynamic>>();
    // This native Save submits every student. Never overwrite an unseen edit or
    // accept row-index reassignment after a class roster change.
    if (rows.length != expected.length ||
        rows.any(
          (r) => !expected.any(
            (e) =>
                e['id'] == r['id'] &&
                e['attendance_id'] == r['attendance_id'] &&
                e['working_days'] == r['working_days'] &&
                e['value'] == r['value'] &&
                e['enabled'] == r['enabled'],
          ),
        )) {
      throw const MonthlyAttendanceError(
        'Attendance, working days or student list changed on the portal. Reload and review.',
      );
    }
    final payload = _payload('btnsave');
    final normalized = <String, String>{};
    for (final change in changes.entries) {
      final row = rows.singleWhere((r) => r['id'] == change.key);
      final value = int.tryParse(change.value);
      if (row['enabled'] != true ||
          !RegExp(r'^\d+$').hasMatch(change.value) ||
          value == null ||
          change.value.length > (row['max_length'] as int) ||
          value < 0 ||
          value > (row['working_days'] as int)) {
        throw MonthlyAttendanceError(
          'Enter attendance from 0 to ${row['working_days']} for ${row['name']}.',
        );
      }
      normalized[change.key] = value.toString();
      payload[row['field'] as String] = value.toString();
    }
    _guard();
    _attempted = true;
    List<String> messages = [];
    try {
      await _send(fields: payload, mutation: true);
      messages = _messages();
      final portalError =
          _document!.querySelector(
            '.alert-danger, .alert-error, .validation-summary-errors',
          ) !=
          null;
      // No captured Save-success wording is assumed. A new read verifies actual
      // persisted values, including all untouched students.
      final readBack = await _load(session, klass, section, month);
      final after = (readBack['rows'] as List).cast<Map<String, dynamic>>();
      final verified =
          !portalError &&
          after.length == rows.length &&
          rows.every(
            (r) => after.any(
              (a) =>
                  a['id'] == r['id'] &&
                  a['working_days'] == r['working_days'] &&
                  a['value'] == (normalized[r['id']] ?? r['value']),
            ),
          );
      _attempted = !verified;
      return {
        'success': verified,
        'verified': verified,
        'submission_attempted': true,
        'snapshot': readBack,
        'message': messages.isNotEmpty
            ? messages.join('\n')
            : verified
            ? 'Monthly attendance saved and verified on the portal.'
            : 'Save could not be verified. Reload and check attendance before trying again.',
      };
    } catch (e) {
      _attempted = true;
      throw MonthlyAttendanceError(
        messages.isEmpty
            ? '$e'
            : '${messages.join('\n')}\nSave verification is unavailable. Reload and check attendance.',
        attempted: true,
      );
    }
  }
}
