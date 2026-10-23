/// RajSIMS backend/coordinator auth binding from core/rajsims_backend.py.
/// MDM workers share the same authenticated context and coordinator.
library;

import 'dart:async';

import '../../../core/direct/coordinator.dart';
import '../../../core/direct/coordinator_config.dart';
import '../../../core/direct/runtime_slot.dart';
import 'auth_manager.dart';
import 'captcha_onnx.dart';
import 'http_auth.dart';
import 'http_context.dart';
import 'rajsims_sso_httpx.dart';
import 'rajsims_mdm_worker.dart';
import 'rajsims_mdm_service.dart';
import 'sso_captcha.dart';

const rajsimsCoordinatorConfig = CoordinatorConfig(
  authTimeout: 90,
  keepaliveInterval: 300,
  recoverCooldown: 60,
  autoRecoveryLimit: 2,
  autoRecoveryWindow: 300,
  maxAttempts: 2,
);
const rajsimsUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

class RajsimsHttpBackend implements PortalBackend {
  const RajsimsHttpBackend(this.registry);
  final RajsimsHttpAuth registry;
  @override
  Object? currentContext() => registry.current();
  @override
  Future<Map<String, dynamic>> authenticate(
    String user,
    String password,
    bool forceFresh,
  ) => registry.auth.executeLogin(user, password, forceFresh: forceFresh);
  @override
  Future<Probe> probe(Object context) => context is RajsimsHttpContext
      ? registry.auth.probe(context)
      : Future.value(Probe.unknown);
}

class RajsimsDirectRuntime {
  RajsimsDirectRuntime._(this.registry, this.captcha, this.coordinator);
  final RajsimsHttpAuth registry;
  final RajssoOnnxCaptcha captcha;
  final PortalCoordinator coordinator;
  late final RajsimsMdmWorker worker;
  late final RajsimsMdmService mdm;
  static final _slot = RuntimeSlot<RajsimsDirectRuntime>(
    create: _create,
    close: (runtime) => runtime._closeSafely(),
  );
  static RajsimsDirectRuntime? get current => _slot.current;
  // Explicit version avoids guessing between the two different Python input
  // normalizations. Supply the installed backend version with --dart-define.
  static const installedDdddocrVersion = String.fromEnvironment(
    'RAJSHALA_DDDDOCR_VERSION',
  );

  static Future<RajsimsDirectRuntime> get() => _slot.get();

  /// Python's full installer supplies the same browser User-Agent to SSO and
  /// Gateway transports. Separate cookie jars still follow their context owner.
  static NativeRajsimsHttpTransport createHttpTransport() =>
      NativeRajsimsHttpTransport(userAgent: rajsimsUserAgent);

  static Future<RajsimsDirectRuntime> _create() async {
    final profile = rajssoOcrProfileForVersion(installedDdddocrVersion);
    final captcha = RajssoOnnxCaptcha(profile: profile);
    final sso = RajssoHttpx(
      solveCaptcha: (bytes) async =>
          extractSixDigits(await captcha.solve(bytes)),
      clientFactory: createHttpTransport,
    );
    late RajsimsMdmWorker worker;
    final registry = RajsimsHttpAuth(
      sso: sso,
      clearWorkerUserInfoCache: () => worker.clearUserInfoCache(),
    );
    final runtime = RajsimsDirectRuntime._(
      registry,
      captcha,
      PortalCoordinator(
        name: 'rajsims',
        displayName: 'RajSIMS Portal',
        backend: RajsimsHttpBackend(registry),
        config: rajsimsCoordinatorConfig,
      ),
    );
    worker = RajsimsMdmWorker(
      auth: registry.auth,
      currentContext: registry.current,
      clientFactory: createHttpTransport,
    );
    runtime.worker = worker;
    runtime.mdm = RajsimsMdmService(
      registry: registry,
      worker: worker,
      coordinator: runtime.coordinator,
    );
    return runtime;
  }

  /// Retires the live runtime. A failed retirement keeps its barrier and is
  /// retried by the next call / login (see [RuntimeSlot]).
  static Future<void> reset() => _slot.retire();

  Future<void> close() => _slot.retire(this);

  Future<void> _closeSafely() async {
    await coordinator.shutdown();
    await worker.close();
    await registry.closeSession();
    await captcha.close();
  }
}
