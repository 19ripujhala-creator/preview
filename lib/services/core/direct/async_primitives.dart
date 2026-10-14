import 'dart:async';

class OperationCancelled implements Exception {
  const OperationCancelled();
}

/// Dart Futures do not cancel implicitly; native requests cooperate with this
/// token. An uncooperative future keeps its lease until it actually settles.
class OperationCancellation {
  static final Object zoneKey = Object();
  static OperationCancellation? get current =>
      Zone.current[zoneKey] as OperationCancellation?;
  bool _cancelled = false;
  final Set<void Function()> _listeners = {};
  bool get cancelled => _cancelled;
  void check() {
    if (_cancelled) throw const OperationCancelled();
  }

  void Function() listen(void Function() callback) {
    if (_cancelled) {
      callback();
      return () {};
    }
    _listeners.add(callback);
    return () => _listeners.remove(callback);
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final callback in List.of(_listeners)) {
      try {
        callback();
      } catch (_) {}
    }
    _listeners.clear();
  }
}

class AsyncSignal {
  AsyncSignal({bool set = false}) : _set = set {
    if (set) _ready.complete();
  }
  bool _set;
  Completer<void> _ready = Completer<void>();
  bool get isSet => _set;
  void clear() {
    if (!_set) return;
    _set = false;
    _ready = Completer<void>();
  }

  void set() {
    _set = true;
    if (!_ready.isCompleted) _ready.complete();
  }

  Future<void> wait(Duration timeout) => _ready.future.timeout(timeout);
}

class _Waiter {
  final Completer<void> ready = Completer<void>();
  Timer? timeout;
  void Function()? stopCancellation;
  bool live = true;
  void stop() {
    timeout?.cancel();
    stopCancellation?.call();
  }
}

class AsyncMutex {
  bool _locked = false;
  final List<_Waiter> _queue = [];
  bool get locked => _locked;

  Future<void Function()> acquire({
    Duration? timeout,
    OperationCancellation? cancellation,
  }) async {
    cancellation?.check();
    if (!_locked) {
      _locked = true;
      return _releaseOnce();
    }
    if (timeout != null && timeout <= Duration.zero) {
      throw TimeoutException('Resource lock deadline expired.');
    }
    final waiter = _Waiter();
    _queue.add(waiter);
    void fail(Object error) {
      if (!waiter.live) return;
      waiter.live = false;
      _queue.remove(waiter);
      waiter.stop();
      waiter.ready.completeError(error);
    }

    if (timeout != null) {
      waiter.timeout = Timer(
        timeout,
        () => fail(TimeoutException('Resource lock deadline expired.')),
      );
    }
    waiter.stopCancellation = cancellation?.listen(
      () => fail(const OperationCancelled()),
    );
    await waiter.ready.future;
    return _releaseOnce();
  }

  void Function() _releaseOnce() {
    var released = false;
    return () {
      if (released) return;
      released = true;
      while (_queue.isNotEmpty) {
        final next = _queue.removeAt(0);
        if (!next.live) continue;
        next.live = false;
        next.stop();
        next.ready.complete();
        return;
      }
      _locked = false;
    };
  }

  Future<T> protect<T>(Future<T> Function() operation) async {
    final release = await acquire();
    try {
      return await operation();
    } finally {
      release();
    }
  }
}
