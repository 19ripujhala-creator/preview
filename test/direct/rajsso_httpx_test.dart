import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../lib/services/portals/shaladarpan/direct/school_http.dart';
import '../../lib/services/portals/rajsims/direct/http_context.dart';
import '../../lib/services/portals/rajsims/direct/rajsims_sso_httpx.dart';

Map<String, dynamic> loadSsoFixture() => jsonDecode(
  File('test/direct/fixtures/python_rajsso_httpx.json').readAsStringSync(),
) as Map<String, dynamic>;

class ScriptedSsoTransport implements RajsimsHttpTransport {
  ScriptedSsoTransport(this.fixture, {this.scenario = 'native_full_launch'});
  final Map<String, dynamic> fixture;
  final String scenario;
  @override
  final jar = SchoolCookieJar();
  final calls = <Map<String, dynamic>>[];
  int credentialPosts = 0, closes = 0;
  Future<SchoolHttpReply> Function(String, Uri, String?, Map<String, String>)?
  handlerHook;
  SchoolHttpReply response(
    Uri url, {
    String text = '',
    int status = 200,
    Map<String, List<String>> headers = const {},
    Object? data,
  }) => SchoolHttpReply(
    url,
    status,
    Uint8List.fromList(utf8.encode(data == null ? text : jsonEncode(data))),
    headers,
  );
  @override
  Future<SchoolHttpReply> request(
    String method,
    Uri url, {
    String? content,
    Map<String, String> headers = const {},
    Duration? timeout,
  }) async {
    calls.add({
      'method': method,
      'url': url.toString(),
      'content': content ?? '',
      'headers': {
        for (final e in headers.entries) e.key.toLowerCase(): e.value,
      },
    });
    if (handlerHook != null) return handlerHook!(method, url, content, headers);
    final path = url.path;
    if (path == '/signin' && method == 'GET')
      return response(url, text: fixture['form'] as String);
    if (path == '/signin' && method == 'POST') {
      credentialPosts++;
      if (scenario == 'credentials_rejected')
        return response(
          url,
          text: '<div role="alert">Invalid password — मूल संदेश</div>',
        );
      if (scenario == 'active_session')
        return response(
          url,
          text: '<div role="alert">Terminate previous active session?</div>',
        );
      if (scenario == 'captcha_rejected' && credentialPosts == 1)
        return response(url, text: '<div role="alert">Incorrect captcha</div>');
      if (scenario == 'unverified_signin')
        return response(url, text: fixture['form'] as String);
      if (scenario.startsWith('timeout')) throw TimeoutException('offline');
      if (scenario == 'post307')
        return response(
          url,
          status: 307,
          headers: {
            'location': ['/sso'],
          },
        );
      if (scenario == 'external_redirect')
        return response(
          url,
          status: 302,
          headers: {
            'location': ['https://evil.example/sso'],
          },
        );
      return response(
        url,
        status: 302,
        headers: {
          'location': ['/sso'],
        },
      );
    }
    if (path == '/sso' && method == 'GET')
      return response(
        url,
        text:
            fixture[['timeout_unknown', 'unverified_signin'].contains(scenario)
                    ? 'form'
                    : 'tile']
                as String,
      );
    if (path == '/sso' && method == 'POST') {
      if (scenario == 'launch_timeout') throw TimeoutException('offline');
      if (scenario == 'launch307')
        return response(
          url,
          status: 307,
          headers: {
            'location': ['/bridge'],
          },
        );
      if (scenario == 'repeated_launch_post') {
        final values = Uri(query: content).queryParametersAll;
        final inputs = [
          for (final e in values.entries)
            for (final value in e.value)
              '<input type="hidden" name="${e.key}" value="$value">',
        ].join();
        return response(
          url,
          text:
              '<form id="again" action="/sso" method="post">$inputs</form><script>document.getElementById("again").submit();</script>',
        );
      }
      return response(url, text: fixture['bridge'] as String);
    }
    if (path == '/SSOIntegration/SSOLogin')
      return response(url, text: fixture['dept'] as String);
    if (path == '/SSOIntegration/SsoDetail')
      return response(url, text: fixture['detail'] as String);
    if (url.host == 'rajsims-mdm.rajasthan.gov.in' && path == '/')
      return response(url, text: '<html>native app</html>');
    if (path.contains('GetSSOlogin'))
      return response(
        url,
        data: scenario == 'token_denied'
            ? {'StatusCode': 401}
            : fixture['profile'],
      );
    throw StateError('Unexpected mocked request: $method $path');
  }

  @override
  Future<void> close() async {
    closes++;
  }
}

void main() {
  test(
    'unknown SSO response remains a failure and sends credential POST once',
    () async {
      final transport = ScriptedSsoTransport(
        loadSsoFixture(),
        scenario: 'unverified_signin',
      );
      final sso = RajssoHttpx(
        solveCaptcha: (_) => '123456',
        clientFactory: () => transport,
      );
      try {
        await sso.login('offline-user', 'offline-password');
        fail('Unknown page must never authenticate');
      } on RajssoError catch (error) {
        expect(error.code, 'LOGIN_NOT_VERIFIED');
        expect(error.message, 'SSO did not confirm login: LOGIN_NOT_VERIFIED');
        expect(error.portalMessage, false);
        expect(error.diagnostics?['http_status'], 200);
        expect(error.diagnostics?['page'], 'signin');
        expect(error.diagnostics?['attempt'], 1);
        expect(error.diagnostics?['password_control'], true);
        expect(transport.credentialPosts, 1);
        expect(transport.closes, 1);
      }
    },
  );
  test('diagnostics omit response text, secrets and URL queries', () {
    final transport = ScriptedSsoTransport(loadSsoFixture());
    final response = transport.response(
      Uri.parse(
        'https://sso.rajasthan.gov.in/other/private-identity?token=secret-query',
      ),
      text: '<form><input id="cpBodyMain_cpBody_txt_Data2" value="secret-password"><input name="__VIEWSTATE" value="secret-token"><p>secret-account</p></form><script>location.href="/sso?token=secret-script"</script>',
    );
    final details = rajssoFailureDiagnostics(response, 1);
    expect(details['page'], 'other');
    expect(details['form_count'], 1);
    expect(details['password_control'], true);
    expect(details['javascript_redirect'], true);
    final encoded = jsonEncode(details);
    for (final secret in [
      'secret-query',
      'secret-password',
      'secret-token',
      'secret-account',
      'secret-script',
      'private-identity',
    ]) {
      expect(encoded, isNot(contains(secret)));
    }
  });
  test(
    'response structure separates empty error containers from actual text',
    () {
      final transport = ScriptedSsoTransport(loadSsoFixture());
      final reply = transport.response(
        Uri.parse(rajssoSignin),
        text: '<div role="alert"></div><span id="lblError">Actual portal message</span><meta http-equiv="refresh" content="0;url=/sso"><script>alert("unused");</script>',
      );
      final details = rajssoFailureDiagnostics(reply, 2);
      expect(details['error_nodes'], 2);
      expect(details['nonempty_error_nodes'], 1);
      expect(details['meta_refresh'], true);
      expect(details['javascript_alert_call'], true);
      expect(details['attempt'], 2);
      expect(jsonEncode(details), isNot(contains('Actual portal message')));
    },
  );

  final fixture = loadSsoFixture();
  for (final item in fixture['parsers'] as List) {
    test('actual Python SSO parser ${item['kind']}: ${item['name']}', () {
      final args = (item['args'] as List).cast<String>();
      Object? value;
      String? code;
      try {
        switch (item['kind']) {
          case 'form':
            final parsed = rajssoParseForm(args[0], Uri.parse(args[1]));
            value = {
              'fields': parsed.fields,
              'action': parsed.action.toString(),
              'key': parsed.key,
              'iv': parsed.iv,
              'image': parsed.image,
              'controls': {
                for (final e in parsed.controls.entries)
                  e.key: e.value.attributes,
              },
            };
          case 'tile':
            final parsed = rajssoParseLaunchForm(args[0], Uri.parse(args[1]));
            value = [
              parsed.url.toString(),
              [
                for (final f in parsed.fields!) [f.$1, f.$2],
              ],
            ];
          case 'document':
            final parsed = rajssoDocumentLaunchAction(
              args[0],
              Uri.parse(args[1]),
            );
            value = [
              parsed.method,
              parsed.url.toString(),
              parsed.fields == null
                  ? null
                  : [
                      for (final f in parsed.fields!) [f.$1, f.$2],
                    ],
            ];
          case 'tokens':
            final parsed = rajssoLaunchTokens(Uri.parse(args[0]));
            value = parsed == null ? null : [parsed.$1, parsed.$2];
          case 'literal':
            value = rajssoLiteralNavigation(args[0]);
          default:
            throw StateError('Unknown golden parser');
        }
      } on RajssoError catch (error) {
        code = error.code;
      }
      if (item.containsKey('code')) {
        expect(code, item['code']);
      } else {
        expect(code, isNull);
        expect(value, item['value']);
      }
    });
  }
  for (final item in fixture['crypto'] as List) {
    test(
      'actual CryptoJS/Python AES ${item['key'].length}/${jsonEncode(item['value'])}',
      () {
        expect(
          rajssoEncrypt(
            item['value'] as String,
            item['key'] as String,
            item['iv'] as String,
          ),
          item['expected'],
        );
      },
    );
  }
  for (final entry in fixture['flows'] as List) {
    test('actual Python request sequence: ${entry['name']}', () async {
      final transport = ScriptedSsoTransport(
        fixture,
        scenario: entry['name'] as String,
      );
      final sso = RajssoHttpx(
        solveCaptcha: (_) => '123456',
        clientFactory: () => transport,
      );
      Map<String, dynamic> result;
      try {
        final login = await sso.login(
          'offline-user',
          ' password ',
          client: transport,
          savedState: entry['name'] == 'saved_session'
              ? {
                  'cookies': [
                    {
                      'name': 'sid',
                      'value': 'offline',
                      'domain': '.rajasthan.gov.in',
                    },
                  ],
                }
              : null,
        );
        final launch = await sso.launch(login);
        result = {
          'cached': login.cached,
          'auth_id': launch.authId,
          'auth_key': launch.authKey,
          'url': launch.url.toString(),
          'profile': launch.profile,
        };
      } on RajssoError catch (error) {
        result = {'code': error.code};
      } on TimeoutException {
        result = {'timeout': true};
      }
      expect(result, entry['result']);
      expect(transport.calls, entry['calls']);
    });
  }
  test(
    'portal login message has priority and preserves original text',
    () async {
      final transport = ScriptedSsoTransport(
        fixture,
        scenario: 'credentials_rejected',
      );
      final sso = RajssoHttpx(
        solveCaptcha: (_) => '123456',
        clientFactory: () => transport,
      );
      await expectLater(
        sso.login('u', 'p'),
        throwsA(
          isA<RajssoError>()
              .having(
                (e) => e.message,
                'message',
                'Invalid password — मूल संदेश',
              )
              .having((e) => e.portalMessage, 'portalMessage', true),
        ),
      );
      expect(transport.credentialPosts, 1);
      expect(transport.closes, 1);
    },
  );
  test(
    'bad OCR result fetches a fresh form without posting credentials',
    () async {
      final transport = ScriptedSsoTransport(fixture);
      final sso = RajssoHttpx(
        solveCaptcha: (_) => '12X4567',
        clientFactory: () => transport,
      );
      await expectLater(
        sso.login('u', 'p', maxAttempts: 3),
        throwsA(
          isA<RajssoError>().having(
            (e) => e.code,
            'code',
            'CAPTCHA_UNAVAILABLE',
          ),
        ),
      );
      expect(transport.calls.length, 3);
      expect(transport.credentialPosts, 0);
    },
  );
  test(
    'credential form honors per-control data-encrypt and named submit',
    () async {
      final changed = Map<String, dynamic>.of(fixture);
      changed['form'] = (fixture['form'] as String)
          .replaceAll(
            'name="user" type="text"',
            'name="user" type="text" data-encrypt="true"',
          )
          .replaceAll(
            'name="password" type="password"',
            'name="password" type="password" data-encrypt="false"',
          );
      final transport = ScriptedSsoTransport(changed);
      await RajssoHttpx(
        solveCaptcha: (_) => '123456',
        clientFactory: () => transport,
      ).login(' user ', ' pass ');
      final form = Uri(
        query:
            transport.calls.firstWhere((c) => c['method'] == 'POST')['content']
                as String,
      ).queryParameters;
      expect(
        form['user'],
        rajssoEncrypt('user', '0123456789abcdef', 'fedcba9876543210'),
      );
      expect(form['password'], 'pass');
      expect(form['button'], 'Login');
      expect(form['__VIEWSTATE'], 'state');
      expect(form['csrf'], 'csrf-token');
    },
  );
  test(
    'captcha handler follows same-host image redirect and rejects foreign hop',
    () async {
      final transport = ScriptedSsoTransport(fixture);
      transport.handlerHook = (method, url, body, headers) async {
        if (url.path == '/captcha')
          return transport.response(
            url,
            status: 302,
            headers: {
              'location': ['/image'],
            },
          );
        return SchoolHttpReply(url, 200, Uint8List.fromList([1, 2, 3]), {
          'content-type': ['image/jpeg'],
        });
      };
      final sso = RajssoHttpx(
        solveCaptcha: (_) => '',
        clientFactory: () => transport,
      );
      expect(
        await sso.getCaptchaImage(
          transport,
          Uri.parse('https://sso.rajasthan.gov.in/captcha'),
          Uri.parse(rajssoSignin),
        ),
        [1, 2, 3],
      );
      expect(transport.calls.length, 2);
      transport.calls.clear();
      transport.handlerHook = (method, url, body, headers) async =>
          transport.response(
            url,
            status: 302,
            headers: {
              'location': ['https://evil.example/image'],
            },
          );
      await expectLater(
        sso.getCaptchaImage(
          transport,
          Uri.parse('https://sso.rajasthan.gov.in/captcha'),
          Uri.parse(rajssoSignin),
        ),
        throwsA(
          isA<RajssoError>().having((e) => e.code, 'code', 'INVALID_REDIRECT'),
        ),
      );
      expect(transport.calls.length, 1);
    },
  );
  test(
    'redirect limit and invalid image response fail without credential POST',
    () async {
      final transport = ScriptedSsoTransport(fixture);
      final sso = RajssoHttpx(
        solveCaptcha: (_) => '',
        clientFactory: () => transport,
      );
      transport.handlerHook = (method, url, body, headers) async =>
          transport.response(
            url,
            status: 302,
            headers: {
              'location': ['/loop'],
            },
          );
      await expectLater(
        sso.getDocument(transport, Uri.parse(rajssoSignin)),
        throwsA(isA<RajssoError>()),
      );
      expect(transport.calls.length, 6);
      transport.handlerHook = (method, url, body, headers) async =>
          transport.response(url, text: '<html>expired</html>');
      await expectLater(
        sso.getCaptchaImage(
          transport,
          Uri.parse(rajssoSignin),
          Uri.parse(rajssoSignin),
        ),
        throwsA(
          isA<RajssoError>().having(
            (e) => e.code,
            'code',
            'CAPTCHA_UNAVAILABLE',
          ),
        ),
      );
    },
  );
  test(
    'form URL encoding preserves duplicate keys, Unicode and Python escaping',
    () {
      expect(
        rajssoEncodeForm([
          ('x', 'one'),
          ('x', 'two'),
          ('text', "space + * ! () ~ हिन्दी"),
        ]),
        'x=one&x=two&text=space+%2B+%2A+%21+%28%29+~+%E0%A4%B9%E0%A4%BF%E0%A4%A8%E0%A5%8D%E0%A4%A6%E0%A5%80',
      );
    },
  );
  test('invalid AES parameters fail before sending a request', () {
    expect(
      () => rajssoEncrypt('password', 'short', 'fedcba9876543210'),
      throwsA(isA<RajssoError>().having((e) => e.code, 'code', 'FORM_CHANGED')),
    );
  });
}
