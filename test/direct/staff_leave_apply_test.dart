import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:html/parser.dart' as html;
import 'package:flutter_test/flutter_test.dart';

import '../../lib/services/portals/staff_login/direct/http_session.dart';
import '../../lib/services/portals/shaladarpan/direct/school_http.dart';
import '../../lib/services/portals/staff_login/direct/leave_apply_worker.dart';
import '../../lib/services/portals/staff_login/direct/leave_payload.dart';
import 'staff_auth_test.dart' show StaffFakeTransport, staffReply;

const base = 'https://rajshaladarpan.rajasthan.gov.in/SD1';
Map<String, dynamic> payload({bool half = false}) => {
  'reason_id': '1',
  'leave_type_id': '1',
  'from_date': '13/10/2026',
  'to_date': '13/10/2026',
  'from_duration': half ? 'Half' : 'Full',
  'to_duration': half ? 'Half' : 'Full',
  if (half) 'day_type': '2',
  'station_leave': 'N',
  'address': 'At Home',
  'remark': 'Leave Application',
  'confirmed': true,
};
String fixture() =>
    File('test/direct/fixtures/staff_leave_apply_form.html').readAsStringSync();

class LeavePortal {
  LeavePortal({
    this.nextMessage,
    this.finalMessage = 'Leave Request Applied Successfully',
    this.mismatch = false,
    this.uncertain = false,
    this.retainedEdit = false,
    this.edit = false,
    this.delta = false,
    this.clearFields = false,
  });
  final String? nextMessage;
  final String finalMessage;
  final bool mismatch, uncertain, retainedEdit, edit, delta, clearFields;
  late final client = StaffFakeTransport()..handler = respond;
  late final session = StaffHttpSession(client: client)
    ..base = base
    ..user = '99'
    ..authenticated = true;
  var state = html.parse(fixture());
  int applies = 0, nexts = 0, postbacks = 0;
  String? editTarget;
  final forms = <Map<String, String>>[];
  void input(String suffix, String value) {
    state.getElementById('ContentPlaceHolder1_$suffix')!.attributes['value'] =
        value;
  }

  String value(String suffix) {
    final e = state.getElementById('ContentPlaceHolder1_$suffix')!;
    return e.localName == 'select'
        ? e
              .querySelectorAll('option')
              .firstWhere(
                (o) => o.attributes.containsKey('selected'),
                orElse: () => e.querySelectorAll('option').first,
              )
              .attributes['value']!
        : e.attributes['value'] ?? '';
  }

  String deltaRecord(String kind, String id, String content) =>
      '${content.length}|$kind|$id|$content|';
  Future<SchoolHttpReply> respond(Map<String, Object?> req) async {
    final url = req['url'] as String;
    if (req['method'] == 'GET') {
      input('hdnID', retainedEdit ? '501' : '');
      if (edit) {
        final panel = state.getElementById('ContentPlaceHolder1_UpdatePanel1')!;
        state.getElementById('ContentPlaceHolder1_grdLeaveDetails')?.remove();
        panel.nodes.addAll(
          html
              .parseFragment(
                '<table id="ContentPlaceHolder1_grdLeaveDetails"><tr><td>7</td><td>13/10/2026</td><td>13/10/2026</td><td><input id="ContentPlaceHolder1_grid_btnEdit_7" name="ctl00\$ContentPlaceHolder1\$grid\$btnEdit7" type="image"></td></tr></table>',
              )
              .nodes
              .toList(),
        );
      }
      return staffReply(url, state.outerHtml);
    }
    if (url.endsWith('/getTotalDays')) return staffReply(url, '{"d":1}');
    final fields = Uri.splitQueryString(req['content'] as String);
    forms.add(fields);
    for (final e in state.querySelectorAll('input,select,textarea')) {
      final field = fields[e.attributes['name']];
      if (field == null) continue;
      if (e.localName == 'select') {
        for (final o in e.querySelectorAll('option')) {
          o.attributes.remove('selected');
          if (o.attributes['value'] == field)
            o.attributes['selected'] = 'selected';
        }
      } else if (e.localName == 'textarea') {
        e.text = field;
      } else {
        e.attributes['value'] = field;
      }
    }
    String? startup;
    if (fields.keys.any((k) => k.endsWith('btnEdit7.x'))) {
      editTarget = fields.keys.firstWhere((k) => k.endsWith('btnEdit7.x'));
      input('hdnID', '501');
      input('txt_FromDate', '13-10-2026');
      input('txt_ToDate', '13-10-2026');
    } else if ((fields['__EVENTTARGET'] ?? '').isNotEmpty) {
      postbacks++;
      for (final side in ['From', 'To']) {
        final duration = value(
          side == 'From' ? 'ddl_fromDuration' : 'ddl_ToDuration',
        );
        final period = state.getElementById(
          'ContentPlaceHolder1_ddl_${side}DayType',
        )!;
        if (duration == '2')
          period.attributes.remove('disabled');
        else
          period.attributes['disabled'] = 'disabled';
      }
      if (clearFields) input('txt_Remark', 'reset by portal');
    } else if (fields.containsKey('ctl00\$ContentPlaceHolder1\$BtnNext')) {
      nexts++;
      if (nextMessage != null) {
        startup = 'openMsgModal(${jsonEncode(nextMessage)});';
      } else {
        state.getElementById('ContentPlaceHolder1_Txt_From')!.text = value(
          'txt_FromDate',
        );
        state.getElementById('ContentPlaceHolder1_Txt_To')!.text = value(
          'txt_ToDate',
        );
        state.getElementById('ContentPlaceHolder1_Txt_Total')!.text = mismatch
            ? '99'
            : value('Txt_Days');
        state.getElementById('ContentPlaceHolder1_Txt_LeaveType')!.text = state
            .getElementById('ContentPlaceHolder1_ddl_LeaveType')!
            .querySelectorAll('option')
            .firstWhere((o) => o.attributes.containsKey('selected'))
            .text;
        startup = 'OpenPrintPop();';
      }
    } else if (fields.containsKey('ctl00\$ContentPlaceHolder1\$btnApply')) {
      applies++;
      if (uncertain)
        throw TimeoutException('Offline simulated uncertain Apply');
      startup = 'openMsgModal(${jsonEncode(finalMessage)});';
    } else {
      throw StateError('Unexpected offline POST');
    }
    final nonce = 'fresh-${forms.length}';
    state.getElementById('__VIEWSTATE')!.attributes['value'] = nonce;
    state.getElementById('__EVENTVALIDATION')!.attributes['value'] =
        'ev-$nonce';
    state
        .querySelectorAll('script[data-test-startup]')
        .forEach((e) => e.remove());
    if (delta) {
      final panel = state.getElementById('ContentPlaceHolder1_UpdatePanel1')!;
      return staffReply(
        url,
        deltaRecord('updatePanel', panel.id, panel.innerHtml) +
            deltaRecord('hiddenField', '__VIEWSTATE', nonce) +
            deltaRecord('hiddenField', '__EVENTVALIDATION', 'ev-$nonce') +
            (startup == null
                ? ''
                : deltaRecord(
                    'scriptStartupBlock',
                    'ScriptContentNoTags',
                    startup,
                  )),
      );
    }
    if (startup != null)
      state.body!.nodes.addAll(
        html
            .parseFragment('<script data-test-startup>$startup</script>')
            .nodes
            .toList(),
      );
    return staffReply(url, state.outerHtml);
  }

  Future<Map<String, dynamic>> run(Map<String, dynamic> data) =>
      StaffLeaveApplyWorker(session).apply(prepareStaffLeavePayload(data));
}

void main() {
  test(
    'portal page-method error retains its exact JSON message and never applies',
    () async {
      final portal = LeavePortal();
      portal.client.handler = (request) async {
        if ((request['url'] as String).endsWith('/getTotalDays')) {
          return staffReply(
            request['url'] as String,
            '{"Message":"Portal day calculation is unavailable."}',
            status: 500,
          );
        }
        return portal.respond(request);
      };
      final result = await portal.run(payload());
      expect(result['message'], 'Portal day calculation is unavailable.');
      expect(result['message_source'], 'portal');
      expect(portal.applies, 0);
    },
  );
  test(
    'server failure does not mistake hidden modal title for an error body',
    () async {
      final portal = LeavePortal();
      portal.client.handler = (request) async => staffReply(
        request['url'] as String,
        fixture().replaceFirst(
          '<body>',
          '<body><h2>Actual portal server error</h2>',
        ),
        status: 500,
      );
      final result = await portal.run(payload());
      expect(result['code'], 'PORTAL_RESPONSE_ERROR');
      expect(result['message'], 'Actual portal server error');
      expect(portal.applies, 0);
    },
  );
  test(
    'full-day follows source GET/day method/Next/Terms/Apply with fresh tokens',
    () async {
      final portal = LeavePortal();
      final result = await portal.run(payload());
      expect(result['success'], true);
      expect(result['message'], portal.finalMessage);
      expect(result['message_source'], 'portal');
      expect(portal.applies, 1);
      expect(portal.nexts, 1);
      expect(portal.postbacks, 0);
      expect(portal.forms.last['__VIEWSTATE'], 'fresh-1');
      expect(portal.forms.last['ctl00\$ContentPlaceHolder1\$Chk_Terms'], 'on');
      expect(
        portal.forms.first.containsKey('ctl00\$ContentPlaceHolder1\$btnApply'),
        false,
      );
      expect(
        portal.client.requests.every((r) => r['followRedirects'] == false),
        true,
      );
    },
  );
  for (final delta in [false, true]) {
    test(
      'half-day sequential postbacks preserve 0.5 and both periods; delta=$delta',
      () async {
        final portal = LeavePortal(delta: delta);
        final result = await portal.run(payload(half: true));
        expect(result['success'], true, reason: result.toString());
        expect(portal.postbacks, 2);
        expect(portal.applies, 1);
        final next = portal.forms[2];
        expect(next['__VIEWSTATE'], 'fresh-2');
        expect(next['ctl00\$ContentPlaceHolder1\$Txt_Days'], '0.5');
        expect(next['ctl00\$ContentPlaceHolder1\$ddl_FromDayType'], '2');
        expect(next['ctl00\$ContentPlaceHolder1\$ddl_ToDayType'], '2');
      },
    );
  }
  test(
    'exact serial/date edit loads fresh identity and submits same record',
    () async {
      final portal = LeavePortal(edit: true);
      final result = await portal.run({
        ...payload(),
        'record_id': '7',
        'sNo': '7',
        'original_from_date': '13/10/2026',
        'original_to_date': '13/10/2026',
      });
      expect(result['success'], true, reason: result.toString());
      expect(portal.editTarget, isNotNull);
      expect(portal.forms.last['ctl00\$ContentPlaceHolder1\$hdnID'], '501');
    },
  );
  test('wrong serial edit cannot Next or Apply', () async {
    final portal = LeavePortal(edit: true);
    final result = await portal.run({
      ...payload(),
      'record_id': '8',
      'sNo': '8',
      'original_from_date': '13/10/2026',
      'original_to_date': '13/10/2026',
    });
    expect(result['code'], 'EDIT_NOT_READY');
    expect(portal.forms, isEmpty);
    expect(portal.applies, 0);
  });
  test('new form containing retained edit identity cannot submit', () async {
    final portal = LeavePortal(retainedEdit: true);
    expect((await portal.run(payload()))['code'], 'EDIT_NOT_READY');
    expect(portal.forms, isEmpty);
  });
  test(
    'portal Next validation is exact and never overridden or followed by Apply',
    () async {
      const msg = 'अवकाश अवधि मान्य नहीं है।';
      final portal = LeavePortal(nextMessage: msg, delta: true);
      final result = await portal.run(payload());
      expect(result['message'], msg);
      expect(result['message_source'], 'portal');
      expect(portal.applies, 0);
    },
  );
  test('preview mismatch stops final Apply', () async {
    final portal = LeavePortal(mismatch: true);
    expect((await portal.run(payload()))['code'], 'INVALID_PAYLOAD');
    expect(portal.applies, 0);
  });
  test(
    'duration postback losing entered fields stops Next and Apply',
    () async {
      final portal = LeavePortal(clearFields: true);
      expect(
        (await portal.run(payload(half: true)))['code'],
        'INVALID_PAYLOAD',
      );
      expect(portal.nexts, 0);
      expect(portal.applies, 0);
    },
  );
  test('uncertain Apply is sent once and never reported successful', () async {
    final portal = LeavePortal(uncertain: true);
    final result = await portal.run(payload());
    expect(result['code'], 'SAVE_UNCONFIRMED');
    expect(result['submission_attempted'], true);
    expect(portal.applies, 1);
  });
  test(
    'duplicate message preserved and failure words override success',
    () async {
      const msg = 'Already applied successfully for these dates.';
      final portal = LeavePortal(finalMessage: msg, delta: true);
      final result = await portal.run(payload());
      expect(result['success'], false);
      expect(result['message'], msg);
      expect(result['submission_attempted'], true);
      expect(portal.applies, 1);
    },
  );
  test('unrecognized original message stays original and uncertain', () async {
    const msg = 'कृपया अवकाश सूची देखें।';
    final portal = LeavePortal(finalMessage: msg);
    final result = await portal.run(payload());
    expect(result['success'], false);
    expect(result['code'], 'SAVE_UNCONFIRMED');
    expect(result['message'], msg);
  });
  test('unconfirmed preview never opens portal or sends any request', () async {
    final portal = LeavePortal();
    final result = await portal.run({...payload(), 'confirmed': false});
    expect(result['confirmation_required'], true);
    expect(portal.client.requests, isEmpty);
  });
  test('route validation rejects edit without original dates', () {
    expect(
      () => prepareStaffLeavePayload({
        ...payload(),
        'record_id': '7',
        'sNo': '7',
      }),
      throwsA(isA<StaffLeavePayloadError>()),
    );
  });
}
