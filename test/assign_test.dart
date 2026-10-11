import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tpms_libre/treel/model.dart';
import 'package:tpms_libre/treel/reading.dart';
import 'package:tpms_libre/treel/scanner.dart';
import 'package:tpms_libre/ui/home_page.dart';
import 'package:tpms_libre/ui/theme.dart';
import 'package:tpms_libre/ui/tyre.dart';

/// Putting sensors on wheels: the two pickers, and the sheets they open in,
/// in both orientations.

const portrait = Size(411, 915);
const landscape = Size(923, 411);

TreelReading heard(String id, int psi) => TreelReading(
  sensorId: id,
  psi: psi,
  celsius: 26,
  rssi: -60,
  at: DateTime.now(),
);

/// A vehicle of [layout] with [sensors] heard, the first [placed] of them on
/// its wheels in order.
Future<TreelModel> vehicle(
  WheelLayout layout, {
  int sensors = 5,
  int placed = 0,
}) async {
  final model = TreelModel();
  await model.load();
  await model.setAnimations(false);
  await model.setLayout(model.vehicle.id, layout);
  for (var i = 0; i < sensors; i++) {
    model.ingest(heard('d0e00${i + 1}', 30 + i));
    if (i < placed) await model.assign('d0e00${i + 1}', model.positions[i]);
  }
  return model;
}

Future<void> show(
  WidgetTester tester,
  TreelModel model, {
  Size size = portrait,
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

/// Opens "which wheel?" for the first sensor not yet on one.
Future<void> openPositionPicker(WidgetTester tester) async {
  await tester.tap(find.byType(ActionChip).first);
  await tester.pumpAndSettle();
}

/// Opens "which sensor?" for the first empty wheel.
Future<void> openSensorPicker(WidgetTester tester, TreelModel model) async {
  final empty = model.positions.firstWhere(
    (p) => model.stateOf(p).sensorId == null,
  );
  await tester.tap(
    find.byWidgetPredicate((w) => w is TyreCard && w.state.position == empty),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Assign a sensor'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('"which wheel?" offers only the wheels this vehicle has', () {
    const expected = {
      WheelLayout.carWithSpare: [
        'Front left',
        'Front right',
        'Rear left',
        'Rear right',
        'Spare',
      ],
      WheelLayout.car: ['Front left', 'Front right', 'Rear left', 'Rear right'],
      WheelLayout.motorcycle: ['Front', 'Rear'],
    };
    for (final MapEntry(key: layout, value: wheels) in expected.entries) {
      testWidgets(layout.label, (tester) async {
        final model = await vehicle(layout, sensors: 1);
        try {
          await show(tester, model);
          await openPositionPicker(tester);
          final offered = [
            for (final p in TyrePosition.values)
              if (find
                  .descendant(
                    of: find.byType(BottomSheet),
                    matching: find.text(p.label),
                  )
                  .evaluate()
                  .isNotEmpty)
                p.label,
          ];
          expect(offered, wheels);
        } finally {
          model.dispose();
        }
      });
    }
  });

  testWidgets('"which sensor?" leads with the ones it said were free', (
    tester,
  ) async {
    // The wheel's menu promises "2 available"; the list must open with
    // exactly those two, and keep the three on other wheels apart.
    final model = await vehicle(WheelLayout.carWithSpare, placed: 3);
    try {
      await show(tester, model);
      expect(model.unassigned, hasLength(2));
      await openSensorPicker(tester, model);

      expect(find.text('NOT ON A WHEEL · 2'), findsOneWidget);
      expect(find.textContaining('ON ANOTHER WHEEL'), findsOneWidget);

      final freeY = tester.getTopLeft(find.text('d0e004')).dy;
      final placedY = tester.getTopLeft(find.text('d0e001')).dy;
      expect(freeY, lessThan(placedY), reason: 'free sensors come first');
      expect(find.textContaining('On the front left'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      model.dispose();
    }
  });

  testWidgets('taking a sensor from another wheel leaves that wheel empty', (
    tester,
  ) async {
    final model = await vehicle(WheelLayout.carWithSpare, placed: 3);
    try {
      await show(tester, model);
      await openSensorPicker(tester, model);
      await tester.tap(find.text('d0e001'));
      await tester.pumpAndSettle();
      expect(model.positionOf('d0e001'), TyrePosition.rearRight);
      expect(model.stateOf(TyrePosition.frontLeft).sensorId, isNull);
    } finally {
      model.dispose();
    }
  });

  group('every sheet fits a phone on its side', () {
    for (final scale in [1.0, 1.5]) {
      testWidgets('which wheel, text x$scale', (tester) async {
        final model = await vehicle(WheelLayout.carWithSpare, sensors: 1);
        try {
          await show(tester, model, size: landscape, textScale: scale);
          await openPositionPicker(tester);
          expect(tester.takeException(), isNull);
          // The last wheel is reachable by scrolling, not cut off.
          await tester.dragUntilVisible(
            find.text('Spare'),
            find.byType(SingleChildScrollView).last,
            const Offset(0, -80),
          );
          expect(find.text('Spare'), findsOneWidget);
        } finally {
          model.dispose();
        }
      });

      testWidgets('which sensor, text x$scale', (tester) async {
        final model = await vehicle(WheelLayout.carWithSpare, placed: 3);
        try {
          await show(tester, model, size: landscape, textScale: scale);
          await openSensorPicker(tester, model);
          expect(tester.takeException(), isNull);
        } finally {
          model.dispose();
        }
      });

      testWidgets('a wheel\'s menu, text x$scale', (tester) async {
        final model = await vehicle(WheelLayout.carWithSpare, placed: 5);
        try {
          await show(tester, model, size: landscape, textScale: scale);
          await tester.tap(find.byType(TyreCard).first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        } finally {
          model.dispose();
        }
      });

      testWidgets('the garage, text x$scale', (tester) async {
        final model = await vehicle(WheelLayout.carWithSpare, placed: 5);
        try {
          await model.addVehicle('Second', WheelLayout.motorcycle);
          await model.addVehicle('Third', WheelLayout.car);
          await show(tester, model, size: landscape, textScale: scale);
          await tester.tap(find.text('Third'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        } finally {
          model.dispose();
        }
      });
    }
  });
}
