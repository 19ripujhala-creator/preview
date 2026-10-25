import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaladarpan/experiments/direct_school_session.dart';
import 'package:shaladarpan/tabs/student/modules/monthly_attendance/monthly_attendance_screen.dart';
import 'package:shaladarpan/widgets/page_transitions.dart';

import 'working_days_fixture.dart';

class _Assets extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin')
      return const StandardMessageCodec().encodeMessage(<String, Object>{})!;
    return ByteData.sublistView(File(key).readAsBytesSync());
  }
}

Future<void> launch(
  WidgetTester t,
  WorkingDaysFixture f, {
  Size size = const Size(390, 760),
  double scale = 1,
}) async {
  await t.runAsync(() async {
    final loader = FontLoader('PlusJakartaSans');
    for (final weight in ['Regular', 'SemiBold', 'Bold']) {
      loader.addFont(
        Future.value(
          ByteData.sublistView(
            File('assets/fonts/PlusJakartaSans-$weight.ttf').readAsBytesSync(),
          ),
        ),
      );
    }
    await loader.load();
  });
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = size;
  DirectSchoolSession.attach(f, 'school-1');
  await t.pumpWidget(
    DefaultAssetBundle(
      bundle: _Assets(),
      child: MaterialApp(
        theme: ThemeData(
          pageTransitionsTheme: desktopPageTransitions,
          splashFactory: NoSplash.splashFactory,
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: AppNavigationBackdrop(child: child!),
        ),
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(ctx).push(
                appPageRoute<void>(
                  builder: (_) => const MonthlyAttendanceScreen(),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('Open'));
  await t.pumpAndSettle();
  await t.scrollUntilVisible(
    find.byType(DropdownButtonFormField<String>),
    100,
    scrollable: find.byType(Scrollable).first,
  );
  await t.tap(find.byType(DropdownButtonFormField<String>).first);
  await t.pumpAndSettle();
  await t.ensureVisible(find.text('2026-27').last);
  await t.pumpAndSettle();
  await t.tap(find.text('2026-27').last);
  await t.pumpAndSettle();
  await t.ensureVisible(find.text('Show Working Days'));
  await t.tap(find.text('Show Working Days'));
  await t.pumpAndSettle();
}

Future<void> edit(WidgetTester t) async {
  final field = find.byKey(const ValueKey('working-days/1'));
  await t.scrollUntilVisible(
    field,
    120,
    scrollable: find.byType(Scrollable).first,
  );
  await t.pumpAndSettle();
  await t.enterText(field, '22');
  await t.pump();
  await t.tap(find.textContaining('Save ').last);
  await t.pumpAndSettle();
  expect(find.text('Confirm Working Days'), findsOneWidget);
}

Future<void> cleanup(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  DirectSchoolSession.reset();
  t.view.resetPhysicalSize();
  t.view.resetDevicePixelRatio();
}

void main() {
  AutomatedTestWidgetsFlutterBinding.ensureInitialized();
  for (final size in [const Size(320, 560), const Size(1920, 1080)]) {
    testWidgets(
      'working days fits $size with large text and confirmation can be cancelled',
      (t) async {
        final f = WorkingDaysFixture();
        try {
          await launch(t, f, size: size, scale: 1.5);
          await edit(t);
          expect(t.takeException(), isNull);
          await t.tap(find.text('Keep Editing'));
          await t.pumpAndSettle();
          expect(f.submissions, isEmpty);
          expect(
            t
                .widget<TextField>(find.byKey(const ValueKey('working-days/1')))
                .controller!
                .text,
            '22',
          );
          expect(t.takeException(), isNull);
        } finally {
          await cleanup(t);
        }
      },
    );
  }
  testWidgets(
    'confirmed save refreshes values and displays original portal success once',
    (t) async {
      final f = WorkingDaysFixture();
      try {
        await launch(t, f);
        await edit(t);
        await t.tap(find.text('Submit'));
        await t.pumpAndSettle();
        expect(f.submissions, hasLength(1));
        expect(
          find.text('Success : Data has been added successfully.'),
          findsOneWidget,
        );
        await t.ensureVisible(find.byKey(const ValueKey('working-days/1')));
        expect(
          t
              .widget<TextField>(find.byKey(const ValueKey('working-days/1')))
              .controller!
              .text,
          '22',
        );
        expect(t.takeException(), isNull);
      } finally {
        await cleanup(t);
      }
    },
  );
  testWidgets('account change during confirmation prevents Submit', (t) async {
    final f = WorkingDaysFixture();
    try {
      await launch(t, f);
      await edit(t);
      DirectSchoolSession.attach(WorkingDaysFixture(), 'other-school');
      await t.tap(find.text('Submit'));
      await t.pumpAndSettle();
      expect(f.submissions, isEmpty);
      expect(
        find.text('School login has changed. Reopen Monthly Attendance.'),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    } finally {
      await cleanup(t);
    }
  });
  testWidgets(
    'discard cancellation restores the selected month and keeps the draft',
    (t) async {
      final f = WorkingDaysFixture();
      try {
        await launch(t, f);
        final field = find.byKey(const ValueKey('working-days/1'));
        await t.scrollUntilVisible(
          field,
          120,
          scrollable: find.byType(Scrollable).first,
        );
        await t.enterText(field, '22');
        await t.pump();
        final month = find.byType(DropdownButtonFormField<String>).last;
        final original = t
            .widget<DropdownButtonFormField<String>>(month)
            .initialValue;
        await t.ensureVisible(month);
        await t.tap(month);
        await t.pumpAndSettle();
        final other = original == 'May' ? 'Jun' : 'May';
        await t.ensureVisible(find.text(other).last);
        await t.tap(find.text(other).last);
        await t.pumpAndSettle();
        expect(find.text('Discard unsaved changes?'), findsOneWidget);
        await t.tap(find.text('Keep Editing'));
        await t.pumpAndSettle();
        expect(
          t
              .widget<DropdownButtonFormField<String>>(
                find.byType(DropdownButtonFormField<String>).last,
              )
              .initialValue,
          original,
        );
        expect(t.widget<TextField>(field).controller!.text, '22');
        expect(
          t
              .widget<DropdownButton<String>>(
                find.byType(DropdownButton<String>).last,
              )
              .value,
          original,
        );
        expect(f.submissions, isEmpty);
        expect(t.takeException(), isNull);
      } finally {
        await cleanup(t);
      }
    },
  );
  testWidgets('Back is blocked during the single pending Submit', (t) async {
    final f = WorkingDaysFixture()..submitGate = Completer<void>();
    try {
      await launch(t, f);
      await edit(t);
      await t.tap(find.text('Submit'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(f.submissions, hasLength(1));
      await t.state<NavigatorState>(find.byType(Navigator).first).maybePop();
      await t.pump();
      expect(find.text('Monthly Attendance'), findsOneWidget);
      f.submitGate!.complete();
      await t.pumpAndSettle();
      expect(f.submissions, hasLength(1));
      expect(t.takeException(), isNull);
    } finally {
      if (!f.submitGate!.isCompleted) f.submitGate!.complete();
      await cleanup(t);
    }
  });
}
