/// Native equivalent of core/captcha.py and core/captcha_async.py.
/// The same OpenCV preprocessing and ONNX model run on a dedicated worker isolate.
import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:opencv_dart/opencv.dart' as cv;

const captchaModelAsset = 'assets/models/captcha_group_0_layer_0.onnx';
const _characters =
    r'''0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ!"#$%&'()*+,-./:;<=>?@[\]^_`{|}~''';
final captchaLabels = List<String>.unmodifiable([
  '[GO]',
  '[s]',
  ..._characters.split(''),
]);

/// Maintains NumPy float32 rounding after EACH arithmetic operation.
Float32List normalizeCaptchaPixels(Uint8List pixels) {
  if (pixels.length != 32 * 100) {
    throw ArgumentError('CAPTCHA pixels must have shape [32, 100].');
  }
  final values = Float32List(pixels.length);
  for (var i = 0; i < pixels.length; i++) {
    values[i] = pixels[i].toDouble();
    values[i] = values[i] / 255.0;
    values[i] = values[i] - 0.5;
    values[i] = values[i] / 0.5;
  }
  return values;
}

/// Argmax along axis 2, first-tie semantics, EOS truncation and source cleanup.
/// No CTC repeat collapse, numeric filtering or character substitutions.
String decodeCaptchaLogits(Object? value) {
  if (captchaLabels.length != 96 || value is! List || value.length != 1) {
    throw StateError('Unexpected CAPTCHA ONNX output contract.');
  }
  final steps = value.single;
  if (steps is! List || steps.length != 26) {
    throw StateError('Unexpected CAPTCHA ONNX output contract.');
  }
  final decoded = StringBuffer();
  for (final row in steps) {
    if (row is! List || row.length != 96 || row.any((v) => v is! num)) {
      throw StateError('Unexpected CAPTCHA ONNX output contract.');
    }
    var index = 0;
    var largest = (row[0] as num).toDouble();
    if (!largest.isNaN) {
      for (var i = 1; i < row.length; i++) {
        final score = (row[i] as num).toDouble();
        if (score.isNaN) {
          index = i;
          break;
        }
        if (score > largest) {
          index = i;
          largest = score;
        }
      }
    }
    final token = captchaLabels[index];
    if (token == '[s]') break;
    decoded.write(token);
  }
  return decoded.toString().trim().replaceAll(' ', '');
}

/// Validates graph metadata before constructing the native session, matching
/// Python's explicit [1,1,32,100] input and [1,26,96] output checks.
void validateCaptchaModel(Uint8List bytes) {
  final graphs = _protoFields(bytes)
      .where((f) => f.$1 == 7 && f.$2 is Uint8List)
      .map((f) => f.$2 as Uint8List)
      .toList();
  if (graphs.length != 1)
    throw StateError('Unexpected CAPTCHA ONNX model contract.');
  final inputs = <(String, List<int>)>[];
  final outputs = <(String, List<int>)>[];
  for (final field in _protoFields(graphs.single)) {
    if ((field.$1 == 11 || field.$1 == 12) && field.$2 is Uint8List) {
      final info = _valueInfo(field.$2 as Uint8List);
      (field.$1 == 11 ? inputs : outputs).add(info);
    }
  }
  bool shape(List<int> actual, List<int> expected) =>
      actual.length == expected.length &&
      List.generate(
        actual.length,
        (i) => actual[i] == expected[i],
      ).every((v) => v);
  if (captchaLabels.length != 96 ||
      inputs.length != 1 ||
      outputs.length != 1 ||
      inputs.single.$1 != 'image' ||
      outputs.single.$1 != 'logits' ||
      !shape(inputs.single.$2, [1, 1, 32, 100]) ||
      !shape(outputs.single.$2, [1, 26, 96])) {
    throw StateError('Unexpected CAPTCHA ONNX model contract.');
  }
}

(String, List<int>) _valueInfo(Uint8List bytes) {
  var name = '';
  Uint8List? type;
  for (final field in _protoFields(bytes)) {
    if (field.$1 == 1 && field.$2 is Uint8List) {
      name = utf8.decode(field.$2 as Uint8List);
    }
    if (field.$1 == 2 && field.$2 is Uint8List) type = field.$2 as Uint8List;
  }
  final dimensions = <int>[];
  if (type != null) {
    for (final tensor in _protoFields(type)) {
      if (tensor.$1 != 1 || tensor.$2 is! Uint8List) continue;
      for (final tensorField in _protoFields(tensor.$2 as Uint8List)) {
        if (tensorField.$1 != 2 || tensorField.$2 is! Uint8List) continue;
        for (final dim in _protoFields(tensorField.$2 as Uint8List)) {
          if (dim.$1 != 1 || dim.$2 is! Uint8List) continue;
          var number = -1;
          for (final value in _protoFields(dim.$2 as Uint8List)) {
            if (value.$1 == 1 && value.$2 is int) number = value.$2 as int;
            if (value.$1 == 2)
              number = -1; // Dynamic dimensions are not accepted.
          }
          dimensions.add(number);
        }
      }
    }
  }
  return (name, dimensions);
}

/// Minimal zero-copy reader for ONNX protobuf metadata. It never decodes weights.
Iterable<(int, Object)> _protoFields(Uint8List bytes) sync* {
  var position = 0;
  int varint() {
    var value = 0;
    for (var shift = 0; shift < 70; shift += 7) {
      if (position >= bytes.length)
        throw FormatException('Truncated ONNX metadata.');
      final next = bytes[position++];
      value |= (next & 127) << shift;
      if ((next & 128) == 0) return value;
    }
    throw FormatException('Invalid ONNX varint.');
  }

  while (position < bytes.length) {
    final tag = varint();
    final field = tag >> 3;
    if (field == 0) throw FormatException('Invalid ONNX field.');
    final wire = tag & 7;
    if (wire == 0) {
      yield (field, varint());
    } else {
      final length = switch (wire) {
        1 => 8,
        2 => varint(),
        5 => 4,
        _ => throw FormatException('Unsupported ONNX wire type.'),
      };
      if (length < 0 || position + length > bytes.length) {
        throw FormatException('Truncated ONNX field.');
      }
      if (wire == 2)
        yield (
          field,
          Uint8List.sublistView(bytes, position, position + length),
        );
      position += length;
    }
  }
}

class SchoolOnnxCaptcha {
  SchoolOnnxCaptcha({this.modelAsset = captchaModelAsset});
  final String modelAsset;
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
      debugName: 'rajshala-captcha',
    );
    await _started!.future;
    await _call(
      'initialize',
      TransferableTypedData.fromList([
        asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes),
      ]),
    );
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
    if (bytes.isEmpty) return '';
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
  var environmentReady = false;
  try {
    // One isolate processes messages sequentially, equivalent to _OCR_LOCK.
    await for (final message in commands) {
      final request = message as List;
      final id = request[0] as int;
      final command = request[1] as String;
      try {
        if (command == 'initialize') {
          final model = (request[2] as TransferableTypedData)
              .materialize()
              .asUint8List();
          validateCaptchaModel(model);
          OrtEnv.instance.init();
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
          if (session!.inputNames.length != 1 ||
              session!.inputNames.single != 'image' ||
              session!.outputNames.length != 1 ||
              session!.outputNames.single != 'logits') {
            throw StateError('Unexpected CAPTCHA ONNX model contract.');
          }
          replies.send([id, true, null]);
        } else if (command == 'solve') {
          if (session == null)
            throw StateError('CAPTCHA model is not initialized.');
          final bytes = (request[2] as TransferableTypedData)
              .materialize()
              .asUint8List();
          replies.send([id, true, _solveNative(session, bytes)]);
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

String _solveNative(OrtSession session, Uint8List bytes) {
  cv.Mat? bgr, gray, resized;
  OrtValueTensor? input;
  OrtRunOptions? options;
  List<OrtValue?>? outputs;
  try {
    bgr = cv.imdecode(bytes, cv.IMREAD_COLOR);
    if (bgr.isEmpty) return '';
    gray = cv.cvtColor(bgr, cv.COLOR_BGR2GRAY);
    resized = cv.resize(gray, (100, 32), interpolation: cv.INTER_CUBIC);
    if (resized.rows != 32 ||
        resized.cols != 100 ||
        resized.channels != 1 ||
        !resized.isContinuous) {
      throw StateError('Unexpected CAPTCHA image contract.');
    }
    final pixels = normalizeCaptchaPixels(resized.data);
    input = OrtValueTensor.createTensorWithDataList(pixels, [1, 1, 32, 100]);
    options = OrtRunOptions();
    outputs = session.run(options, {'image': input}, ['logits']);
    if (outputs.length != 1 || outputs.single == null) {
      throw StateError('Unexpected CAPTCHA ONNX output contract.');
    }
    return decodeCaptchaLogits(outputs.single!.value);
  } catch (_) {
    // Python returns an empty OCR string for invalid images/inference errors.
    return '';
  } finally {
    if (outputs != null) {
      for (final value in outputs) {
        value?.release();
      }
    }
    options?.release();
    input?.release();
    resized?.dispose();
    gray?.dispose();
    bgr?.dispose();
  }
}
