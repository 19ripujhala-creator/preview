import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shaladarpan/services/core/secure_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:shaladarpan/experiments/direct_school_session.dart';
import 'package:shaladarpan/services/portals/shaladarpan/student_service.dart';
import 'package:shaladarpan/services/portals/shaladarpan/direct/student_attendance_worker.dart';

import 'student_worker_test.dart' show FakePortal, FakeAuth, date, students;
import 'attendance_form_reuse_test.dart' show FormPortal;
import 'school_report_test.dart' show ReportPortal, report;

class HeaderPortal extends FakePortal {
  HeaderPortal(this.header);
  final String header;
  @override
  String entry() => super.entry().replaceAll('>SRNO<', '>$header<');
}

class InternalClassCodePortal extends FakePortal {
  @override
  String summary() => super
      .summary()
      .replaceAll('value="1"', 'value="101"')
      .replaceAll('>1A<', '>1 (A)<');
}

class SplitSectionLetterPortal extends FakePortal {
  @override
  String summary() => super
      .summary()
      .replaceAll('value="1"', 'value="10"')
      .replaceAll('>1A<', '>B<');
  @override
  String entry() => super.entry().replaceFirst(
    '</form>',
    '<span id="ContentPlaceHolder1_lblentrySection">10 (B)</span></form>',
  );
}

class ZeroFirstClassPortal extends FormPortal {
  @override
  String summary() {
    final doc = html.parse(super.summary());
    final grid = doc.getElementById('ContentPlaceHolder1_grd_Student')!;
    final row = grid.querySelector('tr')!;
    final extra = html
        .parse(
          '<table>${row.outerHtml.replaceAll('_0', '_1').replaceAll('ctl02', 'ctl03')}</table>',
        )
        .querySelector('tr')!;
    extra.querySelector('input')!.attributes['value'] = '2';
    extra.querySelector('a')!.text = '2A';
    row
            .querySelector(
              '[id="ContentPlaceHolder1_grd_Student_lbl_TotStudent_0"]',
            )!
            .text =
        '0';
    row.parent!.nodes.insert(row.parent!.nodes.indexOf(row) + 1, extra);
    return doc.outerHtml;
  }
}

class StaleClassEntryPortal extends FormPortal {
  bool rejectFirstClassEntry = true;
  @override
  Future<AttendanceHttpReply> request(
    Uri url, {
    Map<String, Object?>? fields,
    Uri? referer,
    bool mutation = false,
  }) async {
    if (rejectFirstClassEntry &&
        fields?['__READ_ONLY_ACTION'] == 'CLASS_ENTRY') {
      rejectFirstClassEntry = false;
      requests.add({
        'url': url.toString(),
        'fields': fields,
        'mutation': mutation,
      });
      return (
        url: url,
        status: 500,
        html: '<title>Validation of viewstate MAC failed</title>',
      );
    }
    return super.request(
      url,
      fields: fields,
      referer: referer,
      mutation: mutation,
    );
  }
}

class MarkedDuringEntryRecoveryPortal extends StaleClassEntryPortal {
  @override
  Future<AttendanceHttpReply> request(
    Uri url, {
    Map<String, Object?>? fields,
    Uri? referer,
    bool mutation = false,
  }) {
    if (rejectFirstClassEntry &&
        fields?['__READ_ONLY_ACTION'] == 'CLASS_ENTRY') {
      marked = true;
    }
    return super.request(
      url,
      fields: fields,
      referer: referer,
      mutation: mutation,
    );
  }
}

class UnselectedPendingPortal extends FakePortal {
  @override
  String entry() => super
      .entry()
      .replaceAll('value="P" checked', 'value="P"')
      .replaceAll('value="A" checked', 'value="A"');
}

class Auth extends FakeAuth {
  Auth(super.portal);
  @override
  String get authenticatedSchoolId => '123';
  @override
  String get schoolSessionIdentity => 'cause-fixture';
}

class WrongDatePortal extends ReportPortal {
  @override
  String entry() => super.entry().replaceFirst(
    '</form>',
    '<span id="ContentPlaceHolder1_lbldateofAtt">09/10/2026</span></form>',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    DirectSchoolSession.reset();
    StudentService.directAttendanceEnabled = false;
    SecureStorageService.invalidateSchoolIdentity();
    SharedPreferences.setMockInitialValues({});
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'read') {
        return jsonEncode({'shala_id': '123', 'shala_pass': 'fixture'});
      }
      return null;
    });
  });
  tearDown(() {
    DirectSchoolSession.reset();
    StudentService.directAttendanceEnabled = false;
    SecureStorageService.invalidateSchoolIdentity();
    messenger.setMockMethodCallHandler(channel, null);
  });
  for (final header in [
    'SR.No.',
    'SR No.',
    'SR NO',
    'S.R. No.',
    'Scholar No.',
    'S.R.',
    'SR Number',
    'प्रवेशांक',
    'एस.आर.',
    'स्कॉलर',
  ]) {
    test(
      'scholar column $header retains SR identity and verification',
      () async {
        final p = HeaderPortal(header);
        final parsed = StudentAttendanceWorker.studentRows(
          html.parse(p.entry()),
        );
        expect(parsed.built['columnsMapped'], true);
        expect((parsed.built['students'] as List).first['srNo'], '00101');
        expect((parsed.built['students'] as List).first['serialNo'], 1);
        final result = await p.worker.fetchStudentAttendanceList(
          classId: '1',
          attendanceDate: date,
        );
        expect(result['data_verified'], true, reason: '$result');
      },
    );
  }
  test('service preserves column mapping cause instead of class/date generic message', () async {
    final p = HeaderPortal('Student identifier');
    DirectSchoolSession.attach(Auth(p), '123');
    StudentService.directAttendanceEnabled = true;
    final result = await StudentService.fetchAttendance(
      classId: '1',
      date: date,
    );
    expect(result['success'], false);
    expect(result['code'], 'INVALID_ATTENDANCE_READ');
    expect(result['message'], contains('Column headers not fully recognised'));
  });
  test('service accepts verified read when section carries class number and hdn_ClassID is internal code', () async {
    final p = InternalClassCodePortal();
    DirectSchoolSession.attach(Auth(p), '123');
    StudentService.directAttendanceEnabled = true;
    final result = await StudentService.fetchAttendance(
      classId: '1A',
      date: date,
    );
    expect(result['success'], true, reason: '$result');
    expect(result['data_verified'], true);
  });
  test('worker and service match split classId + letter-only section when requested as 10B', () async {
    final p = SplitSectionLetterPortal();
    DirectSchoolSession.attach(Auth(p), '123');
    StudentService.directAttendanceEnabled = true;
    final result = await StudentService.fetchAttendance(
      classId: '10B',
      date: date,
      section: '10B',
    );
    expect(result['success'], true, reason: '$result');
    expect(result['data_verified'], true);
  });
  test('zero-student class retains unconsumed summary form for immediate next class read', () async {
    final p = ZeroFirstClassPortal();
    final w = StudentAttendanceWorker(
      request: p.request,
      baseUrl: () => Uri.parse('https://rajshaladarpan.rajasthan.gov.in/SD1/'),
      sessionIdentity: () => 'fixture-session',
    );
    final empty = await w.fetchStudentAttendanceList(
      classId: '1',
      attendanceDate: date,
    );
    expect(empty['success'], true);
    expect(empty['total'], 0);
    final afterEmpty = p.requests.length;
    final second = await w.fetchStudentAttendanceList(
      classId: '2',
      attendanceDate: date,
    );
    expect(second['success'], true);
    expect(p.requests.length - afterEmpty, 1);
    expect(
      (p.requests[afterEmpty]['fields'] as Map)['__READ_ONLY_ACTION'],
      'CLASS_ENTRY',
    );
  });
  test('stale ViewState on CLASS_ENTRY after unconsumed summary recovers with one fresh read', () async {
    final p = StaleClassEntryPortal();
    final w = StudentAttendanceWorker(
      request: p.request,
      baseUrl: () => Uri.parse('https://rajshaladarpan.rajasthan.gov.in/SD1/'),
      sessionIdentity: () => 'fixture-session',
    );
    expect((await w.fetchClassSummary(attendanceDate: date))['success'], true);
    final getsBefore = p.gets;
    final result = await w.fetchStudentAttendanceList(
      classId: '1',
      attendanceDate: date,
    );
    expect(result['success'], true, reason: '$result');
    expect(p.gets, getsBefore + 1);
    expect(p.saves, 0);
  });
  test(
    'Entry recovery returns the refreshed marked summary and flags',
    () async {
      final p = MarkedDuringEntryRecoveryPortal();
      final w = StudentAttendanceWorker(
        request: p.request,
        baseUrl: () =>
            Uri.parse('https://rajshaladarpan.rajasthan.gov.in/SD1/'),
        sessionIdentity: () => 'fixture-session',
        indiaNow: () => DateTime(2026, 10, 10),
      );
      final initial = await w.fetchClassSummary(attendanceDate: date);
      expect((initial['classes'] as List).first['done'], false);
      final result = await w.fetchStudentAttendanceList(
        classId: '1',
        attendanceDate: date,
      );
      expect(result['success'], true, reason: '$result');
      expect(result['data_verified'], true);
      expect(result['is_already_marked'], true);
      expect(result['attendance_verified'], true);
      expect((result['summary'] as Map)['status'], 'Done');
      expect(w.lastSummarySnapshot!.classes.first['done'], true);
      expect(p.saves, 0);
    },
  );
  test(
    'obsolete read stops before Entry after fresh-summary recovery',
    () async {
      final p = MarkedDuringEntryRecoveryPortal();
      final w = StudentAttendanceWorker(
        request: p.request,
        baseUrl: () =>
            Uri.parse('https://rajshaladarpan.rajasthan.gov.in/SD1/'),
        sessionIdentity: () => 'fixture-session',
      );
      await w.fetchClassSummary(attendanceDate: date);
      final result = await w.fetchStudentAttendanceList(
        classId: '1',
        attendanceDate: date,
        shouldContinue: () => p.rejectFirstClassEntry,
      );
      expect(result['code'], 'STALE_ATTENDANCE_READ');
      expect(
        p.requests
            .where(
              (r) =>
                  (r['fields'] as Map?)?['__READ_ONLY_ACTION'] == 'CLASS_ENTRY',
            )
            .length,
        1,
      );
      expect(p.saves, 0);
    },
  );
  test('hold reconciliation on pending roster with unselected statuses reaches manual review instead of RECHECK_FAILED', () async {
    final p = UnselectedPendingPortal();
    DirectSchoolSession.attach(Auth(p), '123');
    StudentService.directAttendanceEnabled = true;
    final prefs = await SharedPreferences.getInstance();
    const key = 'student_submission_hold/123/$date/1a';
    await prefs.setString(
      key,
      jsonEncode({'created_at': 1, 'expected': students}),
    );
    final checkOnly = await StudentService.checkPreviousSubmission(
      classId: '1A',
      date: date,
      section: '1A',
    );
    expect(checkOnly['code'], 'REVIEW_REQUIRED', reason: '$checkOnly');
    expect(checkOnly['manual_retry_allowed'], true);
    expect(prefs.containsKey(key), true);

    final released = await StudentService.checkPreviousSubmission(
      classId: '1A',
      date: date,
      section: '1A',
      acknowledgeManualRetry: true,
    );
    expect(released['success'], true, reason: '$released');
    expect(released['resolved'], 'manual_review');
    expect(prefs.containsKey(key), false);
    expect(p.saves, 0);
  });
  test(
    'report does not repeat a deterministic wrong-date response three times',
    () async {
      final p = WrongDatePortal();
      final result = await report(p).fetchSchoolReport(attendanceDate: date);
      expect(result['success'], false);
      expect(result['code'], 'DATE_MISMATCH');
      expect(p.sectionEntries, 1);
      expect(result['message'], contains('different attendance date'));
    },
  );
  test('stale ViewState in AJAX Back recovers with one fresh READ', () async {
    final p = BackErrorPortal('Validation of viewstate MAC failed');
    final w = StudentAttendanceWorker(
      request: p.request,
      baseUrl: () => Uri.parse('https://rajshaladarpan.rajasthan.gov.in/SD1/'),
      sessionIdentity: () => 'fixture-session',
    );
    expect(
      (await w.fetchStudentAttendanceList(
        classId: '1',
        attendanceDate: date,
      ))['success'],
      true,
    );
    final gets = p.gets;
    final second = await w.fetchStudentAttendanceList(
      classId: '1',
      attendanceDate: date,
    );
    expect(second['success'], true, reason: '$second');
    expect(p.gets, gets + 1);
    expect(p.saves, 0);
  });
  test(
    'unrelated AJAX business rejection is retained without fresh READ replay',
    () async {
      final p = BackErrorPortal('Attendance access denied');
      final w = StudentAttendanceWorker(
        request: p.request,
        baseUrl: () =>
            Uri.parse('https://rajshaladarpan.rajasthan.gov.in/SD1/'),
        sessionIdentity: () => 'fixture-session',
      );
      expect(
        (await w.fetchStudentAttendanceList(
          classId: '1',
          attendanceDate: date,
        ))['success'],
        true,
      );
      final gets = p.gets;
      final second = await w.fetchStudentAttendanceList(
        classId: '1',
        attendanceDate: date,
      );
      expect(second['success'], false);
      expect(second['portal_message'], 'Attendance access denied');
      expect(p.gets, gets);
      expect(p.saves, 0);
    },
  );
  test(
    'report keeps original portal business message and does not replay it',
    () async {
      final p = RejectingPortal();
      final r = await report(p).fetchSchoolReport(attendanceDate: date);
      expect(r['success'], false);
      expect(r['message'], 'portal native rejection');
      expect(r['portal_message'], 'portal native rejection');
      expect(r['message_source'], 'portal');
      expect(p.sectionEntries, 1);
    },
  );
}

class RejectingPortal extends ReportPortal {
  @override
  Future<AttendanceHttpReply> request(
    Uri url, {
    Map<String, Object?>? fields,
    Uri? referer,
    bool mutation = false,
  }) async {
    if (fields?['__READ_ONLY_ACTION'] == 'CLASS_ENTRY') {
      sectionEntries++;
      const message = 'portal native rejection';
      return (
        url: url,
        status: 200,
        html: '1|#||4|${message.length}|error|500|$message|',
      );
    }
    return super.request(
      url,
      fields: fields,
      referer: referer,
      mutation: mutation,
    );
  }
}

class BackErrorPortal extends FormPortal {
  BackErrorPortal(this.message) {
    disabledDate = true;
  }
  final String message;
  bool rejected = false;
  @override
  Future<AttendanceHttpReply> request(
    Uri url, {
    Map<String, Object?>? fields,
    Uri? referer,
    bool mutation = false,
  }) async {
    if (!rejected && fields?['__READ_ONLY_ACTION'] == 'BACK') {
      rejected = true;
      return (
        url: url,
        status: 200,
        html: '1|#||4|${message.length}|error|500|$message|',
      );
    }
    return super.request(
      url,
      fields: fields,
      referer: referer,
      mutation: mutation,
    );
  }
}
