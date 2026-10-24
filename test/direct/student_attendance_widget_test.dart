import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shaladarpan/tabs/student/modules/student_attendance/screens/daily_attendance_sheet_screen.dart';
import 'package:shaladarpan/tabs/student/modules/student_attendance/screens/school_report_screen.dart';

import 'staff_attendance_batch_support.dart';
import 'student_attendance_batch_test.dart'
    show studentBatchDocument, studentBatchSuccess;

void main() {
  AutomatedTestWidgetsFlutterBinding.ensureInitialized();
  late AttendanceFixture f;
  setUp(() async {
    f = AttendanceFixture();
    await f.setup();
    f.respond = (r) async {
      final d = studentBatchDocument(pending: true)
        ..['date'] = r.url.queryParameters['date'] ?? '24/10/2026';
      return attendanceResponse(d);
    };
    final fonts = FontLoader('PlusJakartaSans');
    fonts.addFont(
      Future.value(
        ByteData.sublistView(
          File('assets/fonts/PlusJakartaSans-Regular.ttf').readAsBytesSync(),
        ),
      ),
    );
    await fonts.load();
  });
  tearDown(() async => f.close());
  Future<void> flush(WidgetTester t) async {
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> show(
    WidgetTester t, {
    double width = 360,
    double scale = 1,
    Widget? screen,
  }) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = Size(width, 1000);
    await t.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 1000),
            textScaler: TextScaler.linear(scale),
          ),
          child: screen ?? const DailyAttendanceSheetScreen(),
        ),
      ),
    );
    await flush(t);
  }

  Future<void> finish(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump();
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  }

  for (final width in [320.0, 360.0, 390.0, 768.0]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets(
        'student register fits width $width text scale $scale',
        (t) async => f.run(() async {
          await show(t, width: width, scale: scale);
          expect(find.text('Student One'), findsOneWidget);
          expect(t.takeException(), isNull);
          await finish(t);
        }),
      );
    }
  }
  testWidgets(
    'unselected row is pending and cannot reach confirmation',
    (t) async => f.run(() async {
      await show(t);
      expect(find.text('Selection pending: 1'), findsOneWidget);
      await t.tap(find.text('Submit Attendance'));
      await flush(t);
      expect(find.text('Confirm Attendance'), findsNothing);
      expect(f.requests.where((r) => r.method == 'POST'), isEmpty);
      await finish(t);
    }),
  );
  testWidgets(
    'resume after school change discards previous school register',
    (t) async => f.run(() async {
      await show(t);
      expect(find.text('Student One'), findsOneWidget);
      f.credentials['shala_id'] = '654321';
      f.respond = (r) async {
        final d = studentBatchDocument()
          ..['date'] = r.url.queryParameters['date'];
        d['students'][0]['name'] = 'New School Student';
        return attendanceResponse(d);
      };
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        t.binding.handleAppLifecycleStateChanged(state);
      }
      await flush(t);
      expect(find.text('Student One'), findsNothing);
      expect(find.text('New School Student'), findsOneWidget);
      await finish(t);
    }),
  );
  testWidgets(
    'wrong saved-date proof stays held and shows original native notice',
    (t) async => f.run(() async {
      String selected = '';
      f.respond = (r) async {
        selected = r.url.queryParameters['date'] ?? selected;
        final d = studentBatchDocument()..['date'] = selected;
        return attendanceResponse(d);
      };
      await show(t);
      await t.tap(find.text('Submit Attendance'));
      await flush(t);
      expect(find.text('Confirm & Save'), findsOneWidget);
      f.respond = (_) async =>
          attendanceResponse(studentBatchSuccess()..['date'] = '01/01/2020');
      await t.tap(find.text('Confirm & Save'));
      await flush(t);
      expect(find.text('Verify Previous Save'), findsOneWidget);
      expect(
        find.textContaining('Exact native attendance notice.'),
        findsWidgets,
      );
      expect(f.requests.where((r) => r.method == 'POST').length, 1);
      await finish(t);
    }),
  );
  for (final inflight in [false, true]) {
    testWidgets(
      'report date update ignores old ${inflight ? 'inflight' : 'completed'} result',
      (t) async => f.run(() async {
        final old = Completer<http.Response>();
        f.respond = (r) async {
          if (r.url.queryParameters['date'] == '24/10/2026')
            return inflight
                ? old.future
                : attendanceResponse({
                    'success': false,
                    'message': 'Old date portal notice.',
                    'message_source': 'portal',
                  });
          return attendanceResponse({
            'success': false,
            'message': 'New date portal notice.',
            'message_source': 'portal',
          });
        };
        await show(t, screen: SchoolReportScreen(date: DateTime(2026, 10, 24)));
        await show(t, screen: SchoolReportScreen(date: DateTime(2026, 10, 25)));
        if (inflight) {
          old.complete(
            attendanceResponse({
              'success': false,
              'message': 'Old date portal notice.',
              'message_source': 'portal',
            }),
          );
          await flush(t);
        }
        expect(find.text('New date portal notice.'), findsOneWidget);
        expect(find.text('Old date portal notice.'), findsNothing);
        expect(f.requests.length, 2);
        await finish(t);
      }),
    );
  }
 testWidgets('India midnight refreshes the default current-day register',(t)async=>f.run(()async{
  var now=DateTime.utc(2026,10,24,18,29,58);
  await show(t,screen:DailyAttendanceSheetScreen(clock:()=>now));expect(f.requests.last.url.queryParameters['date'],'24/10/2026');
  now=now.add(const Duration(seconds:3));await t.pump(const Duration(seconds:15));await flush(t);
  expect(f.requests.last.url.queryParameters['date'],'25/10/2026');expect(f.requests.length,2);await finish(t);
 }));
 testWidgets('midnight closes an old review without submitting yesterday attendance',(t)async=>f.run(()async{
  var now=DateTime.utc(2026,10,24,18,29,58);
  f.respond=(r)async=>attendanceResponse(studentBatchDocument()..['date']=r.url.queryParameters['date']);
  await show(t,screen:DailyAttendanceSheetScreen(clock:()=>now));await t.tap(find.text('Submit Attendance'));await flush(t);expect(find.text('Confirm Attendance'),findsOneWidget);
  now=now.add(const Duration(seconds:3));await t.pump(const Duration(seconds:15));await flush(t);
  expect(find.text('Confirm Attendance'),findsNothing);expect(f.requests.where((r)=>r.method=='POST'),isEmpty);expect(f.requests.last.url.queryParameters['date'],'25/10/2026');await finish(t);
 }));

}
