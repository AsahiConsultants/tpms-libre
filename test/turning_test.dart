import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tpms_libre/treel/model.dart';
import 'package:tpms_libre/treel/reading.dart';
import 'package:tpms_libre/treel/scanner.dart';
import 'package:tpms_libre/ui/home_page.dart';
import 'package:tpms_libre/ui/theme.dart';
import 'package:tpms_libre/ui/tyre.dart';

/// Turning the phone with a screen open must leave it exactly as if it had
/// been opened that way round.
///
/// The settings sheet did not: it took its width from the screen it was
/// opened on and kept it, so opened upright and then turned on its side it
/// squeezed three columns into the upright width. Every screen is opened
/// both ways, in both directions, and the two pictures compared pixel for
/// pixel. Both are rendered here and now, so unlike the golden images this
/// holds on any machine.

/// A 1080 x 2400 phone. On its side the camera cutout is on the left, so
/// turning changes the insets as well as the size.
class Pose {
  const Pose(this.name, this.size, this.padding);
  final String name;
  final Size size;
  final FakeViewPadding padding;
}

const upright = Pose(
  'upright',
  Size(1080, 2400),
  FakeViewPadding(top: 63, bottom: 42),
);
const side = Pose(
  'on its side',
  Size(2400, 1080),
  FakeViewPadding(left: 84, top: 63, bottom: 42),
);
const ratio = 2.625;

class Listening extends TreelScanner {
  Listening(super.model);
  @override
  ScanStatus get status => ScanStatus.scanning;
}

/// Readings stamped now, so both pictures say "just now".
TreelReading heard(String id, int psi) => TreelReading(
  sensorId: id,
  psi: psi,
  celsius: 28,
  rssi: -60,
  at: DateTime.now(),
);

/// Four wheels placed, the spare's sensor heard but not placed, one tyre low.
Future<TreelModel> busyCar() async {
  final model = TreelModel();
  await model.load();
  await model.setAnimations(false);
  const psis = [33, 34, 29, 33, 30];
  for (final (i, p) in model.positions.indexed) {
    model.ingest(heard('d0e00${i + 1}', psis[i]));
    if (i < 4) await model.assign('d0e00${i + 1}', p);
  }
  return model;
}

Future<TreelModel> bike() async {
  final model = TreelModel();
  await model.load();
  await model.setAnimations(false);
  await model.setLayout(model.vehicle.id, WheelLayout.motorcycle);
  for (final (i, p) in model.positions.indexed) {
    model.ingest(heard('b0e00${i + 1}', 30 + i));
    await model.assign('b0e00${i + 1}', p);
  }
  return model;
}

Future<void> tap(WidgetTester tester, Finder f) async {
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> garage(WidgetTester tester) =>
    tap(tester, find.byIcon(Icons.expand_more_rounded));

/// Everything the app can show, and how to get there from the home screen.
final screens =
    <
      (
        String,
        Future<TreelModel> Function(),
        Future<void> Function(WidgetTester),
      )
    >[
      ('home, a car', busyCar, (t) async {}),
      ('home, a motorcycle', bike, (t) async {}),
      (
        'rotating the tyres',
        busyCar,
        (t) async {
          await tap(t, find.byType(TyreCard).first);
          await tap(t, find.text('Rotate this wheel'));
        },
      ),
      ('a wheel', busyCar, (t) => tap(t, find.byType(TyreCard).first)),
      ('an empty wheel', busyCar, (t) => tap(t, find.byType(TyreCard).last)),
      (
        'which sensor',
        busyCar,
        (t) async {
          await tap(t, find.byType(TyreCard).last);
          await tap(t, find.text('Assign a sensor'));
        },
      ),
      ('which wheel', busyCar, (t) => tap(t, find.byType(ActionChip).first)),
      (
        'the picture',
        busyCar,
        (t) => tap(t, find.bySemanticsLabel(RegExp('this vehicle'))),
      ),
      (
        'settings, a car',
        busyCar,
        (t) => tap(t, find.byIcon(Icons.tune_rounded)),
      ),
      (
        'settings, a motorcycle',
        bike,
        (t) => tap(t, find.byIcon(Icons.tune_rounded)),
      ),
      ('the garage', busyCar, garage),
      (
        'adding a vehicle',
        busyCar,
        (t) async {
          await garage(t);
          await tap(t, find.text('Add a vehicle'));
        },
      ),
      (
        'editing a vehicle',
        busyCar,
        (t) async {
          await garage(t);
          await tap(t, find.byIcon(Icons.edit_outlined).first);
        },
      ),
      (
        'removing a vehicle',
        busyCar,
        (t) async {
          await garage(t);
          await tap(t, find.byIcon(Icons.edit_outlined).first);
          await tap(t, find.text('Remove'));
        },
      ),
    ];

final frame = GlobalKey();

void hold(WidgetTester tester, Pose pose) {
  tester.view.physicalSize = pose.size;
  tester.view.devicePixelRatio = ratio;
  tester.view.padding = pose.padding;
}

/// Opens a screen with the phone held [first], turns it to [then], and
/// returns what is on screen.
Future<Uint8List> picture(
  WidgetTester tester,
  Future<TreelModel> Function() vehicle,
  Future<void> Function(WidgetTester) open, {
  required Pose first,
  required Pose then,
}) async {
  final model = await vehicle();
  try {
    hold(tester, first);
    await tester.pumpWidget(
      RepaintBoundary(
        key: frame,
        child: MaterialApp(
          theme: buildTheme(),
          home: HomePage(model: model, scanner: Listening(model)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await open(tester);
    expect(tester.takeException(), isNull, reason: 'opened ${first.name}');
    if (then != first) {
      hold(tester, then);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'turned ${then.name}');
    }
    return (await tester.runAsync(() async {
      final boundary =
          frame.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: ratio);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return bytes!.buffer.asUint8List();
    }))!;
  } finally {
    // A fresh screen for the next picture.
    await tester.pumpWidget(const SizedBox());
    model.dispose();
  }
}

int differing(Uint8List a, Uint8List b) {
  var n = 0;
  for (var i = 0; i < a.length; i += 4) {
    if (a[i] != b[i] ||
        a[i + 1] != b[i + 1] ||
        a[i + 2] != b[i + 2] ||
        a[i + 3] != b[i + 3]) {
      n++;
    }
  }
  return n;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // The vehicle form has a text field; a blinking cursor would make two
    // pictures of the same screen differ.
    EditableText.debugDeterministicCursor = true;
  });
  tearDown(() => EditableText.debugDeterministicCursor = false);

  for (final (name, vehicle, open) in screens) {
    for (final (from, to) in [(upright, side), (side, upright)]) {
      testWidgets('$name, opened ${from.name} and turned ${to.name}', (
        tester,
      ) async {
        addTearDown(tester.view.reset);
        final opened = await picture(
          tester,
          vehicle,
          open,
          first: to,
          then: to,
        );
        final turned = await picture(
          tester,
          vehicle,
          open,
          first: from,
          then: to,
        );
        if (!listEquals(opened, turned)) {
          final n = differing(opened, turned);
          fail(
            '$n of ${opened.length ~/ 4} pixels differ from the same screen '
            'opened ${to.name}',
          );
        }
      });
    }
  }
}
