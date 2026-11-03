import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/models/wardrobe.dart';
import 'package:flutter_app/state/wardrobe_store.dart';

/// The wardrobe store on a real SQLite file, through the ffi factory — the
/// same schema the device runs, no device required.
void main() {
  late Directory tempDir;
  late String dbPath;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('gayaku_wardrobe');
    dbPath = '${tempDir.path}/wardrobe.db';
  });

  tearDown(() async {
    // Windows keeps the file locked until the connection is closed.
    await closeWardrobeStore();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('a fresh file is seeded with the nine demo garments', () async {
    await initWardrobeStore(factory: databaseFactoryFfi, path: dbPath);

    expect(seedWardrobeItems, hasLength(9));
    expect(
      wardrobeItems.value.map((i) => i.id).toList(),
      seedWardrobeItems.map((i) => i.id).toList(),
    );

    // Every column survives the round trip through SQLite.
    final blouse = wardrobeItems.value.first;
    expect(blouse.name, 'Silk Blouse');
    expect(blouse.category, 'Tops');
    expect(blouse.subcategory, isNull);
    expect(blouse.brand, 'Zara');
    expect(blouse.colorName, 'Krem');
    expect(blouse.color, const Color(0xFFEFE3D0));
    expect(blouse.formality, 4);
    expect(blouse.occasions, const ['Formal', 'Smart-Casual']);
  });

  test('opening the same file again neither re-seeds nor loses rows', () async {
    await initWardrobeStore(factory: databaseFactoryFfi, path: dbPath);
    await initWardrobeStore(factory: databaseFactoryFfi, path: dbPath);

    expect(wardrobeItems.value, hasLength(9));
  });

  test('concurrent opens serialise onto one connection', () async {
    await Future.wait([
      initWardrobeStore(factory: databaseFactoryFfi, path: dbPath),
      initWardrobeStore(factory: databaseFactoryFfi, path: dbPath),
    ]);

    expect(wardrobeItems.value, hasLength(9));
  });

  test('addWardrobeItem is still there after reopening the file', () async {
    await initWardrobeStore(factory: databaseFactoryFfi, path: dbPath);

    final scanned = WardrobeItem(
      id: newWardrobeItemId(),
      name: 'Kaos Oversize',
      category: 'Tops',
      subcategory: 'Kaos',
      imagePath: '${tempDir.path}/cutouts/kaos.png',
      colorName: 'Hitam',
      color: const Color(0xFF1A1A1A),
      formality: 2,
      occasions: const ['Kasual'],
    );
    await addWardrobeItem(scanned);
    expect(wardrobeItems.value, hasLength(10));

    // A restart: the in-memory list is gone, the file is reopened.
    wardrobeItems.value = const [];
    await initWardrobeStore(factory: databaseFactoryFfi, path: dbPath);

    final stored = wardrobeItems.value.singleWhere((i) => i.id == scanned.id);
    expect(stored.name, 'Kaos Oversize');
    expect(stored.subcategory, 'Kaos');
    expect(stored.imagePath, '${tempDir.path}/cutouts/kaos.png');
    expect(stored.colorName, 'Hitam');
    expect(stored.color, const Color(0xFF1A1A1A));
    expect(stored.formality, 2);
    expect(stored.occasions, const ['Kasual']);
    expect(wardrobeItems.value, hasLength(10), reason: 'not seeded twice');
  });

  test('deleteWardrobeItem drops the row, and reaches the file', () async {
    await initWardrobeStore(factory: databaseFactoryFfi, path: dbPath);

    await deleteWardrobeItem('seed-linen-shirt');
    expect(wardrobeItems.value, hasLength(8));
    expect(wardrobeItems.value.any((i) => i.id == 'seed-linen-shirt'), isFalse);

    wardrobeItems.value = const [];
    await initWardrobeStore(factory: databaseFactoryFfi, path: dbPath);
    expect(wardrobeItems.value, hasLength(8));

    // An id that is not there is a no-op, not a crash.
    await deleteWardrobeItem('seed-does-not-exist');
    expect(wardrobeItems.value, hasLength(8));
  });

  test('two garments may share a name under different ids', () async {
    await initWardrobeStore(factory: databaseFactoryFfi, path: dbPath);

    final first = WardrobeItem(
      id: newWardrobeItemId(),
      name: 'Kaos Putih',
      category: 'Tops',
      imagePath: '${tempDir.path}/cutouts/kaos-1.png',
    );
    final second = WardrobeItem(
      id: newWardrobeItemId(),
      name: 'Kaos Putih',
      category: 'Tops',
      imagePath: '${tempDir.path}/cutouts/kaos-2.png',
    );
    expect(first.id, isNot(second.id));

    await addWardrobeItem(first);
    await addWardrobeItem(second);

    expect(
      wardrobeItems.value.where((i) => i.name == 'Kaos Putih'),
      hasLength(2),
      reason: 'the name-keyed store could only ever hold one',
    );

    // Distinct rows: deleting one keeps the other.
    await deleteWardrobeItem(first.id);
    final remaining = wardrobeItems.value
        .where((i) => i.name == 'Kaos Putih')
        .single;
    expect(remaining.id, second.id);
    expect(remaining.imagePath, '${tempDir.path}/cutouts/kaos-2.png');
  });

  test('newWardrobeItemId never repeats', () {
    final ids = {for (var i = 0; i < 2000; i++) newWardrobeItemId()};
    expect(ids, hasLength(2000));
  });
}
