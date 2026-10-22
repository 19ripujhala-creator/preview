import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../lib/services/portals/shaladarpan/direct/captcha_onnx.dart';

void main() {
  test('label order matches Python and preserves [GO]/[s]', () {
    expect(captchaLabels, hasLength(96));
    expect(captchaLabels.take(3), ['[GO]', '[s]', '0']);
    expect(captchaLabels.last, '~');
  });

  test(
    'float32 normalization matches independent NumPy bytes for all gray levels',
    () {
      final pixels = Uint8List.fromList(List.generate(3200, (i) => i % 256));
      final actual = normalizeCaptchaPixels(pixels);
      final expected = File('test/direct/python_captcha_normalization.bin')
          .readAsBytesSync();
      expect(actual.buffer.asUint8List(), expected);
    },
  );

  List<List<List<double>>> logits() => [
    List.generate(26, (_) => List.filled(96, -10.0)),
  ];

  test('decoding preserves repeated labels and stops at first EOS', () {
    final values = logits();
    values[0][0][captchaLabels.indexOf('9')] = 10;
    values[0][1][captchaLabels.indexOf('9')] = 10;
    values[0][2][1] = 10;
    values[0][3][captchaLabels.indexOf('A')] = 10;
    expect(decodeCaptchaLogits(values), '99');
  });

  test('argmax first tie and first NaN agree with NumPy', () {
    final values = logits();
    values[0][0][captchaLabels.indexOf('a')] = 10;
    values[0][0][captchaLabels.indexOf('b')] = 10;
    values[0][1][captchaLabels.indexOf('c')] = double.nan;
    values[0][1][captchaLabels.indexOf('d')] = double.nan;
    values[0][2][1] = 10;
    expect(decodeCaptchaLogits(values), 'ac');
  });

  test('the supplied model has the exact source input/output metadata', () {
    validateCaptchaModel(
      File('assets/models/captcha_group_0_layer_0.onnx').readAsBytesSync(),
    );
    expect(
      () => validateCaptchaModel(Uint8List.fromList([0])),
      throwsFormatException,
    );
  });
}
