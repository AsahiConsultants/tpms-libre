import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tpms_libre/treel/model.dart';
import 'package:tpms_libre/treel/reading.dart';
import 'package:tpms_libre/treel/scanner.dart';
import 'package:tpms_libre/treel/vehicle.dart';
import 'package:tpms_libre/ui/home_page.dart';
import 'package:tpms_libre/ui/theme.dart';
import 'package:tpms_libre/ui/tyre.dart';

/// A motorcycle's front and rear tyres are different sizes and never trade
/// places, so it is offered no rotation at all.

class Listening extends TreelScanner {
  Listening(super.model);
  @override
  ScanStatus get status => ScanStatus.scanning;
}

Future<TreelModel> placed(WheelLayout layout) async {
  final model = TreelModel();
  await model.load();
  await model.setAnimations(false);
  await model.setLayout(model.vehicle.id, layout);
  for (final (i, p) in model.positions.indexed) {
    model.ingest(
      TreelReading(
        sensorId: 'd0e00${i + 1}',
        psi: 34,
        celsius: 28,
        rssi: -60,
        at: DateTime.now(),
      ),
    );
    await model.assign('d0e00${i + 1}', p);
  }
  return model;
}

Future<void> show(WidgetTester tester, TreelModel model) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(),
      home: HomePage(model: model, scanner: Listening(model)),
    ),
  );
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('only a motorcycle does not rotate', () {
    expect(WheelLayout.motorcycle.rotates, isFalse);
    expect(WheelLayout.car.rotates, isTrue);
    expect(WheelLayout.carWithSpare.rotates, isTrue);
  });

  testWidgets('a car\'s wheel menu offers a rotation', (tester) async {
    final model = await placed(WheelLayout.car);
    try {
      await show(tester, model);
      await tester.tap(find.byType(TyreCard).first);
      await tester.pumpAndSettle();
      expect(find.text('Rotate this wheel'), findsOneWidget);
    } finally {
      model.dispose();
    }
  });

  testWidgets('a motorcycle\'s wheel menu does not', (tester) async {
    final model = await placed(WheelLayout.motorcycle);
    try {
      await show(tester, model);
      await tester.tap(find.byType(TyreCard).first);
      await tester.pumpAndSettle();
      expect(find.text('Rotate this wheel'), findsNothing);
      expect(find.text('Unassign sensor'), findsOneWidget);
    } finally {
      model.dispose();
    }
  });

  testWidgets('nor does a long press on a motorcycle wheel', (tester) async {
    final model = await placed(WheelLayout.motorcycle);
    try {
      await show(tester, model);
      await tester.longPress(find.byType(TyreCard).first);
      await tester.pumpAndSettle();
      expect(find.textContaining('tap the wheel it swaps with'), findsNothing);
    } finally {
      model.dispose();
    }
  });

  testWidgets('a rotation does not follow the owner onto a motorcycle', (
    tester,
  ) async {
    final model = await placed(WheelLayout.car);
    try {
      await show(tester, model);
      await tester.longPress(find.byType(TyreCard).first);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('tap the wheel it swaps with'),
        findsOneWidget,
      );

      await model.setLayout(model.vehicle.id, WheelLayout.motorcycle);
      await tester.pumpAndSettle();
      expect(find.textContaining('tap the wheel it swaps with'), findsNothing);
    } finally {
      model.dispose();
    }
  });
}
