import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../lib/services/core/direct/coordinator.dart';
import '../../lib/services/portals/shaladarpan/direct/auth_manager.dart'
    show SchoolAuthStorage;
import '../../lib/services/portals/shaladarpan/direct/school_http.dart';
import '../../lib/services/portals/staff_login/direct/auth_manager.dart';
import '../../lib/services/portals/staff_login/direct/http_auth.dart';
import '../../lib/services/portals/staff_login/direct/http_login.dart';
import '../../lib/services/portals/staff_login/direct/http_session.dart';
import '../../lib/services/portals/staff_login/direct/server_manager.dart';
import '../../lib/services/portals/staff_login/direct/staff_runtime.dart'
    show StaffCoordinator, StaffHttpBackend;

const staffTestBase = 'https://rajshaladarpan.rajasthan.gov.in/SD4';
const staffTestForm = '''<form action="stafflogin.aspx"><input name="__VIEWSTATE" value="view&amp;state">
<input name="__EVENTVALIDATION" value="ev"><input name="hdnfld" value="nonce42" type="hidden">
<input id="txt_Username" name="actual-user"><input id="txtUPNswd" name="txtUPNswd" type="password">
<input id="txt_Captchaname" name="actual-captcha"><img id="Img2" src="captcha.aspx">
<input id="btn_StaffLogin" name="actual-submit" type="submit" value="Login">
<input type="submit" name="other-submit" value="NO"><input type="checkbox" name="unchecked">
<input type="checkbox" name="checked" checked value="Y"></form>''';
SchoolHttpReply staffReply(
  String path,
  String text, {
  int status = 200,
  Map<String, List<String>> headers = const {},
}) => SchoolHttpReply(
  Uri.parse(path.startsWith('https:') ? path : '$staffTestBase$path'),
  status,
  Uint8List.fromList(utf8.encode(text)),
  headers,
);
SchoolHttpReply staffLiveHome() =>
    staffReply(staffHomePath, '<a id="lnkLogout"></a>');

class StaffMemoryStorage implements SchoolAuthStorage {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class StaffFakeTransport implements StaffTransport {
  StaffFakeTransport([List<SchoolHttpReply> replies = const []])
    : replies = List.of(replies);
  final List<SchoolHttpReply> replies;
  final requests = <Map<String, Object?>>[];
  bool closed = false;
  Future<SchoolHttpReply> Function(Map<String, Object?>)? handler;
  @override
  final jar = SchoolCookieJar();
  Future<SchoolHttpReply> _request(Map<String, Object?> request) async {
    requests.add(request);
    if (handler != null) return handler!(request);
    if (replies.isEmpty) throw StateError('Unplanned offline request');
    return replies.removeAt(0);
  }

  @override
  Future<SchoolHttpReply> get(
    String url, {
    Map<String, String> headers = const {},
    Duration? timeout,
    bool followRedirects = true,
  }) => _request({
    'method': 'GET',
    'followRedirects': followRedirects,
    'url': url,
    'headers': headers,
    'timeout': timeout,
  });
  @override
  Future<SchoolHttpReply> post(
    String url, {
    Map<String, String>? data,
    String? content,
    Map<String, String> headers = const {},
    bool followRedirects = true,
  }) => _request({
    'method': 'POST',
    'followRedirects': followRedirects,
    'url': url,
    'headers': headers,
    'data': data,
    'content': content,
  });
  @override
  void close() {
    closed = true;
  }
}

class StaffDelayedStorage extends StaffMemoryStorage {
  final readStarted = Completer<void>();
  final readResult = Completer<String?>();
  @override
  Future<String?> read(String key) async {
    if (!readStarted.isCompleted) readStarted.complete();
    return readResult.future;
  }
}

class StaffFixedServers extends StaffServerManager {
  final penalized = <String>[];
  @override
  Future<(String, String, int)> selectFastestServer() async =>
      (staffTestBase, 'SD4', 12);
  @override
  void penalizeNode(String url) {
    penalized.add(url);
  }
}

void main() {
  final goldens = jsonDecode(
    File('test/direct/fixtures/python_staff_auth.json').readAsStringSync(),
  ) as Map;
  for (final raw in goldens['passwords'] as List) {
    final row = raw as Map;
    test('Python Staff password fields ${row['user']}/${row['login_id']}', () {
      expect(
        staffPasswordFields(
          row['user'],
          row['password'],
          row['login_id'],
          row['nonce'],
        ),
        row['fields'],
      );
    });
  }
  for (final raw in goldens['documents'] as List) {
    final row = raw as Map, doc = row['document'] as Map;
    test('Python Staff document evidence ${row['name']}', () {
      final record = (
        url: doc['url'] as String,
        status: doc['status'] as int,
        text: doc['text'] as String,
      );
      expect(StaffAuthManager.classifyHome(record).name, row['home']);
      expect(
        StaffAuthManager.classifyProfileDocument(record).name,
        row['profile'],
      );
      expect(
        StaffAuthManager.classifyHistoryDocument(record).name,
        row['history'],
      );
    });
  }
  var noticeIndex = 0;
  for (final row in goldens['notices'] as List) {
    test(
      'Python Staff original notice ${noticeIndex++}',
      () => expect(staffPortalNotice(row['html']), row['notice']),
    );
  }
  test(
    'Staff nonce/form payload uses actual offered field names and controls',
    () {
      final form = parseStaffLoginForm(
        staffTestBase,
        staffTestForm,
        '$staffTestBase$staffLoginPath',
      );
      expect(form.fields['__VIEWSTATE'], 'view&state');
      expect(form.fields['checked'], 'Y');
      expect(form.fields.containsKey('unchecked'), isFalse);
      expect(form.fields.containsKey('other-submit'), isFalse);
      expect(form.userName, 'actual-user');
      expect(form.captchaName, 'actual-captcha');
      expect(form.captchaUrl, '$staffTestBase/Home/staff/captcha.aspx');
    },
  );
  for (final url in [
    'http://rajshaladarpan.rajasthan.gov.in/SD4',
    'https://example.com/SD4',
    'https://rajshaladarpan.rajasthan.gov.in/SD6',
    'https://rajshaladarpan.rajasthan.gov.in:443/SD4',
  ]) {
    test(
      'Staff rejects unexpected node $url',
      () => expect(() => staffNodeBase(url), throwsA(isA<StaffHttpError>())),
    );
  }
  test(
    'Staff case-normalizes a valid node',
    () => expect(
      staffNodeBase('https://$staffHost/sd4/Home/Staff/x.aspx'),
      staffTestBase,
    ),
  );
  test(
    'Staff form cannot reference a different node',
    () => expect(
      () => parseStaffLoginForm(
        staffTestBase,
        staffTestForm.replaceFirst('captcha.aspx', '/SD1/captcha.aspx'),
        '$staffTestBase$staffLoginPath',
      ),
      throwsA(isA<StaffHttpError>()),
    ),
  );
  test(
    'Staff controls must belong to one original form',
    () => expect(
      () => parseStaffLoginForm(
        staffTestBase,
        staffTestForm.replaceFirst(
          '<input id="txtUPNswd"',
          '</form><form><input id="txtUPNswd"',
        ),
        '$staffTestBase$staffLoginPath',
      ),
      throwsA(isA<StaffHttpError>()),
    ),
  );
  test(
    'single Staff login preserves original request order and password payload',
    () async {
      final client = StaffFakeTransport([
        staffReply(staffLoginPath, staffTestForm),
        staffReply(
          '/Home/staff/About.aspx/getStaff_Userid',
          '{"d":"staff-login"}',
        ),
        staffReply(
          '/Home/staff/captcha.aspx',
          'png',
          headers: {
            'content-type': ['image/png'],
          },
        ),
        staffReply(
          staffLoginPath,
          '<script>location="StaffHome.aspx";</script>',
        ),
        staffLiveHome(),
      ]);
      final session = StaffHttpSession(client: client);
      final result = await staffLoginOnce(
        session,
        staffTestBase,
        ' 1234567 ',
        'TestPassword!',
        (bytes) => '1234',
      );
      expect(result.success, isTrue);
      expect(session.authenticated, isTrue);
      expect(session.user, '1234567');
      expect(client.requests.map((r) => r['method']), [
        'GET',
        'POST',
        'GET',
        'POST',
        'GET',
      ]);
      expect(jsonDecode(client.requests[1]['content'] as String), {
        'Userid': '1234567',
      });
      final payload = client.requests[3]['data'] as Map;
      for (final entry
          in (goldens['passwords'] as List).first['fields'].entries) {
        expect(payload[entry.key], entry.value);
      }
      expect(payload['actual-user'], '1234567');
      expect(payload['actual-captcha'], '1234');
      expect(payload['actual-submit'], 'Login');
      expect(client.requests.where((r) => r['method'] == 'POST').length, 2);
      await session.close();
    },
  );
  test(
    'Staff submit directly returning Home needs no duplicate Home GET',
    () async {
      final client = StaffFakeTransport([
        staffReply(staffLoginPath, staffTestForm),
        staffReply('/Home/staff/About.aspx/getStaff_Userid', '{"d":42}'),
        staffReply(
          '/Home/staff/captcha.aspx',
          'png',
          headers: {
            'content-type': ['image/png'],
          },
        ),
        staffLiveHome(),
      ]);
      final session = StaffHttpSession(client: client);
      expect(
        (await staffLoginOnce(
          session,
          staffTestBase,
          '1234567',
          'pw',
          (_) => '1234',
        )).success,
        isTrue,
      );
      expect(client.requests.length, 4);
      await session.close();
    },
  );
  test(
    'uncertain submitted login is never blindly replayed by login_once',
    () async {
      final client = StaffFakeTransport([
        staffReply(staffLoginPath, staffTestForm),
        staffReply('/Home/staff/About.aspx/getStaff_Userid', '{"d":42}'),
        staffReply(
          '/Home/staff/captcha.aspx',
          'png',
          headers: {
            'content-type': ['image/png'],
          },
        ),
        staffReply(
          staffLoginPath,
          '<script>alert("Original notice");</script>',
        ),
        staffReply(staffHomePath, ''),
      ]);
      final session = StaffHttpSession(client: client);
      final result = await staffLoginOnce(
        session,
        staffTestBase,
        '1234567',
        'pw',
        (_) => '1234',
      );
      expect(result.success, isFalse);
      expect(result.portalMessage, 'Original notice');
      expect(client.requests.where((r) => r['data'] != null).length, 1);
      await session.close();
    },
  );
  test('unreadable CAPTCHA stops before credentials are submitted', () async {
    final client = StaffFakeTransport([
      staffReply(staffLoginPath, staffTestForm),
      staffReply('/Home/staff/About.aspx/getStaff_Userid', '{"d":42}'),
      staffReply(
        '/Home/staff/captcha.aspx',
        'png',
        headers: {
          'content-type': ['image/png'],
        },
      ),
    ]);
    final session = StaffHttpSession(client: client);
    expect(
      (await staffLoginOnce(
        session,
        staffTestBase,
        '1234567',
        'pw',
        (_) => '',
      )).code,
      'CAPTCHA_UNREADABLE',
    );
    expect(client.requests.where((r) => r['data'] != null), isEmpty);
    await session.close();
  });
  for (final bad in ['{}', '{"d":null}', '{"d":[]}', '{"d":""}']) {
    test(
      'Staff rejects changed user-ID lookup $bad',
      () => expect(
        () => staffAjaxUserId(staffReply(staffLoginPath, bad)),
        throwsA(isA<StaffHttpError>()),
      ),
    );
  }
  test('Staff AJAX keeps Python numeric/boolean result semantics', () {
    expect(staffAjaxUserId(staffReply(staffLoginPath, '{"d":0}')), '0');
    expect(staffAjaxUserId(staffReply(staffLoginPath, '{"d":true}')), 'True');
  });
  test(
    'Staff cookie storage preserves paths and excludes School jar',
    () async {
      final storage = StaffMemoryStorage();
      final transport = StaffFakeTransport();
      final session = StaffHttpSession(client: transport)
        ..base = staffTestBase
        ..user = '1234567'
        ..authenticated = true;
      transport.jar.receive([
        Cookie('ASP.NET_SessionId', 'staff')
          ..domain = staffHost
          ..path = '/SD4',
      ], Uri.parse(staffTestBase));
      transport.jar.receive([
        Cookie('ASP.NET_SessionId', 'root')
          ..domain = staffHost
          ..path = '/',
      ], Uri.parse(staffTestBase));
      final school = SchoolCookieJar();
      school.receive([
        Cookie('ASP.NET_SessionId', 'school'),
      ], Uri.parse(staffTestBase));
      final registry = StaffHttpAuth(storage: storage);
      await registry.install(session);
      final restoredTransport = StaffFakeTransport();
      final restored = StaffHttpAuth(
        storage: storage,
        sessionFactory: () => StaffHttpSession(client: restoredTransport),
      );
      await restored.initialize();
      expect(restored.current()!.user, '1234567');
      expect(restored.current()!.base, staffTestBase);
      expect(
        restoredTransport.jar
            .matching(Uri.parse('$staffTestBase/Home/Staff/x'))
            .map((c) => c.value),
        ['staff', 'root'],
      );
      expect(school.matching(Uri.parse(staffTestBase)).single.value, 'school');
      expect(
        storage.values[StaffHttpAuth.cookieKey],
        isNot(contains('password')),
      );
      await restored.closeSession();
      await registry.closeSession();
    },
  );
  test('Staff browser cookie bridge retains metadata and only rotates official-host cookies', () {
    final transport = StaffFakeTransport(),
        session = StaffHttpSession(client: StaffFakeTransport());
    final registry = StaffHttpAuth(storage: StaffMemoryStorage());
    session.client.jar.receive(
      [
        Cookie('c', 'old')
          ..domain = staffHost
          ..path = '/'
          ..httpOnly = true,
      ],
      Uri.parse(staffTestBase),
      rawHeaders: ['c=old; Domain=$staffHost; Path=/; HttpOnly; SameSite=Lax'],
    );
    expect(registry.browserCookies(session).single['sameSite'], 'Lax');
    expect(registry.browserCookies(session).single['httpOnly'], isTrue);
    expect(registry.browserCookies(session).single['secure'], isTrue);
    expect(
      registry.syncFromBrowser(session, [
        {'name': 'c', 'value': 'bad', 'domain': 'other.test', 'path': '/'},
      ]),
      isFalse,
    );
    expect(
      registry.syncFromBrowser(session, [
        {'name': 'c', 'value': 'new', 'domain': '.$staffHost', 'path': '/'},
      ]),
      isTrue,
    );
    expect(
      registry.syncFromBrowser(session, [
        {'name': 'c', 'value': 'new', 'domain': staffHost, 'path': '/'},
      ]),
      isFalse,
    );
    transport.close();
    session.client.close();
  });
  test(
    'all Staff resource leases are serialized by coordinator ownership',
    () async {
      final storage = StaffMemoryStorage(), transport = StaffFakeTransport();
      final session = StaffHttpSession(client: transport)
        ..base = staffTestBase
        ..user = '1234567'
        ..authenticated = true;
      final registry = StaffHttpAuth(storage: storage);
      await registry.install(session);
      transport.handler = (_) => Future.value(staffLiveHome());
      final auth = StaffAuthManager(
        registry: registry,
        solveCaptcha: (_) => '1234',
      );
      final coordinator = StaffCoordinator(backend: StaffHttpBackend(auth));
      final gate = Completer<void>(), entered = Completer<void>();
      final order = <String>[];
      final first = coordinator.run(
        resource: 'staff.home',
        kind: Kind.read,
        worker: (_) async {
          order.add('home');
          entered.complete();
          await gate.future;
          return {'success': true};
        },
      );
      await entered.future;
      final second = coordinator.run(
        resource: 'staff.leave.history',
        kind: Kind.read,
        worker: (_) async {
          order.add('history');
          return {'success': true};
        },
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(order, ['home']);
      gate.complete();
      await Future.wait([first, second]);
      expect(order, ['home', 'history']);
      await coordinator.shutdown();
      await registry.closeSession();
    },
  );

  test(
    'Staff source five-minute node penalty expires without premature ping',
    () async {
      var now = DateTime(2026, 10, 11);
      final client = StaffFakeTransport([
        staffReply(staffLoginPath, 'down', status: 503),
      ]);
      final servers = StaffServerManager(
        now: () => now,
        clientFactory: () => client,
      );
      servers.penalizeNode(staffTestBase);
      expect(
        (await servers.pingAndVerifyNode(client, staffTestBase))['latency'],
        99999,
      );
      expect(client.requests, isEmpty);
      now = now.add(const Duration(minutes: 5));
      await servers.pingAndVerifyNode(client, staffTestBase);
      expect(client.requests.length, 1);
      client.close();
    },
  );
  test(
    'Staff source all-down selector falls back to SD4 and closes ping client',
    () async {
      final client = StaffFakeTransport();
      client.handler = (_) =>
          Future.value(staffReply(staffLoginPath, 'down', status: 503));
      final servers = StaffServerManager(clientFactory: () => client);
      expect(await servers.selectFastestServer(), (staffTestBase, 'SD4', 0));
      expect(client.requests.length, 5);
      expect(client.closed, isTrue);
    },
  );
  test(
    'corrupted persisted Staff cookies are ignored without authentication',
    () async {
      final storage = StaffMemoryStorage()
        ..values[StaffHttpAuth.cookieKey] = '{broken';
      final registry = StaffHttpAuth(storage: storage);
      await registry.initialize();
      expect(registry.current(), isNull);
    },
  );
  test('Staff transport-level tri-state probe distinguishes login from unknown page', () async {
    final client = StaffFakeTransport([
      staffReply(staffHomePath, 'unavailable', status: 503),
      staffReply(staffLoginPath, staffTestForm),
      staffLiveHome(),
    ]);
    final session = StaffHttpSession(client: client)
      ..base = staffTestBase
      ..authenticated = true;
    expect(await session.probeStatus(), SessionProbe.unknown);
    expect(await session.probeStatus(), SessionProbe.dead);
    expect(await session.probeStatus(), SessionProbe.alive);
    await session.close();
  });
  test('Staff adopt requires positive original Home proof', () async {
    final session = StaffHttpSession(client: StaffFakeTransport());
    await expectLater(
      session.adoptVerified(
        staffTestBase,
        '1234567',
        staffReply(staffHomePath, 'generic 200'),
      ),
      throwsA(isA<StaffHttpError>()),
    );
    expect(session.authenticated, isFalse);
    await session.adoptVerified(staffTestBase, '1234567', staffLiveHome());
    expect(session.authenticated, isTrue);
    await session.close();
  });
  for (final action in ['install', 'forget']) {
    test(
      'async cookie restore cannot replace newer $action ownership',
      () async {
        final storage = StaffDelayedStorage();
        final candidates = <StaffFakeTransport>[];
        final registry = StaffHttpAuth(
          storage: storage,
          sessionFactory: () {
            final client = StaffFakeTransport();
            candidates.add(client);
            return StaffHttpSession(client: client);
          },
        );
        final pending = registry.initialize();
        await storage.readStarted.future;
        final newer = StaffHttpSession(client: StaffFakeTransport())
          ..base = staffTestBase
          ..user = '7654321'
          ..authenticated = true;
        if (action == 'install') {
          await registry.install(newer);
        } else {
          await registry.forget();
        }
        storage.readResult.complete(
          jsonEncode({
            'base': staffTestBase,
            'user': '1234567',
            'cookies': [
              {'name': 'c', 'value': 'old', 'path': '/'},
            ],
          }),
        );
        await pending;
        expect(registry.current(), action == 'install' ? same(newer) : isNull);
        expect(candidates.every((c) => c.closed), isTrue);
        await registry.closeSession();
        await newer.close();
      },
    );
  }
  group('complete Staff auth manager', () {
    late StaffMemoryStorage storage;
    late StaffHttpAuth registry;
    late StaffFixedServers servers;
    late StaffAuthManager auth;
    late List<StaffFakeTransport> transports;
    late int attempts;
    late StaffLoginAttempt attempt;
    setUp(() {
      storage = StaffMemoryStorage();
      transports = [];
      attempts = 0;
      servers = StaffFixedServers();
      registry = StaffHttpAuth(
        storage: storage,
        sessionFactory: () {
          final t = StaffFakeTransport();
          transports.add(t);
          return StaffHttpSession(client: t);
        },
      );
      attempt = (session, base, user, password, solve) async {
        attempts++;
        session.base = base;
        session.user = user;
        session.authenticated = true;
        return const StaffLoginOutcome(
          true,
          'AUTHENTICATED',
          'Staff session verified.',
        );
      };
      auth = StaffAuthManager(
        registry: registry,
        solveCaptcha: (_) => '1234',
        servers: servers,
        loginOnce: (s, b, u, p, c) => attempt(s, b, u, p, c),
        sleep: (_) async {},
      );
    });
    test('session replacement during protected read cannot validate old generation', () async {
      await auth.initialize();
      final client = StaffFakeTransport();
      final session = StaffHttpSession(client: client)
        ..base = staffTestBase
        ..user = '1234567'
        ..authenticated = true;
      await registry.install(session);
      client.handler = (_) async {
        final replacement = registry.newSession()
          ..base = staffTestBase
          ..user = '7654321'
          ..authenticated = true;
        await registry.install(replacement);
        return staffLiveHome();
      };
      expect(await auth.probeContext(session), Probe.unknown);
      expect(registry.current()!.user, '7654321');
      expect(client.closed, isTrue);
    });
    test(
      'source login budget expires before another CAPTCHA/session attempt',
      () async {
        var clock = 0.0;
        final timed = StaffAuthManager(
          registry: registry,
          solveCaptcha: (_) => '1234',
          servers: servers,
          monotonic: () => clock,
          loginOnce: (s, b, u, p, c) async {
            attempts++;
            clock = 121;
            return const StaffLoginOutcome(
              false,
              'CAPTCHA_UNREADABLE',
              'Unreadable',
            );
          },
          sleep: (_) async {},
        );
        expect((await timed.executeLogin('1234567', 'pw'))['code'], 'TIMEOUT');
        expect(attempts, 1);
        expect(transports.every((t) => t.closed), isTrue);
      },
    );
    test('empty Staff credentials reject before creating session', () async {
      expect((await auth.executeLogin('', 'pw'))['code'], 'NO_CREDENTIALS');
      expect(
        (await auth.executeLogin('1234567', '  '))['code'],
        'NO_CREDENTIALS',
      );
      expect(attempts, 0);
      expect(transports, isEmpty);
    });
    tearDown(() async {
      await registry.closeSession();
    });
    Future<StaffHttpSession> saved(List<SchoolHttpReply> replies) async {
      await auth.initialize();
      final t = StaffFakeTransport(replies);
      transports.add(t);
      final s = StaffHttpSession(client: t)
        ..base = staffTestBase
        ..user = '1234567'
        ..authenticated = true;
      await registry.install(s);
      await auth.saveActiveSessionInfo(staffTestBase, '1234567');
      return s;
    }

    test(
      'saved live Staff session reused with no CAPTCHA or new login',
      () async {
        await saved([staffLiveHome()]);
        expect((await auth.executeLogin('1234567', 'pw'))['cached'], isTrue);
        expect(attempts, 0);
      },
    );
    test(
      'temporary Home outage returns SESSION_UNCERTAIN without relogin',
      () async {
        final s = await saved([
          staffReply(staffHomePath, 'maintenance', status: 503),
        ]);
        expect(
          (await auth.executeLogin('1234567', 'pw'))['code'],
          'SESSION_UNCERTAIN',
        );
        expect(attempts, 0);
        expect(registry.current(), same(s));
      },
    );
    test(
      'saved explicit login document expires and allows one fresh login',
      () async {
        final s = await saved([staffReply(staffLoginPath, staffTestForm)]);
        expect((await auth.executeLogin('1234567', 'pw'))['cached'], isFalse);
        expect(attempts, 1);
        expect((s.client as StaffFakeTransport).closed, isTrue);
      },
    );
    test('saved other account is forgotten before fresh login', () async {
      final s = await saved([]);
      expect((await auth.executeLogin('7654321', 'pw'))['username'], '7654321');
      expect(attempts, 1);
      expect((s.client as StaffFakeTransport).requests, isEmpty);
    });
    test('force fresh avoids probing saved session', () async {
      final s = await saved([]);
      expect(
        (await auth.executeLogin('1234567', 'pw', forceFresh: true))['cached'],
        isFalse,
      );
      expect((s.client as StaffFakeTransport).requests, isEmpty);
    });
    test('CAPTCHA has exactly eight fresh-session attempts and no committed session', () async {
      attempt = (s, b, u, p, c) async {
        attempts++;
        return const StaffLoginOutcome(
          false,
          'LOGIN_NOT_VERIFIED',
          'Invalid CAPTCHA',
          'Invalid CAPTCHA',
        );
      };
      expect(
        (await auth.executeLogin('1234567', 'pw'))['code'],
        'LOGIN_FAILED',
      );
      expect(attempts, 8);
      expect(registry.current(), isNull);
      expect(transports.every((t) => t.closed), isTrue);
    });
    test('dead node does not consume CAPTCHA attempt and selected node order is retained', () async {
      final nodes = <String>[];
      attempt = (s, b, u, p, c) async {
        attempts++;
        nodes.add(b);
        if (attempts == 1)
          throw const StaffHttpError('LOGIN_FORM_CHANGED', 'Unavailable');
        s.base = b;
        s.user = u;
        s.authenticated = true;
        return const StaffLoginOutcome(true, 'AUTHENTICATED', 'ok');
      };
      final result = await auth.executeLogin('1234567', 'pw');
      expect(result['server_name'], 'SD1');
      expect(nodes, [staffTestBase, staffServers[1]]);
      expect(servers.penalized, [staffTestBase]);
    });
    test('all five unusable nodes stop instead of repeating a node', () async {
      attempt = (s, b, u, p, c) async {
        attempts++;
        throw const StaffHttpError('PORTAL_UNAVAILABLE', 'down');
      };
      expect((await auth.executeLogin('1234567', 'pw'))['code'], 'PORTAL_DOWN');
      expect(attempts, 5);
      expect(servers.penalized, staffServers);
    });
    test(
      'credential rejection matches Python code/message and is not retried',
      () async {
        attempt = (s, b, u, p, c) async {
          attempts++;
          return const StaffLoginOutcome(
            false,
            'LOGIN_NOT_VERIFIED',
            'Invalid username',
          );
        };
        expect(await auth.executeLogin('1234567', 'pw'), {
          'success': false,
          'code': 'INVALID_CREDENTIALS',
          'message': 'Invalid Staff ID or Password.',
        });
        expect(attempts, 1);
      },
    );
    test('active-session notice remains original and never guesses terminate postback', () async {
      attempt = (s, b, u, p, c) async {
        attempts++;
        return const StaffLoginOutcome(
          false,
          'LOGIN_NOT_VERIFIED',
          'Already logged in on another device',
        );
      };
      final result = await auth.executeLogin('1234567', 'pw');
      expect(result['code'], 'ACTIVE_SESSION_EXISTS');
      expect(result['message'], 'Already logged in on another device');
      expect(attempts, 1);
    });
    test('protected Profile proves ALIVE despite Home failure', () async {
      final s = await saved([
        staffReply(staffHomePath, 'Server Error in', status: 500),
        staffReply(
          StaffAuthManager.profilePath,
          '<input id="ContentPlaceHolder1_ImageButton18"><input name="__VIEWSTATE" value="v">',
        ),
      ]);
      expect(await auth.probeContext(s), Probe.alive);
      expect((s.client as StaffFakeTransport).requests.length, 2);
    });
    test(
      'protected History proves ALIVE despite Home/Profile failure',
      () async {
        final s = await saved([
          staffReply(staffHomePath, '', status: 500),
          staffReply(StaffAuthManager.profilePath, '', status: 500),
          staffReply(
            StaffAuthManager.historyPath,
            '<input name="__VIEWSTATE" value="v"><table id="grdLeaveDetails"><tr><td>No records found</td></tr></table>',
          ),
        ]);
        expect(await auth.probeContext(s), Probe.alive);
        expect((s.client as StaffFakeTransport).requests.length, 3);
      },
    );
    test('two independent protected login redirects prove DEAD despite Home server error', () async {
      final s = await saved([
        staffReply(staffHomePath, '', status: 500),
        staffReply(staffLoginPath, staffTestForm),
        staffReply(staffLoginPath, staffTestForm),
      ]);
      expect(await auth.probeContext(s), Probe.dead);
    });
    test(
      'three same-node protected null-state errors request bounded repair',
      () async {
        const error = 'Server Error in System.NullReferenceException';
        final s = await saved([
          staffReply(staffHomePath, error, status: 500),
          staffReply(StaffAuthManager.profilePath, error, status: 500),
          staffReply(StaffAuthManager.historyPath, error, status: 500),
        ]);
        expect(await auth.probeContext(s), Probe.repairRequired);
      },
    );
    test('generic maintenance never establishes repair or expiry', () async {
      final s = await saved([
        staffReply(staffHomePath, 'maintenance', status: 503),
        staffReply(StaffAuthManager.profilePath, 'maintenance', status: 503),
        staffReply(StaffAuthManager.historyPath, 'maintenance', status: 503),
      ]);
      expect(await auth.probeContext(s), Probe.unknown);
    });
    test(
      'explicitly invalidated current session is DEAD without network',
      () async {
        final s = await saved([]);
        registry.invalidate(s);
        expect(await auth.probeContext(s), Probe.dead);
        expect((s.client as StaffFakeTransport).requests, isEmpty);
      },
    );
  });
}
