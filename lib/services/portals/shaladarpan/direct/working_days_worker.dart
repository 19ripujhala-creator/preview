import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import 'ranking_http.dart';
import 'student_attendance_worker.dart';
import 'portal_messages.dart';

typedef WorkingDaysRequest = Future<AttendanceHttpReply> Function(
  Uri url, {
  Map<String, Object?>? fields,
  Uri? referer,
  bool mutation,
  Duration timeout,
});

class WorkingDaysError implements Exception {
  const WorkingDaysError(this.message, {this.attempted = false});
  final String message;
  final bool attempted;
  @override
  String toString() => message;
}

class WorkingDaysWorker {
  WorkingDaysWorker({
    required this.request,
    required this.baseUrl,
    required this.schoolId,
    required this.identity,
    required this.check,
  });
  final WorkingDaysRequest request;
  final Uri Function() baseUrl;
  final String Function() schoolId, identity;
  final void Function() check;
  static const path = 'Home/School/RMSA_MonthlySessionsEntry.aspx';
  static const prefix = 'ContentPlaceHolder1_ctl00_';
  static const sessionId = '${prefix}ddlSession';
  static const gridId = '${prefix}grdMonthlySession';
  static const months = [
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
    'Jan',
    'Feb',
    'Mar',
    'Apr',
  ];
  dom.Document? _document;
  String? _owner, _identity;
  bool _attempted = false;

  void _guard() {
    check();
    if (schoolId().isEmpty || identity().isEmpty) {
      throw const WorkingDaysError('School login is required.');
    }
    _owner ??= schoolId();
    _identity ??= identity();
    if (_owner != schoolId() || _identity != identity()) {
      _document = null;
      throw const WorkingDaysError(
        'School login has changed. Reopen Working Days.',
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
      throw const WorkingDaysError('Invalid School portal destination.');
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
      throw WorkingDaysError(
        'Working Days portal response could not be verified.',
        attempted: mutation,
      );
    }
    if (RegExp(r'^\d+\|').hasMatch(reply.html)) {
      if (_document == null) {
        throw const WorkingDaysError('Missing Working Days form state.');
      }
      final merged = html.parse(_document!.outerHtml);
      var panel = false;
      for (final (type, name, value) in RankingHttp.parseDelta(reply.html)) {
        if (type == 'error') throw WorkingDaysError(value, attempted: mutation);
        if (type == 'pageRedirect') {
          throw WorkingDaysError(
            'School session expired.',
            attempted: mutation,
          );
        }
        if (type == 'updatePanel') {
          final target = merged.getElementById(name);
          if (target == null) {
            throw const WorkingDaysError('Portal update panel is missing.');
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
        throw WorkingDaysError(
          'Incomplete Working Days response.',
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
        _document!.getElementById(sessionId) == null) {
      throw WorkingDaysError(
        'Working Days form is unavailable. Reopen the module.',
        attempted: mutation,
      );
    }
    if (freshOpen) _identity = identity();
  }

  Map<String, Object?> _payload(String action) {
    final doc = _document!;
    final button = doc.getElementById('$prefix$action');
    if (button == null || button.attributes.containsKey('disabled')) {
      throw const WorkingDaysError('Portal action is unavailable.');
    }
    final fields = AttendanceForm.payload(
      AttendanceForm.enclosing(button)!,
      button,
    );
    if (fields['__VIEWSTATE'] is! String ||
        fields['__EVENTVALIDATION'] is! String) {
      throw const WorkingDaysError(
        'Portal form tokens are missing. Reload Working Days.',
      );
    }
    fields['__EVENTTARGET'] = '';
    fields['__EVENTARGUMENT'] = '';
    fields['__ASYNCPOST'] = 'true';
    fields[r'ctl00$ScriptManager1'] =
        'ctl00\$ContentPlaceHolder1\$ctl00\$UpdPanel|${button.attributes['name']}';
    return fields;
  }

  Map<String, dynamic> _snapshot({required bool loaded}) {
    final doc = _document!;
    final rows = <Map<String, dynamic>>[];
    for (final row
        in doc.getElementById(gridId)?.querySelectorAll('tr') ??
            <dom.Element>[]) {
      final id = row
          .querySelector('input[id*="_hdnClass_"]')
          ?.attributes['value'];
      if (id == null || id.isEmpty) continue;
      if (rows.any((r) => r['id'] == id)) {
        throw const WorkingDaysError('Duplicate class returned by the portal.');
      }
      final cells = <String, Map<String, dynamic>>{};
      for (final month in months) {
        final input = row.querySelector('input[id*="_txt${month}_"]');
        if (input == null || input.attributes['name'] == null) {
          throw const WorkingDaysError(
            'A monthly field is missing. Reload Working Days.',
          );
        }
        final validator = doc
            .querySelectorAll('[controltovalidate]')
            .where((v) => v.attributes['controltovalidate'] == input.id)
            .firstOrNull;
        cells[month] = {
          'value': input.attributes['value'] ?? '',
          'name': input.attributes['name'],
          'enabled':
              !input.attributes.containsKey('disabled') &&
              !input.attributes.containsKey('readonly'),
          'max_length': int.tryParse(input.attributes['maxlength'] ?? '') ?? 2,
          'min': int.tryParse(validator?.attributes['minimumvalue'] ?? '') ?? 0,
          'max':
              int.tryParse(validator?.attributes['maximumvalue'] ?? '') ?? 99,
          'validation_message': validator?.attributes['errormessage'],
        };
      }
      rows.add({
        'id': id,
        'label': row.querySelector('[id*="_lblClassName_"]')?.text.trim() ?? id,
        'cells': cells,
      });
    }
    return {
      'success': true,
      'loaded': loaded,
      'session': selected(doc.getElementById(sessionId)),
      'sessions': [
        for (final option
            in doc.getElementById(sessionId)!.querySelectorAll('option'))
          if ((option.attributes['value'] ?? '').isNotEmpty &&
              !option.attributes.containsKey('disabled'))
            {'id': option.attributes['value']!, 'label': option.text.trim()},
      ],
      'rows': rows,
      'messages': _messages(),
      'can_save':
          doc.getElementById('${prefix}btn_SubmitAll') != null &&
          !doc
              .getElementById('${prefix}btn_SubmitAll')!
              .attributes
              .containsKey('disabled'),
    };
  }

  Future<void> _freshPage() async {
    check();
    final owner = schoolId();
    if (owner.isEmpty || identity().isEmpty)
      throw const WorkingDaysError('School login is required.');
    if (_owner != null && _owner != owner) _guard();
    _owner = owner;
    _identity = identity();
    _document = null;
    await _send(freshOpen: true);
  }

  Future<Map<String, dynamic>> open() async {
    await _freshPage();
    _attempted = false;
    return _snapshot(loaded: false);
  }

  Future<Map<String, dynamic>> load(String session) async {
    final result = await _load(session);
    _attempted = false;
    return result;
  }

  Future<Map<String, dynamic>> _load(String session) async {
    await _freshPage();
    final select = _document!.getElementById(sessionId)!;
    if (session.isEmpty ||
        !select
            .querySelectorAll('option')
            .any(
              (e) =>
                  e.attributes['value'] == session &&
                  !e.attributes.containsKey('disabled'),
            )) {
      throw const WorkingDaysError('Select a session offered by the portal.');
    }
    for (final option in select.querySelectorAll('option')) {
      option.attributes.remove('selected');
      if (option.attributes['value'] == session) {
        option.attributes['selected'] = 'selected';
      }
    }
    await _send(fields: _payload('btnShow'));
    if (selected(_document!.getElementById(sessionId)) != session) {
      throw const WorkingDaysError('Portal returned a different session.');
    }
    if (_document!.getElementById(gridId) == null) {
      throw WorkingDaysError(
        _messages().join('\n').isNotEmpty
            ? _messages().join('\n')
            : 'Working Days table was not returned.',
      );
    }
    return _snapshot(loaded: true);
  }

  Future<Map<String, dynamic>> save(
    String session,
    String month,
    Map<String, String> changes,
    Map<String, String> expected,
  ) async {
    _guard();
    if (_attempted) {
      throw const WorkingDaysError(
        'An update was already attempted. Reload and verify the data before submitting again.',
        attempted: true,
      );
    }
    if (!months.contains(month) ||
        changes.isEmpty ||
        changes.keys.toSet().difference(expected.keys.toSet()).isNotEmpty) {
      throw const WorkingDaysError('No valid changes were selected.');
    }
    final fresh = await _load(session);
    final rows = (fresh['rows'] as List).cast<Map<String, dynamic>>();
    final updates = <String, String>{};
    for (final change in changes.entries) {
      final row = rows.where((r) => r['id'] == change.key).firstOrNull;
      if (row == null) {
        throw const WorkingDaysError(
          'Class list changed. Reload and review your entry.',
        );
      }
      final cell = (row['cells'] as Map)[month] as Map;
      if (cell['enabled'] != true || cell['value'] != expected[change.key]) {
        throw const WorkingDaysError(
          'Portal data or permissions changed. Reload and review your entry.',
        );
      }
      final number = int.tryParse(change.value);
      if (!RegExp(r'^\d+$').hasMatch(change.value) ||
          change.value.length > (cell['max_length'] as int) ||
          number == null ||
          number < (cell['min'] as int) ||
          number > (cell['max'] as int)) {
        throw WorkingDaysError(
          cell['validation_message'] as String? ??
              'Enter valid whole working days for Class ${row['label']}.',
        );
      }
      updates[cell['name'] as String] = change.value;
    }
    final payload = _payload('btn_SubmitAll')..addAll(updates);
    _guard();
    _attempted = true;
    try {
      await _send(fields: payload, mutation: true);
      final messages = _messages();
      final original = messages.join('\n');
      final success =
          _document!
              .querySelector('.alert-success')
              ?.text
              .contains('Data has been added successfully.') ==
          true;
      if (!success) {
        return {
          'success': false,
          'message': original.isNotEmpty
              ? original
              : 'Portal save result could not be confirmed.',
          'submission_attempted': true,
        };
      }
      Map<String, dynamic>? readBack;
      var verified = false;
      try {
        readBack = await _load(session);
        final current = (readBack['rows'] as List).cast<Map<String, dynamic>>();
        verified = rows.every(
          (before) => current.any(
            (after) =>
                after['id'] == before['id'] &&
                months.every((m) {
                  final wanted = m == month && changes.containsKey(before['id'])
                      ? changes[before['id']]
                      : ((before['cells'] as Map)[m] as Map)['value'];
                  return ((after['cells'] as Map)[m] as Map)['value'] == wanted;
                }),
          ),
        );
      } catch (_) {
        /* Keep the original portal success, without claiming verification. */
      }
      if (verified) _attempted = false;
      return {
        'success': true,
        'message': original,
        'verified': verified,
        'submission_attempted': true,
        if (readBack != null) 'snapshot': readBack,
      };
    } catch (error) {
      throw WorkingDaysError('$error', attempted: true);
    }
  }
}
