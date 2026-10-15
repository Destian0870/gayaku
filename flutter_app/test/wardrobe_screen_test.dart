import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/screens/wardrobe_screen.dart';
import 'package:flutter_app/state/outfit_store.dart';
import 'package:flutter_app/state/wardrobe_store.dart';

void main() {
  // The screen reads the real SQLite store, so every test opens one on a temp
  // file through the ffi factory — never a device database.
  late Directory tempDir;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('gayaku_wardrobe_screen');
    await initWardrobeStore(
      factory: databaseFactoryFfi,
      path: '${tempDir.path}/wardrobe.db',
    );
  });

  tearDown(() async {
    // Windows keeps the file locked until the connection is closed.
    await closeWardrobeStore();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  testWidgets('WardrobeScreen shows catalog and filters by chip', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: WardrobeScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Wardrobe'), findsWidgets);
    expect(find.text('Total 9 items'), findsOneWidget);
    expect(find.text('Silk Blouse'), findsOneWidget);
    expect(find.text('Tops • Zara'), findsOneWidget);

    await tester.tap(find.text('Bottoms'));
    await tester.pumpAndSettle();

    expect(find.text('Straight Leg Jeans'), findsOneWidget);
    expect(find.text('Silk Blouse'), findsNothing);
  });

  testWidgets('WardrobeScreen switches tabs, searches and filters', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: WardrobeScreen()),
    );
    await tester.pumpAndSettle();

    // Both tabs are offered, and the combinations tab starts empty.
    expect(find.text('Katalog'), findsOneWidget);
    expect(find.text('Kombinasi (0)'), findsOneWidget);
    await tester.tap(find.text('Kombinasi (0)'));
    await tester.pumpAndSettle();
    expect(find.text('Buat Kombinasi'), findsOneWidget);
    expect(find.text('Belum ada kombinasi tersimpan.'), findsOneWidget);

    await tester.tap(find.text('Katalog'));
    await tester.pumpAndSettle();

    // Search narrows the grid to the matching item.
    await tester.enterText(find.byType(TextField), 'trench');
    await tester.pumpAndSettle();
    expect(find.text('Beige Trench'), findsOneWidget);
    expect(find.text('Silk Blouse'), findsNothing);

    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();

    // The filter sheet lists the occasions in the catalog and applies one.
    await tester.tap(find.byTooltip('Filter'));
    await tester.pumpAndSettle();
    expect(find.text('Formalitas minimal'), findsOneWidget);
    await tester.tap(find.text('Formal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Terapkan'));
    await tester.pumpAndSettle();

    expect(find.text('Silk Blouse'), findsOneWidget);
    expect(find.text('Classic Sneakers'), findsNothing);
  });

  testWidgets('WardrobeScreen favourite button marks a combination', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    savedOutfits.value = [
      SavedOutfit(
        id: 'test-1',
        name: 'Kombinasi Uji',
        itemIds: const ['seed-silk-blouse', 'seed-straight-leg-jeans'],
        threshold: 0.80,
      ),
    ];
    addTearDown(() => savedOutfits.value = []);

    await tester.pumpWidget(
      const MaterialApp(home: WardrobeScreen()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Kombinasi (1)'));
    await tester.pumpAndSettle();

    expect(find.text('Kombinasi Uji'), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    expect(find.byTooltip('Tandai favorit'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(find.byTooltip('Hapus dari favorit'), findsOneWidget);
    expect(savedOutfits.value.single.favorite, isTrue);
  });
}
