import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shaladarpan/services/portals/shaladarpan/shaladarpan_service.dart';
import 'package:shaladarpan/services/portals/shaladarpan/offline_attendance_queue.dart';
import 'package:shaladarpan/services/portals/shaladarpan/direct/staff_attendance.dart';

import 'staff_attendance_batch_support.dart';

void main() {
  late AttendanceFixture f;
  setUp(() async {
    f = AttendanceFixture();
    await f.setup();
  });
  tearDown(() async {
    await f.close();
  });
  test(
    'matching confirmed submission retains exact portal notice',
    () async => f.run(() async {
      final r = await f.submit();
      expect(ShaladarpanService.isSubmissionConfirmed(r), true);
      expect(r['message'], 'Native attendance accepted.');
      expect(f.requests.length, 1);
    }),
  );
  for (final flaw in [
    'school',
    'date',
    'empty',
    'duplicate',
    'different IDs',
  ]) {
    test(
      'confirmed flags cannot accept invalid readback $flaw',
      () async => f.run(() async {
        final doc = attendanceDocument(marked: true);
        if (flaw == 'school') doc['school_id'] = '654321';
        if (flaw == 'date') doc['date'] = '2020-01-01';
        if (flaw == 'empty') doc['staff'] = [];
        if (flaw == 'duplicate') (doc['staff'] as List)[1]['staffId'] = '101';
        if (flaw == 'different IDs')
          (doc['staff'] as List)[1]['staffId'] = '999';
        f.respond = (_) async => attendanceResponse(attendanceSuccess(doc));
        final r = await f.submit();
        expect(r['success'], false);
        expect(r['submission_attempted'], true);
        expect(r['portal_message'], 'Native attendance accepted.');
        expect(r['backend_message'], isNotEmpty);
        expect((await SharedPreferences.getInstance()).getBool(f.hold), true);
        expect(f.requests.length, 1);
      }),
    );
  }
  test(
    'unconfirmed success preserves portal message alongside app verification',
    () async => f.run(() async {
      f.respond = (_) async =>
          attendanceResponse(attendanceSuccess(attendanceDocument()));
      final r = await f.submit();
      expect(r['success'], false);
      expect(r['portal_message'], 'Native attendance accepted.');
      expect(r['message'], 'Native attendance accepted.');
      expect(r['backend_message'], isNotEmpty);
    }),
  );
  test(
    'failed durable hold write blocks dispatch',
    () async => f.run(() async {
      f.store.failHold = true;
      final r = await f.submit();
      expect(r['success'], false);
      expect(r['submission_attempted'], false);
      expect(f.requests, isEmpty);
    }),
  );
  test(
    'account switch after dispatch retains original outcome and old-school hold',
    () async => f.run(() async {
      f.respond = (_) async {
        f.credentials['shala_id'] = '654321';
        return attendanceResponse(attendanceSuccess());
      };
      final r = await f.submit();
      expect(r['success'], false);
      expect(r['code'], 'ACCOUNT_CHANGED');
      expect(r['submission_attempted'], true);
      expect(r['portal_message'], 'Native attendance accepted.');
      expect((await SharedPreferences.getInstance()).getBool(f.hold), true);
    }),
  );
  test(
    'concurrent submit performs one HTTP dispatch',
    () async => f.run(() async {
      final entered = Completer<void>(), release = Completer<http.Response>();
      f.respond = (_) async {
        entered.complete();
        return release.future;
      };
      final first = f.submit();
      await entered.future;
      expect((await f.submit())['code'], 'SUBMISSION_BUSY');
      release.complete(attendanceResponse(attendanceSuccess()));
      expect((await first)['success'], true);
      expect(f.requests.length, 1);
    }),
  );
  test(
    'lost response holds submission and prevents blind replay',
    () async => f.run(() async {
      f.respond = (_) async =>
          throw TimeoutException('synthetic response loss');
      expect((await f.submit())['success'], false);
      expect((await f.submit())['code'], 'MUTATION_AMBIGUOUS');
      expect(f.requests.length, 1);
    }),
  );
  test(
    'pre-dispatch failure releases only its hold',
    () async => f.run(() async {
      f.respond = (_) async => attendanceResponse({
        'success': false,
        'code': 'INVALID_STATUS',
        'submission_attempted': false,
        'message': 'No save sent',
      });
      expect((await f.submit())['success'], false);
      expect((await SharedPreferences.getInstance()).getBool(f.hold), isNull);
    }),
  );
  test(
    'read admitted during mutation cannot publish stale result after mutation settles',
    () async => f.run(() async {
      final submitEntered = Completer<void>(), readEntered = Completer<void>();
      final submitReply = Completer<http.Response>(),
          readReply = Completer<http.Response>();
      f.respond = (request) async {
        if (request.url.path.endsWith('/submit')) {
          submitEntered.complete();
          return submitReply.future;
        }
        if (!readEntered.isCompleted) readEntered.complete();
        return readReply.future;
      };
      final saving = f.submit();
      await submitEntered.future;
      final reading = ShaladarpanService.fetchStaffAttendance(
        schoolId: '123456',
        forceRefresh: true,
      );
      await readEntered.future;
      submitReply.complete(attendanceResponse(attendanceSuccess()));
      expect((await saving)['success'], true);
      readReply.complete(
        attendanceResponse({'success': true, 'data': attendanceDocument()}),
      );
      expect((await reading)['success'], false);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          'attendance_already_marked',
        ),
        true,
      );
    }),
  );
  test(
    'warm cache reuses read without allowing caller mutation to contaminate next caller',
    () async => f.run(() async {
      final first = await ShaladarpanService.fetchStaffAttendance(
        schoolId: '123456',
      );
      first['data']['staff'][0]['name'] = 'Contaminated';
      final second = await ShaladarpanService.fetchStaffAttendance(
        schoolId: '123456',
      );
      expect(second['data']['staff'][0]['name'], 'Employee One');
      expect(f.requests.length, 1);
    }),
  );
  test(
    'force refresh bypasses warm snapshot',
    () async => f.run(() async {
      await ShaladarpanService.fetchStaffAttendance(schoolId: '123456');
      await ShaladarpanService.fetchStaffAttendance(
        schoolId: '123456',
        forceRefresh: true,
      );
      expect(f.requests.length, 2);
    }),
  );
  test(
    'fresh pending read safely clears uncertainty without any submission',
    () async => f.run(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(f.hold, true);
      expect(
        (await ShaladarpanService.fetchStaffAttendance(
          schoolId: '123456',
        ))['success'],
        true,
      );
      expect(prefs.getBool(f.hold), isNull);
      expect(f.requests.single.url.path.endsWith('/fetch'), true);
    }),
  );
  test(
    'loaded previous date is rejected before any dispatch',
    () async => f.run(() async {
      final r = await ShaladarpanService.submitStaffAttendance(
        attendanceRows(),
        schoolId: '123456',
        attendanceDate: '2020-01-01',
      );
      expect(r['success'], false);
      expect(r['code'], 'STALE_ATTENDANCE');
      expect(r['submission_attempted'], false);
      expect(f.requests, isEmpty);
    }),
  );
  test(
    'explicit current loaded date retains native successful submission',
    () async => f.run(() async {
      final r = await ShaladarpanService.submitStaffAttendance(
        attendanceRows(),
        schoolId: '123456',
        attendanceDate: attendanceDate(),
      );
      expect(r['success'], true);
      expect(f.requests.length, 1);
    }),
  );
  test(
    'failed draft persistence is reported instead of claiming a stored draft',
    () async {
      f.store.failDraft = true;
      await expectLater(
        OfflineAttendanceQueue.saveToQueue(
          schoolId: '123456',
          staffList: attendanceRows(),
        ),
        throwsStateError,
      );
      expect(await OfflineAttendanceQueue.getQueuedAttendance(), isNull);
    },
  );
  for (final stage in ['SAVE', 'FINAL']) {
    test(
      '$stage ASP.NET error heading is retained with uncertain save and no replay',
      () async {
        final calls = <String>[];
        final w = StaffAttendanceWorker(
          baseUrl: () =>
              Uri.parse('https://rajshaladarpan.rajasthan.gov.in/SD1/'),
          schoolId: () => '123456',
          now: () => DateTime.utc(2026, 10, 10, 3, 30),
          request:
              (
                url, {
                fields,
                referer,
                action,
                mutation = false,
                timeout = const Duration(seconds: 25),
              }) async {
                if (fields == null)
                  return (
                    url: url,
                    status: 200,
                    html: File('test/direct/fixtures/staff_pending.html')
                        .readAsStringSync(),
                  );
                calls.add(action!);
                if (action == stage)
                  return (
                    url: url,
                    status: 200,
                    html: '<h2>Attendance document failed exactly here.</h2><p>Server Error in /SD1 Application.</p>',
                  );
                return (
                  url: url,
                  status: 200,
                  html: File('test/direct/fixtures/staff_confirmation.html')
                      .readAsStringSync(),
                );
              },
        );
        final rows = [
          {
            'staffId': '101',
            'sno': '1',
            'status_code': '2',
            'original_status': 'Present',
          },
          {
            'staffId': '102',
            'sno': '2',
            'status_code': '3',
            'original_status': 'CL',
          },
        ];
        final r = await w.submit(rows, userConfirmed: true);
        expect(r['success'], false);
        expect(r['code'], 'SAVE_UNCONFIRMED');
        expect(r['message'], 'Attendance document failed exactly here.');
        expect(r['submission_attempted'], true);
        expect(r['backend_message'], isNotEmpty);
        expect(calls, stage == 'SAVE' ? ['SAVE'] : ['SAVE', 'FINAL']);
      },
    );
  }
}
