/// Conversion of the uploaded HTTPX staff_attendance.py and its _form_post
/// dependency. No browser JavaScript, automatic commit retries or new statuses.
import 'dart:async';
import 'dart:io';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import '../portal_state.dart';
import '../../../core/direct/async_primitives.dart';
import 'student_attendance_worker.dart' show AttendanceHttpReply;

typedef StaffHttpRequest = Future<AttendanceHttpReply> Function(
  Uri url, {
  Map<String, Object?>? fields,
  Uri? referer,
  String? action,
  bool mutation,
  Duration timeout,
});

class StaffAttendanceError implements Exception {
  const StaffAttendanceError(this.code, this.message);
  final String code, message;
  @override
  String toString() => message;
}

String _clean(Object? value) =>
    (value?.toString() ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
String? _code(Object? value) => value == null ? null : value.toString().trim();
String _text(dom.Node node) {
  final parts = <String>[];
  void visit(dom.Node current) {
    if (current is dom.Text) {
      final part = current.data.trim();
      if (part.isNotEmpty) parts.add(part);
    } else {
      if (current is dom.Element &&
          {'script', 'style', 'template'}.contains(current.localName))
        return;
      for (final child in current.nodes) {
        visit(child);
      }
    }
  }

  visit(node);
  return parts.join(' ');
}

bool _visible(dom.Element? node) {
  if (node == null) return false;
  for (dom.Element? parent = node; parent != null; parent = parent.parent) {
    if (parent.attributes.containsKey('hidden') ||
        RegExp(
          r'display\s*:\s*none|visibility\s*:\s*hidden',
          caseSensitive: false,
        ).hasMatch(parent.attributes['style'] ?? ''))
      return false;
  }
  return true;
}

dom.Element? _parent(dom.Element node, String tag) {
  for (var p = node.parent; p != null; p = p.parent) {
    if (p.localName == tag) return p;
  }
  return null;
}

bool _matches(String expression, String value) =>
    RegExp(expression, caseSensitive: false).hasMatch(value);
bool _markedMessage(String message) => _matches(
  r'attendance (?:has been already filled|is already marked|already marked)|उपस्थिति दर्ज हो चुकी है',
  message,
);

/// Preserves incharge_mapping._form_payload/_action_form semantics used by
/// the Python staff worker, including mandatory tokens and last named value.
class StaffWebForms {
  static ({Uri url, Map<String, Object?> fields}) post(
    Uri responseUrl,
    dom.Element control, {
    Map<String, String>? overrides,
    String? eventTarget,
  }) {
    if (control.attributes.containsKey('disabled'))
      throw const StaffAttendanceError(
        'PAGE_NOT_READY',
        'Portal action is disabled.',
      );
    final form = _parent(control, 'form');
    if (form == null)
      throw const StaffAttendanceError(
        'PAGE_NOT_READY',
        'ASP.NET form missing.',
      );
    final fields = <String, Object?>{};
    final kind = (control.attributes['type'] ?? '').toLowerCase();
    for (final node in form.querySelectorAll('input')) {
      final name = node.attributes['name'];
      if (name == null ||
          name.isEmpty ||
          node.attributes.containsKey('disabled'))
        continue;
      final type = (node.attributes['type'] ?? 'text').toLowerCase();
      if (['reset', 'file', 'button'].contains(type)) continue;
      if (['submit', 'image'].contains(type)) {
        if (!identical(node, control)) continue;
        if (type == 'image') {
          fields['$name.x'] = '0';
          fields['$name.y'] = '0';
        } else {
          fields[name] = node.attributes['value'] ?? '';
        }
        continue;
      }
      if (['checkbox', 'radio'].contains(type) &&
          !node.attributes.containsKey('checked'))
        continue;
      fields[name] =
          node.attributes['value'] ?? (type == 'checkbox' ? 'on' : '');
    }
    for (final node in form.querySelectorAll('select')) {
      final name = node.attributes['name'];
      if (name == null ||
          name.isEmpty ||
          node.attributes.containsKey('disabled'))
        continue;
      final options = node.querySelectorAll('option');
      final selected =
          node.querySelector('option[selected]') ??
          (options.isEmpty ? null : options.first);
      if (selected != null)
        fields[name] = selected.attributes['value'] ?? _text(selected);
    }
    for (final node in form.querySelectorAll('textarea[name]')) {
      if (!node.attributes.containsKey('disabled'))
        fields[node.attributes['name']!] = node.text;
    }
    if ((fields['__VIEWSTATE'] ?? '').toString().isEmpty ||
        (fields['__EVENTVALIDATION'] ?? '').toString().isEmpty)
      throw const StaffAttendanceError(
        'PAGE_NOT_READY',
        'ASP.NET form tokens are missing.',
      );
    fields.addAll(overrides ?? {});
    if (eventTarget != null) {
      fields['__EVENTTARGET'] = eventTarget;
      fields['__EVENTARGUMENT'] = '';
    } else if (!['image', 'submit'].contains(kind)) {
      final script =
          '${control.attributes['onclick'] ?? ''}${control.attributes['href'] ?? ''}';
      final match = RegExp(
        r'''__doPostBack\(\s*['"]([^'"]+)['"]''',
        caseSensitive: false,
      ).firstMatch(script);
      if (match == null)
        throw const StaffAttendanceError(
          'PAGE_NOT_READY',
          'Unknown portal action control.',
        );
      fields['__EVENTTARGET'] = match.group(1)!;
      fields['__EVENTARGUMENT'] = '';
    }
    final target = responseUrl.resolve(
      form.attributes['action'] ?? responseUrl.toString(),
    );
    if (target.scheme != 'https' ||
        target.authority != responseUrl.authority ||
        target.path.toLowerCase() != responseUrl.path.toLowerCase())
      throw const StaffAttendanceError(
        'PAGE_NOT_READY',
        'Unexpected ASP.NET form destination.',
      );
    return (url: target, fields: fields);
  }
}

class StaffAttendanceWorker {
  StaffAttendanceWorker({
    required this.request,
    required this.baseUrl,
    required this.schoolId,
    this.observeUrl,
    DateTime Function()? now,
    void Function()? check,
  }) : now = now ?? DateTime.now,
       check = check ?? (() {});
  final StaffHttpRequest request;
  final Uri Function() baseUrl;
  final String Function() schoolId;
  final Future<void> Function(Uri)? observeUrl;
  final DateTime Function() now;
  final void Function() check;
  static const path = 'Home/School/Staff_DailyAttendanceEntry.aspx';
  static const tableSelector = '#ContentPlaceHolder1_grd_NMMSApplicationFilled';
  static const timeMessage =
      'Attendance can only be marked between 8:00 AM - 5:00 PM.';
  DateTime get _india =>
      now().toUtc().add(const Duration(hours: 5, minutes: 30));
  static String _iso(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  String get today => _iso(_india);
  bool get hoursOpen => _india.hour >= 8 && _india.hour < 17;
  void _check() {
    OperationCancellation.current?.check();
    check();
  }

  void _hours() {
    if (!hoursOpen)
      throw const StaffAttendanceError('PORTAL_TIME_RESTRICTED', timeMessage);
  }

  static Map<String, Map<String, dynamic>> index(
    List<Map<String, dynamic>> rows,
  ) {
    final result = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final id = _clean(row['staffId']);
      if (!RegExp(r'^\d+$').hasMatch(id) || result.containsKey(id))
        throw const StaffAttendanceError(
          'IDENTITY_MISMATCH',
          'Missing or duplicate Staff ID on the attendance table.',
        );
      result[id] = row;
    }
    if (result.isEmpty)
      throw const StaffAttendanceError(
        'PAGE_NOT_READY',
        'The staff attendance table contains no identifiable employees.',
      );
    return result;
  }

  static List<Map<String, dynamic>> parseStaffAttendance(String source) {
    final soup = html.parse(source);
    final table = soup.querySelector(tableSelector);
    if (table == null)
      throw const StaffAttendanceError(
        'PAGE_NOT_READY',
        'Staff attendance grid is missing.',
      );
    if (table.querySelector('a[href*="Page\$"]') != null)
      throw const StaffAttendanceError(
        'PAGE_NOT_READY',
        'Paginated staff attendance cannot be verified as a complete list.',
      );
    final rows = <Map<String, dynamic>>[];
    for (final row in table.querySelectorAll('tr')) {
      if (!identical(_parent(row, 'table'), table)) continue;
      final cells = row.children.where((e) => e.localName == 'td').toList();
      if (cells.length < 4) continue;
      dom.Element? control(String part, String tag) {
        for (final node in row.querySelectorAll('$tag[id]')) {
          if (_matches(part, node.id)) return node;
        }
        return null;
      }

      final hidden = control('hdnStaffId', 'input');
      final id = _clean(
        hidden == null ? _text(cells[1]) : hidden.attributes['value'],
      );
      final raw = _clean(_text(control('Lbl_Name', 'span') ?? cells[3]));
      final name = RegExp(r'^(.*?)\s*\((.*?)\)$').firstMatch(raw);
      final select = control('DDLLeave|ddlStatus', 'select');
      final span = control('Lbl_Leave|lbl_Status|lblStatus', 'span');
      final leave = control('hdnLeave', 'input');
      final options = select?.querySelectorAll('option') ?? <dom.Element>[];
      final selected =
          select?.querySelector('option[selected]') ??
          (options.isEmpty ? null : options.first);
      final anchor = select ?? span ?? leave;
      final cell = anchor == null
          ? (cells.length > 4 ? cells[4] : null)
          : _parent(anchor, 'td');
      final status = _clean(
        selected != null
            ? _text(selected)
            : span != null && _text(span).isNotEmpty
            ? _text(span)
            : cell == null
            ? ''
            : _text(cell),
      );
      final leaveValue = leave?.attributes['value'] ?? '';
      final code = selected != null
          ? selected.attributes['value'] ?? ''
          : RegExp(r'^\d+$').hasMatch(leaveValue)
          ? leaveValue
          : null;
      final category = _matches('absent|अनुपस्थित', status)
          ? 'absent'
          : _matches(r'leave|अवकाश|^(?:cl|ml|pl|hpl|el)(?:\b|$)', status)
          ? 'leave'
          : _matches('present|उपस्थित', status)
          ? 'present'
          : 'other';
      rows.add({
        'schoolId': _clean(control('hdnSCHCD', 'input')?.attributes['value']),
        'sno': _clean(_text(cells[0])),
        'staffId': id,
        'employeeId': _clean(_text(cells[2])),
        'name': name == null ? raw : _clean(name.group(1)),
        'post': name == null ? '' : _clean(name.group(2)),
        'status': status,
        'status_code': code,
        'original_status': status,
        'editable':
            select != null && !select.attributes.containsKey('disabled'),
        'selectId': select?.attributes['id'],
        'options': options
            .where(
              (o) =>
                  !o.attributes.containsKey('disabled') &&
                  (o.attributes['value'] ?? '').isNotEmpty &&
                  !_matches('select|choose|चयन', o.text),
            )
            .map(
              (o) => {
                'code': o.attributes['value'] ?? '',
                'label': _clean(_text(o)),
              },
            )
            .toList(),
        'appliedLeave': select == null && category == 'leave' ? status : null,
        'isApprovedLeave': select == null && category == 'leave',
        'category': category,
      });
    }
    index(rows);
    return rows;
  }

  static List<({String id, String code})> preflight(
    List<Map<String, dynamic>> rows,
    List<Map<String, dynamic>> payload,
  ) {
    final portal = index(rows), requested = index(payload);
    if (!_sameIds(portal, requested))
      throw const StaffAttendanceError(
        'IDENTITY_MISMATCH',
        'Submitted Staff IDs do not exactly match the portal table. Nothing was saved.',
      );
    final changes = <({String id, String code})>[];
    for (final item in requested.entries) {
      final row = portal[item.key]!;
      if (_clean(row['sno']) != _clean(item.value['sno']))
        throw const StaffAttendanceError(
          'IDENTITY_MISMATCH',
          'Staff serial number changed. Nothing was saved.',
        );
      final code = _code(item.value['status_code']),
          current = _code(row['status_code']);
      if (row['editable'] == true) {
        final options = (row['options'] as List).cast<Map>();
        if (!options.any((o) => o['code'].toString() == code))
          throw StaffAttendanceError(
            'INVALID_STATUS',
            'Attendance option is not offered by the portal for Staff ID ${item.key}.',
          );
        if (current != code) changes.add((id: item.key, code: code!));
      } else if (current != null) {
        if (code != current ||
            (item.value['original_status']?.toString() ?? '').trim() !=
                (row['original_status']?.toString() ?? '').trim())
          throw StaffAttendanceError(
            'LOCKED_ROW',
            'The portal locks attendance for Staff ID ${item.key}; it cannot be changed.',
          );
      } else if (code != null ||
          _clean(row['original_status']).isEmpty ||
          (item.value['original_status']?.toString() ?? '').trim() !=
              row['original_status']) {
        throw StaffAttendanceError(
          'LOCKED_ROW',
          'The portal-controlled status for Staff ID ${item.key} must be preserved exactly.',
        );
      }
    }
    return changes;
  }

  static bool _sameIds(Map a, Map b) =>
      a.length == b.length && a.keys.every(b.containsKey);
  static String? verificationMismatch(
    List<Map<String, dynamic>> rows,
    List<Map<String, dynamic>> payload,
    List<Map<String, dynamic>> original,
  ) {
    final portal = index(rows),
        expected = index(payload),
        before = index(original);
    if (!_sameIds(portal, expected) || !_sameIds(portal, before))
      return 'employee_identity_set_changed';
    for (final item in expected.entries) {
      final row = portal[item.key]!, old = before[item.key]!;
      final code = _code(item.value['status_code']),
          current = _code(row['status_code']);
      final label = _clean(row['original_status']);
      if (old['editable'] != true) {
        if (label.isEmpty || label != _clean(old['original_status']))
          return 'locked_label_changed staff_id=${item.key}';
        if (current != null && current != code)
          return 'locked_code_changed staff_id=${item.key} expected=$code actual=$current';
        continue;
      }
      final labels = (old['options'] as List)
          .cast<Map>()
          .where((o) => o['code'].toString().trim() == code)
          .map((o) => _clean(o['label']))
          .toList();
      if (labels.length != 1) return 'option_not_unique staff_id=${item.key}';
      if (current != null) {
        if (current != code)
          return 'option_changed staff_id=${item.key} expected=$code actual=$current';
        if (label.isNotEmpty && label != labels.single)
          return 'option_label_changed staff_id=${item.key}';
      } else if (label.isEmpty || label != labels.single) {
        return 'readonly_label_mismatch staff_id=${item.key}';
      }
    }
    return null;
  }

  ({String date, String? timestamp, String text}) _meta(
    dom.Document soup,
    String school,
  ) {
    if (_clean(
          soup
              .getElementById('ContentPlaceHolder1_hdnSCHCD1')
              ?.attributes['value'],
        ) !=
        school)
      throw const StaffAttendanceError(
        'IDENTITY_MISMATCH',
        'Portal attendance school identity is missing or mismatched.',
      );
    String text(String id) {
      final node = soup.getElementById(id);
      return _visible(node) ? _text(node!) : '';
    }

    final rawDate = text('ContentPlaceHolder1_lblMarkAttendanceDate').trim();
    final match = RegExp(r'^(\d{1,2})-(\d{1,2})-(\d{4})$').firstMatch(rawDate);
    if (match == null)
      throw const StaffAttendanceError(
        'PAGE_NOT_READY',
        'The portal attendance date could not be verified.',
      );
    final d = int.parse(match.group(1)!),
        m = int.parse(match.group(2)!),
        y = int.parse(match.group(3)!);
    final parsed = DateTime.utc(y, m, d);
    if (parsed.year != y || parsed.month != m || parsed.day != d)
      throw const StaffAttendanceError(
        'PAGE_NOT_READY',
        'The portal attendance date could not be verified.',
      );
    final date = _iso(parsed);
    if (date != today)
      throw const StaffAttendanceError(
        'STALE_ATTENDANCE',
        'The portal attendance date differs from today. Nothing was changed.',
      );
    final markingText = text('ContentPlaceHolder1_lblAttendanceMarkDate')
        .trim();
    final marker = RegExp(
      r'^Attendance Mark On\s*:\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(markingText);
    String? timestamp = marker?.group(1)?.trim();
    final stamp = RegExp(
      r'^([A-Za-z]{3})\s+(\d{1,2})\s+(\d{4})\s+\d{1,2}:\d{2}:\d{2}(?::\d{1,3})?\s*(?:AM|PM)$',
      caseSensitive: false,
    ).firstMatch(timestamp ?? '');
    if (stamp == null) {
      timestamp = null;
    } else {
      const months = [
        'jan',
        'feb',
        'mar',
        'apr',
        'may',
        'jun',
        'jul',
        'aug',
        'sep',
        'oct',
        'nov',
        'dec',
      ];
      final month = months.indexOf(stamp.group(1)!.toLowerCase()) + 1;
      final day = int.parse(stamp.group(2)!), year = int.parse(stamp.group(3)!);
      final stampedDate = DateTime.utc(year, month, day);
      if (month == 0 ||
          stampedDate.month != month ||
          stampedDate.day != day ||
          _iso(stampedDate) != date)
        timestamp = null;
    }
    return (date: date, timestamp: timestamp, text: markingText);
  }

  String _message(dom.Document soup) =>
      ['msgDiv', 'ContentPlaceHolder1_lblMsg', 'ContentPlaceHolder1_lblMessage']
          .map(soup.getElementById)
          .where(_visible)
          .map((e) => _text(e!))
          .where((e) => e.isNotEmpty)
          .join('\n');
  void _stop(dom.Document soup) {
    final message = _message(soup);
    if (message.isNotEmpty)
      throw StaffAttendanceError('PORTAL_MESSAGE', message);
  }

  Future<({AttendanceHttpReply response, dom.Document soup})> _document(
    Uri url, {
    Map<String, Object?>? fields,
    Uri? referer,
    String? action,
    bool mutation = false,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    _check();
    final response = await request(
      url,
      fields: fields,
      referer: referer,
      action: action,
      mutation: mutation,
      timeout: timeout,
    );
    _check();
    validateSchoolDocument(response.url, response.html, response.status);
    if (response.url.scheme != 'https' ||
        response.url.host != 'rajshaladarpan.rajasthan.gov.in' ||
        !RegExp(
          r'^/SD[1-5]/Home/School/Staff_DailyAttendanceEntry\.aspx$',
          caseSensitive: false,
        ).hasMatch(response.url.path))
      throw const StaffAttendanceError(
        'PAGE_NOT_READY',
        'Expected staff attendance document was not returned.',
      );
    await observeUrl?.call(response.url);
    return (response: response, soup: html.parse(response.html));
  }

  dom.Element? _schoolRow(dom.Document soup, String school) {
    final table = soup.getElementById('ContentPlaceHolder1_grdSchoolList');
    if (table == null) return null;
    final matches = table
        .querySelectorAll('tr')
        .where(
          (row) =>
              RegExp('(?<!\\d)${RegExp.escape(school)}(?!\\d)')
                  .hasMatch(_text(row)),
        )
        .toList();
    if (matches.length != 1)
      throw const StaffAttendanceError(
        'SCHOOL_NOT_FOUND',
        'A unique attendance row for the exact school was not found.',
      );
    return matches.single;
  }

  bool _schoolMarked(dom.Element? row) {
    if (row == null) return false;
    final text = _text(row);
    if (_matches('pending|not marked|not filled|लंबित', text)) return false;
    return _markedMessage(text) ||
        row
            .querySelectorAll('img')
            .any(
              (img) =>
                  _matches(
                    r'(?:tick|checkmark|right|checked)\.(?:png|gif|jpg)(?:\?|$)',
                    img.attributes['src'] ?? '',
                  ) ||
                  _matches(
                    r'^(?:done|marked|verified|tick|checked)$',
                    (img.attributes['alt'] ?? '').trim(),
                  ),
            );
  }

  Map<String, dynamic> _data(
    dom.Document soup,
    String school, [
    bool marked = false,
  ]) {
    final rows = parseStaffAttendance(soup.outerHtml);
    final meta = _meta(soup, school);
    if (rows.any((r) => r['schoolId'] != '' && r['schoolId'] != school))
      throw const StaffAttendanceError(
        'IDENTITY_MISMATCH',
        'Staff attendance belongs to a different school.',
      );
    marked = marked || meta.timestamp != null || _markedMessage(_message(soup));
    final stats = <String, int>{
      'total': rows.length,
      'present': 0,
      'leave': 0,
      'other': 0,
      'absent': 0,
    };
    for (final row in rows) {
      final category = row['category'] as String;
      stats[category] = stats[category]! + 1;
    }
    stats.addAll({
      for (final e in stats.entries.toList()) '${e.key}_staff': e.value,
    });
    return {
      'success': true,
      'school_id': school,
      'date': meta.date,
      'marked_at': marked ? meta.timestamp : null,
      'portal_marking_text': meta.text,
      'is_already_marked': marked,
      'attendance_verified': marked,
      'attendance_status': marked ? 'marked' : 'pending',
      'can_submit': !marked && hoursOpen,
      'restriction_message': !marked && !hoursOpen ? timeMessage : null,
      'stats': stats,
      'staff': rows,
    };
  }

  Future<
    ({
      AttendanceHttpReply response,
      dom.Document soup,
      Map<String, dynamic> data,
    })
  >
  _snapshot(String school) async {
    var page = await _document(baseUrl().resolve(path));
    var message = _message(page.soup);
    if (message.isNotEmpty && !_markedMessage(message))
      throw StaffAttendanceError('PORTAL_MESSAGE', message);
    final row = _schoolRow(page.soup, school);
    final marked = _schoolMarked(row);
    // School-entry postback is READ navigation. Local submission hours must
    // never prevent opening a roster. Preserve actual portal responses and
    // keep _hours() at mutation admission and immediately before each write.
    if (page.soup.querySelector(tableSelector) == null) {
      final links =
          row
              ?.querySelectorAll('a[id]')
              .where((e) => _matches('lnkSchoolName|lnkbtnSchool', e.id))
              .toList() ??
          [];
      if (links.length != 1)
        throw const StaffAttendanceError(
          'SCHOOL_NOT_FOUND',
          'The exact school attendance link was not found.',
        );
      final post = StaffWebForms.post(page.response.url, links.single);
      page = await _document(
        post.url,
        fields: post.fields,
        referer: page.response.url,
        action: 'SCHOOL_ENTRY',
      );
    }
    message = _message(page.soup);
    if (message.isNotEmpty && !_markedMessage(message))
      throw StaffAttendanceError('PORTAL_MESSAGE', message);
    return (
      response: page.response,
      soup: page.soup,
      data: _data(page.soup, school, marked),
    );
  }

  static Map<String, dynamic> _failure(
    String code,
    String message, {
    bool submitted = false,
  }) => {
    'success': false,
    'code': code,
    'message': message,
    'submission_attempted': submitted,
    'attendance_verified': false,
    'diagnostic_stage': null,
  };
  static Map<String, dynamic> errorResult(
    Object error, [
    bool attempted = false,
  ]) {
    if (attempted) {
      final portalText =
          error is StaffAttendanceError &&
              ['PORTAL_MESSAGE', 'PORTAL_TIME_RESTRICTED'].contains(error.code)
          ? error.message
          : null;
      return {
        ..._failure(
          'SAVE_UNCONFIRMED',
          portalText ?? 'Staff attendance submission outcome is uncertain. Refresh and verify before retrying.',
          submitted: true,
        ),
        'portal_message': portalText,
        'message_source':
            portalText != null &&
                (error as StaffAttendanceError).code == 'PORTAL_MESSAGE'
            ? 'portal'
            : 'backend',
        'requires_verification': true,
      };
    }
    if (error is SchoolDocumentError)
      return {
        ...error.result,
        'submission_attempted': false,
        'attendance_verified': false,
      };
    if (error is StaffAttendanceError) {
      return {
        ..._failure(error.code, error.message),
        if ([
          'PORTAL_MESSAGE',
          'PORTAL_TIME_RESTRICTED',
        ].contains(error.code)) ...{
          'portal_message': error.message,
          'message_source': error.code == 'PORTAL_MESSAGE'
              ? 'portal'
              : 'backend_policy',
          'can_submit': false,
        },
      };
    }
    if (error is TimeoutException)
      return _failure('PORTAL_SLOW', 'Staff attendance request timed out.');
    if (error is SocketException ||
        error is HttpException ||
        error is HandshakeException)
      return _failure(
        'NETWORK_ERROR',
        'Staff attendance portal could not be reached.',
      );
    return _failure('PAGE_NOT_READY', 'Staff attendance could not be read.');
  }

  Future<Map<String, dynamic>> fetch() async {
    try {
      return (await _snapshot(schoolId().trim())).data;
    } catch (error) {
      return errorResult(error);
    }
  }

  dom.Element? _button(dom.Document soup, List<String> ids) {
    final found = ids
        .expand((id) => soup.querySelectorAll('[id="$id"]'))
        .where((e) => _visible(e) && !e.attributes.containsKey('disabled'))
        .toList();
    if (found.length > 1)
      throw const StaffAttendanceError(
        'PAGE_NOT_READY',
        'Multiple attendance action controls were returned.',
      );
    return found.isEmpty ? null : found.single;
  }

  void _ack(dom.Document soup) {
    final modal = soup.getElementById('FinalConfirmMsgModal');
    if (modal == null) return;
    final yes = modal
        .querySelectorAll('button')
        .where(
          (e) =>
              (e.attributes['type'] ?? 'button').toLowerCase() == 'button' &&
              _matches(r'^\s*Yes\s*$', _text(e)),
        )
        .toList();
    if (yes.length != 1 ||
        (yes.single.attributes['onclick'] ?? '').isNotEmpty ||
        yes.single.attributes.containsKey('disabled'))
      throw const StaffAttendanceError(
        'PAGE_NOT_READY',
        'Unrecognized native acknowledgement; final lock was blocked.',
      );
  }

  Future<Map<String, dynamic>> submit(
    List<Map<String, dynamic>> payload, {
    required bool userConfirmed,
  }) async {
    var attempted = false;
    try {
      if (!userConfirmed)
        throw const StaffAttendanceError(
          'CONFIRMATION_REQUIRED',
          'Confirm staff attendance before submitting.',
        );
      _hours();
      if (payload.isEmpty)
        throw const StaffAttendanceError(
          'INVALID_PAYLOAD',
          'Provide all staff attendance rows.',
        );
      final school = schoolId().trim();
      final initial = await _snapshot(school);
      final original = (initial.data['staff'] as List)
          .cast<Map<String, dynamic>>();
      final changes = preflight(original, payload);
      _hours();
      if (initial.data['is_already_marked'] == true) {
        if (verificationMismatch(original, payload, original) != null)
          throw const StaffAttendanceError(
            'ALREADY_MARKED',
            'Marked attendance differs from the requested statuses.',
          );
        return {
          'success': true,
          'attendance_verified': true,
          'is_already_marked': true,
          'already_locked': true,
          'submission_attempted': false,
          'message':
              'Portal attendance already matches the requested staff statuses.',
          'outcome': 'already_marked',
          'data': initial.data,
        };
      }
      var response = initial.response, soup = initial.soup;
      _stop(soup);
      var rows = index(parseStaffAttendance(soup.outerHtml));
      for (final change in changes) {
        final row = rows[change.id];
        final node = row == null
            ? null
            : soup.getElementById(row['selectId'] as String? ?? '');
        if (node == null ||
            node.attributes.containsKey('disabled') ||
            (node.attributes['name'] ?? '').isEmpty ||
            !(row!['options'] as List).cast<Map>().any(
              (o) => o['code'] == change.code,
            ))
          throw const StaffAttendanceError(
            'PORTAL_CHANGED',
            'Attendance option changed during preparation.',
          );
        for (final option in node.querySelectorAll('option')) {
          option.attributes.remove('selected');
          if (option.attributes['value'] == change.code)
            option.attributes['selected'] = '';
        }
        final onchange = node.attributes['onchange'] ?? '';
        if (onchange.isNotEmpty) {
          if (!_matches('__doPostBack|WebForm_DoPostBackWithOptions', onchange))
            throw const StaffAttendanceError(
              'PAGE_NOT_READY',
              'Unsupported attendance selector postback. Save was blocked.',
            );
          final form = _parent(node, 'form');
          if (form == null)
            throw const StaffAttendanceError(
              'PAGE_NOT_READY',
              'Staff attendance form is missing.',
            );
          final dummy = dom.Element.tag('input')
            ..attributes.addAll({'type': 'submit', 'name': '_selector_only'});
          form.append(dummy);
          final post = StaffWebForms.post(
            response.url,
            dummy,
            overrides: {
              '__EVENTTARGET': node.attributes['name']!,
              '__EVENTARGUMENT': '',
            },
          );
          post.fields.remove('_selector_only');
          dummy.remove();
          _check();
          _hours();
          final next = await _document(
            post.url,
            fields: post.fields,
            referer: response.url,
            action: 'SELECTOR',
            mutation: true,
          );
          response = next.response;
          soup = next.soup;
          _stop(soup);
          rows = index(parseStaffAttendance(soup.outerHtml));
          if (rows[change.id]?['status_code'] != change.code)
            throw const StaffAttendanceError(
              'OPTION_NOT_APPLIED',
              'Portal attendance option was not applied.',
            );
        }
      }
      final prepared = parseStaffAttendance(soup.outerHtml);
      if (preflight(prepared, payload).isNotEmpty ||
          verificationMismatch(prepared, payload, original) != null)
        throw const StaffAttendanceError(
          'OPTION_NOT_APPLIED',
          'Portal values changed before Save.',
        );
      if (_meta(soup, school).date != initial.data['date'] ||
          initial.data['date'] != today)
        throw const StaffAttendanceError(
          'STALE_ATTENDANCE',
          'Attendance date changed before Save.',
        );
      _stop(soup);
      final button = _button(soup, [
        'ContentPlaceHolder1_btnMarkAttendance',
        'ContentPlaceHolder1_btn_Save',
      ]);
      if (button == null)
        throw const StaffAttendanceError(
          'NO_SAVE_BUTTON',
          'The native attendance Save control is missing.',
        );
      var post = StaffWebForms.post(response.url, button);
      _check();
      _hours();
      attempted = true;
      var next = await _document(
        post.url,
        fields: post.fields,
        referer: response.url,
        action: 'SAVE',
        mutation: true,
        timeout: const Duration(seconds: 30),
      );
      response = next.response;
      soup = next.soup;
      _stop(soup);
      final finalButton = _button(soup, [
        'ContentPlaceHolder1_btnFinalConifrm',
        'ContentPlaceHolder1_btnFinalConfirm',
      ]);
      if (finalButton != null) {
        final confirmation = _data(soup, school);
        if (confirmation['date'] != initial.data['date'] ||
            verificationMismatch(
                  (confirmation['staff'] as List).cast<Map<String, dynamic>>(),
                  payload,
                  original,
                ) !=
                null)
          throw const StaffAttendanceError(
            'OPTION_NOT_APPLIED',
            'Portal values changed before Final Confirm. Lock was blocked.',
          );
        if (confirmation['date'] != today)
          throw const StaffAttendanceError(
            'STALE_ATTENDANCE',
            'Attendance date changed before Final Confirm. Lock was blocked.',
          );
        _ack(soup);
        post = StaffWebForms.post(response.url, finalButton);
        _check();
        _hours();
        next = await _document(
          post.url,
          fields: post.fields,
          referer: response.url,
          action: 'FINAL',
          mutation: true,
          timeout: const Duration(seconds: 30),
        );
      }
      final last = (await _snapshot(school)).data;
      if (last['is_already_marked'] == true &&
          verificationMismatch(
                (last['staff'] as List).cast<Map<String, dynamic>>(),
                payload,
                original,
              ) ==
              null)
        return {
          'success': true,
          'attendance_verified': true,
          'is_already_marked': true,
          'already_locked': true,
          'submission_attempted': true,
          'message': 'Staff attendance confirmed by the portal.',
          'message_source': 'backend_verified',
          'outcome': 'newly_submitted',
          'portalMessages': [],
          'data': last,
        };
      return {
        ..._failure(
          'SAVE_UNCONFIRMED',
          'Portal has not confirmed matching staff attendance. Refresh and verify before retrying.',
          submitted: true,
        ),
        'data': last,
      };
    } catch (error) {
      return errorResult(error, attempted);
    }
  }
}
