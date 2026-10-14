/// Complete HTTPX leave_approvals.py conversion. Pending disappearance is
/// never proof of approval: exact saved statuses come from All Applications.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import '../portal_state.dart';
import '../../../core/direct/async_primitives.dart';
import 'staff_attendance.dart' show StaffWebForms, StaffAttendanceError;

typedef LeaveHttpReply = ({
  Uri url,
  int status,
  String html,
  Map<String, List<String>> headers,
});
typedef LeaveHttpRequest = Future<LeaveHttpReply> Function(
  Uri url, {
  Map<String, Object?>? fields,
  Uri? referer,
  String? action,
  bool mutation,
  Duration timeout,
});

String _text(dom.Node node) {
  final values = <String>[];
  void visit(dom.Node child) {
    if (child is dom.Text) {
      final text = child.data.trim();
      if (text.isNotEmpty) values.add(text);
    } else {
      if (child is dom.Element &&
          {'script', 'style', 'template'}.contains(child.localName))
        return;
      for (final item in child.nodes) {
        visit(item);
      }
    }
  }

  visit(node);
  return values.join(' ');
}

String _str(Object? value) => value?.toString() ?? '';
Never _fail(String code, String message) =>
    throw StaffAttendanceError(code, message);
dom.Element? _ownForm(dom.Element element) {
  for (var parent = element.parent; parent != null; parent = parent.parent) {
    if (parent.localName == 'form') return parent;
  }
  return null;
}

class _Controls {
  _Controls(this.row, this.checkbox, this.status);
  final dom.Element row, checkbox, status;
}

class _Page {
  _Page(this.response, this.soup);
  final LeaveHttpReply response;
  final dom.Document soup;
}

class _Loaded {
  _Loaded(this.page, this.data, this.native);
  final _Page page;
  final Map<String, dynamic> data;
  final Map<String, _Controls> native;
}

class LeaveApprovalsWorker {
  LeaveApprovalsWorker({
    required this.request,
    required this.baseUrl,
    required this.schoolId,
    required this.sessionKey,
    this.observeUrl,
    this.check,
    this.clock,
  });
  final LeaveHttpRequest request;
  final Uri Function() baseUrl;
  final String Function() schoolId, sessionKey;
  final Future<void> Function(Uri)? observeUrl;
  final void Function()? check;
  final double Function()? clock;
  final Stopwatch _clock = Stopwatch()..start();
  double get _now => clock?.call() ?? _clock.elapsedMicroseconds / 1000000;
  Map<String, String>? _review;
  String? _reviewKey;
  double _reviewAt = 0;
  static const path = 'Home/School/Staff_LeaveApproval.aspx';
  static const summaryId = 'ContentPlaceHolder1_grdSchoolList';
  static const detailsId = 'ContentPlaceHolder1_grdLeaveDetails';
  static const historyRadio = 'ContentPlaceHolder1_rdoLeaveApplicationType_4';
  static const historyTarget =
      'ctl00\$ContentPlaceHolder1\$rdoLeaveApplicationType\$4';
  void _check(String key) {
    OperationCancellation.current?.check();
    check?.call();
    if (key != sessionKey())
      _fail(
        'ACCOUNT_CHANGED',
        'School login session changed. Fetch leave approvals again.',
      );
  }

  Future<_Page> _checked(LeaveHttpReply response, String key) async {
    _check(key);
    validateSchoolDocument(response.url, response.html, response.status);
    if (response.url.scheme != 'https' ||
        response.url.host != 'rajshaladarpan.rajasthan.gov.in' ||
        !RegExp(
          r'^/SD[1-5]/Home/School/Staff_LeaveApproval\.aspx$',
          caseSensitive: false,
        ).hasMatch(response.url.path))
      _fail(
        'PAGE_NOT_READY',
        'Authenticated leave approval document was not returned.',
      );
    await observeUrl?.call(response.url);
    return _Page(response, html.parse(response.html));
  }

  Future<_Page> _get(String key) async {
    _check(key);
    return _checked(
      await request(
        baseUrl().resolve(path),
        mutation: false,
        timeout: const Duration(seconds: 25),
      ),
      key,
    );
  }

  Future<_Page> _navigate(
    _Page page,
    dom.Element control,
    String key, {
    String action = 'SCHOOL_ENTRY',
  }) async {
    final post = StaffWebForms.post(page.response.url, control);
    _check(key);
    return _checked(
      await request(
        post.url,
        fields: post.fields,
        referer: page.response.url,
        action: action,
        mutation: false,
        timeout: const Duration(seconds: 25),
      ),
      key,
    );
  }

  static ({int count, dom.Element? link}) _summary(
    dom.Document soup,
    String school,
  ) {
    final table = soup.getElementById(summaryId);
    if (table == null)
      _fail('PAGE_NOT_READY', 'School leave summary is missing.');
    final matches = <List<dom.Element>>[];
    for (final row in table.querySelectorAll('tr')) {
      final cells = row.children.where((e) => e.localName == 'td').toList();
      if (cells.length < 4) continue;
      if (RegExp('(?<!\\d)${RegExp.escape(school)}(?!\\d)')
          .hasMatch(cells.take(3).map(_text).join(' ')))
        matches.add([row, ...cells]);
    }
    if (matches.length != 1)
      _fail(
        'PAGE_NOT_READY',
        'A unique summary for the logged-in school was not returned.',
      );
    final found = matches.single;
    // BeautifulSoup get_text(strip=True) without a separator in the count cell.
    final raw = found[4].text.trim();
    if (!RegExp(r'^\d+$').hasMatch(raw))
      _fail('PAGE_NOT_READY', 'Pending leave count is invalid.');
    final links = found[0]
        .querySelectorAll('a[id]')
        .where((e) => RegExp('lnkSchoolName').hasMatch(e.id));
    return (count: int.parse(raw), link: links.isEmpty ? null : links.first);
  }

  static ({List<Map<String, dynamic>> rows, Map<String, _Controls> native})
  _details(dom.Document soup) {
    final table = soup.getElementById(detailsId);
    if (table == null)
      _fail('PAGE_NOT_READY', 'Leave details table is missing.');
    if (table.querySelector('a[href*="Page\$"]') != null)
      _fail(
        'PAGE_NOT_READY',
        'Leave details are paginated; complete verification is unavailable.',
      );
    final rows = <Map<String, dynamic>>[], native = <String, _Controls>{};
    for (final row in table.querySelectorAll('tr')) {
      dom.Element? find(
        String pattern, [
        String tags = 'input[id],select[id],textarea[id]',
      ]) {
        final controls = row
            .querySelectorAll(tags)
            .where((e) => RegExp(pattern, caseSensitive: false).hasMatch(e.id));
        return controls.isEmpty ? null : controls.first;
      }

      final leave = find('hdn_Id', 'input[id]');
      if (leave == null) continue;
      final id = (leave.attributes['value'] ?? '').trim();
      final cells = row.children.where((e) => e.localName == 'td').toList();
      if (id.isEmpty || native.containsKey(id) || cells.length < 8)
        _fail('MATCH_MISMATCH', 'Leave rows are incomplete or duplicated.');
      final cb = find('chkBox'),
          start = find('txtFromDateApproved'),
          end = find('txtToDateApproved'),
          days = find('txtTotalDaysApproved'),
          status = find('ddlLLeaveStatus');
      if (cb == null ||
          start == null ||
          end == null ||
          days == null ||
          status == null)
        _fail('PAGE_NOT_READY', 'Leave approval controls are incomplete.');
      final options = status.querySelectorAll('option');
      final selected =
          status.querySelector('option[selected]') ??
          (options.isEmpty ? null : options.first);
      if (selected == null)
        _fail('PAGE_NOT_READY', 'Leave status is unavailable.');
      rows.add({
        'sno': _text(cells[1]),
        'leave_id': id,
        'name': _text(cells[2]),
        'reason': _text(cells[3]),
        'leave_type': _text(cells[4]),
        'from_date': (start.attributes['value'] ?? '').trim(),
        'to_date': (end.attributes['value'] ?? '').trim(),
        'days': (days.attributes['value'] ?? '').trim(),
        'status_code': selected.attributes['value'] ?? '',
        'checkbox_id': cb.id,
      });
      native[id] = _Controls(row, cb, status);
    }
    return (rows: rows, native: native);
  }

  static String _identity(Map row) => jsonEncode([
    for (final k in [
      'leave_id',
      'name',
      'reason',
      'leave_type',
      'from_date',
      'to_date',
      'days',
      'status_code',
    ])
      row[k],
  ]);
  Future<_Loaded> _load(String key, String school) async {
    var page = await _get(key);
    final summary = _summary(page.soup, school);
    if (summary.count == 0)
      return _Loaded(page, {
        'success': true,
        'pending_count': 0,
        'applications': <Map<String, dynamic>>[],
      }, {});
    if (summary.link == null)
      _fail('PAGE_NOT_READY', 'School leave details link is missing.');
    page = await _navigate(page, summary.link!, key);
    final parsed = _details(page.soup);
    if (parsed.rows.length != summary.count)
      _fail(
        'PAGE_NOT_READY',
        'Leave details do not match the portal summary. Fetch again.',
      );
    return _Loaded(page, {
      'success': true,
      'pending_count': summary.count,
      'applications': parsed.rows,
    }, parsed.native);
  }

  static Map<String, dynamic> failure(Object error, [bool attempted = false]) {
    if (attempted)
      return {
        'success': false,
        'code': 'SAVE_UNCONFIRMED',
        'message': 'Mapping Save was submitted but not verified. Fetch mappings before submitting again.',
        'submission_attempted': true,
        'verified': false,
      };
    final code = error is StaffAttendanceError
        ? error.code
        : error is SchoolDocumentError
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

  Future<Map<String, dynamic>> fetch() async {
    try {
      final key = sessionKey(), school = schoolId().trim();
      final loaded = await _load(key, school);
      _check(key);
      _review = {
        for (final row in loaded.data['applications'] as List)
          _str(row['leave_id']): _identity(row as Map),
      };
      _reviewKey = key;
      _reviewAt = _now;
      return loaded.data;
    } catch (error) {
      return {
        ...failure(error),
        'pending_count': null,
        'applications': <Object>[],
      };
    }
  }

  static ({Uri url, Map<String, Object?> fields}) _historyPayload(
    _Page page,
    dom.Element radio,
  ) {
    final form = _ownForm(radio);
    if (form == null ||
        radio.attributes['value'] != '9' ||
        (radio.attributes['name'] ?? '').isEmpty ||
        radio.attributes.containsKey('disabled'))
      _fail('PAGE_NOT_READY', 'All Applications filter is unavailable.');
    if (!('${radio.attributes['onclick'] ?? ''} ${radio.attributes['href'] ?? ''}')
        .contains(historyTarget))
      _fail('PAGE_NOT_READY', 'Unexpected history filter postback.');
    final fields = <String, Object?>{};
    for (final node in form.querySelectorAll(
      'input[name],select[name],textarea[name]',
    )) {
      if (node.attributes.containsKey('disabled')) continue;
      final name = node.attributes['name']!,
          kind = (node.attributes['type'] ?? 'text').toLowerCase();
      if (node.localName == 'input') {
        if ([
          'submit',
          'button',
          'image',
          'reset',
          'file',
          'checkbox',
        ].contains(kind))
          continue;
        if (kind == 'radio' && !node.attributes.containsKey('checked'))
          continue;
        fields[name] =
            node.attributes['value'] ?? (kind == 'radio' ? 'on' : '');
      } else if (node.localName == 'select') {
        final opts = node.querySelectorAll('option');
        final selected =
            node.querySelector('option[selected]') ??
            (opts.isEmpty ? null : opts.first);
        if (selected != null)
          fields[name] = selected.attributes['value'] ?? _text(selected);
      } else {
        fields[name] = node.text;
      }
    }
    if (_str(fields['__VIEWSTATE']).isEmpty ||
        _str(fields['__EVENTVALIDATION']).isEmpty)
      _fail('PAGE_NOT_READY', 'History filter form tokens are missing.');
    fields['__EVENTTARGET'] = historyTarget;
    fields['__EVENTARGUMENT'] = '';
    fields[radio.attributes['name']!] = '9';
    fields.remove('__ASYNCPOST');
    fields.removeWhere(
      (name, _) => name.toLowerCase().endsWith('scriptmanager1'),
    );
    if (fields.keys.any(
      (name) => RegExp(
        r'\$btn(?:Approve|Yes|Reject)$',
        caseSensitive: false,
      ).hasMatch(name),
    ))
      _fail('PAGE_NOT_READY', 'History filter included a mutation control.');
    final url = page.response.url.resolve(
      form.attributes['action'] ?? page.response.url.toString(),
    );
    if (url.scheme != 'https' ||
        url.authority != page.response.url.authority ||
        url.path.toLowerCase() != page.response.url.path.toLowerCase())
      _fail('PAGE_NOT_READY', 'Unexpected leave history form destination.');
    return (url: url, fields: fields);
  }

  static Map<String, String> historyStatuses(dom.Document soup) {
    final radio = soup.getElementById(historyRadio);
    if (radio == null ||
        !radio.attributes.containsKey('checked') ||
        radio.attributes['value'] != '9')
      _fail('PAGE_NOT_READY', 'All Applications filter is not active.');
    final grid = soup.getElementById(detailsId);
    if (grid == null) _fail('PAGE_NOT_READY', 'Leave history grid is missing.');
    if (grid.querySelector('a[href*="Page\$"],a[onclick*="Page\$"]') != null)
      _fail(
        'PAGE_NOT_READY',
        'Leave history pagination is not supported for verification.',
      );
    final heads = grid
        .querySelectorAll('th')
        .map((e) => _text(e).toLowerCase())
        .toList();
    if (heads.where((e) => e == 'status').length != 1)
      _fail('PAGE_NOT_READY', 'A unique history status column was not found.');
    final index = heads.indexOf('status'), found = <String, String>{};
    for (final row in grid.querySelectorAll('tr')) {
      final ids = row
          .querySelectorAll('input[id]')
          .where(
            (e) => RegExp(r'hdn_Id_\d+$', caseSensitive: false).hasMatch(e.id),
          );
      if (ids.isEmpty) continue;
      final id = (ids.first.attributes['value'] ?? '').trim();
      final cells = row.children.where((e) => e.localName == 'td').toList();
      if (!RegExp(r'^\d+$').hasMatch(id) ||
          found.containsKey(id) ||
          cells.length <= index)
        _fail(
          'MATCH_MISMATCH',
          'Leave history IDs are incomplete or duplicated.',
        );
      if (cells[index].querySelector('select') != null)
        _fail(
          'PAGE_NOT_READY',
          'History status is an action selector, not stored status.',
        );
      final status = _text(cells[index]);
      if (!{'Pending', 'Processed', 'Rejected', 'Cancelled'}.contains(status))
        _fail('PAGE_NOT_READY', 'Unrecognised status in leave history.');
      found[id] = status;
    }
    if (found.isEmpty)
      _fail(
        'PAGE_NOT_READY',
        'Leave history has no verified application rows.',
      );
    return found;
  }

  Future<Map<String, String>> _history(
    _Page page,
    String key,
    String school,
  ) async {
    if (page.soup.getElementById(summaryId) != null) {
      final link = _summary(page.soup, school).link;
      if (link == null)
        _fail('PAGE_NOT_READY', 'School history navigation link is missing.');
      page = await _navigate(page, link, key);
    }
    final radio = page.soup.getElementById(historyRadio);
    if (radio == null)
      _fail('PAGE_NOT_READY', 'All Applications filter was not found.');
    if (!radio.attributes.containsKey('checked')) {
      final post = _historyPayload(page, radio);
      _check(key);
      page = await _checked(
        await request(
          post.url,
          fields: post.fields,
          referer: page.response.url,
          action: 'HISTORY',
          mutation: false,
          timeout: const Duration(seconds: 25),
        ),
        key,
      );
    }
    _check(key);
    return historyStatuses(page.soup);
  }

  Future<void> _saveResponse(LeaveHttpReply response, String key) async {
    _check(key);
    if ([301, 302, 303, 307, 308].contains(response.status)) {
      final location = response.headers['location'];
      final target = response.url.resolve(
        location == null || location.isEmpty ? '' : location.first,
      );
      if (target.scheme != 'https' ||
          target.authority != response.url.authority ||
          !RegExp(
            r'^/SD[1-5](?:/|$)',
            caseSensitive: false,
          ).hasMatch(target.path))
        _fail(
          'PAGE_NOT_READY',
          'Leave POST redirected outside the expected school portal.',
        );
    } else {
      await _checked(response, key);
    }
  }

  static Map<String, String?> _observed(
    Map<String, String> statuses,
    Map<String, Map<String, String>> wanted,
  ) => {for (final id in wanted.keys) id: statuses[id]};
  static bool _verified(
    Map<String, String?> observed,
    Map<String, Map<String, String>> wanted,
  ) => wanted.entries.every(
    (e) =>
        observed[e.key] ==
        (e.value['status'] == '1' ? 'Processed' : 'Rejected'),
  );
  Future<Map<String, dynamic>> submit(
    List<Map<String, dynamic>> actions, {
    required bool userConfirmed,
  }) async {
    var attempted = false;
    final wanted = <String, Map<String, String>>{};
    final key = sessionKey(), school = schoolId().trim();
    try {
      if (!userConfirmed)
        _fail(
          'CONFIRMATION_REQUIRED',
          'Confirm leave actions before processing them.',
        );
      if (actions.isEmpty)
        _fail('INVALID_PAYLOAD', 'Provide at least one leave action.');
      for (final item in actions) {
        final id = _str(item['leave_id']).trim(),
            status = _str(item['status']).trim();
        if (!RegExp(r'^\d+$').hasMatch(id) ||
            wanted.containsKey(id) ||
            !{'1', '2'}.contains(status))
          _fail(
            'INVALID_PAYLOAD',
            'Provide unique leave IDs and an explicit Approve (1) or Reject (2) status.',
          );
        wanted[id] = {'status': status, 'remark': _str(item['remark']).trim()};
      }
      final reviewed = _review;
      if (reviewed == null || _reviewKey != key || _now - _reviewAt > 180)
        _fail(
          'STALE_FORM',
          'Fetch and review the pending leaves before processing them.',
        );
      final before = await _load(key, school), soup = before.page.soup;
      final records = {
        for (final row in before.data['applications'] as List)
          _str(row['leave_id']): row as Map,
      };
      final overrides = <String, String>{};
      final table = soup.getElementById(detailsId);
      if (table == null)
        _fail(
          'STALE_FORM',
          'Selected leave changed or is no longer pending. Fetch again.',
        );
      for (final cb in table.querySelectorAll('input[type=checkbox]')) {
        cb.attributes.remove('checked');
      }
      for (final item in wanted.entries) {
        final row = records[item.key];
        if (row == null || reviewed[item.key] != _identity(row))
          _fail(
            'STALE_FORM',
            'Selected leave changed or is no longer pending. Fetch again.',
          );
        if (row['status_code'] != '0')
          _fail('STALE_FORM', 'Selected leave is not in its pending state.');
        final controls = before.native[item.key]!,
            cb = controls.checkbox,
            status = controls.status;
        if ((cb.attributes['name'] ?? '').isEmpty ||
            cb.attributes.containsKey('disabled') ||
            (status.attributes['name'] ?? '').isEmpty ||
            status.attributes.containsKey('disabled'))
          _fail('PAGE_NOT_READY', 'Leave controls are missing or disabled.');
        if (!status
            .querySelectorAll('option')
            .any(
              (e) =>
                  !e.attributes.containsKey('disabled') &&
                  e.attributes['value'] == item.value['status'],
            ))
          _fail(
            'INVALID_SELECTION',
            'Requested leave status is not offered by the portal.',
          );
        if ((status.attributes['onchange'] ?? '').isNotEmpty)
          _fail(
            'PAGE_NOT_READY',
            'Leave status requires a dependent postback. Nothing was submitted.',
          );
        cb.attributes['checked'] = '';
        overrides[status.attributes['name']!] = item.value['status']!;
        if (item.value['remark']!.isNotEmpty) {
          final remarks = controls.row
              .querySelectorAll('input[id],textarea[id]')
              .where(
                (e) => RegExp('remark', caseSensitive: false).hasMatch(e.id),
              )
              .toList();
          if (remarks.isEmpty ||
              (remarks.first.attributes['name'] ?? '').isEmpty ||
              remarks.first.attributes.containsKey('disabled'))
            _fail(
              'INVALID_PAYLOAD',
              'Portal remark control is unavailable; the remark was not submitted.',
            );
          overrides[remarks.first.attributes['name']!] = item.value['remark']!;
        }
      }
      final buttons = soup
          .querySelectorAll('input[id]')
          .where(
            (e) =>
                RegExp('btnApprove').hasMatch(e.id) &&
                !e.attributes.containsKey('disabled'),
          )
          .toList();
      if (buttons.length != 1)
        _fail(
          'NO_SAVE_BUTTON',
          'A unique native leave approval button was not found.',
        );
      final post = StaffWebForms.post(
        before.page.response.url,
        buttons.single,
        overrides: overrides,
      );
      final names = wanted.keys
          .map((id) => before.native[id]!.checkbox.attributes['name']!)
          .toSet();
      final selected = table
          .querySelectorAll('input[type=checkbox][checked]')
          .map((e) => e.attributes['name'])
          .whereType<String>()
          .toSet();
      if (names.length != selected.length || !names.containsAll(selected))
        _fail(
          'MATCH_MISMATCH',
          'Leave checkbox selection changed. Nothing was submitted.',
        );
      for (final item in wanted.entries) {
        if (post.fields[before.native[item.key]!.status.attributes['name']] !=
            item.value['status'])
          _fail(
            'MATCH_MISMATCH',
            'Leave status payload did not match review. Nothing was submitted.',
          );
      }
      for (final cb in table.querySelectorAll('input[type=checkbox]')) {
        final name = cb.attributes['name'];
        if (names.contains(name) && !post.fields.containsKey(name))
          _fail(
            'MATCH_MISMATCH',
            'Selected leave checkbox is missing from POST data.',
          );
        if (!names.contains(name) && post.fields.containsKey(name))
          _fail(
            'MATCH_MISMATCH',
            'Unreviewed leave checkbox appeared in POST data.',
          );
      }
      _check(key);
      _review = null;
      _reviewKey = null;
      attempted = true;
      final response = await request(
        post.url,
        fields: post.fields,
        referer: before.page.response.url,
        action: 'APPROVE',
        mutation: true,
        timeout: const Duration(seconds: 30),
      );
      await _saveResponse(response, key);
      Map<String, dynamic>? after;
      var pendingError = false;
      late _Page readPage;
      try {
        final loaded = await _load(key, school);
        after = loaded.data;
        readPage = loaded.page;
      } catch (_) {
        pendingError = true;
        readPage = await _get(key);
      }
      final observed = _observed(await _history(readPage, key, school), wanted);
      if (!_verified(observed, wanted))
        return {
          'success': false,
          'code': 'SAVE_UNCONFIRMED',
          'submission_attempted': true,
          'verified': false,
          'message': 'Leave action was submitted, but the exact status was not verified in All Applications. Review the portal before any resubmission.',
          'data': after,
          'observed_statuses': observed,
          'verification_source': 'all_applications',
          'pending_count': after?['pending_count'],
          'refresh_required': after == null,
        };
      return {
        'success': true,
        'message': 'Leave action statuses verified in All Applications.',
        'data': after,
        'submission_attempted': true,
        'verified': true,
        'verification_source': 'all_applications',
        'verified_statuses': observed,
        'refresh_required': pendingError,
      };
    } catch (error) {
      if (attempted) {
        try {
          final observed = _observed(
            await _history(await _get(key), key, school),
            wanted,
          );
          if (_verified(observed, wanted))
            return {
              'success': true,
              'message': 'Leave statuses verified in portal history after an uncertain response.',
              'verified': true,
              'submission_attempted': true,
              'verification_source': 'all_applications',
              'verified_statuses': observed,
              'data': null,
              'refresh_required': true,
            };
        } catch (_) {}
        return {
          ...failure(error, true),
          'message': 'Leave submission outcome could not be confirmed. Check All Applications before submitting again.',
        };
      }
      return failure(error);
    }
  }
}
