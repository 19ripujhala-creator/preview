import 'dart:convert';
import 'dart:io';

import 'package:html/parser.dart' as html;
import 'package:flutter_test/flutter_test.dart';

import '../../lib/services/portals/rajsims/direct/rajsims_sso_httpx.dart';
import 'rajsso_httpx_test.dart' show ScriptedSsoTransport, loadSsoFixture;

const checkbox =
    '<input id="cpBodyMain_cpBody_cbx_newsession" type="checkbox" name="ctl00\$ctl00\$cpBodyMain\$cpBody\$cbx_newsession">';
String confirmationForm({bool image = false, String control = checkbox}) {
  var text = (loadSsoFixture()['form'] as String).replaceFirst(
    '</form>',
    '$control</form>',
  );
  if (!image) text = text.replaceAll(RegExp(r'<img[^>]*>'), '');
  return text;
}

void main() {
  for (final item in jsonDecode(
    File('test/direct/fixtures/python_rajsso_latest_login.json')
        .readAsStringSync(),
  ) as List) {
    test('latest Python literal popup parity: ${item['html']}', () {
      expect(rajssoOutcome(item['html'] as String).$1, item['code']);
      expect(
        rajssoStartupMessages(html.parse(item['html'] as String)),
        item['messages'],
      );
    });
  }
  test('native startup CAPTCHA popup is recognized and retains message', () {
    expect(
      rajssoOutcome(
        '<script>//<![CDATA[\nShowAlert("Incorrect captcha");\n//]]></script>',
      ),
      ('CAPTCHA_REJECTED', 'Incorrect captcha'),
    );
    expect(
      rajssoOutcome(
        '<script>ShowModelPopup("alert", "Invalid password");</script>',
      ),
      ('INVALID_CREDENTIALS', 'Invalid password'),
    );
  });
  test('ready wrappers and onload use literal messages only', () {
    expect(
      rajssoOutcome(
        '<script>\$(document).ready(function(){ShowMessage("Error", "Incorrect captcha");});</script>',
      ).$1,
      'CAPTCHA_REJECTED',
    );
    expect(
      rajssoOutcome('<body onload="alert(\'Invalid password\')"></body>').$1,
      'INVALID_CREDENTIALS',
    );
  });
  test('dormant definitions and conditional alerts cannot reject login', () {
    for (final body in [
      'function check(){alert("Invalid password");}',
      'if(false){ShowAlert("Incorrect captcha");}',
      'ShowAlert(variable);',
    ]) {
      expect(rajssoOutcome('<script>$body</script>'), (
        'LOGIN_NOT_VERIFIED',
        '',
      ));
    }
  });
  test('CAPTCHA has priority over mixed credential messages', () {
    expect(
      rajssoOutcome(
        '<div role="alert">Invalid password. Incorrect captcha</div>',
      ).$1,
      'CAPTCHA_REJECTED',
    );
  });
  test('visible native checkbox requires exact form and enabled control', () {
    expect(rajssoNativeSessionConfirmation(confirmationForm())?.$2, 'on');
    for (final control in [
      checkbox.replaceFirst('type="checkbox"', 'type="checkbox" disabled'),
      '<div style="display:none">$checkbox</div>',
      checkbox.replaceFirst('cbx_newsession">', 'other">'),
    ]) {
      expect(
        rajssoNativeSessionConfirmation(confirmationForm(control: control)),
        isNull,
      );
    }
    expect(
      rajssoNativeSessionConfirmation(confirmationForm(control: '') + checkbox),
      isNull,
    );
  });
  test(
    'unknown credential response uses one dashboard GET without POST replay',
    () async {
      final t = ScriptedSsoTransport(loadSsoFixture());
      t.handlerHook = (method, url, content, headers) async => t.response(
        url,
        text: url.path == '/sso'
            ? t.fixture['tile'] as String
            : t.fixture['form'] as String,
      );
      final login = await RajssoHttpx(
        solveCaptcha: (_) => '123456',
        clientFactory: () => t,
      ).login('offline', 'password');
      expect(login.cached, false);
      expect(
        t.calls.map(
          (c) => '${c['method']} ${Uri.parse(c['url'] as String).path}',
        ),
        ['GET /signin', 'POST /signin', 'GET /sso'],
      );
    },
  );
  test(
    'native new-session confirmation uses returned ViewState with no new GET',
    () async {
      final t = ScriptedSsoTransport(loadSsoFixture());
      var posts = 0, solves = 0;
      final returned = confirmationForm().replaceFirstMapped(
        RegExp(r'(<input[^>]*name="__VIEWSTATE"[^>]*value=")[^"]*'),
        (m) => '${m[1]}returned-state',
      );
      t.handlerHook = (method, url, content, headers) async {
        if (method == 'POST') {
          posts++;
          if (posts == 1) return t.response(url, text: returned);
          final values = Uri(query: content).queryParameters;
          expect(
            values['ctl00\$ctl00\$cpBodyMain\$cpBody\$cbx_newsession'],
            'on',
          );
          expect(
            values['__VIEWSTATE'],
            rajssoParseForm(returned, url, true).fields['__VIEWSTATE'],
          );
          return t.response(
            Uri.parse(rajssoDashboard),
            text: t.fixture['tile'] as String,
          );
        }
        return t.response(url, text: t.fixture['form'] as String);
      };
      await RajssoHttpx(
        solveCaptcha: (_) {
          solves++;
          return '123456';
        },
        clientFactory: () => t,
      ).login('offline', 'password', maxAttempts: 1);
      expect(posts, 2);
      expect(solves, 1);
      expect(t.calls.where((c) => c['method'] == 'GET').length, 1);
    },
  );
  test(
    'repeated session confirmation stops after one confirmation POST',
    () async {
      final t = ScriptedSsoTransport(loadSsoFixture());
      t.handlerHook = (method, url, content, headers) async => t.response(
        url,
        text: method == 'POST'
            ? confirmationForm()
            : t.fixture['form'] as String,
      );
      await expectLater(
        RajssoHttpx(
          solveCaptcha: (_) => '123456',
          clientFactory: () => t,
        ).login('offline', 'password'),
        throwsA(
          isA<RajssoError>().having(
            (e) => e.code,
            'code',
            'ACTIVE_SESSION_CONFIRMATION_REQUIRED',
          ),
        ),
      );
      expect(t.calls.where((c) => c['method'] == 'POST').length, 2);
    },
  );
  test(
    'startup CAPTCHA rejection retries fresh sign-in using source limit',
    () async {
      final t = ScriptedSsoTransport(loadSsoFixture());
      var posts = 0;
      t.handlerHook = (method, url, content, headers) async {
        if (method == 'POST' && ++posts == 1)
          return t.response(
            url,
            text: '<script>ShowAlert("Incorrect captcha");</script>',
          );
        return t.response(
          method == 'POST' ? Uri.parse(rajssoDashboard) : url,
          text: t.fixture[method == 'POST' ? 'tile' : 'form'] as String,
        );
      };
      await RajssoHttpx(
        solveCaptcha: (_) => '123456',
        clientFactory: () => t,
      ).login('offline', 'password');
      expect(posts, 2);
    },
  );
}
