@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tpms_libre/treel/model.dart';
import 'package:tpms_libre/treel/reading.dart';
import 'package:tpms_libre/treel/scanner.dart';
import 'package:tpms_libre/ui/home_page.dart';
import 'package:tpms_libre/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fonts.dart';

/// Renders the home screen to PNGs so the vehicle drawings can be looked at.
///
/// Hand-authoring a silhouette as Bezier paths without seeing the result is
/// guesswork, and a build-install-screenshot round trip per adjustment makes
/// it slow guesswork. This runs the real widgets in about a second.
///
/// It renders the whole screen rather than the painter alone, because the
/// wheel cards are part of the composition: the forks and swingarm are
/// supposed to disappear behind them, and a painter previewed on its own
/// looks wrong in ways the real thing is not.
///
///   flutter test --update-goldens test/vehicle_art_test.dart
Future<void> shoot(
  WidgetTester tester,
  String name,
  WheelLayout layout, {
  VehicleArt art = VehicleArt.generic,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(411, 915) * 2.0;
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  final model = TreelModel();
  try {
    await model.load();
    await model.setAnimations(false);
    await model.setLayout(model.vehicle.id, layout);
    await model.setArt(model.vehicle.id, art);
    for (final (i, p) in model.positions.indexed) {
      final id = 'sensor$i';
      model.ingest(
        TreelReading(
          sensorId: id,
          psi: 32 + i,
          celsius: 24,
          rssi: -70,
          at: DateTime.now(),
        ),
      );
      await model.assign(id, p);
    }

    final app = MaterialApp(
      theme: buildTheme(),
      home: HomePage(model: model, scanner: TreelScanner(model)),
    );

    // Real artwork has to be read off disk and decoded, which the fake async
    // clock in a widget test will never let finish. runAsync gives it a real
    // one; without this the drawing renders as an empty box.
    await tester.runAsync(() async {
      await tester.pumpWidget(app);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();
    await expectLater(
      find.byType(HomePage),
      matchesGoldenFile('goldens/$name.png'),
    );
  } finally {
    model.dispose();
  }
}

void main() {
  setUpAll(loadFonts);

  // A vehicle with no picture yet: the prompt and the readings.
  for (final layout in WheelLayout.values) {
    testWidgets('${layout.label} with no picture', (tester) async {
      await shoot(tester, 'plain-${layout.name}', layout);
    });
  }

  for (final art in VehicleArt.values.where((a) => a.hasAsset)) {
    final layout = art.suits.last;
    testWidgets('${layout.label} drawn as ${art.label}', (tester) async {
      await shoot(tester, 'art-${art.name}', layout, art: art);
    });
  }
}
