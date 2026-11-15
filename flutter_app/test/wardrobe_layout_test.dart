import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/screens/home_screen.dart';
import 'package:flutter_app/screens/wardrobe_screen.dart';
import 'package:flutter_app/state/wardrobe_store.dart';
import 'package:flutter_app/widgets/home_bottom_nav.dart';
import 'package:flutter_app/widgets/wardrobe_item_card.dart';

import 'fixtures.dart';

/// Guard for the phone-sized layout: the nav pill must stay pinned to the
/// bottom edge and nothing may overflow while the catalog scrolls.
void main() {
  late Directory tempDir;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('gayaku_wardrobe_layout');
    await initWardrobeStore(
      factory: databaseFactoryFfi,
      path: '${tempDir.path}/wardrobe.db',
    );
    for (final item in wardrobeFixture) {
      await addWardrobeItem(item);
    }
  });

  tearDown(() async {
    await closeWardrobeStore();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  testWidgets('catalog fits a 360x780 phone without moving the nav', (
    WidgetTester tester,
  ) async {
    // Infinix X6851: 1080x2436 px at 3.0 dpr.
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();
    final homeNav = tester.getRect(find.byType(HomeBottomNav));

    await tester.pumpWidget(const MaterialApp(home: WardrobeScreen()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    final nav = tester.getRect(find.byType(HomeBottomNav));
    // Same pill, same place: the Wardrobe page may not shift the taskbar.
    expect(nav, homeNav);
    expect(nav.bottom, lessThanOrEqualTo(780));
    expect(nav.bottom, greaterThanOrEqualTo(740));
    expect(nav.width, 320);

    debugPrint('nav=$nav search=${tester.getRect(find.byType(TextField))}');
    debugPrint('firstTile=${tester.getRect(find.byType(WardrobeItemCard).first)}');

    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
