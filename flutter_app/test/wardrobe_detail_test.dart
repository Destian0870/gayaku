import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/models/wardrobe.dart';
import 'package:flutter_app/screens/wardrobe_item_detail_screen.dart';
import 'package:flutter_app/state/outfit_store.dart';
import 'package:flutter_app/state/wardrobe_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Directory temp;

  const item = WardrobeItem(
    id: 'item-1',
    name: 'Kemeja Linen',
    category: 'Tops',
    imagePath: '',
  );

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('wardrobe_detail');
    await initWardrobeStore(
      factory: databaseFactoryFfi,
      path: '${temp.path}/wardrobe.db',
    );
    await addWardrobeItem(item);
    savedOutfits.value = const [];
  });

  tearDown(() async {
    savedOutfits.value = const [];
    await closeWardrobeStore();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  /// SQLite finishes on the real clock, which fake-async pauses.
  Future<void> settleRealAsync() =>
      Future<void>.delayed(const Duration(milliseconds: 300));

  Future<void> pumpDetail(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WardrobeItemDetailScreen(item: item, catalog: [item]),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('editing a garment saves the new name', (tester) async {
    await pumpDetail(tester);

    await tester.tap(find.byTooltip('Edit baju'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Nama'),
      'Kemeja Baru',
    );
    // The save writes through SQLite, which needs the real clock.
    await tester.runAsync(() async {
      await tester.tap(find.text('Simpan Perubahan'));
      await tester.pumpAndSettle();
      await settleRealAsync();
    });

    expect(wardrobeItems.value.single.name, 'Kemeja Baru');
    await tester.pumpAndSettle();
    expect(find.text('Kemeja Baru'), findsWidgets);
  });

  testWidgets('an unused garment can be deleted', (tester) async {
    await pumpDetail(tester);

    await tester.tap(find.byTooltip('Hapus baju'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(TextButton, 'Hapus'));
      await tester.pumpAndSettle();
      await settleRealAsync();
    });

    expect(wardrobeItems.value, isEmpty);
  });

  testWidgets('a garment inside a combination is not deleted', (tester) async {
    savedOutfits.value = [
      SavedOutfit(
        id: newOutfitId(),
        name: 'Setelan Kemeja',
        itemIds: const ['item-1'],
        threshold: 0.8,
        createdAt: DateTime(2026),
      ),
    ];
    await pumpDetail(tester);

    await tester.tap(find.byTooltip('Hapus baju'));
    await tester.pumpAndSettle();

    expect(wardrobeItems.value, hasLength(1));
    expect(find.textContaining('Masih dipakai di 1 kombinasi'), findsOneWidget);
  });

  testWidgets('the detail page says whether the item is combined', (
    tester,
  ) async {
    await pumpDetail(tester);
    expect(find.text('Belum dikombinasi'), findsOneWidget);

    savedOutfits.value = [
      SavedOutfit(
        id: newOutfitId(),
        name: 'Setelan Kemeja',
        itemIds: const ['item-1'],
        threshold: 0.8,
        createdAt: DateTime(2026),
      ),
    ];
    await pumpDetail(tester);
    expect(find.text('Dipakai di 1 kombinasi'), findsOneWidget);
  });
}
