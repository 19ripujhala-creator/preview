import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shaladarpan/services/portals/shaladarpan/student_service.dart';
import 'package:shaladarpan/tabs/student/modules/student_attendance/screens/daily_attendance_sheet_screen.dart';

import 'staff_attendance_batch_support.dart';

const studentBatchDate = '24/10/2026';
List<Map<String, dynamic>> studentBatchRows({bool pending = false}) => [
  {
    'srNo': '00101',
    'serialNo': 1,
    'name': 'Student One',
    'status': pending ? null : 'Present',
    'present': pending ? null : true,
    'gender': 'B',
  },
  {
    'srNo': '102',
    'serialNo': 2,
    'name': 'Student Two',
    'status': 'Absent',
    'present': false,
    'gender': 'G',
  },
];
Map<String, dynamic> studentBatchDocument({
  bool marked = false,
  bool pending = false,
}) => {
  'success': true,
  'data_verified': true,
  'classId': '1',
  'section': '1A',
  'date': studentBatchDate,
  'total': 2,
  'students': studentBatchRows(pending: pending),
  'classes': ['Class 1', 'Class 2'],
  'sections': ['1A', '1B'],
  'attendance_verified': marked,
  'is_already_marked': marked,
  'attendance_status': marked ? 'marked' : 'pending',
  'summary': {'classId': '1', 'section': '1A', 'total': 2, 'done': marked},
};
Map<String, dynamic> studentBatchPayload() => {
  'class_id': '1A',
  'section': '1A',
  'date': studentBatchDate,
  'students': studentBatchRows(),
};
Map<String, dynamic> studentBatchSuccess() => {
  ...studentBatchDocument(marked: true),
  'submission_attempted': true,
  'message_source': 'portal',
  'message': 'Exact native attendance notice.',
  'portal_message': 'Exact native attendance notice.',
};
Map<String, dynamic> studentBatchReport() => {
  'success': true,
  'date': studentBatchDate,
  'schoolName': 'School One',
  'rows': <Map<String, dynamic>>[
    {
      'className': '1',
      'section': 'A',
      'boys': 1,
      'girls': 0,
      'absent': 1,
      'leave': 0,
      'total': 2,
      'enrolled': 2,
      'presentUnknown': 0,
    },
  ],
  'unknownPresent': 0,
  'failedSections': [],
  'attendance_verified': true,
  'attendance_status': 'marked',
  'pendingSections': [],
};

class StudentGateStore extends AttendanceStore {
  void Function()? onHold;
  bool failRemove = false;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key.contains('student_submission_hold/')) onHold?.call();
    return super.setValue(type, key, value);
  }

  @override
  Future<bool> remove(String key) async {
    if (failRemove && key.contains('student_submission_hold/'))
      throw StateError('disk removal unavailable');
    return super.remove(key);
  }
}

void main() {
  late AttendanceFixture f;
  setUp(() async {
    f = AttendanceFixture();
    await f.setup();
    f.respond = (r) async => attendanceResponse(
      r.method == 'POST' ? studentBatchSuccess() : studentBatchDocument(),
    );
  });
  tearDown(() async => f.close());
  Future<Map<String, dynamic>> read() => StudentService.fetchAttendance(
    classId: '1A',
    section: '1A',
    date: studentBatchDate,
  );
  Future<Map<String, dynamic>> save() =>
      StudentService.saveAttendance(studentBatchPayload());
  test(
    'unselected pending roster is a valid read without becoming a saved count',
    () async => f.run(() async {
      f.respond = (_) async =>
          attendanceResponse(studentBatchDocument(pending: true));
      final r = await read();
      expect(r['success'], true);
      expect(r['students'][0]['status'], isNull);
    }),
  );
  for (final flaw in [
    'duplicate',
    'missing identity',
    'total mismatch',
    'marked unknown',
  ]) {
    test(
      'invalid $flaw roster cannot be returned as verified attendance',
      () async => f.run(() async {
        final d = studentBatchDocument(
          marked: flaw == 'marked unknown',
          pending: flaw == 'marked unknown',
        );
        if (flaw == 'duplicate') d['students'][1]['srNo'] = '101';
        if (flaw == 'missing identity')
          d['students'][0] = {
            'srNo': '',
            'serialNo': '',
            'name': '',
            'status': 'Present',
          };
        if (flaw == 'total mismatch') d['total'] = 3;
        f.respond = (_) async => attendanceResponse(d);
        expect((await read())['success'], false);
      }),
    );
  }
  test(
    'save freezes nested roster before credential awaits',
    () async => f.run(() async {
      final data = studentBatchPayload();
      final saving = StudentService.saveAttendance(data);
      data['students'][0]['status'] = 'Absent';
      data['class_id'] = '2A';
      final r = await saving;
      expect(r['success'], true);
      final sent = jsonDecode(f.requests.single.body);
      expect(sent['class_id'], '1A');
      expect(sent['students'][0]['status'], 'Present');
    }),
  );
  for (final flaw in [
    'missing proof',
    'wrong date',
    'wrong class',
    'wrong section',
    'wrong statuses',
  ]) {
    test(
      'save success with $flaw stays on hold and preserves native notice',
      () async => f.run(() async {
        final d = studentBatchSuccess();
        if (flaw == 'missing proof') d.remove('students');
        if (flaw == 'wrong date') d['date'] = '23/10/2026';
        if (flaw == 'wrong class') d['classId'] = '2';
        if (flaw == 'wrong section') d['section'] = '1B';
        if (flaw == 'wrong statuses') d['students'][0]['status'] = 'Absent';
        f.respond = (_) async => attendanceResponse(d);
        final r = await save();
        expect(r['success'], false);
        expect(r['attendance_verified'], false);
        expect(r['submission_on_hold'], true);
        expect(r['portal_message'], 'Exact native attendance notice.');
        expect(r['message'], 'Exact native attendance notice.');
        expect(r['verification_message'], isNotEmpty);
      }),
    );
  }
  test(
    'credentials changing during hold persistence blocks dispatch',
    () async => f.run(() async {
      final store = StudentGateStore()
        ..onHold = () => f.credentials['shala_id'] = '654321';
      SharedPreferencesStorePlatform.instance = store;
      final r = await save();
      expect(r['success'], false);
      expect(r['submission_attempted'], false);
      expect(f.requests, isEmpty);
    }),
  );
  test(
    'verified native success survives local hold-cleanup failure',
    () async => f.run(() async {
      SharedPreferencesStorePlatform.instance = StudentGateStore()
        ..failRemove = true;
      final r = await save();
      expect(r['success'], true);
      expect(r['attendance_verified'], true);
      expect(r['submission_on_hold'], true);
      expect(r['portal_message'], 'Exact native attendance notice.');
      expect(f.requests.length, 1);
    }),
  );
  test(
    'invalid calendar date is rejected before Save HTTP',
    () async => f.run(() async {
      final d = studentBatchPayload()..['date'] = '31/02/2026';
      final r = await StudentService.saveAttendance(d);
      expect(r['success'], false);
      expect(r['submission_attempted'], false);
      expect(f.requests, isEmpty);
    }),
  );
  test(
    'summary cannot publish after school credentials change',
    () async => f.run(() async {
      f.respond = (_) async {
        f.credentials['shala_id'] = '654321';
        return attendanceResponse({
          'success': true,
          'date': studentBatchDate,
          'classes': [
            {'classId': '1', 'section': '1A', 'total': 2},
          ],
        });
      };
      expect(
        (await StudentService.fetchClassSummary(
          date: studentBatchDate,
        ))['success'],
        false,
      );
    }),
  );
  for (final flaw in [
    'wrong date',
    'duplicate section',
    'bad totals',
    'failed sections',
  ]) {
    test(
      'report with $flaw is refused before PDF display',
      () async => f.run(() async {
        final d = studentBatchReport();
        if (flaw == 'wrong date') d['date'] = '23/10/2026';
        if (flaw == 'duplicate section')
          d['rows'].add(Map<String, dynamic>.from(d['rows'][0]));
        if (flaw == 'bad totals') d['rows'][0]['total'] = 20;
        if (flaw == 'failed sections') d['failedSections'] = ['2A'];
        f.respond = (_) async => attendanceResponse(d);
        expect(
          (await StudentService.fetchSchoolReport(
            date: studentBatchDate,
          ))['success'],
          false,
        );
      }),
    );
  }
  test(
    'legacy report cannot publish for a changed school',
    () async => f.run(() async {
      f.respond = (_) async {
        f.credentials['shala_id'] = '654321';
        return attendanceResponse(studentBatchReport());
      };
      expect(
        (await StudentService.fetchSchoolReport(
          date: studentBatchDate,
        ))['success'],
        false,
      );
    }),
  );
  test(
    'report begun before Save cannot return a pre-save snapshot afterwards',
    () async => f.run(() async {
      final entered = Completer<void>(), reply = Completer<http.Response>();
      f.respond = (r) async {
        if (r.url.path.endsWith('school-report')) {
          entered.complete();
          return reply.future;
        }
        return attendanceResponse(studentBatchSuccess());
      };
      final reading = StudentService.fetchSchoolReport(date: studentBatchDate);
      await entered.future;
      expect((await save())['success'], true);
      reply.complete(attendanceResponse(studentBatchReport()));
      expect((await reading)['success'], false);
    }),
  );
  for (final status in [null, 'Select', 'Not Present']) {
    test(
      'student model preserves $status as unselected rather than Present',
      () {
        final row = StudentRecord.fromJson(
          {'serialNo': 1, 'name': 'Student One', 'status': status},
          'Class 1',
          'A',
          1,
        );
        expect(row.attendanceStatus, isNot('P'));
        expect(row.toJson()['status'], isNot('Present'));
      },
    );
  }
}
