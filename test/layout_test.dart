import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tpms_libre/treel/model.dart';
import 'package:tpms_libre/treel/reading.dart';
import 'package:tpms_libre/treel/scanner.dart';
import 'package:tpms_libre/ui/home_page.dart';
import 'package:tpms_libre/ui/theme.dart';
import 'package:tpms_libre/ui/tyre.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Yesterday the home screen overflowed by 10 pixels the moment five
/// unplaced sensors appeared: the footer grew, and the diagram had a minimum
/// height that would not yield. Nothing caught it but a screenshot.
///
/// Flutter reports an overflow as an exception during a widget test, so
/// pumping the screen across sizes, text scales and states and asserting
/// nothing was thrown is enough to catch the whole class of bug.

const sizes = <String, Size>{
  'small phone': Size(320, 600),
  'pixel': Size(411, 915),
  'large phone': Size(480, 1000),
  'short screen': Size(400, 640),
};

TreelReading reading(String id, int psi) => TreelReading(
  sensorId: id,
  psi: psi,
  celsius: 25,
  rssi: -70,
  at: DateTime.now(),
);

Future<TreelModel> buildModel({
  required int sensors,
  required bool assigned,
  WheelLayout layout = WheelLayout.carWithSpare,
  VehicleArt art = VehicleArt.generic,
}) async {
  final model = TreelModel();
  await model.load();
  await model.setAnimations(false); // layout is the subject, not motion
  await model.setLayout(model.vehicle.id, layout);
  await model.setArt(model.vehicle.id, art);
  const ids = ['f10a01', 'f10a02', 'f10a03', 'f10a04', 'f10a05'];
  final spots = model.positions;
  for (var i = 0; i < sensors && i < ids.length; i++) {
    model.ingest(reading(ids[i], 30 + i));
    if (assigned && i < spots.length) await model.assign(ids[i], spots[i]);
  }
  return model;
}

/// Builds, pumps, asserts and disposes inside the test body. The model runs
/// a periodic tick and a debounced save, and Flutter checks for pending
/// timers *before* addTearDown runs — so disposal has to happen here.
Future<void> expectNoOverflow(
  WidgetTester tester, {
  required Size size,
  double textScale = 1.0,
  required int sensors,
  required bool assigned,
}) async {
  final model = await buildModel(sensors: sensors, assigned: assigned);
  try {
    await pumpHome(tester, model, size: size, textScale: textScale);
    expect(tester.takeException(), isNull);
  } finally {
    model.dispose();
  }
}

Future<void> pumpHome(
  WidgetTester tester,
  TreelModel model, {
  required Size size,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size * 3.0;
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(),
      home: HomePage(model: model, scanner: TreelScanner(model)),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('home screen never overflows', () {
    for (final entry in sizes.entries) {
      for (final scale in [1.0, 1.3, 2.0]) {
        for (final sensors in [0, 5]) {
          for (final assigned in [true, false]) {
            if (sensors == 0 && assigned) continue;
            final what = sensors == 0
                ? 'nothing heard'
                : assigned
                ? '5 placed'
                : '5 unplaced';
            testWidgets('${entry.key}, text x$scale, $what', (tester) async {
              await expectNoOverflow(
                tester,
                size: entry.value,
                textScale: scale,
                sensors: sensors,
                assigned: assigned,
              );
            });
          }
        }
      }
    }
  });

  group('a phone on its side', () {
    // Landscape used to be the portrait column, centred: a picture shrunk
    // to a strip and five thumbnails adrift in a screen of black. It now
    // puts the picture and the readings side by side.
    const sides = <String, Size>{
      'pixel landscape': Size(923, 411),
      'small landscape': Size(640, 360),
      'large landscape': Size(1000, 480),
    };
    for (final entry in sides.entries) {
      for (final scale in [1.0, 1.3, 2.0]) {
        for (final layout in WheelLayout.values) {
          testWidgets('${layout.name} on ${entry.key}, text x$scale', (
            tester,
          ) async {
            final model = await buildModel(
              sensors: 5,
              assigned: true,
              layout: layout,
            );
            try {
              await pumpHome(
                tester,
                model,
                size: entry.value,
                textScale: scale,
              );
              expect(tester.takeException(), isNull);
              expect(
                find.byType(TyreCard),
                findsNWidgets(layout.positions.length),
              );
            } finally {
              model.dispose();
            }
          });
        }
      }
    }

    testWidgets('the readings sit beside the picture, not under it', (
      tester,
    ) async {
      final model = await buildModel(sensors: 5, assigned: true);
      try {
        await pumpHome(tester, model, size: const Size(923, 411));
        final picture = tester.getRect(
          find.text('Add a photo of your vehicle'),
        );
        final card = tester.getRect(find.byType(TyreCard).first);
        expect(card.left, greaterThan(picture.right));
        expect(
          tester.getTopLeft(find.textContaining('live')).dx,
          greaterThan(picture.right),
          reason:
              'the status lines go with the readings, not under the picture',
        );
      } finally {
        model.dispose();
      }
    });
  });

  testWidgets('regression: five unplaced sensors on a short screen', (
    tester,
  ) async {
    // The exact shape of yesterday's bug. The footer carries a chip per
    // unplaced sensor, which is when the diagram has least room.
    final model = await buildModel(sensors: 5, assigned: false);
    try {
      await pumpHome(tester, model, size: const Size(400, 640));
      expect(tester.takeException(), isNull);
      expect(find.textContaining('not placed'), findsOneWidget);
    } finally {
      model.dispose();
    }
  });

  testWidgets('every tyre card names its wheel', (tester) async {
    // These went away when every card sat at its own corner of a drawing of
    // a car. A vehicle with its own artwork puts the readings in a row
    // underneath instead, where nothing else says which wheel is which.
    final model = await buildModel(sensors: 5, assigned: true);
    try {
      await pumpHome(tester, model, size: const Size(411, 915));
      for (final p in model.positions) {
        expect(find.text(p.short), findsOneWidget, reason: '${p.short} label');
      }
      expect(
        find.text('30'),
        findsOneWidget,
        reason: 'the reading still shows',
      );
    } finally {
      model.dispose();
    }
  });

  testWidgets('a restored reading shows its age instead of pretending', (
    tester,
  ) async {
    final model = TreelModel();
    try {
      await model.load();
      await model.setAnimations(false);
      model.ingest(
        TreelReading(
          sensorId: 'f10a05',
          psi: 30,
          celsius: 28,
          rssi: -60,
          at: DateTime.now().subtract(const Duration(days: 5)),
        ),
      );
      await model.assign('f10a05', TyrePosition.spare);

      await pumpHome(tester, model, size: const Size(411, 915));
      expect(tester.takeException(), isNull);
      expect(find.text('5d ago'), findsOneWidget);
    } finally {
      model.dispose();
    }
  });

  testWidgets('every tyre card is tappable', (tester) async {
    final model = await buildModel(sensors: 5, assigned: true);
    try {
      await pumpHome(tester, model, size: const Size(411, 915));
      // A tap with no handler reads as broken; there should be one InkWell
      // per wheel.
      expect(
        find.byType(InkWell),
        findsAtLeast(model.positions.length),
        reason: 'one per wheel this vehicle actually has',
      );
    } finally {
      model.dispose();
    }
  });

  testWidgets('pulling down re-arms every tyre', (tester) async {
    final model = await buildModel(sensors: 5, assigned: true);
    try {
      await pumpHome(tester, model, size: const Size(411, 915));
      expect(model.liveCount, 5);

      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, 320),
        1200,
      );
      // The refresh also retries the scan, and in a test the Bluetooth
      // platform never answers — exactly the stall the gesture has to
      // survive. Without the bound in _refresh this never settles.
      await tester.pumpAndSettle();
      tester.takeException();

      expect(
        model.liveCount,
        0,
        reason: 'every tyre must confirm itself again',
      );
      expect(model.knownCount, 5, reason: 'without losing what it knew');
      expect(tester.takeException(), isNull);
    } finally {
      model.dispose();
    }
  });

  testWidgets('exactly the tyre that woke is highlighted', (tester) async {
    final model = await buildModel(sensors: 0, assigned: false);
    try {
      await model.assign('f10a01', TyrePosition.frontLeft);
      await model.assign('f10a05', TyrePosition.spare);
      model.ingest(reading('f10a01', 33));
      model.ingest(reading('f10a05', 33));

      await pumpHome(tester, model, size: const Size(411, 915));

      final waking = tester
          .widgetList<TyreCard>(find.byType(TyreCard))
          .where((c) => c.waking)
          .toList();
      expect(
        waking,
        hasLength(1),
        reason: 'one tyre lit, not all of them and not none',
      );
      expect(waking.single.state.sensorId, model.wokeSensor);
      expect(tester.takeException(), isNull);
    } finally {
      model.dispose();
    }
  });

  group('other vehicle shapes', () {
    for (final entry in sizes.entries) {
      for (final scale in [1.0, 2.0]) {
        for (final layout in [WheelLayout.car, WheelLayout.motorcycle]) {
          testWidgets('${layout.name} on ${entry.key} at text x$scale', (
            tester,
          ) async {
            final model = await buildModel(
              sensors: 5,
              assigned: true,
              layout: layout,
            );
            try {
              await pumpHome(
                tester,
                model,
                size: entry.value,
                textScale: scale,
              );
              expect(tester.takeException(), isNull);
            } finally {
              model.dispose();
            }
          });
        }
      }
    }

    for (final art in VehicleArt.values.where((a) => a.hasAsset)) {
      for (final layout in art.suits) {
        for (final entry in sizes.entries) {
          for (final scale in [1.0, 2.0]) {
            testWidgets(
              '${art.label} as ${layout.label} fits ${entry.key} at text '
              'x$scale',
              (tester) async {
                // A photograph-sized drawing is far easier to overflow with
                // than a shape drawn to fit, and five cards in one row is
                // the tightest arrangement on the screen, so every
                // combination gets the same grid as the rest of the app.
                final model = await buildModel(
                  sensors: 5,
                  assigned: true,
                  layout: layout,
                  art: art,
                );
                try {
                  await pumpHome(
                    tester,
                    model,
                    size: entry.value,
                    textScale: scale,
                  );
                  expect(tester.takeException(), isNull);
                  expect(
                    find.byType(TyreCard),
                    findsNWidgets(layout.positions.length),
                  );
                } finally {
                  model.dispose();
                }
              },
            );
          }
        }
      }
    }

    testWidgets('a vehicle with no picture invites one, and the tap works', (
      tester,
    ) async {
      final model = await buildModel(
        sensors: 5,
        assigned: true,
        layout: WheelLayout.carWithSpare,
      );
      try {
        await pumpHome(tester, model, size: const Size(411, 915));
        expect(find.text('Add a photo of your vehicle'), findsOneWidget);
        expect(find.byType(Image), findsNothing, reason: 'nothing to draw yet');
        expect(find.byType(TyreCard), findsNWidgets(5));

        await tester.tap(find.text('Add a photo of your vehicle'));
        await tester.pumpAndSettle();
        expect(
          find.text('Use my photo'),
          findsOneWidget,
          reason: 'the prompt opens the same choice the picture would',
        );
        expect(tester.takeException(), isNull);
      } finally {
        model.dispose();
      }
    });

    for (final scale in [1.0, 2.0]) {
      testWidgets('the prompt fits a small phone at text x$scale', (
        tester,
      ) async {
        final model = await buildModel(
          sensors: 5,
          assigned: true,
          layout: WheelLayout.carWithSpare,
        );
        try {
          await pumpHome(
            tester,
            model,
            size: const Size(320, 600),
            textScale: scale,
          );
          expect(tester.takeException(), isNull);
        } finally {
          model.dispose();
        }
      });
    }

    testWidgets('a motorcycle shows two wheels and no spare', (tester) async {
      final model = await buildModel(
        sensors: 2,
        assigned: true,
        layout: WheelLayout.motorcycle,
      );
      try {
        await pumpHome(tester, model, size: const Size(411, 915));
        expect(find.byType(TyreCard), findsNWidgets(2));
        expect(find.text('SPARE'), findsNothing);
      } finally {
        model.dispose();
      }
    });

    testWidgets('a car without a spare shows four', (tester) async {
      final model = await buildModel(
        sensors: 4,
        assigned: true,
        layout: WheelLayout.car,
      );
      try {
        await pumpHome(tester, model, size: const Size(411, 915));
        expect(find.byType(TyreCard), findsNWidgets(4));
        expect(find.text('SPARE'), findsNothing);
      } finally {
        model.dispose();
      }
    });

    testWidgets('the title names the vehicle', (tester) async {
      final model = await buildModel(sensors: 0, assigned: false);
      try {
        await model.renameVehicle(model.vehicle.id, 'Test vehicle');
        await pumpHome(tester, model, size: const Size(411, 915));
        expect(find.text('Test vehicle'), findsOneWidget);
      } finally {
        model.dispose();
      }
    });
  });
}
