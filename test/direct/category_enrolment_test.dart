import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../lib/services/portals/shaladarpan/direct/category_enrolment_worker.dart';
import '../../lib/services/portals/shaladarpan/direct/student_attendance_worker.dart';
import '../../lib/experiments/direct_category_enrolment_service.dart';
import '../../lib/experiments/direct_portal_auth.dart';

String enrolFixture(String name) =>
    File('test/direct/fixtures/$name').readAsStringSync();
Map<String, dynamic> enrolGolden(String mode) => Map<String, dynamic>.from(
  jsonDecode(enrolFixture('python_enrolment_$mode.json')),
);

class EnrolmentPortal {
  EnrolmentPortal([this.mode = 'normal']);
  final String mode;
  String school = '123456';
  int gets = 0;
  final payloads = <Map<String, Object?>>[];
  String? override;
  Uri base = Uri.parse('https://rajshaladarpan.rajasthan.gov.in/SD1/');
  CategoryEnrolmentWorker worker() => CategoryEnrolmentWorker(
    request: send,
    baseUrl: () => base,
    schoolId: () => school,
  );
  Future<AttendanceHttpReply> send(
    Uri url, {
    Map<String, Object?>? fields,
    Uri? referer,
    String? sessionControl,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    expect(timeout, const Duration(seconds: 30));
    if (fields == null) {
      gets++;
      if (mode == 'timeout') throw TimeoutException('offline');
      if (mode == 'network') throw const SocketException('offline');
    } else {
      payloads.add(Map.from(fields));
      expect(sessionControl, 'actualSessionField');
      expect(fields['__EVENTTARGET'], sessionControl);
      expect(referer, url);
    }
    var source = override ?? enrolFixture('enrolment_$mode.html');
    if (fields != null && mode != 'post_wrong')
      source = source
          .replaceAll('value="2026-27" selected', 'value="2026-27"')
          .replaceAll('value="2025-26"', 'value="2025-26" selected');
    return (
      url: mode == 'login' ? base.resolve('OfficeLogin.aspx') : url,
      status: mode.startsWith('http') ? int.parse(mode.substring(4)) : 200,
      html: source,
    );
  }
}

class EnrolmentAuth extends DirectPortalAuth {
  EnrolmentAuth(this.portal);
  final EnrolmentPortal portal;
  bool verified = true;
  @override
  bool get isVerified => verified;
  @override
  String? get authenticatedSchoolId => portal.school;
  @override
  String get verifiedNode => 'SD1';
  @override
  Future<AttendanceHttpReply> categoryEnrolmentRequest(
    Uri url, {
    Map<String, Object?>? fields,
    Uri? referer,
    String? sessionControl,
    Duration timeout = const Duration(seconds: 30),
  }) => portal.send(
    url,
    fields: fields,
    referer: referer,
    sessionControl: sessionControl,
    timeout: timeout,
  );
}

class EnrolmentGateAuth extends DirectPortalAuth {
  @override
  bool get isVerified => true;
}

void main() {
  for (final mode in [
    'normal',
    'duplicate',
    'unknown',
    'empty',
    'trio',
    'category',
    'minority',
    'footer',
    'missing',
    'school',
    'session_missing',
    'unicode',
    'comma',
    'nested',
    'http401',
    'http403',
    'http302',
    'http500',
    'login',
    'timeout',
    'network',
    'postback',
    'post_wrong',
    'state',
    'disabled_select',
    'disabled_option',
    'action',
    'invalid_session',
    'invalid_school',
  ]) {
    test('complete original Python response/payload parity: $mode', () async {
      final p = EnrolmentPortal(mode);
      final session =
          [
            'postback',
            'post_wrong',
            'state',
            'disabled_select',
            'disabled_option',
            'action',
          ].contains(mode)
          ? '2025-26'
          : mode == 'invalid_session'
          ? '2026-2027'
          : null;
      final r = await p.worker().fetch(
        requestedSchoolId: mode == 'invalid_school' ? '000000' : null,
        session: session,
      );
      expect(r, enrolGolden(mode));
      final payload = File(
        'test/direct/fixtures/python_enrolment_${mode}_payload.json',
      );
      if (payload.existsSync())
        expect(p.payloads.single, jsonDecode(payload.readAsStringSync()));
      else
        expect(p.payloads, isEmpty);
    });
  }
  test('all four groups and seven categories preserve source totals and school name', () {
    final r = CategoryEnrolmentWorker.parse(
      enrolFixture('enrolment_normal.html'),
      '123456',
    );
    expect(r['school_name'], 'GOVT SCHOOL (ANNEX)');
    expect(r['groups'].keys, [
      'pre_primary',
      'primary',
      'upper_primary',
      'secondary',
    ]);
    expect(r['totals']['total'], {'boys': 30, 'girls': 30, 'total': 60});
    expect(r['groups']['pre_primary']['total']['total'], 30);
  });
  test('source form state requires ViewState without inventing EventValidation requirement', () async {
    final p = EnrolmentPortal('postback')
      ..override = enrolFixture('enrolment_normal.html')
          .replaceAll('<input name="__EVENTVALIDATION" value="VALID">', '');
    final r = await p.worker().fetch(session: '2025-26');
    expect(r['success'], true);
    expect(p.payloads.single.containsKey('__EVENTVALIDATION'), false);
  });
  test('same selected session does not make a redundant postback', () async {
    final p = EnrolmentPortal();
    expect((await p.worker().fetch(session: '2026-27'))['success'], true);
    expect(p.gets, 1);
    expect(p.payloads, isEmpty);
  });
  test(
    'active school changes during read cannot return another school data',
    () async {
      final p = EnrolmentPortal();
      final w = CategoryEnrolmentWorker(
        baseUrl: () => p.base,
        schoolId: () => p.school,
        request:
            (
              url, {
              fields,
              referer,
              sessionControl,
              timeout = const Duration(seconds: 30),
            }) async {
              final reply = await p.send(
                url,
                fields: fields,
                referer: referer,
                sessionControl: sessionControl,
                timeout: timeout,
              );
              p.school = '999999';
              return reply;
            },
      );
      expect((await w.fetch())['code'], 'ACCOUNT_CHANGED');
      expect(p.payloads, isEmpty);
    },
  );
  test(
    'report base and wrong native destination fail before portal request',
    () async {
      final p = EnrolmentPortal()..base = Uri.parse('https://example.com/SD1/');
      expect((await p.worker().fetch())['code'], 'ENROLMENT_REPORT_INCOMPLETE');
      expect(p.gets, 0);
    },
  );
  test(
    'facade uses shared native transport and does not start authentication',
    () async {
      final p = EnrolmentPortal('postback'),
          a = EnrolmentAuth(EnrolmentPortal('postback'));
      final actual = EnrolmentAuth(p);
      expect(
        await DirectCategoryEnrolmentService(actual).fetch(session: '2025-26'),
        enrolGolden('postback'),
      );
      expect(p.gets, 1);
      expect(p.payloads.length, 1);
      actual.close();
      a.close();
    },
  );
  test(
    'expired direct login cannot fetch cached or synthetic report',
    () async {
      final a = EnrolmentAuth(EnrolmentPortal())..verified = false;
      expect(
        (await DirectCategoryEnrolmentService(a).fetch())['code'],
        'SESSION_EXPIRED',
      );
      expect(a.portal.gets, 0);
      a.close();
    },
  );
  test('native report guard blocks save, incorrect event target and external destination', () async {
    final a = EnrolmentGateAuth();
    final u = Uri.parse(
      'https://rajshaladarpan.rajasthan.gov.in/SD1/Home/School/GenderWiseSchoolStudentReport.aspx',
    );
    await expectLater(
      a.categoryEnrolmentRequest(
        u,
        fields: {
          '__EVENTTARGET': 'session',
          'session': '2025-26',
          'btnSave': 'Save',
        },
        sessionControl: 'session',
        referer: u,
      ),
      throwsStateError,
    );
    await expectLater(
      a.categoryEnrolmentRequest(
        u,
        fields: {'__EVENTTARGET': 'wrong', 'session': '2025-26'},
        sessionControl: 'session',
        referer: u,
      ),
      throwsStateError,
    );
    await expectLater(
      a.categoryEnrolmentRequest(Uri.parse('https://example.com/report')),
      throwsStateError,
    );
    a.close();
  });
  test('school identity compares original portal ID, without normalizing another spelling', () async {
    final p = EnrolmentPortal()
      ..override = enrolFixture('enrolment_normal.html')
          .replaceAll('(123456)', '(१२३४५६)');
    expect((await p.worker().fetch())['code'], 'ENROLMENT_REPORT_INCOMPLETE');
    expect(p.payloads, isEmpty);
  });
}
