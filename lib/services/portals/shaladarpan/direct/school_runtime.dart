/// School-only equivalents of core/sd_backend.py and core/instances.py.
/// The existing UI attaches an adapter to this one shared session/coordinator.
import 'dart:io';

import '../../../core/direct/coordinator.dart';
import '../../../core/direct/runtime_slot.dart';
import 'auth_manager.dart';
import 'captcha_onnx.dart';

class SchoolHttpBackend implements PortalBackend {
  SchoolHttpBackend(this.auth);
  final SchoolAuthManager auth;
  Object? _session;
  (String, String)? _identity;
  @override
  Object? currentContext() {
    final identity = auth.sessionIdentity;
    if (identity == null) {
      _identity = null;
      _session = null;
      return null;
    }
    if (_session == null || _identity != identity) {
      _identity = identity;
      _session = Object();
    }
    return _session;
  }

  @override
  Future<Map<String, dynamic>> authenticate(
    String user,
    String password,
    bool forceFresh,
  ) async {
    final result = await auth.executeLogin(
      user,
      password,
      forceFresh: forceFresh,
    );
    if (result['success'] == true) {
      if (currentContext() == null)
        return {
          'success': false,
          'code': 'SESSION_EXPIRED',
          'message': 'Login did not persist an authenticated HTTP session.',
        };
    }
    return result;
  }

  @override
  Future<Probe> probe(Object context) async {
    if (!identical(currentContext(), context)) return Probe.unknown;
    final verdict = await auth.probeContext(base: auth.activeServerBase);
    if (!identical(currentContext(), context)) return Probe.unknown;
    return switch (verdict) {
      SchoolProbe.alive => Probe.alive,
      SchoolProbe.dead => Probe.dead,
      SchoolProbe.repairRequired => Probe.repairRequired,
      SchoolProbe.unknown => Probe.unknown,
    };
  }
}

class SchoolDirectRuntime {
  SchoolDirectRuntime._(this.auth, this.captcha, this.coordinator);
  final SchoolAuthManager auth;
  final SchoolOnnxCaptcha captcha;
  final PortalCoordinator coordinator;
  static final _slot = RuntimeSlot<SchoolDirectRuntime>(
    create: _create,
    close: (runtime) => runtime._closeSafely(),
  );

  static Future<SchoolDirectRuntime> get() => _slot.get();

  static Future<SchoolDirectRuntime> _create() async {
    final captcha = SchoolOnnxCaptcha();
    PortalCoordinator? coordinator;
    final auth = SchoolAuthManager(
      solveCaptcha: captcha.solve,
      rememberCredentials: (user, password) =>
          coordinator?.rememberCredentials(user, password),
    );
    await auth.initialize();
    final actual = PortalCoordinator(
      name: 'sd',
      backend: SchoolHttpBackend(auth),
      credentialsFallback: () {
        final user = (Platform.environment['SCHOOL_ID'] ?? '').trim();
        final password = Platform.environment['SCHOOL_PASSWORD'] ?? '';
        return user.isNotEmpty && password.isNotEmpty ? (user, password) : null;
      },
    );
    coordinator = actual;
    return SchoolDirectRuntime._(auth, captcha, actual);
  }

  /// Never creates a new session manager while an unsettled old operation could
  /// still persist cookies: a failed retirement keeps its barrier, and the next
  /// [get] / [close] retries it (see [RuntimeSlot]).
  Future<void> close() => _slot.retire(this);

  Future<void> _closeSafely() async {
    await coordinator.shutdown();
    await auth.closeAuthenticatedClients();
    await captcha.close();
  }
}
