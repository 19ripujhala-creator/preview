/// Native HTTP (uses_pages=False) conversion of core/coordinator.py.
/// Browser-page branches are intentionally outside the School HTTP migration.
import 'dart:async';
import 'dart:math';

import 'async_primitives.dart';
import 'coordinator_config.dart';
import 'errors.dart';
import 'portal_diagnostics.dart';

enum Health {
  idle,
  authenticating,
  ready,
  unknown,
  expired,
  recovering,
  failed,
}

enum Probe { alive, dead, repairRequired, unknown }

enum Kind { read, workflow, mutation }

enum Verdict { recovered, alreadyRecovered, alive, unknown, failed }

abstract interface class PortalBackend {
  Object? currentContext();
  Future<Map<String, dynamic>> authenticate(
    String user,
    String password,
    bool forceFresh,
  );
  Future<Probe> probe(Object context);
}

class PortalLease {
  const PortalLease(this.generation, this.resource, this.kind);
  final int generation;
  final String resource;
  final Kind kind;
  Object? get page => null;
}

class _Outcome {
  _Outcome(this.generation);
  Map<String, dynamic>? result;
  ErrorKind? error;
  Object? exception;
  int generation;
  bool started = false,
      timedOut = false,
      abortBeforeStart = false,
      done = false;
  Future<_Outcome>? owner;
  final cancellation = OperationCancellation();
}

class _ActiveOperation {
  _ActiveOperation(this.kind, this.resource, this.cancellation);
  final Kind kind;
  final String resource;
  final OperationCancellation cancellation;
}

class PortalCoordinator {
  PortalCoordinator({
    required this.name,
    required this.backend,
    this.config = const CoordinatorConfig(),
    this.displayName = 'Shala Darpan',
    this.credentialsFallback,
  }) {
    config.validate();
    _context = backend.currentContext();
    if (_context != null) {
      _generation = 1;
      _health = Health.unknown;
    }
  }
  final String name, displayName;
  final PortalBackend backend;
  final CoordinatorConfig config;
  final (String, String)? Function()? credentialsFallback;
  final _lifecycle = AsyncMutex();
  final Map<String, AsyncMutex> _resources = {};
  final _open = AsyncSignal(set: true), _idle = AsyncSignal(set: true);
  final Set<_ActiveOperation> _active = {};
  final Set<Future<dynamic>> _background = {};
  final _clock = Stopwatch()..start();
  final double _clockOrigin = DateTime.now().millisecondsSinceEpoch / 1000;
  final Object _leaseZone = Object();
  Health _health = Health.idle;
  Object? _context;
  int _generation = 0, _unknownStreak = 0;
  bool _barrier = false, _closed = false, _authBlocked = false;
  bool _signedOut = false, _degradedPending = false;
  (String, String)? _credentials;
  double _lastOk = 0, _lastRecoverAttempt = 0;
  bool? _lastRecoverOk;
  final List<double> _recoveryAttempts = [], _repairAttempts = [];
  Future<Probe>? _probeInFlight;
  (Object, int)? _probeKey;
  Timer? _keepalive;
  bool _keepaliveEnabled = false;
  Future<void>? _shutdownTask;

  int get generation => _generation;
  Health get health => _health;
  double get _now => _clockOrigin + _clock.elapsedMicroseconds / 1000000;
  int get _activeMutations =>
      _active.where((e) => e.kind == Kind.mutation).length;
  bool contextIsCurrent() =>
      _context != null && identical(backend.currentContext(), _context);
  bool hasPendingWork() => _active.isNotEmpty || _background.isNotEmpty;
  void rememberCredentials(String user, String password) =>
      _credentials = (user, password);
  void forgetCredentials() => _credentials = null;
  (String, String)? _resolveCredentials() =>
      _signedOut ? null : _credentials ?? credentialsFallback?.call();
  Duration _duration(double seconds) =>
      Duration(microseconds: (max(0, seconds) * 1000000).round());

  Map<String, dynamic> status() => {
    'name': name,
    'health': _health.name.toUpperCase(),
    'generation': _generation,
    'active_operations': _active.length,
    'active_mutations': _activeMutations,
    'active_mutation_resources':
        (_active
            .where((e) => e.kind == Kind.mutation)
            .map((e) => e.resource)
            .toSet()
            .toList()
          ..sort()),
    'barrier': _barrier,
    'last_ok_age_s': _lastOk == 0 ? null : ((_now - _lastOk) * 10).round() / 10,
    'worker_pages': <String>[],
    'transport': 'http',
    'keepalive': _keepaliveEnabled,
    'has_credentials': _resolveCredentials() != null,
    'auth_blocked': _authBlocked,
    'auto_recovery_attempts': _recoveryAttempts.length,
    'closed': _closed,
    'context_current': contextIsCurrent(),
    'pending_background_tasks': _background.length,
  };

  void markAlive([int? observedGeneration]) {
    if (_closed ||
        (observedGeneration != null && observedGeneration != _generation) ||
        !contextIsCurrent())
      return;
    _lastOk = _now;
    _unknownStreak = 0;
    _degradedPending = false;
    if (const {Health.unknown, Health.idle, Health.expired}.contains(_health)) {
      _health = Health.ready;
    }
  }

  void _assertOpen() {
    if (_closed)
      throw CoordinatorError(
        ErrorKind.serverError,
        '$displayName coordinator is shut down.',
      );
  }

  Future<T> _track<T>(Future<T> future) {
    _background.add(future);
    future.then<void>(
      (_) {
        _background.remove(future);
      },
      onError: (Object _, StackTrace __) {
        _background.remove(future);
      },
    );
    return future;
  }

  void _raiseBarrier() {
    _barrier = true;
    _open.clear();
  }

  void _lowerBarrier() {
    if (_closed) return;
    _barrier = false;
    _open.set();
  }

  CoordinatorError _barrierError() => CoordinatorError(
    ErrorKind.recoveryInProgress,
    '$displayName session is synchronizing. Please try again shortly.',
  );
  CoordinatorError _expiredError() => CoordinatorError(
    ErrorKind.sessionExpired,
    '$displayName session expired and automatic login failed.',
  );

  Future<void> _drain() async {
    final started = _now;
    while (_active.isNotEmpty) {
      final age = _now - started;
      if (_activeMutations > 0) {
        if (age >= config.mutationDrainTimeout) return;
      } else if (age >= config.readDrainTimeout) {
        for (final operation in List.of(_active)) {
          if (operation.kind != Kind.mutation) operation.cancellation.cancel();
        }
        try {
          await _idle.wait(_duration(config.readCancelGrace));
        } catch (_) {}
        return;
      }
      try {
        await _idle.wait(const Duration(milliseconds: 100));
      } on TimeoutException {}
    }
    final probe = _probeInFlight;
    if (probe != null) {
      try {
        await probe.timeout(_duration(config.probeTimeout));
      } on TimeoutException {}
    }
  }

  bool get _drained => _active.isEmpty && _probeInFlight == null;

  Future<T> lease<T>(
    String resource,
    Kind kind,
    Future<T> Function(PortalLease) operation, {
    double? wait,
    OperationCancellation? cancellation,
  }) async {
    _assertOpen();
    if (Zone.current[_leaseZone] == true) {
      throw CoordinatorError(
        ErrorKind.serverError,
        'Nested leases on the same coordinator are not supported.',
      );
    }
    final seconds = max(0.0, wait ?? config.defaultLeaseWait);
    final deadline = _now + seconds;
    final lock = _resources.putIfAbsent(resource, AsyncMutex.new);
    late void Function() release;
    try {
      release = await lock.acquire(
        timeout: _duration(seconds),
        cancellation: cancellation,
      );
    } on TimeoutException {
      throw CoordinatorError(
        ErrorKind.pageBusy,
        "'$resource' is busy with another operation. Please try again shortly.",
      );
    }
    _ActiveOperation? record;
    try {
      while (_barrier || _probeInFlight != null) {
        _assertOpen();
        cancellation?.check();
        final remaining = deadline - _now;
        if (remaining <= 0) throw _barrierError();
        try {
          final probe = _probeInFlight;
          if (probe != null) {
            await probe.timeout(_duration(remaining));
          } else {
            await _open.wait(_duration(remaining));
          }
        } on TimeoutException {
          throw _barrierError();
        }
      }
      cancellation?.check();
      _assertOpen();
      if (!contextIsCurrent())
        throw CoordinatorError(
          ErrorKind.browserError,
          'Registered portal session changed before admission.',
        );
      if (!const {Health.ready, Health.unknown}.contains(_health)) {
        throw CoordinatorError(
          ErrorKind.sessionExpired,
          'Session is no longer ready for admission.',
        );
      }
      record = _ActiveOperation(
        kind,
        resource,
        cancellation ?? OperationCancellation(),
      );
      _active.add(record);
      _idle.clear();
      final token = record.cancellation;
      return await runZoned(
        () => operation(PortalLease(_generation, resource, kind)),
        zoneValues: {_leaseZone: true, OperationCancellation.zoneKey: token},
      );
    } finally {
      if (record != null) _active.remove(record);
      if (_active.isEmpty) _idle.set();
      release();
    }
  }

  Future<Probe> _probe() async {
    _assertOpen();
    final context = _context;
    final observed = _generation;
    if (context == null || _active.isNotEmpty || !contextIsCurrent())
      return Probe.unknown;
    if (_probeInFlight != null) {
      if (_probeKey == (context, observed)) return await _probeInFlight!;
      return Probe.unknown;
    }
    final task = _track(_probeImpl(context, observed));
    _probeKey = (context, observed);
    _probeInFlight = task;
    try {
      return await task;
    } finally {
      if (identical(_probeInFlight, task)) {
        _probeInFlight = null;
        _probeKey = null;
      }
    }
  }

  Future<Probe> _probeImpl(Object context, int observed) async {
    Probe verdict;
    final cancellation = OperationCancellation();
    final request = runZoned(
      () => PortalDiagnostics.measure(
        PortalPhase.sessionProbe,
        () => backend.probe(context),
      ),
      zoneValues: {OperationCancellation.zoneKey: cancellation},
    );
    try {
      verdict = await request.timeout(_duration(config.probeTimeout));
    } catch (_) {
      cancellation.cancel();
      try {
        await request;
      } catch (_) {}
      verdict = Probe.unknown;
    }
    if (_closed ||
        observed != _generation ||
        !identical(context, _context) ||
        !identical(backend.currentContext(), context))
      return Probe.unknown;
    if (verdict == Probe.alive) {
      markAlive(observed);
    } else if (verdict == Probe.dead) {
      if (const {Health.ready, Health.unknown}.contains(_health))
        _health = Health.expired;
    } else {
      _unknownStreak++;
      if (verdict == Probe.repairRequired) _health = Health.unknown;
    }
    return verdict;
  }

  Future<Probe> _confirmDead(int observed, Object context) async {
    if (_closed || observed != _generation || !identical(context, _context))
      return Probe.unknown;
    await Future<void>.delayed(_duration(config.probeConfirmDelay));
    if (_closed || observed != _generation || !identical(context, _context))
      return Probe.unknown;
    if (_active.isNotEmpty && _health == Health.ready) return Probe.alive;
    return _probe();
  }

  void _syncContext(bool success) {
    final old = _context;
    _context = backend.currentContext();
    if (success && _context != null) {
      _degradedPending = false;
      _generation++;
      _health = Health.ready;
      _lastRecoverOk = true;
      markAlive(_generation);
    } else {
      if (!identical(old, _context)) _generation++;
      _health = _context != null ? Health.expired : Health.failed;
    }
  }

  Future<(bool, Map<String, dynamic>)> _authenticateLocked(
    (String, String) credentials,
    bool forceFresh,
  ) async {
    _assertOpen();
    _health = Health.authenticating;
    final cancellation = OperationCancellation();
    final auth = _track(
      runZoned(
        () => backend.authenticate(credentials.$1, credentials.$2, forceFresh),
        zoneValues: {OperationCancellation.zoneKey: cancellation},
      ),
    );
    Map<String, dynamic> result;
    try {
      try {
        result = await auth.timeout(_duration(config.authTimeout));
      } on TimeoutException {
        try {
          result = await auth.timeout(
            _duration(max(1, config.authSettleGrace)),
          );
        } on TimeoutException {
          cancellation.cancel();
          // Never release the lifecycle barrier while backend code can still
          // persist a late session. Cooperative HTTP auth checks this token.
          try {
            await auth;
          } catch (_) {}
          result = {
            'success': false,
            'code': 'TIMEOUT',
            'message': 'Login timed out.',
          };
        }
      }
    } catch (error) {
      result = {'success': false, 'code': 'ERROR', 'message': error.toString()};
    }
    var ok = result['success'] == true;
    if (_closed) {
      _health = Health.failed;
      return (
        false,
        {
          ...result,
          'success': false,
          'code': 'SHUTDOWN',
          'message': '$displayName coordinator is shut down.',
        },
      );
    }
    _syncContext(ok && backend.currentContext() != null);
    ok = ok && _health == Health.ready;
    _lastRecoverOk = ok;
    if (ok) {
      _authBlocked = false;
      rememberCredentials(credentials.$1, credentials.$2);
      _startKeepalive();
    } else if (result['code'] == 'INVALID_CREDENTIALS') {
      _authBlocked = true;
    }
    return (ok, result);
  }

  Future<Map<String, dynamic>> authenticate(
    String user,
    String password, {
    bool forceFresh = false,
  }) => _track(
    _lifecycle.protect(() async {
      _assertOpen();
      user = user.trim();
      if (user.isEmpty || password.isEmpty) {
        return {
          'success': false,
          'code': 'NO_CREDENTIALS',
          'message': '$displayName credentials required.',
        };
      }
      final same = _credentials == (user, password);
      final previous = _credentials;
      if (!forceFresh &&
          same &&
          _context != null &&
          contextIsCurrent() &&
          const {Health.ready, Health.unknown}.contains(_health)) {
        final recent = _lastOk > 0 && _now - _lastOk <= config.probeMaxAge;
        final activeVerified = _active.isNotEmpty && _health == Health.ready;
        final verdict = recent || activeVerified ? Probe.alive : await _probe();
        if (const {Probe.alive, Probe.unknown}.contains(verdict) &&
            contextIsCurrent() &&
            const {Health.ready, Health.unknown}.contains(_health)) {
          if (verdict == Probe.unknown) _health = Health.unknown;
          rememberCredentials(user, password);
          _lastRecoverOk = true;
          _startKeepalive();
          return {
            'success': true,
            'cached': true,
            'generation': _generation,
            'session_verified': verdict == Probe.alive,
            'message': verdict == Probe.alive
                ? 'Session already live.'
                : 'Existing session retained; portal operation will verify it.',
          };
        }
      }
      _raiseBarrier();
      try {
        await _drain();
        if (!_drained)
          return {
            'success': false,
            'code': 'BUSY',
            'message':
                'A portal mutation/read is still running. Try again shortly.',
          };
        _signedOut = false;
        _authBlocked = false;
        _recoveryAttempts.clear();
        final (ok, result) = await _authenticateLocked((
          user,
          password,
        ), forceFresh || _context != null);
        // The caller asked for a different account and that login failed. The
        // previous account's credentials must not stay armed: otherwise the next
        // read, keepalive or expiry would silently log the old account back in.
        if (!ok &&
            !_closed &&
            previous != null &&
            previous != (user, password) &&
            _credentials == previous) {
          _credentials = null;
          // A fallback may still contain the retired account. Only an explicit
          // successful login may re-arm recovery after a failed account switch.
          _signedOut = true;
          _authBlocked = true;
        }
        return {...result, 'success': ok, 'generation': _generation};
      } finally {
        _lowerBarrier();
      }
    }),
  );

  Future<Map<String, dynamic>> logout(
    Future<void> Function() cleanup,
  ) => _track(
    _lifecycle.protect(() async {
      _assertOpen();
      _raiseBarrier();
      try {
        await _drain();
        if (!_drained)
          return {
            'success': false,
            'code': 'BUSY',
            'message':
                'Portal work is still running. Retry logout after it settles.',
          };
        _signedOut = true;
        _credentials = null;
        _authBlocked = true;
        _health = Health.idle;
        _generation++;
        _context = null;
        await cleanup();
        return {'success': true, 'message': 'Portal session signed out.'};
      } finally {
        _lowerBarrier();
      }
    }),
  );

  Future<Verdict> _recoverLocked(
    String reason, {
    bool repairAuthorized = false,
  }) async {
    if (_degradedPending && !repairAuthorized)
      return _repairDegradedLocked(reason);
    final credentials = _resolveCredentials();
    if (credentials == null || _authBlocked) {
      _health = _context != null ? Health.expired : Health.failed;
      return Verdict.failed;
    }
    final now = _now;
    if (_lastRecoverOk == false &&
        now - _lastRecoverAttempt < config.recoverCooldown) {
      return Verdict.failed;
    }
    _recoveryAttempts.removeWhere(
      (t) => now - t >= max(1, config.autoRecoveryWindow),
    );
    if (config.autoRecoveryLimit > 0 &&
        _recoveryAttempts.length >= config.autoRecoveryLimit) {
      _health = _context != null ? Health.expired : Health.failed;
      return Verdict.failed;
    }
    _health = Health.recovering;
    _raiseBarrier();
    try {
      await _drain();
      if (!_drained) {
        _health = _context != null ? Health.expired : Health.failed;
        return Verdict.failed;
      }
      _lastRecoverAttempt = _now;
      _recoveryAttempts.add(_lastRecoverAttempt);
      final (ok, _) = await _authenticateLocked(credentials, _context != null);
      _lastRecoverOk = ok;
      return ok ? Verdict.recovered : Verdict.failed;
    } finally {
      _lowerBarrier();
    }
  }

  Future<Verdict> _repairDegradedLocked(String reason) async {
    _degradedPending = true;
    final now = _now;
    _repairAttempts.removeWhere(
      (t) => now - t >= max(1, config.degradedRecoveryWindow),
    );
    if (_repairAttempts.isNotEmpty &&
        (now - _repairAttempts.last < max(1, config.degradedRecoveryCooldown) ||
            _repairAttempts.length >= config.degradedRecoveryLimit)) {
      _health = Health.unknown;
      return Verdict.unknown;
    }
    if (_activeMutations > 0 || _resolveCredentials() == null || _authBlocked) {
      return Verdict.unknown;
    }
    _repairAttempts.add(now);
    return _recoverLocked(
      'protected documents unavailable: $reason',
      repairAuthorized: true,
    );
  }

  Future<Verdict> handleExpiry(
    int observedGeneration,
    String reason, {
    bool assumeDead = false,
  }) => _track(
    _lifecycle.protect(() async {
      _assertOpen();
      if (_generation != observedGeneration && _health == Health.ready) {
        return Verdict.alreadyRecovered;
      }
      _raiseBarrier();
      try {
        if (_active.isNotEmpty) {
          await _drain();
          if (!_drained) return Verdict.unknown;
        }
        final context = _context;
        if (!assumeDead && context != null) {
          final observed = _generation;
          final probe = await _probe();
          if (probe == Probe.alive) return Verdict.alive;
          if (probe == Probe.unknown) return Verdict.unknown;
          final confirm = await _confirmDead(observed, context);
          if (confirm == Probe.alive) return Verdict.alive;
          if (confirm == Probe.unknown) return Verdict.unknown;
          if (probe == Probe.repairRequired ||
              confirm == Probe.repairRequired) {
            if (probe != Probe.repairRequired ||
                confirm != Probe.repairRequired)
              return Verdict.unknown;
            return await _repairDegradedLocked(reason);
          }
        }
        return await _recoverLocked(reason);
      } finally {
        _lowerBarrier();
      }
    }),
  );
  Future<Verdict> recover([String reason = 'manual']) =>
      handleExpiry(_generation, reason);

  Future<void> ensureReady(Kind kind, {double? wait}) async {
    _assertOpen();
    if (_context != null && !contextIsCurrent()) _health = Health.expired;
    final seconds = max(0.0, wait ?? config.defaultLeaseWait);
    if (_lifecycle.locked) {
      try {
        final release = await _lifecycle.acquire(timeout: _duration(seconds));
        release();
      } on TimeoutException {
        throw CoordinatorError(
          ErrorKind.authInProgress,
          '$displayName login or recovery is in progress. Please try again shortly.',
        );
      }
    }
    while (_barrier) {
      _assertOpen();
      await _open.wait(_duration(seconds));
    }
    _assertOpen();
    if (_context != null && !contextIsCurrent()) _health = Health.expired;
    if (_context == null ||
        const {Health.idle, Health.failed, Health.expired}.contains(_health)) {
      final verdict = await handleExpiry(
        _generation,
        'session not ready',
        assumeDead: true,
      );
      if (!const {
        Verdict.recovered,
        Verdict.alreadyRecovered,
      }.contains(verdict)) {
        if (_context == null)
          throw CoordinatorError(
            ErrorKind.notAuthenticated,
            '$displayName login required.',
          );
        throw _expiredError();
      }
      return;
    }
    if (_active.isNotEmpty && _health == Health.ready) return;
    final age = kind == Kind.mutation
        ? config.mutationProbeMaxAge
        : config.probeMaxAge;
    if (_now - _lastOk <= age) return;
    final attempts = kind == Kind.mutation ? 3 : 1;
    for (var attempt = 0; attempt < attempts; attempt++) {
      final observed = _generation;
      final probe = await _probe();
      if (probe == Probe.alive) return;
      if (probe == Probe.repairRequired || probe == Probe.dead) {
        final verdict = await handleExpiry(
          observed,
          probe == Probe.dead
              ? 'probe: session dead'
              : 'probe: protected documents unavailable',
        );
        if (const {
          Verdict.recovered,
          Verdict.alreadyRecovered,
          Verdict.alive,
        }.contains(verdict))
          return;
        if (probe == Probe.dead) throw _expiredError();
        throw CoordinatorError(
          ErrorKind.sessionUnverified,
          '$displayName protected pages are unavailable. Recovery is limited; '
          'try again shortly or sign in again.',
        );
      }
      if (attempt + 1 < attempts)
        await Future<void>.delayed(const Duration(seconds: 1));
    }
    if (kind == Kind.mutation)
      throw CoordinatorError(
        ErrorKind.sessionUnverified,
        '$displayName session could not be verified. The save was not started. Please try again.',
      );
  }

  void _startKeepalive() {
    if (_keepaliveEnabled) return;
    _keepaliveEnabled = true;
    _scheduleKeepalive();
  }

  void _scheduleKeepalive() {
    if (!_keepaliveEnabled || _closed) return;
    final interval = max(120.0, config.keepaliveInterval);
    _keepalive = Timer(
      _duration(interval * (0.95 + 0.1 * Random().nextDouble())),
      () {
        _track(_keepaliveTick(interval)).then<void>(
          (_) {
            _scheduleKeepalive();
          },
          onError: (Object _, StackTrace __) {
            _scheduleKeepalive();
          },
        );
      },
    );
  }

  Future<void> _keepaliveTick(double interval) async {
    if (_closed ||
        _active.isNotEmpty ||
        _barrier ||
        _context == null ||
        _lifecycle.locked ||
        !const {Health.ready, Health.unknown}.contains(_health) ||
        _now - _lastOk < interval * 0.75)
      return;
    final observed = _generation;
    final context = _context;
    final probe = await _probe();
    if (observed != _generation || !identical(context, _context)) return;
    if (probe == Probe.dead) {
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      if (_closed ||
          observed != _generation ||
          !identical(context, _context) ||
          _active.isNotEmpty ||
          _barrier ||
          _lifecycle.locked)
        return;
      if (await _probe() == Probe.dead &&
          observed == _generation &&
          identical(context, _context)) {
        await handleExpiry(
          observed,
          'keepalive: session expired',
          assumeDead: true,
        );
      }
    } else if (probe == Probe.repairRequired) {
      await handleExpiry(
        observed,
        'keepalive: protected documents unavailable',
      );
    } else if (probe == Probe.unknown &&
        _unknownStreak >= 4 &&
        observed == _generation &&
        identical(context, _context)) {
      _health = Health.unknown;
    }
  }

  Future<_Outcome> _owner(
    _Outcome out,
    String resource,
    Kind kind,
    Future<Map<String, dynamic>> Function(Object?) worker,
    double timeout,
    double wait,
  ) async {
    try {
      return await lease(
        resource,
        kind,
        (lease) async {
          out.generation = lease.generation;
          if (out.abortBeforeStart) {
            out.error = ErrorKind.portalSlow;
            return out;
          }
          out.cancellation.check();
          out.started = true;
          final operation = _track(
            Future<Map<String, dynamic>>.sync(() => worker(lease.page)),
          );
          Map<String, dynamic> result;
          if (kind == Kind.mutation) {
            result = await operation;
          } else {
            try {
              result = await operation.timeout(_duration(timeout));
            } on TimeoutException {
              out.timedOut = true;
              out.error = ErrorKind.portalSlow;
              out.exception = TimeoutException('Portal operation timed out.');
              out.cancellation.cancel();
              try {
                await operation;
              } catch (_) {}
              return out;
            }
          }
          out.result = result;
          out.error = classifyWorkerResult(result);
          return out;
        },
        wait: wait,
        cancellation: out.cancellation,
      );
    } catch (error) {
      out.exception = error;
      out.error = classifyException(error);
      return out;
    } finally {
      out.done = true;
    }
  }

  Future<_Outcome> _attempt(
    String resource,
    Kind kind,
    Future<Map<String, dynamic>> Function(Object?) worker,
    double timeout,
    double wait,
  ) async {
    final out = _Outcome(_generation);
    if (kind != Kind.mutation)
      return _owner(out, resource, kind, worker, timeout, wait);
    final owner = _track(_owner(out, resource, kind, worker, timeout, wait));
    out.owner = owner;
    try {
      return await owner.timeout(_duration(timeout));
    } on TimeoutException {
      out.timedOut = true;
      out.error = ErrorKind.portalSlow;
      out.exception = TimeoutException('Portal operation timed out.');
      if (!out.started) {
        out.abortBeforeStart = true;
        out.cancellation.cancel();
        try {
          await owner.timeout(_duration(config.readCancelGrace));
        } catch (_) {}
      }
      return out;
    }
  }

  CoordinatorError _responseError(
    ErrorKind kind,
    String fallback,
    Map<String, dynamic>? upstream, [
    Map<String, dynamic> extra = const {},
  ]) {
    final details = Map<String, dynamic>.of(extra);
    var message = fallback;
    if (upstream != null) {
      details['upstream_response'] = Map.of(upstream);
      final original = upstream['message'];
      if (original is String && original.trim().isNotEmpty) {
        message = original;
        details['coordinator_message'] = fallback;
      }
    }
    return CoordinatorError(kind, message, details);
  }

  CoordinatorError _expiryError(Verdict verdict) => switch (verdict) {
    Verdict.alive => CoordinatorError(
      ErrorKind.pageNotReady,
      'The portal page is not ready. Please try again.',
    ),
    Verdict.unknown => CoordinatorError(
      ErrorKind.networkError,
      'The portal gateway is slow or unreachable. Please try again.',
    ),
    _ => _expiredError(),
  };

  Future<Map<String, dynamic>> _resolveAmbiguous(
    String resource,
    Future<bool?> Function(Object?)? verify,
    String label,
    double wait,
    Set<String> preMutationCodes,
    _Outcome out,
  ) async {
    if (out.owner != null && !out.done) {
      try {
        await out.owner!.timeout(_duration(config.mutationSettleTimeout));
      } on TimeoutException {
        throw _responseError(
          ErrorKind.mutationAmbiguous,
          '$label: The save response did not arrive before the operation settlement deadline. '
          'Please check the status on the portal before submitting again.',
          out.result,
          {'applied': null, 'pending': true},
        );
      }
    }
    final result = out.result;
    if (result != null) {
      if (out.error == null || classifyWorkerResult(result) == null)
        return result;
      if ((out.error == ErrorKind.validationError ||
              preMutationCodes.contains(result['code'])) &&
          result['submission_attempted'] != true) {
        return result;
      }
    }
    bool? applied;
    if (verify != null) {
      final cancellation = OperationCancellation();
      final verification = _track(() async {
        await ensureReady(Kind.read, wait: wait);
        return lease(
          resource,
          Kind.read,
          (lease) => verify(lease.page),
          wait: wait,
          cancellation: cancellation,
        );
      }());
      try {
        applied = await verification.timeout(
          _duration(config.mutationVerifyTimeout),
        );
      } catch (_) {
        cancellation.cancel();
        applied = null;
      }
    }
    final fallback =
        '$label: The response was unclear, but the change was verified on the portal.';
    if (applied == true) {
      final message = result?['message'];
      return {
        'success': true,
        'verifiedAfterAmbiguity': true,
        'message': message is String && message.trim().isNotEmpty
            ? message
            : fallback,
        'coordinator_message': fallback,
        if (result != null) 'upstream_response': Map.of(result),
      };
    }
    throw _responseError(
      ErrorKind.mutationAmbiguous,
      applied == false
          ? '$label: The save was not confirmed; verification found no change '
                'on the portal. You may try again.'
          : '$label: The save outcome is unknown. '
                'Check the status on the portal before submitting again.',
      result,
      {'applied': applied},
    );
  }

  Future<Map<String, dynamic>> run({
    required String resource,
    required Kind kind,
    required Future<Map<String, dynamic>> Function(Object?) worker,
    double? timeout,
    double? wait,
    Set<String> preMutationCodes = const {},
    Future<bool?> Function(Object?)? verify,
    String label = '',
    int? maxAttempts,
  }) {
    _assertOpen();
    final future = _run(
      resource,
      kind,
      worker,
      max(0.0, timeout ?? config.defaultOpTimeout),
      max(0.0, wait ?? config.defaultLeaseWait),
      preMutationCodes,
      verify,
      label.isEmpty ? resource : label,
      max(1, maxAttempts ?? config.maxAttempts),
    );
    return kind == Kind.mutation ? _track(future) : future;
  }

  Future<Map<String, dynamic>> _run(
    String resource,
    Kind kind,
    Future<Map<String, dynamic>> Function(Object?) worker,
    double timeout,
    double wait,
    Set<String> preMutationCodes,
    Future<bool?> Function(Object?)? verify,
    String label,
    int limit,
  ) async {
    var attempt = 0;
    while (true) {
      attempt++;
      await ensureReady(kind, wait: wait);
      final out = await _attempt(resource, kind, worker, timeout, wait);
      if (out.error == null && !out.timedOut) {
        markAlive(out.generation);
        return out.result ?? {'success': true};
      }
      final error = out.error ?? ErrorKind.serverError;
      final code = out.result?['code']?.toString() ?? '';
      final retry = attempt < limit;
      if (kind == Kind.mutation && out.started) {
        if (out.timedOut)
          return _resolveAmbiguous(
            resource,
            verify,
            label,
            wait,
            preMutationCodes,
            out,
          );
        if (error == ErrorKind.validationError &&
            !preMutationCodes.contains(code) &&
            out.result?['submission_attempted'] != true)
          return out.result ?? {'success': false};
        if (preMutationCodes.contains(code) &&
            out.result?['submission_attempted'] != true) {
          if (error == ErrorKind.sessionExpired) {
            final verdict = await handleExpiry(
              out.generation,
              '$label: expired before write',
            );
            if (const {
                  Verdict.recovered,
                  Verdict.alreadyRecovered,
                  Verdict.alive,
                }.contains(verdict) &&
                retry)
              continue;
            if (out.result != null) return out.result!;
            throw _expiryError(verdict);
          }
          if (retry) {
            await Future<void>.delayed(_duration(min(attempt.toDouble(), 2)));
            continue;
          }
          if (out.result != null) return out.result!;
          throw CoordinatorError(
            error,
            '$label: The portal was not ready. The save was not started.',
          );
        }
        return _resolveAmbiguous(
          resource,
          verify,
          label,
          wait,
          preMutationCodes,
          out,
        );
      }
      if (kind == Kind.mutation) {
        if (out.owner != null && !out.done)
          throw CoordinatorError(
            ErrorKind.mutationAmbiguous,
            '$label: previous owner is still settling; retry withheld.',
            {'applied': null, 'pending': true},
          );
        if (error == ErrorKind.sessionExpired) {
          final verdict = await handleExpiry(
            out.generation,
            '$label: session expired before mutation started',
          );
          if (const {
                Verdict.recovered,
                Verdict.alreadyRecovered,
                Verdict.alive,
              }.contains(verdict) &&
              retry)
            continue;
          throw _expiryError(verdict);
        }
        if (const {
              ErrorKind.validationError,
              ErrorKind.serverError,
            }.contains(error) &&
            out.result != null)
          return out.result!;
        if (retry) {
          await Future<void>.delayed(_duration(min(attempt.toDouble(), 2)));
          continue;
        }
        throw CoordinatorError(error, '$label: The save could not be started.');
      }
      if (const {
        ErrorKind.validationError,
        ErrorKind.serverError,
      }.contains(error)) {
        if (out.result != null) return out.result!;
        throw CoordinatorError(
          ErrorKind.serverError,
          '$label: ${out.exception}',
        );
      }
      if (error == ErrorKind.sessionExpired) {
        final verdict = await handleExpiry(
          out.generation,
          '$label: worker reported SESSION_EXPIRED',
        );
        if (const {
              Verdict.recovered,
              Verdict.alreadyRecovered,
              Verdict.alive,
            }.contains(verdict) &&
            retry)
          continue;
        if (out.result != null) return out.result!;
        throw _expiryError(verdict);
      }
      if (error == ErrorKind.browserError) {
        if (retry) continue;
        await handleExpiry(
          out.generation,
          '$label: browser error',
          assumeDead: true,
        );
        if (out.result != null) return out.result!;
        throw CoordinatorError(
          ErrorKind.browserError,
          'The browser session was lost and could not be recovered.',
        );
      }
      if (const {
        ErrorKind.pageBusy,
        ErrorKind.recoveryInProgress,
        ErrorKind.authInProgress,
      }.contains(error)) {
        if (retry) {
          await Future<void>.delayed(_duration(min(0.5 * attempt, 2)));
          continue;
        }
        if (out.result != null) return out.result!;
        throw CoordinatorError(
          error,
          out.exception?.toString() ??
              '$label: operation temporarily unavailable.',
        );
      }
      if (error == ErrorKind.notAuthenticated) {
        if (retry) {
          final verdict = await handleExpiry(
            out.generation,
            '$label: not authenticated',
            assumeDead: true,
          );
          if (const {
            Verdict.recovered,
            Verdict.alreadyRecovered,
          }.contains(verdict))
            continue;
        }
        if (out.result != null) return out.result!;
        throw CoordinatorError(error, '$label: login required.');
      }
      if (out.timedOut) {
        if (retry) {
          await Future<void>.delayed(_duration(min(attempt.toDouble(), 2)));
          continue;
        }
        throw CoordinatorError(
          ErrorKind.portalSlow,
          '$label: The portal did not respond within the deadline.',
        );
      }
      if (retry) {
        await Future<void>.delayed(_duration(min(attempt.toDouble(), 2)));
        continue;
      }
      if (out.result != null) return out.result!;
      throw CoordinatorError(
        error,
        out.exception?.toString() ??
            '$label: The portal is busy. Please try again.',
      );
    }
  }

  /// Idempotent. A shutdown that fails because work is still unsettled stays
  /// retryable: once that work finishes, a later call completes the shutdown.
  /// (The coordinator remains closed meanwhile, and a retry never reports
  /// success while work is pending.) [timeout] overrides the default settle
  /// deadline of `max(10, config.shutdownTimeout)` seconds.
  Future<void> shutdown({double? timeout}) {
    final running = _shutdownTask;
    if (running != null) return running;
    final task = _shutdown(timeout);
    _shutdownTask = task;
    task.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {
        if (identical(_shutdownTask, task)) _shutdownTask = null;
      },
    );
    return task;
  }

  Future<void> _shutdown(double? timeout) async {
    _closed = true;
    _raiseBarrier();
    _keepaliveEnabled = false;
    _keepalive?.cancel();
    final deadline = _now + (timeout ?? max(10.0, config.shutdownTimeout));
    while (hasPendingWork() && _now < deadline) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (_active.isNotEmpty) {
      for (final operation in List.of(_active)) {
        if (operation.kind != Kind.mutation) operation.cancellation.cancel();
      }
      try {
        await _idle.wait(_duration(config.readCancelGrace));
      } catch (_) {}
    }
    if (hasPendingWork())
      throw StateError('Shutdown incomplete; unsettled portal work retained.');
  }
}
