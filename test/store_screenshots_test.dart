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
import 'package:tpms_libre/ui/tyre.dart';

import 'support/fonts.dart';

/// Renders the F-Droid listing screenshots from the real widgets, at a real
/// phone's resolution, straight into the fastlane folder — so the store
/// images cannot drift from what the app looks like:
///
///   flutter test --tags golden --run-skipped test/store_screenshots_test.dart
///
/// The vehicles are shown with an owner's photo, as the app is meant to be
/// used. The photos are Pexels photos in `test/screenshot_photos/`, which
/// says where they come from and that they are not under the MIT licence.
/// SHOT_CAR and SHOT_BIKE try other photos, and SHOT_OUT writes somewhere
/// other than fastlane, for comparing candidates:
///
///   --dart-define=SHOT_CAR=/path/to/car.jpg --dart-define=SHOT_OUT=/tmp/x
///
/// Not a golden comparison: golden files are captured at logical resolution,
/// which for a 1080-pixel-wide phone is a 412-pixel-wide image. These are
/// rendered at the device pixel ratio and written out directly.
///
/// The data is made up: invented sensor ids, plausible pressures. The
/// vehicles are named after what is in the photos, as an owner would name
/// theirs. The
/// vehicles are named after what is in the photos, as an owner would name
/// theirs.

const _out = String.fromEnvironment(
  'SHOT_OUT',
  defaultValue: 'fastlane/metadata/android/en-US/images/phoneScreenshots',
);
const _carPhoto = String.fromEnvironment(
  'SHOT_CAR',
  defaultValue: 'test/screenshot_photos/honda-nsx-wavyvisuals.jpg',
);
const _bikePhoto = String.fromEnvironment(
  'SHOT_BIKE',
  defaultValue: 'test/screenshot_photos/tvs-apache-rr310-akash-a-g.jpg',
);

/// A 1080 x 2400 phone at 420 dpi, the shape of most current Android phones.
const _ratio = 2.625;
const _upright = Size(1080, 2400);
const _onItsSide = Size(2400, 1080);

/// A scanner that reports it is listening, without a radio to listen with.
class _Listening extends TreelScanner {
  _Listening(super.model);
  @override
  ScanStatus get status => ScanStatus.scanning;
}

final _frame = GlobalKey();

/// Puts [home] on screen and lets any photo on it load. Decoding an image
/// needs a real clock, which a widget test does not have outside runAsync.
Future<void> _show(
  WidgetTester tester,
  Widget home, {
  Size size = _upright,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = _ratio;
  addTearDown(tester.view.reset);
  await tester.runAsync(() async {
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
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
  });
  await tester.pump();
}

Future<void> _open(WidgetTester tester, Finder target) async {
  await tester.tap(target);
  await tester.pumpAndSettle();
}

/// Writes what is on screen at the device's own pixel ratio.
Future<void> _capture(WidgetTester tester, String file) async {
  await tester.runAsync(() async {
    final boundary =
        _frame.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: _ratio);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    File('$_out/$file')
      ..createSync(recursive: true)
      ..writeAsBytesSync(png!.buffer.asUint8List());
  });
}

Directory _photoDir() {
  final d = Directory.systemTemp.createTempSync('tpmslibre-shots');
  addTearDown(() {
    if (d.existsSync()) d.deleteSync(recursive: true);
  });
  return d;
}

/// A vehicle with its readings. Every sensor is placed unless [unplaced]
/// names a position to leave empty, with its sensor heard but not assigned.
Future<TreelModel> _vehicle(
  WidgetTester tester,
  String name,
  WheelLayout layout,
  List<(int, int)> readings, {
  String photo = '',
  TyrePosition? unplaced,
}) async {
  final model = TreelModel(photos: PhotoStore(directory: _photoDir()));
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
    if (p != unplaced) await model.assign(id, p);
  }
  if (photo.isNotEmpty) {
    await tester.runAsync(() => model.setPhoto(model.vehicle.id, File(photo)));
  }
  return model;
}

/// The car in every shot: one tyre a few psi down, so there is something to
/// say, and the spare a little cooler for having done no work.
Future<TreelModel> _car(WidgetTester tester, {TyrePosition? unplaced}) =>
    _vehicle(
      tester,
      'Honda NSX',
      WheelLayout.carWithSpare,
      [(33, 29), (34, 29), (29, 28), (33, 30), (30, 26)],
      photo: _carPhoto,
      unplaced: unplaced,
    );

Widget _home(TreelModel model) =>
    HomePage(model: model, scanner: _Listening(model));

void main() {
  setUpAll(loadFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // In listing order: the screen itself first, then what each tap opens.

  testWidgets('1: a car with a spare, one tyre low', (tester) async {
    final model = await _car(tester);
    try {
      await _show(tester, _home(model));
      await _capture(tester, '1.png');
    } finally {
      model.dispose();
    }
  });

  testWidgets('2: one wheel up close', (tester) async {
    final model = await _car(tester);
    try {
      await _show(tester, _home(model));
      await _open(tester, find.byType(TyreCard).at(2));
      await _capture(tester, '2.png');
    } finally {
      model.dispose();
    }
  });

  testWidgets('3: a motorcycle', (tester) async {
    final model = await _vehicle(
      tester,
      'TVS Apache RR310',
      WheelLayout.motorcycle,
      [(32, 31), (34, 33)],
      photo: _bikePhoto,
    );
    try {
      await _show(tester, _home(model));
      await _capture(tester, '3.png');
    } finally {
      model.dispose();
    }
  });

  testWidgets('4: target pressures', (tester) async {
    await _show(
      tester,
      Scaffold(
        body: SafeArea(
          child: SettingsSheet(
            vehicleName: 'Honda NSX',
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
    await _capture(tester, '4.png');
  });

  testWidgets('5: rotating the tyres', (tester) async {
    final model = await _car(tester);
    try {
      await _show(tester, _home(model));
      await _open(tester, find.byType(TyreCard).first);
      await _open(tester, find.text('Rotate this wheel'));
      await _capture(tester, '5.png');
    } finally {
      model.dispose();
    }
  });

  testWidgets('6: putting a sensor on a wheel', (tester) async {
    final model = await _car(tester, unplaced: TyrePosition.spare);
    try {
      await _show(tester, _home(model));
      await _open(tester, find.byType(TyreCard).last);
      await _open(tester, find.text('Assign a sensor'));
      await _capture(tester, '6.png');
    } finally {
      model.dispose();
    }
  });

  testWidgets('7: more than one vehicle', (tester) async {
    final model = await _car(tester);
    try {
      final car = model.vehicle.id;
      await model.addVehicle('TVS Apache RR310', WheelLayout.motorcycle);
      await model.selectVehicle(car);
      await _show(tester, _home(model));
      await _open(tester, find.text('Honda NSX'));
      await _capture(tester, '7.png');
    } finally {
      model.dispose();
    }
  });

  testWidgets('8: adding a vehicle', (tester) async {
    final model = await _car(tester);
    try {
      await _show(tester, _home(model));
      await _open(tester, find.text('Honda NSX'));
      await _open(tester, find.text('Add a vehicle'));
      await _capture(tester, '8.png');
    } finally {
      model.dispose();
    }
  });

  testWidgets('9: the photo stays on the phone', (tester) async {
    final model = await _car(tester);
    try {
      await _show(tester, _home(model));
      await _open(
        tester,
        _carPhoto.isEmpty
            ? find.text('Add a photo of your vehicle')
            : find.byType(Image).first,
      );
      await _capture(tester, '9.png');
    } finally {
      model.dispose();
    }
  });

  testWidgets('10: on its side, in a car mount', (tester) async {
    final model = await _car(tester);
    try {
      await _show(tester, _home(model), size: _onItsSide);
      await _capture(tester, '10.png');
    } finally {
      model.dispose();
    }
  });
}
