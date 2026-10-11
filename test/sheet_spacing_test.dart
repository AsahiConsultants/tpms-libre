import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tpms_libre/treel/model.dart';
import 'package:tpms_libre/treel/reading.dart';
import 'package:tpms_libre/treel/scanner.dart';
import 'package:tpms_libre/ui/home_page.dart';
import 'package:tpms_libre/ui/theme.dart';
import 'package:tpms_libre/ui/tyre.dart';

import 'support/fonts.dart';

/// The sheets, measured: one edge for everything in them, and a settings
/// sheet that says which of its settings belong to the vehicle.

const upright = Size(411, 914);
const side = Size(914, 411);
const sizes = {'upright': upright, 'on its side': side};

class Listening extends TreelScanner {
  Listening(super.model);
  @override
  ScanStatus get status => ScanStatus.scanning;
}

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
    await model.assign('d0e00${i + 1}', p);
  }
  return model;
}

Future<void> show(WidgetTester tester, TreelModel model, Size size) async {
  tester.view.physicalSize = size * 2.625;
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(),
      home: HomePage(model: model, scanner: Listening(model)),
    ),
  );
  await tester.pump();
}

Future<void> openSettings(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Target pressures'));
  await tester.pumpAndSettle();
}

/// The topmost match: the sheet's, not the page's underneath.
Rect top(WidgetTester tester, String text) =>
    tester.getRect(find.text(text).last);

void main() {
  // Whether a label wraps depends on the real font's widths.
  setUpAll(loadFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final MapEntry(key: name, value: size) in sizes.entries) {
    testWidgets('$name, settings name the vehicle their pressures are for', (
      tester,
    ) async {
      final model = await car();
      try {
        await show(tester, model, size);
        await openSettings(tester);
        // The app bar's title, and the sheet's heading over the pressures.
        expect(find.text('Weekend car'), findsNWidgets(2));
        expect(find.text('Saved for this vehicle only'), findsOneWidget);
        expect(
          top(tester, 'Weekend car').top,
          lessThan(top(tester, 'Target pressure').top),
        );

        await tester.scrollUntilVisible(
          find.text('Animations'),
          100,
          scrollable: find.byType(Scrollable).last,
        );
        final everywhere = top(tester, 'All vehicles');
        expect(
          everywhere.top,
          greaterThan(top(tester, 'What you will see').top),
        );
        expect(top(tester, 'Haptics').top, greaterThan(everywhere.bottom));
        expect(top(tester, 'Animations').top, greaterThan(everywhere.bottom));
      } finally {
        model.dispose();
      }
    });

    testWidgets('$name, every setting starts on its heading\'s edge', (
      tester,
    ) async {
      final model = await car();
      try {
        await show(tester, model, size);
        await openSettings(tester);
        final columns = {
          'Target pressure': ['Front axle', 'Rear axle', 'Spare'],
          'Tolerance': [
            'Watch if under by',
            'Alert if under by',
            'Watch if over by',
            'Alert if over by',
          ],
        };
        for (final MapEntry(key: heading, value: labels) in columns.entries) {
          for (final label in labels) {
            // The first: the preview below repeats "Spare".
            final r = tester.getRect(find.text(label).first);
            expect(r.left, top(tester, heading).left, reason: label);
            expect(
              r.height,
              lessThan(TypeScale.row.fontSize! * 1.6),
              reason: '"$label" wrapped',
            );
          }
        }
        expect(
          top(tester, 'Weekend car').left,
          top(tester, 'Target pressure').left,
        );
      } finally {
        model.dispose();
      }
    });
  }

  testWidgets('a wheel\'s actions start on the heading\'s edge', (
    tester,
  ) async {
    final model = await car();
    try {
      await show(tester, model, upright);
      await tester.tap(find.byType(TyreCard).first);
      await tester.pumpAndSettle();
      expect(top(tester, 'Front left').left, Space.margin);
      for (final icon in [Icons.swap_horiz_rounded, Icons.link_off_rounded]) {
        expect(tester.getRect(find.byIcon(icon).last).left, Space.margin);
      }
    } finally {
      model.dispose();
    }
  });

  group('on its side, the vehicle form fits without scrolling', () {
    // Stacked, the button that finishes the job was two screens down.
    void expectOnScreen(WidgetTester tester, Finder f) {
      final r = tester.getRect(f);
      expect(r.top, greaterThanOrEqualTo(0));
      expect(
        r.bottom,
        lessThanOrEqualTo(side.height),
        reason: 'off the bottom',
      );
    }

    Future<void> openGarage(WidgetTester tester) async {
      await tester.tap(find.text('Weekend car'));
      await tester.pumpAndSettle();
    }

    testWidgets('adding', (tester) async {
      final model = await car();
      try {
        await show(tester, model, side);
        await openGarage(tester);
        await tester.tap(find.text('Add a vehicle'));
        await tester.pumpAndSettle();
        for (final f in [
          find.byType(TextField),
          find.text('Car'),
          find.text('Car with spare'),
          find.text('Motorcycle'),
          find.widgetWithText(FilledButton, 'Add'),
        ]) {
          expectOnScreen(tester, f);
        }
        // Side by side: the name beside the shapes, not above them.
        expect(
          tester.getRect(find.text('Shape')).left,
          greaterThan(tester.getRect(find.byType(TextField)).right),
        );
      } finally {
        model.dispose();
      }
    });

    testWidgets('editing', (tester) async {
      final model = await car();
      try {
        await show(tester, model, side);
        await openGarage(tester);
        await tester.tap(find.byIcon(Icons.edit_outlined));
        await tester.pumpAndSettle();
        expectOnScreen(tester, find.widgetWithText(FilledButton, 'Save'));
        expectOnScreen(tester, find.text('Remove'));
      } finally {
        model.dispose();
      }
    });
  });
}
