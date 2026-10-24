/// Complete conversion of latest working Staff auth_manager.py.
/// Source probe evidence, node fallback, CAPTCHA budget and failure codes retained.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:html/parser.dart' as html;

import '../../../core/direct/async_primitives.dart';
import '../../../core/direct/coordinator.dart' show Probe;
import 'http_auth.dart';
import 'http_login.dart';
import 'http_session.dart';
import 'portal_state.dart';
import 'server_manager.dart';

typedef StaffDocument = ({String url, int status, String text});
typedef StaffLoginAttempt = Future<StaffLoginOutcome> Function(
  StaffHttpSession session,
  String base,
  String user,
  String password,
  StaffCaptchaSolver solve,
);
final _staffMonotonic = Stopwatch()..start();

class StaffAuthManager {
  StaffAuthManager({
    required this.registry,
    required this.solveCaptcha,
    StaffServerManager? servers,
    this.progress,
    StaffLoginAttempt? loginOnce,
    double Function()? monotonic,
    Future<void> Function(Duration)? sleep,
  }) : servers = servers ?? StaffServerManager(progress: progress),
       loginOnce = loginOnce ?? staffLoginOnce,
       monotonic =
           monotonic ?? (() => _staffMonotonic.elapsedMicroseconds / 1000000),
       sleep = sleep ?? Future<void>.delayed;
  final StaffHttpAuth registry;
  final StaffCaptchaSolver solveCaptcha;
  final StaffServerManager servers;
  final StaffProgress? progress;
  final StaffLoginAttempt loginOnce;
  final double Function() monotonic;
  final Future<void> Function(Duration) sleep;
  static const activeKey = 'staff_active_server';
  static const loginBudgetSeconds = 120.0, maxCaptchaAttempts = 8;
  static const profilePath = '/Home/Staff/Staff_P10_DetailsV2.aspx';
  static const historyPath = '/Home/Staff/Staff_LeaveApplication_Applied.aspx';
  static const nodeErrorCodes = {
    'PORTAL_UNAVAILABLE',
    'CAPTCHA_UNAVAILABLE',
    'LOGIN_FORM_CHANGED',
    'INVALID_REDIRECT',
    'LOGIN_AJAX_FAILED',
  };
  final Map<String, String> _active = {};
  Future<void>? _initializing;
  Future<void> _writes = Future.value();
  String get activeServerBase => _active['server_base'] ?? staffServers.first;
  String get activeStaffUser => _active['user'] ?? '';
  Future<void> initialize() => _initializing ??= _load();
  Future<void> _load() async {
    try {
      final text = await registry.storage.read(activeKey);
      if (text != null) {
        final data = jsonDecode(text);
        if (data is Map) {
          for (final e in data.entries) {
            if (e.value != null &&
                e.value != false &&
                e.value != '' &&
                e.value != 0)
              _active[e.key.toString()] = e.value.toString();
          }
        }
      }
    } catch (_) {}
    await registry.initialize();
  }

  Future<void> _write(Future<void> Function() operation) {
    final next = _writes.then((_) async {
      try {
        await operation();
      } catch (_) {}
    });
    _writes = next;
    return next;
  }

  Future<void> saveActiveSessionInfo(String base, [String? user]) async {
    base = base.replaceFirst(RegExp(r'/+$'), '');
    if (base.isEmpty) return;
    _active['server_base'] = base;
    if (user != null) _active['user'] = user;
    final text = jsonEncode(_active);
    await _write(() => registry.storage.write(activeKey, text));
  }

  Future<void> forgetSavedSession() async {
    _active.clear();
    await _write(() => registry.storage.delete(activeKey));
    await registry.forget();
  }

  static Map<String, dynamic> failure(String code, String message) => {
    'success': false,
    'code': code,
    'message': message,
  };
  static Map<String, dynamic> _loginFailure(
    String code,
    String message, {
    String portalMessage = '',
  }) => {
    ...failure(code, portalMessage.isEmpty ? message : portalMessage),
    if (portalMessage.isNotEmpty) ...{
      'portal_message': portalMessage,
      'message_source': 'portal',
      if (message != portalMessage) 'backend_message': message,
    },
  };

  static Map<String, dynamic> successPayload(
    String base,
    String user, {
    required bool cached,
    int latency = 0,
  }) => {
    'success': true,
    'cached': cached,
    'server_base': base,
    'server_name': base.replaceFirst(RegExp(r'/+$'), '').split('/').last,
    'latency': latency,
    'username': user,
  };
  bool isCurrent(StaffHttpSession? session) =>
      session != null && identical(registry.current(), session);
  Future<StaffDocument?> getDocument(
    StaffHttpSession session,
    String base,
    String path,
  ) async {
    try {
      final reply = await session.client.get(
        '${base.replaceFirst(RegExp(r'/+$'), '')}$path',
        timeout: const Duration(seconds: 5),
      );
      if (!isCurrent(session)) return null;
      return (
        url: reply.url.toString(),
        status: reply.statusCode,
        text: reply.text,
      );
    } on OperationCancelled {
      rethrow;
    } catch (_) {
      return null;
    }
  }

  Future<StaffDocument?> fetchHome([
    StaffHttpSession? session,
    String? base,
  ]) async {
    final current = session ?? registry.current();
    if (current == null) return null;
    return getDocument(
      current,
      base ?? activeServerBase,
      '/Home/staff/StaffHome.aspx',
    );
  }

  static Probe classifyHome(StaffDocument? home) {
    if (home == null) return Probe.unknown;
    final failure = staffDocumentFailure(
      home.url.toLowerCase(),
      home.text,
      home.status,
    );
    if (failure == 'SESSION_EXPIRED') return Probe.dead;
    if (failure != null) return Probe.unknown;
    if (home.status == 200) {
      final doc = html.parse(home.text);
      const markers = {
        'btnlogout',
        'lnklogout',
        'contentplaceholder1_lblstaffname',
        'contentplaceholder1_lblemployeename',
      };
      for (final e in doc.querySelectorAll('[id]')) {
        final id = e.id.toLowerCase();
        if (id.contains('logout') ||
            (markers.contains(id) && staffText(e).isNotEmpty))
          return Probe.alive;
      }
      final heading = doc.querySelector('.widget-heading');
      if (home.url.toLowerCase().contains('staffhome.aspx') &&
          heading != null &&
          doc.querySelector('.widget-subheading') != null &&
          staffText(heading).isNotEmpty)
        return Probe.alive;
    }
    return Probe.unknown;
  }

  static Probe classifyProfileDocument(StaffDocument? document) {
    if (document == null || staffServerBase(document.url).isEmpty)
      return Probe.unknown;
    final failure = staffDocumentFailure(
      document.url,
      document.text,
      document.status,
    );
    if (failure == 'SESSION_EXPIRED') return Probe.dead;
    if (failure != null ||
        document.status != 200 ||
        !Uri.parse(document.url).path
            .toLowerCase()
            .endsWith('/staff_p10_detailsv2.aspx'))
      return Probe.unknown;
    final doc = html.parse(document.text);
    return doc.querySelector(
                  '#ContentPlaceHolder1_ImageButton18, #ContentPlaceHolder1_divViewLockProfile input',
                ) !=
                null &&
            doc.querySelector("input[name='__VIEWSTATE']") != null
        ? Probe.alive
        : Probe.unknown;
  }

  static Probe classifyHistoryDocument(StaffDocument? document) {
    if (document == null || staffServerBase(document.url).isEmpty)
      return Probe.unknown;
    final failure = staffDocumentFailure(
      document.url,
      document.text,
      document.status,
    );
    if (failure == 'SESSION_EXPIRED') return Probe.dead;
    if (failure != null ||
        document.status != 200 ||
        !Uri.parse(document.url).path
            .toLowerCase()
            .endsWith('/staff_leaveapplication_applied.aspx'))
      return Probe.unknown;
    final doc = html.parse(document.text);
    final grids = doc
        .querySelectorAll('table[id]')
        .where(
          (e) => RegExp(
            r'(?:^|_)grdLeaveDetails$',
            caseSensitive: false,
          ).hasMatch(e.id),
        );
    final state = doc.querySelector("input[name='__VIEWSTATE']");
    if (grids.isEmpty ||
        state == null ||
        (state.attributes['value'] ?? '').trim().isEmpty)
      return Probe.unknown;
    final text = staffText(grids.first, ' ');
    return RegExp(r'\b\d{2}[-/]\d{2}[-/]\d{4}\b').hasMatch(text) ||
            RegExp(
              r'no\s+records?\s+found',
              caseSensitive: false,
            ).hasMatch(text)
        ? Probe.alive
        : Probe.unknown;
  }

  static bool repairEvidence(List<StaffDocument?> documents) {
    if (documents.length != 3) return false;
    const paths = [
      '/staffhome.aspx',
      '/staff_p10_detailsv2.aspx',
      '/staff_leaveapplication_applied.aspx',
    ];
    final bases = <String>{};
    for (var i = 0; i < 3; i++) {
      final document = documents[i];
      if (document == null || staffServerBase(document.url).isEmpty)
        return false;
      if (![200, 500].contains(document.status) ||
          !Uri.parse(document.url).path.toLowerCase().endsWith(paths[i]))
        return false;
      final text = document.text.toLowerCase();
      if (!text.contains('server error in') ||
          ![
            'system.nullreferenceexception',
            'object reference not set to an instance of an object',
          ].any(text.contains))
        return false;
      bases.add(staffServerBase(document.url).toLowerCase());
    }
    return bases.length == 1;
  }

  Future<Probe> probeContext(StaffHttpSession? session) async {
    if (!isCurrent(session)) return Probe.unknown;
    final ctx = session!;
    if (!ctx.authenticated) return Probe.dead;
    final base = ctx.base ?? activeServerBase;
    var home = await fetchHome(ctx, base), verdict = Probe.unknown;
    verdict = classifyHome(home);
    StaffDocument? profile, history;
    if ([Probe.dead, Probe.unknown].contains(verdict) && isCurrent(ctx)) {
      final original = verdict;
      if (staffServerBase(base).isNotEmpty)
        profile = await getDocument(ctx, base, profilePath);
      final confirmation = classifyProfileDocument(profile);
      if (confirmation == Probe.alive) {
        verdict = Probe.alive;
        home = profile;
      } else if (original == Probe.dead) {
        verdict = confirmation;
      } else {
        verdict = Probe.unknown;
      }
    }
    if (verdict == Probe.unknown && isCurrent(ctx)) {
      if (staffServerBase(base).isNotEmpty)
        history = await getDocument(ctx, base, historyPath);
      if (classifyHistoryDocument(history) == Probe.alive && isCurrent(ctx)) {
        verdict = Probe.alive;
        home = history;
      }
    }
    if (!isCurrent(ctx)) return Probe.unknown;
    if (verdict == Probe.unknown &&
        profile != null &&
        history != null &&
        classifyProfileDocument(profile) == Probe.dead &&
        classifyHistoryDocument(history) == Probe.dead)
      verdict = Probe.dead;
    if (verdict == Probe.unknown && repairEvidence([home, profile, history]))
      return Probe.repairRequired;
    if (verdict == Probe.alive && home != null && isCurrent(ctx)) {
      final actual = staffServerBase(home.url);
      if (actual.isNotEmpty &&
          actual.toLowerCase() != activeServerBase.toLowerCase())
        await saveActiveSessionInfo(actual);
      await registry.persist(ctx);
    }
    return verdict;
  }

  Future<Map<String, dynamic>?> trySavedSession(String user) async {
    final session = registry.current();
    if (session == null) return null;
    final saved = registry.sessionUser(session).isNotEmpty
        ? registry.sessionUser(session)
        : activeStaffUser;
    if (saved.isEmpty || staffLower(saved) != staffLower(user)) {
      await forgetSavedSession();
      return null;
    }
    progress?.call(30, 'Checking Staff saved session...');
    final base = session.base ?? activeServerBase;
    var document = await fetchHome(session, base);
    var verdict = classifyHome(document);
    // Reuse the same protected-page proof as probeContext when Home alone is
    // inconclusive. Explicit Home expiry and force-fresh keep their source flow.
    if (verdict == Probe.unknown &&
        staffServerBase(base).isNotEmpty &&
        isCurrent(session)) {
      final profile = await getDocument(session, base, profilePath);
      if (classifyProfileDocument(profile) == Probe.alive) {
        verdict = Probe.alive;
        document = profile;
      } else if (isCurrent(session)) {
        final history = await getDocument(session, base, historyPath);
        if (classifyHistoryDocument(history) == Probe.alive) {
          verdict = Probe.alive;
          document = history;
        }
      }
    }
    Map<String, dynamic> changed() => failure(
      'ACCOUNT_CHANGED',
      'Staff session changed during saved login verification.',
    );
    if (!isCurrent(session)) return changed();
    if (verdict == Probe.alive && document != null) {
      final actual = staffServerBase(document.url);
      final live = actual.isEmpty ? base : actual;
      await saveActiveSessionInfo(live, user);
      if (!isCurrent(session)) return changed();
      await registry.persist(session);
      if (!isCurrent(session)) return changed();
      progress?.call(100, 'Staff Portal Live (saved session)!');
      return successPayload(live, user, cached: true);
    }
    if (verdict == Probe.dead) {
      await forgetSavedSession();
      return null;
    }
    return failure(
      'SESSION_UNCERTAIN',
      'Staff session could not be verified. Please retry when the portal is available.',
    );
  }

  static bool captchaRejection(String message) =>
      message.toLowerCase().contains('captcha');
  static bool credentialRejection(String message) => [
    'invalid',
    'wrong password',
    'user does not exist',
    'valid username',
    'credential',
  ].any(message.toLowerCase().contains);
  static bool activeSessionNotice(String message) => [
    'already',
    'terminate',
    'previous session',
    'another device',
  ].any(message.toLowerCase().contains);
  Future<Map<String, dynamic>> freshLogin(
    String user,
    String password,
    double deadline,
  ) async {
    progress?.call(15, 'Selecting fastest Staff server...');
    final (selected, _, latency) = await servers.selectFastestServer();
    final best = selected.replaceFirst(RegExp(r'/+$'), '');
    final candidates = [
      best,
      ...staffServers.where((s) => s.toLowerCase() != best.toLowerCase()),
    ];
    var node = 0, attempt = 0;
    var lastPortalMessage = '';
    while (attempt < maxCaptchaAttempts) {
      OperationCancellation.current?.check();
      if (monotonic() > deadline)
        return failure('TIMEOUT', 'Staff login timed out.');
      final base = candidates[node];
      attempt++;
      progress?.call(
        (45 + attempt * 5).clamp(0, 85),
        'Solving Staff CAPTCHA (attempt $attempt)...',
      );
      final session = registry.newSession();
      var committed = false;
      try {
        late StaffLoginOutcome outcome;
        try {
          outcome = await loginOnce(
            session,
            base,
            user,
            password,
            solveCaptcha,
          );
        } on OperationCancelled {
          rethrow;
        } catch (error) {
          final transport =
              error is SocketException ||
              error is HttpException ||
              error is HandshakeException ||
              error is TimeoutException;
          if (error is! StaffHttpError && !transport) rethrow;
          final code = error is StaffHttpError
              ? error.code
              : 'PORTAL_UNAVAILABLE';
          if (nodeErrorCodes.contains(code)) {
            servers.penalizeNode(base);
            node++;
            attempt--;
            if (node >= candidates.length)
              return failure(
                'PORTAL_DOWN',
                'Could not connect to any Staff Corner server.',
              );
            continue;
          }
          return failure(code, error.toString());
        }
        if (outcome.success) {
          await registry.install(session);
          committed = true;
          await saveActiveSessionInfo(base, user);
          progress?.call(100, 'Staff Portal Live on HOME!');
          return successPayload(base, user, cached: false, latency: latency);
        }
        final message = outcome.portalMessage.isNotEmpty
            ? outcome.portalMessage
            : outcome.message;
        if (outcome.portalMessage.isNotEmpty) {
          lastPortalMessage = outcome.portalMessage;
        }
        if (outcome.code == 'CAPTCHA_UNREADABLE' ||
            outcome.code == 'LOGIN_NOT_VERIFIED' && captchaRejection(message)) {
          await sleep(const Duration(milliseconds: 300));
          continue;
        }
        if (outcome.code == 'LOGIN_NOT_VERIFIED' &&
            credentialRejection(message))
          return _loginFailure(
            'INVALID_CREDENTIALS',
            'Invalid Staff ID or Password.',
            portalMessage: outcome.portalMessage,
          );
        if (outcome.code == 'LOGIN_NOT_VERIFIED' &&
            activeSessionNotice(message))
          return _loginFailure(
            'ACTIVE_SESSION_EXISTS',
            outcome.message,
            portalMessage: outcome.portalMessage,
          );
        return _loginFailure(
          outcome.code,
          outcome.message,
          portalMessage: outcome.portalMessage,
        );
      } finally {
        if (!committed) {
          try {
            await session.close();
          } catch (_) {}
        }
      }
    }
    return _loginFailure(
      'LOGIN_FAILED',
      'Staff login failed after multiple attempts.',
      portalMessage: lastPortalMessage,
    );
  }

  Future<Map<String, dynamic>> executeLogin(
    String user,
    String password, {
    bool forceFresh = false,
  }) async {
    user = user.trim();
    if (user.isEmpty || password.trim().isEmpty)
      return failure('NO_CREDENTIALS', 'Staff ID and password are required.');
    final deadline = monotonic() + loginBudgetSeconds;
    try {
      await initialize();
      if (forceFresh) {
        await forgetSavedSession();
      } else {
        final reused = await trySavedSession(user);
        if (reused != null) return reused;
      }
      return await freshLogin(user, password, deadline);
    } on OperationCancelled {
      rethrow;
    } catch (error) {
      return failure('ERROR', 'Staff login error: $error');
    }
  }
}
