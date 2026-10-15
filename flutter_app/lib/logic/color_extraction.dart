/// Dominant-colour extraction for a scanned garment.
///
/// Runs over the RGBA pixels of the Cutout (see CONTEXT.md), so transparent
/// pixels are ignored by construction: the mask already removed the background.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Indonesian colour names shown on the scanner's "Dominant colour" row.
///
/// Nearest-name matching keeps the label stable even though K-Means returns an
/// arbitrary centroid: two similar garments never disagree by a shade name.
const colorNames = <(String, Color)>[
  ('Hitam', Color(0xFF000000)),
  ('Putih', Color(0xFFFFFFFF)),
  ('Abu-abu', Color(0xFF9E9E9E)),
  ('Krem', Color(0xFFEFE3D0)),
  ('Beige', Color(0xFFD8C3A5)),
  ('Cokelat', Color(0xFF6B4423)),
  ('Tan', Color(0xFFC08A5A)),
  ('Merah', Color(0xFFD32F2F)),
  ('Marun', Color(0xFF6D1B2E)),
  ('Oranye', Color(0xFFEF6C00)),
  ('Kuning', Color(0xFFF9D21B)),
  ('Hijau', Color(0xFF2E7D32)),
  ('Biru', Color(0xFF1565C0)),
  ('Navy', Color(0xFF1A2A4A)),
  ('Ungu', Color(0xFF6A1B9A)),
  ('Pink', Color(0xFFE9909F)),
  ('Emas', Color(0xFFC9A227)),
  ('Perak', Color(0xFFBFC1C2)),
];

/// Nearest [colorNames] entry, weighted so hue dominates for chromatic colours
/// and lightness dominates for near-greyscale ones.
String colorNameOf(Color color) {
  final hsv = HSVColor.fromColor(color);
  final chromatic = hsv.saturation >= 0.18 && hsv.value >= 0.20 && hsv.value <= 0.94;
  var best = colorNames.first.$1;
  var bestScore = double.infinity;
  for (final (name, reference) in colorNames) {
    final refHsv = HSVColor.fromColor(reference);
    final hue = chromatic
        ? math.min((hsv.hue - refHsv.hue).abs(), 360 - (hsv.hue - refHsv.hue).abs())
        : 0.0;
    final saturation = (hsv.saturation - refHsv.saturation).abs() * 60;
    final value = (hsv.value - refHsv.value).abs() * 120;
    final score = hue + saturation + value;
    if (score < bestScore) {
      bestScore = score;
      best = name;
    }
  }
  return best;
}

/// The dominant colour of a Cutout, its Indonesian name, and the share of
/// opaque pixels that colour covers.
typedef DominantColor = ({Color color, String name, double coverage});

/// K-Means over the opaque pixels of [rgba] (`width * height * 4` bytes).
///
/// Deterministic: the initial centroids are picked by even stride, not randomly,
/// so the same garment always yields the same colour. Returns null when no pixel
/// is opaque (an all-background image, i.e. the matte found no garment).
///
/// Nearly-black and nearly-white clusters are skipped when a better-covered
/// chromatic cluster exists: on a light garment the matte's soft edge leaves a
/// shell of dark fringe pixels that would otherwise win on count alone.
DominantColor? dominantColorFromRgba(
  Uint8List rgba, {
  int width = 0,
  int height = 0,
  int k = 5,
  int maxSamples = 6000,
  int seed = 7,
}) {
  final pixelCount = rgba.length ~/ 4;
  if (pixelCount == 0) return null;

  final opaque = <int>[];
  for (var i = 0; i < pixelCount; i++) {
    if (rgba[i * 4 + 3] > 128) opaque.add(i);
  }
  if (opaque.isEmpty) return null;

  final stride = math.max(1, opaque.length ~/ maxSamples);
  final samples = <List<double>>[];
  for (var i = 0; i < opaque.length; i += stride) {
    final p = opaque[i] * 4;
    samples.add([rgba[p].toDouble(), rgba[p + 1].toDouble(), rgba[p + 2].toDouble()]);
  }

  final clusters = math.max(1, math.min(k, samples.length));
  final centroids = <List<double>>[
    for (var c = 0; c < clusters; c++) samples[(c * samples.length) ~/ clusters],
  ];

  final assignment = List<int>.filled(samples.length, 0);
  for (var iteration = 0; iteration < 12; iteration++) {
    var moved = false;
    for (var i = 0; i < samples.length; i++) {
      var best = 0;
      var bestDistance = double.infinity;
      for (var c = 0; c < clusters; c++) {
        final d = _squaredDistance(samples[i], centroids[c]);
        if (d < bestDistance) {
          bestDistance = d;
          best = c;
        }
      }
      if (assignment[i] != best) {
        assignment[i] = best;
        moved = true;
      }
    }
    final sums = List<List<double>>.generate(clusters, (_) => [0, 0, 0]);
    final counts = List<int>.filled(clusters, 0);
    for (var i = 0; i < samples.length; i++) {
      final c = assignment[i];
      counts[c]++;
      for (var channel = 0; channel < 3; channel++) {
        sums[c][channel] += samples[i][channel];
      }
    }
    for (var c = 0; c < clusters; c++) {
      if (counts[c] == 0) continue;
      for (var channel = 0; channel < 3; channel++) {
        centroids[c][channel] = sums[c][channel] / counts[c];
      }
    }
    if (!moved && iteration > 0) break;
  }

  final counts = List<int>.filled(clusters, 0);
  for (final c in assignment) {
    counts[c]++;
  }

  var pick = 0;
  var pickScore = -1.0;
  for (var c = 0; c < clusters; c++) {
    if (counts[c] == 0) continue;
    final color = _colorOf(centroids[c]);
    final hsv = HSVColor.fromColor(color);
    final extreme = hsv.value < 0.10 || hsv.value > 0.92;
    final score = counts[c] * (extreme ? 0.35 : 1.0);
    if (score > pickScore) {
      pickScore = score;
      pick = c;
    }
  }

  final color = _colorOf(centroids[pick]);
  return (
    color: color,
    name: colorNameOf(color),
    coverage: counts[pick] / samples.length,
  );
}

Color _colorOf(List<double> rgb) => Color.fromARGB(
  255,
  rgb[0].round().clamp(0, 255),
  rgb[1].round().clamp(0, 255),
  rgb[2].round().clamp(0, 255),
);

double _squaredDistance(List<double> a, List<double> b) {
  final dr = a[0] - b[0];
  final dg = a[1] - b[1];
  final db = a[2] - b[2];
  return dr * dr + dg * dg + db * db;
}
