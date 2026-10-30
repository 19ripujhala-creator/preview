import 'package:flutter_test/flutter_test.dart';
import 'package:shaladarpan/services/portals/shaladarpan/direct/student_attendance_worker.dart';

import 'student_worker_test.dart' show FakePortal, students, date;

class FormPortal extends FakePortal {
  bool saveForm = true;
  bool entryControls = true;
  bool disabledDate = false, backEnabled = true;
  int rejectBacks = 0;
  String? actualSection, actualDate;
  int entryVersion = 0;
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
    var page = super.entry();
    if (actualSection != null)
      page = page.replaceFirst(
        '</form>',
        '<span id="ContentPlaceHolder1_lblentrySection">$actualSection</span></form>',
      );
    if (actualDate != null)
      page = page.replaceFirst(
        '</form>',
        '<span id="ContentPlaceHolder1_lbldateofAtt">$actualDate</span></form>',
      );
    if (entryControls) {
      entryVersion++;
      page = page
          .replaceAll('ENTRY_VIEWSTATE', 'ENTRY_VIEWSTATE_$entryVersion')
          .replaceFirst('</form>', '''
        <input id="ContentPlaceHolder1_txtdate" name="ctl00\$ContentPlaceHolder1\$txtdate" value="$date">
        <input id="ContentPlaceHolder1_btn_Show" name="ctl00\$ContentPlaceHolder1\$btn_Show" type="submit" value="Show">
        </form>''');
    }
    if (disabledDate) {
      page = page.replaceFirst(
        'id="ContentPlaceHolder1_txtdate"',
        'disabled="disabled" id="ContentPlaceHolder1_txtdate"',
      );
      page = page.replaceFirst(
        '</form>',
        '<input type="submit" id="ContentPlaceHolder1_btnback" name="ctl00\$ContentPlaceHolder1\$btnback" value="Back" ${backEnabled ? '' : 'disabled="disabled"'}></form>',
      );
    }
    if (missingToken) page = page.replaceAll('ENTRY_EVENTVALIDATION', '');
    return changedRoster ? page.replaceFirst('00101', '99999') : page;
  }

  @override
  Future<AttendanceHttpReply> request(
    Uri url, {
    Map<String, Object?>? fields,
    Uri? referer,
    bool mutation = false,
  }) async {
    if (fields?['__READ_ONLY_ACTION'] == 'BACK') {
      requests.add({
        'url': url.toString(),
        'fields': fields,
        'mutation': mutation,
      });
      if (rejectBacks-- > 0)
        return (
          url: url,
          status: 500,
          html: '<title>Validation of viewstate MAC failed</title>',
        );
      return (url: url, status: 200, html: summary());
    }
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

class EntrySavePortal extends FormPortal {
  @override
  Future<AttendanceHttpReply> request(
    Uri url, {
    Map<String, Object?>? fields,
    Uri? referer,
    bool mutation = false,
  }) async {
    final response = await super.request(
      url,
      fields: fields,
      referer: referer,
      mutation: mutation,
    );
    if (mutation) return (url: url, status: 200, html: entry());
    return response;
  }
}

class SpacedSectionPortal extends FormPortal {
  @override String summary() => super.summary().replaceAll('>1A<', '>1 A<');
  @override String entry() {
    actualSection = '1-A';
    return super.entry();
  }
}
class DuplicateRosterPortal extends FormPortal {
  @override String entry() => super.entry().replaceAll('102', '00101');
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
  test('section spacing and separators identify the same class without changing portal labels', () async {
    final portal = SpacedSectionPortal();
    final worker = StudentAttendanceWorker(request: portal.request,
      baseUrl: () => Uri.parse('https://rajshaladarpan.rajasthan.gov.in/SD1/'),
      sessionIdentity: () => 'school/session', indiaNow: () => DateTime(2026,10,10));
    final result = await worker.fetchStudentAttendanceList(classId: '1A', attendanceDate: date, section: '1_A');
    expect(result['success'], true); expect(result['section'], '1 A');
    expect(result['data_verified'], true);
    final saved = await worker.saveStudentAttendance(classId: '1A', attendanceDate: date,
      section: '1A', students: students, userConfirmed: true);
    expect(saved['success'], true); expect(portal.saves, 1);
  });
  test('duplicate roster identities are unverified on read and cannot be submitted', () async {
    final portal = DuplicateRosterPortal();
    final worker = StudentAttendanceWorker(request: portal.request,
      baseUrl: () => Uri.parse('https://rajshaladarpan.rajasthan.gov.in/SD1/'),
      indiaNow: () => DateTime(2026,10,10));
    final result = await worker.fetchStudentAttendanceList(classId: '1', attendanceDate: date);
    expect(result['data_verified'], false);
    expect(result['warning'], contains('duplicate student identities'));
    final saved = await worker.saveStudentAttendance(classId: '1', attendanceDate: date,
      students: students, userConfirmed: true);
    expect(saved['submission_attempted'], false); expect(portal.saves, 0);
  });
  test(
    'native entry with wrong class label cannot display or save another roster',
    () async {
      portal.disabledDate = true;
      portal.actualSection = '2A';
      expect((await read())['success'], false);
      expect((await save())['submission_attempted'], false);
      expect(portal.saves, 0);
    },
  );
  test('native entry date label must match requested date even if selector looks correct', () async {
    portal.disabledDate = true;
    portal.actualDate = '09/10/2026';
    expect((await read())['code'], 'DATE_MISMATCH');
    expect((await save())['submission_attempted'], false);
    expect(portal.saves, 0);
  });
  test('Save returning disabled-date entry verifies via native Back and fresh roster', () async {
    final p = EntrySavePortal()..disabledDate = true;
    final w = StudentAttendanceWorker(
      request: p.request,
      baseUrl: () => Uri.parse('https://rajshaladarpan.rajasthan.gov.in/SD1/'),
      sessionIdentity: () => 'same',
      indiaNow: () => DateTime(2026, 10, 10),
    );
    await w.fetchStudentAttendanceList(classId: '1', attendanceDate: date);
    final n = p.requests.length;
    final result = await w.saveStudentAttendance(
      classId: '1',
      attendanceDate: date,
      section: '1A',
      students: students,
      userConfirmed: true,
    );
    expect(result['success'], true);
    expect(result['attendance_verified'], true);
    expect(p.saves, 1);
    expect(p.requests.length - n, 5);
    expect(
      p.requests
          .skip(n)
          .map(
            (r) => r['mutation'] == true
                ? 'SAVE'
                : (r['fields'] as Map)['__READ_ONLY_ACTION'],
          ),
      ['BACK', 'CLASS_ENTRY', 'SAVE', 'BACK', 'CLASS_ENTRY'],
    );
  });
  test('real disabled-date entry reuses latest native Back without extra GET or Show', () async {
    portal.disabledDate = true;
    await read();
    final n = portal.requests.length;
    final result = await read();
    expect(result['success'], true);
    final actions = portal.requests
        .skip(n)
        .map((r) => (r['fields'] as Map)['__READ_ONLY_ACTION']);
    expect(actions, ['BACK', 'CLASS_ENTRY']);
    expect(portal.gets, 1);
    final back = portal.requests[n]['fields'] as Map;
    expect(back['__VIEWSTATE'], 'ENTRY_VIEWSTATE_1');
    expect(back.containsKey(r'ctl00$ContentPlaceHolder1$txtdate'), false);
    expect(back.containsKey(r'ctl00$ContentPlaceHolder1$btnsubmit'), false);
    expect(back[r'ctl00$ContentPlaceHolder1$btnback'], 'Back');
    expect(portal.saves, 0);
  });
  test('disabled native Back keeps full fresh navigation instead of using old form', () async {
    portal.disabledDate = true;
    portal.backEnabled = false;
    await read();
    await read();
    expect(portal.gets, 2);
    expect(portal.saves, 0);
  });
  test('expired native Back form never bypasses fresh GET', () async {
    portal.disabledDate = true;
    await read();
    elapsed = const Duration(seconds: 45);
    await read();
    expect(portal.gets, 2);
  });
  test(
    'rejected native Back falls back only to fresh read and never submits',
    () async {
      portal.disabledDate = true;
      await read();
      portal.rejectBacks = 1;
      expect((await read())['success'], true);
      expect(portal.gets, 2);
      expect(portal.saves, 0);
    },
  );
  test(
    'native Back preflight still fetches fresh roster and submits only once',
    () async {
      portal.disabledDate = true;
      await read();
      final n = portal.requests.length;
      expect((await save())['success'], true);
      expect(portal.saves, 1);
      expect(
        (portal.requests[n]['fields'] as Map)['__READ_ONLY_ACTION'],
        'BACK',
      );
    },
  );
  test('native Back cannot hide a changed roster before Save', () async {
    portal.disabledDate = true;
    await read();
    portal.changedRoster = true;
    expect((await save())['submission_attempted'], false);
    expect(portal.saves, 0);
  });
  test(
    'next Show uses latest entry response ViewState, never summary state',
    () async {
      await read();
      await read();
      await read();
      expect(
        (portal.requests[3]['fields'] as Map)['__VIEWSTATE'],
        'ENTRY_VIEWSTATE_1',
      );
      expect(
        (portal.requests[5]['fields'] as Map)['__VIEWSTATE'],
        'ENTRY_VIEWSTATE_2',
      );
    },
  );
  test(
    'entry without navigation controls discards the older summary envelope',
    () async {
      portal.entryControls = false;
      await read();
      await read();
      expect(portal.gets, 2);
    },
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
    'warm SAVE consumes returned Done summary directly and reads independent post-SAVE roster',
    () async {
      await read();
      final initial = portal.requests.length;
      final result = await save();
      expect(result['success'], true);
      expect(result['attendance_verified'], true);
      expect(portal.requests.length - initial, 4);
      expect(portal.saves, 1);
      expect(
        portal.requests
            .skip(initial)
            .map(
              (r) => r['mutation'] == true
                  ? 'SAVE'
                  : (r['fields'] as Map)['__READ_ONLY_ACTION'],
            ),
        ['SHOW', 'CLASS_ENTRY', 'SAVE', 'CLASS_ENTRY'],
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
  test(
    'superseded read aborts before CLASS_ENTRY and hands unconsumed summary to next class',
    () async {
      portal.disabledDate = true;
      await read();
      final n = portal.requests.length;
      final superseded = await worker.fetchStudentAttendanceList(
        classId: '1',
        attendanceDate: date,
        section: '1A',
        shouldContinue: () => false,
      );
      expect(superseded['success'], false);
      expect(superseded['code'], 'STALE_ATTENDANCE_READ');
      expect(portal.requests.length - n, 1);
      expect(
        (portal.requests[n]['fields'] as Map)['__READ_ONLY_ACTION'],
        'BACK',
      );
      final afterBack = portal.requests.length;
      final next = await read();
      expect(next['success'], true);
      expect(portal.requests.length - afterBack, 1);
      expect(
        (portal.requests[afterBack]['fields'] as Map)['__READ_ONLY_ACTION'],
        'CLASS_ENTRY',
      );
    },
  );
  test(
    'dashboard fetchClassSummary leaves unconsumed summary so first class load skips duplicate SHOW',
    () async {
      final summary = await worker.fetchClassSummary(attendanceDate: date);
      expect(summary['success'], true);
      final afterSummary = portal.requests.length;
      final firstClass = await read();
      expect(firstClass['success'], true);
      expect(portal.requests.length - afterSummary, 1);
      expect(
        (portal.requests[afterSummary]['fields'] as Map)['__READ_ONLY_ACTION'],
        'CLASS_ENTRY',
      );
    },
  );
}
