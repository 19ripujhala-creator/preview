import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaladarpan/widgets/page_content_motion.dart';
import 'package:shaladarpan/widgets/page_transitions.dart';

void main() {
  AutomatedTestWidgetsFlutterBinding.ensureInitialized();
  for (final width in [320.0, 1920.0]) {
    testWidgets('only content moves within 12 px at $width', (t) async {
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = Size(width, 720);
      final nav = GlobalKey<NavigatorState>();
      final controller = TextEditingController(text: 'kept');
      try {
        await t.pumpWidget(
          MaterialApp(
            navigatorKey: nav,
            theme: ThemeData(pageTransitionsTheme: desktopPageTransitions),
            home: Scaffold(body: TextField(controller: controller)),
          ),
        );
        final oldElement = t.element(find.byType(TextField));
        final result = nav.currentState!.push<int>(
          appPageRoute<int>(
            builder: (_) => Scaffold(
              appBar: AppBar(
                key: const ValueKey('header'),
                title: const Text('Details'),
              ),
              body: Container(
                key: const ValueKey('background'),
                color: Colors.white,
                child: const PageContentMotion(
                  child: SizedBox.expand(key: ValueKey('content')),
                ),
              ),
            ),
          ),
        );
        await t.pump();
        await t.pump(const Duration(milliseconds: 90));
        final header = t.getRect(find.byKey(const ValueKey('header')));
        final background = t.getRect(find.byKey(const ValueKey('background')));
        await t.pump(const Duration(milliseconds: 30));
        var content = t.getRect(find.byKey(const ValueKey('content')));
        expect(content.top - background.top, inExclusiveRange(0, 12));
        expect(content.width, background.width);
        expect(content.height, background.height);
        expect(content.left, background.left);
        expect(t.getRect(find.byKey(const ValueKey('header'))), header);
        expect(t.getRect(find.byKey(const ValueKey('background'))), background);
        // Reverse while entering: paint position remains continuous.
        final before = content;
        nav.currentState!.pop(7);
        await t.pump();
        content = t.getRect(find.byKey(const ValueKey('content')));
        expect((content.topLeft - before.topLeft).distance, lessThan(.001));
        await t.pump(const Duration(milliseconds: 30));
        expect(t.getRect(find.byKey(const ValueKey('header'))), header);
        expect(t.getRect(find.byKey(const ValueKey('background'))), background);
        await t.pumpAndSettle();
        expect(await result, 7);
        expect(controller.text, 'kept');
        expect(t.element(find.byType(TextField)), same(oldElement));
        expect(t.takeException(), isNull);
      } finally {
        await t.pumpWidget(const SizedBox());
        controller.dispose();
        t.view.resetPhysicalSize();
        t.view.resetDevicePixelRatio();
        debugDefaultTargetPlatformOverride = previous;
      }
    });
  }
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('content wrapper adds no mobile motion on $platform', (
      t,
    ) async {
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = platform;
      try {
        final nav = GlobalKey<NavigatorState>();
        await t.pumpWidget(
          MaterialApp(navigatorKey: nav, home: const Scaffold()),
        );
        nav.currentState!.push(
          appPageRoute<void>(
            builder: (_) =>
                const Scaffold(body: PageContentMotion(child: Text('content'))),
          ),
        );
        await t.pump();
        await t.pump(const Duration(milliseconds: 80));
        expect(
          find.descendant(
            of: find.byType(PageContentMotion),
            matching: find.byType(Transform),
          ),
          findsNothing,
        );
        await t.pumpAndSettle();
        nav.currentState!.pop();
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      } finally {
        await t.pumpWidget(const SizedBox());
        debugDefaultTargetPlatformOverride = previous;
      }
    });
  }
  for (final reduced in [false, true]) {
    testWidgets(
      'first route and reduced motion bypass content movement $reduced',
      (t) async {
        final previous = debugDefaultTargetPlatformOverride;
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        try {
          final nav = GlobalKey<NavigatorState>();
          await t.pumpWidget(
            MaterialApp(
              navigatorKey: nav,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(disableAnimations: reduced),
                child: child!,
              ),
              home: const Scaffold(
                body: PageContentMotion(child: Text('root')),
              ),
            ),
          );
          expect(
            find.descendant(
              of: find.byType(PageContentMotion),
              matching: find.byType(Transform),
            ),
            findsNothing,
          );
          if (reduced) {
            nav.currentState!.push(
              appPageRoute<void>(
                builder: (_) => const Scaffold(
                  body: PageContentMotion(child: Text('next')),
                ),
              ),
            );
            await t.pump();
            await t.pump(const Duration(milliseconds: 50));
            expect(
              find.descendant(
                of: find.byType(PageContentMotion),
                matching: find.byType(Transform),
              ),
              findsNothing,
            );
            await t.pumpAndSettle();
            nav.currentState!.pop();
            await t.pumpAndSettle();
          }
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox());
          debugDefaultTargetPlatformOverride = previous;
        }
      },
    );
  }
}
