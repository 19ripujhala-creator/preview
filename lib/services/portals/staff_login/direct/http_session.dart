/// File equivalent of Staff Corner http_session.py; a separate Staff cookie jar.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import '../../../core/direct/async_primitives.dart';
import '../../shaladarpan/direct/school_http.dart';

const staffHost = 'rajshaladarpan.rajasthan.gov.in';
const staffLoginPath = '/Home/staff/stafflogin.aspx';
const staffHomePath = '/Home/Staff/StaffHome.aspx';

enum SessionProbe { alive, dead, unknown }

class StaffHttpError implements Exception {
  const StaffHttpError(this.code, this.message);
  final String code, message;
  @override
  String toString() => message;
}

String staffNodeBase(String value) {
  final url = Uri.tryParse(value);
  final authority = RegExp(
    r'^https://([^/?#]+)',
    caseSensitive: false,
  ).firstMatch(value)?.group(1)?.split('@').last;
  if (url == null ||
      url.scheme != 'https' ||
      url.host != staffHost ||
      url.hasPort ||
      authority?.contains(':') == true) {
    throw const StaffHttpError('INVALID_NODE', 'Unexpected Staff Portal host.');
  }
  final match = RegExp(
    r'^/(SD[1-5])(?:/|$)',
    caseSensitive: false,
  ).firstMatch(url.path);
  if (match == null) {
    throw const StaffHttpError(
      'INVALID_NODE',
      'Not an official Staff Portal node.',
    );
  }
  return 'https://$staffHost/${match[1]!.toUpperCase()}';
}

bool staffSameNode(String base, String value) {
  try {
    return staffNodeBase(base).toLowerCase() ==
        staffNodeBase(value).toLowerCase();
  } on StaffHttpError {
    return false;
  }
}

String staffText(Node node, [String separator = '']) {
  final parts = <String>[];
  void visit(Node item) {
    if (item is Element && ['script', 'style'].contains(item.localName)) return;
    if (item is Text) {
      final value = item.data.trim();
      if (value.isNotEmpty) parts.add(value);
    } else {
      for (final child in item.nodes) {
        visit(child);
      }
    }
  }

  visit(node);
  return parts.join(separator);
}

bool authenticatedStaffHome(SchoolHttpReply response) {
  if (response.statusCode != 200 ||
      !staffSameNode(response.url.toString(), response.url.toString()) ||
      !response.url.path.toLowerCase().endsWith(staffHomePath.toLowerCase()))
    return false;
  final doc = html.parse(response.text);
  if (doc.querySelector('#txt_Username, #txtUPNswd, #btn_StaffLogin') != null)
    return false;
  if (doc
      .querySelectorAll('[id]')
      .any((e) => e.id.toLowerCase().contains('logout')))
    return true;
  final name = doc.querySelector(
    '#ContentPlaceHolder1_lblStaffName, #ContentPlaceHolder1_lblEmployeeName',
  );
  if (name != null && staffText(name).isNotEmpty) return true;
  final heading = doc.querySelector('.widget-heading');
  return heading != null &&
      staffText(heading).isNotEmpty &&
      doc.querySelector('.widget-subheading') != null;
}

class StaffLoginForm {
  const StaffLoginForm({
    required this.base,
    required this.action,
    required this.fields,
    required this.userName,
    required this.passwordName,
    required this.captchaName,
    required this.captchaUrl,
    required this.submitName,
    required this.submitValue,
    required this.inlineScripts,
  });
  final String base,
      action,
      userName,
      passwordName,
      captchaName,
      captchaUrl,
      submitName,
      submitValue;
  final Map<String, String> fields;
  final List<String> inlineScripts;
}

StaffLoginForm parseStaffLoginForm(
  String base,
  String text,
  String documentUrl,
) {
  base = staffNodeBase(base);
  if (!staffSameNode(base, documentUrl)) {
    throw const StaffHttpError(
      'INVALID_REDIRECT',
      'Login page moved outside the selected node.',
    );
  }
  final doc = html.parse(text);
  final controls = [
    'txt_Username',
    'txtUPNswd',
    'txt_Captchaname',
    'Img2',
    'btn_StaffLogin',
  ].map(doc.getElementById).toList();
  if (controls.any((e) => e == null)) {
    throw const StaffHttpError(
      'LOGIN_FORM_CHANGED',
      'Expected Staff Login controls were not found.',
    );
  }
  Element? formOf(Element element) {
    var parent = element.parent;
    while (parent != null && parent.localName != 'form') {
      parent = parent.parent;
    }
    return parent;
  }

  final user = controls[0]!;
  final form = formOf(user);
  if (form == null ||
      [
        controls[1]!,
        controls[2]!,
        controls[4]!,
      ].any((e) => !identical(formOf(e), form))) {
    throw const StaffHttpError(
      'LOGIN_FORM_CHANGED',
      'Staff login controls are not in one form.',
    );
  }
  final fields = <String, String>{};
  for (final input in form.querySelectorAll('input[name]')) {
    final kind = (input.attributes['type'] ?? '').toLowerCase();
    if (['checkbox', 'radio'].contains(kind) &&
        !input.attributes.containsKey('checked'))
      continue;
    if (['file', 'submit', 'button', 'image'].contains(kind)) continue;
    fields[input.attributes['name']!] = input.attributes['value'] ?? '';
  }
  final uri = Uri.parse(documentUrl);
  final action = uri
      .resolve(
        form.attributes['action']?.isNotEmpty == true
            ? form.attributes['action']!
            : documentUrl,
      )
      .toString();
  final image = uri.resolve(controls[3]!.attributes['src'] ?? '').toString();
  if (!staffSameNode(base, action) || !staffSameNode(base, image)) {
    throw const StaffHttpError(
      'INVALID_REDIRECT',
      'Login form references an unexpected endpoint.',
    );
  }
  return StaffLoginForm(
    base: base,
    action: action,
    fields: fields,
    userName: user.attributes['name'] ?? '',
    passwordName: controls[1]!.attributes['name'] ?? '',
    captchaName: controls[2]!.attributes['name'] ?? '',
    captchaUrl: image,
    submitName: controls[4]!.attributes['name'] ?? '',
    submitValue: controls[4]!.attributes['value'] ?? '',
    inlineScripts: doc
        .querySelectorAll('script:not([src])')
        .map((e) => e.text)
        .toList(),
  );
}

abstract interface class StaffTransport {
  SchoolCookieJar get jar;
  Future<SchoolHttpReply> get(
    String url, {
    Map<String, String> headers,
    Duration? timeout,
    bool followRedirects = true,
  });
  Future<SchoolHttpReply> post(
    String url, {
    Map<String, String>? data,
    String? content,
    Map<String, String> headers,
    bool followRedirects = true,
  });
  void close();
}

class DartStaffTransport implements StaffTransport {
  DartStaffTransport({
    Duration timeout = const Duration(seconds: 20),
    String userAgent = 'Mozilla/5.0 (compatible; Rajshala/1.0)',
  }) : _client = SchoolHttpClient(
         baseUrl: Uri.parse('https://$staffHost/SD4'),
         timeout: timeout,
         defaultHeaders: {'User-Agent': userAgent, 'Accept': '*/*'},
         transport: HttpClient()
           ..maxConnectionsPerHost = 4
           ..idleTimeout = const Duration(seconds: 5),
       ),
       _userAgent = userAgent;
  final SchoolHttpClient _client;
  final String _userAgent;
  Map<String, String> _headers(Map<String, String> values) => {
    'User-Agent': _userAgent,
    'Accept': '*/*',
    ...values,
  };
  @override
  SchoolCookieJar get jar => _client.jar;
  @override
  Future<SchoolHttpReply> get(
    String url, {
    Map<String, String> headers = const {},
    Duration? timeout,
    bool followRedirects = true,
  }) => _client.request(
    'GET',
    Uri.parse(url),
    headers: _headers(headers),
    timeout: timeout,
    followRedirects: followRedirects,
  );
  @override
  Future<SchoolHttpReply> post(
    String url, {
    Map<String, String>? data,
    String? content,
    Map<String, String> headers = const {},
    bool followRedirects = true,
  }) {
    if (data != null && content != null)
      throw ArgumentError('Use form or content.');
    final body =
        content ??
        data?.entries
            .map(
              (e) =>
                  '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
            )
            .join('&');
    return _client.request(
      'POST',
      Uri.parse(url),
      followRedirects: followRedirects,
      body: body == null ? null : utf8.encode(body),
      headers: _headers({
        if (data != null) 'Content-Type': 'application/x-www-form-urlencoded',
        ...headers,
      }),
    );
  }

  @override
  void close() => _client.retire();
}

class StaffHttpSession {
  StaffHttpSession({
    StaffTransport? client,
    Duration timeout = const Duration(seconds: 20),
  }) : client = client ?? DartStaffTransport(timeout: timeout);
  final StaffTransport client;
  final lock = AsyncMutex();
  String? base, user;
  bool authenticated = false;
  Future<T> exclusive<T>(Future<T> Function() operation) async {
    final release = await lock.acquire(
      cancellation: OperationCancellation.current,
    );
    try {
      return await operation();
    } finally {
      release();
    }
  }

  Future<void> close() => exclusive(() async {
    authenticated = false;
    user = null;
    base = null;
    client.close();
  });
  Future<StaffLoginForm> inspectLogin(String selectedBase) {
    selectedBase = staffNodeBase(selectedBase);
    return exclusive(() async {
      final response = await client.get('$selectedBase$staffLoginPath');
      if (response.statusCode != 200)
        throw StaffHttpError(
          'PORTAL_UNAVAILABLE',
          'Login HTTP ${response.statusCode}',
        );
      return parseStaffLoginForm(
        selectedBase,
        response.text,
        response.url.toString(),
      );
    });
  }

  Future<Uint8List> readCaptcha(StaffLoginForm form) => exclusive(() async {
    final response = await client.get(
      form.captchaUrl,
      headers: {'Referer': form.action},
    );
    if (response.statusCode != 200 || response.bytes.isEmpty)
      throw const StaffHttpError(
        'CAPTCHA_UNAVAILABLE',
        'Captcha response was not an image.',
      );
    if (!(response.headers['content-type']?.join(',').toLowerCase() ?? '')
        .startsWith('image/'))
      throw const StaffHttpError(
        'CAPTCHA_UNAVAILABLE',
        'Captcha endpoint returned non-image content.',
      );
    return response.bytes;
  });
  Future<SessionProbe> probeStatus() => exclusive(() async {
    if (!authenticated || base == null) return SessionProbe.dead;
    SchoolHttpReply response;
    try {
      response = await client.get('$base$staffHomePath');
    } catch (_) {
      return SessionProbe.unknown;
    }
    if (authenticatedStaffHome(response)) return SessionProbe.alive;
    if (response.statusCode != 200 ||
        !staffSameNode(base!, response.url.toString()))
      return SessionProbe.unknown;
    return html
                .parse(response.text)
                .querySelector('#txt_Username, #txtUPNswd, #btn_StaffLogin') !=
            null
        ? SessionProbe.dead
        : SessionProbe.unknown;
  });
  Future<bool> probe() async => await probeStatus() == SessionProbe.alive;
  Future<void> adoptVerified(
    String selectedBase,
    String username,
    SchoolHttpReply home,
  ) => exclusive(() async {
    selectedBase = staffNodeBase(selectedBase);
    if (username.isEmpty ||
        !staffSameNode(selectedBase, home.url.toString()) ||
        !authenticatedStaffHome(home))
      throw const StaffHttpError(
        'AUTH_NOT_VERIFIED',
        'Staff Home authentication not established.',
      );
    base = selectedBase;
    user = username;
    authenticated = true;
  });
  StaffHttpError loginBlocker() => const StaffHttpError(
    'PASSWORD_TRANSFORM_UNVERIFIED',
    'sha512auth_New() implementation and Staff login response flow must be verified before enabling HTTP login.',
  );
}
