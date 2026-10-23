/// HTTP authentication/probe integration from core/staff_backend.py.
/// Native PDF resources reuse this coordinator and the same Staff HTTP registry.
import 'dart:async';

import '../../../core/direct/async_primitives.dart';
import '../../../core/direct/coordinator.dart';
import '../../../core/direct/runtime_slot.dart';
import '../../shaladarpan/direct/captcha_onnx.dart';
import 'auth_manager.dart';
import 'http_auth.dart';
import 'http_session.dart';
import 'staff_read_service.dart';
import 'native_print_service.dart';
import 'leave_apply_service.dart';

class StaffHttpBackend implements PortalBackend {
  StaffHttpBackend(this.auth);
  final StaffAuthManager auth;
  @override
  Object? currentContext() => auth.registry.current();
  @override
  Future<Map<String, dynamic>> authenticate(
    String user,
    String password,
    bool forceFresh,
  ) => auth.executeLogin(user, password, forceFresh: forceFresh);
  @override
  Future<Probe> probe(Object context) => context is StaffHttpSession
      ? auth.probeContext(context)
      : Future.value(Probe.unknown);
}

/// Match Python StaffCoordinator._res_lock: all Staff WebForms resources share
/// the coordinator lease, including timed-out/settling operations.
class StaffCoordinator extends PortalCoordinator {
  StaffCoordinator({required super.backend})
    : super(name: 'staff', displayName: 'Staff Corner');
  @override
  Future<T> lease<T>(
    String resource,
    Kind kind,
    Future<T> Function(PortalLease) operation, {
    double? wait,
    OperationCancellation? cancellation,
  }) => super.lease(
    'staff.session',
    kind,
    (lease) => operation(PortalLease(lease.generation, resource, lease.kind)),
    wait: wait,
    cancellation: cancellation,
  );
}

class StaffDirectRuntime {
  StaffDirectRuntime._(
    this.registry,
    this.auth,
    this.captcha,
    this.coordinator,
  );
  final StaffHttpAuth registry;
  final StaffAuthManager auth;
  final SchoolOnnxCaptcha captcha;
  final StaffCoordinator coordinator;
  late final reads = StaffReadService(
    registry: registry,
    coordinator: coordinator,
  );
  late final prints = StaffNativePrintService(
    registry: registry,
    coordinator: coordinator,
  );
  late final leaves = StaffLeaveApplyService(
    registry: registry,
    coordinator: coordinator,
    reads: reads,
  );
  static final _slot = RuntimeSlot<StaffDirectRuntime>(
    create: _create,
    close: (runtime) => runtime._closeSafely(),
  );
  static StaffDirectRuntime? get current => _slot.current;
  static Future<StaffDirectRuntime> get() => _slot.get();

  static Future<StaffDirectRuntime> _create() async {
    final captcha = SchoolOnnxCaptcha();
    final registry = StaffHttpAuth();
    final auth = StaffAuthManager(
      registry: registry,
      solveCaptcha: captcha.solve,
    );
    await auth.initialize();
    final runtime = StaffDirectRuntime._(
      registry,
      auth,
      captcha,
      StaffCoordinator(backend: StaffHttpBackend(auth)),
    );
    return runtime;
  }

  /// Retires the live runtime. A failed retirement keeps its barrier and is
  /// retried by the next call / login (see [RuntimeSlot]).
  static Future<void> reset() => _slot.retire();

  Future<void> close() => _slot.retire(this);

  Future<void> _closeSafely() async {
    await coordinator.shutdown();
    await registry.closeSession();
    await captcha.close();
  }
}
