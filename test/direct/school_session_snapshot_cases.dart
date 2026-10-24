import 'dart:async';
import 'dart:convert';

import '../../lib/services/portals/shaladarpan/direct/auth_manager.dart';

const _activeKey = 'rajshala.direct.sd.active';
const _cookieKey = 'rajshala.direct.sd.cookies';
const _stateKey = 'rajshala.direct.sd.session_v2';
const _base = 'https://rajshaladarpan.rajasthan.gov.in/SD1';
void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

class _Storage implements SchoolAuthStorage {
  final values = <String, String>{};
  final failDeletes = <String>{};
  bool failWrites = false, failReads = false;
  Completer<void>? writeEntered, releaseWrite;
  _Storage();
  _Storage.copy(_Storage other) {
    values.addAll(other.values);
  }
  @override
  Future<String?> read(String key) async {
    if (failReads) throw StateError('Simulated secure storage read failure');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('Simulated secure storage write failure');
    final entered = writeEntered, release = releaseWrite;
    writeEntered = null;
    releaseWrite = null;
    if (entered != null && release != null) {
      entered.complete();
      await release.future;
    }
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    if (failDeletes.contains(key)) throw StateError('Simulated delete failure');
    values.remove(key);
  }
}

SchoolAuthManager _manager(_Storage storage) => SchoolAuthManager(
  storage: storage,
  solveCaptcha: (_) async => throw StateError('Network login is not expected'),
);
_Storage _legacy({bool withId = true}) => _Storage()
  ..values[_activeKey] = jsonEncode({
    'user': 'school-A',
    'server_base': _base,
    if (withId) 'session_id': 'login-A',
  })
  ..values[_cookieKey] = jsonEncode({'ASP.NET_SessionId': 'cookie-A'});
Future<SchoolAuthManager> _restart(_Storage storage) async {
  final m = _manager(_Storage.copy(storage));
  await m.initialize();
  return m;
}

bool _hasCookie(SchoolAuthManager m, String v) =>
    m.loadSessionCookies()['ASP.NET_SessionId'] == v;
String _state(Map<String, String> active, Map<String, String> cookies) =>
    jsonEncode({'version': 2, 'active': active, 'cookies': cookies});

Map<String, Future<void> Function()> schoolSessionSnapshotCases() => {
  'School switch immediately detaches previous cookies in memory': () async {
    final m = _manager(_legacy());
    await m.saveActiveServerBase(_base, user: 'school-B');
    _check(m.activeSchoolId == 'school-B', 'New School ID was not selected');
    _check(
      m.loadSessionCookies().isEmpty,
      'School B retained School A cookies',
    );
    _check(
      m.sessionIdentity == null,
      'Incomplete new session became authenticated',
    );
  },
  'School restart between account and cookie saves cannot bind old cookies':
      () async {
        final s = _legacy();
        await _manager(s).saveActiveServerBase(_base, user: 'school-B');
        final m = await _restart(s);
        _check(m.activeSchoolId == 'school-B', 'Account metadata was lost');
        _check(
          m.loadSessionCookies().isEmpty && m.sessionIdentity == null,
          'Restart bound old cookies to School B',
        );
      },
  'School failed cookie write cannot expose old cookies under new account':
      () async {
        final s = _legacy();
        final m = _manager(s);
        await m.saveActiveServerBase(_base, user: 'school-B');
        s.failWrites = true;
        await m.saveSessionCookies({'ASP.NET_SessionId': 'cookie-B'});
        final restored = await _restart(s);
        _check(
          !_hasCookie(restored, 'cookie-A') && restored.sessionIdentity == null,
          'Failed save restored A cookies under B',
        );
      },
  'School forget plus failed legacy deletes stays forgotten after restart':
      () async {
        final s = _legacy()..failDeletes.addAll([_activeKey, _cookieKey]);
        await _manager(s).forgetSavedSession();
        final m = await _restart(s);
        _check(
          m.activeSchoolId.isEmpty && m.loadSessionCookies().isEmpty,
          'Failed legacy deletes resurrected account or cookies',
        );
      },
  'School interrupted login after failed legacy cookie deletion remains unbound':
      () async {
        final s = _legacy()..failDeletes.add(_cookieKey);
        final m = _manager(s);
        await m.forgetSavedSession();
        await m.saveActiveServerBase(_base, user: 'school-B');
        final restored = await _restart(s);
        _check(
          restored.activeSchoolId == 'school-B',
          'New account metadata was lost',
        );
        _check(
          restored.loadSessionCookies().isEmpty,
          'Interrupted login adopted leftover cookies',
        );
      },
  'School complete current snapshot overrides stale legacy records': () async {
    final s = _legacy()
      ..values[_stateKey] = _state(
        {'user': 'school-B', 'server_base': _base, 'session_id': 'login-B'},
        {'ASP.NET_SessionId': 'cookie-B'},
      );
    final m = await _restart(s);
    _check(
      m.sessionIdentity == ('school-B', 'login-B') && _hasCookie(m, 'cookie-B'),
      'Stale legacy state won over current snapshot',
    );
  },
  'School empty current snapshot prevents legacy resurrection': () async {
    final s = _legacy()..values[_stateKey] = _state({}, {});
    final m = await _restart(s);
    _check(
      m.activeSchoolId.isEmpty && m.loadSessionCookies().isEmpty,
      'Empty authoritative snapshot fell back to old account',
    );
  },
  'School corrupt current snapshot fails closed instead of using legacy':
      () async {
        final s = _legacy()..values[_stateKey] = '{truncated';
        final m = await _restart(s);
        _check(
          m.activeSchoolId.isEmpty && m.loadSessionCookies().isEmpty,
          'Corrupt current snapshot restored stale legacy session',
        );
      },
  'School unsupported snapshot version fails closed': () async {
    final s = _legacy()
      ..values[_stateKey] = jsonEncode({
        'version': 99,
        'active': {},
        'cookies': {},
      });
    final m = await _restart(s);
    _check(
      m.activeSchoolId.isEmpty,
      'Unsupported version fell back to old account',
    );
  },
  'School malformed cookie types cannot restore partial identity': () async {
    final s = _legacy()
      ..values[_stateKey] = jsonEncode({
        'version': 2,
        'active': {'user': 'school-B', 'session_id': 'login-B'},
        'cookies': {'ASP.NET_SessionId': 123},
      });
    final m = await _restart(s);
    _check(
      m.activeSchoolId.isEmpty && m.sessionIdentity == null,
      'Malformed snapshot left a partial or stale identity',
    );
  },
  'School valid legacy session remains compatible': () async {
    final m = await _restart(_legacy());
    _check(
      m.sessionIdentity == ('school-A', 'login-A'),
      'Legacy identity changed',
    );
    _check(
      _hasCookie(m, 'cookie-A') && m.activeServerBase == _base,
      'Legacy state was lost',
    );
  },
  'School legacy session without id obtains stable restart identity': () async {
    final s = _legacy(withId: false);
    final m = _manager(s);
    await m.initialize();
    final identity = m.sessionIdentity;
    _check(
      identity != null && identity.$1 == 'school-A',
      'Legacy id was not generated',
    );
    final restored = await _restart(s);
    _check(
      restored.sessionIdentity == identity && _hasCookie(restored, 'cookie-A'),
      'Generated identity did not survive restart',
    );
  },
  'School same account server update preserves its cookies and identity':
      () async {
        final s = _legacy();
        await _manager(s).saveActiveServerBase(
          'https://rajshaladarpan.rajasthan.gov.in/SD2/',
          user: 'school-A',
        );
        final m = await _restart(s);
        _check(
          m.sessionIdentity == ('school-A', 'login-A') &&
              _hasCookie(m, 'cookie-A'),
          'Same-account server update reset session',
        );
        _check(
          m.activeServerBase.endsWith('/SD2'),
          'Server normalization changed',
        );
      },
  'School failed cookie refresh retains complete previous saved session':
      () async {
        final s = _legacy();
        final m = _manager(s);
        await m.initialize();
        s.failWrites = true;
        await m.saveSessionCookies({'ASP.NET_SessionId': 'rotated'});
        final restored = await _restart(s);
        _check(
          restored.sessionIdentity == ('school-A', 'login-A') &&
              _hasCookie(restored, 'cookie-A'),
          'Failed refresh damaged previous complete session',
        );
      },
  'School saved and returned cookie maps resist caller mutations': () async {
    final s = _legacy();
    final m = _manager(s);
    final cookies = {'ASP.NET_SessionId': 'rotated'};
    await m.saveSessionCookies(cookies);
    cookies['ASP.NET_SessionId'] = 'caller-change';
    m.loadSessionCookies()['ASP.NET_SessionId'] = 'returned-map-change';
    _check(
      _hasCookie(m, 'rotated') && _hasCookie(await _restart(s), 'rotated'),
      'Caller mutated live or saved cookies',
    );
  },
  'School normal client close preserves restart session': () async {
    final s = _legacy();
    final m = _manager(s);
    await m.initialize();
    final client = await m.getAuthenticatedClient();
    await m.closeAuthenticatedClients();
    _check(client.retired, 'Normal close did not retire pooled client');
    final restored = await _restart(s);
    _check(
      restored.sessionIdentity == ('school-A', 'login-A') &&
          _hasCookie(restored, 'cookie-A'),
      'Normal close forgot restart session',
    );
  },
  'School forget can remove session when snapshot write fails': () async {
    final s = _legacy();
    final m = _manager(s);
    await m.initialize();
    s.failWrites = true;
    await m.forgetSavedSession();
    final restored = await _restart(s);
    _check(
      restored.sessionIdentity == null && restored.loadSessionCookies().isEmpty,
      'Failed tombstone write prevented fallback deletion',
    );
  },
  'School unreadable secure storage is nonfatal and restores no session':
      () async {
        final s = _legacy()..failReads = true;
        final m = _manager(s);
        await m.initialize();
        _check(
          m.activeSchoolId.isEmpty && m.loadSessionCookies().isEmpty,
          'Unreadable storage restored a session',
        );
      },
  'School cookie refresh survives restart without any legacy keys': () async {
    final s = _Storage()
      ..values[_stateKey] = _state(
        {'user': 'school-A', 'server_base': _base, 'session_id': 'login-A'},
        {'ASP.NET_SessionId': 'cookie-A'},
      );
    final m = _manager(s);
    await m.saveSessionCookies({'ASP.NET_SessionId': 'rotated'});
    final restored = await _restart(s);
    _check(
      restored.sessionIdentity == ('school-A', 'login-A') &&
          _hasCookie(restored, 'rotated'),
      'Cookie refresh lost identity when legacy keys were absent',
    );
  },
  'School account switch retires the previous authenticated client': () async {
    final m = _manager(_legacy());
    final oldClient = await m.getAuthenticatedClient();
    try {
      await m.saveActiveServerBase(_base, user: 'school-B');
      _check(
        oldClient.retired,
        'Old account client remained available after switch',
      );
    } finally {
      await m.closeAuthenticatedClients();
      oldClient.retire();
    }
  },
  'School forget queues behind in-flight save and wins on restart': () async {
    final s = _legacy();
    final m = _manager(s);
    await m.initialize();
    final entered = Completer<void>(), release = Completer<void>();
    s.writeEntered = entered;
    s.releaseWrite = release;
    final saving = m.saveSessionCookies({'ASP.NET_SessionId': 'rotated'});
    await entered.future;
    final forgetting = m.forgetSavedSession();
    try {
      await Future<void>.delayed(Duration.zero);
      _check(m.sessionIdentity == null, 'Forget retained an in-memory session');
    } finally {
      release.complete();
    }
    await Future.wait([saving, forgetting]);
    final restored = await _restart(s);
    _check(
      restored.activeSchoolId.isEmpty && restored.loadSessionCookies().isEmpty,
      'Earlier in-flight save resurrected forgotten session',
    );
  },
};
