import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shaladarpan/experiments/direct_portal_auth.dart';
import 'package:shaladarpan/experiments/direct_incharge_service.dart';
import 'package:shaladarpan/services/portals/shaladarpan/direct/incharge_mapping.dart';
import 'package:shaladarpan/services/portals/shaladarpan/direct/student_attendance_worker.dart';

String fixture(String name) =>
    File('test/direct/fixtures/$name').readAsStringSync();
dynamic golden(String name) => jsonDecode(fixture(name));
const base = 'https://rajshaladarpan.rajasthan.gov.in/SD1/';
const button = 'ContentPlaceHolder1_grd_InchargeDetails_btndeactive_0';

class InchargePortal {
  InchargePortal([this.mode = 'add']);
  final String mode;
  String? override;
  String key = 'cookie-1', school = '123456', node = 'SD1';
  bool saved = false, rotateOnRead = false, wrongUrl = false;
  Object? readError;
  double time = 0;
  int gets = 0;
  final posts = <String>[], payloads = <Map<String, Object?>>[];
  late final worker = InchargeMappingWorker(
    request: request,
    baseUrl: () => Uri.parse(base.replaceFirst('SD1', node)),
    schoolId: () => school,
    sessionKey: () => key,
    clock: () => time,
  );
  Future<AttendanceHttpReply> request(
    Uri url, {
    Map<String, Object?>? fields,
    Uri? referer,
    String? action,
    String? control,
    String? controlId,
    bool mutation = false,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    String body;
    if (fields == null) {
      gets++;
      expect(timeout, const Duration(seconds: 25));
      if (readError != null) throw readError!;
      if (rotateOnRead) key = 'rotated';
      body =
          override ??
          fixture(
            mode == 'empty'
                ? 'incharge_empty.html'
                : saved && !['mismatch', 'rejection'].contains(mode)
                ? mode == 'deactive'
                      ? 'incharge_deactivated.html'
                      : 'incharge_added.html'
                : mode == 'dependent'
                ? 'incharge_dependent.html'
                : 'incharge_page.html',
          );
    } else {
      posts.add(action!);
      payloads.add(Map.from(fields));
      expect(referer, url);
      if (action == 'SELECTOR') {
        expect(mutation, false);
        expect(timeout, const Duration(seconds: 25));
        expect(fields.containsKey('ctl00\$ContentPlaceHolder1\$btnAdd'), false);
        body = fixture(
          control!.endsWith('ddlrole')
              ? 'incharge_role.html'
              : 'incharge_teacher.html',
        );
      } else {
        expect(mutation, true);
        expect(timeout, const Duration(seconds: 30));
        saved = true;
        if (mode == 'timeout') throw TimeoutException('lost response');
        body = mode == 'no_message'
            ? '<span id="lblMsg">Old result</span>'
            : mode == 'rejection'
            ? '<span id="ContentPlaceHolder1_lblError">Portal rejected this request.</span>'
            : '<span id="ContentPlaceHolder1_lblSuccess">Incharge updated successfully.</span>';
      }
    }
    return (
      url: wrongUrl ? Uri.parse('https://example.org/') : url,
      status: 200,
      html: body,
    );
  }

  Future<Map<String, dynamic>> execute({
    String? type,
    String role = '1',
    String teacher = '101',
    String target = button,
    bool confirmed = true,
  }) => worker.execute(
    type ?? (mode == 'deactive' ? 'deactive' : 'add'),
    roleId: role,
    teacherId: teacher,
    buttonId: target,
    userConfirmed: confirmed,
  );
}

class InchargeAuth extends DirectPortalAuth {
  InchargeAuth(this.portal) : super(node: 'SD1');
  final InchargePortal portal;
  @override
  bool get isVerified => true;
  @override
  String? get authenticatedSchoolId => '123456';
  @override
  String get verifiedNode => 'SD1';
  @override
  String get schoolSessionIdentity => portal.key;
  @override
  Future<AttendanceHttpReply> inchargeRequest(
    Uri url, {
    Map<String, Object?>? fields,
    Uri? referer,
    String? action,
    String? control,
    String? controlId,
    bool mutation = false,
    Duration timeout = const Duration(seconds: 25),
    bool userConfirmed = false,
  }) {
    if (fields != null) expect(userConfirmed, true);
    return portal.request(
      url,
      fields: fields,
      referer: referer,
      action: action,
      control: control,
      controlId: controlId,
      mutation: mutation,
      timeout: timeout,
    );
  }
}

class GateAuth extends DirectPortalAuth {
  GateAuth() : super(node: 'SD1');
  @override
  bool get isVerified => true;
}

void main() {
  for (final mode in ['pending', 'empty'])
    test('$mode exact Python READ, including historical duplicates', () async {
      final p = InchargePortal(mode);
      expect(await p.worker.fetch(), golden('python_incharge_$mode.json'));
      expect(p.posts, isEmpty);
    });
  for (final mode in [
    'add',
    'deactive',
    'dependent',
    'timeout',
    'mismatch',
    'rejection',
    'no_message',
  ])
    test('$mode response and every payload match original Python', () async {
      final p = InchargePortal(mode);
      await p.worker.fetch();
      expect(await p.execute(), golden('python_incharge_$mode.json'));
      expect(p.payloads, golden('python_incharge_${mode}_payloads.json'));
      expect(p.posts.where((x) => x != 'SELECTOR').length, 1);
    });
  test('portal messages match Python including Unicode escapes, entities and confirmations', () {
    expect(
      InchargeMappingWorker.portalMessages(fixture('incharge_messages.html')),
      golden('python_incharge_messages.json'),
    );
  });
  test('no confirmation or review allows any request', () async {
    final p = InchargePortal();
    expect(
      (await p.execute(confirmed: false))['code'],
      'CONFIRMATION_REQUIRED',
    );
    expect((await p.execute())['code'], 'STALE_FORM');
    expect(p.gets, 0);
  });
  for (final kind in ['expiry', 'cookie', 'node'])
    test('$kind changes invalidate the review', () async {
      final p = InchargePortal();
      await p.worker.fetch();
      if (kind == 'expiry') p.time = 901;
      if (kind == 'cookie') p.key = 'new';
      if (kind == 'node') p.node = 'SD2';
      expect((await p.execute())['code'], 'STALE_FORM');
      expect(p.posts, isEmpty);
    });
  test(
    'account request mismatch and absent authentication fail closed',
    () async {
      final p = InchargePortal();
      expect(
        (await p.worker.fetch(requestedSchool: '999999'))['code'],
        'ACCOUNT_MISMATCH',
      );
      p.school = '';
      expect((await p.worker.fetch())['code'], 'SESSION_EXPIRED');
      expect(p.gets, 0);
    },
  );
  test('cookie changes during read reject the returned rows', () async {
    final p = InchargePortal()..rotateOnRead = true;
    expect((await p.worker.fetch())['code'], 'SESSION_CHANGED');
  });
  test('unexpected URL does not display a roster', () async {
    final p = InchargePortal()..wrongUrl = true;
    expect((await p.worker.fetch())['code'], 'PAGE_NOT_READY');
  });
  for (final kind in ['selector', 'duplicate-option', 'row', 'pager', 'grid'])
    test('$kind malformed READ preserves source failure shape', () async {
      var s = fixture('incharge_page.html');
      if (kind == 'selector')
        s = s.replaceAll('ContentPlaceHolder1_ddlrole', 'Other');
      if (kind == 'duplicate-option')
        s = s.replaceAll('value="2"', 'value="1"');
      if (kind == 'row') s = s.replaceFirst('<td>Active</td>', '');
      if (kind == 'pager')
        s = s.replaceFirst(
          '</table>',
          '<tr><td><a href="javascript:__doPostBack(\'g\',\'Page\$2\')">Next</a></td></tr></table>',
        );
      if (kind == 'grid')
        s = s.replaceAll('ContentPlaceHolder1_grd_InchargeDetails', 'Other');
      final p = InchargePortal()..override = s;
      final r = await p.worker.fetch();
      expect(r['success'], false);
      expect(r['current_list'], isEmpty);
      expect(r['message_source'], 'backend');
    });
  test('same holder and occupied role dispatch no commit', () async {
    for (final teacher in ['102', '101']) {
      final p = InchargePortal();
      await p.worker.fetch();
      expect(
        (await p.execute(role: '2', teacher: teacher))['code'],
        teacher == '102' ? 'NO_CHANGES' : 'ROLE_OCCUPIED',
      );
      expect(p.posts, isEmpty);
    }
  });
  test('changed dropdown label invalidates review', () async {
    final p = InchargePortal();
    await p.worker.fetch();
    p.override = fixture('incharge_page.html')
        .replaceAll('Teacher A (101)', 'Other Teacher (101)');
    expect((await p.execute())['code'], 'STALE_FORM');
    expect(p.posts, isEmpty);
  });
  test('missing disabled and dependent controls never commit', () async {
    for (final kind in [
      'tokens',
      'disabled',
      'postback',
      'destination',
      'button',
    ]) {
      final p = InchargePortal();
      await p.worker.fetch();
      var s = fixture('incharge_page.html');
      if (kind == 'tokens') s = s.replaceAll('value="STATE1"', 'value=""');
      if (kind == 'disabled')
        s = s.replaceFirst('<select ', '<select disabled ');
      if (kind == 'postback')
        s = s.replaceFirst('<select ', '<select onchange="unknown()" ');
      if (kind == 'destination')
        s = s.replaceAll(
          'action="AddSDSchemeIncharge.aspx"',
          'action="https://example.org/"',
        );
      if (kind == 'button')
        s = s.replaceAll('ContentPlaceHolder1_btnAdd', 'Other');
      p.override = s;
      final r = await p.execute();
      expect(r['success'], false);
      expect(r['submission_attempted'], false);
      expect(p.posts, isEmpty);
    }
  });
  test(
    'deactivate identity mismatch or active duplicates are blocked',
    () async {
      for (final duplicate in [false, true]) {
        final p = InchargePortal('deactive');
        await p.worker.fetch();
        var s = fixture('incharge_page.html');
        s = duplicate
            ? s.replaceAll('Deactive', 'Active')
            : s.replaceFirst('<td>Teacher B</td>', '<td>Other Teacher</td>');
        p.override = s;
        expect(
          (await p.execute())['code'],
          duplicate ? 'MATCH_MISMATCH' : 'STALE_FORM',
        );
        expect(p.posts, isEmpty);
      }
    },
  );
  test('unknown active status is not assumed active or inactive', () async {
    final p = InchargePortal();
    await p.worker.fetch();
    p.override = fixture('incharge_page.html')
        .replaceFirst('<td>Active</td>', '<td>Unknown</td>');
    expect((await p.execute(role: '2'))['code'], 'PAGE_NOT_READY');
    expect(p.posts, isEmpty);
  });
  test(
    'ambiguous status consumes review so immediate duplicate is blocked',
    () async {
      final p = InchargePortal('mismatch');
      await p.worker.fetch();
      expect((await p.execute())['code'], 'SAVE_UNCONFIRMED');
      expect((await p.execute())['code'], 'STALE_FORM');
      expect(p.posts.length, 1);
    },
  );
  test('timeout READ maps to original network error fields', () async {
    for (final error in [
      TimeoutException('slow'),
      const SocketException('offline'),
    ]) {
      final p = InchargePortal()..readError = error;
      final r = await p.worker.fetch();
      expect(
        r['code'],
        error is TimeoutException ? 'NETWORK_TIMEOUT' : 'NETWORK_ERROR',
      );
      expect(r['message_source'], 'backend');
      expect(r['portal_message'], null);
    }
  });
  test(
    'teacher label fallback is unique and strips employee parentheses',
    () async {
      final p = InchargePortal();
      await p.worker.fetch();
      final saved = fixture('incharge_added.html')
          .replaceAll('<td>101</td>', '<td>Different employee code</td>');
      p.override =
          saved; // preflight already assigned must recognize unique name too
      expect((await p.execute())['code'], 'NO_CHANGES');
      expect(p.posts, isEmpty);
    },
  );
  test('casefold identity recognises Python Unicode matching', () {
    expect(InchargeMappingWorker.active({'status': 'AcTiVe'}), true);
    expect(InchargeMappingWorker.active({'status': 'in-active'}), false);
  });
  test(
    'native gate blocks unconfirmed actions and selector mutation controls',
    () async {
      final a = GateAuth();
      addTearDown(a.close);
      final u = Uri.parse('${base}Home/School/AddSDSchemeIncharge.aspx');
      await expectLater(
        a.inchargeRequest(
          u,
          fields: {'ctl00\$ContentPlaceHolder1\$btnAdd': 'Add'},
          referer: u,
          control: 'ctl00\$ContentPlaceHolder1\$btnAdd',
          action: 'add',
          mutation: true,
        ),
        throwsStateError,
      );
      await expectLater(
        a.inchargeRequest(
          u,
          fields: {
            '__EVENTTARGET': 'ctl00\$ContentPlaceHolder1\$ddlrole',
            'ctl00\$ContentPlaceHolder1\$ddlrole': '1',
            'ctl00\$ContentPlaceHolder1\$btnAdd': 'Add',
          },
          referer: u,
          control: 'ctl00\$ContentPlaceHolder1\$ddlrole',
          action: 'SELECTOR',
          userConfirmed: true,
        ),
        throwsStateError,
      );
      await expectLater(
        a.inchargeRequest(Uri.parse('https://example.org/')),
        throwsStateError,
      );
    },
  );
  test(
    'facade keeps review and authentication across READ and dependent add',
    () async {
      final p = InchargePortal('dependent'), a = InchargeAuth(InchargePortal());
      a.close();
      final auth = InchargeAuth(p);
      addTearDown(auth.close);
      final service = DirectInchargeService(auth);
      expect((await service.fetch())['success'], true);
      expect(
        await service.execute(
          'add',
          roleId: '1',
          teacherId: '101',
          userConfirmed: true,
        ),
        golden('python_incharge_dependent.json'),
      );
    },
  );
}
