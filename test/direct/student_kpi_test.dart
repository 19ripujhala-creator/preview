import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../lib/services/portals/shaladarpan/direct/student_kpi.dart';
import '../../lib/services/portals/shaladarpan/direct/student_attendance_worker.dart';
import '../../lib/experiments/direct_portal_auth.dart';
import '../../lib/experiments/direct_student_attendance_service.dart';
import '../../lib/experiments/direct_student_kpi_service.dart';

String fixture(String file) =>
    File('test/direct/fixtures/$file').readAsStringSync();
Map<String, dynamic> golden(String file) =>
    Map<String, dynamic>.from(jsonDecode(fixture(file)));
final fixed = DateTime.utc(2026, 10, 10, 18, 40);

class KpiPortal {
  KpiPortal([this.mode = 'normal']);
  final String mode;
  int gets = 0;
  final posts = <Map<String, Object?>>[];
  String key = 'session', school = '123456';
  Uri base = Uri.parse('https://rajshaladarpan.rajasthan.gov.in/SD1/');
  String? override;
  StudentKpiWorker worker() => StudentKpiWorker(
    request: send,
    baseUrl: () => base,
    schoolId: () => school,
    sessionKey: () => key,
    clock: () => fixed,
  );
  Future<AttendanceHttpReply> send(
    Uri url, {
    Map<String, Object?>? fields,
    Uri? referer,
    String? showControl,
    String? showControlId,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    if (fields == null) {
      gets++;
      expect(timeout, const Duration(seconds: 25));
      if (mode == 'timeout') throw TimeoutException('offline');
      if (mode == 'network') throw const SocketException('offline');
    } else {
      posts.add(fields);
      expect(timeout, const Duration(seconds: 30));
      expect(referer, url);
      expect(showControl, 'arbitraryShowName');
      expect(showControlId, 'ContentPlaceHolder1_btn_Show');
    }
    return (
      url: url,
      status: mode == 'redirect' && fields != null ? 302 : 200,
      html: override ?? fixture('kpi_$mode.html'),
    );
  }
}

class KpiAuth extends DirectPortalAuth {
  KpiAuth(this.portal) : super(node: 'SD1');
  final KpiPortal portal;
  bool verified = true;
  @override
  bool get isVerified => verified;
  @override
  String get verifiedNode => 'SD1';
  @override
  String? get authenticatedSchoolId => portal.school;
  @override
  String get schoolSessionIdentity => verified ? portal.key : '';
  @override
  Future<AttendanceHttpReply> studentKpiRequest(
    Uri url, {
    Map<String, Object?>? fields,
    Uri? referer,
    String? showControl,
    String? showControlId,
    Duration timeout = const Duration(seconds: 25),
  }) => portal.send(
    url,
    fields: fields,
    referer: referer,
    showControl: showControl,
    showControlId: showControlId,
    timeout: timeout,
  );
}

class KpiAttendance extends DirectStudentAttendanceService {
  KpiAttendance(super.auth);
  int reads = 0;
  Map<String, dynamic> summary = {
    'success': true,
    'classes': [
      {'total': 16, 'present': 10, 'done': false, 'status': 'pending'},
    ],
  };
  void Function()? onRead;
  @override
  Future<Map<String, dynamic>> fetchClassSummaryResponse({String? date, bool background = false}) async {
    reads++;
    expect(date, matches(RegExp(r'^\d{2}/\d{2}/\d{4}$')));
    onRead?.call();
    return summary;
  }
}

class KpiGateAuth extends DirectPortalAuth {
  @override
  bool get isVerified => true;
}

void main() {
  test('dashboard waits outside attendance lock until all foreground owners release', () async {
    final auth = KpiGateAuth();
    final attendance = KpiAttendance(auth);
    final kpi = DirectStudentKpiService(auth, attendance);
    final a = attendance.acquireForeground(), b = attendance.acquireForeground();
    var completed = false;
    final pending = kpi.fetchDashboard().then((r) { completed = true; return r; });
    await Future<void>.delayed(Duration.zero);
    expect(completed, false); expect(attendance.reads, 0);
    a(); a(); expect(attendance.foregroundActive, true);
    b(); await pending; expect(completed, true);
    expect(attendance.foregroundActive, false);
  });

  for (final mode in [
    'normal',
    'image',
    'app',
    'both',
    'comma',
    'zero',
    'unicode',
    'no_footer',
    'invalid',
    'over',
    'mismatch',
    'duplicate',
    'missing',
    'pager',
    'no_grid',
    'tokens',
    'no_show',
    'timeout',
    'network',
    'redirect',
  ]) {
    test('complete Python response and native payload parity: $mode', () async {
      final portal = KpiPortal(mode);
      expect(await portal.worker().fetch(), golden('python_kpi_$mode.json'));
      final payload = File(
        'test/direct/fixtures/python_kpi_${mode}_payload.json',
      );
      if (payload.existsSync())
        expect(portal.posts.single, jsonDecode(payload.readAsStringSync()));
      else
        expect(portal.posts, isEmpty);
      expect(portal.gets, 1);
    });
  }
  for (final counts in [(16, 10), (8, 1), (8, 3), (0, 0)]) {
    test(
      'dashboard original rounding and pending status ${counts.$1}/${counts.$2}',
      () {
        final g = golden('python_kpi_dashboard_${counts.$1}_${counts.$2}.json');
        final summary = Map<String, dynamic>.from(
          g['payload']['class_summary'],
        );
        expect(StudentKpiWorker.dashboard(summary, now: fixed), g);
        expect(summary['classes'][0]['done'], false);
      },
    );
  }
  test('dashboard errors remain errors instead of synthetic zero counts', () {
    final e = {
      'success': false,
      'code': 'SESSION_EXPIRED',
      'message': 'School portal session expired.',
    };
    expect(StudentKpiWorker.dashboard(e), same(e));
    expect(
      StudentKpiWorker.dashboard({'success': true, 'classes': []})['code'],
      'INVALID_RESULT',
    );
  });
  test('cookie identity change blocks Show before postback', () async {
    final p = KpiPortal();
    final w = StudentKpiWorker(
      baseUrl: () => p.base,
      schoolId: () => p.school,
      sessionKey: () => p.key,
      request:
          (
            url, {
            fields,
            referer,
            showControl,
            showControlId,
            timeout = const Duration(seconds: 25),
          }) async {
            final reply = await p.send(
              url,
              fields: fields,
              referer: referer,
              showControl: showControl,
              showControlId: showControlId,
              timeout: timeout,
            );
            p.key = 'rotated';
            return reply;
          },
    );
    expect((await w.fetch())['code'], 'ACCOUNT_CHANGED');
    expect(p.posts, isEmpty);
  });
  test('external form action rejected before sending tokens', () async {
    final p = KpiPortal()
      ..override = fixture('kpi_normal.html').replaceFirst(
        'action="StudentdailyAttendanceStatus_Web_NewVersion.aspx"',
        'action="https://example.com/stolen"',
      );
    expect(
      (await p.worker().fetch())['message'],
      'Unexpected attendance form destination.',
    );
    expect(p.posts, isEmpty);
  });
  test('duplicate/disabled Show button rejected without request', () async {
    for (final replacement in [
      '<input id="second_btn_Show"><input',
      '<input disabled',
    ]) {
      final p = KpiPortal()
        ..override = fixture(
          'kpi_normal.html',
        ).replaceFirst('<input type="submit"', replacement + ' type="submit"');
      expect((await p.worker().fetch())['code'], 'PAGE_NOT_READY');
      expect(p.posts, isEmpty);
    }
  });
  test(
    'native validation preserves portal heading and classifies session expiry',
    () async {
      final p = KpiPortal()
        ..override =
            '<h2>Portal original error</h2><p>Server Error in application</p>';
      expect((await p.worker().fetch())['message'], 'Portal original error');
      p.override =
          '<input id="bodyContent_txtUName"><input id="bodyContent_txtUPswd">';
      expect((await p.worker().fetch())['code'], 'SESSION_EXPIRED');
      expect(p.posts, isEmpty);
    },
  );
  test('invalid base or missing identity cannot access portal', () async {
    final p = KpiPortal()..base = Uri.parse('https://example.com/SD1/');
    expect((await p.worker().fetch())['code'], 'PAGE_NOT_READY');
    expect(p.gets, 0);
    p.base = Uri.parse('https://rajshaladarpan.rajasthan.gov.in/SD1/');
    p.key = '';
    expect((await p.worker().fetch())['code'], 'ACCOUNT_CHANGED');
    expect(p.gets, 0);
  });
  test('direct transport blocks unauthorized destination and mutation before networking', () async {
    final auth = DirectPortalAuth();
    final u = Uri.parse(
      'https://example.com/SD1/Home/School/StudentdailyAttendanceStatus_Web_NewVersion.aspx',
    );
    await expectLater(auth.studentKpiRequest(u), throwsStateError);
    auth.close();
  });
  test(
    'KPI facade shares authenticated transport and performs one GET/Show',
    () async {
      final p = KpiPortal(), auth = KpiAuth(KpiPortal());
      final a = KpiAuth(p), attendance = KpiAttendance(a);
      final result = await DirectStudentKpiService(a, attendance).fetch();
      expect(result['students'], '16');
      expect(p.gets, 1);
      expect(p.posts.length, 1);
      expect(attendance.reads, 0);
      a.close();
      auth.close();
    },
  );
  test('dashboard facade reuses one summary and preserves pending submission state', () async {
    final p = KpiPortal(), a = KpiAuth(KpiPortal());
    final attendance = KpiAttendance(a),
        service = DirectStudentKpiService(a, attendance);
    final result = await service.fetchDashboard();
    expect(result['success'], true);
    expect(result['payload']['percentage'], '62%');
    expect(result['payload']['class_summary'], same(attendance.summary));
    expect(attendance.reads, 1);
    expect(p.gets, 0);
    expect(a.portal.posts, isEmpty);
    a.close();
  });
  test('dashboard facade rejects account/session change after READ', () async {
    final a = KpiAuth(KpiPortal()),
        attendance = KpiAttendance(KpiAuth(KpiPortal()));
    final actual = KpiAttendance(a)
      ..onRead = () {
        a.portal.key = 'new-session';
      };
    expect(
      (await DirectStudentKpiService(a, actual).fetchDashboard())['code'],
      'ACCOUNT_CHANGED',
    );
    expect(actual.reads, 1);
    a.close();
    attendance.auth.close();
  });
  test(
    'expired direct KPI facade cannot fetch or generate zero metrics',
    () async {
      final a = KpiAuth(KpiPortal())..verified = false;
      final service = DirectStudentKpiService(a, KpiAttendance(a));
      expect((await service.fetchDashboard())['code'], 'SESSION_EXPIRED');
      expect((await service.fetch())['success'], false);
      expect(a.portal.gets, 0);
      a.close();
    },
  );
  test(
    'verified native transport blocks Save and unreviewed Show before network',
    () async {
      final a = KpiGateAuth();
      final u = Uri.parse(
        'https://rajshaladarpan.rajasthan.gov.in/SD1/Home/School/StudentdailyAttendanceStatus_Web_NewVersion.aspx',
      );
      await expectLater(
        a.studentKpiRequest(
          u,
          fields: {'btnSave': 'Save'},
          referer: u,
          showControl: 'btnSave',
          showControlId: 'ContentPlaceHolder1_btn_Show',
        ),
        throwsStateError,
      );
      await expectLater(
        a.studentKpiRequest(
          u,
          fields: {'some': 'Show'},
          referer: u,
          showControl: 'some',
          showControlId: 'ContentPlaceHolder1_btnSave',
        ),
        throwsStateError,
      );
      a.close();
    },
  );
}
