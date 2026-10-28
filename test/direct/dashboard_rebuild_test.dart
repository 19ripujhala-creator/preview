import 'package:shaladarpan/experiments/direct_school_session.dart';
import 'package:shaladarpan/services/portals/shaladarpan/student_service.dart';
import 'student_worker_test.dart' show FakeAuth, FakePortal;
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shaladarpan/dashboard.dart';
import 'package:shaladarpan/tabs/teacher/teacher.dart';
import 'package:shaladarpan/tabs/teacher/shaladarpan.dart';
import 'package:shaladarpan/tabs/account/account.dart';
import 'package:shaladarpan/widgets/page_transitions.dart';

class _Assets extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin') {
      return const StandardMessageCodec().encodeMessage(<String, Object>{})!;
    }
    if (key == 'AssetManifest.json') {
      return ByteData.sublistView(Uint8List.fromList('{}'.codeUnits));
    }
    final file = File(key);
    return ByteData.sublistView(
      file.existsSync()
          ? file.readAsBytesSync()
          : base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aY9sAAAAASUVORK5CYII=',
            ),
    );
  }
}

Future<void> frames(WidgetTester t, [int count = 20]) async {
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 20));
  }
}

class PriorityDashboardAuth extends FakeAuth {
  PriorityDashboardAuth(super.portal);
  @override String get authenticatedSchoolId => '123456';
  @override String get schoolSessionIdentity => 'priority-fixture';
}
void main() {
  AutomatedTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('attendance foreground defers dashboard reads and disposal drops deferred work', (t) async {
    t.view.devicePixelRatio = 1; t.view.physicalSize = const Size(1440, 1000);
    await t.runAsync(() async {
      final loader = FontLoader('PlusJakartaSans');
      for (final weight in ['Regular', 'SemiBold', 'Bold']) {
        loader.addFont(Future.value(ByteData.sublistView(
          File('assets/fonts/PlusJakartaSans-$weight.ttf').readAsBytesSync())));
      }
      await loader.load();
    });
    SharedPreferences.setMockInitialValues({'saved_school_id': '123456'});
    const storage = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(storage, (call) async => call.method == 'read' ? '{}' : null);
    final portal = FakePortal();
    DirectSchoolSession.attach(PriorityDashboardAuth(portal), '123456');
    StudentService.directAttendanceEnabled = true;
    final release = DirectSchoolSession.attendance!.acquireForeground();
    var requests = 0;
    try {
      await http.runWithClient(() async {
        await t.pumpWidget(DefaultAssetBundle(bundle: _Assets(), child: MaterialApp(
          home: DashboardScreen(schoolId: '123456', onLogoutRequested: () {}))));
        await frames(t, 40);
        expect(requests, 0); expect(portal.requests, isEmpty);
        await t.pumpWidget(const SizedBox()); release(); await frames(t, 20);
        expect(requests, 0); expect(portal.requests, isEmpty);
      }, () => MockClient((_) async { requests++; return http.Response('{"success":false}', 503); }));
      expect(t.takeException(), isNull);
    } finally {
      release(); DirectSchoolSession.reset(); StudentService.directAttendanceEnabled = false;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(storage, null);
      await t.pumpWidget(const SizedBox()); t.view.resetPhysicalSize(); t.view.resetDevicePixelRatio();
    }
  });
  testWidgets(
    'dashboard refresh preserves tab work, inputs and navigation during back',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1440, 1000);
      final navigator = GlobalKey<NavigatorState>();
      var logoutCalls = 0;
      void initialLogout() {}
      void updatedLogout() {
        logoutCalls++;
      }

      Widget appFor(String school, VoidCallback logout) => DefaultAssetBundle(
        bundle: _Assets(),
        child: MaterialApp(
          navigatorKey: navigator,
          theme: ThemeData(pageTransitionsTheme: desktopPageTransitions),
          home: DashboardScreen(schoolId: school, onLogoutRequested: logout),
        ),
      );
      await t.runAsync(() async {
        final loader = FontLoader('PlusJakartaSans');
        for (final weight in ['Regular', 'SemiBold', 'Bold']) {
          loader.addFont(
            Future.value(
              ByteData.sublistView(
                File('assets/fonts/PlusJakartaSans-$weight.ttf')
                    .readAsBytesSync(),
              ),
            ),
          );
        }
        await loader.load();
      });
      SharedPreferences.setMockInitialValues({'saved_school_id': '123456'});
      const storage = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        storage,
        (call) async => call.method == 'read' ? '{}' : null,
      );
      final counts = <String, int>{};
      final old = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (e, builtOnce) {
        if (e.widget is TeacherTabScreen ||
            e.widget is AccountTabView ||
            e.widget is DashboardScreen) {
          final n = e.widget.runtimeType.toString();
          counts.update(n, (v) => v + 1, ifAbsent: () => 1);
        }
      };
      try {
        await http.runWithClient(
          () async {
            await t.pumpWidget(appFor('123456', initialLogout));
            await frames(t);
            await t.tap(find.text('Teacher').last);
            await frames(t);
            await t.tap(find.text('Account').last);
            await frames(t);
            debugPrintSynchronously('INITIAL_BUILD_COUNTS $counts');
            counts.clear();
            final dashboard = t.element(find.byType(DashboardScreen));
            // Model a status-notification rebuild without changing navigation inputs.
            dashboard.markNeedsBuild();
            await frames(t, 2);
            debugPrintSynchronously('UNRELATED_REFRESH_COUNTS $counts');
            expect(counts['TeacherTabScreen'] ?? 0, 0);
            expect(counts['AccountTabView'] ?? 0, 0);
            counts.clear();
            await t.ensureVisible(find.text('About app'));
            await t.tap(find.text('About app'));
            await frames(t);
            navigator.currentState!.pop();
            await t.pump(const Duration(milliseconds: 60));
            dashboard.markNeedsBuild();
            await frames(t);
            expect(counts['TeacherTabScreen'] ?? 0, 0);
            expect(counts['AccountTabView'] ?? 0, 0);
            debugPrintSynchronously('BACK_COUNTS $counts');
            final teacherElement = t.element(
              find.byType(TeacherTabScreen, skipOffstage: false),
            );
            final accountElement = t.element(
              find.byType(AccountTabView, skipOffstage: false),
            );
            await t.pumpWidget(appFor('654321', updatedLogout));
            await frames(t);
            final teacher = t.widget<TeacherTabScreen>(
              find.byType(TeacherTabScreen, skipOffstage: false),
            );
            final account = t.widget<AccountTabView>(
              find.byType(AccountTabView, skipOffstage: false),
            );
            expect(teacher.schoolId, '654321');
            expect(account.schoolId, '654321');
            expect(
              t.element(find.byType(TeacherTabScreen, skipOffstage: false)),
              same(teacherElement),
            );
            expect(
              t.element(find.byType(AccountTabView, skipOffstage: false)),
              same(accountElement),
            );
            account.onLogoutRequested();
            expect(logoutCalls, 1);
            final oldModuleKey = t
                .widget<ShaladarpanView>(
                  find.byType(ShaladarpanView, skipOffstage: false),
                )
                .key;
            await t.tap(find.text('Home').last);
            await frames(t);
            await t.ensureVisible(find.text('Staff Attendance').first);
            await t.tap(find.text('Staff Attendance').hitTestable().first);
            await frames(t);
            final updatedModule = t.widget<ShaladarpanView>(
              find.byType(ShaladarpanView, skipOffstage: false),
            );
            expect(updatedModule.key, isNot(oldModuleKey));
            expect(updatedModule.schoolId, '654321');

            await t.pumpWidget(const SizedBox());
            await t.pump(const Duration(seconds: 5));
          },
          () => MockClient(
            (_) async => http.Response(
              '{"success":false,"message":"Offline fixture"}',
              503,
              headers: {'content-type': 'application/json'},
            ),
          ),
        );
        expect(t.takeException(), isNull);
      } finally {
        debugOnRebuildDirtyWidget = old;
        t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          storage,
          null,
        );
        await t.pumpWidget(const SizedBox());
        t.view.resetPhysicalSize();
        t.view.resetDevicePixelRatio();
      }
    },
  );
}
