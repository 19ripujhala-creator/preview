import 'dart:async';

/// Process-wide singleton for a portal runtime together with its retirement
/// barrier. Staff, RajSIMS and School runtimes share this behaviour.
///
/// * A new runtime is never created while the previous one may still own
///   unsettled work: it could persist a late session after the new login.
/// * A failed retirement keeps that barrier, but the next [get] / [retire]
///   *retries* it. Once the old work has settled the retry succeeds and the
///   next login gets a fresh runtime. (The failed future used to be cached, so
///   every later login failed until the app was restarted.)
/// * A failed creation is not cached either.
class RuntimeSlot<T extends Object> {
  RuntimeSlot({
    required Future<T> Function() create,
    required Future<void> Function(T runtime) close,
  }) : _create = create,
       _close = close;

  final Future<T> Function() _create;
  final Future<void> Function(T runtime) _close;
  Future<T>? _instance;
  T? _current;
  Future<void>? _retiring;
  bool _unsettled = false;

  /// The live runtime; null before creation and after a completed retirement.
  T? get current => _current;

  /// True while a retirement is running or the last attempt left work behind.
  bool get retirementPending => _retiring != null || _unsettled;

  /// Returns the shared runtime, creating it if needed. Throws while the
  /// previous runtime still has unsettled work (the barrier is retried first).
  Future<T> get() async {
    if (retirementPending) await retire();
    final existing = _instance;
    if (existing != null) return existing;
    final task = _build();
    _instance = task;
    task.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {
        if (identical(_instance, task)) _instance = null;
      },
    );
    return task;
  }

  Future<T> _build() async {
    final runtime = await _create();
    _current = runtime;
    return runtime;
  }

  /// Retires the live runtime. Concurrent callers share one attempt; a failed
  /// attempt is retried by the next call. When [only] is given, nothing
  /// happens unless it is the slot's live runtime (already retired otherwise).
  Future<void> retire([T? only]) {
    if (only != null && !identical(only, _current)) return Future<void>.value();
    final running = _retiring;
    if (running != null) return running;
    final instance = _instance;
    if (instance == null) {
      _unsettled = false;
      return Future<void>.value();
    }
    final task = _retireInstance(instance);
    _retiring = task;
    task.then<void>(
      (_) {
        if (identical(_retiring, task)) _retiring = null;
      },
      onError: (Object _, StackTrace __) {
        if (identical(_retiring, task)) _retiring = null;
      },
    );
    return task;
  }

  Future<void> _retireInstance(Future<T> instance) async {
    final T runtime;
    try {
      runtime = await instance;
    } catch (_) {
      // Creation failed: there is nothing to retire.
      if (identical(_instance, instance)) _instance = null;
      _unsettled = false;
      return;
    }
    try {
      await _close(runtime);
    } catch (_) {
      // Keep the instance and the barrier; a later call retries.
      _unsettled = true;
      rethrow;
    }
    _unsettled = false;
    if (identical(_current, runtime)) _current = null;
    if (identical(_instance, instance)) _instance = null;
  }
}
