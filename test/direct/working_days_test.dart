import 'package:flutter_test/flutter_test.dart';
import 'package:shaladarpan/experiments/direct_working_days_service.dart';
import 'package:shaladarpan/experiments/direct_portal_auth.dart';

import 'working_days_fixture.dart';

void main() {
  test('captured Show exposes all classes, twelve months and native December validation', () async {
    final s = DirectWorkingDaysService(WorkingDaysFixture());
    final open = await s.open();
    expect(open['session'], '');
    final result = await s.load('2026-27');
    expect(result['success'], true);
    final rows = result['rows'] as List;
    expect(rows.length, 5);
    expect((rows.first['cells'] as Map).keys.toList(), [
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
    ]);
    expect(rows.first['cells']['Dec']['max'], 28);
    expect(
      rows.first['cells']['Dec']['validation_message'],
      'Day limit Exceeded,for class 1(Dec)',
    );
  });
  test('single-month save preserves fresh other-month values and exact portal success', () async {
    final f = WorkingDaysFixture();
    final s = DirectWorkingDaysService(f);
    await s.load('2026-27');
    f.values[fieldName('Oct')] = '11';
    final result = await s.save('2026-27', 'Sep', {'1': '22'}, {'1': '0'});
    expect(result['success'], true);
    expect(result['verified'], true);
    expect(result['message'], 'Success : Data has been added successfully.');
    expect(f.submissions, hasLength(1));
    final sent = f.submissions.single;
    expect(sent[fieldName('Oct')], '11');
    expect(sent[fieldName('Sep')], '22');
    expect(sent['${workingHead}btn_SubmitAll'], 'Submit');
    expect(sent.containsKey('${workingHead}btnShow'), false);
    expect(
      sent[r'ctl00$ScriptManager1'],
      '${workingHead}UpdPanel|${workingHead}btn_SubmitAll',
    );
  });
  test('changed target value is rejected before any Submit', () async {
    final f = WorkingDaysFixture();
    final s = DirectWorkingDaysService(f);
    await s.load('2026-27');
    f.values[fieldName('Sep')] = '21';
    final r = await s.save('2026-27', 'Sep', {'1': '22'}, {'1': '0'});
    expect(r['success'], false);
    expect(r['submission_attempted'], false);
    expect(f.submissions, isEmpty);
  });
  test('locked field is rejected before Submit', () async {
    final f = WorkingDaysFixture()..locked = true;
    final s = DirectWorkingDaysService(f);
    await s.load('2026-27');
    expect(
      (await s.save('2026-27', 'Oct', {'1': '20'}, {'1': '0'}))['success'],
      false,
    );
    expect(f.submissions, isEmpty);
  });
  test(
    'native December maximum is enforced with its original message',
    () async {
      final f = WorkingDaysFixture();
      final s = DirectWorkingDaysService(f);
      await s.load('2026-27');
      final r = await s.save('2026-27', 'Dec', {'1': '29'}, {'1': '0'});
      expect(r['message'], 'Day limit Exceeded,for class 1(Dec)');
      expect(f.submissions, isEmpty);
    },
  );
  test(
    'uncertain Submit cannot automatically or explicitly replay without reload',
    () async {
      final f = WorkingDaysFixture()..ambiguous = true;
      final s = DirectWorkingDaysService(f);
      await s.load('2026-27');
      final a = await s.save('2026-27', 'Sep', {'1': '22'}, {'1': '0'});
      expect(a['submission_attempted'], true);
      await s.save('2026-27', 'Sep', {'1': '22'}, {'1': '0'});
      expect(f.submissions, hasLength(1));
    },
  );
  test('success message survives failed verification without claiming verified data', () async {
    final f = WorkingDaysFixture()..failAfterSave = true;
    final s = DirectWorkingDaysService(f);
    await s.load('2026-27');
    final r = await s.save('2026-27', 'Sep', {'1': '22'}, {'1': '0'});
    expect(r['success'], true);
    expect(r['verified'], false);
    expect(r['message'], 'Success : Data has been added successfully.');
  });
  test('session change cannot reuse a previous school form', () async {
    final f = WorkingDaysFixture();
    final s = DirectWorkingDaysService(f);
    await s.load('2026-27');
    f.identity = 'new-session';
    expect(
      (await s.save('2026-27', 'Sep', {'1': '22'}, {'1': '0'}))['success'],
      false,
    );
    expect(f.submissions, isEmpty);
  });
  test('mismatched session in Show is rejected', () async {
    final f = WorkingDaysFixture()..wrongSession = true;
    final s = DirectWorkingDaysService(f);
    expect((await s.load('2026-27'))['success'], false);
    expect(f.submissions, isEmpty);
  });
  test('unknown month and class cannot send Submit', () async {
    final f = WorkingDaysFixture();
    final s = DirectWorkingDaysService(f);
    await s.load('2026-27');
    expect(
      (await s.save('2026-27', 'Bad', {'1': '22'}, {'1': '0'}))['success'],
      false,
    );
    expect(
      (await s.save('2026-27', 'Sep', {'99': '22'}, {'99': '0'}))['success'],
      false,
    );
    expect(f.submissions, isEmpty);
  });
  test('native transport rejects foreign paths and unreviewed postbacks before network access', () async {
    final auth = _VerifiedAuth();
    await expectLater(
      auth.workingDaysRequest(
        Uri.https(
          'example.com',
          '/SD1/Home/School/RMSA_MonthlySessionsEntry.aspx',
        ),
      ),
      throwsStateError,
    );
    final url = Uri.https(
      'rajshaladarpan.rajasthan.gov.in',
      '/SD1/Home/School/RMSA_MonthlySessionsEntry.aspx',
    );
    await expectLater(
      auth.workingDaysRequest(
        url,
        fields: {'__EVENTTARGET': 'logout'},
        referer: url,
      ),
      throwsStateError,
    );
    await expectLater(
      auth.workingDaysRequest(url, mutation: true),
      throwsStateError,
    );
    auth.close();
  });
}

class _VerifiedAuth extends DirectPortalAuth {
  @override
  bool get isVerified => true;
}
