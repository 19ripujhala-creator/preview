import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shaladarpan/services/portals/shaladarpan/direct/gender_master.dart';
import 'package:shaladarpan/services/portals/shaladarpan/direct/student_attendance_worker.dart';

import 'student_worker_test.dart' show FakePortal, students, date;
import 'school_report_test.dart' show ReportPortal, report, memoryCache;

class UnselectedReportPortal extends ReportPortal {
  @override
  String entry() => super.entry().replaceAll(' checked', '');
}

class NativeErrorReportPortal extends ReportPortal {
  @override
  Future<AttendanceHttpReply> request(
    Uri url, {
    Map<String, Object?>? fields,
    Uri? referer,
    bool mutation = false,
  }) async {
    if (fields?['__READ_ONLY_ACTION'] == 'CLASS_ENTRY')
      return (
        url: url,
        status: 500,
        html: '<title>Server Error in Application</title><h2>Exact native section error.</h2>',
      );
    return super.request(
      url,
      fields: fields,
      referer: referer,
      mutation: mutation,
    );
  }
}

void main() {
  test(
    'unselected portal radios are not counted as report Present boys/girls',
    () async {
      final p = UnselectedReportPortal();
      final r = await report(p).fetchSchoolReport(attendanceDate: date);
      expect(r['success'], true);
      final row = (r['rows'] as List).single;
      expect(row['boys'], 0);
      expect(row['girls'], 0);
      expect(row['unselected'], 2);
      expect(r['attendance_verified'], false);
    },
  );
  test('section failure retains the original native error and names failed sections', () async {
    final p = NativeErrorReportPortal();
    final r = await report(p).fetchSchoolReport(attendanceDate: date);
    expect(r['success'], false);
    expect(r['message'], 'Exact native section error.');
    expect(r['portal_message'], 'Exact native section error.');
    expect(r['failedSections'], ['1A']);
    expect(r['verification_message'], contains('1A'));
  });
  test(
    'gender maps returned to consumers cannot mutate later reports',
    () async {
      final p = ReportPortal(), values = <String, String>{};
      var now = DateTime.utc(2026, 10, 24);
      final g = GenderMaster(
        request: p.request,
        baseUrl: () =>
            Uri.parse('https://rajshaladarpan.rajasthan.gov.in/SD1/'),
        schoolId: () => '123456',
        cache: memoryCache(values),
        now: () => now,
      );
      final one = await g.getGenderMap(neededSr: ['101']);
      expect(one['101'], 'G');
      one['101'] = 'B';
      final two = await g.getGenderMap(neededSr: ['101']);
      expect(two['101'], 'G');
      expect(p.genderShows, 1);
    },
  );
  test(
    'clock regression expires gender master cache instead of extending it',
    () async {
      final p = ReportPortal(), values = <String, String>{};
      var now = DateTime.utc(2026, 10, 24);
      final g = GenderMaster(
        request: p.request,
        baseUrl: () =>
            Uri.parse('https://rajshaladarpan.rajasthan.gov.in/SD1/'),
        schoolId: () => '123456',
        cache: memoryCache(values),
        now: () => now,
      );
      await g.getGenderMap(neededSr: ['101']);
      final before = p.genderShows;
      now = now.subtract(const Duration(seconds: 1));
      await g.getGenderMap(neededSr: ['101']);
      expect(p.genderShows, greaterThan(before));
    },
  );
  test(
    'native Save exposes the exact verified roster to the public service',
    () async {
      final p = FakePortal();
      final r = await p.worker.saveStudentAttendance(
        classId: '1',
        attendanceDate: date,
        section: '1A',
        students: students,
        userConfirmed: true,
      );
      expect(r['success'], true);
      expect(r['data_verified'], true);
      expect(r['students'], isA<List>());
      expect(r['total'], 2);
      expect(p.saves, 1);
    },
  );
  test('native Save input is frozen before preflight HTTP awaits', () async {
    final p = FakePortal();
    final entered = Completer<void>(), release = Completer<void>();
    var first = true;
    final worker = StudentAttendanceWorker(
      baseUrl: () => Uri.parse('https://rajshaladarpan.rajasthan.gov.in/SD1/'),
      indiaNow: () => DateTime(2026, 10, 10),
      request: (url, {fields, referer, mutation = false}) async {
        if (first) {
          first = false;
          entered.complete();
          await release.future;
        }
        return p.request(
          url,
          fields: fields,
          referer: referer,
          mutation: mutation,
        );
      },
    );
    final input = students.map((r) => Map<String, Object?>.from(r)).toList();
    final saving = worker.saveStudentAttendance(
      classId: '1',
      attendanceDate: date,
      section: '1A',
      students: input,
      userConfirmed: true,
    );
    await entered.future;
    input[0]['status'] = 'Absent';
    release.complete();
    final r = await saving;
    expect(r['success'], true);
    expect(p.saves, 1);
    final post =
        p.requests.singleWhere((r) => r['mutation'] == true)['fields'] as Map;
    expect(post['student1'], 'P');
  });
}
