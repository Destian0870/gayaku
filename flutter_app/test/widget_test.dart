import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/screens/home_screen.dart';
import 'package:flutter_app/screens/favorites_screen.dart';
import 'package:flutter_app/screens/wardrobe_screen.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/greeting_header.dart';

void main() {
  testWidgets('HomeScreen renders all sections at 420px', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    final greeting = GreetingHeader.greetingFor(DateTime.now());
    expect(find.textContaining(greeting.split(',').first), findsOneWidget);
    expect(find.text('Isabella'), findsOneWidget);
    expect(find.text("Today's Look"), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            (w.decoration?.hintText ?? '').startsWith('Search by occasion'),
      ),
      findsOneWidget,
    );
    expect(find.text('Quick Actions'), findsOneWidget);
    expect(find.text('Recently Added'), findsOneWidget);
  });

  testWidgets('Your Favorite opens Wardrobe favorites', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.ensureVisible(find.text('Your Favorite'));
    await tester.tap(find.text('Your Favorite'));
    await tester.pumpAndSettle();

    expect(find.byType(WardrobeScreen), findsOneWidget);
    expect(find.text('Kombinasi (0)'), findsOneWidget);
    expect(find.text('Favorit'), findsOneWidget);
    expect(find.text('Belum ada favorit tersimpan.'), findsOneWidget);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.checkroom_outlined)).color,
      AppPalette.light.ink,
    );
    expect(
      (tester.widget<Text>(find.text('Favorit')).style?.color),
      AppPalette.light.onAction,
    );
  });

  testWidgets('Outfit detail shows look components and actions', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: FavoritesScreen()));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beige Trench & Denim'));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -520));
    await tester.pumpAndSettle();
    expect(find.text('Items in this Look'), findsOneWidget);
    expect(find.text('Color Harmony'), findsOneWidget);
    expect(find.text('94% Match'), findsOneWidget);
    expect(find.text('Swap Item'), findsOneWidget);
    expect(find.text('Saved Look'), findsOneWidget);
  });

  testWidgets('Favorites sorting modal changes the active sort option', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: FavoritesScreen()));

    expect(find.text('Newest'), findsOneWidget);
    await tester.tap(find.byTooltip('Sort favorites'));
    await tester.pumpAndSettle();

    expect(find.text('Sort Favorite Looks'), findsOneWidget);
    expect(find.text('Newest first'), findsOneWidget);
    expect(find.text('Oldest first'), findsOneWidget);
    expect(find.text('A-Z'), findsOneWidget);
    expect(find.text('Z-A'), findsOneWidget);

    await tester.tap(find.text('A-Z'));
    await tester.pumpAndSettle();

    expect(find.text('A-Z'), findsOneWidget);
    expect(find.text('Sort Favorite Looks'), findsNothing);
  });
}
