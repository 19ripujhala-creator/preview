import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../lib/services/core/direct/coordinator.dart';
import '../../lib/services/portals/shaladarpan/direct/auth_manager.dart'
    show SchoolAuthStorage;
import '../../lib/services/portals/rajsims/direct/http_auth.dart';
import '../../lib/services/portals/rajsims/direct/http_context.dart';
import '../../lib/services/portals/rajsims/direct/rajsims_runtime.dart';
import '../../lib/services/portals/rajsims/direct/rajsims_mdm_worker.dart';
import '../../lib/services/portals/rajsims/direct/rajsims_sso_httpx.dart';
import 'rajsso_httpx_test.dart' show loadSsoFixture, ScriptedSsoTransport;

class RajsimsMemoryStorage implements SchoolAuthStorage {
  final values = <String, String>{};
  final writes = <String>[];
  Future<void> Function(String, String)? beforeWrite;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    await beforeWrite?.call(key, value);
    writes.add(key);
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

RajsimsHttpAuth registry(
  RajsimsMemoryStorage storage,
  ScriptedSsoTransport Function() factory, {
  void Function()? clearCache,
}) => RajsimsHttpAuth(
  storage: storage,
  clearWorkerUserInfoCache: clearCache,
  sso: RajssoHttpx(solveCaptcha: (_) => '123456', clientFactory: factory),
);

void saved(RajsimsMemoryStorage storage, String user) {
  storage.values[RajsimsHttpAuth.userKey] = user;
  storage.values[RajsimsHttpAuth.stateKey] = jsonEncode({
    'user': user,
    'cookies': [
      {
        'name': 'sso',
        'value': 'saved',
        'domain': '.rajasthan.gov.in',
        'path': '/',
      },
      {
        'name': 'school',
        'value': 'wrong',
        'domain': 'rajshaladarpan.nic.in',
        'path': '/',
      },
    ],
    'origins': [],
  });
}

void main() {
  final fixture = loadSsoFixture();
  test(
    'unverified response diagnostics survive existing authentication facade',
    () async {
      final store = RajsimsMemoryStorage();
      final transport = ScriptedSsoTransport(
        fixture,
        scenario: 'unverified_signin',
      );
      final auth = registry(store, () => transport);
      final result = await auth.auth.executeLogin(
        'offline-user',
        'offline-password',
      );
      expect(result['success'], false);
      expect(result['code'], 'LOGIN_NOT_VERIFIED');
      expect(
        result['message'],
        'SSO did not confirm login: LOGIN_NOT_VERIFIED',
      );
      expect((result['diagnostics'] as Map)['page'], 'signin');
      expect(transport.credentialPosts, 1);
      expect(store.writes, isEmpty);
      expect(auth.current(), isNull);
    },
  );

  tearDown(RajsimsHttpContext.closeAll);
  test(
    'coordinator used by diagnostic button preserves failure evidence',
    () async {
      final client = ScriptedSsoTransport(
        fixture,
        scenario: 'unverified_signin',
      );
      final auth = registry(RajsimsMemoryStorage(), () => client);
      final coordinator = PortalCoordinator(
        name: 'rajsims',
        backend: RajsimsHttpBackend(auth),
      );
      try {
        final result = await coordinator.authenticate(
          'offline-user',
          'offline-password',
        );
        expect(result['success'], false);
        expect(result['code'], 'LOGIN_NOT_VERIFIED');
        expect((result['diagnostics'] as Map)['http_status'], 200);
        expect(client.credentialPosts, 1);
      } finally {
        await coordinator.shutdown();
      }
    },
  );
  test('effective native SSO and Gateway factories retain original shared User-Agent', () async {
    final login = RajsimsDirectRuntime.createHttpTransport();
    final auth = registry(
      RajsimsMemoryStorage(),
      () => ScriptedSsoTransport(fixture),
    );
    final worker = RajsimsMdmWorker(
      auth: auth.auth,
      currentContext: auth.current,
      clientFactory: RajsimsDirectRuntime.createHttpTransport,
    );
    final gateway =
        worker.adapter.clientFactory() as NativeRajsimsHttpTransport;
    try {
      expect(login.client.defaultHeaders['User-Agent'], rajsimsUserAgent);
      expect(
        gateway.client.defaultHeaders['User-Agent'],
        login.client.defaultHeaders['User-Agent'],
      );
      expect(identical(login.jar, gateway.jar), false);
      expect(gateway.client.defaultHeaders.containsKey('Authkey'), false);
    } finally {
      await login.close();
      await gateway.close();
      await worker.close();
    }
  });
  test('complete auth adopts verified school and persists source cookie/account shape', () async {
    final store = RajsimsMemoryStorage();
    final transport = ScriptedSsoTransport(fixture);
    final auth = registry(store, () => transport);
    final result = await auth.auth.executeLogin(' offline-user ', ' password ');
    expect(result, {
      'success': true,
      'message': 'RajSIMS HTTPX token and school session verified',
      'current_url': 'https://rajsims-mdm.rajasthan.gov.in/',
    });
    expect(result.toString(), isNot(contains('offline-key')));
    expect(auth.auth.getAuth(), ('offline-id', 'offline-key'));
    expect(auth.auth.getUserInfo()['office_id'], 11);
    expect(auth.auth.getUserInfo()['org_id'], 13);
    expect(store.values[RajsimsHttpAuth.userKey], 'offline-user');
    expect(jsonDecode(store.values[RajsimsHttpAuth.stateKey]!), {
      'cookies': [],
      'origins': [],
      'user': 'offline-user',
    });
    expect(store.writes, [RajsimsHttpAuth.stateKey, RajsimsHttpAuth.userKey]);
    expect(transport.credentialPosts, 1);
  });
  test(
    'same saved SSO account verifies dashboard without credential POST',
    () async {
      final store = RajsimsMemoryStorage();
      saved(store, 'offline-user');
      final transport = ScriptedSsoTransport(fixture);
      final auth = registry(store, () => transport);
      expect(
        (await auth.auth.executeLogin('offline-user', 'password'))['success'],
        true,
      );
      expect(transport.calls.first['url'], rajssoDashboard);
      expect(transport.credentialPosts, 0);
      expect(
        transport.jar
            .matching(Uri.parse(rajssoDashboard))
            .any((c) => c.name == 'sso'),
        true,
      );
      expect(
        transport.jar
            .matching(Uri.parse(rajssoDashboard))
            .any((c) => c.name == 'school'),
        false,
      );
    },
  );
  for (final spec in [
    ('different_user', 'different', false),
    ('case_changed', 'Offline-user', false),
    ('force_fresh', 'offline-user', true),
  ]) {
    test('saved account guard: ${spec.$1}', () async {
      final store = RajsimsMemoryStorage();
      saved(store, 'offline-user');
      final transport = ScriptedSsoTransport(fixture);
      final auth = registry(store, () => transport);
      expect(
        (await auth.auth.executeLogin(
          spec.$2,
          'password',
          forceFresh: spec.$3,
        ))['success'],
        true,
      );
      expect(transport.calls.first['url'], rajssoSignin);
      expect(transport.credentialPosts, 1);
      expect(store.values[RajsimsHttpAuth.userKey], spec.$2);
    });
  }
  test(
    'new verified auth closes previous context only after successful bootstrap',
    () async {
      final store = RajsimsMemoryStorage();
      final clients = [
        ScriptedSsoTransport(fixture),
        ScriptedSsoTransport(fixture),
      ];
      final auth = registry(store, () => clients.removeAt(0));
      expect((await auth.auth.executeLogin('u', 'p'))['success'], true);
      final old = auth.current()!;
      expect(
        (await auth.auth.executeLogin('u', 'p', forceFresh: true))['success'],
        true,
      );
      expect(old.closed, true);
      expect(identical(auth.current(), old), false);
      expect(auth.auth.getAuth(old), (null, null));
    },
  );
  test(
    'unverified replacement token retains the previous school context',
    () async {
      final store = RajsimsMemoryStorage();
      final first = ScriptedSsoTransport(fixture),
          next = ScriptedSsoTransport(fixture, scenario: 'token_denied');
      final clients = [first, next];
      final auth = registry(store, () => clients.removeAt(0));
      await auth.auth.executeLogin('u', 'p');
      final old = auth.current();
      final result = await auth.auth.executeLogin('u', 'p', forceFresh: true);
      expect(result['code'], 'TOKEN_NOT_VERIFIED');
      expect(auth.current(), same(old));
      expect(first.closes, 0);
      expect(next.closes, 1);
      expect(auth.auth.getUserInfo()['office_id'], 11);
    },
  );
  test('ambiguous school profile closes both contexts and never persists a new identity', () async {
    final store = RajsimsMemoryStorage();
    final first = ScriptedSsoTransport(fixture);
    final conflicting = Map<String, dynamic>.of(fixture)
      ..['profile'] = {
        'IsSuccess': true,
        'CustomObject': [
          {'OfficeId': 11, 'OrgId': 13},
          {'OfficeId': 12, 'OrgId': 13},
        ],
      };
    final next = ScriptedSsoTransport(conflicting);
    final clients = [first, next];
    var clears = 0;
    final auth = registry(
      store,
      () => clients.removeAt(0),
      clearCache: () {
        clears++;
      },
    );
    await auth.auth.executeLogin('u', 'p');
    final writes = store.writes.length;
    final result = await auth.auth.executeLogin('u', 'p', forceFresh: true);
    expect(result['code'], 'SCHOOL_IDENTITY_NOT_VERIFIED');
    expect(auth.current(), isNull);
    expect(auth.auth.getUserInfo(), isEmpty);
    expect(first.closes, 1);
    expect(next.closes, greaterThanOrEqualTo(1));
    expect(store.writes.length, writes);
    expect(clears, 3);
  });
  test('native login denial keeps original message through complete public wrapper', () async {
    final store = RajsimsMemoryStorage();
    final client = ScriptedSsoTransport(
      fixture,
      scenario: 'credentials_rejected',
    );
    final auth = registry(store, () => client);
    expect(await auth.auth.executeLogin('u', 'p'), {
      'success': false,
      'code': 'INVALID_CREDENTIALS',
      'message': 'Invalid password — मूल संदेश',
      'message_source': 'portal',
    });
    expect(client.credentialPosts, 1);
    expect(client.closes, 1);
    expect(store.writes, isEmpty);
  });
  test(
    'uncertain launch closes candidate and never replays any launch POST',
    () async {
      final store = RajsimsMemoryStorage();
      final client = ScriptedSsoTransport(fixture, scenario: 'launch_timeout');
      final auth = registry(store, () => client);
      final result = await auth.auth.executeLogin('u', 'p');
      expect(result['code'], 'PORTAL_LAUNCH_UNCONFIRMED');
      expect(
        client.calls
            .where(
              (c) =>
                  c['method'] == 'POST' &&
                  Uri.parse(c['url'] as String).path == '/sso',
            )
            .length,
        1,
      );
      expect(auth.current(), isNull);
      expect(client.closes, 1);
      expect(store.writes, isEmpty);
    },
  );
  test('unconfirmed credential timeout never becomes a login success or duplicate POST', () async {
    final store = RajsimsMemoryStorage();
    final client = ScriptedSsoTransport(fixture, scenario: 'timeout_unknown');
    final result = await registry(
      store,
      () => client,
    ).auth.executeLogin('u', 'p');
    expect(result['code'], 'LOGIN_RESULT_UNKNOWN');
    expect(client.credentialPosts, 1);
    expect(store.writes, isEmpty);
    expect(client.closes, 1);
  });
  test('corrupt saved JSON falls back to original fresh SSO login', () async {
    final store = RajsimsMemoryStorage();
    saved(store, 'u');
    store.values[RajsimsHttpAuth.stateKey] = 'broken';
    final client = ScriptedSsoTransport(fixture);
    expect(
      (await registry(
        store,
        () => client,
      ).auth.executeLogin('u', 'p'))['success'],
      true,
    );
    expect(client.calls.first['url'], rajssoSignin);
    expect(client.credentialPosts, 1);
  });
  test(
    'native secure storage failure does not overturn verified successful login',
    () async {
      final store = RajsimsMemoryStorage()
        ..beforeWrite = (_, _) async =>
            throw StateError('secure storage unavailable');
      final client = ScriptedSsoTransport(fixture);
      final auth = registry(store, () => client);
      expect((await auth.auth.executeLogin('u', 'p'))['success'], true);
      expect(auth.auth.getUserInfo()['org_id'], 13);
    },
  );
  test('forget clears only RajSIMS session/state and invalidates worker user cache', () async {
    final store = RajsimsMemoryStorage()..values['school_state'] = 'preserved';
    final client = ScriptedSsoTransport(fixture);
    var clears = 0;
    final auth = registry(
      store,
      () => client,
      clearCache: () {
        clears++;
      },
    );
    await auth.auth.executeLogin('u', 'p');
    await auth.forgetSavedSession();
    expect(auth.current(), isNull);
    expect(auth.auth.getAuth(), (null, null));
    expect(store.values, {'school_state': 'preserved'});
    expect(client.closes, 1);
    expect(clears, 2);
  });
  test('close during late bootstrap cannot adopt an account into a retired registry', () async {
    final store = RajsimsMemoryStorage();
    final client = ScriptedSsoTransport(fixture);
    final entered = Completer<void>(), release = Completer<void>();
    client.handlerHook = (method, url, body, headers) async {
      // Temporarily delegate earlier steps to the real scripted protocol.
      if (url.path.contains('GetSSOlogin')) {
        entered.complete();
        await release.future;
        return client.response(url, data: fixture['profile']);
      }
      final handler = client.handlerHook;
      client.handlerHook = null;
      try {
        return await client.request(
          method,
          url,
          content: body,
          headers: headers,
        );
      } finally {
        client.handlerHook = handler;
      }
    };
    final auth = registry(store, () => client);
    final pending = auth.auth.executeLogin('u', 'p');
    final expectation = expectLater(
      pending,
      throwsA(isA<RajsimsSessionChanged>()),
    );
    await entered.future;
    await auth.closeSession();
    release.complete();
    await expectation;
    expect(auth.current(), isNull);
    expect(store.writes, isEmpty);
    expect(client.closes, 1);
  });
  test('public login lock prevents overlapping client creation and credential dispatch', () async {
    final store = RajsimsMemoryStorage();
    final entered = Completer<void>(), release = Completer<void>();
    final first = ScriptedSsoTransport(fixture);
    first.handlerHook = (method, url, body, headers) async {
      if (method == 'GET' && url.path == '/signin') {
        entered.complete();
        await release.future;
      }
      return first.response(url, text: fixture['form'] as String);
    };
    var creations = 0;
    final auth = registry(store, () {
      creations++;
      return creations == 1 ? first : ScriptedSsoTransport(fixture);
    });
    final a = auth.auth.executeLogin('u', 'p');
    await entered.future;
    final b = auth.auth.executeLogin('u', 'p');
    await Future<void>.delayed(Duration.zero);
    expect(creations, 1);
    // First response deliberately returns the form after credential POST, so
    // it is a definitive unverified login; the second explicit call then runs.
    release.complete();
    expect((await a)['success'], false);
    expect((await b)['success'], true);
    expect(creations, 2);
  });
  test(
    'RajSIMS coordinator reuses live authentication with exact source config',
    () async {
      final store = RajsimsMemoryStorage();
      final client = ScriptedSsoTransport(fixture);
      final auth = registry(store, () => client);
      final backend = RajsimsHttpBackend(auth);
      final coordinator = PortalCoordinator(
        name: 'rajsims',
        backend: backend,
        config: rajsimsCoordinatorConfig,
        displayName: 'RajSIMS Portal',
      );
      try {
        expect((await coordinator.authenticate('u', 'p'))['success'], true);
        final count = client.calls.length;
        final again = await coordinator.authenticate('u', 'p');
        expect(again['cached'], true);
        expect(client.calls.length, count);
        expect(coordinator.health, Health.ready);
        expect(backend.currentContext(), same(auth.current()));
        expect(rajsimsCoordinatorConfig.authTimeout, 90);
        expect(rajsimsCoordinatorConfig.keepaliveInterval, 300);
        expect(rajsimsCoordinatorConfig.recoverCooldown, 60);
        expect(rajsimsCoordinatorConfig.autoRecoveryLimit, 2);
      } finally {
        await coordinator.shutdown();
        await auth.closeSession();
      }
    },
  );
  test(
    'HTTPX binding retains the verified URL token values without cleanup',
    () async {
      final changed = Map<String, dynamic>.of(fixture);
      changed['detail'] = (fixture['detail'] as String)
          .replaceAll('AuthId=offline-id', 'AuthId=%20offline-id%20')
          .replaceAll('AuthKey=offline-key', 'AuthKey=%20offline-key%20');
      final client = ScriptedSsoTransport(changed);
      final auth = registry(RajsimsMemoryStorage(), () => client);
      expect((await auth.auth.executeLogin('u', 'p'))['success'], true);
      expect(auth.auth.getAuth(), (' offline-id ', ' offline-key '));
      final bootstrap = client.calls.last;
      expect(jsonDecode(bootstrap['content'] as String)['ApiParams'], {
        'AuthId': ' offline-id ',
        'AuthKey': ' offline-key ',
      });
    },
  );

  for (final success in [true, false]) {
    test(
      'bootstrap native message reaches public auth result ($success)',
      () async {
        final changed = Map<String, dynamic>.of(fixture);
        changed['profile'] = {
          'IsSuccess': success,
          'Message': ' मूल पोर्टल संदेश ',
          'CustomObject': {'OfficeId': 11, 'OrgId': 13},
        };
        final client = ScriptedSsoTransport(changed);
        final auth = registry(RajsimsMemoryStorage(), () => client);
        final result = await auth.auth.executeLogin('u', 'p');
        expect(result['success'], success);
        expect(result['message'], ' मूल पोर्टल संदेश ');
        expect(result['message_source'], 'portal');
        if (!success) expect(result['code'], 'TOKEN_NOT_VERIFIED');
      },
    );
  }

  for (final owner in ['other-account', null]) {
    test(
      'mixed or unowned saved cookies never adopt an account ($owner)',
      () async {
        final store = RajsimsMemoryStorage();
        saved(store, 'u');
        final state =
            jsonDecode(store.values[RajsimsHttpAuth.stateKey]!) as Map;
        if (owner == null) {
          state.remove('user');
        } else {
          state['user'] = owner;
        }
        store.values[RajsimsHttpAuth.stateKey] = jsonEncode(state);
        final client = ScriptedSsoTransport(fixture);
        final auth = registry(store, () => client);
        expect((await auth.auth.executeLogin('u', 'p'))['success'], true);
        expect(client.calls.first['url'], rajssoSignin);
        expect(client.credentialPosts, 1);
        expect(await auth.current()!.storageState(), {
          'cookies': [],
          'origins': [],
        });
      },
    );
  }

  test('actual body Status interpretation excludes booleans, fractional and unrelated fields', () {
    expect(rajsimsBodyStatusCode({'Status': ' 401 '}), 401);
    expect(rajsimsBodyStatusCode({'Status': 403}), 403);
    for (final value in [true, 401.0, '401.0', 99, 600, null]) {
      expect(rajsimsBodyStatusCode({'Status': value}), isNull);
    }
    expect(rajsimsBodyStatusCode({'StatusCode': 401}), isNull);
  });
}
