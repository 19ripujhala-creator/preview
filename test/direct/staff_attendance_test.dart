import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:shaladarpan/experiments/direct_portal_auth.dart';
import 'package:shaladarpan/experiments/direct_staff_attendance_service.dart';
import 'package:shaladarpan/services/portals/shaladarpan/direct/staff_attendance.dart';
import 'package:shaladarpan/services/portals/shaladarpan/direct/school_http.dart';
import 'package:shaladarpan/services/portals/shaladarpan/direct/student_attendance_worker.dart';

String fixture(String name) =>
    File('test/direct/fixtures/$name').readAsStringSync();
const base = 'https://rajshaladarpan.rajasthan.gov.in/SD1/';
DateTime morning() => DateTime.utc(2026, 10, 10, 3, 30);
List<Map<String, dynamic>> requested() => [
  {
    'staffId': '101',
    'sno': '1',
    'status_code': '2',
    'original_status': 'Present',
  },
  {'staffId': '102', 'sno': '2', 'status_code': '3', 'original_status': 'CL'},
];

class StaffPortal {
  bool schoolGrid = true, selector = false, marked = false;
  bool markedSchoolGrid = false;
  bool timeoutSave = false, failFinal = false, mismatchedConfirmation = false;
  bool malformedAck = false, unconfirmed = false, redirectSave = false;
  String? documentOverride;
  String pending = fixture('staff_pending.html');
  final posts = <String>[];
  final payloads = <Map<String, Object?>>[];
  int gets = 0;
  DateTime clock = morning();
  Future<AttendanceHttpReply> request(
    Uri url, {
    Map<String, Object?>? fields,
    Uri? referer,
    String? action,
    bool mutation = false,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    if (fields == null) {
      gets++;
      return (
        url: url,
        status: 200,
        html:
            documentOverride ??
            (markedSchoolGrid
                ? fixture('staff_school.html').replaceAll(
                    'Pending',
                    '<img src="checked.png" alt="marked">',
                  )
                : marked
                ? fixture('staff_marked.html')
                : schoolGrid
                ? fixture('staff_school.html')
                : selector
                ? fixture('staff_selector.html')
                : pending),
      );
    }
    posts.add(action!);
    payloads.add(Map.from(fields));
    if (action == 'SCHOOL_ENTRY') {
      expect(mutation, false);
      return (
        url: url,
        status: 200,
        html: markedSchoolGrid
            ? fixture('staff_marked.html')
            : selector
            ? fixture('staff_selector.html')
            : pending,
      );
    }
    expect(mutation, true);
    expect(referer, url);
    if (action == 'SELECTOR') {
      expect(fields['__EVENTTARGET'], 'g\$DDLLeave\$0');
      expect(fields['g\$DDLLeave\$0'], '2');
      final source = fixture('staff_selector.html')
          .replaceAll('value="1" selected', 'value="1"')
          .replaceAll('value="2"', 'value="2" selected');
      return (
        url: url,
        status: 200,
        html: source.replaceAll('STATE1', 'STATE2'),
      );
    }
    if (action == 'SAVE') {
      if (timeoutSave) throw TimeoutException('lost save response');
      if (redirectSave) return (url: url, status: 302, html: 'Redirect');
      expect(fields['g\$DDLLeave\$0'], '2');
      if (selector) expect(fields['__VIEWSTATE'], 'STATE2');
      var source = fixture('staff_confirmation.html');
      if (mismatchedConfirmation)
        source = source.replaceAll('>Absent<', '>Present<');
      if (malformedAck)
        source = source.replaceAll(
          'type="button"',
          'type="button" onclick="unexpected()"',
        );
      return (url: url, status: 200, html: source);
    }
    if (action == 'FINAL') {
      if (failFinal) throw TimeoutException('lost final response');
      marked = !unconfirmed;
      return (url: url, status: 200, html: fixture('staff_marked.html'));
    }
    throw StateError('Unexpected staff action');
  }

  StaffAttendanceWorker worker() => StaffAttendanceWorker(
    request: request,
    baseUrl: () => Uri.parse(base),
    schoolId: () => '123456',
    now: () => clock,
  );
}

class StaffAuth extends DirectPortalAuth {
  StaffAuth(this.portal);
  final StaffPortal portal;
  @override
  bool get isVerified => true;
  @override
  String get verifiedNode => 'SD1';
  @override
  String? get authenticatedSchoolId => '123456';
  @override
  Future<void> observeAttendanceUrl(Uri url) async {}
  @override
  Future<AttendanceHttpReply> staffAttendanceRequest(
    Uri url, {
    Map<String, Object?>? fields,
    Uri? referer,
    String? action,
    bool mutation = false,
    Duration timeout = const Duration(seconds: 25),
    bool userConfirmed = false,
  }) {
    if (mutation) expect(userConfirmed, true);
    return portal.request(
      url,
      fields: fields,
      referer: referer,
      action: action,
      mutation: mutation,
      timeout: timeout,
    );
  }
}

void main() {
  test(
    'full pending result equals execution of the uploaded Python worker',
    () async {
      final portal = StaffPortal();
      expect(
        await portal.worker().fetch(),
        jsonDecode(fixture('python_staff_pending.json')),
      );
      expect(portal.posts, ['SCHOOL_ENTRY']);
    },
  );
  test('marked plain-text rows and native milliseconds equal Python', () async {
    final portal = StaffPortal()..marked = true;
    expect(
      await portal.worker().fetch(),
      jsonDecode(fixture('python_staff_marked.json')),
    );
  });
  test('Save, inert Yes, final lock, fresh readback equal Python', () async {
    final portal = StaffPortal();
    expect(
      await portal.worker().submit(requested(), userConfirmed: true),
      jsonDecode(fixture('python_staff_save.json')),
    );
    expect(portal.posts, ['SCHOOL_ENTRY', 'SAVE', 'FINAL']);
    expect(portal.gets, 2);
  });
  test('selector postback uses returned VIEWSTATE before Save', () async {
    final portal = StaffPortal()..selector = true;
    final result = await portal.worker().submit(
      requested(),
      userConfirmed: true,
    );
    expect(result['success'], true);
    expect(portal.posts, ['SCHOOL_ENTRY', 'SELECTOR', 'SAVE', 'FINAL']);
    expect(portal.payloads[1].containsKey('_selector_only'), false);
  });
  test('already marked matching roster performs no commit', () async {
    final portal = StaffPortal()..marked = true;
    final rows = requested();
    rows[0]['status_code'] = null;
    rows[0]['original_status'] = 'Absent';
    rows[1]['status_code'] = null;
    final result = await portal.worker().submit(rows, userConfirmed: true);
    expect(result['outcome'], 'already_marked');
    expect(result['submission_attempted'], false);
    expect(portal.posts, isEmpty);
  });
  test('incomplete roster cannot save', () async {
    final portal = StaffPortal();
    final result = await portal.worker().submit([
      requested().first,
    ], userConfirmed: true);
    expect(result['code'], 'IDENTITY_MISMATCH');
    expect(portal.posts, ['SCHOOL_ENTRY']);
  });
  test('duplicate staff ID cannot save', () async {
    final portal = StaffPortal();
    final result = await portal.worker().submit([
      requested().first,
      requested().first,
    ], userConfirmed: true);
    expect(result['code'], 'IDENTITY_MISMATCH');
    expect(result['submission_attempted'], false);
  });
  test('changed serial number cannot save', () async {
    final portal = StaffPortal();
    final rows = requested()..first['sno'] = '9';
    expect(
      (await portal.worker().submit(rows, userConfirmed: true))['code'],
      'IDENTITY_MISMATCH',
    );
  });
  test('portal locked approved leave must remain exact', () async {
    final portal = StaffPortal();
    final rows = requested()..last['status_code'] = '1';
    expect(
      (await portal.worker().submit(rows, userConfirmed: true))['code'],
      'LOCKED_ROW',
    );
    expect(portal.posts, ['SCHOOL_ENTRY']);
  });
  test('disabled or invented attendance option cannot save', () async {
    final portal = StaffPortal();
    final rows = requested()..first['status_code'] = '9';
    expect(
      (await portal.worker().submit(rows, userConfirmed: true))['code'],
      'INVALID_STATUS',
    );
  });
  test('uncertain Save is sent once and never followed by lock', () async {
    final portal = StaffPortal()..timeoutSave = true;
    final result = await portal.worker().submit(
      requested(),
      userConfirmed: true,
    );
    expect(result['code'], 'SAVE_UNCONFIRMED');
    expect(result['submission_attempted'], true);
    expect(result['requires_verification'], true);
    expect(portal.posts, ['SCHOOL_ENTRY', 'SAVE']);
  });
  test('uncertain final is never repeated', () async {
    final portal = StaffPortal()..failFinal = true;
    final result = await portal.worker().submit(
      requested(),
      userConfirmed: true,
    );
    expect(result['code'], 'SAVE_UNCONFIRMED');
    expect(portal.posts, ['SCHOOL_ENTRY', 'SAVE', 'FINAL']);
  });
  test('changed confirmation roster blocks final lock', () async {
    final portal = StaffPortal()..mismatchedConfirmation = true;
    expect(
      (await portal.worker().submit(requested(), userConfirmed: true))['code'],
      'SAVE_UNCONFIRMED',
    );
    expect(portal.posts, ['SCHOOL_ENTRY', 'SAVE']);
  });
  test('unexpected acknowledgement blocks final lock', () async {
    final portal = StaffPortal()..malformedAck = true;
    expect(
      (await portal.worker().submit(requested(), userConfirmed: true))['code'],
      'SAVE_UNCONFIRMED',
    );
    expect(portal.posts, ['SCHOOL_ENTRY', 'SAVE']);
  });
  test(
    'successful POST without fresh marked readback stays uncertain',
    () async {
      final portal = StaffPortal()..unconfirmed = true;
      final result = await portal.worker().submit(
        requested(),
        userConfirmed: true,
      );
      expect(result['success'], false);
      expect(result['code'], 'SAVE_UNCONFIRMED');
      expect(portal.gets, 2);
    },
  );
  test('Save redirect remains uncertain without replay', () async {
    final portal = StaffPortal()..redirectSave = true;
    expect(
      (await portal.worker().submit(requested(), userConfirmed: true))['code'],
      'SAVE_UNCONFIRMED',
    );
    expect(portal.posts, ['SCHOOL_ENTRY', 'SAVE']);
  });
  test('IST hour boundary preserves uploaded HTTPX policy', () async {
    for (final testCase in [
      (2, 29, false),
      (2, 30, true),
      (11, 29, true),
      (11, 30, false),
    ]) {
      final portal = StaffPortal()
        ..clock = DateTime.utc(2026, 10, 10, testCase.$1, testCase.$2);
      expect(portal.worker().hoursOpen, testCase.$3);
    }
    final portal = StaffPortal()..clock = DateTime.utc(2026, 10, 10, 12);
    expect(
      (await portal.worker().submit(requested(), userConfirmed: true))['code'],
      'PORTAL_TIME_RESTRICTED',
    );
    expect(portal.gets, 0);
    expect(portal.posts, isEmpty);
  });
  test(
    'marked school link opens complete READ outside hours without commit',
    () async {
      final portal = StaffPortal()
        ..markedSchoolGrid = true
        ..clock = DateTime.utc(2026, 10, 10, 17);
      final result = await portal.worker().fetch();
      expect(result['success'], true);
      expect(result['attendance_verified'], true);
      expect(result['attendance_status'], 'marked');
      expect((result['staff'] as List).length, 2);
      expect(result['can_submit'], false);
      expect(result['restriction_message'], null);
      expect(portal.posts, ['SCHOOL_ENTRY']);
      final submit = await portal.worker().submit(
        requested(),
        userConfirmed: true,
      );
      expect(submit['code'], 'PORTAL_TIME_RESTRICTED');
      expect(submit['submission_attempted'], false);
      expect(portal.posts, ['SCHOOL_ENTRY']);
    },
  );
  test(
    'pending school row stays pending even with a misleading tick',
    () async {
      final portal = StaffPortal()
        ..clock = DateTime.utc(2026, 10, 10, 17)
        ..documentOverride = fixture(
          'staff_school.html',
        ).replaceAll('Pending', 'Pending <img src="checked.png" alt="marked">');
      final result = await portal.worker().fetch();
      expect(result['success'], true);
      expect(result['attendance_verified'], false);
      expect(result['can_submit'], false);
      expect((result['staff'] as List).length, 2);
      expect(portal.posts, ['SCHOOL_ENTRY']);
    },
  );
  test('outside hours existing staff table can still be read', () async {
    final portal = StaffPortal()
      ..schoolGrid = false
      ..clock = DateTime.utc(2026, 10, 10, 12);
    final result = await portal.worker().fetch();
    expect(result['success'], true);
    expect(result['can_submit'], false);
    expect(result['restriction_message'], StaffAttendanceWorker.timeMessage);
  });
  test('pending roster opens outside hours through READ school link', () async {
    final portal = StaffPortal()..clock = DateTime.utc(2026, 10, 10, 12);
    final result = await portal.worker().fetch();
    expect(result['success'], true);
    expect(result['can_submit'], false);
    expect((result['staff'] as List).length, 2);
    expect(portal.posts, ['SCHOOL_ENTRY']);
  });
  test('wrong date and school cannot display staff data', () async {
    for (final altered in [
      fixture('staff_pending.html').replaceAll('10-10-2026', '09-10-2026'),
      fixture('staff_pending.html').replaceAll('123456', '999999'),
    ]) {
      final portal = StaffPortal()..documentOverride = altered;
      expect((await portal.worker().fetch())['success'], false);
    }
  });
  test(
    'yesterday timestamp and absent save control are not completion evidence',
    () async {
      final portal = StaffPortal()
        ..documentOverride = fixture('staff_marked.html')
            .replaceAll('Oct 10 2026', 'Oct 9 2026');
      expect((await portal.worker().fetch())['attendance_verified'], false);
    },
  );
  test('pagination and duplicate IDs reject whole roster', () {
    final source = fixture('staff_pending.html');
    for (final altered in [
      source.replaceAll(
        '</table>',
        '<tr><td><a href="javascript:__doPostBack(\'g\',\'Page\$2\')">Next</a></td></tr></table>',
      ),
      source.replaceAll('value="102"', 'value="101"'),
    ]) {
      expect(
        () => StaffAttendanceWorker.parseStaffAttendance(altered),
        throwsA(isA<StaffAttendanceError>()),
      );
    }
  });
  test(
    'server errors preserve source headings; login detected as expiry',
    () async {
      final portal = StaffPortal()
        ..documentOverride = '<h2>Server Error in application</h2>';
      expect(
        (await portal.worker().fetch())['message'],
        'Server Error in application',
      );
      portal.documentOverride =
          '<input id="bodyContent_txtUName"><input id="bodyContent_txtUPswd">';
      expect((await portal.worker().fetch())['code'], 'SESSION_EXPIRED');
    },
  );
  test('hidden messages ignored and visible portal message returned', () async {
    final portal = StaffPortal()
      ..documentOverride = fixture('staff_pending.html').replaceAll(
        '</form>',
        '<div id="msgDiv" style="display:none">Ignore</div></form>',
      );
    expect((await portal.worker().fetch())['success'], true);
    portal.documentOverride = portal.documentOverride!.replaceAll(
      'display:none',
      'display:block',
    );
    final result = await portal.worker().fetch();
    expect(result['code'], 'PORTAL_MESSAGE');
    expect(result['portal_message'], 'Ignore');
  });
  test('cross-origin forms and missing WebForms tokens are blocked', () {
    for (final source in [
      fixture('staff_pending.html').replaceAll(
        'action="Staff_DailyAttendanceEntry.aspx"',
        'action="https://example.org/"',
      ),
      fixture('staff_pending.html').replaceAll('value="VALID1"', 'value=""'),
    ]) {
      final soup = html.parse(source);
      expect(
        () => StaffWebForms.post(
          Uri.parse('${base}Staff_DailyAttendanceEntry.aspx'),
          soup.getElementById('ContentPlaceHolder1_btnMarkAttendance')!,
        ),
        throwsA(isA<StaffAttendanceError>()),
      );
    }
  });
  test('user confirmation required before any portal request', () async {
    final portal = StaffPortal();
    expect(
      (await portal.worker().submit(requested(), userConfirmed: false))['code'],
      'CONFIRMATION_REQUIRED',
    );
    expect(portal.gets, 0);
  });
  test(
    'same auth facade fetch and submit return source-shaped results',
    () async {
      final portal = StaffPortal();
      final auth = StaffAuth(portal);
      addTearDown(auth.close);
      final service = DirectStaffAttendanceService(auth, now: morning);
      expect((await service.fetch())['school_id'], '123456');
      expect(
        (await service.submit(
          requested(),
          attendanceDate: '2026-10-10',
          userConfirmed: true,
        ))['attendance_verified'],
        true,
      );
      expect(
        (await service.submit(
          requested(),
          attendanceDate: '2026-10-09',
          userConfirmed: true,
        ))['code'],
        'STALE_ATTENDANCE',
      );
    },
  );
  test(
    'native transport disabled POST redirects does not replay body',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var calls = 0;
      server.listen((request) async {
        calls++;
        await request.drain<void>();
        request.response.statusCode = 307;
        request.response.headers.set('Location', '/replayed');
        request.response.write('Redirect');
        await request.response.close();
      });
      final url = Uri.parse('http://127.0.0.1:${server.port}/save');
      final client = SchoolHttpClient(
        baseUrl: url,
        allowUrl: (uri) => uri.host == '127.0.0.1',
      );
      addTearDown(() async {
        client.retire();
        await server.close(force: true);
      });
      final result = await client.request(
        'POST',
        url,
        body: utf8.encode('attendance=1'),
        followRedirects: false,
      );
      expect(result.statusCode, 307);
      expect(result.url, url);
      expect(calls, 1);
    },
  );
}
