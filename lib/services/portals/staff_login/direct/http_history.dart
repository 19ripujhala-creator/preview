/// Complete Staff http_history.py equivalent; no row actions or POST replay.
import 'dart:async';
import 'dart:io';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import '../../../core/direct/async_primitives.dart';
import 'http_session.dart';
import 'webforms_delta.dart';

const staffHistoryPath = '/Home/Staff/Staff_LeaveApplication_Applied.aspx';
const staffHistoryRadios = {
  'all': 'ContentPlaceHolder1_rdoLeaveApplicationType_1',
  'pending': 'ContentPlaceHolder1_rdoLeaveApplicationType_0',
};
final staffHistoryPostback = RegExp(
  r'''__doPostBack\(\s*['"]([^'"]+)['"]\s*,\s*['"]([^'"]*)['"]\s*\)''',
);

class StaffHistoryError implements Exception {
  const StaffHistoryError(this.code, this.message);
  final String code, message;
  @override
  String toString() => message;
}

Map<String, dynamic> staffHistoryFailure(
  String code,
  String message, {
  List<Map<String, String>>? records,
  Map<String, dynamic> extra = const {},
}) => {
  'success': false,
  'code': code,
  'message': message,
  'records': records ?? <Map<String, String>>[],
  ...extra,
};
String normalizeStaffHistoryDate(String value) {
  final s = value.trim().split('T').first.split(' ').first;
  var m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
  if (m != null) return '${m[3]}-${m[2]}-${m[1]}';
  m = RegExp(r'^(\d{2})[/-](\d{2})[/-](\d{4})').firstMatch(s);
  return m == null ? s : '${m[1]}-${m[2]}-${m[3]}';
}

List<Map<String, String>> extractStaffHistoryRows(Element table) {
  final direct = table.children.where((e) => e.localName == 'tr').toList();
  final rows = direct.isEmpty ? table.querySelectorAll('tr') : direct;
  final records = <Map<String, String>>[];
  for (final row in rows) {
    if (row.classes.contains('GridPager') || row.querySelector('table') != null)
      continue;
    final cols = row
        .querySelectorAll('td,th')
        .map((e) => staffText(e, ' '))
        .toList();
    if (cols.length < 5 || !RegExp(r'^\d+$').hasMatch(cols[0])) continue;
    final dates = cols
        .map(normalizeStaffHistoryDate)
        .where((s) => RegExp(r'^\d{2}-\d{2}-\d{4}$').hasMatch(s))
        .toList();
    if (dates.length < 2) continue;
    var status = cols.length > 5 ? cols[5] : 'Unknown';
    final low = status.toLowerCase();
    if (['cancel', 'निरस्त', 'रद्द', 'withdrawn'].any(low.contains)) {
      status = 'Cancelled';
    } else if (['reject', 'अस्वीकृत'].any(low.contains)) {
      status = 'Rejected';
    } else if (!RegExp('not|unapproved|unprocessed|नहीं').hasMatch(low) &&
        ['processed', 'approved', 'स्वीकृत'].any(low.contains)) {
      status = 'Approved';
    }
    records.add({
      'sNo': cols[0],
      'type': cols[1],
      'from_date': dates[0],
      'to_date': dates[1],
      'reason': cols[4],
      'status': status.isEmpty ? 'Unknown' : status,
    });
  }
  return records;
}

Element? _ancestor(Element control, bool Function(Element) test) {
  var parent = control.parent;
  while (parent != null) {
    if (test(parent)) return parent;
    parent = parent.parent;
  }
  return null;
}

class StaffHistoryHttp {
  StaffHistoryHttp(this.client, String base, {this.maxPages = 200}) {
    final uri = Uri.parse(base);
    final authority = RegExp(r'^https://([^/?#]+)').firstMatch(base)?.group(1);
    if (uri.scheme != 'https' ||
        authority != staffHost ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        !RegExp(r'^/SD[1-5]$', caseSensitive: false).hasMatch(uri.path)) {
      throw ArgumentError('Expected an official HTTPS SD1-SD5 portal base.');
    }
    if (maxPages < 1) throw ArgumentError('max_pages must be positive');
    url = '$base$staffHistoryPath';
    home = '$base$staffHomePath';
  }
  final StaffTransport client;
  final int maxPages;
  late final String url, home;
  final _lock = AsyncMutex();
  Never _notReady([
    String message =
        'The Staff portal page is unavailable or rejected the postback.',
  ]) => throw StaffHistoryError('PAGE_NOT_READY', message);
  Future<Document> request(
    String method,
    String target, {
    Document? previous,
    String? content,
    Map<String, String> headers = const {},
  }) async {
    final response = method == 'GET'
        ? await client.get(
            target,
            timeout: const Duration(seconds: 20),
            followRedirects: false,
          )
        : await client.post(
            target,
            content: content,
            headers: headers,
            followRedirects: false,
          );
    final low = response.text.toLowerCase();
    final location = Uri.parse(target)
        .resolve(response.headers['location']?.firstOrNull ?? '')
        .toString();
    if (response.statusCode == 401 ||
        (response.statusCode >= 300 &&
            response.statusCode < 400 &&
            RegExp(
              r'/(?:stafflogin|officelogin|login|default)\.aspx',
              caseSensitive: false,
            ).hasMatch(location)))
      throw const StaffHistoryError(
        'SESSION_EXPIRED',
        'Staff session expired.',
      );
    if (response.statusCode == 403)
      throw const StaffHistoryError(
        'ACCESS_DENIED',
        'The Staff portal page is unavailable or rejected the postback.',
      );
    if (response.statusCode >= 500 ||
        [
          'server error in',
          'nullreferenceexception',
          'validation of viewstate mac failed',
          'invalid postback or callback argument',
          'the state information is invalid',
        ].any(low.contains) ||
        response.statusCode != 200)
      _notReady();
    if (previous != null && RegExp(r'^\d+\|').hasMatch(response.text)) {
      for (final (kind, _, value) in parseStaffDelta(response.text)) {
        if (kind == 'pageRedirect') {
          final expired = RegExp(
            r'(?:login|default)\.aspx',
            caseSensitive: false,
          ).hasMatch(value);
          throw StaffHistoryError(
            expired ? 'SESSION_EXPIRED' : 'PAGE_NOT_READY',
            expired ? 'Staff session expired.' : 'The Staff portal page is unavailable or rejected the postback.',
          );
        }
        if (kind == 'error') _notReady();
      }
      return applyStaffDelta(previous, response.text);
    }
    final doc = html.parse(response.text);
    if (doc.querySelector('input#txt_Username') != null &&
        doc.querySelector('input#txtUPNswd,input#btn_StaffLogin') != null)
      throw const StaffHistoryError(
        'SESSION_EXPIRED',
        'Staff session expired.',
      );
    if (doc.querySelector('form') == null)
      _notReady('Staff leave history could not be loaded completely.');
    return doc;
  }

  Element radio(Document doc, String filter) {
    final value = doc.getElementById(staffHistoryRadios[filter]!);
    if (value == null ||
        value.localName != 'input' ||
        value.attributes['type']?.toLowerCase() != 'radio' ||
        (value.attributes['name'] ?? '').isEmpty ||
        value.attributes.containsKey('disabled'))
      _notReady(
        'The Staff portal did not retain the requested leave history filter.',
      );
    return value;
  }

  Future<Document> post(
    Document doc,
    (String, String) event,
    Element selected,
  ) async {
    final form = _ancestor(selected, (e) => e.localName == 'form');
    if (form == null)
      _notReady('Staff leave history could not be loaded completely.');
    final action = Uri.parse(url)
        .resolve(
          (form.attributes['action'] ?? '').isEmpty
              ? url
              : form.attributes['action']!,
        )
        .toString();
    if (action != url ||
        (form.attributes['method'] ?? 'post').toLowerCase() != 'post')
      _notReady('Staff leave history could not be loaded completely.');
    var fields = <(String, String)>[];
    for (final control in form.querySelectorAll('input,select,textarea')) {
      final name = control.attributes['name'],
          kind = (control.attributes['type'] ?? '').toLowerCase();
      if (name == null ||
          name.isEmpty ||
          control.attributes.containsKey('disabled') ||
          _ancestor(
                control,
                (e) =>
                    e.localName == 'fieldset' &&
                    e.attributes.containsKey('disabled'),
              ) !=
              null)
        continue;
      if (['__EVENTTARGET', '__EVENTARGUMENT', '__ASYNCPOST'].contains(name) ||
          ['submit', 'button', 'image', 'file', 'reset'].contains(kind))
        continue;
      if (['radio', 'checkbox'].contains(kind)) {
        if (name == selected.attributes['name'] ||
            !control.attributes.containsKey('checked'))
          continue;
      }
      if (control.localName == 'select') {
        final options = control.querySelectorAll('option');
        var selectedOptions = options
            .where((e) => e.attributes.containsKey('selected'))
            .toList();
        if (selectedOptions.isEmpty &&
            options.isNotEmpty &&
            !control.attributes.containsKey('multiple'))
          selectedOptions = options.take(1).toList();
        fields.addAll(
          selectedOptions
              .where((e) => !e.attributes.containsKey('disabled'))
              .map((e) => (name, e.attributes['value'] ?? e.text)),
        );
      } else {
        fields.add((
          name,
          control.localName == 'textarea'
              ? control.text
              : control.attributes['value'] ?? (kind == 'checkbox' ? 'on' : ''),
        ));
      }
    }
    if (!fields.any((p) => p.$1 == '__VIEWSTATE'))
      _notReady('Staff leave history could not be loaded completely.');
    fields.addAll([
      (selected.attributes['name']!, selected.attributes['value'] ?? 'on'),
      ('__EVENTTARGET', event.$1),
      ('__EVENTARGUMENT', event.$2),
    ]);
    final headers = {
      'Content-Type': 'application/x-www-form-urlencoded',
      'Referer': url,
    };
    final init = RegExp(
      r'''PageRequestManager\._initialize\(\s*['"]([^'"]+)['"]''',
    ).firstMatch(doc.outerHtml);
    if (init != null) {
      final panel = _ancestor(selected, (e) => e.id.contains('UpdatePanel'));
      if (panel == null)
        _notReady('Staff leave history could not be loaded completely.');
      final mapping = RegExp(
        '''['"]t([^'"]+)['"]\\s*,\\s*['"]${RegExp.escape(panel.id)}['"]''',
      ).firstMatch(doc.outerHtml);
      if (mapping == null)
        _notReady('Staff leave history could not be loaded completely.');
      fields = fields.where((p) => p.$1 != init[1]).toList()
        ..addAll([
          (init[1]!, '${mapping[1]}|${event.$1}'),
          ('__ASYNCPOST', 'true'),
        ]);
      headers.addAll({
        'X-MicrosoftAjax': 'Delta=true',
        'X-Requested-With': 'XMLHttpRequest',
      });
    }
    final body = fields
        .map(
          (p) =>
              '${Uri.encodeQueryComponent(p.$1)}=${Uri.encodeQueryComponent(p.$2)}',
        )
        .join('&');
    return request(
      'POST',
      action,
      previous: doc,
      content: body,
      headers: headers,
    );
  }

  Element grid(Document doc) {
    final table = doc
        .querySelectorAll('table[id]')
        .where((e) => e.id.contains('grdLeaveDetails'))
        .firstOrNull;
    if (table == null)
      throw const StaffHistoryError(
        'INVALID_RESULT',
        'Portal leave-history grid was not found.',
      );
    return table;
  }

  Map<int, (String, String)> links(Element table) {
    final result = <int, (String, String)>{};
    for (final a in table.querySelectorAll('a[href]')) {
      final href = a.attributes['href']!,
          match = staffHistoryPostback.firstMatch(href);
      if (href.contains('Page\$')) {
        if (match == null ||
            !RegExp(r'^Page\$[1-9]\d*$').hasMatch(match[2]!) ||
            !{
              table.id,
              'ctl00_${table.id}',
            }.contains(match[1]!.replaceAll('\$', '_')))
          _notReady('The requested history page link is unavailable.');
        result[int.parse(match[2]!.substring(5))] = (match[1]!, match[2]!);
      }
    }
    return result;
  }

  Element confirm(Document doc, String filter, [int? number]) {
    if (!radio(doc, filter).attributes.containsKey('checked'))
      _notReady(
        'The Staff portal did not retain the requested leave history filter.',
      );
    final table = grid(doc);
    if (number != null &&
        !table
            .querySelectorAll('tr')
            .any(
              (row) =>
                  row
                      .querySelectorAll('a[href]')
                      .any(
                        (a) =>
                            RegExp(r'Page\$').hasMatch(a.attributes['href']!),
                      ) &&
                  row
                      .querySelectorAll('span')
                      .any((s) => staffText(s) == '$number'),
            ))
      _notReady('Portal did not confirm the requested history page.');
    return table;
  }

  Future<Map<String, dynamic>> fetch([String filter = 'all']) async {
    if (!staffHistoryRadios.containsKey(filter))
      return staffHistoryFailure(
        'INVALID_PAYLOAD',
        'History filter must be all or pending.',
      );
    final release = await _lock.acquire(
      cancellation: OperationCancellation.current,
    );
    try {
      return await _fetch(filter);
    } finally {
      release();
    }
  }

  Future<Map<String, dynamic>> _fetch(String filter) async {
    final records = <Map<String, String>>[],
        seen = <String>{},
        visited = <int>{},
        discovered = <int>{};
    int? number;
    try {
      Document doc;
      try {
        doc = await request('GET', url);
      } on StaffHistoryError catch (e) {
        if (e.code != 'PAGE_NOT_READY') rethrow;
        await request('GET', home);
        doc = await request('GET', url);
      }
      final selected = radio(doc, filter);
      if (!selected.attributes.containsKey('checked')) {
        final handler =
            '${selected.attributes['onclick'] ?? ''}${selected.attributes['onchange'] ?? ''}'
                .replaceAll("\\'", "'")
                .replaceAll('\\"', '"');
        final event = staffHistoryPostback.firstMatch(handler),
            name = selected.attributes['name']!;
        if (event == null ||
            !{
              name,
              '$name\$${staffHistoryRadios[filter]!.split('_').last}',
            }.contains(event[1]) ||
            event[2] != '')
          _notReady(
            'The Staff portal did not retain the requested leave history filter.',
          );
        doc = await post(doc, (event[1]!, event[2]!), selected);
      }
      var table = confirm(doc, filter);
      var paging = links(table);
      if (paging.containsKey(1)) {
        doc = await post(doc, paging[1]!, radio(doc, filter));
        table = confirm(doc, filter, 1);
      }
      number = 1;
      while (true) {
        if (staffText(table).contains('No Record Found') && records.isEmpty)
          return {
            'success': true,
            'records': <Map<String, String>>[],
            'total': 0,
            'message': 'No leave history found.',
          };
        final rows = extractStaffHistoryRows(table);
        if (rows.isEmpty)
          throw const StaffHistoryError(
            'INVALID_RESULT',
            'No valid leave rows or explicit empty-history message was found.',
          );
        for (final row in rows) {
          final key = '${row['sNo']}|${row['from_date']}|${row['to_date']}';
          if (seen.add(key)) records.add(row);
        }
        visited.add(number!);
        paging = links(table);
        discovered.addAll(paging.keys);
        final remaining = discovered.difference(visited).toList()..sort();
        if (remaining.isEmpty)
          return {'success': true, 'records': records, 'total': records.length};
        if (visited.length >= maxPages)
          throw const StaffHistoryError(
            'INVALID_RESULT',
            'Leave-history page limit reached.',
          );
        number = remaining.first;
        if (!paging.containsKey(number))
          _notReady('The requested history page link is unavailable.');
        doc = await post(doc, paging[number]!, radio(doc, filter));
        table = confirm(doc, filter, number);
      }
    } on StaffHistoryError catch (e) {
      return staffHistoryFailure(
        e.code,
        records.isNotEmpty && e.code == 'SESSION_EXPIRED'
            ? 'Session expired while paging history.'
            : e.message,
        records: records,
        extra: {
          if (records.isNotEmpty) 'partial': true,
          if (records.isNotEmpty && number != null) 'failed_page': number,
        },
      );
    } on IOException {
      return _networkFailure(records);
    } on TimeoutException {
      return _networkFailure(records);
    } on FormatException {
      return _networkFailure(records);
    } on ArgumentError {
      return _networkFailure(records);
    }
  }

  Map<String, dynamic> _networkFailure(List<Map<String, String>> records) =>
      staffHistoryFailure(
        'PAGE_NOT_READY',
        records.isEmpty
            ? 'Staff leave history could not be loaded completely.'
            : 'Leave-history pagination failed.',
        records: records,
        extra: {if (records.isNotEmpty) 'partial': true},
      );
}

Future<Map<String, dynamic>> fetchStaffHttpHistory(
  StaffHttpSession session, [
  String filter = 'all',
]) async {
  if (!staffHistoryRadios.containsKey(filter))
    return staffHistoryFailure(
      'INVALID_PAYLOAD',
      'History filter must be all or pending.',
    );
  return session.exclusive(() async {
    if (!session.authenticated ||
        session.base == null ||
        (session.user ?? '').isEmpty)
      return staffHistoryFailure('SESSION_EXPIRED', 'Staff session expired.');
    return StaffHistoryHttp(session.client, session.base!).fetch(filter);
  });
}
