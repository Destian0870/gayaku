/// The Smart Scanner pipeline: photo in, detected garment out.
///
/// Order is frozen by docs/adr/0005-classify-the-cutout.md — matte, then
/// classify the Cutout, then read its Dominant colour. Everything runs
/// on-device; the photo never leaves the phone (docs/adr/0001).
///
/// Both models are ordinary `.tflite` files driven through `tflite_flutter`:
/// - matting: U-2-Net small (`u2netp_320.tflite`), `[1,320,320,3]` NHWC RGB in
///   `[0,1]`, first output is the `[1,320,320,1]` mask;
/// - classifier: our own export, `[1,224,224,3]` NHWC RGB in `[0,1]` with
///   normalisation baked in, softmax output in `garmentCategories` order.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'color_extraction.dart';
import 'garment_defaults.dart';
import 'garment_labels.dart';

/// Square size the matting model expects.
const mattingInputSize = 320;

/// Square size the classifier expects.
const classifierInputSize = 224;

/// Longest edge of the photo we decode. A 12 MP phone photo costs ~48 MB of
/// RGBA and buys no accuracy these models can use, so we downscale on ingest.
const maxDecodeEdge = 1600;

/// Raised for anything the user can act on: no garment in frame, missing model.
class ScanFailure implements Exception {
  const ScanFailure(this.message);

  /// Indonesian, shown to the user as-is.
  final String message;

  @override
  String toString() => 'ScanFailure: $message';
}

/// Everything one Scan produced, ready for the review screen.
class ScanResult {
  const ScanResult({
    required this.cutoutPng,
    required this.dominantColor,
    required this.colorName,
    required this.label,
    required this.category,
    required this.suggestedName,
    required this.confidence,
  });

  /// PNG with a transparent background — becomes the WardrobeItem's image.
  final Uint8List cutoutPng;
  final Color dominantColor;
  final String colorName;

  /// Fine garment type the classifier predicted, e.g. `Jeans`.
  final String label;

  /// The one Category the fine [label] maps down to.
  final String category;

  /// Indonesian name suggested for the item's name field.
  final String suggestedName;

  /// Softmax score of the winning class, 0..1.
  final double confidence;

  /// Formality the item starts with, from its Category.
  int get formality => defaultFormality(category);

  /// Occasions the item starts with, from its Category.
  List<String> get occasions => defaultOccasions(category);
}

/// Runs both models over one photo.
///
/// Use [load] in the app; construct directly in tests to inject interpreters
/// pointing at fixture models.
class ScanPipeline {
  ScanPipeline({required this.matting, required this.classifier});

  final Interpreter matting;
  final Interpreter classifier;

  /// Loads the bundled models and checks they match the generated label list.
  static Future<ScanPipeline> load() async {
    final pipeline = ScanPipeline(
      matting: await Interpreter.fromAsset('assets/models/u2netp_320.tflite'),
      classifier: await Interpreter.fromAsset(
        'assets/models/garment_classifier.tflite',
      ),
    );
    pipeline.checkContracts();
    return pipeline;
  }

  void close() {
    matting.close();
    classifier.close();
  }

  /// Fails loudly rather than mislabelling every garment by one index.
  void checkContracts() {
    final classes = classifier.getOutputTensor(0).shape.last;
    if (classes != garmentCategories.length) {
      throw ScanFailure(
        'Model klasifikasi punya $classes kelas, label aplikasi punya '
        '${garmentCategories.length}. Jalankan ulang '
        'ml_workspace/scripts/gen_dart_labels.py.',
      );
    }
    final shape = matting.getInputTensor(0).shape;
    if (shape.length != 4 ||
        shape[1] != mattingInputSize ||
        shape[2] != mattingInputSize ||
        shape[3] != 3) {
      throw ScanFailure(
        'Model matting tidak menerima '
        '${mattingInputSize}x$mattingInputSize RGB (bentuk: $shape).',
      );
    }
  }

  /// Runs the whole pipeline over [photoBytes] (JPEG or PNG).
  Future<ScanResult> scan(Uint8List photoBytes) async {
    final photo = await _decode(photoBytes, maxEdge: maxDecodeEdge);
    final mask = await _matte(photoBytes);
    final box = maskBoundingBox(mask, mattingInputSize);
    if (box == null) {
      throw const ScanFailure(
        'Pakaian tidak terdeteksi. Coba foto ulang dengan latar yang lebih polos.',
      );
    }

    final crop = cropRgba(photo.rgba, photo.width, photo.height, box);
    final cutoutPng = await _encodePng(
      premultipliedCutout(crop.rgba, crop.width, crop.height, mask, mattingInputSize),
      crop.width,
      crop.height,
    );
    final dominant = dominantColorFromRgba(
      garmentPixels(crop.rgba, crop.width, crop.height, mask, mattingInputSize),
    );
    if (dominant == null) {
      throw const ScanFailure(
        'Warna pakaian tidak terbaca. Coba foto dengan pencahayaan lebih terang.',
      );
    }

    final prediction = await _classifyCutout(cutoutPng);
    if (prediction.index >= garmentCategories.length) {
      throw ScanFailure(
        'Model mengembalikan kelas ${prediction.index} di luar daftar label.',
      );
    }
    final label = garmentCategories[prediction.index];
    final category = garmentLabelCategory[label];
    if (category == null) {
      throw ScanFailure(
        'Label "$label" belum dipetakan ke Category. Perbarui '
        'ml_workspace/labels.json lalu jalankan ulang generatornya.',
      );
    }

    return ScanResult(
      cutoutPng: cutoutPng,
      dominantColor: dominant.color,
      colorName: dominant.name,
      label: label,
      category: category,
      suggestedName: garmentLabelName[label] ?? label,
      confidence: prediction.confidence,
    );
  }

  /// Matting mask in `[0,1]`, `mattingInputSize * mattingInputSize` values.
  ///
  /// The photo is squashed to a square first: that is what U-2-Net was trained
  /// on, and the bounding box is mapped back onto the un-squashed photo.
  Future<Float32List> _matte(Uint8List photoBytes) async {
    final small = await _decode(
      photoBytes,
      width: mattingInputSize,
      height: mattingInputSize,
    );
    final outputTensor = matting.getOutputTensor(0);
    final output = bufferFor(outputTensor);
    matting.run(
      packFloats(
        rgbaToNhwcFloats(small.rgba, mattingInputSize),
        matting.getInputTensor(0).type,
      ),
      output,
    );
    return unpackFloats(output, outputTensor.type);
  }

  /// Classifies the Cutout: the model sees a background-free garment, which is
  /// exactly the framing its training data had.
  Future<({int index, double confidence})> _classifyCutout(
    Uint8List cutoutPng,
  ) async {
    final square = await _decode(
      cutoutPng,
      width: classifierInputSize,
      height: classifierInputSize,
    );
    final outputTensor = classifier.getOutputTensor(0);
    final classes = garmentCategories.length;
    final pixels = classifierInputSize * classifierInputSize;
    final input = Float32List(pixels * 3);
    for (var i = 0; i < pixels; i++) {
      input[i * 3] = square.rgba[i * 4] / 255;
      input[i * 3 + 1] = square.rgba[i * 4 + 1] / 255;
      input[i * 3 + 2] = square.rgba[i * 4 + 2] / 255;
    }
    final output = bufferFor(outputTensor);
    classifier.run(
      packFloats(input, classifier.getInputTensor(0).type),
      output,
    );

    final scores = unpackFloats(output, outputTensor.type);
    var best = 0;
    for (var i = 1; i < classes; i++) {
      if (scores[i] > scores[best]) best = i;
    }
    return (index: best, confidence: scores[best].toDouble());
  }

  Future<({Uint8List rgba, int width, int height})> _decode(
    Uint8List bytes, {
    int? width,
    int? height,
    int? maxEdge,
  }) async {
    var targetWidth = width;
    if (maxEdge != null) {
      final probe = await ui.instantiateImageCodec(bytes);
      final frame = await probe.getNextFrame();
      final longest = math.max(frame.image.width, frame.image.height);
      frame.image.dispose();
      probe.dispose();
      if (longest > maxEdge) targetWidth = maxEdge;
    }

    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: targetWidth,
      targetHeight: height,
    );
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final decodedWidth = image.width;
    final decodedHeight = image.height;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    codec.dispose();
    image.dispose();
    if (data == null) {
      throw const ScanFailure('Foto tidak bisa dibaca. Coba pilih foto lain.');
    }
    return (
      rgba: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      width: decodedWidth,
      height: decodedHeight,
    );
  }

  Future<Uint8List> _encodePng(Uint8List rgba, int width, int height) async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    final image = await completer.future;
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) {
      throw const ScanFailure('Hasil potongan gagal disimpan.');
    }
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }
}

// ---------------------------------------------------------------------------
// Pure helpers — unit-tested directly, no models needed.
// ---------------------------------------------------------------------------

/// RGBA bytes to interleaved NHWC floats in `[0,1]` — the matting model's input
/// layout (verified from the shipped `u2netp_320.tflite` flatbuffer, which takes
/// `[1,320,320,3]`).
Float32List rgbaToNhwcFloats(Uint8List rgba, int size) {
  final pixels = size * size;
  final out = Float32List(pixels * 3);
  for (var i = 0; i < pixels; i++) {
    out[i * 3] = rgba[i * 4] / 255;
    out[i * 3 + 1] = rgba[i * 4 + 1] / 255;
    out[i * 3 + 2] = rgba[i * 4 + 2] / 255;
  }
  return out;
}

/// Tightest box holding every mask value at or above [threshold], as fractions
/// of [size] so it maps onto any resolution. Null when the matte is empty —
/// i.e. the photo held no salient garment.
({double left, double top, double right, double bottom})? maskBoundingBox(
  Float32List mask,
  int size, {
  double threshold = 0.5,
  double margin = 0.03,
}) {
  var minX = size, minY = size, maxX = -1, maxY = -1;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      if (mask[y * size + x] < threshold) continue;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
  }
  if (maxX < 0 || maxY < 0) return null;

  return (
    left: math.max(0.0, minX / size - margin),
    top: math.max(0.0, minY / size - margin),
    right: math.min(1.0, (maxX + 1) / size + margin),
    bottom: math.min(1.0, (maxY + 1) / size + margin),
  );
}

/// Cuts the mask's box out of a full-resolution RGBA image.
({Uint8List rgba, int width, int height}) cropRgba(
  Uint8List rgba,
  int width,
  int height,
  ({double left, double top, double right, double bottom}) box,
) {
  final x0 = (box.left * width).round().clamp(0, width - 1);
  final y0 = (box.top * height).round().clamp(0, height - 1);
  final x1 = (box.right * width).round().clamp(x0 + 1, width);
  final y1 = (box.bottom * height).round().clamp(y0 + 1, height);
  final cropWidth = x1 - x0;
  final cropHeight = y1 - y0;
  final out = Uint8List(cropWidth * cropHeight * 4);
  for (var y = 0; y < cropHeight; y++) {
    out.setRange(
      y * cropWidth * 4,
      (y + 1) * cropWidth * 4,
      rgba,
      ((y0 + y) * width + x0) * 4,
    );
  }
  return (rgba: out, width: cropWidth, height: cropHeight);
}

/// Writes the matte into the crop's alpha channel and premultiplies the colour,
/// because `ui.PixelFormat.rgba8888` expects premultiplied bytes. Used only for
/// the PNG we save.
Uint8List premultipliedCutout(
  Uint8List cropRgba,
  int cropWidth,
  int cropHeight,
  Float32List mask,
  int maskSize,
) {
  final out = Uint8List(cropRgba.length);
  for (var y = 0; y < cropHeight; y++) {
    final maskRow = math.min(maskSize - 1, (y * maskSize) ~/ cropHeight) * maskSize;
    for (var x = 0; x < cropWidth; x++) {
      final alpha = mask[maskRow + math.min(maskSize - 1, (x * maskSize) ~/ cropWidth)]
          .clamp(0.0, 1.0);
      final i = (y * cropWidth + x) * 4;
      out[i] = (cropRgba[i] * alpha).round();
      out[i + 1] = (cropRgba[i + 1] * alpha).round();
      out[i + 2] = (cropRgba[i + 2] * alpha).round();
      out[i + 3] = (alpha * 255).round();
    }
  }
  return out;
}

/// Straight RGB with alpha 255 where the matte claims the pixel and alpha 0
/// elsewhere — the input for [dominantColorFromRgba], which ignores transparent
/// pixels. Kept separate from [premultipliedCutout] so the premultiplication
/// above cannot darken the sampled colours.
Uint8List garmentPixels(
  Uint8List cropRgba,
  int cropWidth,
  int cropHeight,
  Float32List mask,
  int maskSize, {
  double threshold = 0.5,
}) {
  final out = Uint8List(cropRgba.length);
  for (var y = 0; y < cropHeight; y++) {
    final maskRow = math.min(maskSize - 1, (y * maskSize) ~/ cropHeight) * maskSize;
    for (var x = 0; x < cropWidth; x++) {
      final inside =
          mask[maskRow + math.min(maskSize - 1, (x * maskSize) ~/ cropWidth)] >=
              threshold;
      final i = (y * cropWidth + x) * 4;
      out[i] = cropRgba[i];
      out[i + 1] = cropRgba[i + 1];
      out[i + 2] = cropRgba[i + 2];
      out[i + 3] = inside ? 255 : 0;
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// tflite_flutter plumbing: models differ in tensor dtypes, so every buffer is
// allocated from the tensor itself rather than assumed.
// ---------------------------------------------------------------------------

/// Zero-filled buffer matching [tensor]'s dtype, for use as the output argument.
Object bufferFor(Tensor tensor) {
  final elements = tensor.numElements();
  return switch (tensor.type) {
    TensorType.float32 => Float32List(elements),
    TensorType.float16 => Uint16List(elements),
    TensorType.int8 => Int8List(elements),
    TensorType.uint8 => Uint8List(elements),
    TensorType.int32 => Int32List(elements),
    _ => throw ScanFailure('Tipe tensor ${tensor.type} belum didukung.'),
  };
}

/// Converts float input to the tensor's dtype (float16 models need half bits).
Object packFloats(Float32List values, TensorType type) {
  if (type == TensorType.float32) return values;
  if (type == TensorType.float16) {
    final half = Uint16List(values.length);
    for (var i = 0; i < values.length; i++) {
      half[i] = floatToHalf(values[i]);
    }
    return half;
  }
  throw ScanFailure('Input model bertipe $type, bukan float.');
}

/// Reads a float or float16 output tensor back into floats.
Float32List unpackFloats(Object buffer, TensorType type) {
  if (type == TensorType.float32) return buffer as Float32List;
  if (type == TensorType.float16) {
    final half = buffer as Uint16List;
    final out = Float32List(half.length);
    for (var i = 0; i < half.length; i++) {
      out[i] = halfToFloat(half[i]);
    }
    return out;
  }
  throw ScanFailure('Output model bertipe $type, bukan float.');
}

/// Float32 bits to IEEE-754 half precision.
int floatToHalf(double value) {
  final bits = (Float32List(1)..[0] = value).buffer.asUint32List()[0];
  final sign = (bits >> 16) & 0x8000;
  final exponent = ((bits >> 23) & 0xff) - 127 + 15;
  final mantissa = bits & 0x7fffff;
  if (exponent <= 0) return sign; // underflows to zero
  if (exponent >= 31) return sign | 0x7c00; // inf / nan
  return sign | (exponent << 10) | (mantissa >> 13);
}

double halfToFloat(int half) {
  final sign = (half & 0x8000) << 16;
  var exponent = (half >> 10) & 0x1f;
  var mantissa = half & 0x3ff;
  if (exponent == 0) {
    if (mantissa == 0) return _bitsToFloat(sign);
    while ((mantissa & 0x400) == 0) {
      mantissa <<= 1;
      exponent--;
    }
    exponent++;
    mantissa &= ~0x400;
  } else if (exponent == 31) {
    return _bitsToFloat(sign | 0x7f800000 | (mantissa << 13));
  }
  return _bitsToFloat(sign | ((exponent + 127 - 15) << 23) | (mantissa << 13));
}

double _bitsToFloat(int bits) =>
    Float32List.view(Uint32List.fromList([bits]).buffer)[0];
