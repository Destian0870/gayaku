import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/logic/color_extraction.dart';

/// Builds an RGBA buffer from `(r,g,b,a)` tuples, one per pixel.
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

void main() {
  group('colorNameOf', () {
    test('names the plainest colour words', () {
      expect(colorNameOf(const Color(0xFF000000)), 'Hitam');
      expect(colorNameOf(const Color(0xFFFFFFFF)), 'Putih');
      expect(colorNameOf(const Color(0xFF1565C0)), 'Biru');
      expect(colorNameOf(const Color(0xFF6D1B2E)), 'Marun');
      expect(colorNameOf(const Color(0xFF2E7D32)), 'Hijau');
    });

    test('greys land on the grey name, not on a hue', () {
      expect(colorNameOf(const Color(0xFF9E9E9E)), 'Abu-abu');
      expect(colorNameOf(const Color(0xFF808080)), 'Abu-abu');
    });
  });

  group('dominantColorFromRgba', () {
    test('returns null when nothing is opaque', () {
      final pixels = List.filled(9, (255, 0, 0, 0));
      expect(dominantColorFromRgba(rgbaOf(pixels)), isNull);
      expect(dominantColorFromRgba(Uint8List(0)), isNull);
    });

    test('reads a flat colour and names it', () {
      final red = dominantColorFromRgba(
        rgbaOf(List.filled(64, (200, 30, 40, 255))),
      );
      expect(red, isNotNull);
      expect(red!.color, const Color(0xFFC81E28));
      expect(red.name, 'Merah');
      expect(red.coverage, closeTo(1.0, 0.01));
    });

    test('ignores transparent pixels, so the cutout background cannot win', () {
      // Left half garment-red and opaque, right half background-blue but fully
      // transparent: only the visible garment may be reported.
      final pixels = <(int, int, int, int)>[
        for (var i = 0; i < 16; i++) (200, 30, 40, 255),
        for (var i = 0; i < 16; i++) (20, 60, 200, 0),
      ];
      final dominant = dominantColorFromRgba(rgbaOf(pixels))!;
      expect(dominant.name, 'Merah');
      expect(dominant.coverage, closeTo(1.0, 0.01));
    });

    test('is deterministic across runs', () {
      final pixels = <(int, int, int, int)>[
        for (var i = 0; i < 30; i++) (18, 90, 160, 255),
        for (var i = 0; i < 12; i++) (140, 20, 30, 255),
        for (var i = 0; i < 6; i++) (240, 235, 225, 255),
      ];
      final first = dominantColorFromRgba(rgbaOf(pixels))!;
      final second = dominantColorFromRgba(rgbaOf(pixels))!;
      expect(first.color, second.color);
      expect(first.name, second.name);
    });
  });
}
