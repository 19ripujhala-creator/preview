import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shaladarpan/services/core/secure_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:shaladarpan/experiments/direct_school_session.dart';
import 'package:shaladarpan/services/portals/shaladarpan/student_service.dart';
import 'package:shaladarpan/services/portals/shaladarpan/direct/student_attendance_worker.dart';

import 'student_worker_test.dart' show FakePortal, FakeAuth, date;
import 'attendance_form_reuse_test.dart' show FormPortal;
import 'school_report_test.dart' show ReportPortal, report;

class HeaderPortal extends FakePortal {
  HeaderPortal(this.header);
  final String header;
  @override
  String entry() => super.entry().replaceAll('>SRNO<', '>$header<');
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
  for (final header in ['SR No.', 'SR NO', 'S.R. No.', 'Scholar No.']) {
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
