import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaladarpan/widgets/page_transitions.dart';
import 'package:shaladarpan/widgets/route_completion.dart';

double pageOpacity(WidgetTester tester, Finder page) => tester
    .widgetList<FadeTransition>(
      find.ancestor(of: page, matching: find.byType(FadeTransition)),
    )
    .fold<double>(1, (value, fade) => value * fade.opacity.value);

void main() {
  AutomatedTestWidgetsFlutterBinding.ensureInitialized();
  test('non-Windows platform builders retain SDK defaults', () {
    final defaults = const PageTransitionsTheme().builders;
    for (final platform in TargetPlatform.values) {
      if (platform == TargetPlatform.windows) {
        expect(
          desktopPageTransitions.builders[platform],
          isA<StableWindowsPageTransitionsBuilder>(),
        );
      } else {
        expect(
          desktopPageTransitions.builders[platform],
          same(defaults[platform]),
        );
      }
    }
  });

  for (final width in [320.0, 390.0, 1280.0, 1920.0]) {
    for (final account in [false, true]) {
      testWidgets(
        '${account ? 'Account' : 'Material'} fades with stationary page bounds at $width',
        (t) async {
          final previousPlatform = debugDefaultTargetPlatformOverride;
          debugDefaultTargetPlatformOverride = TargetPlatform.windows;
          try {
            t.view.devicePixelRatio = 1;
            t.view.physicalSize = Size(width, 720);
            addTearDown(t.view.resetPhysicalSize);
            addTearDown(t.view.resetDevicePixelRatio);
            final nav = GlobalKey<NavigatorState>();
            final controller = TextEditingController(text: 'kept edits');
            const parentKey = ValueKey('parent');
            const childKey = ValueKey('child');
            late BuildContext home;
            await t.pumpWidget(
              MaterialApp(
                navigatorKey: nav,
                theme: ThemeData(
                  platform: TargetPlatform.windows,
                  pageTransitionsTheme: desktopPageTransitions,
                ),
                home: Builder(
                  builder: (context) {
                    home = context;
                    return Scaffold(
                      body: SizedBox.expand(
                        key: parentKey,
                        child: TextField(controller: controller),
                      ),
                    );
                  },
                ),
              ),
            );
            final parentRect = t.getRect(find.byKey(parentKey));
            final parentElement = t.element(find.byType(TextField));
            for (var i = 0; i < 2; i++) {
              Widget page(BuildContext _) => const Scaffold(
                body: SizedBox.expand(
                  key: childKey,
                  child: ColoredBox(color: Colors.white),
                ),
              );
              final PageRoute<int> route = account
                  ? appPageRoute<int>(builder: page)
                  : MaterialPageRoute<int>(builder: page);
              final result = pushPageAndWaitForExit<int>(home, route);
              await t.pump();
              await t.pump(const Duration(milliseconds: 100));
              var childRect = t.getRect(find.byKey(childKey));
              expect(childRect.left, 0);
              expect(childRect.top, 0);
              expect(childRect.width, closeTo(width, 0.001));
              expect(childRect.height, closeTo(720, 0.001));
              expect(t.getRect(find.byKey(parentKey)), parentRect);
              expect(find.byType(SnapshotWidget), findsNothing);
              expect(
                find.ancestor(
                  of: find.byKey(childKey),
                  matching: find.byType(FadeTransition),
                ),
                findsNWidgets(2),
              );
              final fade = pageOpacity(t, find.byKey(childKey));
              expect(fade, greaterThan(0));
              expect(fade, lessThan(1));
              await t.pumpAndSettle();
              nav.currentState!.pop(i);
              await t.pump();
              await t.pump(const Duration(milliseconds: 100));
              childRect = t.getRect(find.byKey(childKey));
              expect(childRect.left, 0);
              expect(childRect.top, 0);
              expect(childRect.width, closeTo(width, 0.001));
              expect(childRect.height, closeTo(720, 0.001));
              expect(t.getRect(find.byKey(parentKey)), parentRect);
              expect(find.byType(SnapshotWidget), findsNothing);
              final reverseFade = pageOpacity(t, find.byKey(childKey));
              expect(reverseFade, greaterThan(0));
              expect(reverseFade, lessThan(1));
              if (account) expect(route.barrierColor, isNull);
              await t.pumpAndSettle();
              expect(await result, i);
              expect(t.element(find.byType(TextField)), same(parentElement));
              expect(controller.text, 'kept edits');
              expect(t.takeException(), isNull);
            }
            await t.pumpWidget(const SizedBox());
            controller.dispose();
          } finally {
            debugDefaultTargetPlatformOverride = previousPlatform;
          }
        },
      );
    }
  }

  testWidgets('Windows respects reduced-motion preference', (t) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final nav = GlobalKey<NavigatorState>();
      const key = ValueKey('motion-child');
      await t.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          theme: ThemeData(
            platform: TargetPlatform.windows,
            pageTransitionsTheme: desktopPageTransitions,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: const Scaffold(),
        ),
      );
      nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: SizedBox.expand(key: key)),
        ),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 16));
      expect(t.getTopLeft(find.byKey(key)), Offset.zero);
      expect(
        find.ancestor(
          of: find.byKey(key),
          matching: find.byType(FadeTransition),
        ),
        findsNothing,
      );
      await t.pumpAndSettle();
      nav.currentState!.pop();
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });

  testWidgets('Windows RTL entrance keeps the same stationary fade', (t) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final nav = GlobalKey<NavigatorState>();
      const key = ValueKey('rtl-child');
      await t.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          theme: ThemeData(
            platform: TargetPlatform.windows,
            pageTransitionsTheme: desktopPageTransitions,
          ),
          builder: (_, child) =>
              Directionality(textDirection: TextDirection.rtl, child: child!),
          home: const Scaffold(),
        ),
      );
      nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: SizedBox.expand(key: key)),
        ),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(t.getTopLeft(find.byKey(key)).dx, 0);
      expect(t.getTopLeft(find.byKey(key)).dy, 0);
      await t.pumpAndSettle();
      nav.currentState!.pop();
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });
}
