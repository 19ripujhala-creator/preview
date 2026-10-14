/// Behavior-preserving conversion of the uploaded class_mapping_worker.py.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import '../portal_state.dart';
import '../../../core/direct/async_primitives.dart';
import 'student_attendance_worker.dart';

class MappingError implements Exception {
  const MappingError(this.code, this.message);
  final String code, message;
  @override
  String toString() => message;
}

typedef MappingRequest = Future<AttendanceHttpReply> Function(
  Uri url, {
  Map<String, Object?>? fields,
  Uri? referer,
  String? saveControl,
  Duration timeout,
});
String _text(dom.Node node) {
  final parts = <String>[];
  void visit(dom.Node n) {
    if (n is dom.Text) {
      final t = n.data.trim();
      if (t.isNotEmpty) parts.add(t);
    } else {
      if (n is dom.Element &&
          ['script', 'style', 'template'].contains(n.localName))
        return;
      for (final child in n.nodes) {
        visit(child);
      }
    }
  }

  visit(node);
  return parts.join(' ');
}

Never _fail(String code, String message) => throw MappingError(code, message);
String _str(Object? value) => value?.toString() ?? '';

class ClassMappingWorker {
  ClassMappingWorker({
    required this.request,
    required this.baseUrl,
    required this.schoolId,
    required this.sessionKey,
    this.check,
    this.clock,
  });
  final MappingRequest request;
  final Uri Function() baseUrl;
  final String Function() schoolId, sessionKey;
  final void Function()? check;
  final double Function()? clock;
  final Stopwatch _clock = Stopwatch()..start();
  double get _now => clock?.call() ?? _clock.elapsedMicroseconds / 1000000;
  Map<int, String>? _review;
  String? _reviewKey;
  double _reviewAt = 0;
  static const path = 'Home/School/TeacherClassMapping.aspx';
  static const gridId = 'ContentPlaceHolder1_grdList';
  void _check(String key) {
    OperationCancellation.current?.check();
    check?.call();
    if (key.isEmpty || key != sessionKey())
      _fail(
        'ACCOUNT_CHANGED',
        'School login session changed. Fetch class mapping again.',
      );
  }

  ({String key, Uri url}) _session() {
    final base = baseUrl(), school = schoolId().trim();
    if (base.port != 443 ||
        base.userInfo.isNotEmpty ||
        base.scheme != 'https' ||
        base.host != 'rajshaladarpan.rajasthan.gov.in' ||
        !RegExp(r'^/SD[1-5]/?$', caseSensitive: false).hasMatch(base.path) ||
        base.hasQuery ||
        base.hasFragment)
      _fail('PAGE_NOT_READY', 'Active school server base is invalid.');
    final key = sessionKey();
    if (school.isEmpty || key.isEmpty)
      _fail(
        'ACCOUNT_CHANGED',
        'School account changed. Fetch class mapping again.',
      );
    _check(key);
    if (_reviewKey != key || _now - _reviewAt > 180) {
      _review = null;
      _reviewKey = null;
    }
    return (
      key: key,
      url: Uri.parse('${base.toString().replaceFirst(RegExp(r'/$'), '')}/')
          .resolve(path),
    );
  }

  static ({dom.Document soup, List<Map<String, dynamic>> rows}) parse(
    String source,
  ) {
    final soup = html.parse(source), grid = soup.getElementById(gridId);
    if (grid == null || grid.localName != 'table')
      _fail('PAGE_NOT_READY', 'Class mapping table not found on portal.');
    final rows = <Map<String, dynamic>>[], seen = <int>{};
    final pattern = RegExp('^${gridId}_ddlClassTeacher_(\\d+)\$');
    for (final tr in grid.querySelectorAll('tr')) {
      final selects = tr
          .querySelectorAll('select[id]')
          .where((e) => pattern.hasMatch(e.id))
          .toList();
      if (selects.isEmpty) continue;
      final select = selects.first,
          index = int.parse(pattern.firstMatch(select.id)!.group(1)!);
      if (!seen.add(index))
        _fail('MATCH_MISMATCH', 'Duplicate class mapping row index.');
      String value(String suffix, {bool hidden = false}) {
        final matches = tr
            .querySelectorAll('[id]')
            .where((e) => e.id == '${gridId}_${suffix}_$index')
            .toList();
        if (matches.isEmpty)
          _fail('PAGE_NOT_READY', 'Class mapping row identity is incomplete.');
        return hidden
            ? _str(matches.first.attributes['value']).trim()
            : _text(matches.first);
      }

      final options = select.querySelectorAll('option'),
          selected =
              select.querySelector('option[selected]') ??
              (options.isEmpty ? null : options.first);
      rows.add({
        'index': index,
        'class_id': value('hdnClassID', hidden: true),
        'class_section_id': value('hdnClassSectionId', hidden: true),
        'teacher_profile_id': value('hdnTeacherProfile_ID', hidden: true),
        'session': value('lblSession'),
        'class': value('lblClass'),
        'section': value('lblSection'),
        'selected_teacher_id': _str(selected?.attributes['value']).trim(),
        'teachers_list': [
          for (final option in options)
            if (!option.attributes.containsKey('disabled') &&
                option.attributes.containsKey('value'))
              {'id': option.attributes['value']!.trim(), 'name': _text(option)},
        ],
      });
    }
    if (rows.isEmpty &&
        !RegExp(
          r'no\s+records?\s+found',
          caseSensitive: false,
        ).hasMatch(_text(grid)))
      _fail('PAGE_NOT_READY', 'Class mapping rows are missing or incomplete.');
    return (soup: soup, rows: rows);
  }

  Future<
    ({
      AttendanceHttpReply response,
      dom.Document soup,
      List<Map<String, dynamic>> rows,
    })
  >
  _read(Uri url, String key) async {
    _check(key);
    final response = await request(url, timeout: const Duration(seconds: 25));
    _check(key);
    try {
      validateSchoolDocument(response.url, response.html, response.status);
    } on SchoolDocumentError catch (error) {
      _fail(error.code ?? 'PAGE_NOT_READY', error.toString());
    }
    if (response.url.scheme != 'https' ||
        response.url.authority != url.authority ||
        response.url.path.toLowerCase() != url.path.toLowerCase())
      _fail(
        'PAGE_NOT_READY',
        'Portal did not return the authenticated class mapping document.',
      );
    final parsed = parse(response.html);
    return (response: response, soup: parsed.soup, rows: parsed.rows);
  }

  static String _signature(Map row) => jsonEncode([
    for (final key in [
      'class_id',
      'class_section_id',
      'teacher_profile_id',
      'session',
      'class',
      'section',
      'selected_teacher_id',
    ])
      row[key],
  ]);
  static Map<String, dynamic> failure(Object error, [bool attempted = false]) {
    if (attempted)
      return {
        'success': false,
        'code': 'SAVE_UNCONFIRMED',
        'message': 'Mapping Save was submitted but not verified. Fetch mappings before submitting again.',
        'submission_attempted': true,
        'verified': false,
      };
    final code = error is MappingError
        ? error.code
        : error is TimeoutException
        ? 'PORTAL_SLOW'
        : error is SocketException ||
              error is HttpException ||
              error is HandshakeException
        ? 'NETWORK_ERROR'
        : 'PAGE_NOT_READY';
    return {
      'success': false,
      'code': code,
      'message': error.toString(),
      'data': <Object>[],
      'submission_attempted': false,
    };
  }

  void _remember(String key, List<Map<String, dynamic>> rows) {
    _check(key);
    _review = {for (final row in rows) row['index'] as int: _signature(row)};
    _reviewKey = key;
    _reviewAt = _now;
  }

  Future<Map<String, dynamic>> fetch() async {
    try {
      final context = _session(), read = await _read(context.url, context.key);
      _remember(context.key, read.rows);
      return {
        'success': true,
        'message': 'Class mapping fetched successfully',
        'data': read.rows,
      };
    } catch (error) {
      return failure(error);
    }
  }

  Future<Map<String, dynamic>> save(
    List<Map<String, dynamic>> updates, {
    required bool userConfirmed,
  }) async {
    var attempted = false;
    try {
      if (!userConfirmed)
        _fail(
          'CONFIRMATION_REQUIRED',
          'Confirm the mapping updates before saving.',
        );
      final context = _session(), key = context.key;
      if (updates.isEmpty)
        _fail('INVALID_PAYLOAD', 'Provide at least one valid mapping update.');
      final wanted = <int, String>{};
      for (final update in updates) {
        final index = update['index'], teacher = update['teacher_id'];
        if (index is! int ||
            index < 0 ||
            wanted.containsKey(index) ||
            teacher == null ||
            _str(teacher).trim().isEmpty)
          _fail(
            'INVALID_PAYLOAD',
            'Provide valid unique mapping rows and teacher IDs.',
          );
        wanted[index] = _str(teacher).trim();
      }
      final review = _review;
      if (review == null || _reviewKey != key)
        _fail('STALE_FORM', 'Fetch and review class mappings before saving.');
      final before = await _read(context.url, key),
          byIndex = {for (final row in before.rows) row['index'] as int: row},
          overrides = <String, String>{};
      for (final entry in wanted.entries) {
        final row = byIndex[entry.key];
        if (row == null || review[entry.key] != _signature(row))
          _fail(
            'STALE_FORM',
            'A selected mapping row changed. Fetch and review mappings again.',
          );
        final select = before.soup.getElementById(
          '${gridId}_ddlClassTeacher_${entry.key}',
        )!;
        if (!(row['teachers_list'] as List).any(
              (option) => option['id'] == entry.value,
            ) ||
            select.attributes.containsKey('disabled') ||
            (select.attributes['name'] ?? '').isEmpty)
          _fail(
            'INVALID_SELECTION',
            'Selected teacher is unavailable for this class.',
          );
        if ((select.attributes['onchange'] ?? '').isNotEmpty)
          _fail(
            'PAGE_NOT_READY',
            'This mapping form requires a dependent postback. Nothing was saved.',
          );
        overrides[select.attributes['name']!] = entry.value;
      }
      final buttons = before.soup
          .querySelectorAll('input[type="submit"],input[type="image"],button')
          .where((button) {
            final text =
                '${button.id} ${button.attributes['value'] ?? ''} ${_text(button)}'
                    .toLowerCase();
            return !button.attributes.containsKey('disabled') &&
                (text.contains('save') || text.contains('submit'));
          })
          .toList();
      if (buttons.length != 1)
        _fail(
          'NO_SAVE_BUTTON',
          'A unique class mapping Save/Submit control was not found.',
        );
      final button = buttons.single, form = AttendanceForm.enclosing(button);
      if (form == null) _fail('PAGE_NOT_READY', 'Mapping form is missing.');
      final payload = AttendanceForm.payload(form, button);
      if (_str(payload['__VIEWSTATE']).isEmpty ||
          _str(payload['__EVENTVALIDATION']).isEmpty)
        _fail('PAGE_NOT_READY', 'Mapping form tokens are missing.');
      payload.addAll(overrides);
      payload.removeWhere(
        (key, value) => key.toLowerCase().endsWith('scriptmanager1'),
      );
      final action = before.response.url.resolve(
        form.attributes['action'] ?? before.response.url.toString(),
      );
      if (action.scheme != 'https' ||
          action.authority != before.response.url.authority ||
          action.path.toLowerCase() != before.response.url.path.toLowerCase())
        _fail('PAGE_NOT_READY', 'Unexpected mapping form destination.');
      _check(key);
      _review = null;
      _reviewKey = null;
      attempted = true;
      final saved = await request(
        action,
        fields: payload,
        referer: before.response.url,
        saveControl:
            button.attributes['name'] ?? _str(payload['__EVENTTARGET']),
        timeout: const Duration(seconds: 30),
      );
      _check(key);
      if (saved.status != 200)
        _fail('SAVE_UNCONFIRMED', 'Portal Save response was not successful.');
      final confirmed = (await _read(context.url, key)).rows,
          actual = {for (final row in confirmed) row['index'] as int: row};
      if (actual.length != byIndex.length ||
          !actual.keys.toSet().containsAll(byIndex.keys))
        _fail('SAVE_UNCONFIRMED', 'Mapping rows changed after Save.');
      for (final entry in byIndex.entries) {
        final expected =
                wanted[entry.key] ?? entry.value['selected_teacher_id'],
            after = actual[entry.key]!;
        if ([
              'class_id',
              'class_section_id',
              'session',
              'class',
              'section',
            ].any((k) => after[k] != entry.value[k]) ||
            after['selected_teacher_id'] != expected)
          _fail(
            'SAVE_UNCONFIRMED',
            'Portal mapping read-back did not match the request.',
          );
      }
      _remember(key, confirmed);
      return {
        'success': true,
        'message': 'Class teacher mappings saved and verified on portal.',
        'verified': true,
        'submission_attempted': true,
        'updatedCount': wanted.length,
      };
    } catch (error) {
      return failure(error, attempted);
    }
  }
}
