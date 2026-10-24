import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../lib/services/portals/staff_login/direct/http_auth.dart';
import '../../lib/services/portals/staff_login/direct/http_session.dart';
import 'staff_auth_test.dart'
    show StaffFakeTransport, StaffMemoryStorage, staffTestBase;

void _check(bool value, String message) {
  if (!value) throw StateError(message);
}

class _Storage extends StaffMemoryStorage {
  final dispatched = <Map>[];
  bool pauseNext = false, failNext = false;
  final entered = Completer<void>(), release = Completer<void>();
  @override
  Future<void> write(String key, String value) async {
    if (key == StaffHttpAuth.cookieKey) {
      dispatched.add(jsonDecode(value) as Map);
      if (pauseNext) {
        pauseNext = false;
        entered.complete();
        await release.future;
      }
      if (failNext) {
        failNext = false;
        throw StateError('Offline storage write failure');
      }
    }
    await super.write(key, value);
  }
}

class _Registry {
  final storage = _Storage();
  final sessions = <StaffHttpSession>[];
  late final registry = StaffHttpAuth(
    storage: storage,
    sessionFactory: () {
      final session = StaffHttpSession(client: StaffFakeTransport());
      sessions.add(session);
      return session;
    },
  );
  StaffHttpSession session(String user, String cookie) {
    final s = StaffHttpSession(client: StaffFakeTransport())
      ..base = staffTestBase
      ..user = user
      ..authenticated = true;
    rotate(s, cookie);
    sessions.add(s);
    return s;
  }

  void rotate(StaffHttpSession s, String value) {
    s.client.jar.receive([
      Cookie('sid', value)
        ..domain = staffHost
        ..path = '/SD4',
    ], Uri.parse(staffTestBase));
  }

  Map? get stored {
    final value = storage.values[StaffHttpAuth.cookieKey];
    return value == null ? null : jsonDecode(value) as Map;
  }

  bool hasCookie(Map? record, String value) =>
      record != null &&
      (record['cookies'] as List).any((c) => (c as Map)['value'] == value);
}

Future<void> _withRegistry(Future<void> Function(_Registry) body) async {
  final f = _Registry();
  try {
    await body(f);
  } finally {
    if (!f.storage.release.isCompleted) f.storage.release.complete();
    await f.registry.closeSession();
    for (final session in f.sessions) {
      await session.close();
    }
  }
}

Map<String, Future<void> Function()> staffCookieOwnershipCases() => {
  'unowned authenticated session cannot become the persisted current account':
      () => _withRegistry((f) async {
        final foreign = f.session('99', 'unowned');
        await f.registry.persist(foreign);
        _check(
          f.stored == null && f.storage.dispatched.isEmpty,
          'Unowned session was persisted',
        );
        _check(
          f.registry.current() == null,
          'Persist implicitly installed a session',
        );
      }),
  'old active worker cannot overwrite new account while old close is waiting':
      () => _withRegistry((f) async {
        final old = f.session('99', 'old');
        await f.registry.install(old);
        final entered = Completer<void>(), release = Completer<void>();
        final work = old.exclusive(() async {
          entered.complete();
          await release.future;
        });
        await entered.future;
        final newer = f.session('100', 'new-owner');
        final installing = f.registry.install(newer);
        Map? snapshot;
        try {
          await Future<void>.delayed(Duration.zero);
          await f.registry.persist(old);
          snapshot = f.stored;
        } finally {
          release.complete();
          await work;
          await installing;
        }
        _check(
          snapshot?['user'] == '100' && f.hasCookie(snapshot, 'new-owner'),
          'Old worker overwrote new saved cookies',
        );
        _check(
          identical(f.registry.current(), newer),
          'Old worker replaced current owner',
        );
      }),
  'late old worker cannot restore cookies after forget has deleted them': () =>
      _withRegistry((f) async {
        final old = f.session('99', 'old');
        await f.registry.install(old);
        final entered = Completer<void>(), release = Completer<void>();
        final work = old.exclusive(() async {
          entered.complete();
          await release.future;
        });
        await entered.future;
        final forgetting = f.registry.forget();
        try {
          await Future<void>.delayed(Duration.zero);
          await f.registry.persist(old);
        } finally {
          release.complete();
          await work;
          await forgetting;
        }
        _check(
          f.stored == null && f.registry.current() == null,
          'Late worker restored forgotten cookies',
        );
      }),
  'queued old snapshot is skipped when another session takes ownership': () =>
      _withRegistry((f) async {
        final old = f.session('99', 'old');
        await f.registry.install(old);
        f.storage.pauseNext = true;
        f.rotate(old, 'in-flight');
        final first = f.registry.persist(old);
        await f.storage.entered.future;
        f.rotate(old, 'queued-stale');
        final queued = f.registry.persist(old);
        final newer = f.session('100', 'new-owner');
        final installing = f.registry.install(newer);
        f.storage.release.complete();
        await Future.wait([first, queued, installing]);
        _check(
          !f.storage.dispatched.any((r) => f.hasCookie(r, 'queued-stale')),
          'Stale queued snapshot reached storage',
        );
        _check(
          f.stored?['user'] == '100' && f.hasCookie(f.stored, 'new-owner'),
          'New owner was not persisted',
        );
      }),
  'queued snapshot cannot cross an epoch even when the session object is reused':
      () => _withRegistry((f) async {
        final session = f.session('99', 'old');
        await f.registry.install(session);
        f.storage.pauseNext = true;
        f.rotate(session, 'in-flight');
        final first = f.registry.persist(session);
        await f.storage.entered.future;
        f.rotate(session, 'queued-stale');
        final queued = f.registry.persist(session);
        session.user = '100';
        f.rotate(session, 'new-owner');
        final installing = f.registry.install(session);
        f.storage.release.complete();
        await Future.wait([first, queued, installing]);
        _check(
          !f.storage.dispatched.any((r) => f.hasCookie(r, 'queued-stale')),
          'Queued snapshot crossed registry epoch',
        );
        _check(
          f.stored?['user'] == '100' && f.hasCookie(f.stored, 'new-owner'),
          'Reinstalled context was not persisted',
        );
      }),
  'queued snapshot of an invalidated session is not dispatched': () =>
      _withRegistry((f) async {
        final session = f.session('99', 'old');
        await f.registry.install(session);
        f.storage.pauseNext = true;
        f.rotate(session, 'in-flight');
        final first = f.registry.persist(session);
        await f.storage.entered.future;
        f.rotate(session, 'queued-stale');
        final queued = f.registry.persist(session);
        f.registry.invalidate(session);
        f.storage.release.complete();
        await Future.wait([first, queued]);
        _check(
          !f.storage.dispatched.any((r) => f.hasCookie(r, 'queued-stale')),
          'Invalidated queued snapshot reached storage',
        );
        _check(
          !session.authenticated,
          'Persistence revived an invalidated session',
        );
      }),
  'current session cookie rotation still persists and cold-restores': () =>
      _withRegistry((f) async {
        final session = f.session('99', 'old');
        await f.registry.install(session);
        f.rotate(session, 'rotated');
        await f.registry.persist(session);
        final restored = StaffHttpAuth(
          storage: f.storage,
          sessionFactory: () => StaffHttpSession(client: StaffFakeTransport()),
        );
        try {
          await restored.initialize();
          _check(
            restored.current()?.user == '99' &&
                restored.current()?.base == staffTestBase,
            'Owner/base contract changed',
          );
          _check(
            restored.current()!.client.jar.records().any(
              (c) => c['value'] == 'rotated',
            ),
            'Rotated cookies did not restore',
          );
        } finally {
          await restored.closeSession();
        }
      }),
  'normal closeSession retains latest cookies for next startup': () =>
      _withRegistry((f) async {
        final session = f.session('99', 'old');
        await f.registry.install(session);
        f.rotate(session, 'before-close');
        await f.registry.closeSession();
        _check(
          f.registry.current() == null && f.hasCookie(f.stored, 'before-close'),
          'Normal retirement lost latest cookie snapshot',
        );
        _check(!session.authenticated, 'Closed session stayed authenticated');
      }),
  'storage failure does not poison the next valid owned persist': () =>
      _withRegistry((f) async {
        final session = f.session('99', 'old');
        await f.registry.install(session);
        f.storage.failNext = true;
        f.rotate(session, 'failed');
        await f.registry.persist(session);
        f.rotate(session, 'retry-owned');
        await f.registry.persist(session);
        _check(
          f.hasCookie(f.stored, 'retry-owned') && f.stored?['user'] == '99',
          'Persistence queue was poisoned by storage failure',
        );
      }),
  'null unauthenticated and incomplete sessions keep existing no-write behavior':
      () => _withRegistry((f) async {
        await f.registry.persist(null);
        final session = f.session('99', 'old')..authenticated = false;
        await f.registry.install(session);
        await f.registry.persist(session);
        session.authenticated = true;
        session.base = null;
        await f.registry.persist(session);
        _check(f.storage.dispatched.isEmpty, 'Invalid session was written');
      }),
  'same-owner snapshots remain FIFO and end at the latest cookie': () =>
      _withRegistry((f) async {
        final session = f.session('99', 'old');
        await f.registry.install(session);
        f.rotate(session, 'one');
        final first = f.registry.persist(session);
        f.rotate(session, 'two');
        final second = f.registry.persist(session);
        await Future.wait([first, second]);
        _check(
          f.hasCookie(f.stored, 'two') &&
              identical(f.registry.current(), session),
          'Owned FIFO cookie writes changed',
        );
      }),
  'current browser cookie bridge continues to persist official-host rotation':
      () => _withRegistry((f) async {
        final session = f.session('99', 'old');
        await f.registry.install(session);
        final changed = f.registry.syncFromBrowser(session, [
          {
            'domain': staffHost,
            'name': 'sid',
            'value': 'browser',
            'path': '/SD4',
          },
        ]);
        await f.registry.persist(session);
        _check(
          changed && f.hasCookie(f.stored, 'browser'),
          'Browser cookie rotation was lost',
        );
      }),
};
