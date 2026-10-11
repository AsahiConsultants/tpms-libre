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

/// Text that does the same job looks the same, whichever sheet it is in.
/// Before the type scale, a sheet's title was 16, 19 or 22 depending on the
/// sheet, and a row was 16 in one sheet and 14 in the next.

class Listening extends TreelScanner {
  Listening(super.model);
  @override
  ScanStatus get status => ScanStatus.scanning;
}

/// Four wheels placed, the spare's sensor heard but not placed, and a second
/// vehicle so the garage lists more than one.
Future<TreelModel> car() async {
  final model = TreelModel();
  await model.load();
  await model.setAnimations(false);
  await model.renameVehicle(model.vehicle.id, 'Weekend car');
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
    if (i < 4) await model.assign('d0e00${i + 1}', p);
  }
  await model.addVehicle('Bike', WheelLayout.motorcycle);
  await model.selectVehicle(model.vehicles.first.id);
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

/// The style the text is actually drawn with, theme and defaults included.
TextStyle drawn(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(find.text(text).last).text.style!;

void expectRole(WidgetTester tester, String text, TextStyle role) {
  final s = drawn(tester, text);
  expect(s.fontSize, role.fontSize, reason: '"$text" size');
  expect(
    s.fontWeight ?? FontWeight.w400,
    role.fontWeight ?? FontWeight.w400,
    reason: '"$text" weight',
  );
}

/// The sheet as drawn. The BottomSheet widget spans the screen and centres
/// its narrower surface within itself.
double sheetLeft(WidgetTester tester) => tester
    .getTopLeft(
      find
          .descendant(
            of: find.byType(BottomSheet).last,
            matching: find.byType(Material),
          )
          .first,
    )
    .dx;

Future<void> close(WidgetTester tester) async {
  await tester.tapAt(const Offset(10, 10));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('every screen and sheet has the same kind of title', (
    tester,
  ) async {
    final model = await car();
    try {
      await show(tester, model);
      expectRole(tester, 'Weekend car', TypeScale.title);

      await tester.tap(find.byType(TyreCard).first);
      await tester.pumpAndSettle();
      expectRole(tester, 'Front left', TypeScale.title);
      await close(tester);

      await tester.tap(find.byType(TyreCard).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Assign a sensor'));
      await tester.pumpAndSettle();
      expectRole(tester, 'Which sensor is on the spare?', TypeScale.title);
      expect(
        tester.getTopLeft(find.text('Which sensor is on the spare?')).dx,
        sheetLeft(tester) + Space.margin,
      );
      await close(tester);
      await close(tester);

      await tester.tap(find.byType(ActionChip).first);
      await tester.pumpAndSettle();
      expectRole(tester, 'Which wheel is d0e005 on?', TypeScale.title);
      // It was centred once, alone among the titles.
      expect(
        tester.getTopLeft(find.text('Which wheel is d0e005 on?')).dx,
        sheetLeft(tester) + Space.margin,
      );
      await close(tester);

      await tester.tap(find.byTooltip('Target pressures'));
      await tester.pumpAndSettle();
      expectRole(tester, 'Weekend car', TypeScale.title);
      await close(tester);

      await tester.tap(find.text('Weekend car'));
      await tester.pumpAndSettle();
      expectRole(tester, 'Vehicles', TypeScale.title);
      await tester.tap(find.text('Add a vehicle'));
      await tester.pumpAndSettle();
      expectRole(tester, 'Add a vehicle', TypeScale.title);
    } finally {
      model.dispose();
    }
  });

  testWidgets('a section heading looks the same in every sheet', (
    tester,
  ) async {
    final model = await car();
    try {
      await show(tester, model);
      await tester.tap(find.byTooltip('Target pressures'));
      await tester.pumpAndSettle();
      expectRole(tester, 'Target pressure', TypeScale.heading);
      expectRole(tester, 'Tolerance', TypeScale.heading);
      await close(tester);

      await tester.tap(find.text('Weekend car'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add a vehicle'));
      await tester.pumpAndSettle();
      expectRole(tester, 'Shape', TypeScale.heading);
    } finally {
      model.dispose();
    }
  });

  testWidgets('a row is the same size in every sheet', (tester) async {
    final model = await car();
    try {
      await show(tester, model);
      await tester.tap(find.byTooltip('Target pressures'));
      await tester.pumpAndSettle();
      for (final row in ['Front axle', 'Watch if under by', 'Haptics']) {
        expectRole(tester, row, TypeScale.row);
      }
      await close(tester);

      await tester.tap(find.text('Weekend car'));
      await tester.pumpAndSettle();
      expectRole(tester, 'Bike', TypeScale.row);
      await tester.tap(find.text('Add a vehicle'));
      await tester.pumpAndSettle();
      expectRole(tester, 'Motorcycle', TypeScale.row);
    } finally {
      model.dispose();
    }
  });
}
