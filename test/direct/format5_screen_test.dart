import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaladarpan/experiments/direct_portal_auth.dart';
import 'package:shaladarpan/experiments/direct_school_session.dart';
import 'package:shaladarpan/services/portals/shaladarpan/direct/student_attendance_worker.dart';
import 'package:shaladarpan/tabs/student/modules/format5/format5_screen.dart';
import 'package:shaladarpan/widgets/page_transitions.dart';
import 'package:shaladarpan/widgets/adaptive_layout.dart';

const name = r'ctl00$ContentPlaceHolder1$grdStudentProfile$ctl02$';
const prefix = 'ContentPlaceHolder1_grdStudentProfile_';

String form({
  required bool edit,
  String mobile = '9000000000',
  bool success = false,
}) =>
    '''
    <html><body><form id="form1" action="./SchoolStudentProfiles_New.aspx">
      <input type="hidden" name="__VIEWSTATE" value="state123" />
      <input type="hidden" name="__EVENTVALIDATION" value="event456" />
      <div id="UpdatePanel1"></div>
      <div id="ContentPlaceHolder1_UpdPanel">
        ${success ? '<div class="alert alert-success">Success : Student profile has been updated successfully.</div>' : ''}
        <select name="ctl00\$ContentPlaceHolder1\$ddlSession" id="ddlSession">
          <option value="2026-27" selected="selected">2026-27</option>
        </select>
        <select name="ctl00\$ContentPlaceHolder1\$ddlClass" id="ContentPlaceHolder1_ddlClass">
          <option value="1" selected="selected">1</option><option value="2">2</option>
        </select>
        <select name="ctl00\$ContentPlaceHolder1\$ddlSection" id="ContentPlaceHolder1_ddlSection">
          <option value="1" selected="selected">A</option>
        </select>
        <input type="submit" name="ctl00\$ContentPlaceHolder1\$btnSearch" id="ContentPlaceHolder1_btnSearch" value="Show" />
        <table id="ContentPlaceHolder1_grdStudentProfile"><tr><td>
          ${edit ? '''
            <input id="${prefix}txtSnicid_Edit_0" name="${name}txtSnicid_Edit" value="00001" disabled="disabled" />
            <input id="${prefix}txtSRNO_Edit_0" name="${name}txtSRNO_Edit" value="19" />
            <input id="${prefix}txtMobile_edit_0" name="${name}txtMobile_edit" value="$mobile" />
            <select name="${name}ddlCategory_Edit" id="${prefix}ddlCategory_Edit_0">
              <option value="2" selected="selected">ST</option>
              <option value="5">OBC</option>
            </select>
            <input type="image" id="${prefix}btnUpdate_0" name="${name}btnUpdate" />
          ''' : '''
            <span id="${prefix}lblSnicid_0">00001</span>
            <span id="${prefix}lblSRNO_0">19</span>
            <span id="${prefix}lblName_0">Sample Student</span>
            <span id="${prefix}lblFatherName_0">Sample Father</span>
            <span id="${prefix}lblCategory_0">ST</span>
            <span id="${prefix}lblMobile_0">$mobile</span>
            <input type="image" id="${prefix}btnEdit_0" name="${name}btnEdit" />
          '''}
        </td></tr></table>
      </div>
    </form></body></html>''';

class _Assets extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin') {
      return const StandardMessageCodec().encodeMessage(<String, Object>{})!;
    }
    return ByteData.sublistView(File(key).readAsBytesSync());
  }
}

class _Auth extends DirectPortalAuth {
  int updates = 0, requests = 0, showPosts = 0;
  Completer<void>? refreshGate, editGate;
  bool failEdit = false, lockMobile = false;
  String mobile = '9000000000';
  Completer<void>? saveGate, listGate;
  bool ambiguous = false, failRefresh = false;
  bool retainEditOnShow = false, portalEditing = false;
  int freshGets = 0;
  bool closeSuccess = false, manyStudents = false;
  String successSuffix = '';
  @override
  bool get isVerified => true;
  @override
  String get authenticatedSchoolId => '123';
  @override
  String get verifiedNode => 'SD1';
  String identity = 'fixture';
  bool renewOnGet = false;
  @override
  String get schoolSessionIdentity => identity;
  @override
  void close() {}
  @override
  Future<AttendanceHttpReply> format5Request(
    Uri url, {
    Map<String, Object?>? fields,
    Uri? referer,
    bool mutation = false,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    requests++;
    if (fields != null && fields.keys.any((k) => k.endsWith('btnSearch'))) {
      showPosts++;
      if (updates > 0 && showPosts >= 3) await refreshGate?.future;
    }
    if (fields == null) {
      freshGets++;
      if (renewOnGet) identity = 'renewed-$freshGets';
      portalEditing = false;
    }
    if (fields != null && fields.keys.any((k) => k.endsWith('btnUpdate.x'))) {
      updates++;
      await saveGate?.future;
      if (ambiguous) throw const SocketException('Offline update fixture');
      mobile = '${fields['${name}txtMobile_edit']}';
      return (
        url: url,
        status: 200,
        html: form(edit: false, mobile: mobile, success: true)
            .replaceFirst(
              'Success :',
              '${closeSuccess ? '<button type="button" class="close" data-dismiss="alert">×</button>' : ''}Success :',
            )
            .replaceFirst(
              'updated successfully.',
              'updated successfully.$successSuffix',
            ),
      );
    }
    final edit =
        fields != null && fields.keys.any((k) => k.endsWith('btnEdit.x'));
    if (edit) {
      await editGate?.future;
      if (failEdit) {
        throw const SocketException('Original edit response unavailable');
      }
      portalEditing = true;
    }
    if (fields != null && !edit) {
      await listGate?.future;
      if (failRefresh && updates > 0) {
        throw const SocketException('Offline refresh fixture');
      }
    }
    var page = form(
      edit: edit || (retainEditOnShow && portalEditing),
      mobile: mobile,
    );
    if (edit && lockMobile) {
      page = page.replaceFirst(
        'name="${name}txtMobile_edit"',
        'name="${name}txtMobile_edit" disabled="disabled"',
      );
    }
    if (manyStudents && !edit && !portalEditing) {
      final start = page.indexOf('<tr>'), end = page.indexOf('</tr>') + 5;
      final row = page.substring(start, end);
      page = page.replaceRange(
        start,
        end,
        List.generate(
          20,
          (index) => row
              .replaceAll('_0', '_$index')
              .replaceAll('00001', '${index + 1}'.padLeft(5, '0'))
              .replaceAll('Sample Student', 'Sample Student ${index + 1}'),
        ).join(),
      );
    }
    return (url: url, status: 200, html: page);
  }
}

class _Navigation extends NavigatorObserver {
  ModalRoute<dynamic>? lastPage;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is ModalRoute<dynamic>) lastPage = route;
  }
}

late _Navigation navigation;

Future<void> _launch(
  WidgetTester t,
  _Auth auth, {
  Size size = const Size(390, 760),
  double textScale = 1,
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
  navigation = _Navigation();
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = size;
  DirectSchoolSession.attach(auth, '123');
  await t.pumpWidget(
    DefaultAssetBundle(
      bundle: _Assets(),
      child: MaterialApp(
        navigatorObservers: [navigation],
        theme: ThemeData(
          pageTransitionsTheme: desktopPageTransitions,
          // This fixture bundle omits compiled Material ripple shaders.
          splashFactory: NoSplash.splashFactory,
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: AppNavigationBackdrop(child: child!),
        ),
        home: const Format5Screen(),
      ),
    ),
  );
  await t.pumpAndSettle();
}

/// Finish navigation without waiting for the deliberately blocked Edit request
/// (and its repeating progress indicator). Native route durations differ.
Future<void> finishTransition(
  WidgetTester t,
  ModalRoute<dynamic> route, {
  bool reverse = false,
}) async {
  var exited = false;
  if (reverse) route.completed.then((_) => exited = true);
  final duration = reverse
      ? route.reverseTransitionDuration
      : route.transitionDuration;
  final step = duration ~/ 10 + const Duration(milliseconds: 1);
  for (var frame = 0; frame < 40; frame++) {
    if (reverse ? exited : route.animation!.isCompleted) break;
    await t.pump(step);
  }
  expect(
    reverse ? exited : route.animation!.isCompleted,
    isTrue,
    reason:
        'The selected platform route must finish while Edit remains pending.',
  );
  await t.pump();
}

Future<ModalRoute<dynamic>> finishEditTransition(WidgetTester t) async {
  await t.pump();
  final route = navigation.lastPage!;
  expect(route.isFirst, isFalse);
  await finishTransition(t, route);
  return route;
}

Future<void> showStudents(WidgetTester t) async {
  await t.ensureVisible(find.text('Show Students'));
  await t.tap(find.text('Show Students'));
  await t.pumpAndSettle();
}

Future<void> editStudent(WidgetTester t) async {
  await showStudents(t);
  await t.scrollUntilVisible(
    find.text('Sample Student'),
    120,
    scrollable: find.byType(Scrollable).first,
  );
  await t.tap(find.text('Sample Student'));
  await t.pumpAndSettle();
  expect(find.text('Edit Student Profile'), findsOneWidget);
  await t.enterText(find.byType(TextField).last, '9111111111');
  await t.pump();
}

Future<void> confirm(WidgetTester t) async {
  await t.tap(find.text('Update on Portal'));
  await t.pumpAndSettle();
  expect(find.text('Confirm Update'), findsOneWidget);
}

void main() {
  AutomatedTestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    DirectSchoolSession.reset();
  });
  Future<void> cleanup(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  }

  testWidgets(
    'initial Format-5 GET may renew same-school cookies without blocking selectors',
    (t) async {
      final auth = _Auth()..renewOnGet = true;
      try {
        await _launch(t, auth);
        expect(
          find.text('School session changed. Reopen Format 5.'),
          findsNothing,
        );
        expect(
          t
              .widgetList<DropdownButton<String>>(
                find.byType(DropdownButton<String>),
              )
              .every((d) => d.items!.isNotEmpty),
          true,
        );
        expect(auth.freshGets, 1);
        expect(auth.updates, 0);
        expect(t.takeException(), isNull);
      } finally {
        await cleanup(t);
      }
    },
  );
  testWidgets(
    'Refresh recovers a same-school session change on the existing service',
    (t) async {
      final auth = _Auth();
      try {
        await _launch(t, auth);
        auth.identity = 'recovered-session';
        await t.tap(find.byTooltip('Refresh portal'));
        await t.pumpAndSettle();
        await showStudents(t);
        expect(find.text('Sample Student'), findsOneWidget);
        expect(
          find.text('School session changed. Reopen Format 5.'),
          findsNothing,
        );
        expect(auth.updates, 0);
        expect(t.takeException(), isNull);
      } finally {
        await cleanup(t);
      }
    },
  );
  testWidgets(
    'Edit Back Edit works repeatedly when portal retains edit mode on Show',
    (t) async {
      final auth = _Auth()..retainEditOnShow = true;
      try {
        await _launch(t, auth);
        await showStudents(t);
        for (var i = 0; i < 3; i++) {
          await t.scrollUntilVisible(
            find.text('Edit'),
            100,
            scrollable: find.byType(Scrollable).first,
          );
          await t.tap(find.text('Edit'));
          await t.pumpAndSettle();
          expect(find.text('Edit Student Profile'), findsOneWidget);
          final requestsBeforeBack = auth.requests;
          if (i.isEven) {
            final nav = t.state<NavigatorState>(find.byType(Navigator).first);
            await nav.maybePop();
          } else {
            await t.tap(find.text('Cancel'));
          }
          await t.pumpAndSettle();
          expect(
            auth.requests,
            requestsBeforeBack,
            reason: 'Back/Cancel must not reload the portal list',
          );
        }
        expect(auth.updates, 0);
        expect(auth.freshGets, 1);
        expect(
          find.text('Student row or portal action is not available.'),
          findsNothing,
        );
        expect(t.takeException(), isNull);
      } finally {
        await cleanup(t);
      }
    },
  );
  testWidgets(
    'cached details open before a delayed Edit response and only verified fields become editable',
    (t) async {
      final auth = _Auth()
        ..editGate = Completer<void>()
        ..mobile = '9000000000';
      try {
        await _launch(t, auth, size: const Size(1920, 1080));
        await showStudents(t);
        await t.tap(find.text('Sample Student'));
        await finishEditTransition(t);
        expect(auth.editGate!.isCompleted, isFalse);
        expect(find.text('Edit Student Profile'), findsOneWidget);
        expect(find.text('Sample Student'), findsOneWidget);
        expect(find.text('Sample Father'), findsOneWidget);
        final fields = t.widgetList<TextField>(find.byType(TextField)).toList();
        expect(fields.map((f) => f.controller!.text), ['19', '9000000000']);
        expect(fields.every((f) => f.enabled == false), isTrue);
        expect(
          t
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Update on Portal'),
              )
              .onPressed,
          isNull,
        );
        auth.mobile = '9333333333';
        auth.editGate!.complete();
        await t.pumpAndSettle();
        expect(
          t.widget<TextField>(find.byType(TextField).last).controller!.text,
          '9333333333',
        );
        expect(
          t.widget<TextField>(find.byType(TextField).last).enabled,
          isTrue,
        );
        expect(find.text('ST'), findsOneWidget);
        expect(find.text('Sample Father'), findsOneWidget);
        await t.enterText(find.byType(TextField).last, '9444444444');
        await t.pump();
        await confirm(t);
        expect(find.text('9333333333'), findsOneWidget);
        await t.tap(find.text('Keep Editing'));
        await t.pumpAndSettle();
        expect(auth.updates, 0);
        expect(t.takeException(), isNull);
      } finally {
        if (!auth.editGate!.isCompleted) auth.editGate!.complete();
        await cleanup(t);
      }
    },

    variant: const TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );
  testWidgets('cached Edit and deferred fields fit 320px at large text scale', (
    t,
  ) async {
    final auth = _Auth()..editGate = Completer<void>();
    try {
      await _launch(t, auth, size: const Size(320, 560), textScale: 1.5);
      await showStudents(t);
      await t.scrollUntilVisible(
        find.text('Edit'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.text('Edit'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 260));
      expect(find.text('Edit Student Profile'), findsOneWidget);
      expect(t.takeException(), isNull);
      auth.editGate!.complete();
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(auth.updates, 0);
    } finally {
      if (!auth.editGate!.isCompleted) auth.editGate!.complete();
      await cleanup(t);
    }
  });
  testWidgets(
    'Back while Edit is pending never opens a late page or starts another request',
    (t) async {
      final auth = _Auth()..editGate = Completer<void>();
      try {
        await _launch(t, auth);
        await showStudents(t);
        await t.scrollUntilVisible(
          find.text('Edit'),
          100,
          scrollable: find.byType(Scrollable).first,
        );
        await t.tap(find.text('Edit'));
        final route = await finishEditTransition(t);
        expect(find.text('Edit Student Profile'), findsOneWidget);
        await t.tap(find.text('Cancel'));
        await t.pump();
        await finishTransition(t, route, reverse: true);
        expect(find.text('Edit Student Profile'), findsNothing);
        final count = auth.requests;
        await t.tap(find.text('Sample Student'));
        await t.pump();
        expect(auth.requests, count);
        auth.editGate!.complete();
        await t.pumpAndSettle();
        expect(find.text('Edit Student Profile'), findsNothing);
        expect(auth.updates, 0);
        await t.tap(find.text('Sample Student'));
        await t.pumpAndSettle();
        expect(find.text('Edit Student Profile'), findsOneWidget);
        expect(auth.requests, count);
        expect(t.takeException(), isNull);
      } finally {
        if (!auth.editGate!.isCompleted) auth.editGate!.complete();
        await cleanup(t);
      }
    },

    variant: const TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );
  testWidgets(
    'delayed Edit cannot enable fields after the school session changes',
    (t) async {
      final auth = _Auth()..editGate = Completer<void>();
      try {
        await _launch(t, auth);
        await showStudents(t);
        await t.scrollUntilVisible(
          find.text('Edit'),
          100,
          scrollable: find.byType(Scrollable).first,
        );
        await t.tap(find.text('Edit'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 260));
        DirectSchoolSession.attach(_Auth(), '999');
        auth.editGate!.complete();
        await t.pumpAndSettle();
        expect(
          t
              .widgetList<TextField>(find.byType(TextField))
              .every((f) => f.enabled == false),
          isTrue,
        );
        await t.ensureVisible(
          find.text('School login has changed. Reopen Format 5.'),
        );
        expect(
          find.text('School login has changed. Reopen Format 5.'),
          findsOneWidget,
        );
        expect(auth.updates, 0);
        expect(t.takeException(), isNull);
      } finally {
        if (!auth.editGate!.isCompleted) auth.editGate!.complete();
        await cleanup(t);
      }
    },
  );
  testWidgets('Edit failure is visible and cached fields cannot be submitted', (
    t,
  ) async {
    final auth = _Auth()..failEdit = true;
    try {
      await _launch(t, auth);
      await showStudents(t);
      await t.scrollUntilVisible(
        find.text('Edit'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.text('Edit'));
      await t.pumpAndSettle();
      expect(find.text('Edit Student Profile'), findsOneWidget);
      await t.ensureVisible(
        find.textContaining('Original edit response unavailable'),
      );
      expect(
        find.textContaining('Original edit response unavailable'),
        findsOneWidget,
      );
      expect(
        t
            .widgetList<TextField>(find.byType(TextField))
            .every((f) => f.enabled == false),
        isTrue,
      );
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Update on Portal'),
            )
            .onPressed,
        isNull,
      );
      expect(auth.updates, 0);
      expect(t.takeException(), isNull);
    } finally {
      await cleanup(t);
    }
  });
  testWidgets(
    'a locked mobile field stays locked after deferred Edit preparation',
    (t) async {
      try {
        await _launch(t, _Auth()..lockMobile = true);
        await showStudents(t);
        await t.scrollUntilVisible(
          find.text('Edit'),
          100,
          scrollable: find.byType(Scrollable).first,
        );
        await t.tap(find.text('Edit'));
        await t.pumpAndSettle();
        expect(
          t.widget<TextField>(find.byType(TextField).last).enabled,
          isFalse,
        );
        expect(
          t
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Update on Portal'),
              )
              .onPressed,
          isNull,
        );
        expect(t.takeException(), isNull);
      } finally {
        await cleanup(t);
      }
    },
  );
  testWidgets(
    'Back keeps the loaded list, search and scroll position without a request',
    (t) async {
      final auth = _Auth()..manyStudents = true;
      try {
        await _launch(t, auth, size: const Size(390, 600));
        await showStudents(t);
        await t.enterText(
          find.byKey(const ValueKey('format5-search')),
          'Sample Student',
        );
        await t.pumpAndSettle();
        final search = t
            .widget<TextField>(find.byKey(const ValueKey('format5-search')))
            .controller!;
        await t.scrollUntilVisible(
          find.text('Sample Student 1'),
          120,
          scrollable: find.byType(Scrollable).first,
        );
        await t.pumpAndSettle();
        final before = t
            .widget<CustomScrollView>(find.byType(CustomScrollView))
            .controller!
            .offset;
        expect(before, greaterThan(0));
        await t.tap(find.text('Sample Student 1'));
        await t.pumpAndSettle();
        expect(find.text('Edit Student Profile'), findsOneWidget);
        await t.enterText(find.byType(TextField).last, '9222222222');
        final requests = auth.requests;
        await t.state<NavigatorState>(find.byType(Navigator).first).maybePop();
        await t.pumpAndSettle();
        expect(auth.requests, requests);
        expect(auth.updates, 0);
        expect(
          t
              .widget<SliverList>(find.byType(SliverList))
              .delegate
              .estimatedChildCount,
          20,
        );
        expect(search.text, 'Sample Student');
        expect(
          t
              .widget<CustomScrollView>(find.byType(CustomScrollView))
              .controller!
              .offset,
          closeTo(before, .001),
        );
        expect(find.text('Sample Student 1').hitTestable(), findsOneWidget);
        expect(t.takeException(), isNull);
      } finally {
        await cleanup(t);
      }
    },
  );
  testWidgets(
    'success stays six seconds after a slow refresh, then automatically dismisses',
    (t) async {
      final auth = _Auth()..refreshGate = Completer<void>();
      const message =
          'Success : Student profile has been updated successfully.';
      try {
        await _launch(t, auth);
        await editStudent(t);
        await confirm(t);
        await t.tap(find.text('Update'));
        await t.pump();
        await t.pump(const Duration(seconds: 1));
        await t.pump(const Duration(seconds: 8));
        expect(auth.showPosts, 3);
        expect(find.text(message), findsOneWidget);
        auth.refreshGate!.complete();
        await t.pumpAndSettle();
        await t.pump(const Duration(seconds: 5));
        expect(find.text(message), findsOneWidget);
        await t.pump(const Duration(seconds: 2));
        expect(find.text(message), findsNothing);
        expect(find.byTooltip('Dismiss success message'), findsNothing);
        expect(auth.updates, 1);
        expect(t.takeException(), isNull);
      } finally {
        if (!auth.refreshGate!.isCompleted) auth.refreshGate!.complete();
        await cleanup(t);
      }
    },
  );
  testWidgets(
    'automatic success dismissal keeps a separate refresh error visible',
    (t) async {
      final auth = _Auth()..failRefresh = true;
      try {
        await _launch(t, auth);
        await editStudent(t);
        await confirm(t);
        await t.tap(find.text('Update'));
        await t.pumpAndSettle();
        expect(find.byTooltip('Dismiss success message'), findsOneWidget);
        await t.pump(const Duration(seconds: 7));
        expect(find.byTooltip('Dismiss success message'), findsNothing);
        expect(find.textContaining('Offline refresh fixture'), findsOneWidget);
        expect(find.byTooltip('Dismiss error message'), findsOneWidget);
        expect(auth.updates, 1);
        expect(t.takeException(), isNull);
      } finally {
        await cleanup(t);
      }
    },
  );
  testWidgets(
    'desktop details use readable type and Cancel has an opaque white fill',
    (t) async {
      try {
        await _launch(t, _Auth(), size: const Size(1920, 1080));
        await editStudent(t);
        final details = find.byKey(const ValueKey('format5-details-card'));
        expect(
          t
              .widget<Text>(
                find.descendant(of: details, matching: find.text('NIC ID')),
              )
              .style!
              .fontSize,
          12,
        );
        expect(
          t
              .widget<Text>(
                find.descendant(of: details, matching: find.text('00001')),
              )
              .style!
              .fontSize,
          13,
        );
        final cancel = t.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, 'Cancel'),
        );
        expect(cancel.style!.backgroundColor!.resolve({}), Colors.white);
        expect(
          cancel.style!.backgroundColor!.resolve({WidgetState.disabled}),
          Colors.white,
        );
        expect(cancel.style!.surfaceTintColor!.resolve({}), Colors.transparent);
        final a = t.getRect(details);
        final b = t.getRect(find.byKey(const ValueKey('format5-fields-card')));
        expect(a.height, closeTo(b.height, .001));
        expect(t.takeException(), isNull);
      } finally {
        await cleanup(t);
      }
    },
  );
  testWidgets('edit menus are neutral and footer has no white container', (
    t,
  ) async {
    try {
      await _launch(t, _Auth());
      await editStudent(t);
      expect(find.byType(AppBar), findsNothing);
      final dropdown = find.byType(DropdownButtonFormField<String>);
      expect(
        Theme.of(t.element(dropdown)).colorScheme.primary,
        const Color(0xFF18212F),
      );
      final footer = find.text('Update on Portal');
      final boxes = t.widgetList<Container>(
        find.ancestor(of: footer, matching: find.byType(Container)),
      );
      expect(
        boxes.where(
          (c) =>
              c.decoration is BoxDecoration &&
              (c.decoration! as BoxDecoration).color == Colors.white,
        ),
        isEmpty,
      );
      expect(
        t
            .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
            .dropdownColor,
        Colors.white,
      );
      await t.ensureVisible(dropdown);
      await t.tap(dropdown);
      await t.pumpAndSettle();
      expect(find.text('OBC').hitTestable(), findsOneWidget);
      await t.tap(find.text('OBC').last);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    } finally {
      await cleanup(t);
    }
  });
  testWidgets('large text uses stacked footer actions without overflow', (
    t,
  ) async {
    try {
      await _launch(t, _Auth(), textScale: 1.5);
      await editStudent(t);
      final update = t.getRect(
        find.widgetWithText(FilledButton, 'Update on Portal'),
      );
      final cancel = t.getRect(find.widgetWithText(OutlinedButton, 'Cancel'));
      expect(update.bottom, lessThan(cancel.top));
      expect(update.width, closeTo(cancel.width, .001));
      expect(t.takeException(), isNull);
    } finally {
      await cleanup(t);
    }
  });
  testWidgets(
    'portal outcome is shown once and filter change clears the old outcome',
    (t) async {
      final auth = _Auth();
      try {
        await _launch(t, auth);
        await editStudent(t);
        await confirm(t);
        await t.tap(find.text('Update'));
        await t.pumpAndSettle();
        expect(auth.updates, 1);
        expect(
          find.text('Success : Student profile has been updated successfully.'),
          findsOneWidget,
        );
        expect(find.byType(SnackBar), findsNothing);
        final dropdown = find.byType(DropdownButtonFormField<String>).at(1);
        await t.ensureVisible(dropdown);
        await t.tap(dropdown);
        await t.pumpAndSettle();
        await t.tap(find.text('2').last);
        await t.pumpAndSettle();
        expect(
          find.text('Success : Student profile has been updated successfully.'),
          findsNothing,
        );
        expect(find.byType(SnackBar), findsNothing);
        expect(t.takeException(), isNull);
      } finally {
        await cleanup(t);
      }
    },
  );
  testWidgets(
    'wide list and edit use the adaptive canvas with side-by-side panels',
    (t) async {
      try {
        await _launch(t, _Auth(), size: const Size(1920, 1080));
        expect(
          t.getSize(find.byKey(const ValueKey('format5-list-workspace'))).width,
          closeTo(AppAdaptive.contentWidth(1920), .001),
        );
        final content = t.getRect(find.byKey(const ValueKey('format5-search')));
        final refresh = t.getCenter(find.byTooltip('Refresh portal'));
        final back = t.getCenter(find.byType(BackButton));
        expect(refresh.dy, closeTo(back.dy, .001));
        expect(
          content.right - refresh.dx,
          closeTo(back.dx - content.left, .001),
        );
        await editStudent(t);
        expect(
          t.getSize(find.byKey(const ValueKey('format5-edit-workspace'))).width,
          closeTo(AppAdaptive.contentWidth(1920), .001),
        );
        final first = t.getRect(
          find.byKey(const ValueKey('format5-details-card')),
        );
        final second = t.getRect(
          find.byKey(const ValueKey('format5-fields-card')),
        );
        expect(second.left, greaterThan(first.right));
        expect(second.top, closeTo(first.top, .001));
        expect(second.width, greaterThan(first.width));
        expect(second.height, closeTo(first.height, .001));
        expect(t.takeException(), isNull);
      } finally {
        await cleanup(t);
      }
    },
  );
  testWidgets(
    'confirmation reviews only changed values and uses neutral buttons',
    (t) async {
      final auth = _Auth();
      try {
        await _launch(t, auth);
        await editStudent(t);
        await confirm(t);
        final dialog = find.byType(AlertDialog);
        expect(
          find.descendant(of: dialog, matching: find.text('Sample Student')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: dialog, matching: find.text('NIC ID: 00001')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: dialog, matching: find.text('9000000000')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: dialog, matching: find.text('9111111111')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: dialog, matching: find.text('SR Number')),
          findsNothing,
        );
        final cancel = find.widgetWithText(TextButton, 'Keep Editing');
        final button = t.widget<TextButton>(cancel);
        expect(
          button.style!.foregroundColor!.resolve({}),
          const Color(0xFF18212F),
        );
        final overlay = button.style!.overlayColor!.resolve({
          WidgetState.hovered,
        })!;
        expect(overlay.toARGB32() & 0xFFFFFF, 0x18212F);
        expect(
          Theme.of(t.element(cancel)).colorScheme.primary,
          const Color(0xFF18212F),
        );
        final update = t.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Update'),
        );
        expect(
          update.style!.overlayColor!.resolve({WidgetState.pressed}),
          const Color(0x1AFFFFFF),
        );
        await t.tap(cancel);
        await t.pumpAndSettle();
        expect(auth.updates, 0);
        expect(find.text('Edit Student Profile'), findsOneWidget);
        expect(t.takeException(), isNull);
      } finally {
        await cleanup(t);
      }
    },
  );
  testWidgets(
    'small-screen review fits with large text and keeps editing without save',
    (t) async {
      final auth = _Auth();
      try {
        await _launch(t, auth, size: const Size(320, 560), textScale: 1.5);
        await editStudent(t);
        await confirm(t);
        expect(t.takeException(), isNull);
        await t.tap(find.text('Keep Editing'));
        await t.pumpAndSettle();
        expect(auth.updates, 0);
        expect(t.takeException(), isNull);
      } finally {
        await cleanup(t);
      }
    },
  );
  testWidgets('desktop scroll thumb has a separate gutter from student cards', (
    t,
  ) async {
    final auth = _Auth()..manyStudents = true;
    try {
      await _launch(t, auth, size: const Size(1920, 1080));
      await showStudents(t);
      await t.scrollUntilVisible(
        find.text('Sample Student 20'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      final bar = find.byKey(const ValueKey('format5-scrollbar'));
      expect(find.byType(Scrollbar), findsOneWidget);
      final barRect = t.getRect(bar);
      final viewport = t.getRect(find.byType(CustomScrollView));
      final card = t.getRect(
        find.byKey(const ValueKey('format5-student-00020')),
      );
      expect(barRect.right - viewport.right, greaterThanOrEqualTo(14));
      expect(card.right, lessThanOrEqualTo(viewport.right));
      expect(t.widget<Scrollbar>(bar).controller!.hasClients, isTrue);
      expect(t.takeException(), isNull);
    } finally {
      await cleanup(t);
    }
  }, variant: TargetPlatformVariant.desktop());
  testWidgets(
    'portal close glyph is excluded and success can be dismissed on small screens',
    (t) async {
      final auth = _Auth()..closeSuccess = true;
      try {
        await _launch(t, auth, size: const Size(320, 560), textScale: 1.5);
        await editStudent(t);
        await confirm(t);
        await t.tap(find.text('Update'));
        await t.pumpAndSettle();
        expect(
          find.text('Success : Student profile has been updated successfully.'),
          findsOneWidget,
        );
        expect(find.textContaining('×'), findsNothing);
        expect(
          find.byKey(const ValueKey('format5-success-badge')),
          findsOneWidget,
        );
        final badge = t.widget<Image>(
          find.byKey(const ValueKey('format5-success-badge')),
        );
        expect(
          ((badge.image as ResizeImage).imageProvider as AssetImage).assetName,
          'assets/icons/check.png',
        );
        await t.tap(find.byTooltip('Dismiss success message'));
        await t.pumpAndSettle();
        expect(
          find.text('Success : Student profile has been updated successfully.'),
          findsNothing,
        );
        expect(find.byTooltip('Dismiss success message'), findsNothing);
        expect(auth.updates, 1);
        expect(t.takeException(), isNull);
      } finally {
        await cleanup(t);
      }
    },
  );
  testWidgets('closing a banner does not close a different outcome', (t) async {
    final auth = _Auth()
      ..closeSuccess = true
      ..failRefresh = true;
    try {
      await _launch(t, auth);
      await editStudent(t);
      await confirm(t);
      await t.tap(find.text('Update'));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Dismiss error message'));
      await t.pumpAndSettle();
      expect(find.textContaining('Offline refresh fixture'), findsNothing);
      expect(
        find.text('Success : Student profile has been updated successfully.'),
        findsOneWidget,
      );
      await t.tap(find.byTooltip('Dismiss success message'));
      await t.pumpAndSettle();
      expect(
        find.text('Success : Student profile has been updated successfully.'),
        findsNothing,
      );
      expect(auth.updates, 1);
      expect(t.takeException(), isNull);
    } finally {
      await cleanup(t);
    }
  });
  testWidgets('literal multiplication sign inside portal words is preserved', (
    t,
  ) async {
    final auth = _Auth()
      ..closeSuccess = true
      ..successSuffix = ' 2 × 3';
    try {
      await _launch(t, auth);
      await editStudent(t);
      await confirm(t);
      await t.tap(find.text('Update'));
      await t.pumpAndSettle();
      expect(
        find.text(
          'Success : Student profile has been updated successfully. 2 × 3',
        ),
        findsOneWidget,
      );
      expect(auth.updates, 1);
      expect(t.takeException(), isNull);
    } finally {
      await cleanup(t);
    }
  });
  testWidgets(
    'edit saves once and system back is blocked while update is pending',
    (t) async {
      final auth = _Auth()..saveGate = Completer<void>();
      try {
        await _launch(t, auth);
        await editStudent(t);
        await confirm(t);
        await t.tap(find.text('Update'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 250));
        expect(auth.updates, 1);
        final nav = t.state<NavigatorState>(find.byType(Navigator).first);
        await nav.maybePop();
        await t.pump();
        expect(find.text('Edit Student Profile'), findsOneWidget);
        expect(
          t
              .widget<FilledButton>(
                find.byWidgetPredicate((w) => w is FilledButton).last,
              )
              .onPressed,
          isNull,
        );
        auth.saveGate!.complete();
        await t.pumpAndSettle();
        expect(auth.updates, 1);
        expect(find.text('Edit Student Profile'), findsNothing);
        expect(
          find.text('Success : Student profile has been updated successfully.'),
          findsWidgets,
        );
        expect(t.takeException(), isNull);
      } finally {
        if (!auth.saveGate!.isCompleted) auth.saveGate!.complete();
        await cleanup(t);
      }
    },
  );
  testWidgets('login change while confirmation is open prevents submission', (
    t,
  ) async {
    final auth = _Auth();
    try {
      await _launch(t, auth);
      await editStudent(t);
      await confirm(t);
      DirectSchoolSession.attach(_Auth(), '999');
      await t.tap(find.text('Update'));
      await t.pumpAndSettle();
      expect(auth.updates, 0);
      expect(
        find.text('School login has changed. Reopen Format 5.'),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    } finally {
      await cleanup(t);
    }
  });
  testWidgets('stale list result is not shown after school changes', (t) async {
    final auth = _Auth()..listGate = Completer<void>();
    try {
      await _launch(t, auth);
      await t.tap(find.text('Show Students'));
      await t.pump();
      DirectSchoolSession.attach(_Auth(), '999');
      auth.listGate!.complete();
      await t.pumpAndSettle();
      expect(find.text('Sample Student'), findsNothing);
      expect(
        find.text('School login has changed. Reopen Format 5.'),
        findsWidgets,
      );
      expect(t.takeException(), isNull);
    } finally {
      if (!auth.listGate!.isCompleted) auth.listGate!.complete();
      await cleanup(t);
    }
  });
  testWidgets('small height scrolls filters and list without overflow', (
    t,
  ) async {
    try {
      await _launch(t, _Auth(), size: const Size(320, 360));
      await showStudents(t);
      await t.scrollUntilVisible(
        find.text('Sample Student'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      expect(find.text('Sample Student'), findsOneWidget);
      expect(t.takeException(), isNull);
    } finally {
      await cleanup(t);
    }
  });
  testWidgets('uncertain save cannot be sent again from the edit page', (
    t,
  ) async {
    final auth = _Auth()..ambiguous = true;
    try {
      await _launch(t, auth);
      await editStudent(t);
      await confirm(t);
      await t.tap(find.text('Update'));
      await t.pumpAndSettle();
      expect(auth.updates, 1);
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Update on Portal'),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('Edit Student Profile'), findsOneWidget);
      final requestsBeforeBack = auth.requests;
      await t.state<NavigatorState>(find.byType(Navigator).first).maybePop();
      await t.pumpAndSettle();
      expect(auth.requests, greaterThan(requestsBeforeBack));
      expect(auth.updates, 1);
      expect(find.text('Sample Student'), findsOneWidget);
      expect(t.takeException(), isNull);
    } finally {
      await cleanup(t);
    }
  });
  testWidgets(
    'portal success remains visible when the later list refresh fails',
    (t) async {
      final auth = _Auth()..failRefresh = true;
      try {
        await _launch(t, auth);
        await editStudent(t);
        await confirm(t);
        await t.tap(find.text('Update'));
        await t.pumpAndSettle();
        expect(auth.updates, 1);
        expect(
          find.text('Success : Student profile has been updated successfully.'),
          findsWidgets,
        );
        expect(find.textContaining('Offline refresh fixture'), findsWidgets);
        expect(t.takeException(), isNull);
      } finally {
        await cleanup(t);
      }
    },
  );
}
