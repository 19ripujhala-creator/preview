import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../lib/tabs/teacher/modules/stafflogin/leave_apply_view.dart';
import 'staff_attendance_batch_support.dart';

Map<String, dynamic> staffHistoryRow() => {
  'sNo': '3',
  'type': 'CL',
  'leave_type_id': '1',
  'reason_id': '1',
  'reason': 'DOMESTIC / PERSONAL',
  'from_date': '13-10-2026',
  'to_date': '13-10-2026',
  'days': 0.5,
  'duration': '2',
  'dayType': '1',
  'status': 'Pending',
};
void main() {
  AutomatedTestWidgetsFlutterBinding.ensureInitialized();
  late AttendanceFixture f;
  late List<Map<String, dynamic>> rows;
  setUp(() async {
    f = AttendanceFixture();
    await f.setup();
    rows = [staffHistoryRow()];
    f.respond = (_) async => attendanceResponse({
      'success': true,
      'records': rows,
      'total': rows.length,
      'has_more': false,
    });
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
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> show(
    WidgetTester t, {
    double width = 360,
    double scale = 1,
    String user = '99',
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
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(12),
              child: user == '__hidden__' ? const SizedBox.shrink() : LeaveApplyView(
                currentUser: {'id': user, 'name': 'Employee $user'},
              ),
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
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  }

  for (final width in [320.0, 360.0, 390.0, 768.0]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets(
        'staff leave history fits width $width text scale $scale',
        (t) async => f.run(() async {
          await show(t, width: width, scale: scale);
          expect(find.text('Request Leave'), findsOneWidget);
          expect(t.takeException(), isNull);
          await finish(t);
        }),
      );
    }
  }
  for (final width in [320.0, 390.0]) {
    testWidgets(
      'staff request form fits width $width at 200 percent text',
      (t) async => f.run(() async {
        await show(t, width: width, scale: 2);
        await t.tap(find.text('Request Leave'));
        await flush(t);
        expect(find.text('Submit Request'), findsOneWidget);
        expect(t.takeException(), isNull);
        await finish(t);
        await t.pump(const Duration(milliseconds: 400));
      }),
    );
  }
  testWidgets(
    'account update replaces old history in the retained screen state',
    (t) async => f.run(() async {
      await show(t);
      expect(find.text('13-10-2026 - 13-10-2026'), findsOneWidget);
      rows = [
        {
          ...staffHistoryRow(),
          'from_date': '15-10-2026',
          'to_date': '15-10-2026',
        },
      ];
      await show(t, user: '100');
      expect(find.text('13-10-2026 - 13-10-2026'), findsNothing);
      expect(find.text('15-10-2026 - 15-10-2026'), findsOneWidget);
      expect(f.requests.length, 2);
      await finish(t);
    }),
  );
  testWidgets(
    'old account PDF completion cannot open a preview for the new account',
    (t) async => f.run(() async {
      await show(t);
      final pdf = Completer<http.Response>();
      f.respond = (r) async => r.url.path.endsWith('/leave/pdf')
          ? pdf.future
          : attendanceResponse({'success': true, 'records': [], 'total': 0});
      final action = find.byWidgetPredicate(
        (w) =>
            w is InkWell &&
            w.child is Container &&
            (w.child as Container).constraints?.maxWidth == 32,
      );
      expect(action, findsOneWidget);
      await t.tap(action);
      await flush(t);
      await show(t, user: '100');
      pdf.complete(http.Response('%PDF-native', 200));
      await flush(t);
      await t.pump(const Duration(milliseconds: 300));
      await flush(t);
      expect(find.byType(ModernLeavePdfPreviewScreen), findsNothing);
      expect(t.takeException(), isNull);
      await finish(t);
    }),
  );
  testWidgets(
    'account update closes the old leave form instead of reusing its review',
    (t) async => f.run(() async {
      await show(t);
      await t.tap(find.text('Request Leave'));
      await flush(t);
      expect(find.text('Submit Request'), findsOneWidget);
      await show(t, user: '100');
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Submit Request'), findsNothing);
      await finish(t);
    }),
  );
  testWidgets(
    'unavailable history is an error and never a verified zero',
    (t) async => f.run(() async {
      f.respond = (_) async => attendanceResponse({
        'success': false,
        'message': 'Original history unavailable.',
          'message_source': 'portal',
      });
      await show(t);
      expect(find.text('Original history unavailable.'), findsOneWidget);
      expect(find.text('No pending leaves'), findsNothing);
      await finish(t);
    }),
  );
  testWidgets(
    'malformed history success cannot become a no-pending-leaves claim',
    (t) async => f.run(() async {
      f.respond = (_) async =>
          attendanceResponse({'success': true, 'message': '', 'total': 0});
      await show(t);
      expect(find.text('No pending leaves'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
      await finish(t);
    }),
  );
  testWidgets(
    'missing duration does not invent a full-day leave count',
    (t) async => f.run(() async {
      rows = [
        staffHistoryRow()
          ..remove('days')
          ..remove('duration')
          ..remove('dayType'),
      ];
      await show(t);
      expect(find.textContaining('Full day', findRichText: true), findsNothing);
      expect(
        find.textContaining('Duration unavailable', findRichText: true),
        findsOneWidget,
      );
      await finish(t);
    }),
  );
  testWidgets(
    'known HCL history shows half a day when the grid omits days',
    (t) async => f.run(() async {
      rows = [
        {...staffHistoryRow(), 'type': 'HCL', 'leave_type_id': '12'}
          ..remove('days')
          ..remove('duration')
          ..remove('dayType'),
      ];
      await show(t);
      expect(
        find.textContaining('0.5 days', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('Full day', findRichText: true), findsNothing);
      await finish(t);
    }),
  );
  testWidgets(
    'native half-day endpoints initialize the edit form as Half day',
    (t) async => f.run(() async {
      rows = [
        {
            ...staffHistoryRow(),
            'from_duration': 'Half',
            'to_duration': 'Half',
            'from_day_type': 'Afternoon',
            'to_day_type': 'Afternoon',
          }
          ..remove('days')
          ..remove('duration')
          ..remove('dayType'),
      ];
      await show(t);
      await t.tap(find.text('Edit'));
      await flush(t);
      expect(find.text('Half day'), findsWidgets);
      expect(find.text('Afternoon'), findsWidgets);
      expect(t.takeException(), isNull);
      await finish(t);
      await t.pump(const Duration(milliseconds: 400));
    }),
  );
  testWidgets(
    'confirmation review fits a 320px screen at 200 percent text',
    (t) async => f.run(() async {
      await show(t, width: 320, scale: 2);
      await t.tap(find.text('Edit'));
      await flush(t);
      await t.tap(find.text('Update Request'));
      await flush(t);
      expect(find.text('Confirm & Apply'), findsOneWidget);
      expect(t.takeException(), isNull);
      await finish(t);
      await t.pump(const Duration(milliseconds: 400));
    }),
  );
  testWidgets(
    'native failed Apply remains original portal text in the form',
    (t) async => f.run(() async {
      await show(t);
      await t.tap(find.text('Edit'));
      await flush(t);
      await t.tap(find.text('Update Request'));
      await flush(t);
      f.respond = (r) async => attendanceResponse({
        'success': false,
        'code': 'PORTAL_MESSAGE',
        'message': 'Exact original leave validation.',
        'message_source': 'portal',
        'submission_attempted': false,
      });
      await t.tap(find.text('Confirm & Apply'));
      await flush(t);
      expect(find.text('Exact original leave validation.'), findsOneWidget);
      expect(find.text('App: Exact original leave validation.'), findsNothing);
      final post = f.requests.singleWhere((r) => r.method == 'POST');
      final body = jsonDecode(post.body) as Map;
      expect(body['from_duration'], 'Half');
      expect(body['to_duration'], 'Half');
      expect(body['day_type'], '1');
      await finish(t);
      await t.pump(const Duration(milliseconds: 400));
    }),
  );
  testWidgets(
    'unknown half-day period must be chosen explicitly before review',
    (t) async => f.run(() async {
      rows = [
        {...staffHistoryRow(), 'type': 'HCL', 'leave_type_id': '12'}
          ..remove('dayType'),
      ];
      await show(t);
      await t.tap(find.text('Edit'));
      await flush(t);
      await t.tap(find.text('Update Request'));
      await flush(t);
      expect(find.text('Select period'), findsOneWidget);
      expect(find.text('Confirm & Apply'), findsNothing);
      expect(f.requests.where((r) => r.method == 'POST'), isEmpty);
      await finish(t);
      await t.pump(const Duration(milliseconds: 400));
    }),
  );
  testWidgets(
    'two separate half-day endpoints are not silently converted by Edit',
    (t) async => f.run(() async {
      rows = [
        {
          ...staffHistoryRow(),
          'to_date': '15-10-2026',
          'days': 2,
          'from_duration': 'Half',
          'to_duration': 'Half',
          'from_day_type': 'Afternoon',
          'to_day_type': 'Forenoon',
        },
      ];
      await show(t);
      await t.tap(find.text('Edit'));
      await flush(t);
      expect(find.text('Update Request'), findsNothing);
      expect(
        find.textContaining('separate half-day endpoints'),
        findsOneWidget,
      );
      await finish(t);
      await t.pump(const Duration(milliseconds: 400));
    }),
  );
  testWidgets(
    'incomplete full history cannot report a complete empty list',
    (t) async => f.run(() async {
      f.respond = (_) async => attendanceResponse({
        'success': true,
        'records': [],
        'total': 12,
        'has_more': true,
      });
      await show(t);
      expect(find.text('No pending leaves'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
      await finish(t);
    }),
  );
  testWidgets(
    'rapid review callbacks open just one confirmation route',
    (t) async => f.run(() async {
      await show(t);
      await t.tap(find.text('Edit'));
      await flush(t);
      final button = t.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Update Request'),
      );
      button.onPressed!();
      button.onPressed!();
      await flush(t);
      expect(find.text('Confirm & Apply', skipOffstage: false), findsOneWidget);
      await finish(t);
      await t.pump(const Duration(milliseconds: 400));
    }),
  );
  testWidgets(
    'late Pending read cannot replace a newer All history result',
    (t) async => f.run(() async {
      final pending = Completer<http.Response>();
      f.respond = (r) async => r.url.queryParameters['filter'] == 'pending'
          ? pending.future
          : attendanceResponse({
              'success': true,
              'records': [
                {...staffHistoryRow(), 'from_date': '20-10-2026'},
              ],
              'total': 1,
            });
      await show(t);
      await t.tap(find.text('All'));
      await flush(t);
      pending.complete(
        attendanceResponse({'success': true, 'records': rows, 'total': 1}),
      );
      await flush(t);
      expect(find.text('20-10-2026 - 13-10-2026'), findsOneWidget);
      expect(find.text('13-10-2026 - 13-10-2026'), findsNothing);
      await finish(t);
    }),
  );
 testWidgets('account change closes nested selectors and ignores their late callback',(t)async=>f.run(()async{
  await show(t);await t.tap(find.text('Edit'));await flush(t);
  await t.tap(find.text('DOMESTIC / PERSONAL'));await flush(t);
  expect(find.text('Select Leave Reason'),findsOneWidget);
  final item=t.widget<InkWell>(find.widgetWithText(InkWell,'CASUAL / INCIDENTAL'));
  await show(t,user:'100');await t.pump(const Duration(milliseconds:400));
  expect(find.text('Select Leave Reason'),findsNothing);expect(find.text('Update Request'),findsNothing);
  item.onTap!();await flush(t);expect(t.takeException(),isNull);await finish(t);
 }));
 testWidgets('account change closes a calendar owned by the previous form',(t)async=>f.run(()async{
  await show(t);await t.tap(find.text('Edit'));await flush(t);
  await t.tap(find.text('13-10-2026').first);await flush(t);expect(find.byType(Dialog),findsNWidgets(2));
  await show(t,user:'100');await t.pump(const Duration(milliseconds:400));
  expect(find.byType(Dialog),findsNothing);expect(t.takeException(),isNull);await finish(t);
 }));

 testWidgets('removing the leave screen also dismisses its open form',(t)async=>f.run(()async{
  await show(t);await t.tap(find.text('Edit'));await flush(t);expect(find.byType(Dialog),findsOneWidget);
  await show(t,user:'__hidden__');await t.pump(const Duration(milliseconds:400));
  expect(find.byType(Dialog),findsNothing);expect(t.takeException(),isNull);await finish(t);
 }));

}
