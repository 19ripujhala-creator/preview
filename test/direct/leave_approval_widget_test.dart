import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shaladarpan/services/portals/shaladarpan/leave_approval_service.dart';
import 'package:shaladarpan/tabs/teacher/modules/shaladarpan/leave_approvals_view.dart';

import 'staff_attendance_batch_support.dart';
import 'leave_approval_batch_test.dart'
    show leaveBatchDocument, leaveBatchSuccess;

void main() {
  AutomatedTestWidgetsFlutterBinding.ensureInitialized();
  late AttendanceFixture f;
  var tick = 0, callbacks = 0;
  setUp(() async {
    f = AttendanceFixture();
    await f.setup();
    callbacks = 0;
    final time = DateTime.utc(2026, 10, 23, 0, tick++ * 5);
    LeaveApprovalService.clock = () => time;
    f.respond = (r) async => attendanceResponse(
      r.url.path.endsWith('/action')
          ? leaveBatchSuccess()
          : {'success': true, 'data': leaveBatchDocument()},
    );
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
    LeaveApprovalService.clock = null;
    await f.close();
  });
  Future<void> flush(WidgetTester t) async {
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> show(
    WidgetTester t, {
    double width = 360,
    double scale = 1,
  }) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = Size(width, 1000);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 1000),
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(12),
              child: LeaveApprovalsView(onLeaveProcessed: () => callbacks++),
            ),
          ),
        ),
      ),
    );
    await flush(t);
  }

  Future<void> finish(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump();
  }

  for (final width in [320.0, 360.0, 390.0, 768.0]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets(
        'leave actions fit width $width text scale $scale',
        (t) async => f.run(() async {
          await show(t, width: width, scale: scale);
          expect(find.text('Employee One'), findsOneWidget);
          expect(find.text('Approve'), findsNWidgets(2));
          expect(t.takeException(), isNull);
          await finish(t);
        }),
      );
    }
  }
  testWidgets(
    'another row cannot interrupt an owned action with a busy error',
    (t) async => f.run(() async {
      await show(t);
      final reply = Completer<http.Response>();
      f.respond = (r) async => r.url.path.endsWith('/action')
          ? reply.future
          : attendanceResponse({'success': true, 'data': leaveBatchDocument()});
      await t.tap(find.text('Approve').first);
      await flush(t);
      if (find.text('Approve').evaluate().isNotEmpty) {
        await t.tap(find.text('Approve').last);
        await flush(t);
      }
      final hadBusy = find
          .textContaining('already in progress')
          .evaluate()
          .isNotEmpty;
      reply.complete(attendanceResponse(leaveBatchSuccess()));
      await flush(t);
      expect(hadBusy, false);
      expect(f.requests.where((r) => r.url.path.endsWith('/action')).length, 1);
      await finish(t);
    }),
  );
  testWidgets(
    'refresh during action does not admit a competing pending read',
    (t) async => f.run(() async {
      await show(t);
      final reply = Completer<http.Response>();
      f.respond = (r) async => r.url.path.endsWith('/action')
          ? reply.future
          : attendanceResponse({'success': true, 'data': leaveBatchDocument()});
      await t.tap(find.text('Approve').first);
      await flush(t);
      if (find.byIcon(CupertinoIcons.arrow_clockwise).evaluate().isNotEmpty) {
        await t.tap(find.byIcon(CupertinoIcons.arrow_clockwise));
        await flush(t);
      }
      final before = f.requests.length;
      reply.complete(attendanceResponse(leaveBatchSuccess()));
      await flush(t);
      expect(before, 2);
      expect(callbacks, 1);
      await finish(t);
    }),
  );
  testWidgets(
    'verified action plus failed refresh never invents an Approved row',
    (t) async => f.run(() async {
      await show(t);
      f.respond = (r) async => attendanceResponse(
        r.url.path.endsWith('/action')
            ? leaveBatchSuccess()
            : {'success': false, 'message': 'Read unavailable.'},
      );
      await t.tap(find.text('Approve').first);
      await flush(t);
      expect(find.text('Approved'), findsNothing);
      expect(find.textContaining('Read unavailable.'), findsOneWidget);
      expect(callbacks, 1);
      expect(
        find.textContaining('Original leave action notice.'),
        findsOneWidget,
      );
      await finish(t);
    }),
  );
  testWidgets(
    'unverified success retains original portal notice and disables actions',
    (t) async => f.run(() async {
      await show(t);
      final result = leaveBatchSuccess()..remove('verified_statuses');
      f.respond = (_) async => attendanceResponse(result);
      await t.tap(find.text('Approve').first);
      await flush(t);
      expect(callbacks, 0);
      expect(find.text('Approved'), findsNothing);
      expect(find.text('Approve'), findsNothing);
      expect(
        find.textContaining('Original leave action notice.'),
        findsWidgets,
      );
      expect(find.textContaining('App verification:'), findsWidgets);
      await finish(t);
    }),
  );
  testWidgets(
    'native rejection proof refreshes to authoritative zero',
    (t) async => f.run(() async {
      await show(t);
      f.respond = (r) async => attendanceResponse(
        r.url.path.endsWith('/action')
            ? {
                ...leaveBatchSuccess(),
                'verified_statuses': {'501': 'Rejected'},
              }
            : {
                'success': true,
                'data': {
                  'success': true,
                  'pending_count': 0,
                  'applications': [],
                },
              },
      );
      await t.tap(find.text('Reject').first);
      await flush(t);
      expect(callbacks, 1);
      expect(find.text('All Caught Up'), findsOneWidget);
      expect(find.text('Employee One'), findsNothing);
      await finish(t);
    }),
  );
  testWidgets(
    'submitting label fits 320px with 200 percent text',
    (t) async => f.run(() async {
      await show(t, width: 320, scale: 2);
      final reply = Completer<http.Response>();
      f.respond = (r) async => r.url.path.endsWith('/action')
          ? reply.future
          : attendanceResponse({'success': true, 'data': leaveBatchDocument()});
      await t.tap(find.text('Approve').first);
      await flush(t);
      final exception = t.takeException();
      reply.complete(attendanceResponse(leaveBatchSuccess()));
      await flush(t);
      expect(exception, isNull);
      await finish(t);
    }),
  );
}
