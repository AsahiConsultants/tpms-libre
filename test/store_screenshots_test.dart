@Tags(['golden'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tpms_libre/treel/model.dart';
import 'package:tpms_libre/treel/reading.dart';
import 'package:tpms_libre/treel/scanner.dart';
import 'package:tpms_libre/ui/home_page.dart';
import 'package:tpms_libre/ui/settings_sheet.dart';
import 'package:tpms_libre/ui/theme.dart';

import 'support/fonts.dart';

/// Renders the F-Droid listing screenshots from the real widgets, at a real
/// phone's resolution, straight into the fastlane folder — so the store
/// images cannot drift from what the app looks like:
///
///   flutter test --tags golden --run-skipped test/store_screenshots_test.dart
///
/// Not a golden comparison: golden files are captured at logical resolution,
/// which for a 1080-pixel-wide phone is a 412-pixel-wide image. These are
/// rendered at the device pixel ratio and written out directly.
///
/// The data is made up: invented sensor ids, plausible pressures.

const _shots = 'fastlane/metadata/android/en-US/images/phoneScreenshots';

/// A 1080 x 2400 phone at 420 dpi, the shape of most current Android phones.
const _ratio = 2.625;

/// A scanner that reports it is listening, without a radio to listen with.
class _Listening extends TreelScanner {
  _Listening(super.model);
  @override
  ScanStatus get status => ScanStatus.scanning;
}

final _frame = GlobalKey();

Future<void> _show(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = _ratio;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _frame,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: home,
      ),
    ),
  );
  await tester.pump();
}

/// Writes what is on screen at the device's own pixel ratio. Encoding an
/// image needs a real clock, hence runAsync.
Future<void> _capture(WidgetTester tester, String file) async {
  await tester.runAsync(() async {
    final boundary =
        _frame.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: _ratio);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    File('$_shots/$file')
      ..createSync(recursive: true)
      ..writeAsBytesSync(png!.buffer.asUint8List());
  });
}

Future<TreelModel> _vehicle(
  String name,
  WheelLayout layout,
  List<(int, int)> readings,
) async {
  final model = TreelModel();
  await model.load();
  await model.setAnimations(false);
  await model.renameVehicle(model.vehicle.id, name);
  await model.setLayout(model.vehicle.id, layout);
  await model.setSpec(
    model.vehicle.spec.copyWith(front: 33, rear: 33, spare: 30),
  );
  for (final (i, p) in model.positions.indexed) {
    final id = 'd0e00${i + 1}';
    final (psi, celsius) = readings[i];
    model.ingest(
      TreelReading(
        sensorId: id,
        psi: psi,
        celsius: celsius,
        rssi: -62,
        at: DateTime.now(),
      ),
    );
    await model.assign(id, p);
  }
  return model;
}

void main() {
  setUpAll(loadFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a car with a spare, one tyre low', (tester) async {
    final model = await _vehicle('My car', WheelLayout.carWithSpare, [
      (33, 29),
      (34, 29),
      (29, 28),
      (33, 30),
      (30, 26),
    ]);
    try {
      await _show(tester, HomePage(model: model, scanner: _Listening(model)));
      await _capture(tester, '1.png');
    } finally {
      model.dispose();
    }
  });

  testWidgets('a motorcycle', (tester) async {
    final model = await _vehicle('My motorcycle', WheelLayout.motorcycle, [
      (32, 31),
      (34, 33),
    ]);
    try {
      await _show(tester, HomePage(model: model, scanner: _Listening(model)));
      await _capture(tester, '2.png');
    } finally {
      model.dispose();
    }
  });

  testWidgets('target pressures', (tester) async {
    await _show(
      tester,
      Scaffold(
        body: SafeArea(
          child: SettingsSheet(
            vehicleName: 'My car',
            layout: WheelLayout.carWithSpare,
            spec: const PressureSpec(front: 33, rear: 33, spare: 30),
            onChanged: (_) {},
            haptics: true,
            animations: true,
            onHaptics: (_) {},
            onAnimations: (_) {},
          ),
        ),
      ),
    );
    await _capture(tester, '3.png');
  });
}
