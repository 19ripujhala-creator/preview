import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shaladarpan/services/portals/shaladarpan/leave_approval_service.dart';
import 'package:shaladarpan/services/portals/shaladarpan/direct/leave_approvals.dart';

import 'staff_attendance_batch_support.dart';

import 'package:shaladarpan/services/portals/shaladarpan/student_service.dart';

import 'leave_approvals_test.dart' show LeavePortal, actions;

Map<String, dynamic> leaveBatchDocument() => {
  'success': true,
  'pending_count': 2,
  'applications': [
    {
      'leave_id': '501',
      'name': 'Employee One',
      'leave_type': 'CL',
      'from_date': '23/10/2026',
      'to_date': '23/10/2026',
      'days': '1',
      'reason': 'Personal',
      'status': 'Pending',
    },
    {
      'leave_id': '502',
      'name': 'Employee Two',
      'leave_type': 'CL',
      'from_date': '23/10/2026',
      'to_date': '24/10/2026',
      'days': '2',
      'reason': 'Personal',
      'status': 'Pending',
    },
  ],
};
Map<String, dynamic> leaveBatchSuccess() => {
  'success': true,
  'verified': true,
  'submission_attempted': true,
  'verification_source': 'all_applications',
  'verified_statuses': {'501': 'Processed'},
  'message_source': 'portal',
  'portal_message': 'Original leave action notice.',
  'message': 'Original leave action notice.',
};
void main() {
  late AttendanceFixture f;
  setUp(() async {
    f = AttendanceFixture();
    await f.setup();
    f.respond = (r) async => attendanceResponse(
      r.url.path.endsWith('/action')
          ? leaveBatchSuccess()
          : {'success': true, 'data': leaveBatchDocument()},
    );
  });
  tearDown(() async {
    LeaveApprovalService.clock = null;
    await f.close();
  });
  Future<Map<String, dynamic>> read() =>
      LeaveApprovalService.fetchLeaveApprovals();
  Future<Map<String, dynamic>> save() =>
      LeaveApprovalService.submitLeaveAction(leaveId: '501', status: '1');
  test(
    'native verified action preserves exact notice and explicit history proof',
    () async => f.run(() async {
      expect((await read())['success'], true);
      final r = await save();
      expect(r['success'], true);
      expect(r['portal_message'], 'Original leave action notice.');
      expect(f.requests.length, 2);
    }),
  );
  for (final flaw in ['duplicate', 'blank']) {
    test(
      'invalid $flaw leave IDs cannot become a verified pending list',
      () async => f.run(() async {
        final d = leaveBatchDocument();
        d['applications'][1]['leave_id'] = flaw == 'duplicate' ? '501' : '   ';
        f.respond = (_) async =>
            attendanceResponse({'success': true, 'data': d});
        expect((await read())['success'], false);
      }),
    );
  }
  for (final flaw in [
    'missing proof',
    'wrong status',
    'missing ID',
    'extra ID',
  ]) {
    test(
      'success flags with $flaw cannot approve UI records',
      () async => f.run(() async {
        await read();
        final result = leaveBatchSuccess();
        if (flaw == 'missing proof') {
          result.remove('verified');
          result.remove('verified_statuses');
        }
        if (flaw == 'wrong status')
          result['verified_statuses'] = {'501': 'Rejected'};
        if (flaw == 'missing ID') result['verified_statuses'] = {};
        if (flaw == 'extra ID')
          result['verified_statuses'] = {
            '501': 'Processed',
            '999': 'Processed',
          };
        f.respond = (_) async => attendanceResponse(result);
        final r = await save();
        expect(r['success'], false);
        expect(r['verified'], false);
        expect(r['submission_attempted'], true);
        expect(r['portal_message'], 'Original leave action notice.');
        expect(r['verification_message'], isNotEmpty);
      }),
    );
  }
  test(
    'changed account cannot dispatch a review from the previous school',
    () async => f.run(() async {
      await read();
      f.credentials['shala_id'] = '654321';
      final r = await save();
      expect(r['success'], false);
      expect(r['code'], 'ACCOUNT_CHANGED');
      expect(f.requests.length, 1);
    }),
  );
  test(
    'unreviewed ID is rejected before any action dispatch',
    () async => f.run(() async {
      await read();
      final r = await LeaveApprovalService.submitLeaveAction(
        leaveId: '999',
        status: '1',
      );
      expect(r['success'], false);
      expect(f.requests.length, 1);
    }),
  );
  test(
    'invalid explicit action is rejected before dispatch',
    () async => f.run(() async {
      await read();
      final r = await LeaveApprovalService.submitLeaveAction(
        leaveId: '501',
        status: '0',
      );
      expect(r['success'], false);
      expect(f.requests.length, 1);
    }),
  );
  test(
    'returned snapshots and notifier values cannot mutate a later confirmed snapshot',
    () async => f.run(() async {
      final first = await read();
      first['data']['applications'][0]['name'] = 'Changed by caller';
      final one = LeaveApprovalService.confirmedSnapshot('123456')!;
      expect(one['data']['applications'][0]['name'], 'Employee One');
      one['data']['applications'][0]['name'] = 'Changed again';
      LeaveApprovalService
              .liveStatus
              .value!['data']['applications'][0]['name'] =
          'Changed by notifier consumer';
      expect(
        LeaveApprovalService.confirmedSnapshot(
          '123456',
        )!['data']['applications'][0]['name'],
        'Employee One',
      );
      expect(f.requests.length, 1);
    }),
  );
  test(
    'read begun before an action cannot publish old pending count after it settles',
    () async => f.run(() async {
      await read();
      final entered = Completer<void>(), reply = Completer<http.Response>();
      f.respond = (request) async {
        if (request.url.path.endsWith('/fetch')) {
          entered.complete();
          return reply.future;
        }
        return attendanceResponse(leaveBatchSuccess());
      };
      final reading = read();
      await entered.future;
      expect((await save())['success'], true);
      reply.complete(
        attendanceResponse({'success': true, 'data': leaveBatchDocument()}),
      );
      expect((await reading)['success'], false);
      expect(LeaveApprovalService.confirmedSnapshot('123456'), isNull);
    }),
  );
  test(
    'read during action cannot publish after the action settles',
    () async => f.run(() async {
      await read();
      final sent = Completer<void>(), seen = Completer<void>();
      final actionReply = Completer<http.Response>(),
          readReply = Completer<http.Response>();
      f.respond = (request) async {
        if (request.url.path.endsWith('/action')) {
          sent.complete();
          return actionReply.future;
        }
        seen.complete();
        return readReply.future;
      };
      final saving = save();
      await sent.future;
      final reading = read();
      await seen.future;
      actionReply.complete(attendanceResponse(leaveBatchSuccess()));
      expect((await saving)['success'], true);
      readReply.complete(
        attendanceResponse({'success': true, 'data': leaveBatchDocument()}),
      );
      expect((await reading)['success'], false);
      expect(LeaveApprovalService.confirmedSnapshot('123456'), isNull);
    }),
  );
  test(
    'account changes after dispatch retain original message but cannot claim current success',
    () async => f.run(() async {
      await read();
      f.respond = (_) async {
        f.credentials['shala_id'] = '654321';
        return attendanceResponse(leaveBatchSuccess());
      };
      final r = await save();
      expect(r['success'], false);
      expect(r['submission_attempted'], true);
      expect(r['portal_message'], 'Original leave action notice.');
    }),
  );
  test(
    'duplicate tap creates a single owned action request',
    () async => f.run(() async {
      await read();
      final entered = Completer<void>(), reply = Completer<http.Response>();
      f.respond = (_) async {
        entered.complete();
        return reply.future;
      };
      final first = save();
      await entered.future;
      expect((await save())['success'], false);
      reply.complete(attendanceResponse(leaveBatchSuccess()));
      expect((await first)['success'], true);
      expect(f.requests.length, 2);
    }),
  );
  test(
    'failed fresh public read disarms an earlier review',
    () async => f.run(() async {
      await read();
      f.respond = (_) async =>
          attendanceResponse({'success': false, 'message': 'Unavailable'});
      expect((await read())['success'], false);
      final count = f.requests.length;
      expect((await save())['success'], false);
      expect(f.requests.length, count);
    }),
  );
  test(
    'action input is frozen before credential and HTTP awaits',
    () async => f.run(() async {
      await read();
      final input = [
        {'leave_id': '501', 'status': '1', 'remark': 'Reviewed'},
      ];
      final saving = LeaveApprovalService.submitBatchLeaveActions(input);
      input.first['leave_id'] = '502';
      input.first['status'] = '2';
      input.clear();
      expect((await saving)['success'], true);
      final posted = jsonDecode(f.requests.last.body)['actions'] as List;
      expect(posted.single, {
        'leave_id': '501',
        'status': '1',
        'remark': 'Reviewed',
      });
    }),
  );
  test(
    'duplicate action IDs never dispatch a POST',
    () async => f.run(() async {
      await read();
      final r = await LeaveApprovalService.submitBatchLeaveActions([
        {'leave_id': '501', 'status': '1'},
        {'leave_id': '501', 'status': '2'},
      ]);
      expect(r['success'], false);
      expect(f.requests.length, 1);
    }),
  );
  test(
    'direct mode change disarms the backend review',
    () async => f.run(() async {
      await read();
      StudentService.directAttendanceEnabled = true;
      expect((await save())['success'], false);
      expect(f.requests.length, 1);
      StudentService.directAttendanceEnabled = false;
    }),
  );
  test(
    'India midnight rejects an in-flight previous-day read',
    () async => f.run(() async {
      var now = DateTime.utc(2026, 10, 23, 18, 29, 59);
      LeaveApprovalService.clock = () => now;
      final entered = Completer<void>(), reply = Completer<http.Response>();
      f.respond = (_) async {
        entered.complete();
        return reply.future;
      };
      final pending = read();
      await entered.future;
      now = now.add(const Duration(seconds: 2));
      reply.complete(
        attendanceResponse({'success': true, 'data': leaveBatchDocument()}),
      );
      expect((await pending)['success'], false);
      expect(LeaveApprovalService.confirmedSnapshot('123456'), isNull);
      expect(await LeaveApprovalService.getCachedLeaves(), isNull);
    }),
  );
  test(
    'clock regression cannot reuse a future-dated review',
    () async => f.run(() async {
      var now = DateTime.utc(2026, 10, 23, 10);
      LeaveApprovalService.clock = () => now;
      await read();
      now = now.subtract(const Duration(seconds: 1));
      expect(LeaveApprovalService.confirmedSnapshot('123456'), isNull);
      expect((await save())['success'], false);
      expect(f.requests.length, 1);
    }),
  );
  test(
    'expired review cannot dispatch an action',
    () async => f.run(() async {
      var now = DateTime.utc(2026, 10, 23, 10);
      LeaveApprovalService.clock = () => now;
      await read();
      now = now.add(const Duration(seconds: 181));
      expect((await save())['success'], false);
      expect(f.requests.length, 1);
    }),
  );
  test(
    'partial native results retain observed statuses without claiming all approved',
    () async => f.run(() async {
      await read();
      f.respond = (_) async => attendanceResponse({
        ...leaveBatchSuccess(),
        'success': false,
        'verified': false,
        'code': 'SAVE_UNCONFIRMED',
        'observed_statuses': {'501': 'Processed', '502': 'Pending'},
        'verification_message': 'The second leave is still pending.',
      });
      final r = await LeaveApprovalService.submitBatchLeaveActions([
        {'leave_id': '501', 'status': '1'},
        {'leave_id': '502', 'status': '2'},
      ]);
      expect(r['success'], false);
      expect(r['observed_statuses'], {'501': 'Processed', '502': 'Pending'});
      expect(r['portal_message'], 'Original leave action notice.');
      expect(r['verification_message'], 'The second leave is still pending.');
    }),
  );
  test(
    'deduplicated readers receive independent copies and one request',
    () async => f.run(() async {
      final entered = Completer<void>(), reply = Completer<http.Response>();
      f.respond = (_) async {
        entered.complete();
        return reply.future;
      };
      final one = read();
      await entered.future;
      final two = read();
      await Future<void>.delayed(Duration.zero);
      reply.complete(
        attendanceResponse({'success': true, 'data': leaveBatchDocument()}),
      );
      final a = await one, b = await two;
      a['data']['applications'][0]['name'] = 'Caller edit';
      expect(b['data']['applications'][0]['name'], 'Employee One');
      expect(f.requests.length, 1);
    }),
  );
  test(
    'failed fresh worker read invalidates its previous action review',
    () async {
      final p = LeavePortal();
      await p.worker.fetch();
      p.getError = const SocketException('offline');
      expect((await p.worker.fetch())['success'], false);
      p.getError = null;
      final r = await p.worker.submit(actions(), userConfirmed: true);
      expect(r['success'], false);
      expect(r['code'], 'STALE_FORM');
      expect(p.posts.where((s) => s == 'APPROVE'), isEmpty);
    },
  );
  test(
    'ASP.NET mutation error heading survives an unavailable history readback',
    () async {
      final p = LeavePortal();
      final w = LeaveApprovalsWorker(
        baseUrl: () =>
            Uri.parse('https://rajshaladarpan.rajasthan.gov.in/SD1/'),
        schoolId: () => '123456',
        sessionKey: () => p.key,
        request:
            (
              url, {
              fields,
              referer,
              action,
              mutation = false,
              timeout = const Duration(seconds: 25),
            }) async {
              final r = await p.request(
                url,
                fields: fields,
                referer: referer,
                action: action,
                mutation: mutation,
                timeout: timeout,
              );
              if (mutation) {
                p.getError = const SocketException('unavailable readback');
                return (
                  url: r.url,
                  status: 500,
                  html: '<h2>Exact portal error heading.</h2><p>Server Error in /SD1 Application.</p>',
                  headers: r.headers,
                );
              }
              return r;
            },
      );
      await w.fetch();
      final r = await w.submit(actions(), userConfirmed: true);
      expect(r['success'], false);
      expect(r['portal_message'], 'Exact portal error heading.');
      expect(r['verification_message'], isNotEmpty);
      expect(p.posts.where((s) => s == 'APPROVE').length, 1);
    },
  );
}
