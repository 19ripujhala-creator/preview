import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:shaladarpan/experiments/direct_portal_auth.dart';
import 'package:shaladarpan/experiments/direct_student_attendance_service.dart';
import 'package:shaladarpan/services/portals/shaladarpan/direct/student_attendance_worker.dart';

const portalBase = 'https://rajshaladarpan.rajasthan.gov.in/SD1/';
const date = '10/10/2026';
const students = <Map<String, Object?>>[
  {'srNo': '00101', 'serialNo': 1, 'name': 'Alice', 'status': 'Present'},
  {'srNo': '102', 'serialNo': 2, 'name': 'Bob', 'status': 'Absent'},
];

class FakeAuth extends DirectPortalAuth {
  FakeAuth(this.portal);
  final FakePortal portal;
  @override
  bool get isVerified => true;
  @override
  String get verifiedNode => 'SD1';
  @override
  Future<void> observeAttendanceUrl(Uri url) async {}
  @override
  Future<AttendanceHttpReply> attendanceRequest(
    Uri url, {
    Map<String, Object?>? navigationFields,
    Uri? referer,
  }) => portal.request(url, fields: navigationFields, referer: referer);
  @override
  Future<AttendanceHttpReply> submitStudentAttendanceOnce(
    Uri url, {
    required Map<String, Object?> fields,
    required Uri referer,
    required bool userConfirmed,
  }) {
    if (!userConfirmed) throw StateError('Explicit confirmation is required');
    return portal.request(
      url,
      fields: fields,
      referer: referer,
      mutation: true,
    );
  }
}

String fixture(String name) =>
    File('test/direct/fixtures/$name').readAsStringSync();

class FakePortal {
  FakePortal({this.marked = false});
  bool marked;
  bool saved = false;
  bool rejectSave = false;
  bool timeoutSave = false;
  bool mismatchDate = false;
  bool sameAfterSave = false;
  bool failFirstPage = false;
  DateTime indiaToday = DateTime(2026, 10, 10);
  int saves = 0;
  int gets = 0;
  final requests = <Map<String, Object?>>[];

  String summary() =>
      fixture('worker_summary.html')
          .replaceAll('@@STATUS@@', marked ? 'Done' : 'Pending')
          .replaceAll('@@DATE@@', mismatchDate ? '09/10/2026' : date);

  String entry() => fixture(
    saved && !sameAfterSave
        ? 'worker_students_saved.html'
        : 'worker_students.html',
  );

  Future<AttendanceHttpReply> request(
    Uri url, {
    Map<String, Object?>? fields,
    Uri? referer,
    bool mutation = false,
  }) async {
    requests.add({
      'url': url.toString(),
      'fields': fields,
      'mutation': mutation,
    });
    if (mutation) {
      saves++;
      if (timeoutSave) throw TimeoutException('simulated save timeout');
      if (rejectSave)
        return (
          url: url,
          status: 500,
          html: '<title>Server Error in application</title>',
        );
      saved = true;
      marked = true;
      return (
        url: url,
        status: 200,
        html: '<html><body>Submitted</body></html>',
      );
    }
    if (fields == null) {
      gets++;
      if (failFirstPage && gets == 1) {
        return (
          url: url,
          status: 500,
          html: '<title>Object reference not set to an instance of an object.</title>',
        );
      }
      if (url.path.endsWith('Home_New.aspx')) {
        return (
          url: url,
          status: 200,
          html: '<a href="StudentdailyAttendanceStatus_Web_NewVersion.aspx">Attendance</a>',
        );
      }
      return (url: url, status: 200, html: fixture('worker_page.html'));
    }
    if (fields['__READ_ONLY_ACTION'] == 'SHOW') {
      return (url: url, status: 200, html: summary());
    }
    return (url: url, status: 200, html: entry());
  }

  StudentAttendanceWorker get worker => StudentAttendanceWorker(
    request: request,
    baseUrl: () => Uri.parse(portalBase),
    indiaNow: () => indiaToday,
  );
}

Future<Map<String, dynamic>> save(
  FakePortal portal, {
  List<Map<String, Object?>> roster = students,
  bool confirmed = true,
}) => portal.worker.saveStudentAttendance(
  classId: '1',
  attendanceDate: date,
  section: '1A',
  students: roster,
  userConfirmed: confirmed,
);

void main() {
  test(
    'existing service adapter retains full worker responses and snapshots',
    () async {
      final portal = FakePortal();
      final auth = FakeAuth(portal);
      addTearDown(auth.close);
      final service = DirectStudentAttendanceService(auth);
      final response = await service.fetchStudentsResponse(
        classId: '1',
        date: date,
      );
      expect(response, jsonDecode(fixture('python_worker_read.json')));
      final snapshot = await service.fetchStudents(classId: '1', date: date);
      expect(snapshot.date, date);
      expect(snapshot.students.first['fatherName'], 'Father A');
      expect(snapshot.verified, true);
      final result = await service.save(
        classId: '1',
        date: date,
        students: students,
        userConfirmed: true,
      );
      expect(result.response, jsonDecode(fixture('python_worker_save.json')));
      expect(result.verified, true);
      expect(portal.saves, 1);
    },
  );

  test('existing diagnostic transport rejects unapproved URL and unconfirmed SAVE before HTTP', () async {
    final auth = DirectPortalAuth();
    addTearDown(auth.close);
    await expectLater(
      auth.attendanceRequest(Uri.parse('${portalBase}Home/School/Other.aspx')),
      throwsStateError,
    );
    await expectLater(
      auth.submitStudentAttendanceOnce(
        Uri.parse(
          '${portalBase}Home/School/${StudentAttendanceWorker.pageName}',
        ),
        fields: {},
        referer: Uri.parse(portalBase),
        userConfirmed: false,
      ),
      throwsStateError,
    );
  });

  test(
    'complete pending READ equals the original Python worker result',
    () async {
      final actual = await FakePortal().worker.fetchStudentAttendanceList(
        classId: '1',
        attendanceDate: date,
        section: '1A',
      );
      final expected = jsonDecode(fixture('python_worker_read.json'));
      expect(actual, expected);
      expect(actual['data_verified'], true);
      expect(actual['attendance_verified'], false);
    },
  );

  test(
    'complete summary retains Python totals, date, source and link fields',
    () async {
      final actual = await FakePortal().worker.fetchClassSummary(
        attendanceDate: date,
      );
      expect(actual, jsonDecode(fixture('python_worker_summary.json')));
    },
  );

  test(
    'new SAVE equals Python result after a fresh complete verification',
    () async {
      final portal = FakePortal();
      final result = await save(portal);
      expect(result, jsonDecode(fixture('python_worker_save.json')));
      expect(portal.saves, 1);
      expect(portal.gets, 2);
      final payload =
          portal.requests.singleWhere((r) => r['mutation'] == true)['fields']
              as Map;
      expect(payload['student1'], 'P');
      expect(payload['student2'], 'A');
      expect(payload['__VIEWSTATE'], 'ENTRY_VIEWSTATE');
      expect(payload['ctl00\$ContentPlaceHolder1\$btnsubmit'], 'Submit All');
    },
  );

  test('already marked and unchanged register never sends a SAVE', () async {
    final portal = FakePortal(marked: true);
    final result = await save(portal);
    expect(result, jsonDecode(fixture('python_worker_unchanged.json')));
    expect(portal.saves, 0);
  });

  test(
    'full roster, duplicate identity and wrong identity block SAVE',
    () async {
      for (final roster in <List<Map<String, Object?>>>[
        [students.first],
        [students.first, students.first],
        [
          students.first,
          {...students.last, 'srNo': '999'},
        ],
      ]) {
        final portal = FakePortal();
        expect((await save(portal, roster: roster))['code'], 'MATCH_MISMATCH');
        expect(portal.saves, 0);
      }
    },
  );

  test(
    'duplicate radio groups block SAVE rather than overwriting a payload',
    () {
      final soup = html.parse(
        fixture('worker_students.html')
            .replaceAll('name="student2"', 'name="student1"'),
      );
      final rows = StudentAttendanceWorker.studentRows(soup);
      expect(
        () => StudentAttendanceWorker.applyUpdates(
          rows.built,
          rows.rows,
          students,
          soup,
        ),
        throwsA(
          isA<AttendanceWorkerError>().having(
            (e) => e.code,
            'code',
            'RADIO_FAILED',
          ),
        ),
      );
    },
  );

  test(
    'form encoding preserves repeated inputs and multiple select values',
    () {
      final soup = html.parse(
        '<form><input name="same" value="one">'
        '<input name="same" value="two"><select name="multi" multiple>'
        '<option value="A" selected>A</option><option value="B" selected>B</option></select>'
        '<input name="off" type="checkbox"><input name="disabled" disabled>'
        '<input type="image" name="saveImage" id="button"></form>',
      );
      final payload = AttendanceForm.payload(
        soup.querySelector('form')!,
        soup.getElementById('button')!,
      );
      expect(payload['same'], ['one', 'two']);
      expect(payload['multi'], ['A', 'B']);
      expect(payload.containsKey('off'), false);
      expect(payload.containsKey('disabled'), false);
      expect(payload['saveImage.x'], '0');
      expect(
        AttendanceForm.encode(payload),
        contains('same=one&same=two&multi=A&multi=B'),
      );
    },
  );

  test('portal date mismatch blocks display and SAVE', () async {
    final portal = FakePortal()..mismatchDate = true;
    final read = await portal.worker.fetchStudentAttendanceList(
      classId: '1',
      attendanceDate: date,
    );
    expect(read['code'], 'DATE_MISMATCH');
    expect((await save(portal))['code'], 'DATE_MISMATCH');
    expect(portal.saves, 0);
  });

  test('session expiry and real portal error heading are retained', () async {
    final worker = StudentAttendanceWorker(
      baseUrl: () => Uri.parse(portalBase),
      request: (url, {fields, referer, mutation = false}) async => (
        url: url.resolve('../Public2/OfficeLoginNew.aspx'),
        status: 200,
        html: '<html></html>',
      ),
    );
    expect((await worker.fetchClassSummary())['code'], 'SESSION_EXPIRED');
    final broken = StudentAttendanceWorker(
      baseUrl: () => Uri.parse(portalBase),
      request: (url, {fields, referer, mutation = false}) async => (
        url: url,
        status: 500,
        html: '<title>Server Error in application</title>',
      ),
    );
    expect(
      (await broken.fetchClassSummary())['message'],
      'Server Error in application',
    );
  });

  test('source Home_New fallback recovers the attendance entry page', () async {
    final portal = FakePortal()..failFirstPage = true;
    final result = await portal.worker.fetchStudentAttendanceList(
      classId: '1',
      attendanceDate: date,
    );
    expect(result['success'], true);
    expect(portal.requests[1]['url'], endsWith('Home_New.aspx'));
    expect(portal.saves, 0);
  });

  test(
    'SAVE HTTP error and transport timeout stay uncertain without replay',
    () async {
      for (final portal in [
        FakePortal()..rejectSave = true,
        FakePortal()..timeoutSave = true,
      ]) {
        final result = await save(portal);
        expect(result['code'], 'SAVE_UNCONFIRMED');
        expect(result['submission_attempted'], true);
        expect(result['attendance_verified'], false);
        expect(portal.saves, 1);
        expect(portal.gets, 1);
      }
    },
  );

  test('fresh read with mismatching statuses does not confirm SAVE', () async {
    final portal = FakePortal()..sameAfterSave = true;
    final result = await save(
      portal,
      roster: [
        {...students.first, 'status': 'Absent'},
        {...students.last, 'status': 'Present'},
      ],
    );
    expect(result['code'], 'SAVE_UNCONFIRMED');
    expect(portal.saves, 1);
  });

  test('no explicit confirmation sends no portal requests', () async {
    final portal = FakePortal();
    expect(
      (await save(portal, confirmed: false))['submission_attempted'],
      false,
    );
    expect(portal.requests, isEmpty);
  });

  test(
    'historical marked register permits no-op but blocks corrections',
    () async {
      final portal = FakePortal(marked: true)
        ..indiaToday = DateTime(2026, 10, 11);
      expect((await save(portal))['action'], 'unchanged');
      final result = await save(
        portal,
        roster: [
          {...students.first, 'status': 'Absent'},
          students.last,
        ],
      );
      expect(result['code'], 'ALREADY_MARKED');
      expect(result['submission_attempted'], false);
      expect(portal.saves, 0);
    },
  );

  test(
    'class/section mismatch retains available choices and submits nothing',
    () async {
      final portal = FakePortal();
      final result = await portal.worker.fetchStudentAttendanceList(
        classId: '1',
        section: '1B',
        attendanceDate: date,
      );
      expect(result['code'], 'BAD_CLASS');
      expect(result['available'], [
        {'classId': '1', 'section': '1A'},
      ]);
      expect(portal.saves, 0);
    },
  );

  test('blank date uses the actual portal date and invalid calendar date is rejected', () async {
    final portal = FakePortal();
    final result = await portal.worker.fetchStudentAttendanceList(classId: '1');
    expect(result['date'], date);
    final invalid = await portal.worker.fetchStudentAttendanceList(
      classId: '1',
      attendanceDate: '31/02/2026',
    );
    expect(invalid['code'], 'BAD_DATE');
    expect(invalid['message'], 'Invalid attendance date.');
  });
}
