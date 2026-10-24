import 'dart:convert';
import 'dart:io';

import '../../lib/services/core/direct/async_primitives.dart';
import '../../lib/services/portals/staff_login/direct/auth_manager.dart';
import '../../lib/services/portals/staff_login/direct/http_auth.dart';
import '../../lib/services/portals/staff_login/direct/http_login.dart';
import '../../lib/services/portals/staff_login/direct/http_session.dart';
import 'staff_auth_test.dart'
    show
        StaffMemoryStorage,
        StaffFakeTransport,
        StaffFixedServers,
        staffReply,
        staffTestBase;

void _check(bool value, String message) {
  if (!value) throw StateError(message);
}

const _profile =
    '<input id="ContentPlaceHolder1_ImageButton18"><input name="__VIEWSTATE" value="v">';
const _history =
    '<input name="__VIEWSTATE" value="v"><table id="ContentPlaceHolder1_grdLeaveDetails"><tr><td>No records found</td></tr></table>';
const _home = '<a id="lnkLogout">Logout</a>';
const _login =
    '<input id="txt_Username"><input id="txtUPNswd" type="password">';

class _Storage extends StaffMemoryStorage {
  Future<void> Function(String key)? afterWrite;
  @override
  Future<void> write(String key, String value) async {
    await super.write(key, value);
    await afterWrite?.call(key);
  }
}

class _SavedStaff {
  final storage = _Storage();
  final savedClient = StaffFakeTransport();
  final freshClients = <StaffFakeTransport>[];
  late final registry = StaffHttpAuth(
    storage: storage,
    sessionFactory: () {
      final client = StaffFakeTransport();
      freshClients.add(client);
      return StaffHttpSession(client: client);
    },
  );
  late final auth = StaffAuthManager(
    registry: registry,
    solveCaptcha: (_) => '1234',
    servers: StaffFixedServers(),
    loginOnce: (session, base, user, password, solve) async {
      freshLogins++;
      session
        ..base = base
        ..user = user
        ..authenticated = true;
      return const StaffLoginOutcome(true, 'AUTHENTICATED', 'ok');
    },
  );
  late final saved = StaffHttpSession(client: savedClient)
    ..base = staffTestBase
    ..user = '99'
    ..authenticated = true;
  int freshLogins = 0;
  Future<void> initialize() async {
    await auth.initialize();
    savedClient.jar.receive([
      Cookie('ASP.NET_SessionId', 'offline-saved')..path = '/',
    ], Uri.parse(staffTestBase));
    await registry.install(saved);
    await auth.saveActiveSessionInfo(staffTestBase, '99');
  }

  void pages({
    String home = '',
    int homeStatus = 500,
    String profile = '',
    String history = '',
    bool wrongProfilePath = false,
  }) {
    savedClient.handler = (request) async {
      final url = request['url'] as String;
      final path = Uri.parse(url).path.toLowerCase();
      if (path.endsWith('/staffhome.aspx'))
        return staffReply(url, home, status: homeStatus);
      if (path.endsWith('/staff_p10_detailsv2.aspx'))
        return staffReply(
          wrongProfilePath ? '$staffTestBase/Home/Staff/Other.aspx' : url,
          profile,
        );
      if (path.endsWith('/staff_leaveapplication_applied.aspx'))
        return staffReply(url, history);
      throw StateError('Unexpected protected request');
    };
  }

  Future<Map<String, dynamic>> login({
    String user = '99',
    bool forceFresh = false,
  }) => auth.executeLogin(user, 'offline-password', forceFresh: forceFresh);
  Future<void> close() async {
    await registry.closeSession();
    await saved.close();
  }
}

Future<void> _withSaved(Future<void> Function(_SavedStaff) body) async {
  final s = _SavedStaff();
  await s.initialize();
  try {
    await body(s);
  } finally {
    await s.close();
  }
}

void _cached(_SavedStaff s, Map result, int requests) {
  _check(
    result['success'] == true &&
        result['cached'] == true &&
        result['username'] == '99',
    'Valid saved session was not reused: $result',
  );
  _check(
    s.freshLogins == 0 && s.freshClients.isEmpty,
    'Saved reuse started CAPTCHA or a fresh session',
  );
  _check(
    identical(s.registry.current(), s.saved),
    'Saved context was replaced',
  );
  _check(
    s.savedClient.requests.length == requests,
    'Unexpected number of protected reads',
  );
}

Map<String, Future<void> Function()> staffRestoreCases() => {
  'cold registry restore reuses persisted cookies through protected Profile':
      () => _withSaved((s) async {
        s.pages(profile: _profile);
        await s.registry.closeSession();
        final client = StaffFakeTransport()..handler = s.savedClient.handler;
        final registry = StaffHttpAuth(
          storage: s.storage,
          sessionFactory: () => StaffHttpSession(client: client),
        );
        var logins = 0;
        final auth = StaffAuthManager(
          registry: registry,
          solveCaptcha: (_) => '1234',
          servers: StaffFixedServers(),
          loginOnce: (a, b, c, d, e) async {
            logins++;
            throw StateError(
              'Cold saved session unexpectedly started a fresh login',
            );
          },
        );
        try {
          final result = await auth.executeLogin('99', 'offline-password');
          _check(
            result['success'] == true &&
                result['cached'] == true &&
                logins == 0,
            '$result',
          );
          _check(
            registry.current()?.user == '99' && client.requests.length == 2,
            'Persisted owner or protected probe changed',
          );
          _check(
            client.jar.records().any((c) => c['value'] == 'offline-saved'),
            'Persisted cookie was not restored',
          );
        } finally {
          await registry.closeSession();
        }
      }),

  'saved restore reuses protected Profile when Home returns server error': () =>
      _withSaved((s) async {
        s.pages(
          home: 'Server Error in / System.NullReferenceException',
          profile: _profile,
        );
        _cached(s, await s.login(), 2);
      }),
  'saved restore reuses protected History when Home and Profile are inconclusive':
      () => _withSaved((s) async {
        s.pages(history: _history);
        _cached(s, await s.login(), 3);
      }),
  'generic Home 200 needs positive protected-page evidence': () =>
      _withSaved((s) async {
        s.pages(home: 'generic page', homeStatus: 200, profile: _profile);
        _cached(s, await s.login(), 2);
      }),
  'history remains usable when Profile redirects to login': () =>
      _withSaved((s) async {
        s.pages(profile: _login, history: _history);
        _cached(s, await s.login(), 3);
      }),
  'healthy Home remains one request and no fallback': () =>
      _withSaved((s) async {
        s.pages(home: _home, homeStatus: 200);
        _cached(s, await s.login(), 1);
      }),
  'all inconclusive pages remain uncertain without forced login': () =>
      _withSaved((s) async {
        s.pages(home: 'maintenance', homeStatus: 503);
        final result = await s.login();
        _check(
          result['code'] == 'SESSION_UNCERTAIN' && s.freshLogins == 0,
          '$result',
        );
        _check(
          identical(s.registry.current(), s.saved),
          'Inconclusive outage discarded session',
        );
      }),
  'matching marker on wrong protected path cannot validate a session': () =>
      _withSaved((s) async {
        s.pages(profile: _profile, wrongProfilePath: true);
        final result = await s.login();
        _check(
          result['success'] == false &&
              result['code'] == 'SESSION_UNCERTAIN' &&
              s.freshLogins == 0,
          '$result',
        );
      }),
  'explicit Home login document preserves one fresh-login flow': () =>
      _withSaved((s) async {
        s.savedClient.handler = (request) async =>
            staffReply('$staffTestBase/stafflogin.aspx', _login);
        final result = await s.login();
        _check(
          result['success'] == true &&
              result['cached'] == false &&
              s.freshLogins == 1,
          '$result',
        );
        _check(
          s.savedClient.requests.length == 1 && s.savedClient.closed,
          'Explicit expiry probing changed',
        );
      }),
  'force-fresh continues to bypass all saved-session probes': () =>
      _withSaved((s) async {
        final result = await s.login(forceFresh: true);
        _check(
          result['success'] == true &&
              result['cached'] == false &&
              s.freshLogins == 1 &&
              s.savedClient.requests.isEmpty,
          '$result',
        );
      }),
  'different requested account is never validated by saved protected pages':
      () => _withSaved((s) async {
        final result = await s.login(user: '100');
        _check(
          result['success'] == true &&
              result['username'] == '100' &&
              s.freshLogins == 1,
          '$result',
        );
        _check(
          s.savedClient.requests.isEmpty,
          'Other account probed old saved pages',
        );
      }),
  'session replaced during Profile check cannot report cached success': () =>
      _withSaved((s) async {
        s.pages(profile: _profile);
        final original = s.savedClient.handler!;
        s.savedClient.handler = (request) async {
          if ((request['url'] as String).endsWith(
            StaffAuthManager.profilePath,
          )) {
            final newer = StaffHttpSession(client: StaffFakeTransport())
              ..base = staffTestBase
              ..user = '100'
              ..authenticated = true;
            await s.registry.install(newer);
          }
          return original(request);
        };
        final result = await s.login();
        _check(
          result['success'] == false && result['code'] == 'ACCOUNT_CHANGED',
          '$result',
        );
        _check(
          s.registry.current()?.user == '100' && s.freshLogins == 0,
          'Old restore replaced the newer session',
        );
        final persisted =
            jsonDecode(s.storage.values[StaffHttpAuth.cookieKey]!) as Map;
        _check(
          persisted['user'] == '100',
          'Old restore overwrote newer persisted cookies',
        );
      }),
  'session replaced during active-info write cannot persist old cookies': () =>
      _withSaved((s) async {
        s.pages(home: _home, homeStatus: 200);
        s.storage.afterWrite = (key) async {
          if (key != StaffAuthManager.activeKey) return;
          s.storage.afterWrite = null;
          final newer = StaffHttpSession(client: StaffFakeTransport())
            ..base = staffTestBase
            ..user = '100'
            ..authenticated = true;
          await s.registry.install(newer);
        };
        final result = await s.login();
        _check(
          result['success'] == false && result['code'] == 'ACCOUNT_CHANGED',
          '$result',
        );
        final persisted =
            jsonDecode(s.storage.values[StaffHttpAuth.cookieKey]!) as Map;
        _check(
          persisted['user'] == '100',
          'Old saved-session probe overwrote newer cookies',
        );
      }),
  'cancellation during fallback is propagated without retry or session replacement':
      () => _withSaved((s) async {
        s.pages(profile: _profile);
        final original = s.savedClient.handler!;
        s.savedClient.handler = (request) {
          if ((request['url'] as String).endsWith(StaffAuthManager.profilePath))
            throw const OperationCancelled();
          return original(request);
        };
        var cancelled = false;
        try {
          await s.login();
        } on OperationCancelled {
          cancelled = true;
        }
        _check(
          cancelled &&
              s.freshLogins == 0 &&
              identical(s.registry.current(), s.saved),
          'Fallback cancellation was swallowed or relogged in',
        );
      }),
  'empty credentials still reject before protected requests': () =>
      _withSaved((s) async {
        final result = await s.auth.executeLogin('', 'offline-password');
        _check(
          result['code'] == 'NO_CREDENTIALS' &&
              s.savedClient.requests.isEmpty &&
              s.freshLogins == 0,
          '$result',
        );
      }),
};
