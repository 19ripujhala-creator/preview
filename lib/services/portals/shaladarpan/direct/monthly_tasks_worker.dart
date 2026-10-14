/// Complete monthly_tasks_worker.py conversion. No mutation replay.
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import '../../../core/direct/async_primitives.dart';
import '../portal_state.dart';
import 'student_attendance_worker.dart';
import 'school_http.dart';
import 'ranking_http.dart';
import 'ranking_status_cache.dart';
import 'viffs_worker.dart';

class MonthlyError implements Exception {
  const MonthlyError(
    this.message,
    this.code, {
    this.attempted = false,
    this.rejected = false,
    this.data,
    this.fieldErrors = const {},
  });
  final String message, code;
  final bool attempted, rejected;
  final Map<String, dynamic>? data;
  final Map<String, String> fieldErrors;
  @override
  String toString() => message;
  Map<String, dynamic> get response => {
    'success': false,
    'code': code,
    'message': message,
    'submission_attempted': attempted,
    'submission_rejected': rejected,
    'data': data,
    'field_errors': fieldErrors,
  };
}

typedef MonthlyReply = ({
  Uri url,
  int status,
  String html,
  SchoolCookieJar? cookies,
});
typedef MonthlyRequest = Future<MonthlyReply> Function(
  Uri url, {
  String? body,
  Uri? referer,
  Map<String, String> headers,
  Duration timeout,
  bool followRedirects,
  SchoolCookieJar? cookies,
});

/// Python json.dumps(sort_keys=True), including its separator spacing.
String monthlyJson(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((k) => k.toString()).toList()..sort();
    return '{${keys.map((k) => '${jsonEncode(k)}: ${monthlyJson(value[k])}').join(', ')}}';
  }
  if (value is Iterable) return '[${value.map(monthlyJson).join(', ')}]';
  return jsonEncode(value);
}

Map<String, dynamic> monthlyCopy(Map<String, dynamic> v) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(v)));
String monthlyText(dom.Node? node) {
  final parts = <String>[];
  void visit(dom.Node n) {
    if (n is dom.Text) {
      final t = n.data.trim();
      if (t.isNotEmpty) parts.add(t);
    } else {
      if (n is dom.Element &&
          {'script', 'style', 'template'}.contains(n.localName))
        return;
      for (final c in n.nodes) {
        visit(c);
      }
    }
  }

  if (node != null) visit(node);
  return parts.join(' ');
}

Exception _viffsError(
  String message,
  String code, {
  Map<String, String> fieldErrors = const {},
}) => MonthlyError(message, code, attempted: false, fieldErrors: fieldErrors);

class MonthlyTasksWorker {
  MonthlyTasksWorker({
    required this.request,
    required this.baseUrl,
    required this.schoolId,
    required this.sessionKey,
    this.check,
    this.clock,
    RankingStatusCache? statusCache,
    List<int>? secret,
  }) : statusCache = statusCache ?? RankingStatusCache(),
       _secret =
           secret ?? List.generate(32, (_) => Random.secure().nextInt(256)) {
    ranking = RankingHttp(this);
  }
  final MonthlyRequest request;
  final Uri Function() baseUrl;
  final String Function() schoolId, sessionKey;
  final void Function()? check;
  final double Function()? clock;
  final RankingStatusCache statusCache;
  final List<int> _secret;
  late final RankingHttp ranking;
  final Stopwatch _clock = Stopwatch()..start();
  double get now => clock?.call() ?? _clock.elapsedMicroseconds / 1000000;
  final _reviews = LinkedHashMap<String, Map<String, dynamic>>();
  final _httpReviews = LinkedHashMap<String, ({String key, double at})>();
  static const prefix = 'ContentPlaceHolder1_';
  static const paths = {
    'ranking': 'Home/school/StudentAwardEntry.aspx',
    'viffs': 'Home/School/RMSA_SchoolMonthly_NP_tablets.aspx',
  };
  static const selectors = {
    'ranking': ['ddlMonth1', 'ddlyear'],
    'viffs': ['ddlStudentType', 'ddlClass', 'ddlmonth'],
  };
  static Map<String, dynamic> control(dom.Element node, String label) {
    final options = node.localName == 'select'
        ? node.querySelectorAll('option')
        : <dom.Element>[];
    final chosen =
        options
            .where((o) => o.attributes.containsKey('selected'))
            .firstOrNull ??
        options.firstOrNull;
    return {
      'id': node.id,
      'label': label,
      'value': node.localName == 'select'
          ? (chosen == null
                ? ''
                : chosen.attributes['value'] ?? monthlyText(chosen))
          : node.attributes['value'] ?? '',
      'options': [
        for (final o in options)
          {
            'value': o.attributes['value'] ?? monthlyText(o),
            'label': monthlyText(o),
          },
      ],
      'required':
          node.attributes.containsKey('required') ||
          node.attributes['aria-required'] == 'true',
      'readonly':
          node.attributes.containsKey('disabled') ||
          node.attributes.containsKey('readonly'),
      'numeric':
          node.attributes['type'] == 'number' ||
          RegExp(r'CheckNumeric|onlyNumber')
              .hasMatch(node.attributes['onkeypress'] ?? ''),
      'maxlength': int.parse(node.attributes['maxlength'] ?? '0'),
      'date': node.classes.contains('datepicker'),
    };
  }

  static Map<String, dynamic> parseForm(
    String source,
    String task, {
    Map<String, String>? selection,
    bool editing = false,
  }) {
    final soup = html.parse(source);
    if (monthlyText(soup).contains('Object reference not set to an instance') ||
        monthlyText(soup.querySelector('title')).contains('Server Error in'))
      throw const MonthlyError(
        'Portal returned a server error. Refresh to read the form.',
        'MONTHLY_UNAVAILABLE',
      );
    if (!selectors.containsKey(task))
      throw const MonthlyError('Unsupported monthly task.', 'INVALID_PAYLOAD');
    const labels = {
      'ddlMonth1': 'Month',
      'ddlyear': 'Year',
      'ddlStudentType': 'सत्र',
      'ddlClass': 'गोली',
      'ddlmonth': 'माह',
    };
    final chosen = <Map<String, dynamic>>[];
    for (final suffix in selectors[task]!) {
      final node = soup.getElementById(prefix + suffix);
      if (node == null)
        throw const MonthlyError(
          'Monthly form was not returned by the authenticated portal.',
          'MONTHLY_UNAVAILABLE',
        );
      chosen.add(control(node, labels[suffix]!));
    }
    final result = <String, dynamic>{
      'task': task,
      'selectors': chosen,
      'sections': <Map<String, dynamic>>[],
      'history': <Map<String, dynamic>>[],
      'can_submit': false,
      'can_lock': false,
      'locked': false,
      'lock_date': null,
      'completed': null,
      'no_records': false,
      'message': '',
      'selection': {for (final f in chosen) f['id']: f['value']},
    };
    final sections = result['sections'] as List<Map<String, dynamic>>,
        history = result['history'] as List<Map<String, dynamic>>;
    if (task == 'ranking') {
      final fields = <Map<String, dynamic>>[];
      for (final pair in [
        ('txtaward', 'Label4'),
        ('txtlibbooks', 'Label5'),
        ('txtsports', 'Label6'),
        ('TextBox1', 'Label7'),
      ]) {
        final node = soup.getElementById(prefix + pair.$1);
        if (node == null)
          throw const MonthlyError(
            'District Ranking fields are incomplete.',
            'MONTHLY_UNAVAILABLE',
          );
        final f = control(
          node,
          monthlyText(soup.getElementById(prefix + pair.$2)),
        );
        final requiredMessage = {
          'txtaward': 'कृप्या अवार्ड एंट्री की प्रविष्ठी करें',
          'txtlibbooks': 'कृप्या वितरित पुस्तकों की प्रविष्ठी करें',
          'txtsports': 'Sports participation is required',
        }[pair.$1];
        if (requiredMessage != null) {
          f['required'] = true;
          f['required_message'] = requiredMessage;
        }
        fields.add(f);
      }
      sections.add({
        'title': 'District Entry Data Ranking',
        'fields': fields,
        'identity': <String, String>{},
      });
      final table = soup.getElementById('${prefix}grd_Add');
      if (table != null) {
        for (final row in table.querySelectorAll('tr')) {
          final month = row
              .querySelectorAll('input')
              .where((n) => RegExp(r'_hdnmonth_\d+$').hasMatch(n.id))
              .firstOrNull;
          final cells = row.children.where((n) => n.localName == 'td').toList();
          if (month != null && cells.length >= 7)
            history.add({
              'year': monthlyText(cells[1]),
              'month': month.attributes['value'] ?? '',
              'month_label': monthlyText(cells[2]),
              'values': cells.sublist(3, 7).map(monthlyText).toList(),
              'actions': {
                for (final action in ['Edit', 'Delete'])
                  if (row
                          .querySelectorAll('input')
                          .where(
                            (n) =>
                                RegExp('_btn${action}_\\d+\$').hasMatch(n.id) &&
                                !n.attributes.containsKey('disabled'),
                          )
                          .firstOrNull
                      case final dom.Element n)
                    action: n.id,
              },
            });
        }
      }
      final complete =
          table != null &&
          !table
              .querySelectorAll('a')
              .any((n) => (n.attributes['href'] ?? '').contains(r'Page$'));
      result['history_complete'] = complete;
      final select = result['selection'] as Map;
      final existing = history
          .where(
            (r) =>
                r['year'] == select['${prefix}ddlyear'] &&
                r['month'] == select['${prefix}ddlMonth1'],
          )
          .toList();
      final validMonth = !['', '0'].contains(select['${prefix}ddlMonth1']);
      result['completed'] = existing.isNotEmpty
          ? true
          : (validMonth && complete ? false : null);
      if (existing.isNotEmpty && !editing)
        for (var i = 0; i < fields.length; i++) {
          fields[i]['value'] = existing.first['values'][i];
          fields[i]['readonly'] = true;
        }
      final button = soup.getElementById('${prefix}sub_btn');
      result.addAll({
        'editing': editing,
        'can_edit':
            existing.length == 1 &&
            (existing.first['actions'] as Map).containsKey('Edit') &&
            complete,
        'can_delete':
            existing.length == 1 &&
            (existing.first['actions'] as Map).containsKey('Delete') &&
            complete,
        'can_submit':
            button != null &&
            !button.attributes.containsKey('disabled') &&
            (existing.isEmpty || editing) &&
            validMonth &&
            complete,
      });
    } else {
      result['note'] = 'नोट :- सत्र का प्रारंभ मई माह से मानते हुए, इस प्रपत्र में एंट्रीज़ करनी है';
      final grid = ViffsWorker.parseGrid(
        soup,
        control,
        monthlyText,
        _viffsError,
      );
      if (grid != null) {
        result['grid_id'] = grid['grid_id'];
        result['sections'] = grid['sections'];
        final submit = soup.getElementById('${prefix}btnSubmit'),
            lock = soup.getElementById('${prefix}Lock');
        final nonempty = (grid['sections'] as List).isNotEmpty;
        result['can_submit'] =
            nonempty &&
            submit != null &&
            !submit.attributes.containsKey('disabled');
        final match = RegExp(
          r'^Lock\s+on\s*:\s*(\d{2}/\d{2}/\d{4})$',
          caseSensitive: false,
        ).firstMatch((lock?.attributes['value'] ?? '').trim());
        final date = match == null ? null : _date(match.group(1)!, '/');
        final locked =
            date != null &&
            lock!.attributes.containsKey('disabled') &&
            (submit == null || submit.attributes.containsKey('disabled'));
        result['locked'] = locked;
        result['lock_date'] = locked ? match!.group(1) : null;
        result['can_lock'] =
            nonempty &&
            lock != null &&
            !lock.attributes.containsKey('disabled') &&
            (lock.attributes['value'] ?? '').trim() == 'Lock';
        result['completed'] = locked ? true : null;
        if (locked) {
          result['can_submit'] = false;
          result['can_lock'] = false;
          for (final sec in result['sections'])
            for (final f in sec['fields']) {
              f['readonly'] = true;
            }
        }
      } else {
        // A Show response may omit the grid because the portal rejected the
        // reporting period. Preserve its alert/validation message rather than
        // treating that response as an empty roster or a generic read failure.
        final rejection = portalRejection(soup);
        if (rejection.isNotEmpty) {
          throw MonthlyError(rejection, 'PORTAL_MESSAGE');
        }
        final match = RegExp(
          r'(?:no\s+records?\s+found|not\s+record\s+found)',
          caseSensitive: false,
        ).firstMatch(monthlyText(soup));
        if (match != null) {
          result['no_records'] = true;
          result['message'] = match.group(0);
        } else if (['P', 'B'].contains(selection?['${prefix}ddlClass']))
          throw const MonthlyError(
            'VIFFS table or an explicit portal no-record message was not returned.',
            'MONTHLY_UNAVAILABLE',
          );
      }
    }
    return result;
  }

  static DateTime? _date(String raw, String separator) {
    final parts = raw.split(separator);
    if (parts.length != 3 ||
        !RegExp(r'^\d{1,2}$').hasMatch(parts[0]) ||
        !RegExp(r'^\d{1,2}$').hasMatch(parts[1]) ||
        !RegExp(r'^\d{4}$').hasMatch(parts[2]))
      return null;
    final day = int.tryParse(parts[0]),
        month = int.tryParse(parts[1]),
        year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null || year < 1) return null;
    final d = DateTime.utc(year, month, day);
    return d.day == day && d.month == month && d.year == year ? d : null;
  }

  static Map<String, dynamic> reviewData(Map<String, dynamic> form) {
    if (form['task'] != 'ranking')
      return {
        for (final k in [
          'http_session',
          'task',
          'selection',
          'selectors',
          'sections',
          'history',
          'can_submit',
          'can_lock',
          'locked',
          'lock_date',
          'editing',
          'can_edit',
          'can_delete',
          'edit_control',
          'confirmations',
        ])
          k: form[k],
      };
    final rows =
        <Map<String, dynamic>>[
          for (final r in form['history'])
            {
              'year': r['year'],
              'month': r['month'],
              'values': r['values'],
              'actions': (r['actions'] as Map).keys.toList()..sort(),
            },
        ]..sort((a, b) {
          final y = (a['year'] as String).compareTo(b['year']);
          return y != 0 ? y : (a['month'] as String).compareTo(b['month']);
        });
    return {
      'task': 'ranking',
      'selection': form['selection'],
      'selectors': [
        for (final f in form['selectors'])
          {
            'id': f['id'],
            'values': [for (final o in f['options']) o['value']]..sort(),
          },
      ],
      'fields': [
        for (final sec in form['sections'])
          for (final f in sec['fields'])
            {
              for (final k in [
                'id',
                'value',
                'readonly',
                'numeric',
                'maxlength',
                'date',
              ])
                k: f[k],
            },
      ],
      'history': rows,
      'history_complete': form['history_complete'],
      'editing': form['editing'] ?? false,
      'can_submit': form['can_submit'],
      'can_edit': form['can_edit'],
      'can_delete': form['can_delete'],
      'confirmations': form['confirmations'] ?? {},
    };
  }

  String signature(Map<String, dynamic> form, String school) {
    final stable = reviewData(form),
        token = Hmac(
          sha256,
          _secret,
        ).convert(utf8.encode(monthlyJson([school, stable]))).toString();
    _reviews.remove(token);
    _reviews[token] = {'school': school, 'stable': monthlyCopy(stable)};
    while (_reviews.length > 256) {
      _reviews.remove(_reviews.keys.first);
    }
    return token;
  }

  void requireReview(
    String snapshot,
    Map<String, dynamic> form,
    String school,
    String action,
  ) {
    final expected = form['snapshot']?.toString() ?? '';
    var difference = snapshot.length ^ expected.length;
    for (var i = 0; i < snapshot.length && i < expected.length; i++) {
      difference |= snapshot.codeUnitAt(i) ^ expected.codeUnitAt(i);
    }
    if (difference == 0) return;
    throw const MonthlyError(
      'Portal data changed. Show the period again before continuing.',
      'STALE_FORM',
    );
  }

  /// Parse one quoted Python-compatible literal; never run JavaScript.
  static String? literal(String raw) {
    if (raw.length < 2 ||
        !['"', "'"].contains(raw[0]) ||
        raw[raw.length - 1] != raw[0])
      return null;
    final out = StringBuffer();
    for (var i = 1; i < raw.length - 1; i++) {
      var c = raw[i];
      if (c != '\\') {
        out.write(c);
        continue;
      }
      if (++i >= raw.length - 1) return null;
      c = raw[i];
      const escapes = {
        'n': '\n',
        'r': '\r',
        't': '\t',
        'b': '\b',
        'f': '\f',
        'v': '\v',
        'a': '\u0007',
        '\\': '\\',
        "'": "'",
        '"': '"',
      };
      if (escapes.containsKey(c)) {
        out.write(escapes[c]);
        continue;
      }
      if (c == '\n') continue;
      if (['x', 'u', 'U'].contains(c)) {
        final count = c == 'x'
            ? 2
            : c == 'u'
            ? 4
            : 8;
        if (i + count >= raw.length) return null;
        final n = int.tryParse(raw.substring(i + 1, i + 1 + count), radix: 16);
        if (n == null || n > 0x10ffff) return null;
        out.writeCharCode(n);
        i += count;
        continue;
      }
      if (RegExp('[0-7]').hasMatch(c)) {
        var digits = c;
        while (digits.length < 3 &&
            i + 1 < raw.length - 1 &&
            RegExp('[0-7]').hasMatch(raw[i + 1])) {
          digits += raw[++i];
        }
        out.writeCharCode(int.parse(digits, radix: 8));
        continue;
      }
      out.write('\\$c');
    }
    return out.toString();
  }

  static final quoted = r"""((?:"(?:[^"\\]|\\.)*")|(?:'(?:[^'\\]|\\.)*'))""";
  static String? literalConfirmation(String source) {
    final calls = RegExp(r'(?:window\.)?confirm\s*\(\s*' + quoted + r'\s*\)')
        .allMatches(source)
        .toList();
    if (calls.length != 1 ||
        RegExp(r'\bconfirm\s*\(').allMatches(source).length != 1)
      return null;
    final value = literal(calls.single.group(1)!);
    return value != null && value.trim().isNotEmpty ? value : null;
  }

  static String submitResponseError(String source) =>
      monthlyText(html.parse(source).getElementById('${prefix}lblerrmsg'));
  static Map<String, dynamic> validateValues(
    Map<String, dynamic> form,
    Map<String, String> values, {
    DateTime? today,
  }) {
    final editable = <String, dynamic>{
      for (final sec in form['sections'])
        for (final f in sec['fields'])
          if (f['readonly'] != true) f['id'] as String: f,
    };
    if (values.length != editable.length ||
        values.keys.any((k) => !editable.containsKey(k)))
      throw const MonthlyError(
        'Form fields changed. Reload before submitting.',
        'STALE_FORM',
      );
    for (final entry in values.entries) {
      final key = entry.key, value = entry.value, f = editable[key];
      if (f['required'] == true && value.trim().isEmpty) {
        final message = f['required_message'] ?? '${f['label']}: required.';
        throw MonthlyError(
          message,
          'INVALID_PAYLOAD',
          attempted: false,
          fieldErrors: {key: message},
        );
      }
      if (f['maxlength'] != 0 && value.runes.length > f['maxlength'])
        throw MonthlyError(
          '${f['label']}: maximum ${f['maxlength']} characters.',
          'INVALID_PAYLOAD',
          attempted: false,
          fieldErrors: {key: 'Maximum ${f['maxlength']} characters.'},
        );
      if (f['numeric'] == true &&
          value.isNotEmpty &&
          !ViffsWorker.isDecimal(value))
        throw MonthlyError(
          '${f['label']}: enter a non-negative whole number.',
          'INVALID_PAYLOAD',
          attempted: false,
          fieldErrors: {key: 'Enter a non-negative whole number.'},
        );
      if ((f['options'] as List).isNotEmpty &&
          !(f['options'] as List).any((o) => o['value'] == value))
        throw const MonthlyError(
          'Select a portal-provided option.',
          'INVALID_PAYLOAD',
        );
      if (f['date'] == true && value.isNotEmpty) {
        final day = _date(value, '-');
        if (day == null)
          throw const MonthlyError(
            'Use a valid date in DD-MM-YYYY format.',
            'INVALID_PAYLOAD',
          );
        final now = today ?? RankingStatusCache.indiaNow();
        if (day.isBefore(DateTime.utc(2024, 1, 1)) ||
            day.isAfter(DateTime.utc(now.year, now.month, now.day)))
          throw const MonthlyError(
            'Meeting date is outside the portal date range.',
            'INVALID_PAYLOAD',
          );
      }
    }
    if (form['task'] == 'viffs')
      ViffsWorker.validateCounts(form, values, _viffsError);
    return editable;
  }

  static Map<String, dynamic> rankingRecord(
    Map<String, dynamic> form,
    Map<String, String> selection,
  ) {
    if (form['task'] != 'ranking' || form['history_complete'] != true)
      throw const MonthlyError(
        'Ranking history is incomplete. Refresh before changing an entry.',
        'STALE_FORM',
      );
    final rows = (form['history'] as List)
        .where(
          (r) =>
              r['year'] == selection['${prefix}ddlyear'] &&
              r['month'] == selection['${prefix}ddlMonth1'],
        )
        .toList();
    if (rows.length != 1)
      throw const MonthlyError(
        'A unique entry for the selected month/year was not found.',
        'STALE_FORM',
      );
    return rows.single as Map<String, dynamic>;
  }

  static dom.Element? parentForm(dom.Element node) {
    for (dom.Element? n = node.parent; n != null; n = n.parent) {
      if (n.localName == 'form') return n;
    }
    return null;
  }

  static bool visible(dom.Element? node) {
    if (node == null) return false;
    for (dom.Element? n = node; n != null; n = n.parent)
      if (n.attributes.containsKey('hidden') ||
          RegExp(
            r'display\s*:\s*none|visibility\s*:\s*hidden',
            caseSensitive: false,
          ).hasMatch(n.attributes['style'] ?? ''))
        return false;
    return true;
  }

  static String messages(dom.Document soup) => LinkedHashSet<String>.from(
    soup
        .querySelectorAll(
          '.validationsummary, .validation-summary-errors, [role="alert"], #msgDiv, #msg_Success, #MsgPopup, #popMsg, #ContentPlaceHolder1_lblerrmsg',
        )
        .where(visible)
        .map(monthlyText)
        .where((s) => s.isNotEmpty),
  ).join('\n');
  void checkSession(String key) {
    OperationCancellation.current?.check();
    check?.call();
    if (key.isEmpty || key != sessionKey())
      throw const MonthlyError(
        'School login session changed. Fetch class mapping again.',
        'ACCOUNT_CHANGED',
      );
  }

  String context(String school) {
    final base = baseUrl();
    if (base.scheme != 'https' ||
        base.host != 'rajshaladarpan.rajasthan.gov.in' ||
        base.port != 443 ||
        base.userInfo.isNotEmpty ||
        !RegExp(r'^/SD[1-5]/?$', caseSensitive: false).hasMatch(base.path) ||
        base.hasQuery ||
        base.hasFragment)
      throw const MonthlyError(
        'Active school server base is invalid.',
        'PAGE_NOT_READY',
      );
    if (school.trim() != schoolId().trim() ||
        school.trim().isEmpty ||
        sessionKey().isEmpty)
      throw const MonthlyError(
        'School account changed. Fetch class mapping again.',
        'ACCOUNT_CHANGED',
      );
    final key = sessionKey();
    checkSession(key);
    return key;
  }

  dom.Document checked(MonthlyReply response, String key) {
    checkSession(key);
    validateSchoolDocument(response.url, response.html, response.status);
    if (response.url.scheme != 'https' ||
        response.url.host != 'rajshaladarpan.rajasthan.gov.in' ||
        !RegExp(
          r'^/SD[1-5]/' + RegExp.escape(paths['viffs']!) + r'$',
          caseSensitive: false,
        ).hasMatch(response.url.path))
      throw const MonthlyError(
        'Authenticated VIFFS form was not returned.',
        'WORKFLOW_EXPIRED',
      );
    return html.parse(response.html);
  }

  static ({Uri action, Map<String, Object?> payload}) fields(
    MonthlyReply response,
    dom.Document soup,
    dom.Element? button, [
    Map<String, Object?> overrides = const {},
  ]) {
    if (button == null || button.attributes.containsKey('disabled'))
      throw const MonthlyError(
        'Native monthly action control is missing or disabled.',
        'SUBMISSION_BLOCKED',
      );
    final form = parentForm(button);
    if (form == null)
      throw const MonthlyError(
        'Native monthly form is missing.',
        'MONTHLY_UNAVAILABLE',
      );
    final payload = AttendanceForm.payload(form, button);
    if (payload['__VIEWSTATE'] == null ||
        payload['__VIEWSTATE'] == '' ||
        payload['__EVENTVALIDATION'] == null ||
        payload['__EVENTVALIDATION'] == '')
      throw const MonthlyError(
        'Monthly form tokens are missing.',
        'WORKFLOW_EXPIRED',
      );
    payload.addAll(overrides);
    payload.removeWhere((k, v) => k.toLowerCase().endsWith('scriptmanager1'));
    final action = response.url.resolve(
      form.attributes['action'] ?? response.url.toString(),
    );
    if (action.scheme != response.url.scheme ||
        action.authority != response.url.authority ||
        action.path != response.url.path)
      throw const MonthlyError(
        'Unexpected monthly form destination.',
        'WORKFLOW_EXPIRED',
      );
    return (action: action, payload: payload);
  }

  Future<({MonthlyReply response, dom.Document soup})> post(
    MonthlyReply response,
    dom.Document soup,
    dom.Element? button,
    String key, [
    Map<String, Object?> overrides = const {},
  ]) async {
    final f = fields(response, soup, button, overrides);
    checkSession(key);
    final fresh = await request(
      f.action,
      body: AttendanceForm.encode(f.payload),
      referer: response.url,
      timeout: const Duration(seconds: 30),
      followRedirects: false,
    );
    return (response: fresh, soup: checked(fresh, key));
  }

  Map<String, dynamic> view(
    dom.Document soup,
    Map<String, String> selection,
    String school,
    String key,
  ) {
    final form = parseForm(soup.outerHtml, 'viffs', selection: selection);
    if (selection.entries.any((e) => form['selection'][e.key] != e.value))
      throw const MonthlyError(
        'Portal did not retain the selected period.',
        'SELECTION_CHANGED',
      );
    form['school_id'] = school;
    form['http_session'] = sha256
        .convert(utf8.encode(monthlyJson(key)))
        .toString();
    form['message'] = messages(soup);
    final token = signature(form, school);
    form['snapshot'] = token;
    _httpReviews.remove(token);
    _httpReviews[token] = (key: key, at: now);
    while (_httpReviews.length > 256) {
      _httpReviews.remove(_httpReviews.keys.first);
    }
    return form;
  }

  Future<
    ({MonthlyReply response, dom.Document soup, Map<String, dynamic> form})
  >
  readHttp(Map<String, String> selection, String school, String key) async {
    if (selection.keys.any(
      (k) => !selectors['viffs']!.map((s) => prefix + s).contains(k),
    ))
      throw const MonthlyError('Invalid VIFFS selection.', 'INVALID_SELECTION');
    var response = await request(
      baseUrl().resolve(paths['viffs']!),
      timeout: const Duration(seconds: 25),
      followRedirects: true,
    );
    var soup = checked(response, key);
    for (final suffix in selectors['viffs']!) {
      final id = prefix + suffix, value = selection[id];
      if (value == null || value.isEmpty) continue;
      final node = soup.getElementById(id);
      if (node == null ||
          node.localName != 'select' ||
          node.attributes.containsKey('disabled') ||
          (node.attributes['name'] ?? '').isEmpty)
        throw const MonthlyError(
          'Portal monthly selector is unavailable.',
          'INVALID_SELECTION',
        );
      final offered = node
          .querySelectorAll('option')
          .where((o) => !o.attributes.containsKey('disabled'))
          .map((o) => o.attributes['value'] ?? monthlyText(o));
      if (!offered.contains(value) || value == '0')
        throw const MonthlyError(
          'Selected period/tablet is not offered by portal.',
          'INVALID_SELECTION',
        );
      final options = node.querySelectorAll('option');
      for (final option in options) {
        option.attributes.remove('selected');
        if ((option.attributes['value'] ?? monthlyText(option)) == value)
          option.attributes['selected'] = '';
      }
      // viffs_mpr_http.py sends every requested native selector postback,
      // including an already-selected value. Client-side selection alone does
      // not establish the server's dependent session/tablet/month state.
      {
        if ((node.attributes['onchange'] ?? '').isNotEmpty &&
            !RegExp(r'__doPostBack|WebForm_DoPostBackWithOptions')
                .hasMatch(node.attributes['onchange']!))
          throw const MonthlyError(
            'Unsupported monthly selector handler.',
            'MONTHLY_UNAVAILABLE',
          );
        final form = parentForm(node);
        if (form == null)
          throw const MonthlyError(
            'Monthly form is missing.',
            'MONTHLY_UNAVAILABLE',
          );
        final dummy = dom.Element.tag('input')
          ..attributes.addAll({'type': 'submit', 'name': '_selector_only'});
        form.append(dummy);
        final f = fields(response, soup, dummy, {
          '__EVENTTARGET': node.attributes['name'],
          '__EVENTARGUMENT': '',
        });
        f.payload.remove('_selector_only');
        dummy.remove();
        checkSession(key);
        response = await request(
          f.action,
          body: AttendanceForm.encode(f.payload),
          referer: response.url,
          timeout: const Duration(seconds: 25),
          followRedirects: false,
        );
        soup = checked(response, key);
      }
    }
    if (['P', 'B'].contains(selection['${prefix}ddlClass'])) {
      final shown = await post(
        response,
        soup,
        soup.getElementById('${prefix}Button1'),
        key,
      );
      response = shown.response;
      soup = shown.soup;
    }
    try {
      return (
        response: response,
        soup: soup,
        form: view(soup, selection, school, key),
      );
    } on MonthlyError catch (error) {
      // Structural diagnostics only: no HTML, cookies, tokens, school/student
      // identity or field values. Debug console output supports a failed READ.
      assert(() {
        final metadata = <String, Object?>{
          'code': error.code,
          'path': response.url.path,
          'status': response.status,
          'ajax_delta': RegExp(r'^\d+\|').hasMatch(response.html.trimLeft()),
          'form_present': soup.querySelector('form') != null,
          'selectors': [
            for (final suffix in selectors['viffs']!)
              {
                'id': prefix + suffix,
                'name': soup
                    .getElementById(prefix + suffix)
                    ?.attributes['name'],
                'selected': soup.getElementById(prefix + suffix) == null
                    ? null
                    : control(
                        soup.getElementById(prefix + suffix)!,
                        suffix,
                      )['value'],
              },
          ],
          'table_ids': soup
              .querySelectorAll('table[id]')
              .map((n) => n.id)
              .take(20)
              .toList(),
          'show_present': soup.getElementById('${prefix}Button1') != null,
        };
        print('[Rajshala VIFFS READ] ${jsonEncode(metadata)}');
        return true;
      }());
      rethrow;
    }
  }

  void reviewContext(String snapshot, String key) {
    final old = _httpReviews[snapshot];
    if (old == null || old.key != key || now - old.at > 180)
      throw const MonthlyError(
        'Show and review the monthly form again before continuing.',
        'STALE_FORM',
      );
  }

  static MonthlyError wrap(Object error, [bool attempted = false]) {
    if (attempted)
      return const MonthlyError(
        'Monthly operation outcome is uncertain. Refresh and verify before retrying.',
        'SUBMISSION_UNCONFIRMED',
        attempted: true,
      );
    if (error is MonthlyError) return error;
    if (error is SchoolDocumentError)
      return MonthlyError(error.message, error.code ?? 'MONTHLY_UNAVAILABLE');
    if (error is TimeoutException)
      return const MonthlyError(
        'Monthly portal request timed out.',
        'PORTAL_SLOW',
      );
    if (error is IOException)
      return const MonthlyError(
        'Monthly portal could not be reached.',
        'NETWORK_ERROR',
      );
    return const MonthlyError(
      'Monthly portal form could not be read.',
      'MONTHLY_UNAVAILABLE',
    );
  }

  Future<Map<String, dynamic>> readForm(
    String task,
    Map<String, String> selection,
    String school, {
    bool refresh = false,
  }) async {
    if (task == 'ranking')
      return (await ranking.read(selection, school, refresh: refresh)).form;
    if (task != 'viffs')
      throw const MonthlyError('Unsupported monthly task.', 'INVALID_PAYLOAD');
    try {
      final key = context(school);
      return (await readHttp(selection, school, key)).form;
    } catch (e) {
      throw wrap(e);
    }
  }

  static String portalRejection(dom.Document soup) {
    final messages = <String>[
      submitResponseError(soup.outerHtml),
      ...soup
          .querySelectorAll('.validationsummary, .validation-summary-errors')
          .where(visible)
          .map(monthlyText),
    ];
    for (final script in soup.querySelectorAll('script'))
      for (final m in RegExp(
        r'^\s*(?://<!\[CDATA\[\s*)?(?:window\.)?alert\s*\(\s*' +
            quoted +
            r'\s*\)',
      ).allMatches(script.text)) {
        final value = literal(m.group(1)!);
        if (value != null) messages.add(value);
      }
    return LinkedHashSet<String>.from(messages.where((m) => m.isNotEmpty))
        .join('\n');
  }

  Future<Map<String, dynamic>> submitForm(
    String task,
    Map<String, String> selection,
    String school,
    String snapshot,
    Map<String, String> values, {
    bool editing = false,
  }) async {
    if (task == 'ranking')
      return ranking.submit(
        selection,
        school,
        snapshot,
        values,
        editing: editing,
      );
    var attempted = false;
    final started = now;
    try {
      if (task != 'viffs' || editing)
        throw const MonthlyError(
          'Unsupported monthly action.',
          'INVALID_PAYLOAD',
        );
      final key = context(school);
      reviewContext(snapshot, key);
      final read = await readHttp(selection, school, key);
      final form = read.form;
      requireReview(snapshot, form, school, 'submit');
      if (form['can_submit'] != true)
        throw MonthlyError(
          (form['message'] as String).isNotEmpty
              ? form['message']
              : 'Portal does not allow Submit.',
          'SUBMISSION_BLOCKED',
        );
      final editable = validateValues(form, values);
      if (editable.entries.every((e) => values[e.key] == e.value['value']))
        throw const MonthlyError('No changes to submit.', 'NO_CHANGES');
      final overrides = <String, Object?>{};
      for (final entry in values.entries) {
        final nodes = read.soup
            .querySelectorAll('[id]')
            .where((n) => n.id == entry.key)
            .toList();
        if (nodes.length != 1 ||
            nodes.single.attributes.containsKey('disabled') ||
            nodes.single.attributes.containsKey('readonly') ||
            (nodes.single.attributes['name'] ?? '').isEmpty)
          throw const MonthlyError(
            'Monthly fields changed. Reload the form.',
            'STALE_FORM',
          );
        overrides[nodes.single.attributes['name']!] = entry.value;
      }
      final f = fields(
        read.response,
        read.soup,
        read.soup.getElementById('${prefix}btnSubmit'),
        overrides,
      );
      checkSession(key);
      _httpReviews.remove(snapshot);
      attempted = true;
      final response = await request(
            f.action,
            body: AttendanceForm.encode(f.payload),
            referer: read.response.url,
            timeout: const Duration(seconds: 30),
            followRedirects: false,
          ),
          soup = checked(response, key);
      final rejection = portalRejection(soup);
      if (rejection.isNotEmpty)
        throw MonthlyError(rejection, 'PORTAL_MESSAGE', attempted: true);
      final fresh = (await readHttp(selection, school, key)).form;
      if (!ViffsWorker.savedMatches(form, fresh, values))
        throw const MonthlyError(
          'Saved VIFFS values could not be verified.',
          'SUBMISSION_UNCONFIRMED',
          attempted: true,
        );
      return {
        'success': true,
        'data': fresh,
        'message': messages(soup),
        'verified': true,
        'submission_attempted': true,
        'elapsed_ms': ((now - started) * 1000).round(),
      };
    } catch (e) {
      if (e is MonthlyError && e.attempted) rethrow;
      throw wrap(e, attempted);
    }
  }

  Future<Map<String, dynamic>> lockForm(
    String task,
    Map<String, String> selection,
    String school,
    String snapshot,
  ) async {
    var attempted = false;
    try {
      if (task != 'viffs' ||
          selectors['viffs']!.any(
            (k) =>
                selection[prefix + k] == null ||
                selection[prefix + k] == '' ||
                selection[prefix + k] == '0',
          ))
        throw const MonthlyError(
          'Select VIFFS session, tablet and month.',
          'INVALID_SELECTION',
        );
      final key = context(school);
      reviewContext(snapshot, key);
      final read = await readHttp(selection, school, key);
      final form = read.form;
      if (form['locked'] == true)
        return {
          'success': true,
          'data': form,
          'verified': true,
          'submission_attempted': false,
          'message': 'Lock on : ${form['lock_date']}',
        };
      requireReview(snapshot, form, school, 'lock');
      if (form['can_lock'] != true)
        throw MonthlyError(
          (form['message'] as String).isNotEmpty
              ? form['message']
              : 'Portal does not allow Lock.',
          'SUBMISSION_BLOCKED',
        );
      final oldValues = <String, String>{
        for (final sec in form['sections'])
          for (final f in sec['fields'])
            f['id'] as String: f['value'] as String,
      };
      ViffsWorker.validateCounts(form, oldValues, _viffsError);
      final f = fields(
        read.response,
        read.soup,
        read.soup.getElementById('${prefix}Lock'),
      );
      checkSession(key);
      _httpReviews.remove(snapshot);
      attempted = true;
      var response = await request(
        f.action,
        body: AttendanceForm.encode(f.payload),
        referer: read.response.url,
        timeout: const Duration(seconds: 30),
        followRedirects: false,
      );
      var soup = checked(response, key);
      final ok = soup.getElementById('${prefix}btn_ok');
      if (visible(ok) && !ok!.attributes.containsKey('disabled')) {
        const expected =
            'कृपया सूचना को लॉक करने से पूर्व एक बार चेक कर ले अन्यथा लॉक करने के बाद बदलाव संभव नहीं होगा';
        final warning = monthlyText(soup.getElementById('${prefix}div1'))
            .split(RegExp(r'\s+'))
            .join(' ');
        if (warning != expected)
          throw MonthlyError(
            warning.isNotEmpty ? warning : 'Unrecognized Lock confirmation.',
            'SUBMISSION_UNCONFIRMED',
            attempted: true,
          );
        final current = parseForm(soup.outerHtml, 'viffs', selection: selection)
          ..['school_id'] = school;
        if (!ViffsWorker.savedMatches(form, current, oldValues))
          throw const MonthlyError(
            'VIFFS values changed before final Lock.',
            'SUBMISSION_UNCONFIRMED',
            attempted: true,
          );
        final locked = await post(response, soup, ok, key);
        response = locked.response;
        soup = locked.soup;
      }
      final rejection = portalRejection(soup);
      if (rejection.isNotEmpty)
        throw MonthlyError(rejection, 'PORTAL_MESSAGE', attempted: true);
      final fresh = (await readHttp(selection, school, key)).form;
      if (fresh['locked'] != true ||
          !ViffsWorker.savedMatches(form, fresh, oldValues))
        throw const MonthlyError(
          'Lock could not be verified. Refresh and check portal before retrying.',
          'SUBMISSION_UNCONFIRMED',
          attempted: true,
        );
      return {
        'success': true,
        'data': fresh,
        'verified': true,
        'submission_attempted': true,
        'message': messages(soup).isNotEmpty
            ? messages(soup)
            : 'Lock on : ${fresh['lock_date']}',
      };
    } catch (e) {
      if (e is MonthlyError && e.attempted) rethrow;
      throw wrap(e, attempted);
    }
  }

  Future<Map<String, dynamic>> editRanking(
    Map<String, String> selection,
    String school,
    String snapshot,
  ) => ranking.action(selection, school, snapshot, 'Edit');
  Future<Map<String, dynamic>> deleteRanking(
    Map<String, String> selection,
    String school,
    String snapshot,
  ) => ranking.action(selection, school, snapshot, 'Delete');
}
