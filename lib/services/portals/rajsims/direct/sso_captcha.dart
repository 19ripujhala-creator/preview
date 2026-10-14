/// ddddocr default-model preprocessing/CTC decoding, executed on-device.
/// Pillow's Lanczos coefficients, fixed-point rounding and RGB -> L order are
/// preserved; replacing them with OpenCV.resize/cvtColor changes model input.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// The installed Python package version determines normalization, not the model:
/// ddddocr 1.5.x and 1.6.x ship the same common_old.onnx bytes.
enum RajssoOcrProfile { ddddocr15, ddddocr16 }

RajssoOcrProfile rajssoOcrProfileForVersion(String version) {
  if (RegExp(r'^1\.5\.\d+(?:\D.*)?$').hasMatch(version))
    return RajssoOcrProfile.ddddocr15;
  if (RegExp(r'^1\.6\.\d+(?:\D.*)?$').hasMatch(version))
    return RajssoOcrProfile.ddddocr16;
  throw ArgumentError(
    'Set RAJSHALA_DDDDOCR_VERSION to the working backend package version.',
  );
}

const rajssoModelAsset = 'assets/models/rajsso_common_old.onnx';
const rajssoCharsetAsset = 'assets/models/rajsso_charset.json';
const rajssoModelSha256 =
    'b8f2ad9cbc1f2e3922a6cb9459e30824e7e2467f3fb4fd61420640e34ea0bf68';

class RajssoPixels {
  const RajssoPixels(
    this.bytes,
    this.width,
    this.height,
    this.channels, {
    this.nearest = false,
  });
  final Uint8List bytes;
  final int width, height, channels;
  // Pillow always uses nearest for palette/bilevel modes, even when Lanczos
  // was requested. Decoder provides their resolved palette/gray pixel values.
  final bool nearest;
}

List<(int, List<int>)> _coefficients(int input, int output) {
  final scale = input / output;
  final filterScale = math.max(scale, 1.0);
  final support = 3 * filterScale;
  double sinc(double value) {
    if (value == 0) return 1;
    final angle = value * math.pi;
    return math.sin(angle) / angle;
  }

  return List.generate(output, (index) {
    final center = (index + 0.5) * scale;
    final start = math.max((center - support + 0.5).toInt(), 0);
    final end = math.min((center + support + 0.5).toInt(), input);
    var sum = 0.0;
    final weights = List<double>.generate(end - start, (offset) {
      final x = (offset + start - center + 0.5) / filterScale;
      final weight = x >= -3 && x < 3 ? sinc(x) * sinc(x / 3) : 0.0;
      sum += weight;
      return weight;
    });
    return (
      start,
      weights.map((weight) {
        final normalized = sum == 0 ? weight : weight / sum;
        return (normalized * (1 << 22) + (normalized < 0 ? -0.5 : 0.5)).toInt();
      }).toList(),
    );
  });
}

int _premultiply(int value, int alpha) {
  final product = value * alpha + 128;
  return (product + (product >> 8)) >> 8;
}

/// Input is decoded L, LA, RGB or RGBA byte order, before any resampling.
/// Resize colors first, then grayscale, matching Image.resize(...).convert('L').
Uint8List rajssoResizeGray(RajssoPixels image) {
  final channels = image.channels;
  if (image.width <= 0 ||
      image.height <= 0 ||
      ![1, 2, 3, 4].contains(channels) ||
      image.bytes.length != image.width * image.height * channels) {
    throw ArgumentError('Invalid SSO CAPTCHA image dimensions/pixels.');
  }
  final width = (image.width * (64 / image.height)).toInt();
  if (width <= 0) throw ArgumentError('SSO CAPTCHA resized width is zero.');
  var source = Uint8List.fromList(image.bytes);
  final alpha = channels == 2 || channels == 4;
  final resized = width != image.width || image.height != 64;
  if (alpha && resized && !image.nearest) {
    for (var i = 0; i < source.length; i += channels) {
      for (var channel = 0; channel < channels - 1; channel++) {
        source[i + channel] = _premultiply(
          source[i + channel],
          source[i + channels - 1],
        );
      }
    }
  }
  var sourceWidth = image.width;
  if (image.nearest) {
    final nearest = Uint8List(width * 64 * channels);
    for (var y = 0; y < 64; y++) {
      final sy = math.min(
        ((y + 0.5) * image.height / 64).floor(),
        image.height - 1,
      );
      for (var x = 0; x < width; x++) {
        final sx = math.min(
          ((x + 0.5) * image.width / width).floor(),
          image.width - 1,
        );
        final from = (sy * image.width + sx) * channels;
        final to = (y * width + x) * channels;
        nearest.setRange(to, to + channels, source, from);
      }
    }
    source = nearest;
  } else {
    if (width != image.width) {
      final coefficients = _coefficients(image.width, width);
      final horizontal = Uint8List(width * image.height * channels);
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < width; x++) {
          final (start, weights) = coefficients[x];
          for (var channel = 0; channel < channels; channel++) {
            var sum = 1 << 21;
            for (var offset = 0; offset < weights.length; offset++) {
              sum +=
                  source[(y * image.width + start + offset) * channels +
                      channel] *
                  weights[offset];
            }
            horizontal[(y * width + x) * channels + channel] = (sum >> 22)
                .clamp(0, 255);
          }
        }
      }
      source = horizontal;
      sourceWidth = width;
    }
    if (image.height != 64) {
      final coefficients = _coefficients(image.height, 64);
      final vertical = Uint8List(sourceWidth * 64 * channels);
      for (var y = 0; y < 64; y++) {
        final (start, weights) = coefficients[y];
        for (var x = 0; x < sourceWidth; x++) {
          for (var channel = 0; channel < channels; channel++) {
            var sum = 1 << 21;
            for (var offset = 0; offset < weights.length; offset++) {
              sum +=
                  source[((start + offset) * sourceWidth + x) * channels +
                      channel] *
                  weights[offset];
            }
            vertical[(y * sourceWidth + x) * channels + channel] = (sum >> 22)
                .clamp(0, 255);
          }
        }
      }
      source = vertical;
    }
    if (alpha && resized) {
      for (var i = 0; i < source.length; i += channels) {
        final a = source[i + channels - 1];
        if (a == 0 || a == 255) continue;
        for (var channel = 0; channel < channels - 1; channel++) {
          source[i + channel] = (source[i + channel] * 255 ~/ a).clamp(0, 255);
        }
      }
    }
  }
  final gray = Uint8List(width * 64);
  for (var i = 0; i < gray.length; i++) {
    final offset = i * channels;
    gray[i] = channels <= 2
        ? source[offset]
        : (source[offset] * 19595 +
                  source[offset + 1] * 38470 +
                  source[offset + 2] * 7471 +
                  32768) >>
              16;
  }
  return gray;
}

Float32List rajssoNormalizePixels(Uint8List pixels, RajssoOcrProfile profile) {
  if (pixels.isEmpty || pixels.length % 64 != 0) {
    throw ArgumentError('SSO CAPTCHA input must have height 64.');
  }
  final tensor = Float32List(pixels.length);
  for (var i = 0; i < pixels.length; i++) {
    tensor[i] = pixels[i].toDouble();
    tensor[i] = tensor[i] / 255.0;
    if (profile == RajssoOcrProfile.ddddocr15) {
      tensor[i] = tensor[i] - 0.5;
      tensor[i] = tensor[i] / 0.5;
    }
  }
  return tensor;
}

/// Actual common_old output is [sequenceLength,1,8210]. The graph's declared
/// [1,seqlen] metadata is inaccurate; validate the real inference result instead.
String rajssoDecodeLogits(Object? output, List<String> charset) {
  if (charset.length != 8210 ||
      charset.first.isNotEmpty ||
      output is! List ||
      output.isEmpty) {
    throw StateError('Unexpected ddddocr model/charset output contract.');
  }
  final indices = <int>[];
  for (final step in output) {
    if (step is! List || step.length != 1 || step.single is! List) {
      throw StateError('Unexpected ddddocr model output shape.');
    }
    final row = step.single as List;
    if (row.length != charset.length || row.any((value) => value is! num)) {
      throw StateError('Unexpected ddddocr model output shape.');
    }
    var index = 0;
    var best = (row.first as num).toDouble();
    if (!best.isNaN) {
      for (var i = 1; i < row.length; i++) {
        final score = (row[i] as num).toDouble();
        if (score.isNaN) {
          index = i;
          break;
        }
        if (score > best) {
          index = i;
          best = score;
        }
      }
    }
    indices.add(index);
  }
  return rajssoDecodeIndices(indices, charset);
}

String rajssoDecodeIndices(Iterable<int> indices, List<String> charset) {
  var previous = 0;
  final result = StringBuffer();
  for (final index in indices) {
    if (index < 0 || index >= charset.length)
      throw StateError('Invalid ddddocr charset index.');
    if (index == previous) continue;
    previous = index;
    if (index != 0) result.write(charset[index]);
  }
  return result.toString();
}
