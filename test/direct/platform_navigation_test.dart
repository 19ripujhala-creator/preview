import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaladarpan/widgets/page_transitions.dart';

Future<void> onPlatform(
  WidgetTester t,
  TargetPlatform platform,
  Future<void> Function() body,
) async {
  final previous = debugDefaultTargetPlatformOverride;
  debugDefaultTargetPlatformOverride = platform;
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = const Size(390, 720);
  try {
    await body();
  } finally {
    await t.pumpWidget(const SizedBox());
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
    debugDefaultTargetPlatformOverride = previous;
  }
}

Widget app(GlobalKey<NavigatorState> nav) => MaterialApp(
  navigatorKey: nav,
  theme: ThemeData(pageTransitionsTheme: desktopPageTransitions),
  home: const Scaffold(body: Text('parent')),
);
Future<void> gesture(WidgetTester t, String method, [double? progress]) async {
  final data = const StandardMethodCodec().encodeMethodCall(
    MethodCall(
      method,
      progress == null
          ? null
          : {
              'touchOffset': [5.0 + progress * 300, 300.0],
              'progress': progress,
              'swipeEdge': 0,
            },
    ),
  );
  // Exercise the same system channel used by the installed SDK's own tests.
  // ignore: deprecated_member_use
  await t.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/backgesture',
    data,
    (ByteData? _) {},
  );
}

double pageOpacity(WidgetTester tester, Finder page) => tester
    .widgetList<FadeTransition>(
      find.ancestor(of: page, matching: find.byType(FadeTransition)),
    )
    .fold<double>(1, (value, fade) => value * fade.opacity.value);

void main() {
  AutomatedTestWidgetsFlutterBinding.ensureInitialized();
  test('route factory preserves settings and selects native routes', () {
    final previous = debugDefaultTargetPlatformOverride;
    try {
      for (final platform in TargetPlatform.values) {
        debugDefaultTargetPlatformOverride = platform;
        const settings = RouteSettings(name: '/details', arguments: 9);
        final route = appPageRoute<int>(
          builder: (_) => const Scaffold(),
          settings: settings,
        );
        expect(route.settings, same(settings));
        if (platform == TargetPlatform.iOS ||
            platform == TargetPlatform.macOS) {
          expect(route, isA<CupertinoPageRoute<int>>());
        } else {
          expect(route, isA<MaterialPageRoute<int>>());
        }
      }
    } finally {
      debugDefaultTargetPlatformOverride = previous;
    }
  });
  for (final commit in [false, true]) {
    testWidgets(
      'Android predictive back ${commit ? 'commit' : 'cancel'} preserves navigation',
      (t) => onPlatform(t, TargetPlatform.android, () async {
        final nav = GlobalKey<NavigatorState>();
        await t.pumpWidget(app(nav));
        final route = appPageRoute<int>(
          builder: (_) => const Scaffold(body: Text('child')),
        );
        var returned = false;
        final result = nav.currentState!.push(route).then((v) {
          returned = true;
          return v;
        });
        await t.pumpAndSettle();
        await gesture(t, 'startBackGesture', 0);
        await t.pump();
        expect(nav.currentState!.userGestureInProgress, isTrue);
        await gesture(t, 'updateBackGestureProgress', .4);
        await t.pumpAndSettle();
        await gesture(t, commit ? 'commitBackGesture' : 'cancelBackGesture');
        await t.pumpAndSettle();
        if (commit) {
          expect(returned, isTrue);
          expect(find.text('child'), findsNothing);
        } else {
          expect(returned, isFalse);
          expect(find.text('child'), findsOneWidget);
          nav.currentState!.pop(5);
          await t.pumpAndSettle();
          expect(await result, 5);
        }
        expect(find.text('parent'), findsOneWidget);
        expect(t.takeException(), isNull);
      }),
    );
  }
  for (final commit in [false, true]) {
    testWidgets(
      'iOS edge swipe ${commit ? 'commit' : 'cancel'} uses native route',
      (t) => onPlatform(t, TargetPlatform.iOS, () async {
        final nav = GlobalKey<NavigatorState>();
        await t.pumpWidget(app(nav));
        final route = appPageRoute<int>(
          builder: (_) => const Scaffold(body: Text('child')),
        );
        var returned = false;
        final result = nav.currentState!.push(route).then((v) {
          returned = true;
          return v;
        });
        await t.pumpAndSettle();
        expect(route.popGestureEnabled, isTrue);
        if (commit) {
          await t.dragFrom(const Offset(1, 360), const Offset(350, 0));
        } else {
          final drag = await t.startGesture(const Offset(1, 360));
          await drag.moveBy(const Offset(30, 0));
          await t.pump(const Duration(milliseconds: 50));
          await drag.moveBy(const Offset(-20, 0));
          await t.pump(const Duration(milliseconds: 500));
          await drag.up();
        }
        await t.pumpAndSettle();
        if (commit) {
          expect(returned, isTrue);
        } else {
          expect(returned, isFalse);
          expect(find.text('child'), findsOneWidget);
          nav.currentState!.pop(8);
          await t.pumpAndSettle();
          expect(await result, 8);
        }
        expect(find.text('parent'), findsOneWidget);
        expect(t.takeException(), isNull);
      }),
    );
  }
  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    testWidgets(
      'unsaved form blocks back on $platform',
      (t) => onPlatform(t, platform, () async {
        final nav = GlobalKey<NavigatorState>();
        await t.pumpWidget(app(nav));
        final route = appPageRoute<void>(
          builder: (_) => const PopScope(
            canPop: false,
            child: Scaffold(body: Text('protected')),
          ),
        );
        nav.currentState!.push(route);
        await t.pumpAndSettle();
        await nav.currentState!.maybePop();
        await t.pumpAndSettle();
        expect(find.text('protected'), findsOneWidget);
        if (platform == TargetPlatform.iOS) {
          expect(route.popGestureEnabled, isFalse);
        }
        nav.currentState!.pop();
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      }),
    );
  }
  testWidgets(
    'Windows back fades without spatial movement',
    (t) => onPlatform(t, TargetPlatform.windows, () async {
      final nav = GlobalKey<NavigatorState>();
      await t.pumpWidget(app(nav));
      const key = ValueKey('page');
      final route = appPageRoute<void>(
        builder: (_) => const Scaffold(body: SizedBox.expand(key: key)),
      );
      nav.currentState!.push(route);
      await t.pumpAndSettle();
      expect(route.transitionDuration, const Duration(milliseconds: 220));
      expect(
        route.reverseTransitionDuration,
        const Duration(milliseconds: 180),
      );
      nav.currentState!.pop();
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(t.getTopLeft(find.byKey(key)).dx, 0);
      final fade = pageOpacity(t, find.byKey(key));
      expect(fade, greaterThan(0));
      expect(fade, lessThan(1));
      expect(t.getTopLeft(find.byKey(key)).dy, 0);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    }),
  );
  testWidgets(
    'Windows reverse during entrance preserves opacity without a leaked ticker',
    (t) => onPlatform(t, TargetPlatform.windows, () async {
      final nav = GlobalKey<NavigatorState>();
      await t.pumpWidget(app(nav));
      const key = ValueKey('page');
      nav.currentState!.push(
        appPageRoute<void>(
          builder: (_) => const Scaffold(body: SizedBox.expand(key: key)),
        ),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 90));
      final before = t.getTopLeft(find.byKey(key));
      double opacity() => pageOpacity(t, find.byKey(key));
      final opacityBefore = opacity();
      nav.currentState!.pop();
      await t.pump();
      expect((t.getTopLeft(find.byKey(key)) - before).distance, lessThan(.01));
      expect(opacity(), closeTo(opacityBefore, .0001));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    }),
  );
}
