import 'package:flutter_test/flutter_test.dart';

import '../../lib/services/portals/rajsims/direct/rajsims_sso_httpx.dart';
import 'rajsso_httpx_test.dart' show ScriptedSsoTransport, loadSsoFixture;

void main() {
  final source = Uri.parse('https://sso.rajasthan.gov.in/sso');
  const endpoint = 'https://rajsims.rajasthan.gov.in/SSOIntegration/SSOLogin';
  String form(String action, {String input = 'opaque+value/='}) =>
      '<form action="$action" method="post">'
      '<input type="hidden" name="userdetails" value="$input"></form>';

  test('preserves repeated query fields, order and percent encoded values', () {
    const query = 'state=a%2Bb%2Fc%3D&amp;x=one&amp;x=two&amp;empty=';
    final action = rajssoDocumentLaunchAction(form('$endpoint?$query'), source);
    expect(
      action.url.toString(),
      '$endpoint?state=a%2Bb%2Fc%3D&x=one&x=two&empty=',
    );
    expect(action.url.queryParametersAll['x'], ['one', 'two']);
    expect(action.fields, [('userdetails', 'opaque+value/=')]);
    expect(action.method, 'POST');
  });

  test('query values do not change the trusted request destination', () {
    final action = rajssoDocumentLaunchAction(
      form('$endpoint?return=https%3A%2F%2Fexample.invalid%2F'),
      source,
    );
    expect(action.url.host, 'rajsims.rajasthan.gov.in');
    expect(action.url.path, '/SSOIntegration/SSOLogin');
  });

  test('query does not allow HTTP bridge transport', () {
    expect(
      () => rajssoDocumentLaunchAction(
        form('${endpoint.replaceFirst('https:', 'http:')}?state=opaque'),
        source,
      ),
      throwsA(isA<RajssoError>()),
    );
  });

  test('query does not allow userinfo or a different HTTPS port', () {
    for (final action in [
      endpoint.replaceFirst('https://', 'https://user@'),
      endpoint.replaceFirst('.gov.in/', '.gov.in:444/'),
    ]) {
      expect(
        () => rajssoDocumentLaunchAction(form('$action?state=opaque'), source),
        throwsA(isA<RajssoError>()),
      );
    }
  });

  test('query does not allow a fragment or an untrusted source', () {
    expect(
      () => rajssoDocumentLaunchAction(
        form('$endpoint?state=opaque#fragment'),
        source,
      ),
      throwsA(isA<RajssoError>()),
    );
    expect(
      () => rajssoDocumentLaunchAction(
        form('$endpoint?state=opaque'),
        Uri.parse('https://example.invalid/'),
      ),
      throwsA(isA<RajssoError>()),
    );
  });

  test('query does not allow empty userdetails or ambiguous forms', () {
    expect(
      () => rajssoDocumentLaunchAction(
        form('$endpoint?state=opaque', input: ''),
        source,
      ),
      throwsA(isA<RajssoError>()),
    );
    expect(
      () => rajssoDocumentLaunchAction(
        form('$endpoint?state=opaque') + form('$endpoint?state=other'),
        source,
      ),
      throwsA(isA<RajssoError>()),
    );
  });

  test(
    'full launch posts query and opaque body once and verifies profile',
    () async {
      final fixture = loadSsoFixture();
      fixture['bridge'] = (fixture['bridge'] as String).replaceFirst(
        'SSOLogin"',
        'SSOLogin?state=a%2Bb%2Fc%3D&amp;app=mdm"',
      );
      final transport = ScriptedSsoTransport(fixture);
      final sso = RajssoHttpx(
        solveCaptcha: (_) => '123456',
        clientFactory: () => transport,
      );
      try {
        final login = await sso.login(
          'offline-user',
          'offline-password',
          client: transport,
        );
        final launch = await sso.launch(login);
        final posts = transport.calls
            .where(
              (call) =>
                  call['method'] == 'POST' &&
                  Uri.parse(call['url'] as String).path ==
                      '/SSOIntegration/SSOLogin',
            )
            .toList();
        expect(posts, hasLength(1));
        expect(posts.single['url'], '$endpoint?state=a%2Bb%2Fc%3D&app=mdm');
        final body = Uri(query: posts.single['content'] as String)
            .queryParameters;
        expect(body, {'userdetails': 'native opaque'});
        expect(transport.credentialPosts, 1);
        expect(launch.profile, fixture['profile']);
      } finally {
        await transport.close();
      }
    },
  );
}
