import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../lib/services/portals/shaladarpan/direct/native_print_browser.dart';
import '../../lib/services/portals/staff_login/direct/format10_worker.dart';
import '../../lib/services/portals/staff_login/direct/leave_pdf_worker.dart';
import '../../lib/services/portals/staff_login/direct/native_print_service.dart';
import '../../lib/services/portals/staff_login/direct/http_auth.dart';
import '../../lib/services/portals/staff_login/direct/portal_state.dart';
import '../../lib/services/portals/staff_login/direct/staff_runtime.dart'
    show StaffCoordinator;
import 'staff_auth_test.dart'
    show StaffFakeTransport, StaffMemoryStorage, staffTestBase;
import 'staff_read_test.dart' show ReadBackend, authenticated;

final printGoldens = jsonDecode(
  File('test/direct/fixtures/python_staff_print.json').readAsStringSync(),
) as Map;

class StaffFakePrintBrowser implements StaffPrintBrowser {
  String path = '', modal = 'divCLLeaveApplication';
  bool checked = false,
      closed = false,
      popupClosed = false,
      wrongPopupDate = false;
  bool noPrint = false, missingTrigger = false, mismatchModal = false;
  int viewClicks = 0, page = 1, renders = 0;
  final calls = <String>[], scripts = <String>[];
  final margins = <int>[];
  List<Map<String, dynamic>> cookies = [];
  String home = '<a id="lnkLogout">Logout</a>';
  void Function()? afterCapture;
  bool paginate = false;
  bool disabledTab = false;
  @override
  Future<void> begin(Uri base, Map<String, String> cookies) async =>
      throw StateError('Staff must preserve cookie paths');
  @override
  Future<void> beginStaff(Uri base, List<Map<String, dynamic>> value) async {
    cookies = value;
    calls.add('begin:$base');
  }

  @override
  Future<List<Map<String, dynamic>>> staffCookies() async => [
    for (final c in cookies) {...c, 'value': 'rotated'},
  ];
  @override
  Future<void> navigate(String value) async {
    path = value;
    calls.add(value);
  }

  @override
  Future<Object?> evaluate(String expression, {bool popup = false}) async {
    scripts.add(expression);
    if (expression.contains('document.documentElement.outerHTML')) {
      String content;
      if (popup) {
        content = path.contains('P10')
            ? 'प्रपत्र - 10'
            : '${leaveModalRequiredStrings[modal]?.join(' ') ?? ''} ${wrongPopupDate ? 'wrong date' : '01-10-2026 03-10-2026'}';
      } else if (path.contains('StaffHome')) {
        content = home;
      } else if (path.contains('P10')) {
        content = '<input id="ContentPlaceHolder1_ucP10Print_ImageButton1">';
      } else {
        content = printGoldens['html'] as String;
        if (paginate && page == 1)
          content =
              content.replaceAll('<td>3</td>', '<td>8</td>') +
              '<a href="javascript:__doPostBack(\'grid\',\'Page\$2\')">2</a>';
      }
      return {'url': '$staffTestBase/$path', 'text': content};
    }
    if (expression.startsWith('[window.__rajPrintPost')) {
      final function = openModalFunctionToId.entries
          .firstWhere((e) => e.value == modal)
          .key;
      return [
        missingTrigger
            ? ''
            : 'scriptStartupBlock|ScriptContentNoTags|$function();|',
      ];
    }
    if (expression.contains('const excluded=')) {
      if (expression.startsWith('!!') || expression.contains('?.text_length'))
        return true;
      return {
        'modal_id': mismatchModal ? 'divCCLApplication' : modal,
        'button_id': noPrint ? null : 'officialPrint',
        'text_length': 300,
      };
    }
    if (expression.contains("?.checked")) return checked;
    if (expression.startsWith('!!document.querySelector') ||
        expression.contains('getClientRects') ||
        expression.startsWith('!!document.getElementById') ||
        expression.contains('document.readyState') ||
        expression.contains('document.fonts') ||
        expression.contains('get_isInAsyncPostBack'))
      return true;
    return null;
  }

  @override
  Future<void> postback(String expression, {String? grid}) async {
    scripts.add(expression);
    calls.add('postback');
    if (disabledTab)
      throw const StaffPortalError(
        'PAGE_NOT_READY',
        'View and Lock tab is disabled.',
      );
    if (expression.contains('rdoLeaveApplicationType')) checked = true;
    if (expression.contains('ImgView')) viewClicks++;
    if (expression.contains('Page\$2')) page = 2;
  }

  @override
  Future<void> openPopup(String expression) async {
    scripts.add(expression);
    calls.add('popup');
  }

  @override
  Future<String> renderPopup() async =>
      throw StateError('Staff must select source margins');
  @override
  Future<String> renderStaffPopup({required int marginMm}) async {
    margins.add(marginMm);
    renders++;
    afterCapture?.call();
    return 'official-pdf';
  }

  @override
  Future<Uint8List> merge(List<String> pdfIds) async =>
      Uint8List.fromList(utf8.encode('%PDF-offline'));
  @override
  Future<void> closePopup() async {
    popupClosed = true;
  }

  @override
  Future<void> abort() async {}
  @override
  Future<void> close() async {
    closed = true;
  }
}

class StaffCloseFailureBrowser extends StaffFakePrintBrowser {
  @override
  Future<void> closePopup() async {
    await super.closePopup();
    throw const StaffPortalError('PAGE_NOT_READY', 'Popup close failed.');
  }
}

void main() {
  test('Format10 reports original failure stage and control message', () async {
    final browser = StaffFakePrintBrowser()..disabledTab = true;
    await expectLater(
      Format10Worker(browser: browser, check: () {}).generate(),
      throwsA(
        isA<Format10StageError>()
            .having((e) => e.stage, 'stage', 'open_view_lock_tab')
            .having(
              (e) => e.message,
              'message',
              'View and Lock tab is disabled.',
            ),
      ),
    );
    expect(browser.renders, 0);
  });
  test(
    'Format10 retains valid capture if popup close fails, as Python does',
    () async {
      final result = await Format10Worker(
        browser: StaffCloseFailureBrowser(),
        check: () {},
      ).generate();
      expect(result['success'], true);
    },
  );
  for (final c in printGoldens['dates'] as List) {
    test(
      'Python date normalization ${c['input']}',
      () =>
          expect(normalizeStaffLeaveDate(c['input'] as String), c['expected']),
    );
  }
  for (var i = 0; i < (printGoldens['rows'] as List).length; i++) {
    final c = printGoldens['rows'][i] as Map, a = c['args'] as Map;
    test(
      'Python exact leave row $i',
      () => expect(
        findLeaveViewOnPage(
          printGoldens['html'] as String,
          sNo: a['s_no'],
          fromDate: a['from_date'],
          toDate: a['to_date'],
          leaveType: a['leave_type'],
        ).button,
        c['expected'],
      ),
    );
  }
  test(
    'Required modal strings equal Python constants',
    () => expect(leaveModalRequiredStrings, printGoldens['required']),
  );
  for (final marker in format10RequiredStrings) {
    test(
      'Format10 source accepts either official marker: $marker',
      () => expect(format10PopupHasOfficialContent(marker), true),
    );
  }
  test(
    'Format10 refuses unverified empty popup',
    () => expect(format10PopupHasOfficialContent('loading'), false),
  );
  for (final e in openModalFunctionToId.entries) {
    test(
      'Source startup block ${e.key}',
      () => expect(
        leaveResponseModal(
          'scriptStartupBlock|ScriptContentNoTags|${e.key}();|',
        ),
        e.value,
      ),
    );
  }
  test(
    'Other response scripts do not invent a modal',
    () => expect(leaveResponseModal('OpenPrintPopClLeave();'), null),
  );
  for (final modal in leaveModalRequiredStrings.keys) {
    test(
      'Verify official $modal popup and both dates',
      () => validateStaffLeavePopup(
        '${leaveModalRequiredStrings[modal]!.join(' ')} 01-10-2026 03-10-2026',
        modal,
        '2026-10-01',
        '2026-10-03',
      ),
    );
    test(
      'Reject missing official $modal text',
      () => expect(
        () => validateStaffLeavePopup(
          '01-10-2026 03-10-2026',
          modal,
          '01-10-2026',
          '03-10-2026',
        ),
        throwsA(isA<StaffPortalError>()),
      ),
    );
    test(
      'Reject wrong $modal dates',
      () => expect(
        () => validateStaffLeavePopup(
          leaveModalRequiredStrings[modal]!.join(' '),
          modal,
          '01-10-2026',
          '03-10-2026',
        ),
        throwsA(isA<StaffPortalError>()),
      ),
    );
  }
  test(
    'Format10 follows official View tab then print and source 5mm margins',
    () async {
      final b = StaffFakePrintBrowser();
      final result = await Format10Worker(
        browser: b,
        check: () {},
      ).generate(nicId: 'informational');
      expect(result['success'], true);
      expect(b.margins, [5]);
      expect(b.popupClosed, true);
      expect(b.calls, [
        'Home/Staff/Staff_P10_DetailsV2.aspx',
        'postback',
        'popup',
      ]);
      expect(
        b.scripts.any(
          (s) =>
              s.contains('btnLock') ||
              s.contains('Staff_LeaveApplication.aspx'),
        ),
        false,
      );
    },
  );
  for (final modal in leaveModalRequiredStrings.keys) {
    test(
      'Source View/CallPrint $modal capture, one View and 10mm margins',
      () async {
        final b = StaffFakePrintBrowser()..modal = modal;
        final result = await LeavePdfWorker(
          browser: b,
          check: () {},
        ).generate(sNo: '3', fromDate: '01-10-2026', toDate: '03-10-2026');
        expect(result['source'], 'native_$modal');
        expect(b.viewClicks, 1);
        expect(b.margins, [10]);
        expect(b.popupClosed, true);
        expect(
          b.scripts.any(
            (s) => s.contains('innerHTML =') || s.contains('document.write'),
          ),
          false,
        );
      },
    );
  }
  test('Source BFS locates row on subsequent page', () async {
    final b = StaffFakePrintBrowser()..paginate = true;
    await LeavePdfWorker(
      browser: b,
      check: () {},
    ).generate(sNo: '3', fromDate: '01-10-2026', toDate: '03-10-2026');
    expect(b.page, 2);
    expect(b.viewClicks, 1);
  });
  for (final mode in ['status', 'missing_button', 'mismatch', 'wrong_date']) {
    test(
      'Fail closed on $mode, never generate a substitute or click View twice',
      () async {
        final b = StaffFakePrintBrowser();
        if (mode == 'status') b.modal = 'divApplicationStatus';
        if (mode == 'missing_button') b.noPrint = true;
        if (mode == 'mismatch') b.mismatchModal = true;
        if (mode == 'wrong_date') b.wrongPopupDate = true;
        await expectLater(
          LeavePdfWorker(
            browser: b,
            check: () {},
          ).generate(sNo: '3', fromDate: '01-10-2026', toDate: '03-10-2026'),
          throwsA(isA<StaffPortalError>()),
        );
        expect(b.viewClicks, 1);
        expect(b.renders, 0);
      },
    );
  }
  test(
    'Absent startup capture uses live modal without re-clicking View',
    () async {
      final b = StaffFakePrintBrowser()..missingTrigger = true;
      final result = await LeavePdfWorker(
        browser: b,
        check: () {},
      ).generate(sNo: '3', fromDate: '01-10-2026', toDate: '03-10-2026');
      expect(result['success'], true);
      expect(b.viewClicks, 1);
    },
  );
  test('Missing leave identity stops before any browser request', () async {
    final b = StaffFakePrintBrowser();
    await expectLater(
      LeavePdfWorker(browser: b, check: () {}).generate(),
      throwsA(isA<StaffPortalError>()),
    );
    expect(b.calls, isEmpty);
  });
  test('Shared Staff session handoff, home verification, scoped cookie rotation and cleanup', () async {
    final storage = StaffMemoryStorage(), client = StaffFakeTransport();
    final session = authenticated(client);
    client.jar.receive([
      Cookie('session', 'one')
        ..domain = 'rajshaladarpan.rajasthan.gov.in'
        ..path = '/',
      Cookie('session', 'staff')
        ..domain = 'rajshaladarpan.rajasthan.gov.in'
        ..path = '/SD4/Home/Staff',
    ], Uri.parse(staffTestBase));
    final registry = StaffHttpAuth(storage: storage);
    await registry.install(session);
    final coordinator = StaffCoordinator(backend: ReadBackend(registry));
    final b = StaffFakePrintBrowser();
    try {
      final result = await StaffNativePrintService(
        registry: registry,
        coordinator: coordinator,
        browserFactory: () => b,
      ).format10Pdf('99');
      expect(result['success'], true);
      expect(b.cookies.map((e) => e['path']).toList(), [
        '/',
        '/SD4/Home/Staff',
      ]);
      expect(client.jar.records().map((e) => e['value']).toList(), [
        'rotated',
        'rotated',
      ]);
      expect(b.calls[1], 'Home/Staff/StaffHome.aspx');
      expect(b.closed, true);
      expect(client.requests, isEmpty);
      expect(storage.values[StaffHttpAuth.cookieKey], contains('rotated'));
    } finally {
      await coordinator.shutdown();
      await registry.closeSession();
    }
  });
  test('Account mismatch blocks native cookie handoff', () async {
    final registry = StaffHttpAuth(storage: StaffMemoryStorage());
    await registry.install(authenticated(StaffFakeTransport()));
    final coordinator = StaffCoordinator(backend: ReadBackend(registry));
    var created = false;
    try {
      final result = await StaffNativePrintService(
        registry: registry,
        coordinator: coordinator,
        browserFactory: () {
          created = true;
          return StaffFakePrintBrowser();
        },
      ).format10Pdf('other');
      expect(result['code'], 'ACCOUNT_CHANGED');
      expect(created, false);
    } finally {
      await coordinator.shutdown();
      await registry.closeSession();
    }
  });
}
