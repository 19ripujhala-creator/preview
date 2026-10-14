/// Local original-template PDF filling. One background isolate serializes native
/// PDFium calls; its font/template cache contains no authenticated portal state.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import 'mpr_pdf.dart';
import 'mpr_pdf_renderer.dart';

class MprPdfService {
  MprPdfService._();
  static final instance = MprPdfService._();
  static const _root = 'assets/mpr/';
  Future<Map<String, Object?>>? _assets;
  Future<SendPort>? _starting;
  ReceivePort? _events, _errors, _exits;
  final _pending = <int, Completer<Uint8List>>{};
  int _next = 0, _epoch = 0;
  Future<Map<String, Object?>> _load() async {
    Future<Uint8List> load(String file) async {
      final bytes = await rootBundle.load('$_root$file');
      return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
    }

    final result = await Future.wait([
      load('mpr_original.pdf'),
      load('Roboto-Regular.ttf'),
      load('NotoSansDevanagari.ttf'),
      load('font_metrics.json'),
    ]);
    final metrics = Map<String, dynamic>.from(
      jsonDecode(utf8.decode(result[3])) as Map,
    );
    for (final (key, index) in [('latin', 1), ('hindi', 2)]) {
      if (sha256.convert(result[index]).toString() !=
          (metrics[key] as Map)['sha256'])
        throw const MprPdfError(
          'MPR font does not match its original template metrics.',
        );
    }
    return {
      'template': result[0],
      'latin': result[1],
      'hindi': result[2],
      'metrics': metrics,
    };
  }

  Future<SendPort> _start() async {
    final assets = await (_assets ??= _load()), ready = Completer<SendPort>();
    final epoch = ++_epoch;
    _events = ReceivePort();
    _errors = ReceivePort();
    _exits = ReceivePort();
    void fail(Object error) {
      if (epoch != _epoch) return;
      final e = MprPdfError(error.toString());
      if (!ready.isCompleted) ready.completeError(e);
      for (final pending in _pending.values) {
        if (!pending.isCompleted) pending.completeError(e);
      }
      _pending.clear();
      _starting = null;
      _events?.close();
      _errors?.close();
      _exits?.close();
    }

    _events!.listen((dynamic message) {
      if (epoch != _epoch) return;
      if (message is SendPort) {
        if (!ready.isCompleted) ready.complete(message);
        return;
      }
      if (message is! List || message.length < 3) return;
      if (message[0] == 'startup_error') {
        fail(message[2] as Object);
        return;
      }
      final completer = _pending.remove(message[0]);
      if (completer == null) return;
      if (message[1] == true) {
        completer.complete(
          (message[2] as TransferableTypedData).materialize().asUint8List(),
        );
      } else {
        completer.completeError(MprPdfError(message[2].toString()));
      }
    });
    _errors!.listen(
      (dynamic e) => fail(
        e is List && e.isNotEmpty
            ? e.first.toString()
            : 'MPR PDF rendering failed.',
      ),
    );
    _exits!.listen((_) => fail('MPR PDF worker stopped. Generate again.'));
    try {
      await Isolate.spawn(
        _mprPdfActor,
        {'reply': _events!.sendPort, 'assets': assets},
        onError: _errors!.sendPort,
        onExit: _exits!.sendPort,
        errorsAreFatal: true,
        debugName: 'Rajshala MPR PDF',
      );
    } catch (e) {
      fail(e);
    }
    return ready.future;
  }

  Future<Uint8List> generate(Map<String, dynamic> payload) async {
    final plan = buildMprPdfPlan(payload);
    final port = await (_starting ??= _start());
    final id = ++_next, completer = Completer<Uint8List>();
    _pending[id] = completer;
    port.send([id, plan.commands]);
    return completer.future;
  }

  Future<void> close() async {
    final start = _starting;
    if (start == null) return;
    try {
      final port = await start;
      port.send(['close']);
    } catch (_) {}
    // An in-flight render finishes before its queued close request; never kill
    // the isolate while native PDFium owns document/font resources.
  }
}

@pragma('vm:entry-point')
void _mprPdfActor(Map<String, Object?> bootstrap) async {
  final reply = bootstrap['reply'] as SendPort;
  final port = ReceivePort();
  MprPdfRenderer? renderer;
  try {
    final raw = Map<String, Object?>.from(bootstrap['assets'] as Map),
        assets = MprPdfAssets(
          template: raw['template'] as Uint8List,
          latin: raw['latin'] as Uint8List,
          hindi: raw['hindi'] as Uint8List,
          metrics: Map<String, dynamic>.from(raw['metrics'] as Map),
        );
    renderer = MprPdfRenderer();
    reply.send(port.sendPort);
    await for (final message in port) {
      if (message is! List) continue;
      if (message.first == 'close') break;
      if (message.length != 2) continue;
      final id = message.first;
      try {
        final plan = MprPdfPlan(
              (message[1] as List)
                  .map((v) => Map<String, dynamic>.from(v as Map))
                  .toList(),
            ),
            bytes = await renderer.render(plan, assets);
        reply.send([
          id,
          true,
          TransferableTypedData.fromList([bytes]),
        ]);
      } catch (e) {
        reply.send([id, false, e.toString()]);
      }
    }
  } catch (e) {
    reply.send(['startup_error', false, e.toString()]);
  } finally {
    renderer?.close();
    port.close();
  }
}
