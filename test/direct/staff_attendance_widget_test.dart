import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shaladarpan/tabs/teacher/modules/shaladarpan/attendance_view.dart';

import 'staff_attendance_batch_support.dart';

void main() {
  AutomatedTestWidgetsFlutterBinding.ensureInitialized();
  late AttendanceFixture f;
  late DateTime now;
  setUp(() async {
    f = AttendanceFixture();
    await f.setup();
    final d = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    now = DateTime.utc(d.year, d.month, d.day, 4);
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
  tearDown(() async {
    await f.close();
  });
  Future<void> show(
    WidgetTester t, {
    double width = 360,
    double scale = 1,
  }) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = Size(width, 800);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 800),
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(12),
              child: AttendanceView(clock: () => now),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> finish(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump();
  }

  for (final size in [320.0, 360.0, 390.0, 768.0]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets(
        'attendance layout fits width $size text scale $scale',
        (t) async => f.run(() async {
          await show(t, width: size, scale: scale);
          expect(find.text('Employee One'), findsOneWidget);
          expect(t.takeException(), isNull);
          expect(find.bySemanticsLabel('Present: 1'), findsOneWidget);
          expect(find.bySemanticsLabel('Leave: 1'), findsOneWidget);
          await finish(t);
        }),
      );
    }
  }
  testWidgets(
    'new day clears yesterday locked roster and fetches current attendance',
    (t) async => f.run(() async {
      f.respond = (_) async => attendanceResponse({
        'success': true,
        'data': attendanceDocument(marked: true),
      });
      await show(t);
      expect(
        find.textContaining('Attendance locked & verified'),
        findsOneWidget,
      );
      final before = f.requests.length;
      now = now.add(const Duration(days: 1));
      await t.pump(const Duration(seconds: 16));
      for (var i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 20));
      }
      expect(f.requests.length, greaterThan(before));
      expect(find.text('Employee One'), findsNothing);
      expect(find.textContaining('Attendance locked & verified'), findsNothing);
      await finish(t);
    }),
  );
  testWidgets(
    'placeholder option remains pending and cannot reach confirmation',
    (t) async => f.run(() async {
      final doc = attendanceDocument();
      final row = (doc['staff'] as List).first as Map;
      row['status_code'] = '0';
      row['status'] = 'Select';
      row['options'] = [];
      f.respond = (_) async =>
          attendanceResponse({'success': true, 'data': doc});
      await show(t);
      expect(find.text('Selection pending: 1'), findsOneWidget);
      expect(find.bySemanticsLabel('Present: 0'), findsOneWidget);
      expect(find.bySemanticsLabel('Other: 0'), findsOneWidget);
      await t.tap(find.text('Submit Attendance'));
      await t.pumpAndSettle();
      expect(find.text('Review Final Attendance'), findsNothing);
      expect(f.requests.length, 1);
      await finish(t);
    }),
  );
  testWidgets(
    'resume refresh disables editing until the current read settles',
    (t) async => f.run(() async {
      await show(t);
      final waiting = Completer<http.Response>();
      f.respond = (_) async => waiting.future;
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
      for (var i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 20));
      }
      expect(f.requests.length, 2);
      final button = t.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Mark All Present'),
      );
      expect(button.onPressed, isNull);
      waiting.complete(
        attendanceResponse({'success': true, 'data': attendanceDocument()}),
      );
      for (var i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 20));
      }
      await finish(t);
    }),
  );
  testWidgets(
    'mark all preserves locked leave and reviewed save dispatches once',
    (t) async => f.run(() async {
      final doc = attendanceDocument();
      doc['staff'][0]['status_code'] = '9';
      doc['staff'][0]['status'] = 'Not Present';
      f.respond = (request) async => attendanceResponse(
        request.url.path.endsWith('/submit')
            ? attendanceSuccess()
            : {'success': true, 'data': doc},
      );
      await show(t);
      expect(find.bySemanticsLabel('Absent: 1'), findsOneWidget);
      await t.tap(find.text('Mark All Present'));
      await t.pump();
      expect(find.bySemanticsLabel('Present: 1'), findsOneWidget);
      expect(find.bySemanticsLabel('Leave: 1'), findsOneWidget);
      await t.tap(find.text('Submit Attendance'));
      await t.pumpAndSettle();
      expect(find.text('Review Final Attendance'), findsOneWidget);
      await t.tap(find.text('Confirm & Submit'));
      for (var i = 0; i < 12; i++) {
        await t.pump(const Duration(milliseconds: 30));
      }
      expect(f.requests.where((r) => r.url.path.endsWith('/submit')).length, 1);
      expect(
        find.textContaining('Attendance locked & verified'),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
      await finish(t);
    }),
  );
  testWidgets(
    'refresh during review requires a new review before any submit',
    (t) async => f.run(() async {
      await show(t);
      await t.tap(find.text('Submit Attendance'));
      await t.pumpAndSettle();
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
      for (var i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 20));
      }
      expect(f.requests.length, 2);
      await t.tap(find.text('Confirm & Submit'));
      await t.pumpAndSettle();
      expect(f.requests.where((r) => r.url.path.endsWith('/submit')), isEmpty);
      expect(
        find.textContaining('Attendance changed during review'),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
      await finish(t);
    }),
  );
  for (final owner in ['123456', '654321']) {
    testWidgets(
      'stored uncertain draft review respects owner $owner without dispatch',
      (t) async => f.run(() async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'offline_attendance_queue_payload',
          jsonEncode({
            'school_id': owner,
            'date': attendanceDate(),
            'timestamp': 1,
            'sync_state': 'uncertain',
            'staff_list': attendanceRows(),
          }),
        );
        await show(t);
        expect(find.text('Stored Attendance Draft'), findsOneWidget);
        await t.tap(find.text('Review'));
        await t.pumpAndSettle();
        if (owner == '123456') {
          expect(find.text('Stored attendance draft'), findsOneWidget);
          expect(
            find.textContaining(
              'Previous submission requires portal verification',
            ),
            findsOneWidget,
          );
          await t.tap(find.text('Close'));
          await t.pumpAndSettle();
        } else {
          expect(find.text('Stored attendance draft'), findsNothing);
          expect(
            find.textContaining('Stored draft belongs to a different school'),
            findsOneWidget,
          );
        }
        expect(
          f.requests.where((r) => r.url.path.endsWith('/submit')),
          isEmpty,
        );
        expect(t.takeException(), isNull);
        await finish(t);
      }),
    );
  }
  testWidgets(
    'corrupt legacy draft cannot escape as an unhandled UI error',
    (t) async => f.run(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('offline_attendance_queue_payload', '{bad');
      await show(t);
      expect(find.text('Employee One'), findsOneWidget);
      expect(t.takeException(), isNull);
      await finish(t);
    }),
  );
}
