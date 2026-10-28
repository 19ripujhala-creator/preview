import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaladarpan/tabs/student/modules/student_attendance/widgets/attendance_page_header.dart';

void main() {
  for (final width in [320.0, 430.0, 960.0, 1920.0]) {
    testWidgets(
      'both attendance headers fit ${width}px and keep actions usable',
      (t) async {
        t.view.physicalSize = Size(width, 720);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        Rect? first;
        for (final title in ['Attendance Register', 'Attendance Report']) {
          var tapped = false;
          await t.pumpWidget(
            MaterialApp(
              home: Scaffold(
                appBar: AttendancePageHeader(
                  title: title,
                  foreground: Colors.black,
                  actions: [
                    IconButton(
                      tooltip: 'Header action',
                      onPressed: () => tapped = true,
                      icon: const Icon(Icons.more_horiz),
                    ),
                  ],
                ),
                body: const SizedBox.expand(),
              ),
            ),
          );
          await t.pumpAndSettle();
          final rect = t.getRect(
            find.byKey(const ValueKey('attendance-page-header-canvas')),
          );
          expect(rect.width, lessThanOrEqualTo(1280));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(width));
          if (first != null) expect(rect, first);
          first = rect;
          final label = t.getRect(find.text(title));
          expect(label.left, greaterThan(rect.left));
          expect(label.right, lessThanOrEqualTo(rect.right));
          await t.tap(find.byTooltip('Header action'));
          expect(tapped, isTrue);
          expect(t.takeException(), isNull);
        }
        await t.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
