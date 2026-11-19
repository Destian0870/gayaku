import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/logic/outfit_matcher.dart';
import 'package:flutter_app/models/wardrobe.dart';

WardrobeItem _item(
  String id,
  String name,
  String category, {
  Color color = const Color(0xFF222222),
  int formality = 3,
  List<String> occasions = const ['Kasual'],
}) => WardrobeItem(
  id: id,
  name: name,
  category: category,
  imagePath: '',
  color: color,
  formality: formality,
  occasions: occasions,
);

void main() {
  final catalog = <WardrobeItem>[
    _item(
      't1',
      'Kemeja Putih',
      'Tops',
      color: const Color(0xFFF2F2F2),
      formality: 4,
      occasions: const ['Formal', 'Kasual'],
    ),
    _item(
      't2',
      'Kaos Hitam',
      'Tops',
      color: const Color(0xFF1A1A1A),
      formality: 1,
      occasions: const ['Sport'],
    ),
    _item(
      'b1',
      'Chino Krem',
      'Bottoms',
      color: const Color(0xFFD9C7A7),
      formality: 4,
      occasions: const ['Formal', 'Kasual'],
    ),
    _item(
      'b2',
      'Celana Sport',
      'Bottoms',
      color: const Color(0xFF2B4C7E),
      formality: 1,
      occasions: const ['Sport'],
    ),
    _item(
      's1',
      'Sneakers Putih',
      'Shoes',
      color: const Color(0xFFEFEFEF),
      formality: 2,
      occasions: const ['Kasual', 'Sport'],
    ),
  ];

  test('fills one garment per slot with compatible pieces', () {
    final filled = autoFillOutfit(catalog);

    expect(filled.length, greaterThanOrEqualTo(3));
    expect(filled.map((i) => i.category).toSet().length, filled.length);
    expect(outfitScore(filled), greaterThan(0.5));
  });

  test('honours the chosen theme', () {
    final sport = autoFillOutfit(catalog, occasion: 'Sport');
    expect(sport, isNotEmpty);
    expect(sport.every((i) => i.occasions.contains('Sport')), isTrue);

    final formal = autoFillOutfit(catalog, occasion: 'Formal');
    expect(formal.every((i) => i.occasions.contains('Formal')), isTrue);
    expect(outfitScore(formal), greaterThan(0));
  });

  test('a seeded random still produces a valid outfit', () {
    for (var seed = 0; seed < 8; seed++) {
      final filled = autoFillOutfit(catalog, random: Random(seed));
      expect(filled.length, greaterThanOrEqualTo(3));
      expect(outfitScore(filled), greaterThan(0));
    }
  });

  test('too few garments is not an error', () {
    expect(autoFillOutfit(const []), isEmpty);
    expect(autoFillOutfit([catalog.first]), isEmpty);
  });
}
