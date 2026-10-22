import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

import '../../lib/services/portals/shaladarpan/direct/auth_manager.dart';
import '../../lib/services/portals/shaladarpan/direct/school_http.dart';
import '../../lib/services/portals/shaladarpan/portal_state.dart';

void main() {
  test('login payload agrees with independent Python hashlib fixture', () {
    final doc = html.parse('''<form>
      <input id="__VIEWSTATE" value="view&amp;state">
      <input id="__EVENTVALIDATION" value="event-token">
      <input id="__VIEWSTATEGENERATOR" value="ABCD">
      <input id="bodyContent_hdnfld" value="salt-42">
      </form>''');
    final actual = SchoolAuthManager.buildLoginPayload(
      doc,
      user: '123456',
      password: 'TestPassword!',
      loginId: 'SchoolABC',
      captcha: '123456',
    );
    final expected = jsonDecode(
      File('test/direct/python_login_payload.json').readAsStringSync(),
    ) as Map;
    expect(actual, expected);
  });

  test(
    'dynamic input names are preserved and unrelated hidden inputs excluded',
    () {
      final doc = html.parse('''<form>
      <input id="__VIEWSTATE" value="v"><input id="__EVENTVALIDATION" value="e">
      <input id="bodyContent_txtUName" name="actual-user">
      <input id="bodyContent_txtUPswd" name="actual-password">
      <input id="extra" name="extra" type="hidden" value="do-not-submit">
      </form>''');
      final values = SchoolAuthManager.buildLoginPayload(
        doc,
        user: 'u',
        password: 'p',
        loginId: 'u',
        captcha: '1234',
      );
      expect(values['actual-user'], 'u');
      expect(values.containsKey('actual-password'), true);
      expect(values.containsKey('extra'), false);
      expect(values.containsKey('__VIEWSTATEGENERATOR'), false);
    },
  );

  test('mixed actual CAPTCHA and credentials messages remain retryable', () {
    const message =
        'Enter valid Result of Captcha Calculation. | Please enter valid username1 | Invalid UserId or Password';
    final rejection = SchoolAuthManager.loginRejection(
      '<span id="bodyContent_lblMsg">$message</span>',
    );
    expect(rejection['code'], 'CAPTCHA_REJECTED');
    expect(rejection['retry'], true);
    expect(rejection['portal_message'], message);
  });
  test('dormant password validator cannot invalidate a CAPTCHA response', () {
    final rejection = SchoolAuthManager.loginRejection(
      '<span id="lblMsg">Incorrect CAPTCHA</span><script>function validate(){alert("Invalid UserId or Password");}</script>',
    );
    expect(rejection['code'], 'CAPTCHA_REJECTED');
    expect(rejection['portal_message'], 'Incorrect CAPTCHA');
  });
  test('visible actual invalid credentials still suspend login', () {
    final rejection = SchoolAuthManager.loginRejection(
      '<span id="lblMsg">Invalid UserId or Password</span>',
    );
    expect(rejection['code'], 'INVALID_CREDENTIALS');
    expect(rejection['retry'], false);
    expect(rejection['portal_message'], 'Invalid UserId or Password');
  });
  test('generic incorrect message does not claim wrong password', () {
    expect(
      SchoolAuthManager.loginRejection(
        '<span id="lblMsg">Incorrect result</span>',
      )['code'],
      'LOGIN_REJECTED',
    );
  });
  test('literal ASP.NET startup alerts preserve original messages', () {
    final rejection = SchoolAuthManager.loginRejection(
      '<script>//<![CDATA[\nalert("Enter valid Result of Captcha Calculation.");\n//]]></script>',
    );
    expect(rejection['code'], 'CAPTCHA_REJECTED');
    expect(
      rejection['portal_message'],
      'Enter valid Result of Captcha Calculation.',
    );
  });
  test('hidden credential error and dormant alert do not suspend login', () {
    final rejection = SchoolAuthManager.loginRejection(
      '<div style="display: none"><span id="lblMsg">Invalid password</span></div><script>function validate(){alert("Invalid password");}</script>',
    );
    expect(rejection['code'], 'LOGIN_REJECTED');
    expect(rejection.containsKey('portal_message'), false);
  });

  test(
    'startup alert does not activate a later dormant credentials function',
    () {
      final rejection = SchoolAuthManager.loginRejection(
        '<script>alert("Portal maintenance"); function validate(){alert("Invalid password");}</script>',
      );
      expect(rejection['code'], 'LOGIN_REJECTED');
      expect(rejection['portal_message'], 'Portal maintenance');
    },
  );

  test('cookie rotation removes the obsolete domainless seed', () {
    final jar = SchoolCookieJar({'ASP.NET_SessionId': 'old'});
    final uri = Uri.parse('https://rajshaladarpan.rajasthan.gov.in/SD1/Home/x');
    jar.receive([Cookie('ASP.NET_SessionId', 'new')..path = '/'], uri);
    expect(jar.matching(uri).map((c) => c.value), ['new']);
    expect(jar.snapshot(), {'ASP.NET_SessionId': 'new'});
  });

  test('cookie paths use a slash boundary and RFC default path', () {
    expect(SchoolCookieJar.pathMatches('/SD10', '/SD1'), false);
    expect(SchoolCookieJar.pathMatches('/SD1/x', '/SD1'), true);
    expect(SchoolCookieJar.defaultPath('/SD1/Home/login.aspx'), '/SD1/Home');
    expect(SchoolCookieJar.defaultPath('/x'), '/');
  });

  test('Max-Age deletion overrides future Expires', () {
    final uri = Uri.parse('https://rajshaladarpan.rajasthan.gov.in/SD1/');
    final jar = SchoolCookieJar({'session': 'old'});
    jar.receive([
      Cookie('session', 'deleted')
        ..path = '/'
        ..expires = DateTime.utc(2100)
        ..maxAge = 0,
    ], uri);
    expect(jar.matching(uri), isEmpty);
  });

  test('cookie host and secure scope are enforced', () {
    final jar = SchoolCookieJar();
    final uri = Uri.parse('https://rajshaladarpan.rajasthan.gov.in/SD1/x');
    jar.receive([
      Cookie('session', 'value')
        ..path = '/'
        ..secure = true,
    ], uri);
    expect(
      jar.matching(Uri.parse('http://rajshaladarpan.rajasthan.gov.in/')),
      isEmpty,
    );
    expect(jar.matching(Uri.parse('https://other.example/')), isEmpty);
    expect(jar.matching(uri), hasLength(1));
  });

  test('Python home probe classifications are preserved', () {
    expect(SchoolAuthManager.classifyHome(null), SchoolProbe.unknown);
    expect(
      SchoolAuthManager.classifyHome({
        'status': 503,
        'text': '',
        'url': 'https://x/Home_New.aspx',
      }),
      SchoolProbe.unknown,
    );
    expect(
      SchoolAuthManager.classifyHome({
        'status': 200,
        'text': '<p>x</p>',
        'url': 'https://x/Home_New.aspx',
      }),
      SchoolProbe.alive,
    );
    expect(
      SchoolAuthManager.classifyHome({
        'status': 200,
        'text': '<input id="bodyContent_txtUName">',
        'url': 'https://x/Home_New.aspx',
      }),
      SchoolProbe.dead,
    );
    expect(
      SchoolAuthManager.classifyHome({
        'status': 200,
        'text': '<span id="x_lblSchoolName">School</span>',
        'url': 'https://x/Other.aspx',
      }),
      SchoolProbe.alive,
    );
  });

  test('document classification retains Python priority', () {
    const uri = 'https://x/SD1/Home/Public2/OfficeLoginNew.aspx';
    expect(documentFailure(uri, 'x', 500), 'PAGE_NOT_READY');
    expect(documentFailure(uri, 'x', 403), 'ACCESS_DENIED');
    expect(documentFailure(uri, 'x', 429), 'SESSION_EXPIRED');
    expect(
      documentFailure('https://x/SD1/Home/School/x.aspx', 'x', 429),
      'RATE_LIMITED',
    );
    expect(
      documentFailure(
        'https://x/SD1/Home/School/x.aspx',
        'validation of viewstate mac failed',
      ),
      'PAGE_NOT_READY',
    );
  });

  test('portal error heading is preserved using Python text-node spacing', () {
    expect(
      () => validateSchoolDocument(
        'https://x/School/x.aspx',
        '<h1>Server error in <b>School</b></h1><h2>Actual <b>portal</b> message</h2>',
        500,
      ),
      throwsA(
        isA<SchoolDocumentError>().having(
          (e) => e.message,
          'message',
          'Actual portal message',
        ),
      ),
    );
  });

  test('HTTP reply status overrides caller-supplied legacy status', () async {
    await expectLater(
      requireSchoolDocument((
        url: Uri.parse('https://x/SD1/Home/School/x.aspx'),
        status: 403,
        html: 'x',
      ), 200),
      throwsA(
        isA<SchoolDocumentError>().having(
          (e) => e.code,
          'code',
          'ACCESS_DENIED',
        ),
      ),
    );
  });

  test(
    '302 POST becomes GET and rotated cookies reach redirected request',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final base = Uri.parse('http://127.0.0.1:${server.port}');
      final client = SchoolHttpClient(
        baseUrl: base,
        allowUrl: (uri) => uri.host == '127.0.0.1' && uri.port == server.port,
      );
      final seen = <String>[];
      final subscription = server.listen((request) async {
        seen.add('${request.method} ${request.uri.path}');
        await request.drain<void>();
        if (request.uri.path == '/start') {
          request.response.statusCode = 302;
          request.response.headers.set('location', '/finish');
          request.response.cookies.add(
            Cookie('session', 'rotated')..path = '/',
          );
        } else {
          request.response.write(request.cookies.single.value);
        }
        await request.response.close();
      });
      try {
        final response = await client.post('/start', data: {'value': 'one'});
        expect(response.text, 'rotated');
        expect(seen, ['POST /start', 'GET /finish']);
      } finally {
        client.retire();
        await subscription.cancel();
        await server.close(force: true);
      }
    },
  );

  test(
    'retirement rejects new leases but allows an active lease to finish',
    () async {
      final client = SchoolHttpClient(
        baseUrl: Uri.parse('https://rajshaladarpan.rajasthan.gov.in/SD1'),
      );
      final release = Completer<void>();
      final started = Completer<void>();
      final active = client.withLease((_) async {
        started.complete();
        await release.future;
        return 42;
      });
      await started.future;
      client.retire();
      expect(client.isClosed, false);
      await expectLater(client.withLease((_) async => 0), throwsStateError);
      release.complete();
      expect(await active, 42);
      expect(client.isClosed, true);
    },
  );

  test(
    'uncertain POST is never automatically submitted a second time',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final base = Uri.parse('http://127.0.0.1:${server.port}');
      final client = SchoolHttpClient(
        baseUrl: base,
        timeout: const Duration(milliseconds: 100),
        allowUrl: (uri) => uri.host == '127.0.0.1' && uri.port == server.port,
      );
      var posts = 0;
      final requests = <HttpRequest>[];
      final subscription = server.listen((request) async {
        posts++;
        requests.add(request);
        await request.drain<void>();
        // Local mock accepts the POST but deliberately never confirms it.
      });
      try {
        await expectLater(
          client.post('/save', data: {'test': 'one'}),
          throwsA(isA<TimeoutException>()),
        );
        expect(posts, 1);
      } finally {
        client.retire();
        await subscription.cancel();
        for (final request in requests) {
          try {
            await request.response.close();
          } catch (_) {}
        }
        await server.close(force: true);
      }
    },
  );
}
