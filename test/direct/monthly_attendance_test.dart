import 'package:flutter_test/flutter_test.dart';
import 'package:shaladarpan/experiments/direct_monthly_attendance_service.dart';

import 'package:shaladarpan/experiments/direct_portal_auth.dart';
import 'package:shaladarpan/experiments/direct_working_days_service.dart';

import 'monthly_attendance_fixture.dart';

Future<Map<String, dynamic>> list(DirectMonthlyAttendanceService s) =>
    s.load('2026-27', '1', '1', '9');
List<Map<String, dynamic>> rows(Map<String, dynamic> r) =>
    (r['rows'] as List).cast<Map<String, dynamic>>();
Future<Map<String, dynamic>> save(
  DirectMonthlyAttendanceService s,
  Map<String, dynamic> before, {
  String value = '20',
}) => s.save('2026-27', '1', '1', '9', {monthlyId(0): value}, rows(before));
void main() {
  test('captured monthly grid maps student identities, SR and per-student working days', () async {
    final s = DirectMonthlyAttendanceService(MonthlyAttendanceFixture());
    final r = await list(s);
    expect(r['success'], true, reason: r.toString());
    expect(rows(r), hasLength(9));
    expect(rows(r).first, containsPair('working_days', 22));
    expect(rows(r).first, containsPair('id', monthlyId(0)));
    expect(rows(r).first['sr_no'], '1001');
    expect(rows(r).first['field'], monthlyField(0));
    expect((r['months'] as List).length, 12);
  });
  test('one native Save keeps hidden student identities and untouched attendance, then verifies persistence', () async {
    final f = MonthlyAttendanceFixture()..attendance[monthlyField(1)] = '17';
    final s = DirectMonthlyAttendanceService(f);
    final before = await list(s);
    final r = await save(s, before);
    expect(r['verified'], true);
    expect(r['success'], true, reason: r.toString());
    expect(f.attendanceSubmissions, hasLength(1));
    final fields = f.attendanceSubmissions.single;
    expect(fields[monthlyField(0)], '20');
    expect(fields[monthlyField(1)], '17');
    expect(
      fields['${monthlyHead}gvattendence\$ctl02\$hdnstudentprofileid'],
      '20001',
    );
    expect(
      fields[r'ctl00$ScriptManager1'],
      '${monthlyHead}UpdPanel|${monthlyHead}btnsave',
    );
    expect(fields['${monthlyHead}ddlmonth'], ['9']);
    expect(fields['__VIEWSTATE'], 'fixture-updated-state');
  });
  for (final value in ['23', '-1', '', '1.5', '001']) {
    test('invalid attendance $value cannot submit', () async {
      final f = MonthlyAttendanceFixture();
      final s = DirectMonthlyAttendanceService(f);
      final b = await list(s);
      expect((await save(s, b, value: value))['success'], false);
      expect(f.attendanceSubmissions, isEmpty);
    });
  }
  for (final change in [
    'working days',
    'roster',
    'untouched student',
    'locked',
  ]) {
    test('$change changed since review blocks entire native Save', () async {
      final f = MonthlyAttendanceFixture();
      final s = DirectMonthlyAttendanceService(f);
      final b = await list(s);
      if (change == 'working days') f.zeroDays = true;
      if (change == 'roster') f.changedRoster = true;
      if (change == 'untouched student') f.attendance[monthlyField(1)] = '15';
      if (change == 'locked') f.locked = true;
      expect((await save(s, b))['submission_attempted'], false);
      expect(f.attendanceSubmissions, isEmpty);
    });
  }
  test('uncertain Save cannot replay; explicit reload exposes state and permits review', () async {
    final f = MonthlyAttendanceFixture();
    final s = DirectMonthlyAttendanceService(f);
    final b = await list(s);
    f.ambiguous = true;
    expect((await save(s, b))['submission_attempted'], true);
    expect((await save(s, b))['success'], false);
    expect(f.attendanceSubmissions, hasLength(1));
    f.ambiguous = false;
    final fresh = await list(s);
    expect((await save(s, fresh))['verified'], true);
    expect(f.attendanceSubmissions, hasLength(2));
  });
  test('missing persistence or unhandled portal confirmation never reports success', () async {
    for (final confirmation in [false, true]) {
      final f = MonthlyAttendanceFixture()
        ..noPersist = !confirmation
        ..pendingConfirmation = confirmation;
      final s = DirectMonthlyAttendanceService(f);
      final b = await list(s);
      expect((await save(s, b))['verified'], false);
      await save(s, b);
      expect(f.attendanceSubmissions, hasLength(1));
    }
  });
  test('original popup is retained when read-back fails; another Save stays blocked', () async {
    final f = MonthlyAttendanceFixture()..popup = 'Portal original message';
    final s = DirectMonthlyAttendanceService(f);
    final b = await list(s);
    f.failAfterSave = true;
    final r = await save(s, b);
    expect(r['success'], false);
    expect(r['message'], contains('Portal original message'));
    await save(s, b);
    expect(f.attendanceSubmissions, hasLength(1));
  });
  test('same-school fresh GET renewal loads; old reviewed identity cannot authorize a Save', () async {
    final f = MonthlyAttendanceFixture()..renewOnGet = true;
    final s = DirectMonthlyAttendanceService(f);
    final b = await list(s);
    expect(b['success'], true);
    f.identity = 'different';
    expect((await save(s, b))['submission_attempted'], false);
    expect(f.attendanceSubmissions, isEmpty);
    expect((await list(s))['success'], true);
  });
  test('different-school GET cannot transfer worker ownership', () async {
    final f = MonthlyAttendanceFixture();
    final s = DirectMonthlyAttendanceService(f);
    await s.open();
    f.switchSchoolOnGet = true;
    expect((await list(s))['success'], false);
    expect(f.attendanceSubmissions, isEmpty);
  });
  test(
    'unknown selection, off-origin reply and off-origin form are rejected',
    () async {
      final f = MonthlyAttendanceFixture();
      final s = DirectMonthlyAttendanceService(f);
      expect((await s.load('2026-27', '99', '1', '9'))['success'], false);
      f.badDestination = true;
      expect((await s.open())['success'], false);
      f.badDestination = false;
      f.badForm = true;
      expect((await list(s))['success'], false);
      expect(f.attendanceSubmissions, isEmpty);
    },
  );
  test('stateful Show cannot adopt a new identity during its POST', () async {
    final f = MonthlyAttendanceFixture()..renewOnPost = true;
    expect((await list(DirectMonthlyAttendanceService(f)))['success'], false);
    expect(f.attendanceSubmissions, isEmpty);
  });
  test(
    'Working Days can explicitly reopen after a same-school session renewal',
    () async {
      final f = MonthlyAttendanceFixture()..renewWorkingGet = true;
      final s = DirectWorkingDaysService(f);
      expect((await s.open())['success'], true);
      f.identity = 'next-session';
      expect((await s.load('2026-27'))['success'], true);
      f.owner = 'different-school';
      expect((await s.open())['success'], false);
      expect(f.submissions, isEmpty);
    },
  );
  test('mismatched session in student Show cannot authorize a Save', () async {
    final f = MonthlyAttendanceFixture()..wrongSession = true;
    expect((await list(DirectMonthlyAttendanceService(f)))['success'], false);
    expect(f.attendanceSubmissions, isEmpty);
  });
  test('monthly transport rejects foreign destinations, GET mutations and unreviewed actions before IO', () async {
    final auth = _VerifiedAuth();
    final url = Uri.https(
      'rajshaladarpan.rajasthan.gov.in',
      '/SD1/Home/School/StudentAttendence.aspx',
    );
    await expectLater(
      auth.monthlyAttendanceRequest(Uri.https('example.com', '/')),
      throwsStateError,
    );
    await expectLater(
      auth.monthlyAttendanceRequest(url, mutation: true),
      throwsStateError,
    );
    await expectLater(
      auth.monthlyAttendanceRequest(
        url,
        fields: {'__EVENTTARGET': 'logout'},
        referer: url,
      ),
      throwsStateError,
    );
    await expectLater(
      auth.monthlyAttendanceRequest(url.replace(query: 'save=true')),
      throwsStateError,
    );
    auth.close();
  });
  test('leading-zero input is submitted and verified as whole days', () async {
    final f = MonthlyAttendanceFixture();
    final s = DirectMonthlyAttendanceService(f);
    final before = await list(s);
    final result = await save(s, before, value: '01');
    expect(result['verified'], true);
    expect(f.attendanceSubmissions.single[monthlyField(0)], '1');
  });
}

class _VerifiedAuth extends DirectPortalAuth {
  @override
  bool get isVerified => true;
}
