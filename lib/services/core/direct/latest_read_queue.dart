/// For screen READs only: finish the active read, then load only the latest
/// requested selection. Never cancels, schedules or coalesces mutations.
import 'dart:async';

class LatestReadQueue {
  Future<void> Function()? _pending;
  Completer<void>? _completion;

  Future<void> request(Future<void> Function() read) {
    _pending = read;
    final existing = _completion;
    if (existing != null) return existing.future;
    final completion = Completer<void>();
    _completion = completion;
    unawaited(_drain(completion));
    return completion.future;
  }

  void discardPending() => _pending = null;

  Future<void> _drain(Completer<void> completion) async {
    // A failed read must not swallow a newer selection that never ran: keep
    // draining and report the outcome of the last read that actually executed.
    Object? failure;
    StackTrace? failureStack;
    while (_pending != null) {
      final read = _pending!;
      _pending = null;
      try {
        await read();
        failure = null;
        failureStack = null;
      } catch (error, stack) {
        failure = error;
        failureStack = stack;
      }
    }
    _completion = null;
    if (failure != null) {
      completion.completeError(failure, failureStack);
    } else {
      completion.complete();
    }
  }
}
