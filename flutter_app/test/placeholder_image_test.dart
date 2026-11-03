import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/widgets/placeholder_image.dart';

void main() {
  testWidgets('a bundled asset is drawn through Image.asset', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PlaceholderImage(
          imagePath: 'assets/images/silk_blouse.png',
          icon: Icons.checkroom_outlined,
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as AssetImage).assetName,
      'assets/images/silk_blouse.png',
    );
  });

  testWidgets('a scanned cutout is drawn from its absolute file path', (
    tester,
  ) async {
    final cutout = '${Directory.systemTemp.path}/gayaku_cutout_test.png';
    expect(File(cutout).isAbsolute, isTrue, reason: 'scanner writes abs paths');

    await tester.pumpWidget(
      MaterialApp(
        home: PlaceholderImage(
          imagePath: cutout,
          icon: Icons.checkroom_outlined,
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as FileImage).file.path, cutout);
  });

  testWidgets('a missing file leaves the placeholder instead of crashing', (
    tester,
  ) async {
    final missing = '${Directory.systemTemp.path}/gayaku_nope/cutout.png';

    await tester.pumpWidget(
      MaterialApp(
        home: PlaceholderImage(
          imagePath: missing,
          icon: Icons.checkroom_outlined,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.checkroom_outlined), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });
}
