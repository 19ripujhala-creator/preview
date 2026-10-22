import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../lib/services/portals/shaladarpan/direct/native_print_browser.dart';
import '../../lib/services/portals/shaladarpan/direct/native_print_worker.dart';
import '../../lib/services/portals/shaladarpan/direct/nic_catalog_worker.dart';
import '../../lib/experiments/direct_native_print_service.dart';
import '../../lib/experiments/direct_portal_auth.dart';

class FakeNativeBrowser implements NativePrintBrowser {
  FakeNativeBrowser([this.mode = 'normal']);
  final String mode;
  String path = '', school = '123456';
  int renders = 0, htmlReads = 0, page = 1;
  bool closed = false, popupClosed = false;
  final calls = <String>[];
  final scripts = <String>[];
  final selected = {
    'ddlSession': '2026-27',
    'ContentPlaceHolder1_ddlClass': '1',
    'ContentPlaceHolder1_ddlSection': '1',
  };
  static const certificate =
      'Original portal certificate for the selected student; Hindi and English text.';
  String roster() {
    final name = mode == 'changed_roster' && htmlReads > 1
        ? 'Changed Student'
        : 'Student $page';
    final student = mode == 'repeated_page' ? '1' : '$page';
    final row =
        '<tr><td><span id="x_lblSnicid_0">NIC$student</span></td><td><span id="x_lblName_0">$name</span></td><td><span id="x_lblSRNO_0">$page</span></td></tr>';
    final pager = (mode == 'pagination' || mode == 'repeated_page') && page == 1
        ? '<a href="javascript:__doPostBack(\'ctl00\$ContentPlaceHolder1\$grdStudentProfile\',\'Page\$2\')">2</a>'
        : '';
    return '<div id="dvReport"><table id="ContentPlaceHolder1_grdStudentProfile"><tr><th>NIC ID</th></tr>$row${mode == 'duplicate' ? row : ''}<tr><td>$pager</td></tr></table></div>';
  }

  @override
  Future<void> begin(Uri base, Map<String, String> cookies) async {
    calls.add('begin');
    expect(base.toString(), 'https://rajshaladarpan.rajasthan.gov.in/SD1');
    expect(cookies, {'session': 'synthetic-cookie'});
    if (mode == 'missing_plugin')
      throw const NicError(
        'NATIVE_PRINT_UNAVAILABLE',
        'Native portal printing is not installed for this platform.',
      );
  }

  @override
  Future<void> navigate(String value) async {
    path = value;
    calls.add('navigate:$value');
  }

  @override
  Future<Object?> evaluate(String expression, {bool popup = false}) async {
    calls.add('eval${popup ? ':popup' : ''}');
    scripts.add(expression);
    if (expression.contains('ready:document.readyState'))
      return {
        'url': 'https://rajshaladarpan.rajasthan.gov.in/SD1/$path',
        'ready': true,
        'text': 'Original portal page',
      };
    if (expression.contains('filter(o => o.value.trim()')) {
      final id = RegExp(r'getElementById\("([^"\n]+)"\)')
          .firstMatch(expression)![1]!;
      if (id == 'ddlSession')
        return [
          {'id': '2026-27', 'label': '2026-27', 'selected': true},
        ];
      if (id == 'ContentPlaceHolder1_ddlClass')
        return [
          {'id': '1', 'label': '1', 'selected': true},
        ];
      return [
        {'id': '1', 'label': 'A', 'selected': true},
      ];
    }
    if (expression.contains("getAttribute('onchange')")) return false;
    if (expression.contains('e.dispatchEvent')) {
      final id = RegExp(r'getElementById\("([^"\n]+)"\)')
          .firstMatch(expression)![1]!;
      final value = RegExp(r'e.value="([^"\n]+)"').firstMatch(expression)![1]!;
      selected[id] = value;
      calls.add('select:$id:$value');
      return null;
    }
    if (expression.contains('session:document.querySelector'))
      return {
        'session': '2026-27',
        'cls': mode == 'wrong_selection' ? '2' : '1',
        'section': '1',
      };
    if (expression == '[document.documentElement.outerHTML]') {
      if (popup)
        return [
          '<body>2026-27 1 A NIC$page ${mode == 'wrong_popup' ? 'Other Student<script>Student $page</script>' : 'Student $page'}</body>',
        ];
      htmlReads++;
      return [roster()];
    }
    if (expression.contains('Array.from(document.images).some'))
      return mode == 'broken_image';
    if (expression.contains("a[id*=\"btnUpdate\"]")) {
      if (mode == 'not_found') return [];
      final rows = [
        {
          'cells': ['001', 'Student'],
          'links': ['native_btnUpdate_0'],
        },
      ];
      if (mode == 'ambiguous')
        rows.add({
          'cells': ['1', 'Another'],
          'links': ['native_btnUpdate_1'],
        });
      return rows;
    }
    if (expression.contains('ContentPlaceHolder1_upPnl'))
      return ['Original portal no-record notice'];
    if (expression == "[document.getElementById('dvReport').innerText]")
      return [certificate];
    if (expression == '[document.body.innerText]')
      return [mode == 'wrong_certificate' ? 'Other certificate' : certificate];
    if (expression.contains('getClientRects') ||
        expression.contains('document.fonts') ||
        expression.startsWith('!!document.body'))
      return true;
    if (expression.startsWith('!!document.getElementById')) return true;
    if (expression.contains('getBoundingClientRect')) return 200;
    return null;
  }

  @override
  Future<void> postback(String expression, {String? grid}) async {
    calls.add('post:$grid');
    scripts.add(expression);
    expect(expression.contains('btn_Lock'), false);
    expect(expression.contains('btnSave'), false);
    if (mode == 'portal_alert')
      throw const NicError('PORTAL_MESSAGE', 'Original portal alert');
    if (expression.contains('__doPostBack')) page++;
  }

  @override
  Future<void> openPopup(String expression) async {
    calls.add('popup');
    scripts.add(expression);
    expect(expression.contains('preventDefault'), true);
    expect(expression.contains('document.write'), false);
  }

  @override
  Future<String> renderPopup() async {
    calls.add('render');
    return 'original-pdf-${++renders}';
  }

  @override
  Future<Uint8List> merge(List<String> ids) async {
    calls.add('merge:${ids.join(',')}');
    return Uint8List.fromList(ascii.encode('%PDF-offline-boundary'));
  }

  @override
  Future<void> closePopup() async {
    popupClosed = true;
    calls.add('closePopup');
  }

  @override
  Future<void> close() async {
    closed = true;
    calls.add('close');
  }
}

class NativeAuth extends DirectPortalAuth {
  NativeAuth();
  bool verified = true;
  String identity = 'source-session';
  @override
  bool get isVerified => verified;
  @override
  String get schoolSessionIdentity => identity;
  @override
  String get verifiedNode => 'SD1';
  @override
  String? get authenticatedSchoolId => '123456';
  @override
  Map<String, String> nativePrintCookies() => {'session': 'synthetic-cookie'};
}

void main() {
  final goldens = jsonDecode(
    File('test/direct/fixtures/python_native_nic_identities.json')
        .readAsStringSync(),
  ) as List;
  for (final value in goldens) {
    final expected = value['result'] as Map;
    test('original Python report identity parity: ${value['name']}', () {
      if (expected['code'] != null) {
        expect(
          () => NicSheetWorker.nicIdentities(value['html'] as String),
          throwsA(
            isA<NicError>()
                .having((e) => e.code, 'code', expected['code'])
                .having((e) => e.message, 'message', expected['message']),
          ),
        );
      } else {
        expect(
          NicSheetWorker.nicIdentities(value['html'] as String)
              .map((r) => [r.$1, r.$2, r.$3])
              .toList(),
          expected['identities'],
        );
      }
    });
  }
  for (final sr in ['1', '001', '0001', '0', '000']) {
    test('certificate matches full SR cell including leading zeros: $sr', () {
      final cell = sr.replaceAll('1', '01');
      expect(
        StudyCertificateWorker.certificateLink([
          {
            'cells': [cell],
            'links': ['exact_link'],
          },
        ], sr),
        'exact_link',
      );
    });
  }
  test(
    'certificate does not accept a substring SR',
    () => expect(
      () => StudyCertificateWorker.certificateLink([
        {
          'cells': ['123'],
          'links': ['a'],
        },
      ], '23'),
      throwsA(isA<NicError>().having((e) => e.code, 'code', 'MATCH_MISMATCH')),
    ),
  );
  test(
    'ambiguous SR blocks certificate print',
    () => expect(
      () => StudyCertificateWorker.certificateLink([
        {
          'cells': ['1'],
          'links': ['a'],
        },
        {
          'cells': ['001'],
          'links': ['b'],
        },
      ], '1'),
      throwsA(isA<NicError>().having((e) => e.code, 'code', 'MATCH_MISMATCH')),
    ),
  );
  test(
    'multiple links block certificate print',
    () => expect(
      () => StudyCertificateWorker.certificateLink([
        {
          'cells': ['1'],
          'links': ['a', 'b'],
        },
      ], '1'),
      throwsA(isA<NicError>()),
    ),
  );
  test(
    'no-record notice remains exact',
    () => expect(
      () => StudyCertificateWorker.certificateLink(
        [],
        '1',
        notice: 'Original notice',
      ),
      throwsA(
        isA<NicError>().having((e) => e.message, 'message', 'Original notice'),
      ),
    ),
  );
  String pager(String link) =>
      '<table id="ContentPlaceHolder1_grdStudentProfile"><tr><td><a href="$link">next</a></td></tr></table>';
  test(
    'native pager target and argument retained',
    () => expect(
      NicSheetWorker.nextPage(
        pager("javascript:__doPostBack('ctl00\$grdStudentProfile','Page\$2')"),
        1,
      ),
      ('ctl00\$grdStudentProfile', 'Page\$2'),
    ),
  );
  test(
    'missing next page cannot produce partial PDF',
    () => expect(
      () => NicSheetWorker.nextPage(
        pager("javascript:__doPostBack('ctl00\$grdStudentProfile','Page\$3')"),
        1,
      ),
      throwsA(isA<NicError>()),
    ),
  );
  test(
    'unverified pager target cannot be clicked',
    () => expect(
      () => NicSheetWorker.nextPage(
        pager("javascript:__doPostBack('Other','Page\$Next')"),
        1,
      ),
      throwsA(isA<NicError>()),
    ),
  );
  test(
    'no pager ends native section',
    () => expect(NicSheetWorker.nextPage(pager('Other'), 1), isNull),
  );
  for (final mode in ['normal', 'pagination']) {
    test('complete native NIC flow and original result: $mode', () async {
      final browser = FakeNativeBrowser(mode), auth = NativeAuth();
      final progress = <List<int>>[];
      try {
        final result = await DirectNativePrintService(
          auth,
          browserFactory: () => browser,
        ).nicPdf('123456', progress: (a, b) => progress.add([a, b]));
        expect(result['success'], true);
        expect(result['student_count'], mode == 'pagination' ? 2 : 1);
        expect(result['class_count'], 1);
        expect(result['section_count'], 1);
        expect(result['filename'], 'NIC_Sheet_123456_All_Classes_2026-27.pdf');
        expect(progress, [
          [1, 1],
        ]);
        expect(browser.renders, mode == 'pagination' ? 2 : 1);
        expect(browser.closed, true);
        final selectors = browser.calls
            .where((c) => c.startsWith('select:'))
            .toList();
        expect(selectors, [
          'select:ContentPlaceHolder1_ddlClass:1',
          'select:ddlSession:2026-27',
          'select:ContentPlaceHolder1_ddlClass:1',
          'select:ContentPlaceHolder1_ddlSection:1',
        ]);
        expect(browser.calls.where((c) => c.startsWith('merge:')).length, 1);
      } finally {
        auth.close();
      }
    });
  }
  for (final mode in [
    'duplicate',
    'changed_roster',
    'wrong_selection',
    'wrong_popup',
    'broken_image',
    'repeated_page',
    'portal_alert',
    'missing_plugin',
  ]) {
    test('unsafe/incomplete NIC $mode returns no PDF', () async {
      final browser = FakeNativeBrowser(mode), auth = NativeAuth();
      try {
        final result = await DirectNativePrintService(
          auth,
          browserFactory: () => browser,
        ).nicPdf('123456');
        expect(result['success'], false);
        expect(result.containsKey('pdf_base64'), false);
        expect(browser.calls.any((c) => c.startsWith('merge:')), false);
        expect(browser.closed, true);
        if (mode == 'portal_alert')
          expect(result['message'], 'Original portal alert');
      } finally {
        auth.close();
      }
    });
  }
  for (final mode in [
    'normal',
    'not_found',
    'ambiguous',
    'wrong_certificate',
    'broken_image',
  ]) {
    test(
      'complete native certificate $mode preserves source behavior',
      () async {
        final browser = FakeNativeBrowser(mode), auth = NativeAuth();
        final progress = <List<int>>[];
        try {
          final result = await DirectNativePrintService(
            auth,
            browserFactory: () => browser,
          ).studyPdf('123456', '1', progress: (a, b) => progress.add([a, b]));
          expect(result['success'], mode == 'normal');
          expect(browser.closed, true);
          if (mode == 'normal') {
            expect(result['filename'], 'Study_Certificate_123456_SR_1.pdf');
            expect(progress, [
              [1, 4],
              [2, 4],
              [3, 4],
              [4, 4],
            ]);
            expect(browser.renders, 1);
          } else
            expect(browser.renders, 0);
          if (mode == 'not_found')
            expect(result['message'], 'Original portal no-record notice');
        } finally {
          auth.close();
        }
      },
    );
  }
  for (final invalid in [
    '',
    '123A',
    '-1',
    '1.5',
    '1234567890123456789012345678901',
  ]) {
    test('invalid SR rejected before browser: $invalid', () async {
      final auth = NativeAuth();
      var created = false;
      try {
        final result = await DirectNativePrintService(
          auth,
          browserFactory: () {
            created = true;
            return FakeNativeBrowser();
          },
        ).studyPdf('123456', invalid);
        expect(result['code'], 'BAD_SR');
        expect(created, false);
      } finally {
        auth.close();
      }
    });
  }
  test('native print never relogs or starts with an expired session', () async {
    final auth = NativeAuth()..verified = false;
    var created = false;
    try {
      expect(
        (await DirectNativePrintService(
          auth,
          browserFactory: () {
            created = true;
            return FakeNativeBrowser();
          },
        ).nicPdf('123456'))['code'],
        'SESSION_EXPIRED',
      );
      expect(created, false);
    } finally {
      auth.close();
    }
  });
  test('account change during native output discards the PDF', () async {
    final auth = NativeAuth(), browser = FakeNativeBrowser();
    try {
      final result =
          await DirectNativePrintService(
            auth,
            browserFactory: () => browser,
          ).nicPdf(
            '123456',
            progress: (a, b) {
              auth.identity = 'new-session';
            },
          );
      expect(result['code'], 'SESSION_CHANGED');
      expect(result.containsKey('pdf_base64'), false);
      expect(browser.closed, true);
    } finally {
      auth.close();
    }
  });
}
