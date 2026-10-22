import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lib/services/portals/rajsims/direct/sso_captcha.dart';

void main() {
  final fixture = jsonDecode(
    File('test/direct/fixtures/python_rajsso_captcha.json').readAsStringSync(),
  ) as Map;
  final charset = (fixture['charset'] as List).cast<String>();
  for (final item in fixture['pixels'] as List) {
    test('actual Pillow/NumPy pixel tensor ${item['name']}', () {
      final pixels = RajssoPixels(
        base64Decode(item['pixels'] as String),
        item['width'] as int,
        item['height'] as int,
        item['channels'] as int,
        nearest: item['nearest'] == true,
      );
      final gray = rajssoResizeGray(pixels);
      expect(gray, base64Decode(item['gray'] as String));
      for (final pair in [
        (RajssoOcrProfile.ddddocr15, 'norm15'),
        (RajssoOcrProfile.ddddocr16, 'norm16'),
      ]) {
        final values = rajssoNormalizePixels(gray, pair.$1);
        expect(base64Encode(values.buffer.asUint8List()), item[pair.$2]);
      }
    });
  }
  for (final item in fixture['inference'] as List) {
    test('actual ddddocr default model CTC ${item['name']}', () {
      expect(
        rajssoDecodeIndices((item['indices'] as List).cast<int>(), charset),
        item['raw_ocr'],
      );
      expect(item['shape'][1], 1);
      expect(item['shape'][2], 8210);
    });
  }
  test(
    'model and charset use separate SSO identities and official checksum',
    () {
      expect(fixture['model_sha256'], rajssoModelSha256);
      expect(charset.length, 8210);
      expect(charset.first, '');
      final model = File('assets/models/rajsso_common_old.onnx');
      expect(
        sha256.convert(model.readAsBytesSync()).toString(),
        rajssoModelSha256,
      );
      expect(rajssoModelAsset, isNot(contains('captcha_group_0_layer_0')));
    },
  );
  test(
    'version is explicit and distinguishes the two source normalizations',
    () {
      expect(rajssoOcrProfileForVersion('1.5.6'), RajssoOcrProfile.ddddocr15);
      expect(rajssoOcrProfileForVersion('1.6.1'), RajssoOcrProfile.ddddocr16);
      expect(() => rajssoOcrProfileForVersion(''), throwsArgumentError);
      expect(() => rajssoOcrProfileForVersion('2.0.0'), throwsArgumentError);
    },
  );
  test('CTC collapse is before blank removal, preserving doubled digits', () {
    final index = charset.indexOf('1');
    expect(rajssoDecodeIndices([0, index, index, 0, index], charset), '11');
  });
  test(
    'argmax first tie and NaN behavior match NumPy without forced digit range',
    () {
      List<double> row(int index) =>
          List.generate(8210, (i) => i == index ? 5.0 : -2.0);
      final a = charset.indexOf('A'), digit = charset.indexOf('1');
      final tie = row(digit)..[a] = 5;
      final nan = row(digit)..[a] = double.nan;
      expect(
        rajssoDecodeLogits([
          [tie],
          [List<double>.filled(8210, 0)],
          [nan],
        ], charset),
        '${charset[a < digit ? a : digit]}A',
      );
    },
  );
  test(
    'unexpected inference shapes, label sets and pixel lengths fail closed',
    () {
      expect(() => rajssoDecodeLogits([[]], charset), throwsStateError);
      expect(
        () => rajssoDecodeLogits([
          [
            [0.0],
          ],
        ], charset),
        throwsStateError,
      );
      expect(() => rajssoDecodeIndices([-1], charset), throwsStateError);
      expect(
        () => rajssoResizeGray(RajssoPixels(Uint8List(3), 2, 2, 3)),
        throwsArgumentError,
      );
    },
  );
}
