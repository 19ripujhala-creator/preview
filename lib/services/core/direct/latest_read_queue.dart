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
    try {
      while (_pending != null) {
        final read = _pending!;
        _pending = null;
        await read();
      }
      completion.complete();
    } catch (error, stack) {
      _pending = null;
      completion.completeError(error, stack);
    } finally {
      _completion = null;
    }
  }
}
