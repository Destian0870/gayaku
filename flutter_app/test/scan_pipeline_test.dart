import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'package:flutter_app/logic/scan_pipeline.dart';

/// Builds an RGBA buffer from `(r,g,b,a)` tuples.
Uint8List rgbaOf(List<(int, int, int, int)> pixels) {
  final out = Uint8List(pixels.length * 4);
  for (var i = 0; i < pixels.length; i++) {
    final (r, g, b, a) = pixels[i];
    out[i * 4] = r;
    out[i * 4 + 1] = g;
    out[i * 4 + 2] = b;
    out[i * 4 + 3] = a;
  }
  return out;
}

/// A `size x size` mask with the given box (inclusive) set to 1.
Float32List maskWithBox(int size, int x0, int y0, int x1, int y1) {
  final mask = Float32List(size * size);
  for (var y = y0; y <= y1; y++) {
    for (var x = x0; x <= x1; x++) {
      mask[y * size + x] = 1;
    }
  }
  return mask;
}

void main() {
  group('rgbaToNhwcFloats', () {
    test('interleaves RGB and scales to 0..1', () {
      final rgba = rgbaOf([
        (255, 0, 128, 255),
        (0, 64, 255, 255),
        (10, 20, 30, 255),
        (40, 50, 60, 255),
      ]);
      final floats = rgbaToNhwcFloats(rgba, 2);
      expect(floats.length, 12);
      // First pixel: red 1.0, green 0.0, blue 128/255.
      expect(floats[0], 1.0);
      expect(floats[1], 0.0);
      expect(floats[2], closeTo(128 / 255, 1e-6));
      // Second pixel: red 0.0, green 64/255, blue 1.0.
      expect(floats[3], 0.0);
      expect(floats[4], closeTo(64 / 255, 1e-6));
      expect(floats[5], 1.0);
      // Third pixel keeps its own slot.
      expect(floats[6], closeTo(10 / 255, 1e-6));
      expect(floats[7], closeTo(20 / 255, 1e-6));
      expect(floats[8], closeTo(30 / 255, 1e-6));
    });
  });

  group('maskBoundingBox', () {
    test('returns null for an empty matte', () {
      expect(maskBoundingBox(Float32List(16), 4), isNull);
      // A single pixel below the threshold is still empty.
      final faint = Float32List(16)..[5] = 0.4;
      expect(maskBoundingBox(faint, 4), isNull);
    });

    test('brackets the mask with the margin applied', () {
      final box = maskBoundingBox(maskWithBox(4, 1, 1, 2, 2), 4)!;
      expect(box.left, closeTo(0.22, 1e-6));
      expect(box.top, closeTo(0.22, 1e-6));
      expect(box.right, closeTo(0.78, 1e-6));
      expect(box.bottom, closeTo(0.78, 1e-6));
    });

    test('clamps the margin at the image edges', () {
      final box = maskBoundingBox(maskWithBox(4, 0, 0, 3, 3), 4)!;
      expect(box.left, 0.0);
      expect(box.top, 0.0);
      expect(box.right, 1.0);
      expect(box.bottom, 1.0);
    });
  });

  group('cropRgba', () {
    test('cuts the requested region, row by row', () {
      // 2x2: red green / blue white.
      final rgba = rgbaOf([
        (255, 0, 0, 255),
        (0, 255, 0, 255),
        (0, 0, 255, 255),
        (255, 255, 255, 255),
      ]);
      final whole = cropRgba(
        rgba,
        2,
        2,
        (left: 0.0, top: 0.0, right: 1.0, bottom: 1.0),
      );
      expect(whole.width, 2);
      expect(whole.height, 2);
      expect(whole.rgba, rgba);

      final rightColumn = cropRgba(
        rgba,
        2,
        2,
        (left: 0.5, top: 0.0, right: 1.0, bottom: 1.0),
      );
      expect(rightColumn.width, 1);
      expect(rightColumn.height, 2);
      expect(rightColumn.rgba, rgbaOf([(0, 255, 0, 255), (255, 255, 255, 255)]));
    });
  });

  group('premultipliedCutout', () {
    test('writes the matte into alpha and premultiplies the colour', () {
      final crop = rgbaOf([(255, 0, 0, 255), (255, 0, 0, 255)]);
      final out = premultipliedCutout(crop, 2, 1, Float32List.fromList([1, 0.5]), 2);
      expect(out.sublist(0, 4), [255, 0, 0, 255]);
      // 0.5 alpha: colour halves, alpha rounds to 128.
      expect(out.sublist(4, 8), [128, 0, 0, 128]);
    });

    test('a zero mask erases the pixel entirely', () {
      final crop = rgbaOf([(10, 20, 30, 255)]);
      final out = premultipliedCutout(crop, 1, 1, Float32List.fromList([0]), 1);
      expect(out, [0, 0, 0, 0]);
    });
  });

  group('garmentPixels', () {
    test('keeps straight colours and only the pixels inside the matte', () {
      final crop = rgbaOf([(10, 20, 30, 255), (200, 100, 50, 255)]);
      final out = garmentPixels(crop, 2, 1, Float32List.fromList([0.9, 0.2]), 2);
      // Inside: colour untouched, opaque — premultiplication must not darken it.
      expect(out.sublist(0, 4), [10, 20, 30, 255]);
      // Outside: colour kept but transparent, so colour sampling skips it.
      expect(out.sublist(4, 8), [200, 100, 50, 0]);
    });
  });

  group('float16 conversion', () {
    test('matches the known half-precision patterns', () {
      expect(floatToHalf(0), 0x0000);
      expect(floatToHalf(1), 0x3C00);
      expect(floatToHalf(0.5), 0x3800);
      expect(floatToHalf(2), 0x4000);
      expect(floatToHalf(-1), 0xBC00);
    });

    test('round-trips within half precision', () {
      for (final value in [0.0, 0.25, 0.5, 1.0, 0.1, 123.5, 0.03125]) {
        expect(halfToFloat(floatToHalf(value)), closeTo(value, 1e-2));
      }
    });
  });

  // The models are driven through raw bytes because `Interpreter.run` infers the
  // input shape from the object handed to it; these cover that plumbing.
  group('byte plumbing', () {
    test('float32Bytes shares memory with the float buffer', () {
      final values = Float32List.fromList([0, 0.5, 1, -2.5]);
      final bytes = float32Bytes(values);
      expect(bytes.length, 16);
      final back = bytesToFloat32(bytes);
      expect(back, values);
      // Writing 1.0f through the byte view must show up in both float lists —
      // that is what makes this a view rather than a copy.
      bytes.setAll(0, [0x00, 0x00, 0x80, 0x3F]);
      expect(values[0], 1.0);
      expect(back[0], 1.0);
    });

    test('floatsToInputBytes writes half bits for a float16 input tensor', () {
      final bytes = floatsToInputBytes(
        Float32List.fromList([1.0, 0.5]),
        TensorType.float16,
      );
      expect(bytes.length, 4);
      expect(bytes.buffer.asUint16List(0, 2), [0x3C00, 0x3800]);
    });

    test('outputFloats reads half bits back', () {
      final half = Uint16List.fromList([0x3C00, 0x3800]);
      final floats = outputFloats(
        half.buffer.asUint8List(0, 4),
        TensorType.float16,
      );
      expect(floats[0], 1.0);
      expect(floats[1], 0.5);
    });

    test('a quantised tensor dtype is refused instead of misread', () {
      expect(
        () => floatsToInputBytes(Float32List(1), TensorType.int8),
        throwsA(isA<ScanFailure>()),
      );
      expect(
        () => outputFloats(Uint8List(4), TensorType.uint8),
        throwsA(isA<ScanFailure>()),
      );
    });
  });
}
