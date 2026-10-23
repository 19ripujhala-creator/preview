import 'package:flutter_test/flutter_test.dart';

import 'leave_approvals_test.dart' show LeavePortal, actions;

String selectedAction(
  String page,
  String value, {
  bool removePlaceholder = false,
}) {
  var changed = page.replaceAll('value="0" selected', 'value="0"');
  changed = changed.replaceAll('value="$value">', 'value="$value" selected>');
  if (removePlaceholder) {
    changed = changed.replaceAll('<option value="0">Pending</option>', '');
  }
  return changed;
}

void main() {
  for (final defaultAction in ['1', '2']) {
    test(
      'fresh pending leave can be rejected with action default $defaultAction',
      () async {
        final p = LeavePortal();
        p.details = selectedAction(
          p.details,
          defaultAction,
          removePlaceholder: true,
        );
        final fetched = await p.worker.fetch();
        expect(fetched['success'], true);
        expect(
          (fetched['applications'] as List).first['status_code'],
          defaultAction,
        );
        // Fixture history for leave 502 confirms Rejected after one mutation.
        final result = await p.worker.submit([
          actions()[1],
        ], userConfirmed: true);
        expect(result['success'], true);
        expect(result['verified'], true);
        expect(result['verified_statuses'], {'502': 'Rejected'});
        expect(p.posts.where((x) => x == 'APPROVE'), hasLength(1));
        final payload = p.payloads[p.posts.indexOf('APPROVE')];
        expect(payload[r'g$1$ddlLLeaveStatus'], '2');
        expect(payload[r'g$1$chkBox'], 'on');
        expect(payload.containsKey(r'g$0$chkBox'), false);
      },
    );
  }

  test(
    'approval also uses the requested action, not the portal default',
    () async {
      final p = LeavePortal();
      p.details = selectedAction(p.details, '2', removePlaceholder: true);
      await p.worker.fetch();
      final result = await p.worker.submit([
        actions().first,
      ], userConfirmed: true);
      expect(result['verified'], true);
      expect(result['verified_statuses'], {'501': 'Processed'});
      expect(p.posts.where((x) => x == 'APPROVE'), hasLength(1));
      final payload = p.payloads[p.posts.indexOf('APPROVE')];
      expect(payload[r'g$0$ddlLLeaveStatus'], '1');
      expect(payload.containsKey(r'g$1$chkBox'), false);
    },
  );

  test('a changed action default is not a changed leave identity', () async {
    final p = LeavePortal();
    await p.worker.fetch();
    p.details = selectedAction(p.details, '1');
    final result = await p.worker.submit([actions()[1]], userConfirmed: true);
    expect(result['verified'], true);
    expect(p.posts.where((x) => x == 'APPROVE'), hasLength(1));
  });

  test('changed leave dates still block before rejection', () async {
    final p = LeavePortal();
    p.details = selectedAction(p.details, '1');
    await p.worker.fetch();
    p.details = p.details.replaceAll('10/10/2026', '11/10/2026');
    final result = await p.worker.submit([actions()[1]], userConfirmed: true);
    expect(result['code'], 'STALE_FORM');
    expect(result['submission_attempted'], false);
    expect(p.posts, isNot(contains('APPROVE')));
  });

  test('a matching count does not make All Applications a pending view', () async {
    final p = LeavePortal();
    await p.worker.fetch();
    p.details = selectedAction(p.details, '1').replaceFirst(
      'type="radio" id="ContentPlaceHolder1_rdoLeaveApplicationType_4"',
      'type="radio" checked id="ContentPlaceHolder1_rdoLeaveApplicationType_4"',
    );
    final result = await p.worker.submit([actions()[1]], userConfirmed: true);
    expect(result['success'], false);
    expect(result['submission_attempted'], false);
    expect(p.posts, isNot(contains('APPROVE')));
  });

  test('disabled rejection option still blocks before mutation', () async {
    final p = LeavePortal();
    p.details = selectedAction(p.details, '1');
    await p.worker.fetch();
    p.details = p.details.replaceAll(
      'value="2">Reject',
      'value="2" disabled>Reject',
    );
    final result = await p.worker.submit([actions()[1]], userConfirmed: true);
    expect(result['code'], 'INVALID_SELECTION');
    expect(result['submission_attempted'], false);
    expect(p.posts, isNot(contains('APPROVE')));
  });

  test(
    'wrong readback state cannot confirm rejection after action default fix',
    () async {
      final p = LeavePortal();
      p.details = selectedAction(p.details, '1');
      p.history = p.history.replaceAll('Rejected', 'Pending');
      await p.worker.fetch();
      final result = await p.worker.submit([actions()[1]], userConfirmed: true);
      expect(result['code'], 'SAVE_UNCONFIRMED');
      expect(result['submission_attempted'], true);
      expect(result['verified'], false);
      expect(p.posts.where((x) => x == 'APPROVE'), hasLength(1));
    },
  );

  test(
    'timeout rejection with verified readback is not submitted twice',
    () async {
      final p = LeavePortal()..timeoutSave = true;
      p.details = selectedAction(p.details, '2');
      await p.worker.fetch();
      final result = await p.worker.submit([actions()[1]], userConfirmed: true);
      expect(result['verified'], true);
      expect(p.posts.where((x) => x == 'APPROVE'), hasLength(1));
    },
  );

  test(
    'pending count zero or missing reviewed row still blocks rejection',
    () async {
      final p = LeavePortal();
      p.details = selectedAction(p.details, '1');
      await p.worker.fetch();
      p.zero = true;
      final result = await p.worker.submit([actions()[1]], userConfirmed: true);
      expect(result['code'], 'STALE_FORM');
      expect(result['submission_attempted'], false);
      expect(p.posts, isNot(contains('APPROVE')));
    },
  );
}
