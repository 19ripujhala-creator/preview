import 'dart:convert';
import 'dart:io';

import '../../lib/services/core/direct/coordinator.dart';
import '../../lib/services/core/ecosystem_service.dart';
import '../../lib/services/portals/staff_login/direct/auth_manager.dart';
import '../../lib/services/portals/staff_login/direct/http_auth.dart';
import '../../lib/services/portals/staff_login/direct/http_login.dart';
import '../../lib/services/portals/staff_login/direct/http_session.dart';
import '../../lib/services/portals/staff_login/direct/staff_runtime.dart'
    show StaffCoordinator, StaffHttpBackend;
import 'staff_auth_test.dart'
    show
        StaffMemoryStorage,
        StaffFakeTransport,
        StaffFixedServers,
        staffReply,
        staffLiveHome,
        staffTestForm;

void _check(bool value, String message) {
  if (!value) throw StateError(message);
}

class _Fixture {
  _Fixture({
    this.notices = const ['Wrong password'],
    this.unreadableAfter,
    this.successIndex,
    this.down = false,
    this.localDiagnostic = false,
  });
  final List<String> notices;
  final int? unreadableAfter, successIndex;
  final bool down, localDiagnostic;
  final clients = <StaffFakeTransport>[], sessions = <StaffHttpSession>[];
  final storage = StaffMemoryStorage();
  final servers = StaffFixedServers();
  int solved = 0;
  late final registry = StaffHttpAuth(
    storage: storage,
    sessionFactory: () {
      final index = clients.length;
      final notice = notices.isEmpty
          ? ''
          : notices[index < notices.length ? index : notices.length - 1];
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
        if (index == successIndex)
          staffLiveHome()
        else
          staffReply(
            staffLoginPath,
            notice.isEmpty
                ? ''
                : '<script>alert(${jsonEncode(notice)});</script>',
          ),
        if (index != successIndex) staffReply(staffHomePath, ''),
      ]);
      if (down)
        client.handler = (_) async =>
            throw const SocketException('Offline portal unavailable');
      clients.add(client);
      final session = StaffHttpSession(client: client);
      sessions.add(session);
      return session;
    },
  );
  late final auth = StaffAuthManager(
    registry: registry,
    servers: servers,
    solveCaptcha: (_) {
      final attempt = solved++;
      return unreadableAfter != null && attempt >= unreadableAfter!
          ? ''
          : '1234';
    },
    sleep: (_) async {},
    monotonic: () => 0,
    loginOnce: localDiagnostic
        ? (_, _, _, _, _) async => const StaffLoginOutcome(
            false,
            'LOGIN_NOT_VERIFIED',
            'Invalid username',
          )
        : null,
  );
  late final coordinator = StaffCoordinator(backend: StaffHttpBackend(auth));
  Future<Map<String, dynamic>> login() =>
      auth.executeLogin('1234567', 'offline-password');
  int get credentialPosts => clients.fold(
    0,
    (n, c) => n + c.requests.where((r) => r['data'] != null).length,
  );
  void rejected(int attempts) {
    _check(
      clients.length == attempts && clients.every((c) => c.closed),
      'Attempt count or candidate cleanup changed',
    );
    _check(
      registry.current() == null &&
          !storage.values.containsKey(StaffHttpAuth.cookieKey),
      'Rejected session was committed',
    );
  }

  Future<void> close() async {
    await coordinator.shutdown();
    await registry.closeSession();
    for (final s in sessions) {
      await s.close();
    }
  }
}

Future<void> _with(_Fixture f, Future<void> Function(_Fixture) body) async {
  try {
    await body(f);
  } finally {
    await f.close();
  }
}

void _portal(Map result, String text, String code) {
  _check(
    result['success'] == false && result['code'] == code,
    'Rejection classification changed',
  );
  _check(
    result['message'] == text,
    'Original portal message was replaced: ${result['message']}',
  );
  _check(
    result['portal_message'] == text && result['message_source'] == 'portal',
    'Portal provenance was lost',
  );
}

Map<String, Future<void> Function()> staffLoginMessageCases() => {
  'Staff credential rejection retains exact portal wording': () => _with(
    _Fixture(notices: ['Wrong password. Please check your Staff ID.']),
    (f) async {
      _portal(await f.login(), f.notices.single, 'INVALID_CREDENTIALS');
      _check(f.credentialPosts == 1, 'Credential rejection was retried');
      f.rejected(1);
    },
  ),
  'Staff mixed-language credential notice survives native login': () => _with(
    _Fixture(
      notices: [
        'Wrong password: \u0915\u0943\u092a\u092f\u093e Staff ID/password \u091c\u093e\u0901\u091a\u0947\u0902\u0964',
      ],
    ),
    (f) async {
      _portal(await f.login(), f.notices.single, 'INVALID_CREDENTIALS');
      f.rejected(1);
    },
  ),
  'Staff unrecognized portal rejection retains wording and provenance': () =>
      _with(
        _Fixture(
          notices: [
            '\u092a\u094b\u0930\u094d\u091f\u0932 \u092a\u0930 \u0938\u0947\u0935\u093e \u0905\u092d\u0940 \u0909\u092a\u0932\u092c\u094d\u0927 \u0928\u0939\u0940\u0902 \u0939\u0948\u0964',
          ],
        ),
        (f) async {
          _portal(await f.login(), f.notices.single, 'LOGIN_NOT_VERIFIED');
          _check(
            f.credentialPosts == 1,
            'Unknown rejection replayed credentials',
          );
          f.rejected(1);
        },
      ),
  'Staff active-session rejection keeps original text without terminate replay':
      () => _with(
        _Fixture(
          notices: [
            'Already logged in on another device. Please terminate the previous session.',
          ],
        ),
        (f) async {
          _portal(await f.login(), f.notices.single, 'ACTIVE_SESSION_EXISTS');
          _check(
            f.credentialPosts == 1,
            'Active-session rejection caused replay',
          );
          f.rejected(1);
        },
      ),
  'Staff CAPTCHA exhaustion retains the last original portal notice': () =>
      _with(
        _Fixture(
          notices: List.generate(
            8,
            (i) => 'Invalid CAPTCHA - portal attempt ${i + 1}',
          ),
        ),
        (f) async {
          final result = await f.login();
          _portal(result, f.notices.last, 'LOGIN_FAILED');
          _check(
            result['backend_message'] ==
                'Staff login failed after multiple attempts.',
            'Budget explanation was not kept separately',
          );
          _check(
            f.credentialPosts == 8 && f.solved == 8,
            'CAPTCHA budget changed',
          );
          f.rejected(8);
        },
      ),
  'Staff unreadable OCR without portal message retains app failure': () =>
      _with(_Fixture(unreadableAfter: 0), (f) async {
        final result = await f.login();
        _check(
          result['code'] == 'LOGIN_FAILED' &&
              result['message'] ==
                  'Staff login failed after multiple attempts.',
          'OCR-only fallback changed',
        );
        _check(
          !result.containsKey('message_source') &&
              !result.containsKey('portal_message'),
          'Local OCR failure was labelled as portal text',
        );
        _check(
          f.credentialPosts == 0 && f.solved == 8,
          'Unreadable OCR submitted credentials',
        );
        f.rejected(8);
      }),
  'Staff CAPTCHA then unreadable OCR retains last available portal notice':
      () => _with(
        _Fixture(
          notices: ['Incorrect CAPTCHA supplied by portal'],
          unreadableAfter: 1,
        ),
        (f) async {
          _portal(await f.login(), f.notices.single, 'LOGIN_FAILED');
          _check(
            f.credentialPosts == 1 && f.solved == 8,
            'Mixed CAPTCHA/OCR attempt policy changed',
          );
          f.rejected(8);
        },
      ),
  'Staff successful retry does not inherit previous portal rejection': () =>
      _with(_Fixture(notices: ['Invalid CAPTCHA'], successIndex: 1), (f) async {
        final result = await f.login();
        _check(
          result['success'] == true && result['cached'] == false,
          'Valid retry failed',
        );
        _check(
          !result.containsKey('portal_message') &&
              !result.containsKey('message_source'),
          'Success retained old rejection metadata',
        );
        _check(
          f.credentialPosts == 2 &&
              f.clients.length == 2 &&
              f.registry.current()?.authenticated == true,
          'Successful retry sequence changed',
        );
      }),
  'Staff portal rejection reaches coordinator and ecosystem details unchanged':
      () => _with(
        _Fixture(
          notices: ['Invalid username or password - contact your office.'],
        ),
        (f) async {
          final result = await f.coordinator.authenticate(
            '1234567',
            'offline-password',
          );
          _portal(result, f.notices.single, 'INVALID_CREDENTIALS');
          final row = EcosystemService.describeLoginResult(
            result,
            durationSeconds: 0.1,
          );
          _check(
            row['message'] == f.notices.single &&
                row['message_source'] == 'portal' &&
                row['code'] == 'INVALID_CREDENTIALS',
            'Ecosystem lost the portal failure',
          );
          try {
            await f.coordinator.ensureReady(Kind.read);
          } catch (_) {}
          _check(
            f.credentialPosts == 1,
            'Invalid credentials automatically replayed after rejection',
          );
          f.rejected(1);
        },
      ),
  'Staff missing credentials remain local and start no request': () =>
      _with(_Fixture(), (f) async {
        final result = await f.auth.executeLogin('1234567', ' ');
        _check(
          result['code'] == 'NO_CREDENTIALS' &&
              !result.containsKey('message_source') &&
              f.clients.isEmpty,
          'Local credential validation changed',
        );
      }),
  'Staff network outage remains separate from portal notice': () =>
      _with(_Fixture(down: true), (f) async {
        final result = await f.login();
        _check(
          result['code'] == 'PORTAL_DOWN' &&
              result['message'] ==
                  'Could not connect to any Staff Corner server.',
          'Node outage classification changed',
        );
        _check(
          !result.containsKey('portal_message') &&
              !result.containsKey('message_source'),
          'Network outage was labelled as portal text',
        );
        _check(
          f.credentialPosts == 0 && f.clients.length == 5,
          'Outage introduced credential replay',
        );
        f.rejected(5);
      }),
  'Staff backend-only credential diagnostic retains existing fallback contract':
      () => _with(_Fixture(localDiagnostic: true), (f) async {
        final result = await f.login();
        _check(
          result.length == 3 &&
              result['code'] == 'INVALID_CREDENTIALS' &&
              result['message'] == 'Invalid Staff ID or Password.',
          'Backend-only fallback contract changed',
        );
        f.rejected(1);
      }),
};
