import 'package:flutter_test/flutter_test.dart';
import 'package:shaladarpan/services/portals/shaladarpan/dashboard_bootstrap.dart';

void main() {
  late int calls;
  setUp(() {
    calls = 0;
    DashboardBootstrap.resetForTest();
  });
  tearDown(DashboardBootstrap.resetForTest);

  test('failed dashboard load is not cached; the next call retries', () async {
    DashboardBootstrap.dashboardLoader =
        ({
          bool forceRefresh = false,
          void Function(double, String)? onProgress,
        }) async {
          calls++;
          return calls == 1
              ? <String, dynamic>{'success': false, 'code': 'SESSION_EXPIRED'}
              : <String, dynamic>{'success': true};
        };
    final first = await DashboardBootstrap.load('123456');
    expect(first['success'], false);
    final second = await DashboardBootstrap.load('123456');
    expect(calls, 2);
    expect(second['success'], true);
    // A successful load is still shared inside the two-minute window.
    final third = await DashboardBootstrap.load('123456');
    expect(calls, 2);
    expect(third['success'], true);
  });

  test('thrown dashboard load is not cached; the next call retries', () async {
    DashboardBootstrap.dashboardLoader =
        ({
          bool forceRefresh = false,
          void Function(double, String)? onProgress,
        }) async {
          calls++;
          if (calls == 1) throw StateError('portal unreachable');
          return <String, dynamic>{'success': true};
        };
    await expectLater(
      DashboardBootstrap.load('123456'),
      throwsA(isA<StateError>()),
    );
    final second = await DashboardBootstrap.load('123456');
    expect(calls, 2);
    expect(second['success'], true);
  });

  test('concurrent callers share one in-flight load', () async {
    DashboardBootstrap.dashboardLoader =
        ({
          bool forceRefresh = false,
          void Function(double, String)? onProgress,
        }) async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return <String, dynamic>{'success': true};
        };
    final results = await Future.wait([
      DashboardBootstrap.load('123456'),
      DashboardBootstrap.load('123456'),
    ]);
    expect(calls, 1);
    expect(results.every((r) => r['success'] == true), true);
  });

  test('partial dashboard failure retries the next call', () async {
    DashboardBootstrap.dashboardLoader =
        ({
          bool forceRefresh = false,
          void Function(double, String)? onProgress,
        }) async {
          calls++;
          return calls == 1
              ? <String, dynamic>{'success': false, 'partial': true}
              : <String, dynamic>{'success': true};
        };
    expect((await DashboardBootstrap.load('123456'))['partial'], true);
    expect((await DashboardBootstrap.load('123456'))['success'], true);
    expect(calls, 2);
  });
}
