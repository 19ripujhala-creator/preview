/// On-device ddddocr inference, using the existing ONNX/OpenCV plugins.
/// The separate SSO model is bundled; no Python/API/browser process is involved.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:opencv_dart/opencv.dart' as cv;

import 'sso_captcha.dart';

class RajssoOnnxCaptcha {
  RajssoOnnxCaptcha({
    required this.profile,
    this.modelAsset = rajssoModelAsset,
    this.charsetAsset = rajssoCharsetAsset,
  });
  final RajssoOcrProfile profile;
  final String modelAsset, charsetAsset;
  Future<void>? _initialization;
  final Map<int, Completer<Object?>> _pending = {};
  ReceivePort? _replies, _errors, _exits;
  Isolate? _isolate;
  SendPort? _commands;
  Completer<void>? _started;
  int _sequence = 0;
  bool _closed = false, _closing = false;
  Object? _fatal;

  Future<void> initialize() {
    if (_closed || _closing) throw StateError('CAPTCHA solver is closed.');
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    final asset = await rootBundle.load(modelAsset);
    final charsetText = await rootBundle.loadString(charsetAsset);
    if (sha256.convert(utf8.encode(charsetText)).toString() !=
        '25161311e636d3a678fc29610287432d4fa9e5048183ed7087701d69d44e3190') {
      throw StateError('Unexpected ddddocr charset asset.');
    }
    final charset = (jsonDecode(charsetText) as List).cast<String>();
    if (_closed || _closing) throw StateError('CAPTCHA solver is closed.');
    _started = Completer<void>();
    _replies = ReceivePort();
    _errors = ReceivePort();
    _exits = ReceivePort();
    _replies!.listen((message) {
      final data = message as List;
      if (data[0] == 'ready') {
        _commands = data[1] as SendPort;
        if (!_started!.isCompleted) _started!.complete();
      } else {
        final pending = _pending.remove(data[0] as int);
        if (pending == null) return;
        if (data[1] == true) {
          pending.complete(data[2]);
        } else {
          pending.completeError(StateError(data[2] as String));
        }
      }
    });
    _errors!.listen(
      (message) => _failWorker(
        StateError('CAPTCHA worker failed: ${(message as List).first}'),
      ),
    );
    _exits!.listen((_) {
      if (!_closing || _pending.isNotEmpty) {
        _failWorker(StateError('CAPTCHA worker stopped.'));
      }
    });
    _isolate = await Isolate.spawn(
      _captchaWorker,
      _replies!.sendPort,
      onError: _errors!.sendPort,
      onExit: _exits!.sendPort,
      errorsAreFatal: true,
      debugName: 'rajshala-rajsso-captcha',
    );
    await _started!.future;
    await _call('initialize', [
      TransferableTypedData.fromList([
        asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes),
      ]),
      charset,
      profile.index,
    ]);
  }

  void _failWorker(Object error) {
    _fatal = error;
    if (_started != null && !_started!.isCompleted)
      _started!.completeError(error);
    final pending = List.of(_pending.values);
    _pending.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) completer.completeError(error);
    }
  }

  Future<Object?> _call(String command, Object? data) {
    if (_fatal != null) return Future.error(_fatal!);
    if (_commands == null)
      return Future.error(StateError('CAPTCHA worker unavailable.'));
    final id = ++_sequence;
    final result = Completer<Object?>();
    _pending[id] = result;
    _commands!.send([id, command, data]);
    return result.future;
  }

  Future<String> solve(Uint8List bytes) async {
    if (bytes.isEmpty)
      throw const FormatException('Invalid SSO CAPTCHA image.');
    await initialize();
    if (_closed || _closing) throw StateError('CAPTCHA solver is closed.');
    return await _call('solve', TransferableTypedData.fromList([bytes]))
        as String;
  }

  /// Retains native buffers/session until queued inference has completed.
  Future<void> close() async {
    if (_closed || _closing) return;
    _closing = true;
    try {
      if (_initialization != null) {
        try {
          await _initialization;
        } catch (_) {}
      }
      if (_commands != null && _fatal == null) await _call('close', null);
    } finally {
      _closed = true;
      _isolate?.kill(priority: Isolate.immediate);
      _commands = null;
      _replies?.close();
      _errors?.close();
      _exits?.close();
    }
  }
}

void _captchaWorker(SendPort replies) async {
  final commands = ReceivePort();
  replies.send(['ready', commands.sendPort]);
  OrtSession? session;
  var charset = <String>[];
  var profile = RajssoOcrProfile.ddddocr15;
  var environmentReady = false;
  try {
    // One isolate processes messages sequentially, equivalent to _OCR_LOCK.
    await for (final message in commands) {
      final request = message as List;
      final id = request[0] as int;
      final command = request[1] as String;
      try {
        if (command == 'initialize') {
          final init = request[2] as List;
          final model = (init[0] as TransferableTypedData)
              .materialize()
              .asUint8List();
          charset = (init[1] as List).cast<String>();
          profile = RajssoOcrProfile.values[init[2] as int];
          if (sha256.convert(model).toString() != rajssoModelSha256 ||
              charset.length != 8210 ||
              charset.first.isNotEmpty) {
            throw StateError('Unexpected ddddocr default model/charset.');
          }
          OrtEnv.instance.init(level: OrtLoggingLevel.error);
          environmentReady = true;
          final options = OrtSessionOptions();
          try {
            options.setIntraOpNumThreads(2);
            options.setInterOpNumThreads(1);
            options.setSessionGraphOptimizationLevel(
              GraphOptimizationLevel.ortEnableAll,
            );
            session = OrtSession.fromBuffer(model, options);
          } finally {
            options.release();
          }
          if (session.inputNames.length != 1 ||
              session.inputNames.single != 'input1' ||
              session.outputNames.length != 1 ||
              session.outputNames.single != '387') {
            throw StateError('Unexpected CAPTCHA ONNX model contract.');
          }
          replies.send([id, true, null]);
        } else if (command == 'solve') {
          if (session == null)
            throw StateError('CAPTCHA model is not initialized.');
          final bytes = (request[2] as TransferableTypedData)
              .materialize()
              .asUint8List();
          replies.send([
            id,
            true,
            _solveNative(session, bytes, charset, profile),
          ]);
        } else if (command == 'close') {
          session?.release();
          session = null;
          if (environmentReady) {
            OrtEnv.instance.release();
            environmentReady = false;
          }
          replies.send([id, true, null]);
          commands.close();
          return;
        } else {
          throw StateError('Unknown CAPTCHA worker command.');
        }
      } catch (error) {
        replies.send([id, false, error.toString()]);
      }
    }
  } finally {
    session?.release();
    if (environmentReady) OrtEnv.instance.release();
    commands.close();
  }
}

String _solveNative(
  OrtSession session,
  Uint8List bytes,
  List<String> charset,
  RajssoOcrProfile profile,
) {
  cv.Mat? decoded, ordered;
  OrtValueTensor? input;
  OrtRunOptions? options;
  List<OrtValue?>? outputs;
  try {
    decoded = cv.imdecode(bytes, cv.IMREAD_UNCHANGED);
    if (decoded.isEmpty)
      throw const FormatException('Invalid SSO CAPTCHA image.');
    if (decoded.channels == 3) {
      ordered = cv.cvtColor(decoded, cv.COLOR_BGR2RGB);
    } else if (decoded.channels == 4) {
      ordered = cv.cvtColor(decoded, cv.COLOR_BGRA2RGBA);
    }
    final pixels = ordered ?? decoded;
    final png =
        bytes.length >= 26 &&
        bytes[0] == 137 &&
        bytes[1] == 80 &&
        bytes[2] == 78 &&
        bytes[3] == 71;
    // Native decoder must produce 8-bit channels; do not silently reinterpret
    // 16-bit/float image bytes as the Python default model's uint8 tensor.
    if (![1, 3, 4].contains(pixels.channels) ||
        pixels.data.length != pixels.rows * pixels.cols * pixels.channels ||
        !pixels.isContinuous) {
      throw const FormatException('Unsupported SSO CAPTCHA pixel mode.');
    }
    final gray = rajssoResizeGray(
      RajssoPixels(
        pixels.data,
        pixels.cols,
        pixels.rows,
        pixels.channels,
        nearest: png && (bytes[25] == 3 || bytes[24] == 1),
      ),
    );
    final width = gray.length ~/ 64;
    input = OrtValueTensor.createTensorWithDataList(
      rajssoNormalizePixels(gray, profile),
      [1, 1, 64, width],
    );
    options = OrtRunOptions();
    outputs = session.run(options, {'input1': input}, ['387']);
    if (outputs.length != 1 || outputs.single == null) {
      throw StateError('Unexpected ddddocr inference output.');
    }
    // Raw OCR text only: original auth_manager.extract_six_digits is applied by
    // the HTTPX login binding. No forced digit charset or image cleanup is added.
    return rajssoDecodeLogits(outputs.single!.value, charset);
  } finally {
    if (outputs != null) {
      for (final value in outputs) {
        value?.release();
      }
    }
    options?.release();
    input?.release();
    ordered?.dispose();
    decoded?.dispose();
  }
}
