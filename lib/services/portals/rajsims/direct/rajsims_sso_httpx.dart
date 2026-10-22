/// Production HTTP-only RajSSO login/launch from rajsims_sso_httpx.py.
/// Redirects are explicit. Only the returned native session-confirmation form
/// can trigger a second login POST; ambiguous POSTs and launch forms are not replayed.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;
import 'package:pointycastle/export.dart';

import '../../shaladarpan/direct/school_http.dart';
import 'http_context.dart';

const rajssoSignin = 'https://sso.rajasthan.gov.in/signin';
const rajssoDashboard = 'https://sso.rajasthan.gov.in/sso';
const rajssoDocumentAccept =
    'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7';
const rajssoIds = {
  'user': 'cpBodyMain_cpBody_txt_Data1',
  'password': 'cpBodyMain_cpBody_txt_Data2',
  'captcha': 'cpBodyMain_cpBody_ssoCaptcha_txtCaptcha',
  'button': 'cpBodyMain_cpBody_btn_Login',
};
const _portalHosts = {
  'rajsims.rajasthan.gov.in',
  'rajsims-mdm.rajasthan.gov.in',
};
const _redirects = {301, 302, 303, 307, 308};

class RajssoError implements Exception {
  const RajssoError(
    this.code,
    this.message, {
    this.portalMessage = false,
    this.diagnostics,
  });
  final String code, message;
  final bool portalMessage;
  final Map<String, Object?>? diagnostics;
  @override
  String toString() => message;
}

Uri rajssoTrusted(Uri url) {
  if (!rajsimsTrustedUrl(url) || url.host != 'sso.rajasthan.gov.in') {
    throw const RajssoError(
      'INVALID_REDIRECT',
      'SSO request left the official HTTPS sign-in host.',
    );
  }
  return url;
}

Uri rajssoTrustedLaunch(Uri url) {
  if (!rajsimsTrustedUrl(url)) {
    throw const RajssoError(
      'INVALID_REDIRECT',
      'RajSIMS launch left the official HTTPS hosts.',
    );
  }
  return url;
}

(String, String)? rajssoLaunchTokens(Uri url) {
  rajssoTrustedLaunch(url);
  if (!_portalHosts.contains(url.host)) return null;
  var query = url.query;
  if (url.fragment.startsWith('/') && url.fragment.contains('?')) {
    if (['AuthId', 'AuthKey'].any(url.queryParametersAll.containsKey)) {
      throw const RajssoError(
        'PORTAL_LAUNCH_CHANGED',
        'RajSIMS returned authentication in both document and route queries.',
      );
    }
    query = url.fragment.substring(url.fragment.indexOf('?') + 1);
  }
  final values = Uri(query: query).queryParametersAll;
  if (!['AuthId', 'AuthKey'].any(values.containsKey)) return null;
  for (final key in ['AuthId', 'AuthKey']) {
    if (values[key]?.length != 1 || values[key]!.single.trim().isEmpty) {
      throw const RajssoError(
        'PORTAL_LAUNCH_CHANGED',
        'RajSIMS returned ambiguous or empty authentication parameters.',
      );
    }
  }
  return (values['AuthId']!.single, values['AuthKey']!.single);
}

String rajssoEncrypt(String value, String key, String iv) {
  final keyBytes = Uint8List.fromList(utf8.encode(key));
  final ivBytes = Uint8List.fromList(utf8.encode(iv));
  if (![16, 24, 32].contains(keyBytes.length) || ivBytes.length != 16) {
    throw const RajssoError(
      'FORM_CHANGED',
      'SSO encryption parameters changed.',
    );
  }
  final plaintext = Uint8List.fromList(utf8.encode(value.trim()));
  final padded = Uint8List(plaintext.length + 16 - plaintext.length % 16)
    ..setRange(0, plaintext.length, plaintext);
  PKCS7Padding().addPadding(padded, plaintext.length);
  final cipher = CBCBlockCipher(AESEngine())
    ..init(
      true,
      ParametersWithIV<KeyParameter>(KeyParameter(keyBytes), ivBytes),
    );
  final encrypted = Uint8List(padded.length);
  for (var offset = 0; offset < padded.length; offset += 16) {
    cipher.processBlock(padded, offset, encrypted, offset);
  }
  return base64Encode(encrypted);
}

String _quoteForm(String value) {
  final out = StringBuffer();
  for (final byte in utf8.encode(value)) {
    if ((byte >= 65 && byte <= 90) ||
        (byte >= 97 && byte <= 122) ||
        (byte >= 48 && byte <= 57) ||
        [45, 46, 95, 126].contains(byte)) {
      out.writeCharCode(byte);
    } else if (byte == 32) {
      out.write('+');
    } else {
      out.write('%${byte.toRadixString(16).padLeft(2, '0').toUpperCase()}');
    }
  }
  return out.toString();
}

String rajssoEncodeForm(Iterable<(String, String)> fields) => fields
    .map((field) => '${_quoteForm(field.$1)}=${_quoteForm(field.$2)}')
    .join('&');

Element? _form(Element element) {
  for (var parent = element.parent; parent != null; parent = parent.parent) {
    if (parent.localName == 'form') return parent;
  }
  return null;
}

Map<String, String> rajssoNavigationHeaders(
  Uri target, [
  Uri? referer,
  bool post = false,
]) {
  rajssoTrustedLaunch(target);
  final headers = <String, String>{
    'Accept': rajssoDocumentAccept,
    'Sec-Fetch-Mode': 'navigate',
    'Sec-Fetch-Dest': 'document',
  };
  if (referer == null) {
    headers['Sec-Fetch-Site'] = 'none';
  } else {
    rajssoTrustedLaunch(referer);
    // Preserve the Python tuple: explicit :443 and implicit HTTPS differ here.
    final same =
        target.scheme == referer.scheme &&
        target.host == referer.host &&
        target.hasPort == referer.hasPort &&
        target.port == referer.port;
    final origin = '${referer.scheme}://${referer.authority}';
    headers['Referer'] = same
        ? referer.removeFragment().toString()
        : '$origin/';
    headers['Sec-Fetch-Site'] = same ? 'same-origin' : 'same-site';
    if (post) {
      headers['Origin'] = origin;
      headers['Content-Type'] = 'application/x-www-form-urlencoded';
    }
  }
  return headers;
}

class RajssoForm {
  const RajssoForm(
    this.controls,
    this.fields,
    this.action,
    this.key,
    this.iv,
    this.image,
  );
  final Map<String, Element> controls;
  final Map<String, String> fields;
  final Uri action;
  final String key, iv;
  final String? image;
}

RajssoForm rajssoParseForm(
  String text, [
  Uri? url,
  bool sessionConfirmation = false,
]) {
  url ??= Uri.parse(rajssoSignin);
  final doc = html.parse(text);
  final controls = <String, Element>{};
  for (final entry in rajssoIds.entries) {
    final element = doc.getElementById(entry.value);
    if (entry.key == 'captcha' && sessionConfirmation) {
      if (element != null) controls[entry.key] = element;
      continue;
    }
    if (element == null ||
        (element.attributes['name'] ?? '').isEmpty ||
        element.attributes.containsKey('disabled')) {
      throw const RajssoError(
        'FORM_CHANGED',
        'SSO login controls are missing or disabled.',
      );
    }
    controls[entry.key] = element;
  }
  final form = _form(controls['password']!);
  if (form == null ||
      controls.values.any((element) => !identical(_form(element), form))) {
    throw const RajssoError(
      'FORM_CHANGED',
      'SSO controls are outside the sign-in form.',
    );
  }
  final action = rajssoTrusted(
    url.resolve(form.attributes['action'] ?? url.toString()),
  );
  if (action.path.toLowerCase() != '/signin') {
    throw const RajssoError('FORM_CHANGED', 'SSO sign-in action changed.');
  }
  final script = doc.querySelectorAll('script').map((x) => x.text).join('\n');
  final key = RegExp(r'''var\s+key\s*=\s*['"]([^'"]+)['"]''')
      .firstMatch(script);
  final iv = RegExp(r'''var\s+iv\s*=\s*['"]([^'"]+)['"]''').firstMatch(script);
  if (key == null ||
      iv == null ||
      !script.contains('encryptFormData(key, iv)')) {
    throw const RajssoError(
      'FORM_CHANGED',
      'Official SSO encryption initialization is missing.',
    );
  }
  final fields = <String, String>{};
  for (final field in form.querySelectorAll('input[name]')) {
    final kind = (field.attributes['type'] ?? 'text').toLowerCase();
    if (!_successful(field, kind)) continue;
    fields[field.attributes['name']!] =
        field.attributes['value'] ??
        (['radio', 'checkbox'].contains(kind) ? 'on' : '');
  }
  if ((fields['__VIEWSTATE'] ?? '').isEmpty) {
    throw const RajssoError('FORM_CHANGED', 'SSO ViewState is missing.');
  }
  final image = doc
      .getElementById('cpBodyMain_cpBody_ssoCaptcha_imgCaptcha')
      ?.attributes['src'];
  if ((image == null || image.isEmpty) && !sessionConfirmation) {
    throw const RajssoError('FORM_CHANGED', 'SSO CAPTCHA image is missing.');
  }
  return RajssoForm(controls, fields, action, key[1]!, iv[1]!, image);
}

bool _successful(Element field, String kind) =>
    !field.attributes.containsKey('disabled') &&
    !['submit', 'button', 'image', 'file', 'reset'].contains(kind) &&
    (!['radio', 'checkbox'].contains(kind) ||
        field.attributes.containsKey('checked'));

bool rajssoAuthenticated(String text, Uri url) {
  if (url.path.toLowerCase() == '/signin') return false;
  final doc = html.parse(text);
  if (doc.getElementById(rajssoIds['password']!) != null) return false;
  return doc
          .querySelectorAll('a.tile_anchor,li[data-app]')
          .any(
            (element) =>
                (element.attributes[element.localName == 'a'
                            ? 'title'
                            : 'data-app'] ??
                        '')
                    .toUpperCase()
                    .contains('RAJSIMS'),
          ) ||
      doc
          .querySelectorAll('[id]')
          .any(
            (element) => RegExp(
              'btnLogout|lnkLogout',
              caseSensitive: false,
            ).hasMatch(element.id),
          );
}

class RajssoAction {
  const RajssoAction(this.method, this.url, [this.fields]);
  final String method;
  final Uri url;
  final List<(String, String)>? fields;
}

RajssoAction rajssoParseLaunchForm(String text, [Uri? url]) {
  url = rajssoTrusted(url ?? Uri.parse(rajssoDashboard));
  final doc = html.parse(text);
  final tiles = doc.querySelectorAll('a.tile_anchor[title="RAJSIMS"]');
  if (tiles.length != 1) {
    throw const RajssoError(
      'PORTAL_LAUNCH_CHANGED',
      'A unique official RajSIMS tile was not returned.',
    );
  }
  final tile = tiles.single;
  final event = RegExp(r"^javascript:__doPostBack\('([^']+)','([^']*)'\)$")
      .firstMatch(tile.attributes['href'] ?? '');
  final form = _form(tile);
  if (event == null || form == null) {
    throw const RajssoError(
      'PORTAL_LAUNCH_CHANGED',
      'RajSIMS tile postback changed.',
    );
  }
  final action = rajssoTrusted(
    url.resolve(form.attributes['action'] ?? url.toString()),
  );
  if (action.path.toLowerCase() != '/sso' ||
      (form.attributes['method'] ?? 'get').toLowerCase() != 'post') {
    throw const RajssoError(
      'PORTAL_LAUNCH_CHANGED',
      'RajSIMS dashboard form action changed.',
    );
  }
  final fields = <(String, String)>[];
  for (final field in form.querySelectorAll('input[name]')) {
    final kind = (field.attributes['type'] ?? 'text').toLowerCase();
    if (!_successful(field, kind) ||
        ['__EVENTTARGET', '__EVENTARGUMENT'].contains(field.attributes['name']))
      continue;
    fields.add((
      field.attributes['name']!,
      field.attributes['value'] ??
          (['radio', 'checkbox'].contains(kind) ? 'on' : ''),
    ));
  }
  if (!fields.any(
    (field) => field.$1 == '__VIEWSTATE' && field.$2.isNotEmpty,
  )) {
    throw const RajssoError(
      'PORTAL_LAUNCH_CHANGED',
      'RajSIMS dashboard ViewState is missing.',
    );
  }
  fields.addAll([('__EVENTTARGET', event[1]!), ('__EVENTARGUMENT', event[2]!)]);
  return RajssoAction('POST', action, fields);
}

String _nativeText(Node node) {
  final parts = <String>[];
  void visit(Node current) {
    if (current is Text) {
      final text = current.data.trim();
      if (text.isNotEmpty) parts.add(text);
    } else {
      for (final child in current.nodes) {
        visit(child);
      }
    }
  }

  visit(node);
  return parts.join(' ');
}

/// Literal startup calls only; definitions and conditional code are not messages.
List<String> rajssoStartupMessages(Document doc) {
  const literal = r'''(?:"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')''';
  final call = RegExp(
    r'^(?:window\.)?(ShowAlertBox|ShowAlert|ShowMessage|ShowModelPopup|alert)\s*\((.*?)\)\s*;?$',
    dotAll: true,
  );
  final arguments = RegExp(
    '^\\s*($literal)(?:\\s*,\\s*($literal|null|undefined))*\\s*\$',
    dotAll: true,
  );
  final messages = <String>[];
  final bodies = [
    ...doc.querySelectorAll('script').map((e) => e.text),
    ...doc.querySelectorAll('[onload]').map((e) => e.attributes['onload']!),
  ];
  for (var body in bodies) {
    body = body
        .replaceAll(
          RegExp(r'^\s*//(?:<!\[CDATA\[|\]\]>)\s*$', multiLine: true),
          '',
        )
        .trim();
    final wrapper = RegExp(
      r'^(?:Sys\.Application\.add_(?:load|init)|\$\(document\)\.ready)\s*\(\s*function\s*\(\s*\)\s*\{(.*?)\}\s*\)\s*;?$',
      dotAll: true,
    ).firstMatch(body);
    final shortReady = RegExp(
      r'^\$\s*\(\s*function\s*\(\s*\)\s*\{(.*?)\}\s*\)\s*;?$',
      dotAll: true,
    ).firstMatch(body);
    if (wrapper != null || shortReady != null)
      body = (wrapper ?? shortReady)![1]!.trim();
    final statements = <String>[];
    String? quote;
    var escaped = false, unsupported = false;
    var depth = 0, start = 0;
    for (var i = 0; i < body.length; i++) {
      final c = body[i];
      if (quote != null) {
        if (escaped) {
          escaped = false;
        } else if (c == r'\') {
          escaped = true;
        } else if (c == quote) {
          quote = null;
        }
      } else if (c == "'" || c == '"') {
        quote = c;
      } else if (c == '{' || c == '}') {
        unsupported = true;
        break;
      } else if (c == '(') {
        depth++;
      } else if (c == ')') {
        depth--;
      } else if (c == ';' && depth == 0) {
        statements.add(body.substring(start, i).trim());
        start = i + 1;
      }
    }
    if (unsupported || quote != null || depth != 0) continue;
    statements.add(body.substring(start).trim());
    for (final statement in statements) {
      final match = call.firstMatch(statement);
      if (match == null || !arguments.hasMatch(match[2]!)) continue;
      final values = RegExp(literal)
          .allMatches(match[2]!)
          .map((m) => rajssoDecodeJsString(m[0]!))
          .toList();
      final index = ['ShowMessage', 'ShowModelPopup'].contains(match[1])
          ? 1
          : 0;
      if (match[1] == 'ShowModelPopup' &&
          (values.isEmpty || values.first != 'alert'))
        continue;
      if (values.length > index)
        messages.add(_nativeText(html.parseFragment(values[index])));
    }
  }
  return messages;
}

/// Only the observed visible checkbox inside the native sign-in form is used.
(String, String)? rajssoNativeSessionConfirmation(String text) {
  final doc = html.parse(text);
  final checkbox = doc.getElementById('cpBodyMain_cpBody_cbx_newsession');
  final password = doc.getElementById(rajssoIds['password']!);
  if (checkbox == null || password == null) return null;
  final form = _form(password);
  if (form == null ||
      !identical(_form(checkbox), form) ||
      (checkbox.attributes['type'] ?? '').toLowerCase() != 'checkbox' ||
      checkbox.attributes.containsKey('disabled') ||
      checkbox.attributes['name'] !=
          'ctl00\$ctl00\$cpBodyMain\$cpBody\$cbx_newsession')
    return null;
  for (Element? element = checkbox; element != null; element = element.parent) {
    if (element.attributes.containsKey('hidden') ||
        RegExp(
          r'display\s*:\s*none|visibility\s*:\s*hidden',
          caseSensitive: false,
        ).hasMatch(element.attributes['style'] ?? ''))
      return null;
  }
  return (checkbox.attributes['name']!, checkbox.attributes['value'] ?? 'on');
}

(String, String) rajssoOutcome(String text) {
  final doc = html.parse(text);
  final messages = doc
      .querySelectorAll(
        '.modal-dialog,.popup-dialog,.alert-danger,[role=alert],[id]',
      )
      .where(
        (e) =>
            e.classes.contains('modal-dialog') ||
            e.classes.contains('popup-dialog') ||
            e.classes.contains('alert-danger') ||
            e.attributes['role'] == 'alert' ||
            [
              'lblerror',
              'lblmessage',
              'lblalert',
            ].any(e.id.toLowerCase().contains),
      )
      .map(_nativeText)
      .toList();
  messages.addAll(rajssoStartupMessages(doc));
  final message = messages.join(' ').trim(), low = message.toLowerCase();
  var code = 'LOGIN_NOT_VERIFIED';
  if (low.contains('captcha') &&
      ['invalid', 'incorrect', 'wrong', 'mismatch'].any(low.contains)) {
    code = 'CAPTCHA_REJECTED';
  } else if ([
    'invalid digital identity',
    'invalid password',
    'अमान्य डिजिटल पहचान',
  ].any(low.contains)) {
    code = 'INVALID_CREDENTIALS';
  } else if (rajssoNativeSessionConfirmation(text) != null ||
      [
        'previous session',
        'previous active session',
        'terminate',
      ].any(low.contains)) {
    code = 'ACTIVE_SESSION_CONFIRMATION_REQUIRED';
  }
  return (code, message);
}

/// Response shape only: never includes document text, control values, account
/// identifiers, URL queries, credentials, CAPTCHA guesses, cookies or tokens.
Map<String, Object?> rajssoFailureDiagnostics(
  SchoolHttpReply reply,
  int attempt,
) {
  final doc = html.parse(reply.text);
  final path = reply.url.path.toLowerCase();
  const selectors =
      '.modal-dialog,.popup-dialog,.alert-danger,[role=alert],[id*=lblError],[id*=lblMessage],[id*=lblAlert]';
  final errors = doc.querySelectorAll(selectors);
  final script = doc.querySelectorAll('script').map((e) => e.text).join('\n');
  return {
    'attempt': attempt,
    'http_status': reply.statusCode,
    'page': path == '/signin'
        ? 'signin'
        : path == '/sso'
        ? 'dashboard'
        : 'other',
    'html_bytes': reply.bytes.length,
    'form_count': doc.querySelectorAll('form').length,
    'user_control': doc.getElementById(rajssoIds['user']!) != null,
    'password_control': doc.getElementById(rajssoIds['password']!) != null,
    'captcha_control': doc.getElementById(rajssoIds['captcha']!) != null,
    'error_nodes': errors.length,
    'nonempty_error_nodes': errors
        .where((e) => _nativeText(e).isNotEmpty)
        .length,
    'tile_count': doc.querySelectorAll('a.tile_anchor,li[data-app]').length,
    'logout_control': doc
        .querySelectorAll('[id]')
        .any(
          (e) => RegExp(
            'btnLogout|lnkLogout',
            caseSensitive: false,
          ).hasMatch(e.id),
        ),
    'javascript_alert_call': RegExp(r'\balert\s*\(').hasMatch(script),
    'javascript_redirect': RegExp(
      r'(?:window\.)?location(?:\.href)?\s*=|location\.(?:assign|replace)\s*\(',
    ).hasMatch(script),
    'meta_refresh': doc
        .querySelectorAll('meta[http-equiv]')
        .any((e) => e.attributes['http-equiv']?.toLowerCase() == 'refresh'),
  };
}

// Exact string-literal recognizer used by the Python candidate. No JS execution.
const _jsString = r"""(?:"(?:\\.|[^"\\\r\n])*"|'(?:\\.|[^'\\\r\n])*')""";
String rajssoDecodeJsString(String literal) {
  literal = literal.replaceAll(r'\/', '/');
  if (literal.length < 2 ||
      !['"', "'"].contains(literal[0]) ||
      literal[literal.length - 1] != literal[0]) {
    throw const RajssoError(
      'PORTAL_LAUNCH_CHANGED',
      'RajSIMS redirect string encoding changed.',
    );
  }
  final output = StringBuffer();
  for (var i = 1; i < literal.length - 1; i++) {
    var ch = literal[i];
    if (ch != r'\') {
      output.write(ch);
      continue;
    }
    if (++i >= literal.length - 1) {
      throw const RajssoError(
        'PORTAL_LAUNCH_CHANGED',
        'RajSIMS redirect string encoding changed.',
      );
    }
    ch = literal[i];
    const escaped = {
      'n': '\n',
      'r': '\r',
      't': '\t',
      'a': '\x07',
      'b': '\b',
      'f': '\f',
      'v': '\x0b',
      "'": "'",
      '"': '"',
      r'\': r'\',
    };
    if (escaped.containsKey(ch)) {
      output.write(escaped[ch]);
    } else if (['x', 'u', 'U'].contains(ch)) {
      final count = ch == 'x'
          ? 2
          : ch == 'u'
          ? 4
          : 8;
      if (i + count >= literal.length) {
        throw const RajssoError(
          'PORTAL_LAUNCH_CHANGED',
          'RajSIMS redirect string encoding changed.',
        );
      }
      final digits = literal.substring(i + 1, i + count + 1);
      final code = int.tryParse(digits, radix: 16);
      if (code == null || code > 0x10ffff) {
        throw const RajssoError(
          'PORTAL_LAUNCH_CHANGED',
          'RajSIMS redirect string encoding changed.',
        );
      }
      output.writeCharCode(code);
      i += count;
    } else if (RegExp('[0-7]').hasMatch(ch)) {
      var octal = ch;
      while (octal.length < 3 &&
          i + 1 < literal.length - 1 &&
          RegExp('[0-7]').hasMatch(literal[i + 1])) {
        octal += literal[++i];
      }
      output.writeCharCode(int.parse(octal, radix: 8));
    } else {
      output.write('\\$ch');
    }
  }
  final value = output.toString();
  if (value.runes.any((cp) => cp < 32)) {
    throw const RajssoError(
      'PORTAL_LAUNCH_CHANGED',
      'RajSIMS redirect string is invalid.',
    );
  }
  return value;
}

List<String> rajssoLiteralNavigation(String scripts) {
  final patterns = [
    r'window\.open\(\s*(' + _jsString + r')\s*(?=[,)])',
    r'(?:window\.|self\.|top\.)?location(?:\.href)?\s*=\s*(' +
        _jsString +
        r')\s*(?=[;}\r\n]|$)',
    r'(?:window\.|self\.|top\.)?location\.(?:replace|assign)\(\s*(' +
        _jsString +
        r')\s*\)',
  ];
  return [
    for (final pattern in patterns)
      for (final match in RegExp(pattern).allMatches(scripts))
        rajssoDecodeJsString(match[1]!),
  ];
}

RajssoAction rajssoDocumentLaunchAction(String text, Uri url) {
  final doc = html.parse(text);
  final scripts = doc
      .querySelectorAll('script:not([src])')
      .map((x) => x.text)
      .join('\n');
  final forms = doc.querySelectorAll('form');
  if (url.host == 'rajsims.rajasthan.gov.in' &&
      url.path.toLowerCase() == '/ssointegration/ssologin') {
    final links = doc.querySelectorAll('a.rajlink[href]');
    final counter = RegExp(r'''\bvar\s+cnt\s*=\s*(['"]?)([0-9]+)\1\s*;''')
        .firstMatch(scripts);
    if (links.isNotEmpty) {
      if (counter == null || counter[2] != '1' || links.length != 1) {
        throw const RajssoError(
          'DEPARTMENT_SELECTION_REQUIRED',
          'RajSIMS requires a department selection; no department was guessed.',
        );
      }
      if (!RegExp(
        r'''\$\(\s*(['"])\.rajlink\1\s*\)\.attr\(\s*(['"])href\2\s*\)''',
      ).hasMatch(scripts)) {
        throw const RajssoError(
          'PORTAL_LAUNCH_CHANGED',
          'Native RajSIMS department navigation changed.',
        );
      }
      final target = rajssoTrustedLaunch(
        url.resolve(links.single.attributes['href']!),
      );
      final params = target.queryParametersAll;
      if (target.host != 'rajsims.rajasthan.gov.in' ||
          target.path != '/SSOIntegration/SsoDetail' ||
          target.fragment.isNotEmpty ||
          ['SsoId', 'DeptId', 'Url', 'ssotoken'].any(
            (name) => params[name]?.length != 1 || params[name]!.single.isEmpty,
          )) {
        throw const RajssoError(
          'PORTAL_LAUNCH_CHANGED',
          'Native RajSIMS department link changed.',
        );
      }
      return RajssoAction('GET', target);
    }
  }
  if (url.host == 'rajsims.rajasthan.gov.in' &&
      url.path.toLowerCase() == '/ssointegration/ssodetail') {
    if (forms.length == 1) {
      final form = forms.single;
      if (form.id == 'myForm' &&
          (form.attributes['method'] ?? '').toLowerCase() == 'get' &&
          form
              .querySelectorAll(
                'input[name],select[name],textarea[name],button[name]',
              )
              .isEmpty &&
          RegExp(r'''document\.forms\[\s*(['"])myForm\1\s*\]\.submit\(\s*\)''')
              .hasMatch(scripts)) {
        final target = rajssoTrustedLaunch(
          url.resolve(form.attributes['action'] ?? url.toString()),
        );
        if (target.host == 'rajsims-mdm.rajasthan.gov.in' &&
            target.path == '/' &&
            target.query.isEmpty &&
            target.fragment.startsWith('/') &&
            rajssoLaunchTokens(target) != null) {
          return RajssoAction('GET', target);
        }
      }
    }
    throw const RajssoError(
      'PORTAL_LAUNCH_CHANGED',
      'Native RajSIMS MDM GET form changed.',
    );
  }
  final bridges = <RajssoAction>[];
  for (final form in forms) {
    final target = url.resolve(form.attributes['action'] ?? url.toString());
    if (target.host != 'rajsims.rajasthan.gov.in' ||
        target.path != '/SSOIntegration/SSOLogin')
      continue;
    rajssoTrustedLaunch(target);
    final bridgeChecks = <String, Object?>{
      'source_is_sso': url.host == 'sso.rajasthan.gov.in',
      'source_is_rajsims': url.host == 'rajsims.rajasthan.gov.in',
      'source_is_mdm': url.host == 'rajsims-mdm.rajasthan.gov.in',
      'action_query_empty': target.query.isEmpty,
      'action_fragment_empty': target.fragment.isEmpty,
      'method_is_post':
          (form.attributes['method'] ?? 'get').toLowerCase() == 'post',
      'single_form': forms.length == 1,
    };
    Map<String, Object?> diagnostic(String stage) => {
      'phase': 'rajsims_sso_bridge',
      'stage': stage,
      'checks': bridgeChecks,
    };
    if (url.host != 'sso.rajasthan.gov.in' ||
        target.query.isNotEmpty ||
        target.fragment.isNotEmpty ||
        (form.attributes['method'] ?? 'get').toLowerCase() != 'post') {
      throw RajssoError(
        'PORTAL_LAUNCH_CHANGED',
        'Official RajSIMS SSO bridge contract changed.',
        diagnostics: diagnostic('bridge_envelope'),
      );
    }
    final inputs = form.querySelectorAll('input[name]');
    bridgeChecks.addAll({
      'single_named_input': inputs.length == 1,
      'input_is_userdetails':
          inputs.length == 1 &&
          inputs.single.attributes['name'] == 'userdetails',
      'input_enabled':
          inputs.length == 1 &&
          !inputs.single.attributes.containsKey('disabled'),
      'input_hidden':
          inputs.length == 1 &&
          (inputs.single.attributes['type'] ?? 'text').toLowerCase() ==
              'hidden',
      'input_nonempty':
          inputs.length == 1 &&
          (inputs.single.attributes['value'] ?? '').isNotEmpty,
    });
    if (inputs.length != 1 ||
        inputs.single.attributes['name'] != 'userdetails' ||
        inputs.single.attributes.containsKey('disabled') ||
        (inputs.single.attributes['type'] ?? 'text').toLowerCase() !=
            'hidden' ||
        (inputs.single.attributes['value'] ?? '').isEmpty) {
      throw RajssoError(
        'PORTAL_LAUNCH_CHANGED',
        'Official RajSIMS userdetails field changed or is empty.',
        diagnostics: diagnostic('bridge_input'),
      );
    }
    bridges.add(
      RajssoAction('POST', target, [
        ('userdetails', inputs.single.attributes['value']!),
      ]),
    );
  }
  if (bridges.length == 1 && forms.length == 1) return bridges.single;
  if (bridges.isNotEmpty) {
    throw const RajssoError(
      'PORTAL_LAUNCH_CHANGED',
      'RajSIMS SSO bridge form is ambiguous.',
    );
  }
  final targets = <Uri>{};
  for (final literal in rajssoLiteralNavigation(scripts)) {
    final candidate = url.resolve(literal);
    if (_portalHosts.contains(candidate.host))
      targets.add(rajssoTrustedLaunch(candidate));
  }
  if (targets.length == 1) return RajssoAction('GET', targets.single);
  if (targets.length > 1) {
    throw const RajssoError(
      'PORTAL_LAUNCH_CHANGED',
      'Multiple RajSIMS launch destinations were returned.',
    );
  }
  final hiddenForms = <RajssoAction>[];
  for (final form in forms) {
    final id = form.id;
    if (id.isEmpty ||
        !RegExp(
          r"""document\.getElementById\(\s*(['"])""" +
              RegExp.escape(id) +
              r'\1\s*\)\.submit\(\s*\)',
        ).hasMatch(scripts))
      continue;
    final inputs = form.querySelectorAll('input[name]');
    if (inputs.isEmpty ||
        inputs.any(
          (el) => (el.attributes['type'] ?? 'text').toLowerCase() != 'hidden',
        ) ||
        (form.attributes['method'] ?? 'get').toLowerCase() != 'post')
      continue;
    final action = rajssoTrustedLaunch(
      url.resolve(form.attributes['action'] ?? url.toString()),
    );
    if (action.host != 'sso.rajasthan.gov.in' ||
        action.path.toLowerCase() != '/sso') {
      throw const RajssoError(
        'PORTAL_LAUNCH_CHANGED',
        'RajSIMS bridge form requires protocol inspection; no POST was sent.',
      );
    }
    hiddenForms.add(
      RajssoAction('POST', action, [
        for (final input in inputs)
          if (!input.attributes.containsKey('disabled'))
            (input.attributes['name']!, input.attributes['value'] ?? ''),
      ]),
    );
  }
  if (hiddenForms.length == 1) return hiddenForms.single;
  throw const RajssoError(
    'PORTAL_LAUNCH_CHANGED',
    'RajSIMS launch response requires protocol inspection; no script was executed.',
  );
}

class RajssoLoginResult {
  const RajssoLoginResult(this.client, this.dashboard, this.url, this.cached);
  final RajsimsHttpTransport client;
  final String dashboard;
  final Uri url;
  final bool cached;
}

/// Existing MDM worker's native message keys, without replacing portal text.
String? rajssoPortalMessage(Object? data) {
  if (data is! Map) return null;
  for (final key in const [
    'Message',
    'message',
    'ErrorMessage',
    'error',
    'Error',
    'ErrorDescription',
    'detail',
  ]) {
    final value = data[key];
    if (value is String && value.trim().isNotEmpty) return value;
  }
  return null;
}

class RajssoLaunchResult {
  const RajssoLaunchResult(this.authId, this.authKey, this.profile, this.url);
  final String authId, authKey;
  final Map<String, dynamic> profile;
  final Uri url;
}

class RajssoHttpx {
  const RajssoHttpx({required this.solveCaptcha, required this.clientFactory});
  final FutureOr<String> Function(Uint8List) solveCaptcha;
  final RajsimsHttpTransport Function() clientFactory;

  Future<SchoolHttpReply> getDocument(
    RajsimsHttpTransport client,
    Uri url, [
    Uri? referer,
  ]) async {
    for (var hop = 0; hop < 6; hop++) {
      final response = await client.request(
        'GET',
        rajssoTrusted(url),
        headers: rajssoNavigationHeaders(url, referer),
      );
      if (_redirects.contains(response.statusCode)) {
        referer = response.url;
        url = rajssoTrusted(
          response.url.resolve(response.headers['location']?.first ?? ''),
        );
        continue;
      }
      if (response.statusCode != 200) {
        throw const RajssoError(
          'SSO_HTTP_ERROR',
          'SSO document could not be read.',
        );
      }
      return response;
    }
    throw const RajssoError(
      'INVALID_REDIRECT',
      'SSO redirected too many times.',
    );
  }

  Future<Uint8List> getCaptchaImage(
    RajsimsHttpTransport client,
    Uri url,
    Uri referer,
  ) async {
    for (var hop = 0; hop < 6; hop++) {
      final response = await client.request(
        'GET',
        rajssoTrusted(url),
        headers: {'Referer': rajssoTrusted(referer).toString()},
      );
      if (_redirects.contains(response.statusCode)) {
        final location = response.headers['location']?.first;
        if (location == null || location.isEmpty) break;
        url = rajssoTrusted(response.url.resolve(location));
        continue;
      }
      if (response.statusCode == 200 &&
          (response.headers['content-type']?.first ?? '')
              .toLowerCase()
              .startsWith('image/') &&
          response.bytes.isNotEmpty) {
        return response.bytes;
      }
      break;
    }
    throw const RajssoError(
      'CAPTCHA_UNAVAILABLE',
      'SSO CAPTCHA image could not be read.',
    );
  }

  Future<RajssoLoginResult> login(
    String username,
    String password, {
    RajsimsHttpTransport? client,
    Map<String, dynamic>? savedState,
    int maxAttempts = 13,
  }) async {
    if (username.trim().isEmpty || password.isEmpty) {
      throw const RajssoError(
        'NO_CREDENTIALS',
        'SSO credentials are required.',
      );
    }
    final owns = client == null;
    final transport = client ?? clientFactory();
    try {
      if (savedState != null && savedState.isNotEmpty) {
        for (final value in (savedState['cookies'] as List? ?? const [])) {
          final cookie = value as Map;
          final domain = (cookie['domain'] ?? '').toString();
          final host = domain.replaceFirst(RegExp(r'^\.'), '');
          if (!['rajasthan.gov.in', 'sso.rajasthan.gov.in'].contains(host))
            continue;
          // HTTPX Cookies.set restores these without saved expiry/security flags.
          transport.jar.receive(
            [
              Cookie(cookie['name'] as String, cookie['value'] as String)
                ..domain = domain
                ..path = (cookie['path'] ?? '/') as String,
            ],
            Uri(
              scheme: 'https',
              host: host,
              path: (cookie['path'] ?? '/') as String,
            ),
          );
        }
        final cached = await getDocument(transport, Uri.parse(rajssoDashboard));
        if (rajssoAuthenticated(cached.text, cached.url)) {
          return RajssoLoginResult(transport, cached.text, cached.url, true);
        }
      }
      SchoolHttpReply? pendingDocument;
      var confirmationUsed = false;
      for (var attempt = 0; attempt <= maxAttempts; attempt++) {
        if (attempt == maxAttempts && pendingDocument == null) break;
        final confirming = pendingDocument != null;
        final document =
            pendingDocument ??
            await getDocument(transport, Uri.parse(rajssoSignin));
        pendingDocument = null;
        final form = rajssoParseForm(document.text, document.url, confirming);
        if (confirming) {
          final checkbox = rajssoNativeSessionConfirmation(document.text);
          if (checkbox == null)
            throw const RajssoError(
              'FORM_CHANGED',
              'Native session confirmation changed.',
            );
          form.fields[checkbox.$1] = checkbox.$2;
        }
        final Uint8List? raw;
        if (form.image == null) {
          raw = null;
        } else if (form.image!.startsWith('data:image/')) {
          final payload = form.image!.substring(form.image!.indexOf(',') + 1);
          // Python's b64decode(validate=True) rejects whitespace and URL alphabet.
          if (!RegExp(r'^[A-Za-z0-9+/]*={0,2}$').hasMatch(payload) ||
              payload.length % 4 != 0) {
            throw const FormatException('Invalid CAPTCHA image base64.');
          }
          raw = base64Decode(payload);
        } else {
          raw = await getCaptchaImage(
            transport,
            document.url.resolve(form.image!),
            document.url,
          );
        }
        final candidate = raw == null ? null : await solveCaptcha(raw);
        if (candidate != null &&
            (!RegExp(r'^[0-9]{6}$').hasMatch(candidate) ||
                candidate.length != 6)) {
          if (confirming) pendingDocument = document;
          continue;
        }
        for (final pair in [
          ('user', username.trim()),
          ('password', password),
        ]) {
          final el = form.controls[pair.$1]!;
          final encrypted =
              el.attributes['type'] == 'password' &&
                  el.attributes['data-encrypt'] != 'false' ||
              el.attributes['type'] == 'text' &&
                  el.attributes['data-encrypt'] == 'true';
          form.fields[el.attributes['name']!] = encrypted
              ? rajssoEncrypt(pair.$2, form.key, form.iv)
              : pair.$2.trim();
        }
        if (candidate != null)
          form.fields[form.controls['captcha']!.attributes['name']!] =
              candidate;
        form.fields[form.controls['button']!.attributes['name']!] =
            form.controls['button']!.attributes['value'] ?? 'Login';
        SchoolHttpReply response;
        try {
          response = await transport.request(
            'POST',
            form.action,
            content: rajssoEncodeForm(
              form.fields.entries.map((e) => (e.key, e.value)),
            ),
            headers: rajssoNavigationHeaders(form.action, document.url, true),
          );
        } on TimeoutException {
          final probe = await getDocument(
            transport,
            Uri.parse(rajssoDashboard),
          );
          if (rajssoAuthenticated(probe.text, probe.url)) {
            return RajssoLoginResult(transport, probe.text, probe.url, false);
          }
          throw const RajssoError(
            'LOGIN_RESULT_UNKNOWN',
            'SSO login result unknown; no credential POST was retried.',
          );
        }
        if ([301, 302, 303].contains(response.statusCode)) {
          response = await getDocument(
            transport,
            rajssoTrusted(
              response.url.resolve(response.headers['location']?.first ?? ''),
            ),
            response.url,
          );
        } else if (response.statusCode != 200) {
          throw const RajssoError(
            'LOGIN_RESULT_UNKNOWN',
            'SSO returned an unverified response; no credential POST was retried.',
          );
        }
        if (rajssoAuthenticated(response.text, response.url)) {
          return RajssoLoginResult(
            transport,
            response.text,
            response.url,
            false,
          );
        }
        final (code, message) = rajssoOutcome(response.text);
        if (code == 'ACTIVE_SESSION_CONFIRMATION_REQUIRED' &&
            rajssoNativeSessionConfirmation(response.text) != null &&
            !confirmationUsed) {
          confirmationUsed = true;
          pendingDocument = response;
          continue;
        }
        if (code == 'CAPTCHA_REJECTED') {
          if (confirming)
            throw RajssoError(
              code,
              message.isEmpty
                  ? 'SSO CAPTCHA rejected during session confirmation.'
                  : message,
              portalMessage: message.isNotEmpty,
            );
          continue;
        }
        if (code == 'LOGIN_NOT_VERIFIED') {
          // Latest Python confirms the protected dashboard once, without replay.
          final probe = await getDocument(
            transport,
            Uri.parse(rajssoDashboard),
          );
          if (rajssoAuthenticated(probe.text, probe.url))
            return RajssoLoginResult(transport, probe.text, probe.url, false);
        }
        throw RajssoError(
          code,
          message.isEmpty ? 'SSO did not confirm login: $code' : message,
          portalMessage: message.isNotEmpty,
          diagnostics: code == 'LOGIN_NOT_VERIFIED'
              ? rajssoFailureDiagnostics(response, attempt + 1)
              : null,
        );
      }
      throw const RajssoError(
        'CAPTCHA_UNAVAILABLE',
        'SSO CAPTCHA could not be verified within the attempt limit.',
      );
    } catch (_) {
      if (owns) await transport.close();
      rethrow;
    }
  }

  Future<RajssoLaunchResult> launch(RajssoLoginResult login) async {
    final first = rajssoParseLaunchForm(login.dashboard, login.url);
    final submitted = <(Uri, String)>{
      (first.url, rajssoEncodeForm(first.fields!)),
    };
    var method = 'POST';
    var response = await login.client.request(
      method,
      first.url,
      content: submitted.single.$2,
      headers: rajssoNavigationHeaders(first.url, login.url, true),
    );
    for (var hop = 0; hop < 8; hop++) {
      rajssoTrustedLaunch(response.url);
      final tokens = rajssoLaunchTokens(response.url);
      if (response.statusCode == 200 && tokens != null) {
        final profile = await login.client.request(
          'POST',
          Uri.parse(rajsimsBootstrap),
          content: jsonEncode({
            'ApiKey': 'ValidateTokenAndGetUserDetail',
            'OrgId': 0,
            'ApiParams': {'AuthId': tokens.$1, 'AuthKey': tokens.$2},
          }),
          headers: {
            'Accept': 'application/json, text/plain, */*',
            'Content-Type': 'application/json',
            'Origin': 'https://rajsims-mdm.rajasthan.gov.in',
            'Referer': 'https://rajsims-mdm.rajasthan.gov.in/',
            'Sec-Fetch-Site': 'same-origin',
            'Sec-Fetch-Mode': 'cors',
            'Sec-Fetch-Dest': 'empty',
          },
        );
        Object? data;
        try {
          data = jsonDecode(profile.text);
        } catch (_) {}
        final status = data is Map
            ? (data['StatusCode'] ?? data['statusCode'] ?? '').toString()
            : '';
        if (profile.statusCode != 200 ||
            data is! Map ||
            data['IsSuccess'] == false ||
            ['401', '403'].contains(status)) {
          final message = rajssoPortalMessage(data);
          throw RajssoError(
            'TOKEN_NOT_VERIFIED',
            message ?? 'RajSIMS did not verify the launch token.',
            portalMessage: message != null,
          );
        }
        return RajssoLaunchResult(
          tokens.$1,
          tokens.$2,
          Map<String, dynamic>.from(data),
          response.url,
        );
      }
      if (_redirects.contains(response.statusCode)) {
        if ([307, 308].contains(response.statusCode) && method == 'POST') {
          throw const RajssoError(
            'PORTAL_LAUNCH_CHANGED',
            'RajSIMS requested a POST redirect; no form was replayed.',
          );
        }
        final target = rajssoTrustedLaunch(
          response.url.resolve(response.headers['location']?.first ?? ''),
        );
        method = 'GET';
        response = await login.client.request(
          method,
          target,
          headers: rajssoNavigationHeaders(target, response.url),
        );
      } else if (response.statusCode == 200) {
        final action = rajssoDocumentLaunchAction(response.text, response.url);
        method = action.method;
        String? body;
        if (method == 'POST') {
          body = rajssoEncodeForm(action.fields!);
          if (!submitted.add((action.url, body))) {
            throw const RajssoError(
              'PORTAL_LAUNCH_CHANGED',
              'RajSIMS repeated a submitted launch form; no POST was replayed.',
            );
          }
        }
        response = await login.client.request(
          method,
          action.url,
          content: body,
          headers: rajssoNavigationHeaders(
            action.url,
            response.url,
            method == 'POST',
          ),
        );
      } else {
        throw const RajssoError(
          'PORTAL_LAUNCH_FAILED',
          'RajSIMS launch returned an unverified HTTP response.',
        );
      }
    }
    throw const RajssoError(
      'PORTAL_LAUNCH_CHANGED',
      'RajSIMS launch exceeded its redirect limit.',
    );
  }
}
