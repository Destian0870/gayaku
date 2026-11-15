import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/navigation.dart';
import 'package:flutter_app/screens/home_screen.dart';
import 'package:flutter_app/screens/wardrobe_screen.dart';
import 'package:flutter_app/state/wardrobe_store.dart';
import 'package:flutter_app/widgets/home_bottom_nav.dart';

import 'fixtures.dart';

/// Guards the shell contract: one bar that never moves, pages that slide,
/// and the wardrobe handle that opens the combination tab.
void main() {
  late Directory tempDir;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('gayaku_nav_shell');
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

  testWidgets('one bar stays put while the page slides in', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: NavShell()));
    await tester.pumpAndSettle();

    final restingBar = tester.getRect(find.byType(HomeBottomNav));

    await tester.tap(find.text('Wardrobe'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));

    // Mid-flight: still exactly one bar, and it has not moved a pixel.
    expect(find.byType(HomeBottomNav), findsOneWidget);
    expect(tester.getRect(find.byType(HomeBottomNav)), restingBar);
    expect(find.byType(WardrobeScreen), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsNothing);
    expect(tester.getRect(find.byType(HomeBottomNav)), restingBar);
  });

  testWidgets('back from a page returns home instead of closing the app', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: NavShell(initialIndex: 1)));
    await tester.pumpAndSettle();
    expect(find.byType(WardrobeScreen), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('tapping the wardrobe item lands on the catalog', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: NavShell()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Wardrobe'));
    await tester.pumpAndSettle();

    expect(find.text('Katalog'), findsOneWidget);
    expect(find.text('Total ${wardrobeFixture.length} items'), findsOneWidget);
  });

  testWidgets('holding the handle drops a menu out of the bar', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: NavShell()));
    await tester.pumpAndSettle();

    final barTop = tester.getRect(find.byType(HomeBottomNav)).top;
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Wardrobe')),
    );
    // Shorter than the platform's 500 ms, so a short hold is enough.
    await tester.pump(const Duration(milliseconds: 300));

    // The menu is part of the bar: not a bottom sheet, and it sits directly
    // above the pill instead of floating somewhere else.
    expect(find.text('Kombinasi'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.getRect(find.text('Kombinasi')).bottom, lessThan(barTop));

    // Slide onto the row while still holding, then lift the finger.
    await gesture.moveTo(tester.getCenter(find.text('Kombinasi')));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('Total 0 kombinasi'), findsOneWidget);
  });

  testWidgets('a hold released in place still opens the catalog', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: NavShell()));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Wardrobe')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Kombinasi'), findsOneWidget);

    await gesture.up();
    await tester.pumpAndSettle();

    // The menu is gone and the tap intent won: the catalog, not combinations.
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Katalog'), findsOneWidget);
    expect(find.text('Total ${wardrobeFixture.length} items'), findsOneWidget);
  });
}
