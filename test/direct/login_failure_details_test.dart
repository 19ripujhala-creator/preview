import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shaladarpan/services/core/ecosystem_service.dart';

void main() {
  test('bridge failure retains exact message, source, code and checks', () {
    const message = 'Official RajSIMS SSO bridge contract changed.';
    final row = EcosystemService.describeLoginResult({
      'success': false,
      'message': message,
      'message_source': 'backend',
      'code': 'PORTAL_LAUNCH_CHANGED',
      'diagnostics': {
        'phase': 'rajsims_sso_bridge',
        'stage': 'bridge_envelope',
        'checks': {'source_is_sso': false, 'method_is_post': true},
      },
    }, durationSeconds: 1.25);
    expect(row['message'], message);
    expect(row['message_source'], 'backend');
    expect(row['code'], 'PORTAL_LAUNCH_CHANGED');
    expect(row['state'], 'failed');
    expect(row['live'], false);
    expect(row['duration_s'], 1.25);
    expect(row['diagnostics']['checks']['source_is_sso'], false);
  });

  test('original portal validation message is not replaced', () {
    final row = EcosystemService.describeLoginResult({
      'success': false,
      'message': 'Incorrect captcha',
      'message_source': 'portal',
      'code': 'CAPTCHA_INVALID',
    }, durationSeconds: 0);
    expect(row['message'], 'Incorrect captcha');
    expect(row['message_source'], 'portal');
    expect(row.containsKey('diagnostics'), false);
  });

  test('technical details exclude credentials, tokens, URLs and HTML', () {
    final safe = EcosystemService.safeLoginDiagnostics({
      'phase': 'rajsims_sso_bridge',
      'stage': 'bridge_input',
      'password': 'private-password',
      'authkey': 'private-authkey',
      'userdetails': 'private-token',
      'url': 'https://example.invalid/?token=private-query',
      'html': '<input value="private-html">',
      'checks': {'input_hidden': true, 'token': 'private-nested'},
    });
    expect(safe['checks'], {'input_hidden': true});
    expect(jsonEncode(safe), isNot(contains('private-')));
  });

  test('known fields reject arbitrary string values', () {
    expect(
      EcosystemService.safeLoginDiagnostics({
        'phase': 'private-token',
        'page': 'https://example.invalid/private',
        'attempt': 'private-attempt',
        'password_control': 'private-password',
        'checks': {'input_nonempty': 'private-value'},
      }),
      isEmpty,
    );
  });

  test('SSO login shape details remain available', () {
    final diagnostic = {
      'attempt': 2,
      'http_status': 200,
      'page': 'signin',
      'form_count': 1,
      'captcha_control': true,
      'javascript_redirect': false,
    };
    expect(EcosystemService.safeLoginDiagnostics(diagnostic), diagnostic);
  });

  test('successful login discards previous failure diagnostics', () {
    final row = EcosystemService.describeLoginResult({
      'success': true,
      'message': 'Session verified.',
      'diagnostics': {'stage': 'bridge_input'},
    }, durationSeconds: 0.5);
    expect(row['state'], 'ready');
    expect(row['live'], true);
    expect(row.containsKey('diagnostics'), false);
  });

  test('diagnostic copy cannot be changed through original result map', () {
    final checks = <String, dynamic>{'method_is_post': false};
    final safe = EcosystemService.safeLoginDiagnostics({'checks': checks});
    checks['method_is_post'] = true;
    expect(safe['checks']['method_is_post'], false);
  });

  test(
    'missing or malformed diagnostics do not break login error handling',
    () {
      for (final value in [null, 'text', 3, <Object>[]]) {
        expect(EcosystemService.safeLoginDiagnostics(value), isEmpty);
      }
    },
  );
}
