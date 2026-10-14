/// Complete conversion of the uploaded HTTPX incharge_mapping.py.
/// Authentic portal messages are retained separately from technical failures.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import '../../../core/direct/async_primitives.dart';
import '../portal_state.dart';
import 'staff_attendance.dart';
import 'student_attendance_worker.dart' show AttendanceHttpReply;

class InchargeError implements Exception {
  const InchargeError(this.code, this.message);
  final String code, message;
  @override
  String toString() => message;
}

typedef InchargeRequest = Future<AttendanceHttpReply> Function(
  Uri url, {
  Map<String, Object?>? fields,
  Uri? referer,
  String? action,
  String? control,
  String? controlId,
  bool mutation,
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

String _str(Object? value) => value?.toString() ?? '';
String _normal(Object? value) {
  final cleaned = _str(value).replaceAll(RegExp(r'\s+'), ' ').trim();
  return cleaned.runes
      .map((r) => _caseFold[r] ?? String.fromCharCode(r).toLowerCase())
      .join();
}

Never _fail(String code, String message) => throw InchargeError(code, message);
bool _network(Object e) =>
    e is TimeoutException ||
    e is SocketException ||
    e is HttpException ||
    e is HandshakeException;

class _Context {
  _Context(this.school, this.base, this.session);
  final String school, session;
  final Uri base;
  String get key => '$school/$base/$session';
}

class _Read {
  _Read(this.response, this.soup, this.data);
  final AttendanceHttpReply response;
  final dom.Document soup;
  final Map<String, dynamic> data;
}

class InchargeMappingWorker {
  InchargeMappingWorker({
    required this.request,
    required this.baseUrl,
    required this.schoolId,
    required this.sessionKey,
    this.check,
    this.clock,
  });
  final InchargeRequest request;
  final Uri Function() baseUrl;
  final String Function() schoolId, sessionKey;
  final void Function()? check;
  final double Function()? clock;
  final Stopwatch _clock = Stopwatch()..start();
  double get _now => clock?.call() ?? _clock.elapsedMicroseconds / 1000000;
  Map<String, dynamic>? _review;
  String? _reviewKey;
  double _reviewAt = 0;
  static const path = 'Home/School/AddSDSchemeIncharge.aspx',
      prefix = 'ContentPlaceHolder1_',
      gridId = '${prefix}grd_InchargeDetails';
  static final _noRecord = RegExp(
    r'no\s+(?:record|data|mapping)s?\s+(?:found|available)|no\s+records?|कोई\s+(?:रिकॉर्ड|अभिलेख)\s+नहीं|रिकॉर्ड\s+उपलब्ध\s+नहीं',
    caseSensitive: false,
  );
  static final _confirm = RegExp(
    r'are\s+you\s+sure|do\s+you\s+want\s+to|क्या\s+आप\s+सुनिश्चित|क्या\s+आप\s+चाहते',
    caseSensitive: false,
  );
  static bool looksSuccessful(String message) =>
      RegExp(
        r'success(?:ful|fully)?|सफल|सफलतापूर्वक',
        caseSensitive: false,
      ).hasMatch(message) &&
      !RegExp(
        r'not\s+success|unsuccess|असफल',
        caseSensitive: false,
      ).hasMatch(message);
  static String _unescape(String text) => text.replaceAllMapped(
    RegExp(r'&(?:#[xX][a-fA-F\d]+|#\d+|[A-Za-z][A-Za-z\d]+);?'),
    (m) => html.parseFragment(m[0]!).text ?? m[0]!,
  );
  static String _js(String body) {
    try {
      return body.replaceAllMapped(
        RegExp(
          r'''\\(?:u[0-9a-fA-F]{4}|U[0-9a-fA-F]{8}|x[0-9a-fA-F]{2}|[0-7]{1,3}|[\s\S])''',
        ),
        (m) {
          final token = m[0]!.substring(1);
          if (token.startsWith('u') && token.length == 5)
            return String.fromCharCode(
              int.parse(token.substring(1), radix: 16),
            );
          if (token.startsWith('U') && token.length == 9)
            return String.fromCharCode(
              int.parse(token.substring(1), radix: 16),
            );
          if (token.startsWith('x') && token.length == 3)
            return String.fromCharCode(
              int.parse(token.substring(1), radix: 16),
            );
          if (RegExp(r'^[0-7]{1,3}$').hasMatch(token))
            return String.fromCharCode(int.parse(token, radix: 8));
          return {
                'n': '\n',
                'r': '\r',
                't': '\t',
                'b': '\b',
                'f': '\f',
                'a': '\u0007',
                'v': '\u000b',
                '\\': '\\',
                "'": "'",
                '"': '"',
                '\n': '',
              }[token] ??
              m[0]!;
        },
      );
    } catch (_) {
      return body;
    }
  }

  static List<String> portalMessages(String document) {
    if (document.isEmpty) return [];
    final soup = html.parse(document), found = <String>[];
    void add(String raw) {
      final message = _unescape(raw).trim();
      if (message.runes.length < 2 ||
          message.runes.length > 500 ||
          _confirm.hasMatch(message))
        return;
      if (!found.contains(message)) found.add(message);
    }

    for (final selector in [
      '[id\$="_lblMessage"]',
      '[id\$="_lblMsg"]',
      '[id\$="_lblError"]',
      '[id\$="_lblSuccess"]',
      '[id\$="_lblResult"]',
      '[id\$="_msg"]',
      '#msgDiv',
      '#msg_Success',
      '#MsgPopup',
      '#lblMsg',
      '.alert-success',
      '.alert-danger',
      '.alert-warning',
      '.toast-message',
      '.swal2-html-container',
    ]) {
      for (final node in soup.querySelectorAll(selector)) {
        if (node.attributes.containsKey('hidden') ||
            RegExp(
              r'display\s*:\s*none',
              caseSensitive: false,
            ).hasMatch(node.attributes['style'] ?? ''))
          continue;
        add(_text(node));
      }
    }
    final alert = RegExp(
      r'''(?<![\w.])(?:window\.)?alert\s*\(\s*(['"])((?:\\.|(?!\1).)*?)\1\s*\)''',
      caseSensitive: false,
      dotAll: true,
    );
    for (final script in soup.querySelectorAll('script')) {
      for (final match in alert.allMatches(script.text)) {
        add(_js(match.group(2)!));
      }
    }
    return found;
  }

  static String _newMessage(String document, Set<String> old) {
    for (final m in portalMessages(document)) {
      if (!old.contains(m)) return m;
    }
    return '';
  }

  static Map<String, dynamic> failure(
    Object error, {
    bool attempted = false,
    String portalMessage = '',
  }) {
    late String code, message;
    if (error is InchargeError) {
      code = error.code;
      message = error.message;
    } else if (error is SchoolDocumentError) {
      code = error.code ?? 'PORTAL_RESPONSE_ERROR';
      message = error.toString();
    } else if (error is TimeoutException) {
      code = 'NETWORK_TIMEOUT';
      message = 'Portal request timed out.';
    } else if (_network(error)) {
      code = 'NETWORK_ERROR';
      message = 'Portal connection failed.';
    } else {
      code = 'PORTAL_ERROR';
      message = 'Incharge portal operation failed.';
    }
    if (attempted) {
      final display =
          portalMessage.isNotEmpty && !looksSuccessful(portalMessage)
          ? portalMessage
          : 'Portal result could not be verified. Refresh before further changes.';
      return {
        'success': false,
        'code': 'SAVE_UNCONFIRMED',
        'message': display,
        'message_source': display == portalMessage ? 'portal' : 'backend',
        'portal_message': portalMessage.isEmpty ? null : portalMessage,
        'reason_code': code,
        'verified': false,
        'submission_attempted': true,
      };
    }
    return {
      'success': false,
      'code': code,
      'message': message,
      'message_source': 'backend',
      'portal_message': null,
      'verified': false,
      'submission_attempted': false,
    };
  }

  void _check(_Context ctx) {
    OperationCancellation.current?.check();
    check?.call();
    if (schoolId().trim() != ctx.school)
      _fail('ACCOUNT_CHANGED', 'School login changed; refresh first.');
    if (_base().toString().toLowerCase() != ctx.base.toString().toLowerCase())
      _fail('SESSION_CHANGED', 'Portal node changed; refresh first.');
    if (sessionKey() != ctx.session)
      _fail('SESSION_CHANGED', 'Portal session changed; refresh first.');
  }

  Uri _base() =>
      Uri.parse(baseUrl().toString().replaceFirst(RegExp(r'/$'), ''));
  _Context _context([String requestedSchool = '']) {
    final school = schoolId().trim();
    if (school.isEmpty) _fail('SESSION_EXPIRED', 'School is not logged in.');
    if (requestedSchool.isNotEmpty && requestedSchool.trim() != school)
      _fail('ACCOUNT_MISMATCH', 'Requested school differs from login.');
    final base = _base();
    if (base.scheme != 'https' ||
        base.host != 'rajshaladarpan.rajasthan.gov.in' ||
        base.port != 443 ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment ||
        !RegExp(r'^/SD[1-5]$', caseSensitive: false).hasMatch(base.path))
      _fail('INVALID_SERVER', 'Invalid ShalaDarpan school node.');
    final session = sessionKey();
    if (session.isEmpty)
      _fail('SESSION_EXPIRED', 'School authentication is unavailable.');
    final ctx = _Context(school, base, session);
    _check(ctx);
    return ctx;
  }

  static bool active(Map row) {
    final status = _normal(row['status']),
        compact = status.replaceAll(RegExp(r'[\s_-]+'), '');
    if (['active', 'सक्रिय'].contains(status) || compact == 'active')
      return true;
    if ([
          'deactive',
          'deactivated',
          'inactive',
          'in-active',
          'निष्क्रिय',
        ].contains(status) ||
        ['deactive', 'deactivated', 'inactive'].contains(compact))
      return false;
    _fail('PAGE_NOT_READY', 'Unknown incharge status in portal grid.');
  }

  static String _identity(Map row) => jsonEncode([
    for (final k in ['role', 'name', 'employee_id']) _normal(row[k]),
  ]);
  static List<Map<String, String>> _options(dom.Document soup, String suffix) {
    final node = soup.getElementById('$prefix$suffix');
    if (node == null || node.localName != 'select')
      _fail('PAGE_NOT_READY', 'Missing $suffix selector.');
    final result = <Map<String, String>>[], seen = <String>{};
    for (final option in node.querySelectorAll('option')) {
      final value = _str(option.attributes['value']).trim(),
          label = _text(option),
          normal = _normal(label);
      if (option.attributes.containsKey('disabled') ||
          ['', '-1', '99'].contains(value) ||
          ['select ', '-select', 'चयन करें'].any(normal.startsWith))
        continue;
      if (!seen.add(value))
        _fail('PAGE_NOT_READY', 'Duplicate dropdown option ID.');
      result.add({'value': value, 'label': label});
    }
    return result;
  }

  static ({dom.Document soup, Map<String, dynamic> data}) parse(
    String document,
  ) {
    final soup = html.parse(document),
        roles = _options(soup, 'ddlrole'),
        teachers = _options(soup, 'ddlTeacher'),
        grid = soup.getElementById(gridId);
    if (grid == null || grid.localName != 'table')
      _fail('PAGE_NOT_READY', 'Incharge mapping grid missing.');
    if (grid.querySelector('a[href*="Page\$"],a[href*="Page%24"]') != null)
      _fail('PAGE_NOT_READY', 'Paginated grid cannot be verified fully.');
    final records = <Map<String, String>>[];
    for (final tr in grid.querySelectorAll('tr')) {
      final cells = tr.children.where((e) => e.localName == 'td').toList();
      if (cells.isEmpty) continue;
      if (cells.length == 1 && _noRecord.hasMatch(_text(cells.first))) continue;
      if (cells.length < 6)
        _fail('PAGE_NOT_READY', 'Incharge row structure changed.');
      final text = cells.map(_text).toList();
      if (_normal(text[1]) == 'role' && _normal(text[4]) == 'status') continue;
      final buttons = tr
          .querySelectorAll('input[id]')
          .where(
            (e) => RegExp('btndeactive', caseSensitive: false).hasMatch(e.id),
          )
          .toList();
      final button = buttons.isEmpty ? null : buttons.first;
      records.add({
        'sr_no': text[0],
        'role': text[1],
        'name': text[2],
        'employee_id': text[3],
        'status': text[4],
        'button_id':
            button != null && !button.attributes.containsKey('disabled')
            ? button.id
            : '',
      });
    }
    return (
      soup: soup,
      data: {
        'success': true,
        'roles': roles,
        'teachers': teachers,
        'current_list': records,
      },
    );
  }

  _Read _document(AttendanceHttpReply response, _Context ctx) {
    _check(ctx);
    try {
      validateSchoolDocument(response.url, response.html, response.status);
    } on SchoolDocumentError catch (e) {
      _fail(e.code ?? 'PORTAL_ERROR', e.toString());
    }
    final url = response.url;
    if (url.scheme != 'https' ||
        url.host != 'rajshaladarpan.rajasthan.gov.in' ||
        !RegExp(
          r'^/SD[1-5]/Home/School/AddSDSchemeIncharge\.aspx$',
          caseSensitive: false,
        ).hasMatch(url.path) ||
        url.path.toLowerCase() != '${ctx.base.path}/$path'.toLowerCase())
      _fail('PAGE_NOT_READY', 'Unexpected portal response page.');
    final parsed = parse(response.html);
    return _Read(response, parsed.soup, parsed.data);
  }

  Future<_Read> _read(_Context ctx) async {
    _check(ctx);
    return _document(
      await request(
        Uri.parse('${ctx.base}/$path'),
        mutation: false,
        timeout: const Duration(seconds: 25),
      ),
      ctx,
    );
  }

  static ({Uri url, Map<String, Object?> fields}) _form(
    AttendanceHttpReply response,
    dom.Element control, {
    Map<String, String>? selections,
    String? eventTarget,
  }) {
    try {
      return StaffWebForms.post(
        response.url,
        control,
        overrides: selections,
        eventTarget: eventTarget,
      );
    } on StaffAttendanceError catch (e) {
      _fail(e.code, e.message);
    }
  }

  Future<_Read> _select(
    _Read before,
    _Context ctx,
    String suffix,
    String value,
  ) async {
    final node = before.soup.getElementById('$prefix$suffix');
    if (node == null ||
        node.attributes.containsKey('disabled') ||
        (node.attributes['name'] ?? '').isEmpty)
      _fail('INVALID_SELECTION', 'Incharge dropdown is unavailable.');
    if (!node
        .querySelectorAll('option')
        .any(
          (o) =>
              !o.attributes.containsKey('disabled') &&
              o.attributes['value'] == value,
        ))
      _fail('INVALID_SELECTION', 'Selected dropdown value is not offered.');
    for (final option in node.querySelectorAll('option')) {
      option.attributes.remove('selected');
      if (option.attributes['value'] == value)
        option.attributes['selected'] = 'selected';
    }
    final onchange = node.attributes['onchange'] ?? '';
    if (onchange.isEmpty) return before;
    if (!RegExp(
      '__doPostBack|WebForm_DoPostBackWithOptions',
      caseSensitive: false,
    ).hasMatch(onchange))
      _fail('PAGE_NOT_READY', 'Unrecognized dependent dropdown event.');
    final post = _form(
      before.response,
      node,
      selections: {node.attributes['name']!: value},
      eventTarget: node.attributes['name'],
    );
    _check(ctx);
    return _document(
      await request(
        post.url,
        fields: post.fields,
        referer: before.response.url,
        action: 'SELECTOR',
        control: node.attributes['name'],
        controlId: node.id,
        mutation: false,
        timeout: const Duration(seconds: 25),
      ),
      ctx,
    );
  }

  static String _teacherName(String label) =>
      _normal(label.replaceFirst(RegExp(r'\s*\([^()]*\)\s*$'), ''));
  static bool _teacherMatch(Map record, Map teacher, List teachers) {
    if (_normal(record['employee_id']) == _normal(teacher['value']))
      return true;
    return teachers
                .where(
                  (t) =>
                      _teacherName(_str(t['label'])) ==
                      _teacherName(_str(teacher['label'])),
                )
                .length ==
            1 &&
        _normal(record['name']) == _teacherName(_str(teacher['label']));
  }

  void _remember(_Context ctx, Map<String, dynamic> data) {
    _check(ctx);
    _review = data;
    _reviewKey = ctx.key;
    _reviewAt = _now;
  }

  Future<Map<String, dynamic>> fetch({String requestedSchool = ''}) async {
    try {
      final ctx = _context(requestedSchool), read = await _read(ctx);
      _remember(ctx, read.data);
      return read.data;
    } catch (e) {
      return {
        ...failure(e),
        'roles': <Object>[],
        'teachers': <Object>[],
        'current_list': <Object>[],
      };
    }
  }

  Future<Map<String, dynamic>> execute(
    String actionType, {
    String roleId = '',
    String teacherId = '',
    String buttonId = '',
    required bool userConfirmed,
  }) async {
    var attempted = false, portalMessage = '';
    try {
      if (!userConfirmed)
        _fail(
          'CONFIRMATION_REQUIRED',
          'Confirm the incharge change before submitting.',
        );
      if (!['add', 'deactive'].contains(actionType))
        _fail('INVALID_PAYLOAD', 'Unsupported incharge action.');
      final ctx = _context(), previous = _review;
      if (previous == null || _reviewKey != ctx.key || _now - _reviewAt > 900)
        _fail('STALE_FORM', 'Refresh incharge mappings before acting.');
      var before = await _read(ctx);
      final initial = before.data,
          oldMessages = portalMessages(before.response.html).toSet();
      final teachers = initial['teachers'] as List;
      Map? teacher;
      String? roleName, targetIdentity;
      late ({Uri url, Map<String, Object?> fields}) post;
      late String control;
      late String controlId;
      if (actionType == 'add') {
        roleId = roleId.trim();
        teacherId = teacherId.trim();
        final roles = (initial['roles'] as List)
                .where((x) => x['value'] == roleId)
                .toList(),
            selected = teachers.where((x) => x['value'] == teacherId).toList();
        if (roles.isEmpty || selected.isEmpty)
          _fail('INVALID_SELECTION', 'Role or teacher unavailable.');
        final role = roles.first as Map;
        teacher = selected.first as Map;
        bool contains(List list, Map option) => list.any(
          (x) => x['value'] == option['value'] && x['label'] == option['label'],
        );
        if (!contains(previous['roles'] as List, role) ||
            !contains(previous['teachers'] as List, teacher))
          _fail('STALE_FORM', 'Dropdown choices changed; refresh first.');
        roleName = _normal(role['label']);
        final occupied = (initial['current_list'] as List)
            .where((x) => _normal(x['role']) == roleName && active(x as Map))
            .toList();
        if (occupied.isNotEmpty) {
          if (occupied.length == 1 &&
              _teacherMatch(occupied.first as Map, teacher, teachers))
            _fail('NO_CHANGES', 'Role already assigned to this teacher.');
          _fail(
            'ROLE_OCCUPIED',
            'Deactivate the current role holder before assigning another.',
          );
        }
        before = await _select(before, ctx, 'ddlrole', roleId);
        before = await _select(before, ctx, 'ddlTeacher', teacherId);
        final button = before.soup.getElementById('${prefix}btnAdd');
        if (button == null) _fail('PAGE_NOT_READY', 'Add button missing.');
        if (_ownForm(button) == null)
          _fail('PAGE_NOT_READY', 'Add form missing.');
        final roleField = before.soup.getElementById('${prefix}ddlrole'),
            teacherField = before.soup.getElementById('${prefix}ddlTeacher');
        if (roleField == null || teacherField == null)
          _fail('PAGE_NOT_READY', 'Add selectors missing.');
        final rname = roleField.attributes['name'],
            tname = teacherField.attributes['name'];
        if (rname == null || tname == null)
          _fail('PAGE_NOT_READY', 'Add selectors missing.');
        post = _form(
          before.response,
          button,
          selections: {rname: roleId, tname: teacherId},
        );
        controlId = button.id;
        control =
            button.attributes['name'] ?? _str(post.fields['__EVENTTARGET']);
      } else {
        buttonId = buttonId.trim();
        if (buttonId.isEmpty)
          _fail('INVALID_PAYLOAD', 'Deactivate button ID missing.');
        final matching = (initial['current_list'] as List)
                .where((x) => x['button_id'] == buttonId)
                .toList(),
            reviewed = (previous['current_list'] as List)
                .where((x) => x['button_id'] == buttonId)
                .toList();
        if (matching.length != 1 || reviewed.length != 1)
          _fail('STALE_FORM', 'Incharge row changed; refresh first.');
        final old = reviewed.single as Map, row = matching.single as Map;
        if (_identity(old) != _identity(row) ||
            _normal(old['status']) != _normal(row['status']))
          _fail('STALE_FORM', 'Incharge row changed; refresh first.');
        if (!active(row)) _fail('NO_CHANGES', 'Mapping is already inactive.');
        targetIdentity = _identity(row);
        if ((initial['current_list'] as List)
                .where(
                  (x) => _identity(x as Map) == targetIdentity && active(x),
                )
                .length !=
            1)
          _fail('MATCH_MISMATCH', 'Deactivate target is ambiguous.');
        final button = before.soup.getElementById(buttonId);
        if (button == null ||
            !RegExp('btndeactive', caseSensitive: false).hasMatch(buttonId))
          _fail('PAGE_NOT_READY', 'Deactivate control missing.');
        post = _form(before.response, button);
        controlId = button.id;
        control =
            button.attributes['name'] ?? _str(post.fields['__EVENTTARGET']);
      }
      _check(ctx);
      _review = null;
      _reviewKey = null;
      attempted = true;
      try {
        final posted = await request(
          post.url,
          fields: post.fields,
          referer: before.response.url,
          action: actionType,
          control: control,
          controlId: controlId,
          mutation: true,
          timeout: const Duration(seconds: 30),
        );
        portalMessage = _newMessage(posted.html, oldMessages);
      } catch (e) {
        if (!_network(e)) rethrow;
      }
      final fresh = await _read(ctx), after = fresh.data;
      if (portalMessage.isEmpty)
        portalMessage = _newMessage(fresh.response.html, oldMessages);
      final records = after['current_list'] as List;
      final verified = actionType == 'add'
          ? () {
              final role = records
                  .where(
                    (x) => _normal(x['role']) == roleName && active(x as Map),
                  )
                  .toList();
              return role.length == 1 &&
                  _teacherMatch(role.single as Map, teacher!, teachers);
            }()
          : !records.any(
              (x) => _identity(x as Map) == targetIdentity && active(x),
            );
      if (!verified)
        _fail(
          'SAVE_UNCONFIRMED',
          'Portal status did not verify the requested change.',
        );
      _remember(ctx, after);
      return {
        'success': true,
        'message': portalMessage.isEmpty
            ? 'Incharge $actionType verified on portal.'
            : portalMessage,
        'message_source': portalMessage.isEmpty ? 'backend' : 'portal',
        'portal_message': portalMessage.isEmpty ? null : portalMessage,
        'data': after,
        'verified': true,
        'submission_attempted': true,
      };
    } catch (e) {
      return failure(e, attempted: attempted, portalMessage: portalMessage);
    }
  }
}

dom.Element? _ownForm(dom.Element node) {
  for (var p = node.parent; p != null; p = p.parent) {
    if (p.localName == 'form') return p;
  }
  return null;
}

// Python Unicode casefold differences from lowercase, for exact identity matching.
const _caseFold = <int, String>{
  181: "\u03bc",
  223: "ss",
  329: "\u02bcn",
  383: "s",
  496: "j\u030c",
  837: "\u03b9",
  912: "\u03b9\u0308\u0301",
  944: "\u03c5\u0308\u0301",
  962: "\u03c3",
  976: "\u03b2",
  977: "\u03b8",
  981: "\u03c6",
  982: "\u03c0",
  1008: "\u03ba",
  1009: "\u03c1",
  1013: "\u03b5",
  1415: "\u0565\u0582",
  5024: "\u13a0",
  5025: "\u13a1",
  5026: "\u13a2",
  5027: "\u13a3",
  5028: "\u13a4",
  5029: "\u13a5",
  5030: "\u13a6",
  5031: "\u13a7",
  5032: "\u13a8",
  5033: "\u13a9",
  5034: "\u13aa",
  5035: "\u13ab",
  5036: "\u13ac",
  5037: "\u13ad",
  5038: "\u13ae",
  5039: "\u13af",
  5040: "\u13b0",
  5041: "\u13b1",
  5042: "\u13b2",
  5043: "\u13b3",
  5044: "\u13b4",
  5045: "\u13b5",
  5046: "\u13b6",
  5047: "\u13b7",
  5048: "\u13b8",
  5049: "\u13b9",
  5050: "\u13ba",
  5051: "\u13bb",
  5052: "\u13bc",
  5053: "\u13bd",
  5054: "\u13be",
  5055: "\u13bf",
  5056: "\u13c0",
  5057: "\u13c1",
  5058: "\u13c2",
  5059: "\u13c3",
  5060: "\u13c4",
  5061: "\u13c5",
  5062: "\u13c6",
  5063: "\u13c7",
  5064: "\u13c8",
  5065: "\u13c9",
  5066: "\u13ca",
  5067: "\u13cb",
  5068: "\u13cc",
  5069: "\u13cd",
  5070: "\u13ce",
  5071: "\u13cf",
  5072: "\u13d0",
  5073: "\u13d1",
  5074: "\u13d2",
  5075: "\u13d3",
  5076: "\u13d4",
  5077: "\u13d5",
  5078: "\u13d6",
  5079: "\u13d7",
  5080: "\u13d8",
  5081: "\u13d9",
  5082: "\u13da",
  5083: "\u13db",
  5084: "\u13dc",
  5085: "\u13dd",
  5086: "\u13de",
  5087: "\u13df",
  5088: "\u13e0",
  5089: "\u13e1",
  5090: "\u13e2",
  5091: "\u13e3",
  5092: "\u13e4",
  5093: "\u13e5",
  5094: "\u13e6",
  5095: "\u13e7",
  5096: "\u13e8",
  5097: "\u13e9",
  5098: "\u13ea",
  5099: "\u13eb",
  5100: "\u13ec",
  5101: "\u13ed",
  5102: "\u13ee",
  5103: "\u13ef",
  5104: "\u13f0",
  5105: "\u13f1",
  5106: "\u13f2",
  5107: "\u13f3",
  5108: "\u13f4",
  5109: "\u13f5",
  5112: "\u13f0",
  5113: "\u13f1",
  5114: "\u13f2",
  5115: "\u13f3",
  5116: "\u13f4",
  5117: "\u13f5",
  7296: "\u0432",
  7297: "\u0434",
  7298: "\u043e",
  7299: "\u0441",
  7300: "\u0442",
  7301: "\u0442",
  7302: "\u044a",
  7303: "\u0463",
  7304: "\ua64b",
  7830: "h\u0331",
  7831: "t\u0308",
  7832: "w\u030a",
  7833: "y\u030a",
  7834: "a\u02be",
  7835: "\u1e61",
  7838: "ss",
  8016: "\u03c5\u0313",
  8018: "\u03c5\u0313\u0300",
  8020: "\u03c5\u0313\u0301",
  8022: "\u03c5\u0313\u0342",
  8064: "\u1f00\u03b9",
  8065: "\u1f01\u03b9",
  8066: "\u1f02\u03b9",
  8067: "\u1f03\u03b9",
  8068: "\u1f04\u03b9",
  8069: "\u1f05\u03b9",
  8070: "\u1f06\u03b9",
  8071: "\u1f07\u03b9",
  8072: "\u1f00\u03b9",
  8073: "\u1f01\u03b9",
  8074: "\u1f02\u03b9",
  8075: "\u1f03\u03b9",
  8076: "\u1f04\u03b9",
  8077: "\u1f05\u03b9",
  8078: "\u1f06\u03b9",
  8079: "\u1f07\u03b9",
  8080: "\u1f20\u03b9",
  8081: "\u1f21\u03b9",
  8082: "\u1f22\u03b9",
  8083: "\u1f23\u03b9",
  8084: "\u1f24\u03b9",
  8085: "\u1f25\u03b9",
  8086: "\u1f26\u03b9",
  8087: "\u1f27\u03b9",
  8088: "\u1f20\u03b9",
  8089: "\u1f21\u03b9",
  8090: "\u1f22\u03b9",
  8091: "\u1f23\u03b9",
  8092: "\u1f24\u03b9",
  8093: "\u1f25\u03b9",
  8094: "\u1f26\u03b9",
  8095: "\u1f27\u03b9",
  8096: "\u1f60\u03b9",
  8097: "\u1f61\u03b9",
  8098: "\u1f62\u03b9",
  8099: "\u1f63\u03b9",
  8100: "\u1f64\u03b9",
  8101: "\u1f65\u03b9",
  8102: "\u1f66\u03b9",
  8103: "\u1f67\u03b9",
  8104: "\u1f60\u03b9",
  8105: "\u1f61\u03b9",
  8106: "\u1f62\u03b9",
  8107: "\u1f63\u03b9",
  8108: "\u1f64\u03b9",
  8109: "\u1f65\u03b9",
  8110: "\u1f66\u03b9",
  8111: "\u1f67\u03b9",
  8114: "\u1f70\u03b9",
  8115: "\u03b1\u03b9",
  8116: "\u03ac\u03b9",
  8118: "\u03b1\u0342",
  8119: "\u03b1\u0342\u03b9",
  8124: "\u03b1\u03b9",
  8126: "\u03b9",
  8130: "\u1f74\u03b9",
  8131: "\u03b7\u03b9",
  8132: "\u03ae\u03b9",
  8134: "\u03b7\u0342",
  8135: "\u03b7\u0342\u03b9",
  8140: "\u03b7\u03b9",
  8146: "\u03b9\u0308\u0300",
  8147: "\u03b9\u0308\u0301",
  8150: "\u03b9\u0342",
  8151: "\u03b9\u0308\u0342",
  8162: "\u03c5\u0308\u0300",
  8163: "\u03c5\u0308\u0301",
  8164: "\u03c1\u0313",
  8166: "\u03c5\u0342",
  8167: "\u03c5\u0308\u0342",
  8178: "\u1f7c\u03b9",
  8179: "\u03c9\u03b9",
  8180: "\u03ce\u03b9",
  8182: "\u03c9\u0342",
  8183: "\u03c9\u0342\u03b9",
  8188: "\u03c9\u03b9",
  43888: "\u13a0",
  43889: "\u13a1",
  43890: "\u13a2",
  43891: "\u13a3",
  43892: "\u13a4",
  43893: "\u13a5",
  43894: "\u13a6",
  43895: "\u13a7",
  43896: "\u13a8",
  43897: "\u13a9",
  43898: "\u13aa",
  43899: "\u13ab",
  43900: "\u13ac",
  43901: "\u13ad",
  43902: "\u13ae",
  43903: "\u13af",
  43904: "\u13b0",
  43905: "\u13b1",
  43906: "\u13b2",
  43907: "\u13b3",
  43908: "\u13b4",
  43909: "\u13b5",
  43910: "\u13b6",
  43911: "\u13b7",
  43912: "\u13b8",
  43913: "\u13b9",
  43914: "\u13ba",
  43915: "\u13bb",
  43916: "\u13bc",
  43917: "\u13bd",
  43918: "\u13be",
  43919: "\u13bf",
  43920: "\u13c0",
  43921: "\u13c1",
  43922: "\u13c2",
  43923: "\u13c3",
  43924: "\u13c4",
  43925: "\u13c5",
  43926: "\u13c6",
  43927: "\u13c7",
  43928: "\u13c8",
  43929: "\u13c9",
  43930: "\u13ca",
  43931: "\u13cb",
  43932: "\u13cc",
  43933: "\u13cd",
  43934: "\u13ce",
  43935: "\u13cf",
  43936: "\u13d0",
  43937: "\u13d1",
  43938: "\u13d2",
  43939: "\u13d3",
  43940: "\u13d4",
  43941: "\u13d5",
  43942: "\u13d6",
  43943: "\u13d7",
  43944: "\u13d8",
  43945: "\u13d9",
  43946: "\u13da",
  43947: "\u13db",
  43948: "\u13dc",
  43949: "\u13dd",
  43950: "\u13de",
  43951: "\u13df",
  43952: "\u13e0",
  43953: "\u13e1",
  43954: "\u13e2",
  43955: "\u13e3",
  43956: "\u13e4",
  43957: "\u13e5",
  43958: "\u13e6",
  43959: "\u13e7",
  43960: "\u13e8",
  43961: "\u13e9",
  43962: "\u13ea",
  43963: "\u13eb",
  43964: "\u13ec",
  43965: "\u13ed",
  43966: "\u13ee",
  43967: "\u13ef",
  64256: "ff",
  64257: "fi",
  64258: "fl",
  64259: "ffi",
  64260: "ffl",
  64261: "st",
  64262: "st",
  64275: "\u0574\u0576",
  64276: "\u0574\u0565",
  64277: "\u0574\u056b",
  64278: "\u057e\u0576",
  64279: "\u0574\u056d",
};
