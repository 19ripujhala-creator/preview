import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaladarpan/tabs/rajsims/mpr_page_frame.dart';

void main() {
  for (final width in [320.0, 390.0, 1920.0]) {
    for (final keyboard in [0.0, 240.0]) {
      testWidgets(
        'MPR body reserves footer at width=$width keyboard=$keyboard',
        (t) async {
          t.view.physicalSize = Size(width, 800);
          t.view.devicePixelRatio = 1;
          t.view.viewInsets = FakeViewPadding(bottom: keyboard);
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          addTearDown(t.view.resetViewInsets);
          await t.pumpWidget(
            MaterialApp(
              home: MprPageFrame(
                appBar: AppBar(title: const Text('MPR')),
                background: const Positioned.fill(
                  child: ColoredBox(color: Colors.amber),
                ),
                body: const SizedBox.expand(key: ValueKey('body')),
                footer: const SizedBox(
                  key: ValueKey('footer'),
                  height: 82,
                  child: Center(child: Text('Cooking total  Next')),
                ),
              ),
            ),
          );
          await t.pumpAndSettle();
          final body = t.getRect(find.byKey(const ValueKey('body')));
          final footer = t.getRect(find.byKey(const ValueKey('footer')));
          expect(body.bottom, lessThanOrEqualTo(footer.top));
          expect(footer.bottom, lessThanOrEqualTo(800 - keyboard));
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
  for (final width in [320.0, 960.0, 1920.0]) {
    testWidgets('MPR notice stays within responsive width $width', (t) async {
      t.view.physicalSize = Size(width, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        MaterialApp(
          home: MprPageFrame(
            appBar: AppBar(title: const Text('MPR')),
            background: const Positioned.fill(
              child: ColoredBox(color: Colors.amber),
            ),
            footer: const SizedBox(height: 82),
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    mprPageNotice(context, 'Complete required fields'),
                  ),
                  child: const Text('Validate'),
                ),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Validate'));
      await t.pumpAndSettle();
      final notice = t.getRect(
        find
            .descendant(
              of: find.byType(SnackBar),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(notice.width, lessThan(width));
      expect(notice.width, lessThanOrEqualTo(1280));
      expect(notice.left, greaterThanOrEqualTo(0));
      expect(notice.right, lessThanOrEqualTo(width));
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    });
  }
}
