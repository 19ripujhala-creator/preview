import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../lib/experiments/direct_nic_catalog_service.dart';
import '../../lib/experiments/direct_portal_auth.dart';
import '../../lib/experiments/direct_school_session.dart';
import '../../lib/services/portals/shaladarpan/direct/nic_catalog_worker.dart';
import '../../lib/services/portals/shaladarpan/direct/student_attendance_worker.dart';

final nicBase = Uri.parse('https://rajshaladarpan.rajasthan.gov.in/SD1/');
final nicCases = jsonDecode(
  File('test/direct/fixtures/python_nic_catalog.json').readAsStringSync(),
) as List;

class NicAuth extends DirectPortalAuth {
  NicAuth(this.reply);
  final Future<AttendanceHttpReply> Function(Uri) reply;
  String identity = 'school-session-1';
  bool verified = true;
  @override
  bool get isVerified => verified;
  @override
  String get schoolSessionIdentity => identity;
  @override
  String? get authenticatedSchoolId => '123456';
  @override
  String get verifiedNode => 'SD1';
  @override
  Future<AttendanceHttpReply> nicCatalogRequest(
    Uri url, {
    Map<String, Object?>? fields,
    Uri? referer,
    Duration timeout = const Duration(seconds: 30),
  }) => reply(url);
}

class NicOfflineHttpClient implements HttpClient {
  int requests = 0;
  @override
  set connectionTimeout(Duration? value) {}
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    requests++;
    throw const SocketException('Network disabled in NIC guard tests');
  }

  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class NicGateAuth extends DirectPortalAuth {
  @override
  bool get isVerified => true;
}

NicCatalogWorker worker(
  Future<AttendanceHttpReply> Function(Uri, Map<String, Object?>?) send, {
  String Function()? school,
  void Function()? check,
  Uri? base,
}) => NicCatalogWorker(
  request:
      (url, {fields, referer, timeout = const Duration(seconds: 30)}) async {
        expect(timeout, const Duration(seconds: 30));
        if (fields != null) expect(referer, url);
        return send(url, fields);
      },
  baseUrl: () => base ?? nicBase,
  schoolId: school ?? () => '123456',
  check: check ?? () {},
);

void main() {
  for (final value in nicCases) {
    final c = Map<String, dynamic>.from(value as Map);
    test('original Python NIC catalog parity: ${c['name']}', () async {
      var requests = 0, posts = 0;
      final result = await worker((url, fields) async {
        requests++;
        if (fields != null) {
          posts++;
          expect(fields['__EVENTTARGET'], NicCatalogWorker.sessionName);
          expect(fields['__EVENTARGUMENT'], '');
          expect(fields['__VIEWSTATE'], 'state');
          expect(fields['__EVENTVALIDATION'], 'validation');
          expect(
            fields.keys.any(
              (k) => k.contains('btn_Lock') || k.contains('ScriptManager'),
            ),
            false,
          );
        }
        return (
          url: url,
          status: 200,
          html:
              (fields == null ? c['initial_html'] : c['after_html']) as String,
        );
      }).catalog(' 123456 ');
      expect(result, c['result']);
      expect(posts, c['posts']);
      expect(requests, 1 + posts);
    });
  }
  final normal = nicCases.first['initial_html'] as String;
  for (final kind in [
    'login',
    'foreign',
    'http500',
    'alert',
    'server',
    'timeout',
    'network',
  ]) {
    test('catalog rejects $kind without submission', () async {
      final result = await worker((url, fields) async {
        expect(fields, isNull);
        if (kind == 'timeout') throw TimeoutException('offline');
        if (kind == 'network') throw const SocketException('offline');
        return (
          url: kind == 'login'
              ? nicBase.resolve('OfficeLogin.aspx')
              : kind == 'foreign'
              ? Uri.parse('https://example.org/')
              : url,
          status: kind == 'http500' ? 500 : 200,
          html: kind == 'alert'
              ? "$normal<script>alert('Original portal message');</script>"
              : kind == 'server'
              ? '<body>Server Error in portal</body>'
              : normal,
        );
      }).catalog('123456');
      expect(result['success'], false);
      expect(
        result['code'],
        {
          'login': 'SESSION_EXPIRED',
          'foreign': 'PAGE_NOT_READY',
          'http500': 'PAGE_NOT_READY',
          'alert': 'PORTAL_MESSAGE',
          'server': 'PAGE_NOT_READY',
          'timeout': 'PORTAL_SLOW',
          'network': 'NETWORK_ERROR',
        }[kind],
      );
      if (kind == 'alert') expect(result['message'], 'Original portal message');
    });
  }
  test('wrong school is rejected before transport', () async {
    var sent = false;
    final result = await worker((url, _) async {
      sent = true;
      return (url: url, status: 200, html: normal);
    }).catalog('other');
    expect(result['code'], 'ACCOUNT_CHANGED');
    expect(sent, false);
  });
  test('changed school discards returned catalog', () async {
    var school = '123456';
    final result = await worker((url, _) async {
      school = 'other';
      return (url: url, status: 200, html: normal);
    }, school: () => school).catalog('123456');
    expect(result['code'], 'ACCOUNT_CHANGED');
  });
  test(
    'shared-session identity replacement discards returned catalog',
    () async {
      late NicAuth auth;
      auth = NicAuth((url) async {
        auth.identity = 'replacement';
        return (url: url, status: 200, html: normal);
      });
      try {
        expect(
          (await DirectNicCatalogService(auth).catalog('123456'))['code'],
          'SESSION_CHANGED',
        );
      } finally {
        auth.close();
      }
    },
  );
  test('expired direct session sends no request', () async {
    var sent = false;
    final auth = NicAuth((url) async {
      sent = true;
      return (url: url, status: 200, html: normal);
    })..verified = false;
    try {
      expect(
        (await DirectNicCatalogService(auth).catalog('123456'))['code'],
        'SESSION_EXPIRED',
      );
      expect(sent, false);
    } finally {
      auth.close();
    }
  });
  test('academic selection mismatch rejects preceding catalog', () async {
    final c = nicCases.firstWhere((c) => c['name'] == 'newest');
    final result = await worker(
      (url, fields) async =>
          (url: url, status: 200, html: c['initial_html'] as String),
    ).catalog('123456');
    expect(result['code'], 'MATCH_MISMATCH');
  });
  test('unrecognized onchange is not guessed or executed', () async {
    final c = nicCases.firstWhere((c) => c['name'] == 'newest');
    var sent = 0;
    final result = await worker((url, fields) async {
      sent++;
      return (
        url: url,
        status: 200,
        html: (c['initial_html'] as String).replaceAll(
          '__doPostBack',
          'unknownPostback',
        ),
      );
    }).catalog('123456');
    expect(result['code'], 'PAGE_NOT_READY');
    expect(sent, 1);
  });
  test('NIC catalog is attached to the existing School session', () async {
    final auth = NicAuth((url) async => (url: url, status: 200, html: normal));
    try {
      DirectSchoolSession.attach(auth, '123456');
      final service = DirectSchoolSession.nicCatalog;
      expect(service, isNotNull);
      expect(identical(service!.auth, auth), true);
      expect((await service.catalog('123456'))['success'], true);
    } finally {
      DirectSchoolSession.reset();
    }
    expect(DirectSchoolSession.nicCatalog, isNull);
  });
  for (final kind in ['foreign', 'wrong_path', 'mutation', 'bad_referer']) {
    test('verified transport blocks $kind before HTTPS', () async {
      final offlineClient = NicOfflineHttpClient();
      final auth = HttpOverrides.runZoned(
        () => NicGateAuth(),
        createHttpClient: (_) => offlineClient,
      );
      final url = kind == 'foreign'
          ? Uri.parse('https://example.org')
          : nicBase.resolve(
              kind == 'wrong_path'
                  ? 'Home/School/Other.aspx'
                  : NicCatalogWorker.path,
            );
      try {
        await expectLater(
          auth.nicCatalogRequest(
            url,
            fields: kind == 'mutation' || kind == 'bad_referer'
                ? {
                    '__EVENTTARGET': NicCatalogWorker.sessionName,
                    '__EVENTARGUMENT': '',
                    NicCatalogWorker.sessionName: '2026-27',
                    if (kind == 'mutation')
                      r'ctl00$ContentPlaceHolder1$btn_Lock': 'Lock',
                  }
                : null,
            referer: kind == 'bad_referer'
                ? Uri.parse('https://example.org')
                : url,
          ),
          throwsStateError,
        );
        expect(offlineClient.requests, 0);
      } finally {
        auth.close();
      }
    });
  }
  test('AJAX fresh panel replaces classes and respects UTF-16 frame lengths', () async {
    final c = nicCases.firstWhere((c) => c['name'] == 'newest');
    final initial = (c['initial_html'] as String)
        .replaceFirst(
          '<select id="ddlSession"',
          '<div id="panel"><select id="ddlSession"',
        )
        .replaceFirst('</form>', '</div></form>');
    final panel =
        '<select id="ddlSession"><option value="2026-27" selected>2026-27</option></select><select id="ContentPlaceHolder1_ddlClass"><option value="4">Class 4 🏫</option></select>';
    final delta = '1|#||4|${panel.length}|updatePanel|panel|$panel|';
    final result = await worker(
      (url, fields) async =>
          (url: url, status: 200, html: fields == null ? initial : delta),
    ).catalog('123456');
    expect(result['success'], true);
    expect(result['classes'], [
      {'id': '4', 'label': 'Class 4 🏫', 'selected': true},
    ]);
  });
  test('AJAX class-only panel retains the browser selected session', () async {
    final c = nicCases.firstWhere((c) => c['name'] == 'newest');
    final initial = (c['initial_html'] as String)
        .replaceFirst(
          '<select id="ContentPlaceHolder1_ddlClass"',
          '<div id="classesPanel"><select id="ContentPlaceHolder1_ddlClass"',
        )
        .replaceFirst('</form>', '</div></form>');
    const panel =
        '<select id="ContentPlaceHolder1_ddlClass"><option value="5">Class 5</option></select>';
    final delta = '1|#||4|${panel.length}|updatePanel|classesPanel|$panel|';
    final result = await worker(
      (url, fields) async =>
          (url: url, status: 200, html: fields == null ? initial : delta),
    ).catalog('123456');
    expect(result['success'], true);
    expect(result['session'], '2026-27');
    expect(result['classes'], [
      {'id': '5', 'label': 'Class 5', 'selected': true},
    ]);
  });
  test('malformed AJAX cannot expose stale classes', () async {
    final c = nicCases.firstWhere((c) => c['name'] == 'newest');
    final result = await worker(
      (url, fields) async => (
        url: url,
        status: 200,
        html: fields == null
            ? c['initial_html'] as String
            : '1|#||4|99|updatePanel|missing|broken|',
      ),
    ).catalog('123456');
    expect(result['success'], false);
    expect(result['code'], 'PAGE_NOT_READY');
  });
}
