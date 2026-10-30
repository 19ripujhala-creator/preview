import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shaladarpan/services/portals/shaladarpan/direct/student_attendance_worker.dart';
import 'package:shaladarpan/services/portals/shaladarpan/direct/school_report_worker.dart';
import 'package:shaladarpan/services/portals/shaladarpan/direct/gender_master.dart';

import 'school_report_test.dart' show ReportPortal, memoryCache;
import 'student_worker_test.dart' show date, portalBase;

// Model a WebForms page that retains the entry panel until native Back.
// This is a protocol regression fixture, not a captured live portal response.
class StatefulDatePortal extends ReportPortal {
  String selected = date;
  bool entryOpen = false;
  bool unselectedOnMarked = false;
  final navigation = <String>[];
  @override
  String summary() => super.summary().replaceAll(date, selected);
  @override
  String entry() {
    var base = super.entry();
    if (unselectedOnMarked) {
      base = base.replaceAll('value="P" checked', 'value="P"');
    }
    return base.replaceFirst('</form>', '''
    <input disabled="disabled" id="ContentPlaceHolder1_txtdate" name="ctl00\$ContentPlaceHolder1\$txtdate" value="$selected">
    <input disabled="disabled" id="ContentPlaceHolder1_btn_Show" name="ctl00\$ContentPlaceHolder1\$btn_Show" type="submit" value="Show">
    <input id="ContentPlaceHolder1_btnback" name="ctl00\$ContentPlaceHolder1\$btnback" type="submit" value="Back">
    <span id="ContentPlaceHolder1_lbldateofAtt">$selected</span>
    <span id="ContentPlaceHolder1_lblentrySection">1A</span></form>''');
  }

  @override
  Future<AttendanceHttpReply> request(
    Uri url, {
    Map<String, Object?>? fields,
    Uri? referer,
    bool mutation = false,
  }) async {
    if (!url.path.endsWith(StudentAttendanceWorker.pageName)) {
      return super.request(
        url,
        fields: fields,
        referer: referer,
        mutation: mutation,
      );
    }
    if (mutation) throw StateError('READ fixture must never submit');
    final action = fields?['__READ_ONLY_ACTION']?.toString() ?? 'GET';
    navigation.add(action);
    if (action == 'BACK') {
      expect(fields!.containsKey(r'ctl00$ContentPlaceHolder1$txtdate'), false);
      expect(fields['__VIEWSTATE'], 'ENTRY_VIEWSTATE');
      entryOpen = false;
      return (url: url, status: 200, html: summary());
    }
    if (action == 'GET' && entryOpen) {
      return (url: url, status: 200, html: entry());
    }
    if (action == 'SHOW') {
      if (entryOpen) throw StateError('Show requires summary mode');
      selected = fields![r'ctl00$ContentPlaceHolder1$txtdate'] as String;
    }
    if (action == 'CLASS_ENTRY') entryOpen = true;
    return (url: url, status: 200, html: entryOpen ? entry() : summary());
  }
}

StudentAttendanceWorker worker(StatefulDatePortal p) => StudentAttendanceWorker(
  request: p.request,
  baseUrl: () => Uri.parse(portalBase),
  sessionIdentity: () => 'fixture-session',
  indiaNow: () => DateTime(2026, 10, 10),
);

void main() {
  test(
    'date change exits retained disabled entry with native Back before Show',
    () async {
      final p = StatefulDatePortal();
      final w = worker(p);
      expect(
        (await w.fetchStudentAttendanceList(
          classId: '1',
          attendanceDate: date,
        ))['success'],
        true,
      );
      final n = p.navigation.length;
      final old = await w.fetchStudentAttendanceList(
        classId: '1',
        attendanceDate: '09/10/2026',
      );
      expect(old['success'], true, reason: '$old');
      expect(old['date'], '09/10/2026');
      expect(p.navigation.sublist(n), ['BACK', 'SHOW', 'CLASS_ENTRY']);
      final today = await w.fetchStudentAttendanceList(
        classId: '1',
        attendanceDate: date,
      );
      expect(today['success'], true);
      expect(today['date'], date);
    },
  );
  test(
    'fresh GET returning server-retained disabled entry exits via native Back before Show',
    () async {
      final p = StatefulDatePortal()..entryOpen = true;
      final w = worker(p);
      final old = await w.fetchStudentAttendanceList(
        classId: '1',
        attendanceDate: '09/10/2026',
      );
      expect(old['success'], true, reason: '$old');
      expect(old['date'], '09/10/2026');
      expect(p.navigation, ['GET', 'BACK', 'SHOW', 'CLASS_ENTRY']);
    },
  );
  test(
    'backdate school report can start from retained current-date entry',
    () async {
      final p = StatefulDatePortal();
      final w = worker(p);
      expect(
        (await w.fetchStudentAttendanceList(
          classId: '1',
          attendanceDate: date,
        ))['success'],
        true,
      );
      final base = () => Uri.parse(portalBase);
      final cache = memoryCache({});
      final r = SchoolReportWorker(
        attendance: w,
        gender: GenderMaster(
          request: p.request,
          baseUrl: base,
          schoolId: () => '123',
          cache: cache,
        ),
        request: p.request,
        baseUrl: base,
        schoolId: () => '123',
        cache: cache,
        logoRequest: (url) async =>
            (url: url, status: 404, bytes: Uint8List(0), contentType: ''),
        delay: (_) async {},
      );
      final result = await r.fetchSchoolReport(attendanceDate: '09/10/2026');
      expect(result['success'], true, reason: '$result');
      expect(result['date'], '09/10/2026');
    },
  );
  test(
    'historical marked roster still enforces unselected-status verification',
    () async {
      final p = StatefulDatePortal()
        ..marked = true
        ..unselectedOnMarked = true;
      final w = worker(p);
      final result = await w.fetchStudentAttendanceList(
        classId: '1',
        attendanceDate: '09/10/2026',
      );
      expect(result['success'], true);
      expect(result['data_verified'], false);
      expect(result['attendance_verified'], false);
      expect(
        result['warning'],
        contains('unselected or unrecognised statuses'),
      );
    },
  );
}
