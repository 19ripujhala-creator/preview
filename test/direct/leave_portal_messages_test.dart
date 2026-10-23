import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shaladarpan/experiments/direct_leave_approval_service.dart';
import 'package:shaladarpan/services/portals/shaladarpan/direct/leave_result_messages.dart';
import 'package:shaladarpan/services/portals/shaladarpan/direct/leave_approvals.dart';

import 'leave_approvals_test.dart' show LeavePortal, LeaveAuth, actions;

LeaveApprovalsWorker responseWorker(
  LeavePortal p,
  String markup, {
  bool failReadback = false,
}) => LeaveApprovalsWorker(
  request:
      (
        url, {
        fields,
        referer,
        action,
        mutation = false,
        timeout = const Duration(seconds: 25),
      }) async {
        final reply = await p.request(
          url,
          fields: fields,
          referer: referer,
          action: action,
          mutation: mutation,
          timeout: timeout,
        );
        if (!mutation) return reply;
        if (failReadback)
          p.getError = const SocketException('offline after save');
        return (
          url: reply.url,
          status: reply.status,
          html: reply.html.replaceFirst('</body>', '$markup</body>'),
          headers: reply.headers,
        );
      },
  baseUrl: () => Uri.parse('https://rajshaladarpan.rajasthan.gov.in/SD1/'),
  schoolId: () => '123456',
  sessionKey: () => p.key,
  clock: () => p.time,
);

class MessageAuth extends LeaveAuth {
  MessageAuth(super.portal);
  @override
  Future<LeaveHttpReply> leaveApprovalRequest(
    Uri url, {
    Map<String, Object?>? fields,
    Uri? referer,
    String? action,
    bool mutation = false,
    Duration timeout = const Duration(seconds: 25),
    bool userConfirmed = false,
  }) async {
    final reply = await super.leaveApprovalRequest(
      url,
      fields: fields,
      referer: referer,
      action: action,
      mutation: mutation,
      timeout: timeout,
      userConfirmed: userConfirmed,
    );
    return mutation
        ? (
            url: reply.url,
            status: reply.status,
            html: reply.html.replaceFirst(
              '</body>',
              '<div id="msgDiv">Native action completed.</div></body>',
            ),
            headers: reply.headers,
          )
        : reply;
  }
}

void main() {
  const native = 'अवकाश आवेदन अस्वीकृत किया गया।';
  LeavePortal portalWithMessage(String markup) {
    final p = LeavePortal();
    final response = p.details.replaceFirst('</body>', '$markup</body>');
    p.details = response;
    return p;
  }

  test(
    'verified native alert reaches display without custom success wording',
    () async {
      final p = LeavePortal();
      await p.worker.fetch();
      // Read and save bodies in this fake share details, so add response-only
      // text after the last preflight via its own request adapter below.
      final worker = responseWorker(p, '<script>alert("$native");</script>');
      await worker.fetch();
      final result = await worker.submit([actions()[1]], userConfirmed: true);
      expect(result['verified'], true);
      expect(result['message'], native);
      expect(result['portal_message'], native);
      expect(result['message_source'], 'portal');
      expect(LeaveResultMessages.display(result), native);
      expect(p.posts.where((x) => x == 'APPROVE'), hasLength(1));
    },
  );

  test(
    'portal validation is retained beside separate unconfirmed warning',
    () async {
      const message = 'कृपया अस्वीकृति का कारण दर्ज करें।';
      final p = LeavePortal();
      p.history = p.history.replaceAll('Rejected', 'Pending');
      final worker = responseWorker(p, '<div id="msgDiv">$message</div>');
      await worker.fetch();
      final result = await worker.submit([actions()[1]], userConfirmed: true);
      expect(result['success'], false);
      expect(result['verified'], false);
      expect(result['code'], 'SAVE_UNCONFIRMED');
      expect(result['message'], message);
      expect(result['verification_message'], isNotEmpty);
      expect(
        LeaveResultMessages.display(result),
        startsWith('$message\n\nApp verification:'),
      );
      expect(p.posts.where((x) => x == 'APPROVE'), hasLength(1));
    },
  );

  test(
    'native message survives a subsequent history transport failure',
    () async {
      final p = LeavePortal();
      final worker = responseWorker(
        p,
        '<div class="alert-success">$native</div>',
        failReadback: true,
      );
      await worker.fetch();
      final result = await worker.submit([actions()[1]], userConfirmed: true);
      expect(result['code'], 'SAVE_UNCONFIRMED');
      expect(result['message'], native);
      expect(result['message_source'], 'portal');
      expect(
        LeaveResultMessages.display(result),
        contains('App verification:'),
      );
      expect(p.posts.where((x) => x == 'APPROVE'), hasLength(1));
    },
  );

  test(
    'stale page message does not masquerade as a fresh action response',
    () async {
      final p = portalWithMessage(
        '<script>alert("Old unrelated message");</script>',
      );
      await p.worker.fetch();
      final result = await p.worker.submit([actions()[1]], userConfirmed: true);
      expect(result['message_source'], 'app');
      expect(result.containsKey('portal_message'), false);
      expect(LeaveResultMessages.display(result), startsWith('App:'));
      expect(
        LeaveResultMessages.display(result),
        isNot(contains('Old unrelated')),
      );
    },
  );

  test(
    'no portal text means explicitly labelled app verification message',
    () async {
      final p = LeavePortal();
      await p.worker.fetch();
      final result = await p.worker.submit([actions()[1]], userConfirmed: true);
      expect(result['verified'], true);
      expect(result['message_source'], 'app');
      expect(LeaveResultMessages.display(result), startsWith('App:'));
    },
  );

  test('local confirmation error is not presented as a portal error', () async {
    final p = LeavePortal();
    final result = await p.worker.submit([actions()[1]], userConfirmed: false);
    expect(result['submission_attempted'], false);
    expect(result['message_source'], 'app');
    expect(LeaveResultMessages.display(result), startsWith('App:'));
    expect(p.gets, 0);
  });

  test(
    'an uncertain timeout without a response cannot invent a portal message',
    () async {
      final p = LeavePortal()..timeoutSave = true;
      p.history = p.history.replaceAll('Rejected', 'Pending');
      await p.worker.fetch();
      final result = await p.worker.submit([actions()[1]], userConfirmed: true);
      expect(result['code'], 'SAVE_UNCONFIRMED');
      expect(result['message_source'], 'app');
      expect(result.containsKey('portal_message'), false);
      expect(p.posts.where((x) => x == 'APPROVE'), hasLength(1));
    },
  );

  test('native text takes priority over wrapper fallback text', () {
    final result = LeaveResultMessages.attach(
      {
        'success': false,
        'code': 'SAVE_UNCONFIRMED',
        'message': 'Session changed; verify leave state.',
      },
      [native],
    );
    expect(result['message'], native);
    expect(
      result['verification_message'],
      'Session changed; verify leave state.',
    );
    expect(
      LeaveResultMessages.display(result),
      '$native\n\nApp verification: Session changed; verify leave state.',
    );
  });

  test('portal message source from a server response is honoured', () {
    expect(
      LeaveResultMessages.display({
        'success': false,
        'message_source': 'portal',
        'message': native,
      }),
      native,
    );
    expect(
      LeaveResultMessages.display({
        'portal_message': native,
        'message': 'Generic error',
      }),
      native,
    );
  });

  test('all native messages remain ordered and repeated nodes deduplicate', () async {
    final p = LeavePortal();
    final worker = responseWorker(
      p,
      '<div id="msgDiv">$native</div><script>alert("$native");alert("Second native message");</script>',
    );
    await worker.fetch();
    final result = await worker.submit([actions()[1]], userConfirmed: true);
    expect(result['portalMessages'], [native, 'Second native message']);
    expect(result['message'], '$native\nSecond native message');
  });

  test(
    'direct service facade keeps native text and verification metadata',
    () async {
      final p = LeavePortal();
      final auth = MessageAuth(p);
      addTearDown(auth.close);
      final service = DirectLeaveApprovalService(auth);
      await service.fetch();
      final result = await service.submit([actions()[1]], userConfirmed: true);
      expect(result['verified'], true);
      expect(result['message'], 'Native action completed.');
      expect(result['message_source'], 'portal');
      expect(LeaveResultMessages.display(result), 'Native action completed.');
    },
  );

  test(
    'confirmation prompts are not treated as saved portal messages',
    () async {
      final p = LeavePortal();
      final worker = responseWorker(
        p,
        '<script>alert("Are you sure?");</script>',
      );
      await worker.fetch();
      final result = await worker.submit([actions()[1]], userConfirmed: true);
      expect(result['message_source'], 'app');
    },
  );
}
