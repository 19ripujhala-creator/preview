import 'package:flutter_test/flutter_test.dart';
import 'package:shaladarpan/services/portals/shaladarpan/direct/student_attendance_worker.dart';

import 'student_worker_test.dart' show FakePortal, students, date;

class FormPortal extends FakePortal {
  bool saveForm = true;
  bool rejectShow = false;
  int rejectShows = 0;
  bool invalidAction = false;
  bool missingToken = false;
  bool changedRoster = false;
  @override
  String summary() {
    var page = super.summary();
    if (invalidAction)
      page = page.replaceFirst(
        'action="StudentdailyAttendanceStatus_Web_NewVersion.aspx"',
        'action="https://example.invalid/submit"',
      );
    if (missingToken)
      page = page.replaceFirst(
        'name="__EVENTVALIDATION"',
        'name="missingToken"',
      );
    return page;
  }

  @override
  String entry() {
    final page = super.entry();
    return changedRoster ? page.replaceFirst('00101', '99999') : page;
  }

  @override
  Future<AttendanceHttpReply> request(
    Uri url, {
    Map<String, Object?>? fields,
    Uri? referer,
    bool mutation = false,
  }) async {
    final result = await super.request(
      url,
      fields: fields,
      referer: referer,
      mutation: mutation,
    );
    if (mutation && saveForm) return (url: url, status: 200, html: summary());
    if (fields?['__READ_ONLY_ACTION'] == 'SHOW' &&
        (rejectShow || rejectShows-- > 0))
      return (
        url: url,
        status: 500,
        html: '<title>Validation of viewstate MAC failed</title>',
      );
    return result;
  }
}

void main() {
  late FormPortal portal;
  late StudentAttendanceWorker worker;
  var identity = 'school/generation1/cookies1';
  var elapsed = Duration.zero;
  var node = 'SD1';
  setUp(() {
    portal = FormPortal();
    identity = 'school/generation1/cookies1';
    elapsed = Duration.zero;
    node = 'SD1';
    worker = StudentAttendanceWorker(
      request: portal.request,
      baseUrl: () =>
          Uri.parse('https://rajshaladarpan.rajasthan.gov.in/$node/'),
      sessionIdentity: () => identity,
      formElapsed: () => elapsed,
      indiaNow: () => DateTime(2026, 10, 10),
    );
  });
  Future<Map<String, dynamic>> read() => worker.fetchStudentAttendanceList(
    classId: '1',
    attendanceDate: date,
    section: '1A',
  );
  Future<Map<String, dynamic>> save() => worker.saveStudentAttendance(
    classId: '1',
    attendanceDate: date,
    section: '1A',
    students: students,
    userConfirmed: true,
  );
  test(
    'warm READ skips only GET and reads summary and full roster again',
    () async {
      final first = await read();
      final second = await read();
      expect(first['success'], true);
      expect(second['students'], first['students']);
      expect(portal.gets, 1);
      expect(portal.requests.length, 5);
      expect(
        portal.requests
            .skip(3)
            .map((r) => (r['fields'] as Map)['__READ_ONLY_ACTION']),
        ['SHOW', 'CLASS_ENTRY'],
      );
      expect(portal.saves, 0);
    },
  );
  test(
    'warm SAVE uses five requests and fresh independent post-SAVE roster',
    () async {
      await read();
      final initial = portal.requests.length;
      final result = await save();
      expect(result['success'], true);
      expect(result['attendance_verified'], true);
      expect(portal.requests.length - initial, 5);
      expect(portal.saves, 1);
      expect(
        portal.requests
            .skip(initial)
            .map(
              (r) => r['mutation'] == true
                  ? 'SAVE'
                  : (r['fields'] as Map)['__READ_ONLY_ACTION'],
            ),
        ['SHOW', 'CLASS_ENTRY', 'SAVE', 'SHOW', 'CLASS_ENTRY'],
      );
    },
  );
  test(
    'SAVE without a reusable response form retains full fresh verification',
    () async {
      portal.saveForm = false;
      await read();
      final initial = portal.requests.length;
      expect((await save())['success'], true);
      expect(portal.requests.length - initial, 6);
      expect(portal.saves, 1);
    },
  );
  test('session generation or cookie change forces a fresh GET', () async {
    await read();
    identity = 'school/generation2/cookies2';
    expect((await read())['success'], true);
    expect(portal.gets, 2);
  });
  test(
    'node change invalidates retained form despite identical identity',
    () async {
      await read();
      node = 'SD3';
      await read();
      expect(portal.gets, 2);
      expect((portal.requests[3]['url'] as String).contains('/SD3/'), true);
    },
  );
  test('expired form does not bypass initial page navigation', () async {
    await read();
    elapsed = const Duration(seconds: 45);
    await read();
    expect(portal.gets, 2);
  });
  test('clock regression invalidates retained form', () async {
    elapsed = const Duration(seconds: 10);
    await read();
    elapsed = Duration.zero;
    await read();
    expect(portal.gets, 2);
  });
  test('missing event validation disables cross-operation reuse', () async {
    portal.missingToken = true;
    await read();
    await read();
    expect(portal.gets, 2);
  });
  test('unexpected form action is never retained or submitted', () async {
    portal.invalidAction = true;
    expect((await read())['success'], false);
    expect((await read())['success'], false);
    expect(portal.gets, 2);
    expect(portal.saves, 0);
    expect(
      portal.requests.any((r) => '${r['url']}'.contains('example.invalid')),
      false,
    );
  });
  test(
    'persistent rejected viewstate preserves native error and never submits',
    () async {
      await read();
      portal.rejectShow = true;
      final initial = portal.requests.length;
      final result = await save();
      expect(result['success'], false);
      expect(result['submission_attempted'], false);
      expect(result['message'], 'Validation of viewstate MAC failed');
      expect(portal.requests.length - initial, 3);
      expect(portal.saves, 0);
      portal.rejectShow = false;
      await read();
      expect(portal.gets, 3);
    },
  );
  test('one rejected retained form falls back read-only and disables reuse for that session', () async {
    await read();
    portal.rejectShows = 1;
    final result = await read();
    expect(result['success'], true);
    expect(portal.gets, 2);
    expect(portal.saves, 0);
    await read();
    expect(portal.gets, 3);
    identity = 'school/generation2/cookies2';
    await read();
    expect(portal.gets, 4);
    await read();
    expect(portal.gets, 4);
  });
  test(
    'fresh roster identity change after screen READ prevents SAVE',
    () async {
      await read();
      portal.changedRoster = true;
      final result = await save();
      expect(result['success'], false);
      expect(result['submission_attempted'], false);
      expect(portal.saves, 0);
    },
  );
  test(
    'no authenticated identity retains original cold-navigation behavior',
    () async {
      identity = '';
      await read();
      await read();
      expect(portal.gets, 2);
    },
  );
}
