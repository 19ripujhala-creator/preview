import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shaladarpan/services/portals/rajsims/direct/rajsims_sso_httpx.dart';

void main() {
  const privateValue = 'PRIVATE_USERDETAILS_TOKEN';
  const bridge =
      '<form method="post" action="https://rajsims.rajasthan.gov.in/SSOIntegration/SSOLogin"><input type="hidden" name="userdetails" value="$privateValue"></form>';
  final sso = Uri.parse(
    'https://sso.rajasthan.gov.in/sso?token=PRIVATE_SOURCE_TOKEN',
  );
  final cases = <String, (String, Uri, String)>{
    'unexpected source host': (
      bridge,
      Uri.parse(
        'https://rajsims.rajasthan.gov.in/launch?token=PRIVATE_SOURCE_TOKEN',
      ),
      'source_is_sso',
    ),
    'GET bridge instead of POST': (
      bridge.replaceFirst('method="post"', 'method="get"'),
      sso,
      'method_is_post',
    ),
    'fragment on bridge action': (
      bridge.replaceFirst('SSOLogin"', 'SSOLogin#PRIVATE_FRAGMENT_TOKEN"'),
      sso,
      'action_fragment_empty',
    ),
    'empty userdetails': (
      bridge.replaceFirst(privateValue, ''),
      sso,
      'input_nonempty',
    ),
    'disabled userdetails': (
      bridge.replaceFirst('type="hidden"', 'type="hidden" disabled'),
      sso,
      'input_enabled',
    ),
  };
  for (final entry in cases.entries) {
    test(
      '${entry.key}: exact failed check is returned without sensitive values',
      () {
        RajssoError? failure;
        try {
          rajssoDocumentLaunchAction(entry.value.$1, entry.value.$2);
        } on RajssoError catch (e) {
          failure = e;
        }
        expect(failure, isNotNull);
        expect(failure!.code, 'PORTAL_LAUNCH_CHANGED');
        expect(failure.portalMessage, false);
        expect((failure.diagnostics!['checks'] as Map)[entry.value.$3], false);
        final encoded = jsonEncode(failure.diagnostics);
        expect(encoded, isNot(contains('PRIVATE_')));
        expect(encoded, isNot(contains('https://')));
      },
    );
  }
  test('official bridge query is retained without exposing its values', () {
    final action = rajssoDocumentLaunchAction(
      bridge.replaceFirst('SSOLogin"', 'SSOLogin?token=PRIVATE_QUERY_TOKEN"'),
      sso,
    );
    expect(action.url.query, 'token=PRIVATE_QUERY_TOKEN');
    expect(action.method, 'POST');
    expect(action.fields, [('userdetails', privateValue)]);
  });
  test('original valid bridge and opaque userdetails are unchanged', () {
    final action = rajssoDocumentLaunchAction(bridge, sso);
    expect(action.method, 'POST');
    expect(action.fields, [('userdetails', privateValue)]);
  });
}
