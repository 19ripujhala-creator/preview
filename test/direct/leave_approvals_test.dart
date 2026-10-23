import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:shaladarpan/experiments/direct_portal_auth.dart';
import 'package:shaladarpan/experiments/direct_leave_approval_service.dart';
import 'package:shaladarpan/services/portals/shaladarpan/direct/leave_approvals.dart';

String fixture(String name) =>
    File('test/direct/fixtures/$name').readAsStringSync();
dynamic golden(String name) => jsonDecode(fixture(name));
const base = 'https://rajshaladarpan.rajasthan.gov.in/SD1/';
List<Map<String, dynamic>> actions() => [
  {'leave_id': '501', 'status': '1', 'remark': 'Reviewed'},
  {'leave_id': '502', 'status': '2'},
];

class LeavePortal {
  bool saved = false,
      zero = false,
      timeoutSave = false,
      redirect = false,
      foreign = false;
  String details = fixture('leave_details.html'),
      summary = fixture('leave_summary.html'),
      history = fixture('leave_history.html');
  String key = 'session-1';
  double time = 0;
  int gets = 0;
  Object? getError;
  final posts = <String>[], payloads = <Map<String, Object?>>[];
  late final worker = LeaveApprovalsWorker(
    request: request,
    baseUrl: () => Uri.parse(base),
    schoolId: () => '123456',
    sessionKey: () => key,
    clock: () => time,
  );
  Future<LeaveHttpReply> request(
    Uri url, {
    Map<String, Object?>? fields,
    Uri? referer,
    String? action,
    bool mutation = false,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    String body;
    if (fields == null) {
      gets++;
      if (getError != null) throw getError!;
      body = saved || zero ? fixture('leave_empty.html') : summary;
    } else {
      expect(referer, url);
      posts.add(action!);
      payloads.add(Map.from(fields));
      if (action == 'APPROVE') {
        expect(mutation, true);
        expect(timeout, const Duration(seconds: 30));
        saved = true;
        if (timeoutSave) throw TimeoutException('lost response');
        if (redirect)
          return (
            url: url,
            status: 302,
            html: 'Redirect',
            headers: {
              'location': [
                foreign
                    ? 'https://example.org/'
                    : '/SD1/Home/School/Staff_LeaveApproval.aspx',
              ],
            },
          );
        body = details;
      } else {
        expect(mutation, false);
        expect(timeout, const Duration(seconds: 25));
        body = action == 'HISTORY' ? history : details;
      }
    }
    return (
      url: url,
      status: 200,
      html: body,
      headers: <String, List<String>>{},
    );
  }
}

class LeaveAuth extends DirectPortalAuth {
  LeaveAuth(this.portal) : super(node: 'SD1');
  final LeavePortal portal;
  @override
  bool get isVerified => true;
  @override
  String? get authenticatedSchoolId => '123456';
  @override
  String get verifiedNode => 'SD1';
  @override
  Future<void> observeAttendanceUrl(Uri url) async {}
  @override
  Future<LeaveHttpReply> leaveApprovalRequest(
    Uri url, {
    Map<String, Object?>? fields,
    Uri? referer,
    String? action,
    bool mutation = false,
    Duration timeout = const Duration(seconds: 25),
    bool userConfirmed = false,
  }) {
    if (mutation) expect(userConfirmed, true);
    return portal.request(
      url,
      fields: fields,
      referer: referer,
      action: action,
      mutation: mutation,
      timeout: timeout,
    );
  }
}

class GuardAuth extends DirectPortalAuth {
  GuardAuth() : super(node: 'SD1');
  @override
  bool get isVerified => true;
}

void main() {
  test(
    'pending READ matches uploaded Python response and school postback',
    () async {
      final p = LeavePortal();
      expect(await p.worker.fetch(), golden('python_leave_pending.json'));
      expect(p.posts, ['SCHOOL_ENTRY']);
      expect(
        p.payloads.single['__EVENTTARGET'],
        'ctl00\$ContentPlaceHolder1\$grdSchoolList\$ctl02\$lnkSchoolName',
      );
      expect(
        p.payloads.single.keys.any((k) => k.contains('btnApprove')),
        false,
      );
    },
  );
  test('verified zero is a real summary count and needs no POST', () async {
    final p = LeavePortal()..zero = true;
    expect(await p.worker.fetch(), golden('python_leave_empty.json'));
    expect(p.posts, isEmpty);
  });
  for (final mode in ['save', 'timeout', 'mismatch']) {
    test(
      '$mode response and all payloads exactly match original Python',
      () async {
        final p = LeavePortal()..timeoutSave = mode == 'timeout';
        if (mode == 'mismatch')
          p.history = p.history.replaceAll('Processed', 'Pending');
        await p.worker.fetch();
        expect(await p.worker.submit(actions(), userConfirmed: true), {
          ...golden('python_leave_$mode.json') as Map,
          'message_source': 'app',
        });
        expect(p.payloads, golden('python_leave_${mode}_payloads.json'));
        expect(p.posts.where((a) => a == 'APPROVE').length, 1);
        final f = p.payloads.last;
        expect(f['__EVENTTARGET'], LeaveApprovalsWorker.historyTarget);
        expect(
          f.keys.any((k) => k.contains('chkBox') || k.contains('btnApprove')),
          false,
        );
      },
    );
  }
  test('no confirmation makes no requests', () async {
    final p = LeavePortal();
    expect(
      (await p.worker.submit(actions(), userConfirmed: false))['code'],
      'CONFIRMATION_REQUIRED',
    );
    expect(p.gets, 0);
  });
  test('submission requires a reviewed snapshot', () async {
    final p = LeavePortal();
    expect(
      (await p.worker.submit(actions(), userConfirmed: true))['code'],
      'STALE_FORM',
    );
    expect(p.gets, 0);
  });
  for (final kind in ['expiry', 'account', 'identity']) {
    test('$kind review changes block approval', () async {
      final p = LeavePortal();
      await p.worker.fetch();
      if (kind == 'expiry') p.time = 181;
      if (kind == 'account') p.key = 'session-2';
      if (kind == 'identity')
        p.details = p.details.replaceAll('Teacher A', 'Different Teacher');
      final res = await p.worker.submit(actions(), userConfirmed: true);
      expect(res['code'], 'STALE_FORM');
      expect(res['submission_attempted'], false);
      expect(p.posts, isNot(contains('APPROVE')));
    });
  }
  for (final kind in [
    'duplicate',
    'count',
    'school',
    'pager',
    'token',
    'controls',
  ]) {
    test('incomplete $kind never becomes a zero count', () async {
      final p = LeavePortal();
      if (kind == 'duplicate')
        p.details = p.details.replaceAll('value="502"', 'value="501"');
      if (kind == 'count')
        p.summary = p.summary.replaceAll('<td>2</td>', '<td>3</td>');
      if (kind == 'school')
        p.summary = p.summary.replaceAll('123456', '999999');
      if (kind == 'pager')
        p.details = p.details.replaceAll(
          '</table>',
          '<tr><td><a href="javascript:__doPostBack(\'grid\',\'Page\$2\')">Next</a></td></tr></table>',
        );
      if (kind == 'token')
        p.summary = p.summary.replaceAll('value="LEAVE_STATE"', 'value=""');
      if (kind == 'controls')
        p.details = p.details.replaceAll('ddlLLeaveStatus', 'otherStatus');
      final res = await p.worker.fetch();
      expect(res['success'], false);
      expect(res['pending_count'], null);
      expect(res['applications'], isEmpty);
    });
  }
  test(
    'selected-only checkbox clearing preserves unrelated pending leave',
    () async {
      final p = LeavePortal();
      await p.worker.fetch();
      final res = await p.worker.submit([actions().first], userConfirmed: true);
      expect(res['verified'], true);
      final f = p.payloads[p.posts.indexOf('APPROVE')];
      expect(f['g\$0\$chkBox'], 'on');
      expect(f.containsKey('g\$1\$chkBox'), false);
      expect(f['g\$1\$ddlLLeaveStatus'], '0');
    },
  );
  for (final kind in [
    'postback',
    'remark',
    'disabled',
    'status',
    'button',
    'destination',
  ]) {
    test('$kind action fails before commit', () async {
      final p = LeavePortal();
      await p.worker.fetch();
      if (kind == 'postback')
        p.details = p.details.replaceAll(
          '<select ',
          '<select onchange="__doPostBack(\'g\',\'\')" ',
        );
      if (kind == 'remark')
        p.details = p.details.replaceAll('txtRemark', 'otherText');
      if (kind == 'disabled')
        p.details = p.details.replaceAll(
          'type="checkbox"',
          'type="checkbox" disabled',
        );
      if (kind == 'status')
        p.details = p.details.replaceAll(
          'value="1">Approve',
          'value="1" disabled>Approve',
        );
      if (kind == 'button')
        p.details = p.details.replaceAll('btnApprove', 'otherButton');
      if (kind == 'destination')
        p.details = p.details.replaceAll(
          'action="Staff_LeaveApproval.aspx"',
          'action="https://example.org/"',
        );
      final res = await p.worker.submit(actions(), userConfirmed: true);
      expect(res['success'], false);
      expect(res['submission_attempted'], false);
      expect(p.posts, isNot(contains('APPROVE')));
    });
  }
  test('invalid action IDs and statuses cannot dispatch', () async {
    for (final bad in [
      <Map<String, dynamic>>[],
      [
        {'leave_id': 'x', 'status': '1'},
      ],
      [
        {'leave_id': '501', 'status': '0'},
      ],
      [actions().first, actions().first],
    ]) {
      final p = LeavePortal();
      expect(
        (await p.worker.submit(bad, userConfirmed: true))['code'],
        'INVALID_PAYLOAD',
      );
      expect(p.gets, 0);
    }
  });
  test(
    'same-origin redirect requires fresh history verification, never replay',
    () async {
      final p = LeavePortal()..redirect = true;
      await p.worker.fetch();
      expect(
        (await p.worker.submit(actions(), userConfirmed: true))['verified'],
        true,
      );
      expect(p.posts.where((x) => x == 'APPROVE').length, 1);
    },
  );
  test(
    'foreign redirect recovery uses only known portal and one commit',
    () async {
      final p = LeavePortal()
        ..redirect = true
        ..foreign = true;
      await p.worker.fetch();
      final res = await p.worker.submit(actions(), userConfirmed: true);
      expect(res['verified'], true);
      expect(res['refresh_required'], true);
      expect(p.posts.where((x) => x == 'APPROVE').length, 1);
    },
  );
  test(
    'timeout and unavailable history stay unconfirmed with no second approval',
    () async {
      final p = LeavePortal()
        ..timeoutSave = true
        ..history = '<html>Missing history</html>';
      await p.worker.fetch();
      final res = await p.worker.submit(actions(), userConfirmed: true);
      expect(res['code'], 'SAVE_UNCONFIRMED');
      expect(res['submission_attempted'], true);
      expect(p.posts.where((x) => x == 'APPROVE').length, 1);
      expect(
        (await p.worker.submit(actions(), userConfirmed: true))['code'],
        'STALE_FORM',
      );
    },
  );
  test('history needs active filter, stored status, complete IDs and no pagination', () {
    final source = fixture('leave_history.html');
    expect(LeaveApprovalsWorker.historyStatuses(html.parse(source)), {
      '501': 'Processed',
      '502': 'Rejected',
    });
    for (final s in [
      source.replaceAll('type="radio" checked', 'type="radio"'),
      source.replaceAll('value="502"', 'value="501"'),
      source.replaceAll('Processed', 'Unknown'),
      source.replaceAll(
        'Processed',
        '<select><option>Processed</option></select>',
      ),
      source.replaceAll(
        '</table>',
        '<tr><td><a onclick="__doPostBack(\'g\',\'Page\$2\')">Next</a></td></tr></table>',
      ),
    ]) {
      expect(
        () => LeaveApprovalsWorker.historyStatuses(html.parse(s)),
        throwsA(anything),
      );
    }
  });
  test('timeout and transport read errors retain Python error codes', () async {
    for (final entry in [
      (TimeoutException('slow'), 'PORTAL_SLOW'),
      (const SocketException('offline'), 'NETWORK_ERROR'),
    ]) {
      final p = LeavePortal()..getError = entry.$1;
      final r = await p.worker.fetch();
      expect(r['code'], entry.$2);
      expect(r['pending_count'], null);
    }
  });
  test(
    'native leave gate blocks unconfirmed writes and mutation controls in READ',
    () async {
      final auth = GuardAuth();
      addTearDown(auth.close);
      final uri = Uri.parse('${base}Home/School/Staff_LeaveApproval.aspx');
      final fields = <String, Object?>{
        '__EVENTTARGET': LeaveApprovalsWorker.historyTarget,
        'ctl00\$ContentPlaceHolder1\$btnApprove': 'Process',
      };
      for (final action in ['APPROVE', 'HISTORY']) {
        await expectLater(
          auth.leaveApprovalRequest(
            uri,
            fields: fields,
            referer: uri,
            action: action,
            mutation: action == 'APPROVE',
          ),
          throwsStateError,
        );
      }
      await expectLater(
        auth.leaveApprovalRequest(
          Uri.parse('https://example.org/Staff_LeaveApproval.aspx'),
        ),
        throwsStateError,
      );
    },
  );
  test(
    'facade reuses one authenticated worker and review across READ and submit',
    () async {
      final p = LeavePortal();
      final active = LeaveAuth(p);
      addTearDown(active.close);
      final service = DirectLeaveApprovalService(active);
      expect(await service.fetch(), golden('python_leave_pending.json'));
      expect(await service.submit(actions(), userConfirmed: true), {
        ...golden('python_leave_save.json') as Map,
        'message_source': 'app',
      });
    },
  );
}
