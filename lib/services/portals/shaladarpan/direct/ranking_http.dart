/// Complete ranking_http.py conversion, including native MS-Ajax deltas.

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import 'monthly_tasks_worker.dart';
import 'school_http.dart';

class RankingState {
  RankingState({
    required this.soup,
    required this.url,
    required this.school,
    required this.key,
    required this.at,
    this.cookies,
    this.editing = false,
    Map<String, String>? selection,
  }) : selection = selection ?? {};
  dom.Document soup;
  final Uri url;
  final String school, key;
  double at;
  SchoolCookieJar? cookies;
  bool editing;
  Map<String, String> selection;
  RankingState copy() => RankingState(
    soup: html.parse(soup.outerHtml),
    url: url,
    school: school,
    key: key,
    at: at,
    cookies: cookies?.copy(),
    editing: editing,
    selection: Map.from(selection),
  );
}

class RankingHttp {
  RankingHttp(this.worker);
  final MonthlyTasksWorker worker;
  final _states = <String, RankingState>{};
  static const cp = r'ctl00$ContentPlaceHolder1$';
  static const fields = ['txtaward', 'txtlibbooks', 'txtsports', 'TextBox1'];
  static const prefix = MonthlyTasksWorker.prefix;
  String stateKey(String school) {
    final base = worker.baseUrl();
    if (base.scheme != 'https' ||
        base.host.toLowerCase() != 'rajshaladarpan.rajasthan.gov.in' ||
        base.port != 443 ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment ||
        !RegExp(r'^/SD\d+/?$', caseSensitive: false).hasMatch(base.path))
      throw const MonthlyError(
        'Active ShalaDarpan server base is invalid.',
        'INVALID_SELECTION',
      );
    if (worker.schoolId().trim() != school.trim())
      throw const MonthlyError(
        'The logged-in school changed. Refresh the form.',
        'ACCOUNT_CHANGED',
      );
    final key = worker.sessionKey();
    if (key.isEmpty)
      throw const MonthlyError(
        'School portal session is unavailable.',
        'SESSION_EXPIRED',
      );
    worker.check?.call();
    final scoped = monthlyJson([
      school,
      base.toString().replaceFirst(RegExp(r'/$'), '').toLowerCase(),
      key,
    ]);
    _states.removeWhere(
      (k, s) => worker.now - s.at > 180 || (s.school == school && k != scoped),
    );
    return scoped;
  }

  static String checkResponse(
    MonthlyReply response,
    Uri expected, {
    bool attempted = false,
  }) {
    final actual = response.url;
    if (response.status != 200 ||
        actual.scheme != 'https' ||
        actual.authority.toLowerCase() != expected.authority.toLowerCase() ||
        actual.path.toLowerCase() != expected.path.toLowerCase()) {
      final code = attempted
          ? 'SUBMISSION_UNCONFIRMED'
          : response.status == 401 ||
                RegExp(
                  r'(officelogin|login\.aspx|default\.aspx|/public)',
                  caseSensitive: false,
                ).hasMatch(actual.path)
          ? 'SESSION_EXPIRED'
          : 'MONTHLY_UNAVAILABLE';
      throw MonthlyError(
        attempted
            ? 'Portal operation could not be verified. Refresh before trying again.'
            : 'The authenticated ranking page was not returned.',
        code,
        attempted: attempted,
      );
    }
    return response.html;
  }

  /// Dart String indexes count UTF-16 code units, exactly MS-Ajax framing.
  static List<(String, String, String)> parseDelta(String raw) {
    var pos = 0;
    final records = <(String, String, String)>[];
    int delimiter(int start) {
      final n = raw.indexOf('|', start);
      if (n < 0) throw const FormatException('Incomplete delta');
      return n;
    }

    while (pos < raw.length) {
      final j = delimiter(pos), count = int.parse(raw.substring(pos, j));
      if (count < 0) throw const FormatException('Invalid delta length');
      final k = delimiter(j + 1), l = delimiter(k + 1), end = l + 1 + count;
      if (end >= raw.length || raw[end] != '|')
        throw const FormatException('Invalid delta framing');
      final content = raw.substring(l + 1, end);
      // A frame cannot split a surrogate pair: Python strict UTF-16 decoding fails.
      for (var i = 0; i < content.length; i++) {
        final u = content.codeUnitAt(i);
        if (u >= 0xd800 && u <= 0xdbff) {
          if (++i >= content.length ||
              content.codeUnitAt(i) < 0xdc00 ||
              content.codeUnitAt(i) > 0xdfff)
            throw const FormatException('Invalid UTF-16 delta');
        } else if (u >= 0xdc00 && u <= 0xdfff)
          throw const FormatException('Invalid UTF-16 delta');
      }
      records.add((raw.substring(j + 1, k), raw.substring(k + 1, l), content));
      pos = end + 1;
    }
    return records;
  }

  static List<(String, String)> controls(dom.Document soup) {
    final form = soup.querySelector('form');
    if (form == null)
      throw const MonthlyError(
        'The authenticated portal form is unavailable.',
        'SESSION_EXPIRED',
      );
    final pairs = <(String, String)>[];
    for (final node in form.querySelectorAll('input,select,textarea')) {
      final name = node.attributes['name'];
      if (name == null ||
          name.isEmpty ||
          node.attributes.containsKey('disabled'))
        continue;
      if (node.localName == 'select') {
        var options = node.querySelectorAll('option[selected]');
        if (options.isEmpty && !node.attributes.containsKey('multiple'))
          options = node.querySelectorAll('option').take(1).toList();
        for (final option in options)
          if (!option.attributes.containsKey('disabled'))
            pairs.add((name, option.attributes['value'] ?? option.text));
      } else if (node.localName == 'textarea') {
        pairs.add((name, node.text));
      } else {
        final kind = (node.attributes['type'] ?? 'text').toLowerCase();
        if ({'submit', 'image', 'button', 'reset', 'file'}.contains(kind))
          continue;
        if ({'radio', 'checkbox'}.contains(kind) &&
            !node.attributes.containsKey('checked'))
          continue;
        pairs.add((
          name,
          node.attributes['value'] ??
              ({'radio', 'checkbox'}.contains(kind) ? 'on' : ''),
        ));
      }
    }
    if (!pairs.any((p) => p.$1 == '__VIEWSTATE') ||
        !pairs.any((p) => p.$1 == '__EVENTVALIDATION'))
      throw const MonthlyError(
        'Portal form tokens are missing. Refresh the form.',
        'WORKFLOW_EXPIRED',
      );
    return pairs;
  }

  static String encodePairs(List<(String, String)> pairs) => pairs
      .map(
        (p) =>
            '${Uri.encodeQueryComponent(p.$1)}=${Uri.encodeQueryComponent(p.$2)}',
      )
      .join('&');
  static Map<String, String> confirmations(dom.Document soup) {
    final result = <String, String>{};
    for (final action in ['Edit', 'Delete'])
      for (final script in soup.querySelectorAll('script')) {
        final source = script.text,
            m = RegExp(r'function\s+' + action + r'Message\s*\([^)]*\)\s*\{')
                .firstMatch(source);
        if (m != null) {
          final rest = source.substring(m.end),
              end = RegExp(r'\bfunction\s+\w+\s*\(').firstMatch(rest);
          final text = MonthlyTasksWorker.literalConfirmation(
            end == null ? rest : rest.substring(0, end.start),
          );
          if (text != null) result[action] = text;
          break;
        }
      }
    return result;
  }

  static List<String> history(
    Map<String, dynamic> form, {
    (String?, String?)? exclude,
  }) {
    final rows = <List<dynamic>>[];
    for (final r in form['history'])
      if (exclude == null || (r['year'], r['month']) != exclude)
        rows.add([r['year'], r['month'], r['values']]);
    rows.sort((a, b) {
      final y = (a[0] as String).compareTo(b[0]);
      if (y != 0) return y;
      final m = (a[1] as String).compareTo(b[1]);
      if (m != 0) return m;
      final av = a[2] as List, bv = b[2] as List;
      for (var i = 0; i < av.length && i < bv.length; i++) {
        final c = (av[i] as String).compareTo(bv[i]);
        if (c != 0) return c;
      }
      return av.length.compareTo(bv.length);
    });
    return rows.map(monthlyJson).toList();
  }

  static bool equal(Object? a, Object? b) => monthlyJson(a) == monthlyJson(b);
  static void setPeriod(RankingState state, Map<String, String> selection) {
    for (final suffix in ['ddlMonth1', 'ddlyear']) {
      final node = state.soup.getElementById(prefix + suffix),
          value = selection[prefix + suffix];
      if (node == null ||
          node.attributes.containsKey('disabled') ||
          (node.attributes['onchange'] ?? '').isNotEmpty)
        throw const MonthlyError(
          'Portal period controls changed. Refresh the form.',
          'STALE_FORM',
        );
      if (value == null ||
          value == '' ||
          value == '0' ||
          !node
              .querySelectorAll('option')
              .any((o) => (o.attributes['value'] ?? o.text) == value))
        throw const MonthlyError(
          'Selected period is not offered by the portal.',
          'INVALID_SELECTION',
        );
      for (final option in node.querySelectorAll('option')) {
        option.attributes.remove('selected');
        if ((option.attributes['value'] ?? option.text) == value)
          option.attributes['selected'] = '';
      }
    }
  }

  Map<String, dynamic> view(
    RankingState state,
    Map<String, String> selection,
    String school, {
    bool editing = false,
  }) {
    setPeriod(state, selection);
    final form = MonthlyTasksWorker.parseForm(
      state.soup.outerHtml,
      'ranking',
      selection: selection,
      editing: editing,
    );
    form['confirmations'] = confirmations(state.soup);
    form['school_id'] = school;
    form['snapshot'] = worker.signature(form, school);
    return form;
  }

  Future<void> cache(Map<String, dynamic> form) async {
    final selection = form['selection'];
    await worker.statusCache.storeStatus(
      form['school_id'],
      int.parse(selection['${prefix}ddlyear']),
      int.parse(selection['${prefix}ddlMonth1']),
      form['completed'],
      form: form,
    );
  }

  Future<({RankingState state, Map<String, dynamic> form})> read(
    Map<String, String> selection,
    String school, {
    bool refresh = false,
    bool editing = false,
    bool resetPending = true,
  }) async {
    final url = worker.baseUrl().resolve(MonthlyTasksWorker.paths['ranking']!),
        key = stateKey(school);
    var state = _states[key];
    final valid =
        state != null &&
        state.school == school &&
        state.url.toString().toLowerCase() == url.toString().toLowerCase() &&
        worker.now - state.at <= 180;
    if (editing) {
      if (!valid || !state.editing || !equal(state.selection, selection))
        throw const MonthlyError(
          'The portal editing session changed. Refresh and select Edit again.',
          'WORKFLOW_EXPIRED',
        );
      return (
        state: state,
        form: view(state, selection, school, editing: true),
      );
    }
    if (refresh || !valid || state.editing) {
      _states.remove(key);
      try {
        final response = await worker.request(
              url,
              timeout: const Duration(seconds: 30),
              followRedirects: true,
            ),
            body = checkResponse(response, url);
        if (stateKey(school) != key)
          throw const MonthlyError(
            'Login session changed while reading the form.',
            'WORKFLOW_EXPIRED',
          );
        state = RankingState(
          soup: html.parse(body),
          url: url,
          school: school,
          at: worker.now,
          key: key,
          cookies: response.cookies?.copy(),
        );
        controls(state.soup);
        _states[key] = state;
      } on MonthlyError {
        rethrow;
      } catch (_) {
        throw const MonthlyError(
          'Unable to read the portal ranking form.',
          'MONTHLY_UNAVAILABLE',
        );
      }
    }
    var form = view(state, selection, school);
    if (resetPending &&
        form['completed'] == false &&
        form['history_complete'] == true) {
      for (final suffix in fields) {
        final node = state.soup.getElementById(prefix + suffix);
        if (node == null ||
            node.attributes.containsKey('disabled') ||
            node.attributes.containsKey('readonly'))
          throw const MonthlyError(
            'Portal entry fields changed. Refresh the form.',
            'STALE_FORM',
          );
        node.attributes['value'] = '';
      }
      form = view(state, selection, school);
    }
    if (form['history_complete'] != true)
      throw const MonthlyError(
        'Portal saved-entry table is incomplete.',
        'STALE_FORM',
      );
    state.selection = Map.from(selection);
    await cache(form);
    return (state: state, form: form);
  }

  Future<({RankingState state, String message})> post(
    RankingState state,
    String control, {
    bool image = false,
  }) async {
    if (stateKey(state.school) != state.key)
      throw const MonthlyError(
        'Login session changed. Refresh the form.',
        'WORKFLOW_EXPIRED',
      );
    final pairs = controls(state.soup)
      ..removeWhere(
        (p) => {
          r'ctl00$ScriptManager1',
          '__EVENTTARGET',
          '__EVENTARGUMENT',
          '__ASYNCPOST',
        }.contains(p.$1),
      );
    pairs.addAll([
      (r'ctl00$ScriptManager1', '${cp}upPnl|$control'),
      ('__EVENTTARGET', ''),
      ('__EVENTARGUMENT', ''),
      ('__ASYNCPOST', 'true'),
    ]);
    if (image) {
      pairs.addAll([('$control.x', '4'), ('$control.y', '11')]);
    } else {
      final button = state.soup.getElementById('${prefix}sub_btn');
      if (button == null)
        throw const MonthlyError('Portal entry fields changed.', 'STALE_FORM');
      pairs.add((control, button.attributes['value'] ?? 'Submit'));
    }
    _states.remove(state.key);
    try {
      final response = await worker.request(
        state.url,
        body: encodePairs(pairs),
        cookies: state.cookies?.copy(),
        referer: state.url,
        timeout: const Duration(seconds: 60),
        followRedirects: false,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
          'X-MicrosoftAjax': 'Delta=true',
          'X-Requested-With': 'XMLHttpRequest',
        },
      );
      final raw = checkResponse(response, state.url, attempted: true);
      if (stateKey(state.school) != state.key)
        throw const MonthlyError(
          'Login session changed during the operation. Refresh before trying again.',
          'SUBMISSION_UNCONFIRMED',
          attempted: true,
        );
      final records = parseDelta(raw);
      for (final r in records) {
        if (r.$1 == 'error')
          throw MonthlyError(r.$3, 'PORTAL_MESSAGE', attempted: true);
        if (r.$1 == 'pageRedirect')
          throw const MonthlyError(
            'Portal session changed during the operation.',
            'SESSION_EXPIRED',
            attempted: true,
          );
      }
      if (records
              .where((r) => r.$1 == 'updatePanel' && r.$2 == '${prefix}upPnl')
              .length !=
          1)
        throw const MonthlyError(
          'Portal form response is incomplete.',
          'SUBMISSION_UNCONFIRMED',
          attempted: true,
        );
      final fresh = state.copy(), responseMessages = <String>{};
      for (final r in records) {
        if (r.$1 == 'updatePanel') {
          final message = MonthlyTasksWorker.submitResponseError(r.$3);
          if (message.isNotEmpty) responseMessages.add(message);
          final node = fresh.soup.getElementById(r.$2);
          if (node == null)
            throw const MonthlyError(
              'Portal panel changed unexpectedly.',
              'SUBMISSION_UNCONFIRMED',
              attempted: true,
            );
          node.nodes.clear();
          node.nodes.addAll(
            html
                .parseFragment(r.$3, container: node.localName ?? 'div')
                .nodes
                .toList(),
          );
        } else if (r.$1 == 'hiddenField') {
          var node = fresh.soup
              .querySelectorAll('input')
              .where((n) => n.attributes['name'] == r.$2)
              .firstOrNull;
          if (node == null) {
            node = dom.Element.tag('input')
              ..attributes.addAll({'type': 'hidden', 'id': r.$2, 'name': r.$2});
            fresh.soup.querySelector('form')!.append(node);
          }
          node.attributes['value'] = r.$3;
        }
      }
      for (final token in ['__VIEWSTATE', '__EVENTVALIDATION'])
        if (!records.any((r) => r.$1 == 'hiddenField' && r.$2 == token))
          throw const MonthlyError(
            'Portal did not return updated form tokens.',
            'SUBMISSION_UNCONFIRMED',
            attempted: true,
          );
      controls(fresh.soup);
      fresh.at = worker.now;
      fresh.cookies = response.cookies?.copy();
      return (state: fresh, message: responseMessages.join('\n'));
    } on MonthlyError {
      rethrow;
    } catch (_) {
      throw const MonthlyError(
        'Portal operation result is unknown. Refresh before trying again.',
        'SUBMISSION_UNCONFIRMED',
        attempted: true,
      );
    }
  }

  static String actionControl(
    RankingState state,
    Map<String, dynamic> record,
    String action,
  ) {
    final id = record['actions'][action];
    final node = id is String ? state.soup.getElementById(id) : null;
    if (node == null ||
        node.attributes.containsKey('disabled') ||
        (node.attributes['onclick'] ?? '').trim().replaceFirst(
              RegExp(r';+$'),
              '',
            ) !=
            'return ${action}Message()' ||
        !RegExp(
          r'^ctl00\$ContentPlaceHolder1\$grd_Add\$ctl\d+\$btn' + action + r'$',
        ).hasMatch(node.attributes['name'] ?? ''))
      throw const MonthlyError(
        'The selected native action changed. Refresh the form.',
        'STALE_FORM',
      );
    if ((confirmations(state.soup)[action] ?? '').isEmpty)
      throw const MonthlyError(
        'The portal confirmation is unavailable.',
        'CONFIRMATION_UNAVAILABLE',
      );
    return node.attributes['name']!;
  }

  Future<Map<String, dynamic>> action(
    Map<String, String> selection,
    String school,
    String snapshot,
    String action,
  ) async {
    final started = worker.now, read = await this.read(selection, school);
    worker.requireReview(snapshot, read.form, school, action);
    final record = MonthlyTasksWorker.rankingRecord(read.form, selection),
        control = actionControl(read.state, record, action);
    if (action == 'Delete')
      await worker.statusCache.invalidateStatus(
        school,
        int.parse(record['year']),
        int.parse(record['month']),
      );
    final posted = await post(read.state, control, image: true);
    if (action == 'Edit' &&
        !equal(
          MonthlyTasksWorker.parseForm(
            posted.state.soup.outerHtml,
            'ranking',
            selection: null,
            editing: true,
          )['selection'],
          selection,
        ))
      throw const MonthlyError(
        'The portal opened a different reporting period.',
        'EDIT_UNCONFIRMED',
        attempted: true,
      );
    final fresh = view(
      posted.state,
      selection,
      school,
      editing: action == 'Edit',
    );
    if (posted.message.isNotEmpty)
      throw MonthlyError(posted.message, 'PORTAL_MESSAGE', attempted: true);
    if (action == 'Edit') {
      final vals = [
        for (final sec in fresh['sections'])
          for (final f in sec['fields']) f['value'],
      ];
      if (!equal(vals, record['values']) ||
          !equal(history(fresh), history(read.form)) ||
          fresh['can_submit'] != true ||
          (fresh['sections'] as List).any(
            (sec) => (sec['fields'] as List).any((f) => f['readonly'] == true),
          ))
        throw const MonthlyError(
          'The portal Edit response did not match the selected entry.',
          'EDIT_UNCONFIRMED',
          attempted: true,
        );
      posted.state.editing = true;
    } else {
      final expected = monthlyCopy(read.form);
      (expected['history'] as List).removeWhere((r) => equal(r, record));
      if (fresh['history_complete'] != true ||
          fresh['completed'] != false ||
          !equal(history(fresh), history(expected)))
        throw const MonthlyError(
          'Deletion could not be verified. Refresh before trying again.',
          'SUBMISSION_UNCONFIRMED',
          attempted: true,
        );
      posted.state.editing = false;
      await cache(fresh);
    }
    posted.state.selection = Map.from(selection);
    _states[posted.state.key] = posted.state;
    return {
      'success': true,
      'data': fresh,
      'message': '',
      'verified': true,
      'submission_attempted': action == 'Delete',
      'elapsed_ms': ((worker.now - started) * 1000).round(),
    };
  }

  static Map<String, String> fieldWarnings(dom.Document soup, String message) {
    final ids = fields.map((k) => prefix + k).toSet(),
        linked = <String, String>{};
    for (final node in soup.querySelectorAll('[controltovalidate]')) {
      final target = node.attributes['controltovalidate'],
          native = node.attributes['errormessage'] ?? monthlyText(node);
      if (ids.contains(target) && native.isNotEmpty && message.contains(native))
        linked[target!] = native;
    }
    if (linked.isNotEmpty) return linked;
    const aliases = {
      'txtaward': r'अवार्ड|पुरस्कार|award',
      'txtlibbooks': r'पुस्तक|पुस्तकालय|लाइब्रेरी|library|books?',
      'txtsports': r'खेल|स्पोर्ट|sports?',
      'TextBox1':
          r'एस.?डी.?एम.?सी|एस.?एम.?सी|sdmc|smc|बैठक|meeting|दिनांक|तारीख|date',
    };
    for (final line in message.split('\n')) {
      final targets = aliases.entries
          .where((e) => RegExp(e.value, caseSensitive: false).hasMatch(line))
          .map((e) => prefix + e.key)
          .toList();
      if (targets.length == 1) linked[targets.single] = line;
    }
    return linked;
  }

  Future<Map<String, dynamic>> submit(
    Map<String, String> selection,
    String school,
    String snapshot,
    Map<String, String> values, {
    bool editing = false,
  }) async {
    final started = worker.now,
        read = await this.read(
          selection,
          school,
          editing: editing,
          resetPending: false,
        ),
        before = read.form;
    worker.requireReview(snapshot, before, school, 'submit');
    if (before['can_submit'] != true)
      throw const MonthlyError(
        'Portal does not allow submission for this form.',
        'SUBMISSION_BLOCKED',
      );
    MonthlyTasksWorker.validateValues(before, values);
    if (editing &&
        equal([
          for (final f in fields) values[prefix + f],
        ], MonthlyTasksWorker.rankingRecord(before, selection)['values']))
      throw const MonthlyError('No changes to submit.', 'NO_CHANGES');
    final candidate = read.state.copy();
    for (final entry in values.entries) {
      final node = candidate.soup.getElementById(entry.key);
      if (node == null ||
          node.attributes.containsKey('disabled') ||
          node.attributes.containsKey('readonly') ||
          node.attributes['name'] !=
              cp + entry.key.replaceFirst(RegExp('^$prefix'), ''))
        throw const MonthlyError('Portal entry fields changed.', 'STALE_FORM');
      node.attributes['value'] = entry.value;
    }
    await worker.statusCache.invalidateStatus(
      school,
      int.parse(selection['${prefix}ddlyear']!),
      int.parse(selection['${prefix}ddlMonth1']!),
    );
    final posted = await post(candidate, '${cp}sub_btn');
    if (!equal(
      MonthlyTasksWorker.parseForm(
        posted.state.soup.outerHtml,
        'ranking',
      )['selection'],
      selection,
    ))
      throw MonthlyError(
        posted.message.isNotEmpty
            ? posted.message
            : 'The portal Submit response changed the reporting period.',
        'SUBMISSION_UNCONFIRMED',
        attempted: true,
      );
    var fresh = view(posted.state, selection, school);
    final target = (
      selection['${prefix}ddlyear'],
      selection['${prefix}ddlMonth1'],
    );
    final matches = (fresh['history'] as List)
        .where((r) => (r['year'], r['month']) == target)
        .toList();
    if (posted.message.isNotEmpty) {
      if (fresh['history_complete'] == true &&
          equal(history(fresh), history(before)) &&
          ((before['completed'] == true && matches.length == 1) ||
              (before['completed'] == false && matches.isEmpty))) {
        final errors = fieldWarnings(posted.state.soup, posted.message),
            keepEditing = editing && errors.isNotEmpty;
        if (keepEditing) {
          fresh = view(posted.state, selection, school, editing: true);
          if (fresh['can_submit'] != true ||
              (fresh['sections'] as List).any(
                (s) => (s['fields'] as List).any((f) => f['readonly'] == true),
              ))
            throw MonthlyError(
              posted.message,
              'PORTAL_MESSAGE',
              attempted: true,
            );
        }
        posted.state.editing = keepEditing;
        posted.state.selection = Map.from(selection);
        _states[posted.state.key] = posted.state;
        if (!keepEditing) await cache(fresh);
        throw MonthlyError(
          posted.message,
          'PORTAL_MESSAGE',
          attempted: true,
          rejected: true,
          data: fresh,
          fieldErrors: errors,
        );
      }
      throw MonthlyError(posted.message, 'PORTAL_MESSAGE', attempted: true);
    }
    final expected = [for (final f in fields) values[prefix + f]];
    if (fresh['history_complete'] != true ||
        matches.length != 1 ||
        !equal(matches.single['values'], expected) ||
        !equal(
          history(fresh, exclude: target),
          history(before, exclude: target),
        ))
      throw const MonthlyError(
        'Saved data could not be verified. Refresh before trying again.',
        'SUBMISSION_UNCONFIRMED',
        attempted: true,
      );
    posted.state.editing = false;
    posted.state.selection = Map.from(selection);
    _states[posted.state.key] = posted.state;
    await cache(fresh);
    return {
      'success': true,
      'data': fresh,
      'message': '',
      'verified': true,
      'submission_attempted': true,
      'elapsed_ms': ((worker.now - started) * 1000).round(),
    };
  }
}
