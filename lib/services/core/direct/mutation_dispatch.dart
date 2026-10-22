/// Tracks whether a mutation crossed its validated transport boundary.
/// Does not mean the server committed it, and never permits automatic replay.
import 'dart:async';

class MutationDispatch {
  static final Object _zoneKey = Object();
  static MutationDispatch? get current =>
      Zone.current[_zoneKey] as MutationDispatch?;
  bool _requestEntered = false;
  bool _nativeTransport = false;
  bool _dispatchStarted = false;

  // Injected/custom request implementations without native instrumentation are
  // conservatively considered attempted once their mutation request is entered.
  bool get mayHaveStarted =>
      _nativeTransport ? _dispatchStarted : _requestEntered;
  void enterRequest() => _requestEntered = true;
  void observeNativeTransport() => _nativeTransport = true;
  void startDispatch() {
    // Show/Entry preflight POSTs are READ navigation, not attendance dispatch.
    if (_requestEntered) _dispatchStarted = true;
  }

  Future<T> run<T>(Future<T> Function() operation) =>
      runZoned(operation, zoneValues: {_zoneKey: this});
}
