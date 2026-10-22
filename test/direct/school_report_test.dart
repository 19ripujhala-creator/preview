import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shaladarpan/experiments/direct_student_attendance_service.dart';
import 'package:shaladarpan/services/portals/shaladarpan/direct/gender_master.dart';
import 'package:shaladarpan/services/portals/shaladarpan/direct/school_report_worker.dart';
import 'package:shaladarpan/services/portals/shaladarpan/direct/student_attendance_worker.dart';

import 'student_worker_test.dart' as attendance;

String fixture(String name) =>
    File('test/direct/fixtures/$name').readAsStringSync();

class ReportPortal extends attendance.FakePortal {
  ReportPortal({super.marked});
  int genderShows = 0;
  int sectionEntries = 0;
  bool failSection = false;
  bool expireSection = false;
  bool emptyGender = false;
  bool badLogo = false;

  @override
  Future<AttendanceHttpReply> request(
    Uri url, {
    Map<String, Object?>? fields,
    Uri? referer,
    bool mutation = false,
  }) async {
    if (mutation) throw StateError('Report must never submit a mutation');
    if (url.path.endsWith('Home_New.aspx')) {
      var content = fixture('report_home.html');
      if (badLogo) content = content.replaceAll('AQID', 'invalid@base64');
      return (url: url, status: 200, html: content);
    }
    if (url.path.endsWith('StudentDetails.aspx')) {
      if (fields == null)
        return (url: url, status: 200, html: fixture('gender_page.html'));
      genderShows++;
      if (fields['__READ_ONLY_ACTION'] != 'GENDER_SHOW')
        throw StateError('Wrong Show action');
      return (
        url: url,
        status: 200,
        html: emptyGender
            ? '<table id="${GenderMaster.gridId}"></table>'
            : fixture('gender_rows.html'),
      );
    }
    if (fields?['__READ_ONLY_ACTION'] == 'CLASS_ENTRY') {
      sectionEntries++;
      if (expireSection)
        return (
          url: Uri.parse(
            '${attendance.portalBase}Home/Public2/OfficeLoginNew.aspx',
          ),
          status: 200,
          html: '<input id="txtUserId">',
        );
      if (failSection)
        return (url: url, status: 200, html: '<html>No students table</html>');
    }
    return super.request(
      url,
      fields: fields,
      referer: referer,
      mutation: false,
    );
  }
}

class ReportAuth extends attendance.FakeAuth {
  ReportAuth(ReportPortal portal) : super(portal);
  @override
  String? get authenticatedSchoolId => '480481';
  @override
  Future<AttendanceHttpReply> schoolReportRequest(
    Uri url, {
    Map<String, Object?>? fields,
    Uri? referer,
    bool mutation = false,
  }) =>
      portal.request(url, fields: fields, referer: referer, mutation: mutation);
  @override
  Future<SchoolLogoReply> schoolReportLogo(Uri url) async => (
    url: url,
    status: 200,
    bytes: Uint8List.fromList([1, 2, 3]),
    contentType: 'image/png',
  );
}

class LeavePortal extends ReportPortal {
  LeavePortal() : super(marked: true);
  @override
  String entry() => super
      .entry()
      .replaceAll('value="P" checked', 'value="P"')
      .replaceAll('value="A" checked', 'value="A"')
      .replaceAll(
        'id="s1_2" name="student1" value="L"',
        'id="s1_2" name="student1" value="L" checked',
      )
      .replaceAll(
        'id="s2_3" name="student2" value="M"',
        'id="s2_3" name="student2" value="M" checked',
      );
  @override
  String summary() =>
      super.summary().replaceAll('lbl_P_Web_0">1', 'lbl_P_Web_0">0');
}

SchoolReportCache memoryCache(Map<String, String> values) => SchoolReportCache(
  read: (key) async => values[key],
  write: (key, value) async {
    values[key] = value;
  },
);

SchoolReportWorker report(ReportPortal portal, {SchoolReportCache? cache}) {
  cache ??= memoryCache({});
  final base = () => Uri.parse(attendance.portalBase);
  final gender = GenderMaster(
    request: portal.request,
    baseUrl: base,
    schoolId: () => '480481',
    cache: cache,
  );
  return SchoolReportWorker(
    attendance: portal.worker,
    gender: gender,
    request: portal.request,
    baseUrl: base,
    schoolId: () => '480481',
    cache: cache,
    logoRequest: (url) async => (
      url: url,
      status: 200,
      bytes: Uint8List.fromList([1, 2, 3]),
      contentType: 'image/png',
    ),
    delay: (_) async {},
  );
}

void main() {
  test('OnLeave and OnMedical both contribute to report leave count', () async {
    final result = await report(LeavePortal())
        .fetchSchoolReport(attendanceDate: attendance.date);
    final row = (result['rows'] as List).single;
    expect(row['leave'], 2);
    expect(row['boys'], 0);
    expect(row['girls'], 0);
    expect(row['absent'], 0);
    expect(row['total'], 2);
    expect(result['attendance_verified'], true);
  });
  test(
    'full marked report and progress equal original Python output',
    () async {
      final portal = ReportPortal(marked: true);
      final progress = <List<int>>[];
      final result = await report(portal).fetchSchoolReport(
        attendanceDate: attendance.date,
        onProgress: (completed, total) => progress.add([completed, total]),
      );
      expect(result, jsonDecode(fixture('python_school_report_marked.json')));
      expect(progress, [
        [1, 5],
        [2, 5],
        [3, 5],
        [4, 5],
        [5, 5],
      ]);
      expect(portal.saves, 0);
    },
  );

  test(
    'pending report is data output but never verified marked attendance',
    () async {
      final result = await report(ReportPortal())
          .fetchSchoolReport(attendanceDate: attendance.date);
      expect(result, jsonDecode(fixture('python_school_report_pending.json')));
      expect(result['attendance_verified'], false);
    },
  );

  test(
    'failed section retries three times and rejects a partial report',
    () async {
      final portal = ReportPortal()..failSection = true;
      final result = await report(portal)
          .fetchSchoolReport(attendanceDate: attendance.date);
      expect(result, jsonDecode(fixture('python_school_report_partial.json')));
      expect(portal.sectionEntries, 3);
      expect(portal.genderShows, 0);
      expect(result.containsKey('rows'), false);
    },
  );

  test('session expiry stops further section retries', () async {
    final portal = ReportPortal()..expireSection = true;
    final result = await report(portal)
        .fetchSchoolReport(attendanceDate: attendance.date);
    expect(result['code'], 'SESSION_EXPIRED');
    expect(result['failedSections'], ['1A']);
    expect(portal.sectionEntries, 1);
    expect(portal.genderShows, 0);
  });

  test('gender normalization matches Hindi and English source labels', () {
    for (final value in [
      'F',
      'G',
      'Female',
      'Girl',
      'बालिका',
      'लड़की',
      'महिला',
    ]) {
      expect(GenderMaster.genderCode(value), 'G');
    }
    for (final value in ['M', 'B', 'Male', 'Boy', 'बालक', 'लड़का', 'पुरुष']) {
      expect(GenderMaster.genderCode(value), 'B');
    }
    expect(GenderMaster.normSr(' 00 101 '), '101');
    expect(GenderMaster.genderCode('Unknown'), '');
  });

  test('gender map retains 24h cache and 10min missing-ID cooldown', () async {
    final portal = ReportPortal();
    var clock = DateTime(2026, 10, 10, 10);
    final master = GenderMaster(
      request: portal.request,
      baseUrl: () => Uri.parse(attendance.portalBase),
      schoolId: () => '480481',
      cache: memoryCache({}),
      now: () => clock,
    );
    expect(await master.getGenderMap(), {'101': 'G', '102': 'B'});
    expect(portal.genderShows, 1);
    await master.getGenderMap(neededSr: ['999']);
    expect(portal.genderShows, 1);
    clock = clock.add(const Duration(minutes: 11));
    await master.getGenderMap(neededSr: ['999']);
    expect(portal.genderShows, 2);
    clock = clock.add(const Duration(hours: 25));
    await master.getGenderMap();
    expect(portal.genderShows, 3);
  });

  test('device cache survives new worker and isolates school keys', () async {
    final values = <String, String>{};
    final cache = memoryCache(values);
    final clock = DateTime(2026, 10, 10);
    final portal = ReportPortal();
    GenderMaster instance(String school) => GenderMaster(
      request: portal.request,
      baseUrl: () => Uri.parse(attendance.portalBase),
      schoolId: () => school,
      cache: cache,
      now: () => clock,
    );
    await instance('480481').getGenderMap();
    await instance('480481').getGenderMap();
    expect(portal.genderShows, 1);
    await instance('another-school').getGenderMap();
    expect(portal.genderShows, 2);
    expect(
      values.keys,
      containsAll([
        'gender_master_480481.json',
        'gender_master_another-school.json',
      ]),
    );
  });

  test('failed gender refresh retains previous cache', () async {
    final values = <String, String>{};
    final cache = memoryCache(values);
    var clock = DateTime(2026, 10, 10);
    final portal = ReportPortal();
    final master = GenderMaster(
      request: portal.request,
      baseUrl: () => Uri.parse(attendance.portalBase),
      schoolId: () => '480481',
      cache: cache,
      now: () => clock,
    );
    await master.getGenderMap();
    portal.emptyGender = true;
    clock = clock.add(const Duration(hours: 25));
    expect(await master.getGenderMap(), {'101': 'G', '102': 'B'});
  });

  test(
    'empty gender map preserves unknown present counts and forces one refresh',
    () async {
      final portal = ReportPortal(marked: true)..emptyGender = true;
      final result = await report(portal)
          .fetchSchoolReport(attendanceDate: attendance.date);
      expect(result['success'], true);
      expect(result['unknownPresent'], 1);
      expect((result['rows'] as List).single['presentUnknown'], 1);
      expect((result['rows'] as List).single['total'], 1);
      expect(portal.genderShows, 2);
    },
  );

  test(
    'invalid inline logo is omitted while exact school metadata survives',
    () async {
      final portal = ReportPortal(marked: true)..badLogo = true;
      final result = await report(portal)
          .fetchSchoolReport(attendanceDate: attendance.date);
      expect(result['schoolName'], 'SYNTHETIC SCHOOL');
      expect(result['udise'], '12345678901');
      expect(result['leftLogoBase64'], '');
      expect(result['rightLogoBase64'], '');
    },
  );

  test('natural class sorting and section split follow source rules', () {
    final labels = ['10B', '2A', '1-A']
      ..sort((a, b) {
        final x = SchoolReportWorker.naturalKey(a),
            y = SchoolReportWorker.naturalKey(b);
        final n = x.$1.compareTo(y.$1);
        return n == 0 ? x.$2.compareTo(y.$2) : n;
      });
    expect(labels, ['1-A', '2A', '10B']);
    expect(SchoolReportWorker.splitLabel('1-A'), ('1', 'A'));
  });

  test(
    'existing attendance adapter wires report and progress to same session',
    () async {
      SharedPreferences.setMockInitialValues({});
      final portal = ReportPortal(marked: true);
      final auth = ReportAuth(portal);
      addTearDown(auth.close);
      final progress = <List<int>>[];
      final result = await DirectStudentAttendanceService(auth)
          .fetchSchoolReport(
            date: attendance.date,
            onProgress: (n, total) => progress.add([n, total]),
          );
      expect(result, jsonDecode(fixture('python_school_report_marked.json')));
      expect(progress.last, [5, 5]);
      expect(portal.saves, 0);
    },
  );
}
