/// Staff leave application WebForms flow from the working Python worker.
/// A new GET owns each operation. No POST is retried, including an uncertain Apply.
import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import 'http_session.dart';
import 'leave_payload.dart';
import 'portal_state.dart';
import 'webforms_delta.dart';

const staffLeaveApplyPath = '/Home/Staff/Staff_LeaveApplication.aspx';

class StaffLeaveApplyWorker {
  StaffLeaveApplyWorker(this.session, {void Function()? check})
    : check = check ?? (() {}),
      url = '${session.base}$staffLeaveApplyPath';
  final StaffHttpSession session;
  final void Function() check;
  final String url;
  bool submissionAttempted = false;
  List<String> _scripts = [];

  Map<String, dynamic> _failure(String code, String message) => {
    'success': false,
    'code': code,
    'message': message,
    'submission_attempted': submissionAttempted,
    'submitted': submissionAttempted ? null : false,
  };
  Never _reject(String code, String message) =>
      throw StaffPortalError(code, message);
  Element _control(Document doc, String suffix) {
    final el = doc.getElementById('ContentPlaceHolder1_$suffix');
    if (el == null ||
        el.attributes.containsKey('disabled') ||
        (el.attributes['name'] ?? '').isEmpty) {
      _reject(
        'INVALID_PAYLOAD',
        'Portal form fields/options are missing. No leave was submitted.',
      );
    }
    return el;
  }

  String _value(Element? el) {
    if (el == null) return '';
    if (el.localName == 'select') {
      final options = el.querySelectorAll('option');
      final selected =
          options
              .where((e) => e.attributes.containsKey('selected'))
              .firstOrNull ??
          options.firstOrNull;
      return selected?.attributes['value'] ?? selected?.text ?? '';
    }
    return el.localName == 'textarea' ? el.text : el.attributes['value'] ?? '';
  }

  void _set(Document doc, String suffix, String value) {
    final el = _control(doc, suffix);
    if (el.localName == 'select') {
      final matches = el
          .querySelectorAll('option')
          .where(
            (o) =>
                (o.attributes['value'] ?? o.text) == value &&
                !o.attributes.containsKey('disabled'),
          )
          .toList();
      if (matches.length != 1)
        _reject(
          'INVALID_PAYLOAD',
          'Portal form fields/options are missing. No leave was submitted.',
        );
      for (final option in el.querySelectorAll('option')) {
        option.attributes.remove('selected');
      }
      matches.single.attributes['selected'] = 'selected';
    } else if (el.localName == 'textarea') {
      el.text = value;
    } else {
      el.attributes['value'] = value;
    }
  }

  Future<Document> _request(
    String method, {
    Document? previous,
    String? content,
    Map<String, String> headers = const {},
  }) async {
    check();
    final response = method == 'GET'
        ? await session.client.get(
            url,
            followRedirects: false,
            timeout: const Duration(seconds: 20),
          )
        : await session.client.post(
            url,
            content: content,
            headers: headers,
            followRedirects: false,
          );
    check();
    if (response.statusCode >= 300 && response.statusCode < 400) {
      final target = response.url
          .resolve(response.headers['location']?.firstOrNull ?? '')
          .toString();
      _reject(
        RegExp(
              r'(?:login|default)\.aspx|/public',
              caseSensitive: false,
            ).hasMatch(target)
            ? 'SESSION_EXPIRED'
            : 'PAGE_NOT_READY',
        'Staff session or leave form changed.',
      );
    }
    final failure = staffDocumentFailure(
      response.url.toString(),
      response.text,
      response.statusCode,
    );
    if (failure != null || response.statusCode != 200) {
      final errorDoc = html.parse(response.text);
      String? message;
      for (final id in ['msgDiv', 'msg_Success']) {
        final body = errorDoc.getElementById(id);
        if (body != null && staffText(body, ' ').isNotEmpty) {
          message = extractStaffLeaveMessage(
            '<div id="msgDiv">${body.innerHtml}</div>',
          );
          break;
        }
      }
      if (message != null) _reject('PORTAL_MESSAGE', message);
      final heading = html.parse(response.text).querySelector('h2');
      _reject(
        failure == 'PAGE_NOT_READY'
            ? 'PORTAL_RESPONSE_ERROR'
            : failure ?? 'PORTAL_RESPONSE_ERROR',
        heading == null
            ? 'The Staff portal leave form returned HTTP ${response.statusCode}.'
            : staffText(heading, ' '),
      );
    }
    Document doc;
    if (previous != null && RegExp(r'^\d+\|').hasMatch(response.text)) {
      final records = parseStaffDelta(response.text);
      _scripts = [
        for (final (kind, _, value) in records)
          if (kind == 'scriptBlock' || kind == 'scriptStartupBlock') value,
      ];
      for (final (kind, _, value) in records) {
        if (kind == 'error') _reject('PORTAL_MESSAGE', value);
        if (kind == 'pageRedirect')
          _reject(
            RegExp(
                  r'(?:login|default)\.aspx',
                  caseSensitive: false,
                ).hasMatch(value)
                ? 'SESSION_EXPIRED'
                : 'PAGE_NOT_READY',
            'Staff session or leave form changed.',
          );
      }
      doc = applyStaffDelta(previous, response.text);
    } else {
      doc = html.parse(response.text);
      _scripts = doc
          .querySelectorAll('script:not([src])')
          .map((e) => e.text)
          .toList();
    }
    if (doc.querySelector('form') == null)
      _reject('PAGE_NOT_READY', 'The Staff portal leave form is unavailable.');
    return doc;
  }

  /// Only named function declarations are removed; their definitions are not messages.
  String _startup(String source) {
    final pattern = RegExp(r'\bfunction\s+[\w$]+\s*\([^)]*\)\s*\{');
    var text = source;
    while (true) {
      final match = pattern.firstMatch(text);
      if (match == null) return text;
      var depth = 1, end = match.end;
      String? quote;
      for (; end < text.length && depth > 0; end++) {
        final c = text[end];
        if (quote != null) {
          if (c == r'\') {
            end++;
          } else if (c == quote) {
            quote = null;
          }
        } else if (c == "'" || c == '"' || c == '`') {
          quote = c;
        } else if (c == '{') {
          depth++;
        } else if (c == '}') {
          depth--;
        }
      }
      text = text.replaceRange(match.start, end, '');
    }
  }

  String _decodeLiteral(String value) {
    final out = StringBuffer();
    for (var i = 0; i < value.length; i++) {
      var c = value[i];
      if (c != r'\' || i + 1 == value.length) {
        out.write(c);
        continue;
      }
      c = value[++i];
      if ((c == 'u' || c == 'x') && i + (c == 'u' ? 4 : 2) < value.length) {
        final n = c == 'u' ? 4 : 2;
        final code = int.tryParse(value.substring(i + 1, i + 1 + n), radix: 16);
        if (code != null) {
          out.writeCharCode(code);
          i += n;
          continue;
        }
      }
      out.write(switch (c) {
        'n' => '\n',
        'r' => '\r',
        't' => '\t',
        _ => c,
      });
    }
    return out.toString();
  }

  String? _message(Document doc) {
    final literal = RegExp(
      r'''\b(?:openMsgModal|openAlreadyApplyPopup|alert)\s*\(\s*(['"])((?:\\.|(?!\1)[\s\S])*)\1\s*\)''',
    );
    for (final script in _scripts) {
      final calls = literal.allMatches(_startup(script)).toList();
      if (calls.isNotEmpty) {
        final message = staffText(
          html.parseFragment(_decodeLiteral(calls.last[2]!)),
          ' ',
        );
        if (message.isNotEmpty) return message;
      }
    }
    // A hidden modal's title/Close button is not a portal validation result.
    // Browser workers first read the visible result; HTTP must use the actual
    // message body or this response's startup call, never template chrome.
    for (final id in ['msgDiv', 'msg_Success']) {
      final body = doc.getElementById(id);
      if (body != null && staffText(body, ' ').isNotEmpty) {
        return extractStaffLeaveMessage(
          '<div id="msgDiv">${body.innerHtml}</div>',
        );
      }
    }
    for (final id in ['MsgPopup', 'AlreadyApplyPopup']) {
      final popup = doc.getElementById(id);
      if (popup != null &&
          (popup.classes.contains('show') ||
              popup.classes.contains('in') ||
              RegExp(
                r'display\s*:\s*block',
                caseSensitive: false,
              ).hasMatch(popup.attributes['style'] ?? ''))) {
        return extractStaffLeaveMessage(popup.outerHtml);
      }
    }
    return null;
  }

  bool get _previewOpened => _scripts.any(
    (s) =>
        RegExp(r'\bOpenPrintPop\s*\(\s*\)').hasMatch(_startup(s)) ||
        RegExp(r'''['"]#div_StuPrint['"]\s*\)\s*\.modal\s*\(''')
            .hasMatch(_startup(s)),
  );

  Future<Document> _post(
    Document doc,
    Element selected, {
    String eventTarget = '',
    bool finalApply = false,
  }) async {
    check();
    var parent = selected.parent;
    while (parent != null && parent.localName != 'form') {
      parent = parent.parent;
    }
    if (parent == null)
      _reject(
        'INVALID_PAYLOAD',
        'Portal form fields/options are missing. No leave was submitted.',
      );
    final action = Uri.parse(url).resolve(parent.attributes['action'] ?? '');
    if (action.scheme != 'https' ||
        action.host != staffHost ||
        action.query.isNotEmpty ||
        action.fragment.isNotEmpty ||
        action.path.toLowerCase() != Uri.parse(url).path.toLowerCase() ||
        !staffSameNode(session.base!, action.toString())) {
      _reject(
        'INVALID_PAYLOAD',
        'The portal leave form action changed. No leave was submitted.',
      );
    }
    final fields = <(String, String)>[];
    for (final control in parent.querySelectorAll('input,select,textarea')) {
      final name = control.attributes['name'],
          type = control.attributes['type']?.toLowerCase() ?? '';
      var ancestor = control.parent;
      var disabled = control.attributes.containsKey('disabled');
      while (ancestor != null && ancestor != parent) {
        disabled |=
            ancestor.localName == 'fieldset' &&
            ancestor.attributes.containsKey('disabled');
        ancestor = ancestor.parent;
      }
      if (disabled ||
          name == null ||
          name.isEmpty ||
          ['submit', 'button', 'image', 'file', 'reset'].contains(type) ||
          ['__EVENTTARGET', '__EVENTARGUMENT', '__ASYNCPOST'].contains(name))
        continue;
      if (['checkbox', 'radio'].contains(type) &&
          !control.attributes.containsKey('checked'))
        continue;
      fields.add((
        name,
        ['checkbox', 'radio'].contains(type)
            ? control.attributes['value'] ?? 'on'
            : _value(control),
      ));
    }
    if (!fields.any((f) => f.$1 == '__VIEWSTATE') ||
        !fields.any((f) => f.$1 == '__EVENTVALIDATION'))
      _reject(
        'INVALID_PAYLOAD',
        'Portal WebForms state is missing. No leave was submitted.',
      );
    final name = selected.attributes['name']!;
    fields.addAll([('__EVENTTARGET', eventTarget), ('__EVENTARGUMENT', '')]);
    if (eventTarget.isEmpty) {
      if (selected.attributes['type']?.toLowerCase() == 'image')
        fields.addAll([('$name.x', '1'), ('$name.y', '1')]);
      else
        fields.add((name, selected.attributes['value'] ?? ''));
    }
    final headers = <String, String>{
      'Content-Type': 'application/x-www-form-urlencoded',
      'Referer': url,
    };
    final init = RegExp(
      r'''PageRequestManager\._initialize\(\s*['"]([^'"]+)['"]''',
    ).firstMatch(doc.outerHtml);
    if (init != null) {
      var panel = selected.parent;
      while (panel != null && !panel.id.contains('UpdatePanel')) {
        panel = panel.parent;
      }
      if (panel == null)
        _reject(
          'INVALID_PAYLOAD',
          'Portal UpdatePanel changed. No leave was submitted.',
        );
      final mapping = RegExp(
        '''['"]t([^'"]+)['"]\\s*,\\s*['"]${RegExp.escape(panel.id)}['"]''',
      ).firstMatch(doc.outerHtml);
      if (mapping == null)
        _reject(
          'INVALID_PAYLOAD',
          'Portal UpdatePanel changed. No leave was submitted.',
        );
      fields.removeWhere((f) => f.$1 == init[1]);
      fields.addAll([
        (init[1]!, '${mapping[1]}|${eventTarget.isEmpty ? name : eventTarget}'),
        ('__ASYNCPOST', 'true'),
      ]);
      headers.addAll({
        'X-MicrosoftAjax': 'Delta=true',
        'X-Requested-With': 'XMLHttpRequest',
      });
    }
    final content = fields
        .map(
          (f) =>
              '${Uri.encodeQueryComponent(f.$1)}=${Uri.encodeQueryComponent(f.$2)}',
        )
        .join('&');
    check();
    if (finalApply) submissionAttempted = true;
    return _request('POST', previous: doc, content: content, headers: headers);
  }

  Future<Document> _timing(Document doc, Map<String, dynamic> wanted) async {
    for (var attempts = 0; attempts < 8; attempts++) {
      var changed = false;
      for (final endpoint in ['from', 'to']) {
        final suffix = endpoint == 'from'
            ? 'ddl_fromDuration'
            : 'ddl_ToDuration';
        final el = _control(doc, suffix),
            target = wanted['${endpoint}_duration'];
        final options = el.querySelectorAll('option').where((o) {
          final text = staffText(o, ' ').toLowerCase();
          return target == 'Half'
              ? RegExp(r'\bhalf\b|अर्ध\s*दिवस|आधा\s*दिन').hasMatch(text)
              : RegExp(r'\bfull\b|पूर्ण\s*दिवस|पूरा\s*दिन').hasMatch(text);
        }).toList();
        if (options.length != 1)
          _reject(
            'BAD_DURATION',
            'Portal endpoint duration could not be selected.',
          );
        final value = options.single.attributes['value'] ?? options.single.text;
        if (_value(el) != value) {
          final name = el.attributes['name']!;
          if (!(el.attributes['onchange'] ?? '').contains('__doPostBack'))
            _reject(
              'BAD_DURATION',
              'Portal endpoint duration postback is unavailable.',
            );
          _set(doc, suffix, value);
          doc = await _post(doc, el, eventTarget: name);
          final message = _message(doc);
          if (message != null) _reject('PORTAL_MESSAGE', message);
          changed = true;
          break;
        }
      }
      if (changed) continue;
      for (final endpoint in ['from', 'to']) {
        final period = wanted['${endpoint}_period'];
        final suffix = endpoint == 'from' ? 'ddl_FromDayType' : 'ddl_ToDayType';
        final el = doc.getElementById('ContentPlaceHolder1_$suffix');
        if (period == null &&
            (el == null || el.attributes.containsKey('disabled')))
          continue;
        if (el == null || el.attributes.containsKey('disabled'))
          _reject(
            'BAD_DURATION',
            'The requested endpoint period controls are unavailable.',
          );
        final options = el.querySelectorAll('option').where((o) {
          final text = staffText(o, ' ').toLowerCase();
          if (period == null)
            return !RegExp(
              r'forenoon|afternoon|before\s*noon|after\s*noon|पूर्वाह्न|अपराह्न',
            ).hasMatch(text);
          return (period == 'Forenoon'
                  ? RegExp(r'forenoon|before\s*noon|पूर्वाह्न')
                  : RegExp(r'afternoon|after\s*noon|अपराह्न'))
              .hasMatch(text);
        }).toList();
        if (options.length != 1)
          _reject(
            'BAD_DURATION',
            'Portal endpoint period could not be selected or cleared.',
          );
        _set(
          doc,
          suffix,
          options.single.attributes['value'] ?? options.single.text,
        );
      }
      return doc;
    }
    _reject(
      'BAD_DURATION',
      'Portal timing selection was not retained. No submission was made.',
    );
  }

  void _verify(Document doc, Map<String, dynamic> preview) {
    final from = doc.getElementById('ContentPlaceHolder1_Txt_From'),
        to = doc.getElementById('ContentPlaceHolder1_Txt_To');
    final type = doc.getElementById('ContentPlaceHolder1_ddl_LeaveType');
    final selected = type
        ?.querySelectorAll('option')
        .where((e) => e.attributes.containsKey('selected'))
        .firstOrNull;
    final days = staffText(
      doc.getElementById('ContentPlaceHolder1_Txt_Total') ??
          Element.tag('span'),
      ' ',
    );
    final actualType = staffText(
      doc.getElementById('ContentPlaceHolder1_Txt_LeaveType') ??
          Element.tag('span'),
      ' ',
    );
    final number = RegExp(r'^\d+(?:\.\d+)?$');
    var matches =
        _previewOpened &&
        from != null &&
        to != null &&
        normalizeStaffLeaveDate(staffText(from)) == preview['from_date'] &&
        normalizeStaffLeaveDate(staffText(to)) == preview['to_date'] &&
        _value(type) == preview['leave_type_id'] &&
        actualType.isNotEmpty &&
        selected != null &&
        actualType == staffText(selected, ' ') &&
        number.hasMatch(days) &&
        double.tryParse(days) == preview['total_days'];
    final inputDays = _value(
      doc.getElementById('ContentPlaceHolder1_Txt_Days'),
    );
    matches &=
        number.hasMatch(inputDays) &&
        double.tryParse(inputDays) == preview['total_days'];
    for (final endpoint in ['from', 'to']) {
      matches &=
          _value(
            doc.getElementById(
              'ContentPlaceHolder1_${endpoint == 'from' ? 'ddl_fromDuration' : 'ddl_ToDuration'}',
            ),
          ) ==
          (preview['${endpoint}_duration'] == 'Half' ? '2' : '1');
      if (preview['${endpoint}_duration'] == 'Half')
        matches &=
            _value(
              doc.getElementById(
                'ContentPlaceHolder1_${endpoint == 'from' ? 'ddl_FromDayType' : 'ddl_ToDayType'}',
              ),
            ) ==
            (preview['${endpoint}_day_type'] == 'Forenoon' ? '1' : '2');
    }
    if (!matches)
      _reject(
        'INVALID_PAYLOAD',
        'Portal leave preview does not match the requested type, dates or days. No leave was submitted.',
      );
  }

  Future<Map<String, dynamic>> apply(Map<String, dynamic> data) async {
    if (data['confirmed'] != true) return staffLeaveConfirmation(data);
    final validation = previewStaffLeave(data);
    if (validation['success'] != true) return validation;
    final preview = Map<String, dynamic>.from(validation['preview'] as Map);
    final timing = staffLeaveTiming(data);
    final record = (data['record_id'] ?? data['sNo'] ?? '').toString().trim();
    final edit = record.isNotEmpty && !record.startsWith('LR-');
    try {
      var doc = await _request('GET');
      final startupMessage = _message(doc);
      if (startupMessage != null)
        return {
          ..._failure('PORTAL_MESSAGE', startupMessage),
          'message_source': 'portal',
        };
      if (edit) {
        final originalFrom = normalizeStaffLeaveDate(
              data['original_from_date'] ?? data['from_date'],
            ),
            originalTo = normalizeStaffLeaveDate(
              data['original_to_date'] ?? data['to_date'],
            );
        final target = findStaffLeaveEditTarget(
          doc.outerHtml,
          originalFrom,
          originalTo,
          serialNumber: record,
        );
        if (target == null)
          _reject(
            'EDIT_NOT_READY',
            'The selected leave could not be matched in the fresh portal pending grid. Refresh history and select Edit again. No update was submitted.',
          );
        final button = doc.getElementById(target['button_id']!)!;
        doc = await _post(doc, button);
        final message = _message(doc);
        if (message != null) _reject('PORTAL_MESSAGE', message);
        final id = _value(doc.getElementById('ContentPlaceHolder1_hdnID'));
        if (!RegExp(r'^\d+$').hasMatch(id) ||
            int.parse(id) <= 0 ||
            normalizeStaffLeaveDate(
                  _value(
                    doc.getElementById('ContentPlaceHolder1_txt_FromDate'),
                  ),
                ) !=
                originalFrom ||
            normalizeStaffLeaveDate(
                  _value(doc.getElementById('ContentPlaceHolder1_txt_ToDate')),
                ) !=
                originalTo)
          _reject(
            'EDIT_NOT_READY',
            'The portal did not load the selected leave into edit mode. No update was submitted.',
          );
      } else {
        final identity = doc.getElementById('ContentPlaceHolder1_hdnID');
        if (identity == null || !{'', '0'}.contains(_value(identity).trim()))
          _reject(
            'EDIT_NOT_READY',
            'The portal retained an edit identity in the new leave form. No leave was submitted.',
          );
      }
      final expected = <String, String>{
        'ddl_LeaveReason': (data['reason_id'] as String).trim(),
        'ddl_LeaveType': (data['leave_type_id'] as String).trim(),
        'txt_FromDate': preview['from_date'] as String,
        'txt_ToDate': preview['to_date'] as String,
        'txt_AddressDuringLeave': (data['address'] ?? 'None').toString().trim(),
        'txt_Remark': (data['remark'] ?? 'None').toString().trim(),
      };
      for (final entry in expected.entries) {
        _set(doc, entry.key, entry.value);
      }
      final station = _control(
        doc,
        data['station_leave'] == 'Y'
            ? 'rbl_StationLeaveReq_0'
            : 'rbl_StationLeaveReq_1',
      );
      for (final radio in doc.querySelectorAll('input[type="radio"]')) {
        if (radio.attributes['name'] == station.attributes['name'])
          radio.attributes.remove('checked');
      }
      station.attributes['checked'] = 'checked';
      // Source onValueChange calls the portal page method before the worker
      // explicitly replaces its result with the validated endpoint day count.
      check();
      final reply = await session.client.post(
        '$url/getTotalDays',
        content: jsonEncode({
          'fromDate': preview['from_date'],
          'toDate': preview['to_date'],
        }),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Referer': url,
        },
        followRedirects: false,
      );
      check();
      dynamic daysReply;
      try {
        daysReply = jsonDecode(reply.text);
      } on FormatException {
        daysReply = null;
      }
      if (reply.statusCode != 200 ||
          daysReply is! Map ||
          !daysReply.containsKey('d')) {
        final original = daysReply is Map
            ? daysReply['Message'] ?? daysReply['message']
            : null;
        if (original is String && original.trim().isNotEmpty)
          _reject('PORTAL_MESSAGE', original);
        _reject(
          reply.statusCode == 401 ? 'SESSION_EXPIRED' : 'PAGE_NOT_READY',
          'The portal leave day calculation could not be read. No leave was submitted.',
        );
      }
      doc = await _timing(doc, timing);
      for (final entry in expected.entries) {
        if (_value(doc.getElementById('ContentPlaceHolder1_${entry.key}'))
                .replaceAll('/', '-') !=
            entry.value.replaceAll('/', '-'))
          _reject(
            'INVALID_PAYLOAD',
            'Portal form changed while applying selections. No leave was submitted.',
          );
      }
      final count = preview['total_days'] as double;
      _set(
        doc,
        'Txt_Days',
        count == count.truncateToDouble()
            ? count.toInt().toString()
            : count.toString(),
      );
      doc = await _post(doc, _control(doc, 'BtnNext'));
      final nextMessage = _message(doc);
      if (nextMessage != null)
        return {
          ..._failure('PORTAL_MESSAGE', nextMessage),
          'message_source': 'portal',
        };
      _verify(doc, preview);
      _control(doc, 'Chk_Terms').attributes['checked'] = 'checked';
      doc = await _post(doc, _control(doc, 'btnApply'), finalApply: true);
      final message = _message(doc);
      if (message != null) {
        final verdict = classifyStaffLeaveMessage(message);
        return {
          'success': verdict == true,
          'message': message,
          'message_source': 'portal',
          'submission_attempted': true,
          'submitted': verdict == true ? true : null,
          if (verdict == null) 'code': 'SAVE_UNCONFIRMED',
        };
      }
      return _failure(
        'SAVE_UNCONFIRMED',
        'The portal result could not be verified. Check leave history before submitting again.',
      );
    } on StaffPortalError catch (e) {
      return {
        ..._failure(
          submissionAttempted && e.code != 'PORTAL_MESSAGE'
              ? 'SAVE_UNCONFIRMED'
              : e.code,
          e.message,
        ),
        if (e.code == 'PORTAL_MESSAGE') 'message_source': 'portal',
      };
    } on StaffLeavePayloadError catch (e) {
      return _failure(
        submissionAttempted ? 'SAVE_UNCONFIRMED' : e.code,
        e.message,
      );
    } catch (_) {
      return _failure(
        submissionAttempted ? 'SAVE_UNCONFIRMED' : 'PAGE_NOT_READY',
        submissionAttempted
            ? 'The portal result could not be verified. Check leave history before submitting again.'
            : 'The portal leave form could not be prepared. No leave was submitted.',
      );
    }
  }
}
