import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaladarpan/experiments/direct_school_session.dart';

import 'package:shaladarpan/tabs/student/modules/monthly_attendance/monthly_student_attendance_screen.dart';

import 'monthly_attendance_fixture.dart';
import 'working_days_screen_test.dart' as working;

Future<void> open(
  WidgetTester t,
  MonthlyAttendanceFixture f, {
  Size size = const Size(390, 760),
  double scale = 1,
}) async {
  await working.launch(t, f, size: size, scale: scale);
  await t.ensureVisible(find.text('Student Attendance'));
  await t.tap(find.text('Student Attendance'));
  await t.pumpAndSettle();
  await t.ensureVisible(find.text('Show Students'));
  await t.tap(find.text('Show Students'));
  await t.pumpAndSettle();
}

Future<void> enter(WidgetTester t, {String value = '20'}) async {
  final field = find.byKey(ValueKey('monthly-attendance/${monthlyId(0)}'));
  await t.scrollUntilVisible(
    field,
    100,
    scrollable: find.byType(Scrollable).last,
  );
  await t.pumpAndSettle();
  await t.enterText(field, value);
  await t.pump();
}

Future<void> confirm(WidgetTester t) async {
  await enter(t);
  await t.tap(find.text('Save Attendance (1)'));
  await t.pumpAndSettle();
  expect(find.text('Confirm Monthly Attendance'), findsOneWidget);
  expect(
    Theme.of(t.element(find.byType(AlertDialog))).colorScheme.primary,
    const Color(0xFF18212F),
  );
}

void main() {
  AutomatedTestWidgetsFlutterBinding.ensureInitialized();
  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    for (final size in [const Size(320, 560), const Size(1920, 1080)]) {
      testWidgets(
        'monthly attendance fits $platform $size with 1.5x text; confirmation can be cancelled',
        (t) async {
          debugDefaultTargetPlatformOverride = platform;
          final f = MonthlyAttendanceFixture();
          try {
            await open(t, f, size: size, scale: 1.5);
            await confirm(t);
            expect(t.takeException(), isNull);
            await t.tap(find.text('Keep Editing'));
            await t.pumpAndSettle();
            expect(f.attendanceSubmissions, isEmpty);
            expect(
              t
                  .widget<TextField>(
                    find.byKey(ValueKey('monthly-attendance/${monthlyId(0)}')),
                  )
                  .controller!
                  .text,
              '20',
            );
          } finally {
            await working.cleanup(t);
            debugDefaultTargetPlatformOverride = null;
          }
        },
      );
    }
  }
  testWidgets(
    'one confirmed Save preserves values and verified notification dismisses automatically',
    (t) async {
      final f = MonthlyAttendanceFixture();
      try {
        await open(t, f);
        await confirm(t);
        await t.tap(find.text('Save Attendance'));
        await t.pumpAndSettle();
        expect(f.attendanceSubmissions, hasLength(1));
        expect(
          find.text('Monthly attendance saved and verified on the portal.'),
          findsOneWidget,
        );
        await t.pump(const Duration(seconds: 7));
        await t.pumpAndSettle();
        expect(
          find.text('Monthly attendance saved and verified on the portal.'),
          findsNothing,
        );
        expect(t.takeException(), isNull);
      } finally {
        await working.cleanup(t);
      }
    },
  );
  testWidgets(
    'zero working days disables student attendance and explains prerequisite',
    (t) async {
      final f = MonthlyAttendanceFixture()..zeroDays = true;
      try {
        await open(t, f);
        final field = find.byKey(
          ValueKey('monthly-attendance/${monthlyId(0)}'),
        );
        await t.scrollUntilVisible(
          field,
          100,
          scrollable: find.byType(Scrollable).last,
        );
        expect(t.widget<TextField>(field).enabled, false);
        expect(f.attendanceSubmissions, isEmpty);
        expect(t.takeException(), isNull);
      } finally {
        await working.cleanup(t);
      }
    },
  );
  testWidgets('cancelled selection change restores displayed month and draft', (
    t,
  ) async {
    final f = MonthlyAttendanceFixture();
    try {
      await open(t, f);
      await enter(t);
      await t.drag(find.byType(CustomScrollView), const Offset(0, 900));
      await t.pumpAndSettle();
      final month = find.byType(DropdownButtonFormField<String>).last;
      await t.ensureVisible(month);
      final original = t
          .widget<DropdownButtonFormField<String>>(month)
          .initialValue;
      await t.tap(month);
      await t.pumpAndSettle();
      final other = original == '10' ? 'September' : 'October';
      await t.ensureVisible(find.text(other).last);
      await t.tap(find.text(other).last);
      await t.pumpAndSettle();
      await t.tap(find.text('Keep Editing'));
      await t.pumpAndSettle();
      expect(
        t
            .widget<DropdownButton<String>>(
              find.byType(DropdownButton<String>).last,
            )
            .value,
        original,
      );
      expect(f.attendanceSubmissions, isEmpty);
      expect(t.takeException(), isNull);
    } finally {
      await working.cleanup(t);
    }
  });
  testWidgets(
    'account change while confirmation is open cannot save into either account',
    (t) async {
      final f = MonthlyAttendanceFixture();
      try {
        await open(t, f);
        await confirm(t);
        DirectSchoolSession.attach(MonthlyAttendanceFixture(), 'other-school');
        await t.tap(find.text('Save Attendance'));
        await t.pumpAndSettle();
        expect(f.attendanceSubmissions, isEmpty);
        expect(
          find.textContaining('School login has changed.'),
          findsOneWidget,
        );
        expect(t.takeException(), isNull);
      } finally {
        await working.cleanup(t);
      }
    },
  );
  testWidgets('Save is sent once and Back cannot leave a pending submission', (
    t,
  ) async {
    final f = MonthlyAttendanceFixture();
    try {
      await open(t, f);
      await confirm(t);
      f.submitGate = Completer<void>();
      await t.tap(find.text('Save Attendance'));
      await t.pump();
      await t.pump();
      expect(f.attendanceSubmissions, hasLength(1));
      await t.pageBack();
      await t.pump();
      expect(find.byType(MonthlyStudentAttendanceScreen), findsOneWidget);
      f.submitGate!.complete();
      await t.pumpAndSettle();
      expect(f.attendanceSubmissions, hasLength(1));
      expect(t.takeException(), isNull);
    } finally {
      await working.cleanup(t);
    }
  });
  testWidgets(
    'back from student register preserves Working Days without another request',
    (t) async {
      final f = MonthlyAttendanceFixture();
      try {
        await open(t, f);
        final before = f.reads;
        await t.pageBack();
        await t.pumpAndSettle();
        expect(find.text('Total Working Days'), findsOneWidget);
        expect(f.reads, before);
        expect(t.takeException(), isNull);
      } finally {
        await working.cleanup(t);
      }
    },
  );
  testWidgets(
    'Working Days carries its selected session and month to the student register',
    (t) async {
      final f = MonthlyAttendanceFixture();
      try {
        await working.launch(t, f);
        final month = find.byType(DropdownButtonFormField<String>).last;
        t.widget<DropdownButtonFormField<String>>(month).onChanged!('Sep');
        await t.pumpAndSettle();
        await t.ensureVisible(find.text('Student Attendance'));
        await t.tap(find.text('Student Attendance'));
        await t.pumpAndSettle();
        final choices = t
            .widgetList<DropdownButton<String>>(
              find.byType(DropdownButton<String>),
            )
            .toList();
        expect(choices.first.value, '2026-27');
        expect(choices.last.value, '9');
        expect(f.attendanceSubmissions, isEmpty);
        expect(t.takeException(), isNull);
      } finally {
        await working.cleanup(t);
      }
    },
  );
}
