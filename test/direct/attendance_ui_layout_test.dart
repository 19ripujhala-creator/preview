import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shaladarpan/experiments/direct_school_session.dart';
import 'package:shaladarpan/services/core/secure_storage_service.dart';
import 'package:shaladarpan/services/portals/shaladarpan/student_service.dart';
import 'package:shaladarpan/services/portals/shaladarpan/direct/student_attendance_worker.dart';
import 'package:shaladarpan/tabs/student/modules/student_attendance/screens/daily_attendance_sheet_screen.dart';

import 'package:shaladarpan/tabs/student/modules/student_attendance/attendance_edit_policy.dart';

import 'student_worker_test.dart' show FakeAuth, FakePortal, date;

class _Assets extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin')
      return const StandardMessageCodec().encodeMessage(<String, Object>{})!;
    return ByteData.sublistView(File(key).readAsBytesSync());
  }
}

class _Auth extends FakeAuth {
  _Auth(super.portal);
  @override
  String get authenticatedSchoolId => '123';
  @override
  String get schoolSessionIdentity => 'school-session';
}

class _Portal extends FakePortal {
  String selectedDate = date;
  bool second = false;
  Completer<void>? secondGate;
  Completer<void>? preparationGate;
  @override
  String summary() {
    final doc = html.parse(super.summary().replaceAll(date, selectedDate));
    final grid = doc.getElementById('ContentPlaceHolder1_grd_Student')!;
    final row = grid.querySelector('tr')!;
    // HTML fragment parsing strips table-only nodes; use a temporary full table.
    final extra = html
        .parse(
          '<table>${row.outerHtml.replaceAll('_0', '_1').replaceAll('ctl02', 'ctl03')}</table>',
        )
        .querySelector('tr')!;
    extra.querySelector('input')!.attributes['value'] = '2';
    extra.querySelector('a')!.text = '2A';
    row.parent!.nodes.insert(row.parent!.nodes.indexOf(row) + 1, extra);
    return doc.outerHtml;
  }

  @override
  String entry() =>
      super.entry().replaceAll('Alice', second ? 'Alice two' : 'Alice one');
  @override
  Future<AttendanceHttpReply> request(
    Uri url, {
    Map<String, Object?>? fields,
    Uri? referer,
    bool mutation = false,
  }) async {
    if (fields?['__READ_ONLY_ACTION'] == 'SHOW')
      selectedDate = '${fields![r'ctl00$ContentPlaceHolder1$txtdate']}';
    if (fields?['__READ_ONLY_ACTION'] == 'CLASS_ENTRY') {
      second = '${fields!['__EVENTTARGET']}'.contains('ctl03');
      if (second && secondGate != null) await secondGate!.future;
      final gate = preparationGate;
      preparationGate = null;
      if (gate != null) await gate.future;
    }
    return super.request(
      url,
      fields: fields,
      referer: referer,
      mutation: mutation,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  setUp(() {
    SecureStorageService.invalidateSchoolIdentity();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'read') {
            return jsonEncode({'shala_id': '123', 'shala_pass': 'fixture'});
          }
          return null;
        });
    StudentService.directAttendanceEnabled = true;
  });
  tearDown(() {
    DirectSchoolSession.reset();
    StudentService.directAttendanceEnabled = false;
    SecureStorageService.invalidateSchoolIdentity();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  Future<void> open(
    WidgetTester t,
    _Portal p, {
    Size size = const Size(430, 850),
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.runAsync(() async {
      final loader = FontLoader('PlusJakartaSans');
      for (final w in ['Regular', 'SemiBold', 'Bold'])
        loader.addFont(
          Future.value(
            ByteData.sublistView(
              File('assets/fonts/PlusJakartaSans-$w.ttf').readAsBytesSync(),
            ),
          ),
        );
      await loader.load();
    });
    DirectSchoolSession.attach(_Auth(p), '123');
    await t.pumpWidget(
      DefaultAssetBundle(
        bundle: _Assets(),
        child: MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: const DailyAttendanceSheetScreen(),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.textContaining('Alice one'), findsOneWidget);
  }

  for (final size in [
    const Size(320, 640),
    const Size(430, 850),
    const Size(960, 720),
    const Size(1920, 1080),
  ]) {
    testWidgets('attendance layout and action fit ${size.width}px', (t) async {
      final p = _Portal();
      await open(t, p, size: size);
      final action = find.text('Submit Attendance');
      await t.ensureVisible(action);
      await t.pumpAndSettle();
      expect(
        t.getRect(find.byType(CustomScrollView)).width,
        lessThanOrEqualTo(1280),
      );
      final canvas = t.getRect(
        find.byKey(const ValueKey('attendance-workspace')),
      );
      final header = t.getRect(
        find.byKey(const ValueKey('attendance-page-header-canvas')),
      );
      expect(header.left, canvas.left);
      expect(header.width, canvas.width);
      expect(t.getRect(action).top, greaterThan(size.height - 100));
      await t.tap(action);
      await t.pumpAndSettle();
      expect(find.text('Confirm & Save'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(p.saves, 0);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump();
    });
  }
  for (final marked in [false, true]) {
    testWidgets('past attendance is locked, marked=$marked', (t) async {
      final p = _Portal();
      await open(t, p);
      p.marked = marked;
      await t.tap(find.byKey(const ValueKey('attendance-date-picker')));
      await t.pumpAndSettle();
      final now = attendanceToday();
      if (now.day > 1) {
        await t.tap(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.text('${now.day - 1}'),
          ),
        );
      } else {
        await t.tap(find.byType(PopupMenuButton<int>).last);
        await t.pumpAndSettle();
        await t.tap(find.text('${now.year - 1}').last);
      }
      await t.pumpAndSettle();
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      expect(find.text('Attendance Locked'), findsOneWidget);
      expect(find.text('Update Attendance'), findsNothing);
      expect(find.text('Submit Attendance'), findsNothing);
      final selector = find
          .ancestor(
            of: find.text('A').first,
            matching: find.byType(GestureDetector),
          )
          .first;
      expect(t.widget<GestureDetector>(selector).onTap, isNull);
      await t.tap(find.text('Attendance Locked'));
      await t.pumpAndSettle();
      expect(find.text('Confirm & Save'), findsNothing);
      expect(p.saves, 0);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump();
    });
  }
}
