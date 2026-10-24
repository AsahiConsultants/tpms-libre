import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tpms_libre/treel/model.dart';
import 'package:tpms_libre/treel/reading.dart';
import 'package:tpms_libre/treel/scanner.dart';
import 'package:tpms_libre/ui/home_page.dart';
import 'package:tpms_libre/ui/theme.dart';
import 'package:tpms_libre/ui/tyre.dart';

/// A phone on its side is a normal way to hold one in a car mount, so the
/// sheets are designed for it, not merely allowed to scroll. These pin down
/// the arrangements: what sits beside what, and what must be visible
/// without scrolling.

const side = Size(923, 411);
const upright = Size(411, 915);

class Listening extends TreelScanner {
  Listening(super.model);
  @override
  ScanStatus get status => ScanStatus.scanning;
}

/// A car with a spare: four wheels placed, the spare's sensor heard but not
/// placed, and one tyre low enough to raise an alert.
Future<TreelModel> busyCar() async {
  final model = TreelModel();
  await model.load();
  await model.setAnimations(false);
  const psis = [33, 34, 29, 33, 30];
  for (final (i, p) in model.positions.indexed) {
    model.ingest(
      TreelReading(
        sensorId: 'd0e00${i + 1}',
        psi: psis[i],
        celsius: 28,
        rssi: -60,
        at: DateTime.now(),
      ),
    );
    if (i < 4) await model.assign('d0e00${i + 1}', p);
  }
  return model;
}

Future<void> show(WidgetTester tester, TreelModel model, Size size) async {
  tester.view.physicalSize = size * 2.625;
  tester.view.devicePixelRatio = 2.625;
  tester.view.padding = const FakeViewPadding(top: 63, bottom: 42);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(),
      home: HomePage(model: model, scanner: Listening(model)),
    ),
  );
  await tester.pump();
}

/// Fully on screen, without scrolling.
void expectVisible(WidgetTester tester, Finder f, Size screen) {
  final r = tester.getRect(f);
  expect(r.top, greaterThanOrEqualTo(0));
  expect(r.bottom, lessThanOrEqualTo(screen.height), reason: 'off the bottom');
  expect(r.right, lessThanOrEqualTo(screen.width), reason: 'off the side');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a wheel\'s menu: the reading beside what you can do', (
    tester,
  ) async {
    final model = await busyCar();
    try {
      await show(tester, model, side);
      await tester.tap(find.byType(TyreCard).first);
      await tester.pumpAndSettle();

      final rotate = find.text('Rotate this wheel');
      expectVisible(tester, rotate, side);
      expectVisible(tester, find.text('Unassign sensor'), side);
      expect(
        tester.getRect(rotate).left,
        greaterThan(tester.getRect(find.text('Temperature')).right),
        reason: 'actions sit to the right of the details',
      );
      expect(tester.takeException(), isNull);
    } finally {
      model.dispose();
    }
  });

  testWidgets('settings: three columns, not one tall one', (tester) async {
    final model = await busyCar();
    try {
      await show(tester, model, side);
      await tester.tap(find.byIcon(Icons.tune_rounded));
      await tester.pumpAndSettle();

      final target = tester.getRect(find.text('Target pressure'));
      final tolerance = tester.getRect(find.text('Tolerance'));
      final preview = tester.getRect(find.text('WHAT YOU WILL SEE'));
      expect(tolerance.left, greaterThan(target.right));
      expect(preview.left, greaterThan(tolerance.right));
      expect(tolerance.top, closeTo(target.top, 2), reason: 'side by side');
      expect(tester.takeException(), isNull);
    } finally {
      model.dispose();
    }
  });

  testWidgets('settings opened upright and then turned on its side looks as '
      'if it had been opened on its side', (tester) async {
    // The sheet took its width from the screen it was opened on and kept
    // it: opened upright, it stayed at Material's 640 cap after the phone
    // turned, and the three columns were squeezed into that -- "Front axle"
    // wrapped a few letters to a line.
    const labels = [
      'Target pressure',
      'Front axle',
      'Tolerance',
      'Watch if under by',
      'WHAT YOU WILL SEE',
    ];
    Future<List<Rect>> settings({required Size openedAt}) async {
      final model = await busyCar();
      try {
        await show(tester, model, openedAt);
        await tester.tap(find.byIcon(Icons.tune_rounded));
        await tester.pumpAndSettle();
        tester.view.physicalSize = side * 2.625;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        return [for (final l in labels) tester.getRect(find.text(l))];
      } finally {
        await tester.pumpWidget(const SizedBox());
        model.dispose();
      }
    }

    final opened = await settings(openedAt: side);
    final turned = await settings(openedAt: upright);
    expect(turned, opened);
  });

  testWidgets('rotating: the instruction sits with the cards, and nothing '
      'falls off the bottom', (tester) async {
    // The busiest moment: rotating, with a sensor waiting to be placed and
    // a tyre low enough to raise an alert, all at once.
    final model = await busyCar();
    try {
      await show(tester, model, side);
      await tester.tap(find.byType(TyreCard).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rotate this wheel'));
      await tester.pumpAndSettle();

      final instruction = find.textContaining('tap the wheel it swaps with');
      final cards = tester.getRect(find.byType(TyreCard).first);
      expect(tester.getRect(instruction).bottom, lessThan(cards.top));
      expect(
        tester.getRect(instruction).left,
        greaterThan(side.width / 2 - 40),
        reason: 'in the readings\' column, not across the whole screen',
      );
      expectVisible(tester, find.text('Cancel'), side);
      expectVisible(tester, find.textContaining('psi low'), side);
      expectVisible(tester, find.text('Listening'), side);
      expectVisible(tester, find.byType(ActionChip), side);
      expect(tester.takeException(), isNull);
    } finally {
      model.dispose();
    }
  });

  testWidgets('the action in a banner sits at the end of its line', (
    tester,
  ) async {
    // It used to share the row half and half with the message and float in
    // the middle of its half -- in portrait too, just less obviously.
    for (final size in [upright, side]) {
      final model = await busyCar();
      try {
        await show(tester, model, size);
        await tester.tap(find.byType(TyreCard).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Rotate this wheel'));
        await tester.pumpAndSettle();

        final cancel = tester.getRect(find.text('Cancel'));
        final strip = tester.getRect(
          find
              .ancestor(
                of: find.text('Cancel'),
                matching: find.byType(Container),
              )
              .first,
        );
        expect(strip.right - cancel.right, lessThan(48), reason: '$size');
      } finally {
        // A fresh screen for the next size; otherwise the home screen's state
        // is reused and the next round starts mid-rotation.
        await tester.pumpWidget(const SizedBox());
        model.dispose();
      }
    }
  });

  testWidgets('which wheel: two to a row, all five without scrolling', (
    tester,
  ) async {
    final model = await busyCar();
    try {
      await show(tester, model, side);
      await tester.tap(find.byType(ActionChip).first);
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Front right')).dy,
        closeTo(tester.getTopLeft(find.text('Front left')).dy, 2),
      );
      for (final w in [
        'Front left',
        'Front right',
        'Rear left',
        'Rear right',
      ]) {
        expectVisible(tester, find.text(w), side);
      }
      expectVisible(tester, find.text('Spare').last, side);
    } finally {
      model.dispose();
    }
  });

  testWidgets('which sensor: free ones beside the ones on other wheels', (
    tester,
  ) async {
    final model = await busyCar();
    try {
      await show(tester, model, side);
      await tester.tap(find.byType(TyreCard).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Assign a sensor'));
      await tester.pumpAndSettle();
      final free = tester.getRect(find.textContaining('NOT ON A WHEEL'));
      final placed = tester.getRect(find.textContaining('ON ANOTHER WHEEL'));
      expect(placed.left, greaterThan(free.right));
      expect(placed.top, closeTo(free.top, 2));
    } finally {
      model.dispose();
    }
  });

  testWidgets('upright, the sheets keep their single column', (tester) async {
    final model = await busyCar();
    try {
      await show(tester, model, upright);
      await tester.tap(find.byIcon(Icons.tune_rounded));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Tolerance')).dy,
        greaterThan(tester.getBottomLeft(find.text('Target pressure')).dy),
      );
    } finally {
      model.dispose();
    }
  });
}
