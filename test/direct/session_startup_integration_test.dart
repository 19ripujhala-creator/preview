import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../lib/services/core/direct/async_primitives.dart';
import '../../lib/services/core/direct/coordinator.dart';
import '../../lib/services/core/direct/coordinator_config.dart';
import '../../lib/services/core/direct/errors.dart';
import '../../lib/services/portals/shaladarpan/direct/auth_manager.dart';
import '../../lib/services/portals/shaladarpan/direct/school_runtime.dart';
import '../../lib/services/portals/staff_login/direct/auth_manager.dart';
import '../../lib/services/portals/staff_login/direct/http_auth.dart';
import '../../lib/services/portals/staff_login/direct/http_session.dart';
import '../../lib/services/portals/staff_login/direct/staff_runtime.dart'
    show StaffCoordinator, StaffHttpBackend;
import '../../lib/services/portals/rajsims/direct/rajsims_runtime.dart'
    show RajsimsHttpBackend;
import 'school_error_document_cases.dart' show SchoolAuthHttpFixture;
import 'staff_auth_test.dart'
    show
        StaffMemoryStorage,
        StaffFakeTransport,
        StaffFixedServers,
        staffReply,
        staffLiveHome,
        staffTestForm,
        staffTestBase;
import 'rajsims_http_auth_test.dart' as raj;
import 'rajsso_httpx_test.dart' show ScriptedSsoTransport, loadSsoFixture;

Future<void> _school(
  SchoolAuthHttpFixture f,
  Future<void> Function(SchoolAuthManager, PortalCoordinator) body,
) async {
  PortalCoordinator? co;
  f.rememberCredentials = (user, password) =>
      co?.rememberCredentials(user, password);
  await f.run((auth) async {
    co = PortalCoordinator(name: 'sd', backend: SchoolHttpBackend(auth));
    try {
      await body(auth, co!);
    } finally {
      await co!.shutdown();
    }
  });
}

class _Staff {
  _Staff({this.home = '<a id="lnkLogout">Logout</a>', this.status = 200});
  final String home;
  final int status;
  final storage = StaffMemoryStorage(),
      clients = <StaffFakeTransport>[],
      sessions = <StaffHttpSession>[];
  late final registry = StaffHttpAuth(
    storage: storage,
    sessionFactory: () {
      final index = clients.length;
      late StaffFakeTransport client;
      client = StaffFakeTransport()
        ..handler = (request) async {
          final url = request['url'] as String,
              path = Uri.parse(url).path.toLowerCase();
          if (index == 0) return staffReply(url, home, status: status);
          if (path.endsWith('/about.aspx/getstaff_userid'))
            return staffReply(url, '{"d":"staff-login"}');
          if (path.endsWith('/captcha.aspx'))
            return staffReply(
              url,
              'png',
              headers: {
                'content-type': ['image/png'],
              },
            );
          if (request['data'] != null) {
            client.jar.receive([
              Cookie('ASP.NET_SessionId', 'new-staff-cookie')..path = '/',
            ], Uri.parse(staffTestBase));
            return staffLiveHome();
          }
          return staffReply(url, staffTestForm);
        };
      clients.add(client);
      final session = StaffHttpSession(client: client);
      sessions.add(session);
      return session;
    },
  );
  late final auth = StaffAuthManager(
    registry: registry,
    solveCaptcha: (_) => '1234',
    servers: StaffFixedServers(),
    sleep: (_) async {},
  );
  StaffCoordinator? co;
  int get posts => clients.fold(
    0,
    (n, c) => n + c.requests.where((r) => r['data'] != null).length,
  );
  Future<void> run(Future<void> Function(StaffCoordinator) body) async {
    storage.values[StaffHttpAuth.cookieKey] = jsonEncode({
      'base': staffTestBase,
      'user': '1234567',
      'cookies': [
        {
          'name': 'ASP.NET_SessionId',
          'value': 'old-staff-cookie',
          'domain': staffHost,
          'path': '/',
        },
      ],
    });
    await auth.initialize();
    co = StaffCoordinator(backend: StaffHttpBackend(auth));
    try {
      await body(co!);
    } finally {
      await co!.shutdown();
      await registry.closeSession();
      for (final s in sessions) {
        await s.close();
      }
    }
  }
}

class _Backend implements PortalBackend {
  Object? context = Object();
  final calls = <String>[];
  bool reject = false;
  @override
  Object? currentContext() => context;
  @override
  Future<Probe> probe(Object context) async => Probe.alive;
  @override
  Future<Map<String, dynamic>> authenticate(
    String user,
    String password,
    bool fresh,
  ) async {
    calls.add(user);
    if (reject)
      return {
        'success': false,
        'code': 'NETWORK_ERROR',
        'message': 'Offline unavailable',
      };
    context = Object();
    return {'success': true};
  }
}

void main() {
  test('cold School restore through coordinator reuses verified cookies without CAPTCHA', () async {
    final f = SchoolAuthHttpFixture(
      saved: true,
      home: '<a id="logout">Logout</a>',
    );
    await _school(f, (auth, co) async {
      final original = auth.sessionIdentity;
      final result = await co.authenticate('123456', 'password');
      expect(result['success'], true);
      expect(result['cached'], true);
      expect(f.credentialPosts, 0);
      expect(f.solved, 0);
      expect(f.homeReads, 1);
      expect(auth.sessionIdentity, original);
      expect(auth.loadSessionCookies()['ASP.NET_SessionId'], 'old-cookie');
    });
  });
  for (final status in [200, 403, 503]) {
    test(
      'cold School uncertain response $status retains saved identity and retry probes only',
      () async {
        final f = SchoolAuthHttpFixture(saved: true, status: status);
        await _school(f, (auth, co) async {
          final original = auth.sessionIdentity;
          final result = await co.authenticate('123456', 'password');
          expect(result['success'], false);
          expect(result['code'], 'SESSION_UNCERTAIN');
          expect(auth.sessionIdentity, original);
          expect(f.credentialPosts, 0);
          expect(f.solved, 0);
          expect(co.status()['has_credentials'], false);
          expect(co.health, Health.unknown);
          f.home = '<a id="logout">Logout</a>';
          f.status = 200;
          final retry = await co.authenticate('123456', 'password');
          expect(retry['success'], true);
          expect(retry['cached'], true);
          expect(auth.sessionIdentity, original);
          expect(f.credentialPosts, 0);
        });
      },
    );
  }
  test(
    'cold School other account cannot adopt the restored owner cookies',
    () async {
      final f = SchoolAuthHttpFixture(
        saved: true,
        home: '<a id="logout">Logout</a>',
      );
      await _school(f, (auth, co) async {
        final result = await co.authenticate('654321', 'new-password');
        expect(result['success'], true);
        expect(result['cached'], isNot(true));
        expect(auth.sessionIdentity?.$1, '654321');
        expect(f.credentialPosts, 1);
        expect(auth.loadSessionCookies()['ASP.NET_SessionId'], 'new-cookie');
      });
    },
  );
  test('cold School explicit forceFresh still performs exactly one fresh authentication', () async {
    final f = SchoolAuthHttpFixture(
      saved: true,
      home: '<a id="logout">Logout</a>',
    );
    await _school(f, (auth, co) async {
      final result = await co.authenticate(
        '123456',
        'password',
        forceFresh: true,
      );
      expect(result['success'], true);
      expect(result['cached'], isNot(true));
      expect(f.credentialPosts, 1);
    });
  });
  test(
    'expired cold School login document still allows one original fresh login',
    () async {
      final f = SchoolAuthHttpFixture(
        saved: true,
        home: '<a id="logout">Logout</a>',
      )..firstHome = '<input id="bodyContent_txtUName">';
      await _school(f, (auth, co) async {
        final result = await co.authenticate('123456', 'password');
        expect(result['success'], true);
        expect(result['cached'], isNot(true));
        expect(f.credentialPosts, 1);
        expect(f.homeReads, 2);
      });
    },
  );
  test(
    'School metadata without cookies still reaches normal fresh login',
    () async {
      final f = SchoolAuthHttpFixture(home: '<a id="logout">Logout</a>');
      await _school(f, (auth, co) async {
        await auth.saveActiveServerBase(
          'https://rajshaladarpan.rajasthan.gov.in/SD1',
          user: '123456',
        );
        final result = await co.authenticate('123456', 'password');
        expect(result['success'], true);
        expect(f.credentialPosts, 1);
      });
    },
  );
  test('failed fresh School auth does not remember unverified recovery credentials', () async {
    final f = SchoolAuthHttpFixture();
    await _school(f, (auth, co) async {
      final result = await co.authenticate('123456', 'password');
      expect(result['success'], false);
      expect(co.status()['has_credentials'], false);
    });
  });
  test('cold Staff restore through coordinator reuses Home without credential POST', () async {
    final f = _Staff();
    await f.run((co) async {
      final original = f.registry.current();
      final result = await co.authenticate('1234567', 'password');
      expect(result['success'], true);
      expect(result['cached'], true);
      expect(f.posts, 0);
      expect(f.registry.current(), same(original));
      expect(f.clients.length, 1);
    });
  });
  test(
    'cold Staff protected Profile can prove session through coordinator',
    () async {
      final f = _Staff(
        home: '<input id="ContentPlaceHolder1_ImageButton18"><input name="__VIEWSTATE" value="v">',
      );
      await f.run((co) async {
        final result = await co.authenticate('1234567', 'password');
        expect(result['success'], true);
        expect(result['cached'], true);
        expect(f.posts, 0);
        expect(f.clients.length, 1);
      });
    },
  );
  test(
    'cold Staff uncertain protected documents do not force credential replay',
    () async {
      final f = _Staff(home: 'unavailable', status: 503);
      await f.run((co) async {
        final original = f.registry.current();
        final result = await co.authenticate('1234567', 'password');
        expect(result['success'], false);
        expect(result['code'], 'SESSION_UNCERTAIN');
        expect(f.posts, 0);
        expect(f.registry.current(), same(original));
        expect(f.clients.length, 1);
      });
    },
  );
  test(
    'cold Staff account switch still authenticates as new account once',
    () async {
      final f = _Staff();
      await f.run((co) async {
        final result = await co.authenticate('7654321', 'new-password');
        expect(result['success'], true);
        expect(result['cached'], isNot(true));
        expect(f.posts, 1);
        expect(f.registry.current()?.user, '7654321');
        expect(f.clients.first.closed, true);
      });
    },
  );
  test('cold Staff forceFresh preserves explicit reauthentication', () async {
    final f = _Staff();
    await f.run((co) async {
      final result = await co.authenticate(
        '1234567',
        'password',
        forceFresh: true,
      );
      expect(result['success'], true);
      expect(result['cached'], isNot(true));
      expect(f.posts, 1);
    });
  });
  test('cold restored context failed account switch disarms old fallback credentials', () async {
    final b = _Backend()..reject = true;
    final co = PortalCoordinator(
      name: 'test',
      backend: b,
      credentialsFallback: () => ('A', 'password-A'),
    );
    try {
      expect((await co.authenticate('B', 'password-B'))['success'], false);
      expect(co.status()['has_credentials'], false);
      try {
        await co.ensureReady(Kind.read);
      } catch (_) {}
      expect(b.calls, ['B']);
      b.reject = false;
      expect((await co.authenticate('A', 'password-A'))['success'], true);
    } finally {
      await co.shutdown();
    }
  });
  test(
    'failed sign-in after logout cannot re-arm retained fallback credentials',
    () async {
      final b = _Backend();
      final co = PortalCoordinator(
        name: 'test',
        backend: b,
        credentialsFallback: () => ('A', 'password-A'),
      );
      try {
        await co.authenticate('A', 'password-A');
        expect(
          (await co.logout(() async {
            b.context = null;
          }))['success'],
          true,
        );
        b.reject = true;
        expect((await co.authenticate('A', 'password-A'))['success'], false);
        expect(co.status()['has_credentials'], false);
        try {
          await co.ensureReady(Kind.read);
        } catch (_) {}
        expect(b.calls, ['A', 'A']);
      } finally {
        await co.shutdown();
      }
    },
  );
  test(
    'same-account transient failure retains existing fallback for recovery',
    () async {
      final b = _Backend()..reject = true;
      final co = PortalCoordinator(
        name: 'test',
        backend: b,
        credentialsFallback: () => ('A', 'password-A'),
      );
      try {
        expect(
          (await co.authenticate(
            'A',
            'password-A',
            forceFresh: true,
          ))['success'],
          false,
        );
        expect(co.status()['has_credentials'], true);
      } finally {
        await co.shutdown();
      }
    },
  );
  test('logout waits for mutation ownership and never closes or replays a running save', () async {
    final b = _Backend();
    final co = PortalCoordinator(
      name: 'test',
      backend: b,
      config: const CoordinatorConfig(mutationDrainTimeout: 0.01),
    );
    final entered = Completer<void>(), release = Completer<void>();
    var saves = 0, cleaned = 0;
    try {
      await co.authenticate('A', 'password');
      final save = co.run(
        resource: 'save',
        kind: Kind.mutation,
        worker: (_) async {
          saves++;
          entered.complete();
          await release.future;
          return {'success': true};
        },
      );
      await entered.future;
      final old = b.context;
      final busy = await co.logout(() async {
        cleaned++;
        b.context = null;
      });
      expect(busy['code'], 'BUSY');
      expect(cleaned, 0);
      expect(b.context, same(old));
      release.complete();
      expect((await save)['success'], true);
      expect(
        (await co.logout(() async {
          cleaned++;
          b.context = null;
        }))['success'],
        true,
      );
      expect(saves, 1);
      expect(cleaned, 1);
      expect(co.status()['has_credentials'], false);
    } finally {
      if (!release.isCompleted) release.complete();
      await co.shutdown();
    }
  });
  test(
    'logout cooperatively cancels a pending read before cleanup without replay',
    () async {
      final b = _Backend();
      final co = PortalCoordinator(
        name: 'test',
        backend: b,
        config: const CoordinatorConfig(
          readDrainTimeout: 0.01,
          readCancelGrace: 0.2,
        ),
      );
      final entered = Completer<void>();
      var reads = 0;
      try {
        await co.authenticate('A', 'password');
        final reading = co.run(
          resource: 'read',
          kind: Kind.read,
          maxAttempts: 1,
          worker: (_) async {
            reads++;
            final pending = Completer<Map<String, dynamic>>();
            final stop = OperationCancellation.current!.listen(
              () => pending.completeError(const OperationCancelled()),
            );
            entered.complete();
            try {
              return await pending.future;
            } finally {
              stop();
            }
          },
        );
        final observed = reading.then<Object>(
          (r) => r,
          onError: (Object e) => e,
        );
        await entered.future;
        expect(
          (await co.logout(() async {
            b.context = null;
          }))['success'],
          true,
        );
        expect(await observed, isA<CoordinatorError>());
        expect(reads, 1);
        expect(co.status()['has_credentials'], false);
      } finally {
        await co.shutdown();
      }
    },
  );
  test('RajSIMS cold saved session through coordinator still makes zero credential POSTs', () async {
    final store = raj.RajsimsMemoryStorage();
    raj.saved(store, 'u');
    final client = ScriptedSsoTransport(loadSsoFixture());
    final auth = raj.registry(store, () => client);
    final co = PortalCoordinator(
      name: 'rajsims',
      backend: RajsimsHttpBackend(auth),
    );
    try {
      expect((await co.authenticate('u', 'password'))['success'], true);
      expect(client.credentialPosts, 0);
      expect(auth.username, 'u');
    } finally {
      await co.shutdown();
      await auth.closeSession();
    }
  });
}
