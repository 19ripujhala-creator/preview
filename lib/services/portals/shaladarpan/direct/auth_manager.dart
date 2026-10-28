/// Conversion of portals/shaladarpan/auth_manager.py.
/// Used behind the converted coordinator with the native ONNX solver.
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../../../core/direct/async_primitives.dart';
import '../../../core/direct/portal_diagnostics.dart';
import 'school_http.dart';
import 'server_manager.dart';

// Authentication probes map to core coordinator probe states in school_runtime.
enum SchoolProbe { alive, dead, repairRequired, unknown }

typedef SchoolCaptchaSolver = Future<String> Function(Uint8List bytes);
typedef RememberSchoolCredentials = void Function(String user, String password);

/// Device persistence replaces Python's two JSON files without exporting cookies.
abstract interface class SchoolAuthStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureSchoolAuthStorage implements SchoolAuthStorage {
  SecureSchoolAuthStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class SchoolAuthManager {
  SchoolAuthManager({
    required this.solveCaptcha,
    SchoolAuthStorage? storage,
    this.progress,
    this.rememberCredentials,
  }) : storage = storage ?? SecureSchoolAuthStorage();

  final SchoolCaptchaSolver solveCaptcha;
  final SchoolAuthStorage storage;
  final SchoolProgress? progress;
  final RememberSchoolCredentials? rememberCredentials;
  static const loginBudget = Duration(seconds: 35);
  static const maxCaptchaAttempts = 5;
  static const _activeKey = 'rajshala.direct.sd.active';
  static const _cookieKey = 'rajshala.direct.sd.cookies';
  static const _successMarkers = [
    'home_new.aspx',
    'dashboard',
    'mainpage',
    'studentdetail',
    'home.aspx',
    'home/school',
  ];
  static const _deadMarkers = [
    'default.aspx',
    'officelogin',
    '/public',
    'login.aspx',
  ];
  static const _badCredentials = [
    'invalid username',
    'invalid password',
    'invalid user',
    'wrong password',
    'user not found',
  ];

  final Map<String, String> _active = {};
  Map<String, String> _cookies = {};
  SchoolHttpClient? _client;
  Object? get idleActivityStamp => _client?.idleActivityStamp;
  Future<void>? _initialization;
  Future<void> _writes = Future<void>.value();
  final Map<String, String> _persisted = {};
  (String, String)? _clientIdentity;

  String get activeServerBase => _active['server_base'] ?? schoolServers.first;
  String get activeSchoolId => _active['user'] ?? '';
  String get schoolId => activeSchoolId;
  (String, String)? get sessionIdentity {
    if (activeSchoolId.isEmpty || _cookies.isEmpty) return null;
    final id = _active['session_id'];
    return id == null || id.isEmpty ? null : (activeSchoolId, id);
  }

  static String md5Hex(String value) =>
      md5.convert(utf8.encode(value)).toString();
  static String sha512Hex(String value) =>
      sha512.convert(utf8.encode(value)).toString();

  static Map<String, dynamic> _fail(String code, String message) => {
    'success': false,
    'code': code,
    'message': message,
  };

  static String extractServerBase(String url, String fallback) {
    final parsed = Uri.parse(url);
    final match = RegExp(
      r'^/(SD[1-5])(?:/|$)',
      caseSensitive: false,
    ).firstMatch(parsed.path);
    // Retains Python's scheme/host recognition; transport checks exact HTTPS host.
    if (const ['http', 'https'].contains(parsed.scheme) &&
        parsed.authority.toLowerCase().contains(
          'rajshaladarpan.rajasthan.gov.in',
        ) &&
        match != null) {
      return '${parsed.scheme}://${parsed.authority}/${match.group(1)}';
    }
    return fallback;
  }

  Future<void> initialize() => _initialization ??= _load();
  Future<void> _load() async {
    try {
      final active = await storage.read(_activeKey);
      if (active != null) {
        final data = jsonDecode(active);
        if (data is Map) {
          for (final entry in data.entries) {
            if (entry.value != null && entry.value.toString().isNotEmpty) {
              _active[entry.key.toString()] = entry.value.toString();
            }
          }
        }
      }
    } catch (_) {
      /* Python treats missing/unreadable state as no saved state. */
    }
    try {
      final cookies = await storage.read(_cookieKey);
      if (cookies != null) {
        _cookies = Map<String, String>.from(jsonDecode(cookies) as Map);
      }
    } catch (_) {
      _cookies = {};
    }
    if (activeSchoolId.isNotEmpty &&
        _cookies.isNotEmpty &&
        (_active['session_id'] ?? '').isEmpty) {
      _active['session_id'] = _newSessionId();
      await _persist(_activeKey, _active);
    }
  }

  String _newSessionId() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<void> _persist(
    String key,
    Map<String, String> data, {
    (String, String)? expected,
  }) {
    final keys = data.keys.toList()..sort();
    final frozen = jsonEncode({for (final key in keys) key: data[key]});
    final previous = _writes;
    final operation =
        PortalDiagnostics.measure(
          PortalPhase.httpStorageQueue,
          () => previous,
          source: 'school',
        ).then((_) async {
          if (expected != null && sessionIdentity != expected) return;
          if (_persisted[key] == frozen) return;
          try {
            await PortalDiagnostics.measure(
              PortalPhase.httpStorageWrite,
              () => storage.write(key, frozen),
              source: 'school',
            );
            _persisted[key] = frozen;
          } catch (_) {
            /* Working Python persistence failures are nonfatal. */
          }
        });
    _writes = operation;
    return operation;
  }

  Future<void> saveActiveServerBase(String base, {String? user}) async {
    await initialize();
    base = base.replaceFirst(RegExp(r'/+$'), '');
    if (base.isEmpty) return;
    _active['server_base'] = base;
    if (user != null) {
      if (_active['user'] != user) _active.remove('session_id');
      _active['user'] = user;
    }
    await _persist(_activeKey, _active);
  }

  Future<void> saveSessionCookies(Map<String, String> cookies) async {
    await initialize();
    _cookies = Map.of(cookies);
    await _persist(_cookieKey, _cookies);
  }

  Map<String, String> loadSessionCookies() => Map.of(_cookies);

  void _retireAuthenticatedClient() {
    final previous = _client;
    _client = null;
    _clientIdentity = null;
    previous?.retire();
  }

  Future<void> forgetSavedSession() async {
    await initialize();
    _retireAuthenticatedClient();
    _active.clear();
    _cookies.clear();
    _persisted.clear();
    final delete = _writes.then((_) async {
      for (final key in [_activeKey, _cookieKey]) {
        try {
          await storage.delete(key);
          _persisted.remove(key);
        } catch (_) {
          /* Python suppresses. */
        }
      }
    });
    _writes = delete;
    await delete;
  }

  Future<SchoolHttpClient> getAuthenticatedClient({String? baseUrl}) async {
    await initialize();
    final base = (baseUrl ?? activeServerBase).replaceFirst(RegExp(r'/+$'), '');
    final identity = sessionIdentity;
    if (identity == null) {
      // Caller owns this unauthenticated one-shot client and must retire it.
      return SchoolHttpClient(baseUrl: Uri.parse(base));
    }
    final current = _client;
    if (current != null &&
        !current.retired &&
        !current.isClosed &&
        _clientIdentity == identity &&
        current.baseUrl.toString() == base) {
      return current;
    }
    _retireAuthenticatedClient();
    final client = SchoolHttpClient(
      baseUrl: Uri.parse(base),
      cookies: _cookies,
      onCookies: (owner, responseUrl) async {
        if (owner.retired ||
            !identical(_client, owner) ||
            _clientIdentity != identity ||
            sessionIdentity != identity)
          return;
        final snapshot = owner.jar.snapshot(responseUrl);
        if (snapshot.isEmpty && owner.jar.snapshot().isNotEmpty) return;
        _cookies = snapshot;
        await _persist(_cookieKey, snapshot, expected: identity);
      },
    );
    _clientIdentity = identity;
    _client = client;
    return client;
  }

  /// Preferred worker API: retain a retired pool until active work settles.
  Future<T> withAuthenticatedClient<T>(
    Future<T> Function(SchoolHttpClient) operation, {
    String? baseUrl,
  }) async {
    final client = await PortalDiagnostics.measure(
      PortalPhase.httpClientAcquire,
      () => getAuthenticatedClient(baseUrl: baseUrl),
      source: 'school',
    );
    final pooled = identical(client, _client);
    try {
      return await client.withLease(operation);
    } finally {
      if (!pooled) client.retire();
    }
  }

  Future<void> closeAuthenticatedClients() async {
    _retireAuthenticatedClient();
    await _writes;
  }

  Future<Map<String, dynamic>?> fetchHome({String? base}) async {
    await initialize();
    if (_cookies.isEmpty) return null;
    final node = (base ?? activeServerBase).replaceFirst(RegExp(r'/+$'), '');
    try {
      return await withAuthenticatedClient((client) async {
        final response = await client.get(
          '$node/Home/School/Home_New.aspx',
          timeout: const Duration(seconds: 10),
        );
        return {
          'url': response.url.toString(),
          'status': response.statusCode,
          'text': response.text,
        };
      }, baseUrl: node);
    } catch (_) {
      return null;
    }
  }

  static SchoolProbe classifyHome(Map<String, dynamic>? home) {
    if (home == null || home.isEmpty || home['status'] != 200) {
      return SchoolProbe.unknown;
    }
    final soup = html_parser.parse(home['text'] as String? ?? '');
    final path = Uri.parse(home['url'] as String? ?? '').path.toLowerCase();
    if (_deadMarkers.any(path.contains) ||
        soup.querySelector('#bodyContent_txtUName, #txtUserId') != null) {
      return SchoolProbe.dead;
    }
    dom.Element? label;
    var logout = false;
    for (final element in soup.querySelectorAll('[id]')) {
      if (RegExp(
        r'(?:^|_)lblSchoolName$',
        caseSensitive: false,
      ).hasMatch(element.id))
        label ??= element;
      if (element.id.toLowerCase().contains('logout')) logout = true;
    }
    if (logout || (label != null && label.text.trim().isNotEmpty)) {
      return SchoolProbe.alive;
    }
    if (path.contains('home_new.aspx') || path.contains('home.aspx')) {
      return SchoolProbe.alive;
    }
    return SchoolProbe.unknown;
  }

  Future<SchoolProbe> probeContext({String? base}) async {
    final home = await fetchHome(base: base ?? activeServerBase);
    final verdict = classifyHome(home);
    if (verdict == SchoolProbe.alive && home != null) {
      final actual = extractServerBase(home['url'] as String, '');
      if (actual.isNotEmpty &&
          actual.toLowerCase() != activeServerBase.toLowerCase()) {
        await saveActiveServerBase(actual);
      }
    }
    return verdict;
  }

  static dom.Element? _input(dom.Document doc, String pattern) {
    final regex = RegExp(pattern, caseSensitive: false);
    for (final element in doc.querySelectorAll('input[id]')) {
      if (regex.hasMatch(element.id)) return element;
    }
    return null;
  }

  /// Exact password hash/payload formulas used by the Python auth manager.
  static Map<String, String> buildLoginPayload(
    dom.Document soup, {
    required String user,
    required String password,
    required String loginId,
    required String captcha,
  }) {
    final viewstate = soup.querySelector('input#__VIEWSTATE');
    final eventval = soup.querySelector('input#__EVENTVALIDATION');
    if (viewstate == null || eventval == null) {
      throw StateError('ViewState or EventValidation missing on page.');
    }
    final salt = _input(soup, 'hdnfld')?.attributes['value'] ?? '';
    String field(String pattern, String fallback) =>
        _input(soup, pattern)?.attributes['name'] ?? fallback;
    final hashedPassword = sha512Hex(password);
    final payload = <String, String>{
      '__VIEWSTATE': viewstate.attributes['value'] ?? '',
      '__EVENTVALIDATION': eventval.attributes['value'] ?? '',
      field('txtUName', 'ctl00\$bodyContent\$txtUName'): user,
      field('txtUPswd', 'ctl00\$bodyContent\$txtUPswd'): sha512Hex(
        salt + sha512Hex(loginId.toLowerCase() + password),
      ),
      'ctl00\$bodyContent\$hdnLoginid': loginId,
      'ctl00\$bodyContent\$hdnfld': salt,
      'ctl00\$bodyContent\$hdntxtop': sha512Hex(md5Hex(loginId + password)),
      'ctl00\$bodyContent\$hdntxtUPswdname': hashedPassword,
      'ctl00\$bodyContent\$hdntxtUPswdname1': sha512Hex(salt + hashedPassword),
      field('txt_Captchaname', 'ctl00\$bodyContent\$txt_Captchaname'): captcha,
      field('btn_Login', 'ctl00\$bodyContent\$btn_Login'): 'Login',
    };
    final generator = soup.querySelector('input#__VIEWSTATEGENERATOR');
    if (generator != null) {
      payload['__VIEWSTATEGENERATOR'] = generator.attributes['value'] ?? '';
    }
    return payload;
  }

  /// Classify only actual response messages, never dormant validator strings.
  /// CAPTCHA rejection takes priority when a portal reports multiple errors.
  static Map<String, dynamic> loginRejection(String responseHtml) {
    final document = html_parser.parse(responseHtml);
    bool visible(dom.Element element) {
      for (
        dom.Element? current = element;
        current != null;
        current = current.parent
      ) {
        final style = (current.attributes['style'] ?? '').toLowerCase();
        if (current.attributes.containsKey('hidden') ||
            current.attributes['aria-hidden'] == 'true' ||
            RegExp(r'display\s*:\s*none|visibility\s*:\s*hidden')
                .hasMatch(style)) {
          return false;
        }
      }
      return true;
    }

    final messages = <String>[];
    for (final element in document.querySelectorAll(
      '#bodyContent_lblMsg, .alert, #lblMsg',
    )) {
      final text = _strippedText(element);
      if (visible(element) && text.isNotEmpty && !messages.contains(text))
        messages.add(text);
    }
    if (messages.isEmpty) {
      // ASP.NET writes literal startup alerts as standalone script statements.
      // An alert inside a declared validation function is not a portal response.
      final startup = RegExp(
        r'''^\s*(?:(?://<!\[CDATA\[|<!--|/\*<!\[CDATA\[\*/|;)\s*)*alert\s*\(\s*(['"])(.*?)\1\s*\)''',
        dotAll: true,
      );
      for (final script in document.querySelectorAll('script')) {
        var body = script.text;
        while (true) {
          final match = startup.firstMatch(body);
          if (match == null) break;
          final text = match.group(2)!;
          if (text.isNotEmpty && !messages.contains(text)) messages.add(text);
          body = body.substring(match.end);
        }
      }
    }
    final message = messages.join(' | ');
    final lower = message.toLowerCase();
    final captcha = lower.contains('captcha');
    final invalidCredentials = !captcha && _badCredentials.any(lower.contains);
    return {
      'code': captcha
          ? 'CAPTCHA_REJECTED'
          : invalidCredentials
          ? 'INVALID_CREDENTIALS'
          : 'LOGIN_REJECTED',
      'retry': !invalidCredentials,
      if (message.isNotEmpty) 'portal_message': message,
    };
  }

  Future<Map<String, dynamic>> _freshHttpLogin(
    String user,
    String password,
    String nodeBase,
    Stopwatch clock,
  ) async {
    final loginUrl = '$nodeBase/Home/Public2/OfficeLoginNew.aspx';
    final client = SchoolHttpClient(
      baseUrl: Uri.parse(nodeBase),
      timeout: const Duration(seconds: 15),
    );
    String? lastPortalMessage;
    try {
      for (var attempt = 1; attempt <= maxCaptchaAttempts; attempt++) {
        OperationCancellation.current?.check();
        if (clock.elapsed > loginBudget) {
          return _fail('TIMEOUT', 'Login time budget expired.');
        }
        client.jar.clear();
        progress?.call(
          min(30 + attempt * 12, 85),
          'Solving CAPTCHA (attempt $attempt)...',
        );
        final page = await client.get(loginUrl);
        if (page.statusCode != 200) continue;
        final soup = html_parser.parse(page.text);
        if (soup.querySelector('input#__VIEWSTATE') == null ||
            soup.querySelector('input#__EVENTVALIDATION') == null)
          continue;

        var loginId = user;
        try {
          final check = await client.post(
            '$loginUrl/getUserid',
            json: {'Userid': user},
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              'X-Requested-With': 'XMLHttpRequest',
            },
          );
          final value = check.jsonMap();
          if (value.containsKey('d')) {
            if (value['d'] is! String) {
              throw StateError('Portal getUserid result must be text.');
            }
            loginId = value['d'] as String;
          }
        } catch (_) {
          loginId = user;
        }

        final img = soup.querySelector('#bodyContent_Img2, #imgCaptcha');
        final source = img?.attributes['src'] ?? 'Captcha.aspx';
        // Python resolves against the originally selected login URL.
        final cap = await client.get(
          Uri.parse(loginUrl).resolve(source).toString(),
        );
        final captcha = await solveCaptcha(cap.bytes);
        OperationCancellation.current?.check();
        if (captcha.isEmpty || captcha.runes.length < 4) continue;
        final payload = buildLoginPayload(
          soup,
          user: user,
          password: password,
          loginId: loginId,
          captcha: captcha,
        );
        final posted = await client.post(loginUrl, data: payload);
        OperationCancellation.current?.check();
        final landed = posted.url.toString();
        if (_successMarkers.any(landed.toLowerCase().contains)) {
          final node = extractServerBase(landed, nodeBase);
          await saveActiveServerBase(node, user: user);
          await saveSessionCookies(client.jar.snapshot());
          _active['session_id'] = _newSessionId();
          await _persist(_activeKey, _active);
          _retireAuthenticatedClient();
          rememberCredentials?.call(user, password);
          progress?.call(100, 'Portal Live on HOME!');
          return {
            'success': true,
            'cached': false,
            'server_base': node,
            'server_name': node.split('/').last,
            'latency': 0,
            'current_url': landed,
          };
        }
        final rejection = loginRejection(posted.text);
        lastPortalMessage = rejection['portal_message'] as String?;
        if (rejection['code'] == 'INVALID_CREDENTIALS') {
          return {
            ..._fail('INVALID_CREDENTIALS', lastPortalMessage!),
            'portal_message': lastPortalMessage,
          };
        }
      }
      return {
        ..._fail(
          'LOGIN_FAILED',
          lastPortalMessage ?? 'Login failed after maximum CAPTCHA attempts.',
        ),
        if (lastPortalMessage != null) 'portal_message': lastPortalMessage,
      };
    } finally {
      client.retire();
    }
  }

  static String _strippedText(dom.Element element) {
    final parts = <String>[];
    void visit(dom.Node node) {
      if (node is dom.Text) {
        final value = node.data.trim();
        if (value.isNotEmpty) parts.add(value);
      } else {
        if (node is dom.Element &&
            const {'script', 'style', 'template'}.contains(node.localName))
          return;
        for (final child in node.nodes) {
          visit(child);
        }
      }
    }

    visit(element);
    return parts.join(); // BeautifulSoup get_text(strip=True), no separator.
  }

  /// Invoke through the coordinator lifecycle barrier when it is integrated.
  /// This method mirrors Python execute_login; it does not serialize mutations.
  Future<Map<String, dynamic>> executeLogin(
    String user,
    String password, {
    bool forceFresh = false,
  }) async {
    await initialize();
    OperationCancellation.current?.check();
    user = user.trim();
    password = password.trim();
    if (user.isEmpty || password.isEmpty) {
      return _fail('NO_CREDENTIALS', 'School ID aur password required hain.');
    }
    rememberCredentials?.call(user, password);
    final clock = Stopwatch()..start();
    if (!forceFresh && activeSchoolId == user) {
      progress?.call(20, 'Checking saved session...');
      if (await probeContext() == SchoolProbe.alive) {
        final node = activeServerBase;
        progress?.call(100, 'Portal live (saved session).');
        return {
          'success': true,
          'cached': true,
          'server_base': node,
          'server_name': node.split('/').last,
          'latency': 0,
          'message': 'Saved session reused.',
        };
      }
    }
    await forgetSavedSession();
    progress?.call(15, 'Selecting fastest Shala Darpan server...');
    final (server, _, _) = await selectFastestServer(progress: progress);
    OperationCancellation.current?.check();
    return _freshHttpLogin(
      user,
      password,
      server.replaceFirst(RegExp(r'/+$'), ''),
      clock,
    );
  }
}
