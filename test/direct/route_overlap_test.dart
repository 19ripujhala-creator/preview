import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaladarpan/widgets/page_transitions.dart';

double opacity(WidgetTester t, String key) {
  final page = find.byKey(ValueKey(key), skipOffstage: false);
  if (page.evaluate().isEmpty) return 0;
  var value = 1.0;
  page.evaluate().single.visitAncestorElements((element) {
    final widget = element.widget;
    if (widget is Offstage && widget.offstage) value = 0;
    if (widget is FadeTransition) value *= widget.opacity.value;
    return true;
  });
  return value;
}
Widget screen(String key) => Scaffold(
  body: SizedBox.expand(key: ValueKey(key), child: Text(key)),
);

void main() {
  AutomatedTestWidgetsFlutterBinding.ensureInitialized();
  for (final width in [320.0, 1920.0]) {
    for (final depth in [1, 2]) {
      testWidgets('route content never overlaps at width $width depth $depth', (
        t,
      ) async {
        final previous = debugDefaultTargetPlatformOverride;
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = Size(width, 720);
        final nav = GlobalKey<NavigatorState>();
        try {
          await t.pumpWidget(
            MaterialApp(
              navigatorKey: nav,
              theme: ThemeData(pageTransitionsTheme: desktopPageTransitions),
              builder: (_, child) => AppNavigationBackdrop(child: child!),
              home: screen(depth == 1 ? 'parent' : 'root'),
            ),
          );
          if (depth == 2) {
            nav.currentState!.push(
              appPageRoute<void>(builder: (_) => screen('parent')),
            );
            await t.pumpAndSettle();
          }
          final route = appPageRoute<int>(builder: (_) => screen('child'));
          final result = nav.currentState!.push(route);
          await t.pump();
          var sawParent = false;
          var sawChild = false;
          Future<void> sample() async {
            for (var i = 0; i < 26; i++) {
              await t.pump(const Duration(milliseconds: 10));
              final oldOpacity = opacity(t, 'parent');
              final newOpacity = opacity(t, 'child');
              expect(oldOpacity * newOpacity, closeTo(0, .000001));
              sawParent |= oldOpacity > .01;
              sawChild |= newOpacity > .01;
              expect(
                t.getRect(find.byType(AppNavigationBackdrop)),
                Rect.fromLTWH(0, 0, width, 720),
              );
            }
          }

          await sample();
          expect(sawParent, isTrue);
          expect(sawChild, isTrue);
          expect(opacity(t, 'child'), 1);
          nav.currentState!.pop(9);
          await t.pump();
          sawParent = false;
          sawChild = false;
          await sample();
          expect(sawParent, isTrue);
          expect(sawChild, isTrue);
          expect(await result, 9);
          expect(opacity(t, 'parent'), 1);
          if (depth == 2) {
            nav.currentState!.pop();
            await t.pumpAndSettle();
          }
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox());
          t.view.resetPhysicalSize();
          t.view.resetDevicePixelRatio();
          debugDefaultTargetPlatformOverride = previous;
        }
      });
    }
  }
}
