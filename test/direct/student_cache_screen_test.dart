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
  var secureReads = 0;
  setUp(() {
    SecureStorageService.invalidateSchoolIdentity();
    SharedPreferences.setMockInitialValues({});
    secureReads = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'read') {
            secureReads++;
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
  Future<void> open(WidgetTester t, _Portal p, {Size size = const Size(430, 850)}) async {
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

  testWidgets(
    'full UI confirmation saves once and displays verified attendance',
    (t) async {
      final p = _Portal();
      await open(t, p);
      await t.tap(find.text('Submit Attendance'));
      await t.pumpAndSettle();
      expect(find.text('Confirm & Save'), findsOneWidget);
      await t.tap(find.text('Confirm & Save'));
      await t.pumpAndSettle();
      expect(p.saves, 1);
      expect(find.text('Update Attendance'), findsOneWidget);
      expect(
        find.text('School session changed. Refresh class data before Save.'),
        findsNothing,
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('confirmation overlaps read preparation but Submit waits for it', (t) async {
    final p = _Portal(); await open(t, p);
    final gate = Completer<void>(); p.preparationGate = gate;
    final n = p.requests.length;
    await t.tap(find.text('Submit Attendance')); await t.pumpAndSettle();
    expect(find.text('Confirm & Save'), findsOneWidget);
    expect(p.saves, 0);
    await t.tap(find.text('Confirm & Save')); await t.pump(const Duration(milliseconds: 400));
    expect(p.saves, 0);
    gate.complete(); await t.pumpAndSettle();
    expect(p.saves, 1); expect(p.requests.length, greaterThan(n));
    expect(find.text('Update Attendance'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('cancelling confirmation after read preparation sends no Submit', (t) async {
    final p = _Portal(); await open(t, p);
    await t.tap(find.text('Submit Attendance')); await t.pumpAndSettle();
    expect(find.text('Confirm & Save'), findsOneWidget); expect(p.saves, 0);
    await t.tap(find.text('Cancel')); await t.pumpAndSettle();
    expect(p.saves, 0); expect(find.text('Confirm & Save'), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets('Cancel releases UI while preparation settles and next class read waits', (t) async {
    final p = _Portal(); await open(t, p);
    final gate = Completer<void>(); p.preparationGate = gate;
    await t.tap(find.text('Submit Attendance')); await t.pumpAndSettle();
    await t.tap(find.text('Cancel')); await t.pumpAndSettle();
    expect(p.saves, 0); expect(find.text('Confirm & Save'), findsNothing);
    await t.tap(find.text('Class 2')); await t.pump();
    gate.complete(); await t.pumpAndSettle();
    expect(find.textContaining('Alice two'), findsOneWidget);
    expect(p.saves, 0); expect(t.takeException(), isNull);
  });
  testWidgets('discard cancellation retains edits and confirmed discard restores cached originals', (t) async {
    final p = _Portal(); await open(t, p);
    await t.tap(find.text('A').first); await t.pump();
    await t.tap(find.text('Class 2')); await t.pumpAndSettle();
    expect(find.text('Keep Editing'), findsOneWidget);
    await t.tap(find.text('Keep Editing')); await t.pumpAndSettle();
    expect(find.textContaining('Alice one'), findsOneWidget);
    await t.tap(find.text('Class 2')); await t.pumpAndSettle();
    await t.tap(find.text('Discard')); await t.pumpAndSettle();
    expect(find.textContaining('Alice two'), findsOneWidget);
    await t.tap(find.text('Class 1')); await t.pumpAndSettle();
    expect(find.textContaining('Alice one'), findsOneWidget);
    await t.tap(find.text('Class 2')); await t.pumpAndSettle();
    expect(find.text('Keep Editing'), findsNothing);
    expect(find.textContaining('Alice two'), findsOneWidget);
    expect(p.saves, 0); expect(t.takeException(), isNull);
  });
  for (final size in [const Size(320, 640), const Size(960, 720)]) {
    testWidgets('attendance and confirmation fit ${size.width}px without layout exceptions', (t) async {
      final p = _Portal(); await open(t, p, size: size);
      await t.tap(find.text('Submit Attendance')); await t.pumpAndSettle();
      expect(find.text('Confirm & Save'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.tap(find.text('Cancel')); await t.pumpAndSettle();
      expect(p.saves, 0); expect(t.takeException(), isNull);
    });
  }
  testWidgets('Save preserves another class cache and saved class default cache for immediate return', (t) async {
    final p = _Portal(); await open(t, p);
    await t.tap(find.text('Class 2')); await t.pumpAndSettle();
    await t.tap(find.text('Submit Attendance')); await t.pumpAndSettle();
    await t.tap(find.text('Confirm & Save')); await t.pumpAndSettle();
    expect(p.saves, 1);
    final n = p.requests.length;
    await t.tap(find.text('Class 1')); await t.pump();
    expect(find.textContaining('Alice one'), findsOneWidget);
    expect(p.requests.length, n);
    await t.tap(find.text('Class 2')); await t.pump();
    expect(find.textContaining('Alice two'), findsOneWidget);
    expect(find.text('Update Attendance'), findsOneWidget);
    expect(p.requests.length, n); expect(t.takeException(), isNull);
  });
  testWidgets(
    'returning to cached class renders immediately without storage or HTTP',
    (t) async {
      final p = _Portal();
      await open(t, p);
      await t.tap(find.text('Class 2'));
      await t.pumpAndSettle();
      expect(find.textContaining('Alice two'), findsOneWidget);
      final calls = p.requests.length, reads = secureReads;
      await t.tap(find.text('Class 1'));
      await t.pump();
      expect(find.textContaining('Alice one'), findsOneWidget);
      expect(find.textContaining('Alice two'), findsNothing);
      expect(p.requests.length, calls);
      expect(secureReads, reads);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'cached class is not blocked by active other-class read or overwritten by late completion',
    (t) async {
      final p = _Portal();
      await open(t, p);
      p.secondGate = Completer<void>();
      await t.tap(find.text('Class 2'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 30));
      await t.tap(find.text('Class 1'));
      await t.pump();
      expect(find.textContaining('Alice one'), findsOneWidget);
      p.secondGate!.complete();
      await t.pumpAndSettle();
      expect(find.textContaining('Alice one'), findsOneWidget);
      expect(find.textContaining('Alice two'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'portal summary status change invalidates stale pending class cache automatically',
    (t) async {
      final p = _Portal();
      await open(t, p);
      expect(find.text('Submit Attendance'), findsOneWidget);
      // Another teacher marks attendance on the portal while user switches to Class 2.
      p.marked = true;
      p.saved = true;
      await t.tap(find.text('Class 2'));
      await t.pumpAndSettle();
      expect(find.textContaining('Alice two'), findsOneWidget);
      final beforeReturn = p.requests.length;
      // Returning to Class 1 must not serve the stale Pending cache because
      // the latest portal summary during Class 2 load reported Class 1 as Done.
      await t.tap(find.text('Class 1'));
      await t.pumpAndSettle();
      expect(p.requests.length, greaterThan(beforeReturn));
      expect(find.text('Update Attendance'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  test('StudentRecord maps missing or unrecognised status to Unavailable unless today pending draft default is active', () {
    final missingDefault = StudentRecord.fromJson(
      {'serialNo': 1, 'srNo': '101', 'name': 'Alice', 'status': null, 'present': false},
      'Class 1',
      'A',
      1,
    );
    expect(missingDefault.attendanceStatus, 'Unavailable');
    expect(missingDefault.toJson()['status'], 'Unavailable');
    expect(missingDefault.toJson()['present'], false);

    final pendingDraft = StudentRecord.fromJson(
      {'serialNo': 1, 'srNo': '101', 'name': 'Alice', 'status': null, 'present': false},
      'Class 1',
      'A',
      1,
      defaultDraftPresent: true,
    );
    expect(pendingDraft.attendanceStatus, 'P');
    expect(pendingDraft.toJson()['status'], 'Present');

    final unrecognisedInDraft = StudentRecord.fromJson(
      {'serialNo': 1, 'srNo': '101', 'name': 'Alice', 'status': 'UnknownValue', 'present': true},
      'Class 1',
      'A',
      1,
      defaultDraftPresent: true,
    );
    expect(unrecognisedInDraft.attendanceStatus, 'Unavailable');
    expect(unrecognisedInDraft.toJson()['status'], 'Unavailable');
  });
}
