import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tpms_libre/treel/model.dart';
import 'package:tpms_libre/treel/reading.dart';
import 'package:tpms_libre/treel/scanner.dart';
import 'package:tpms_libre/ui/home_page.dart';
import 'package:tpms_libre/ui/theme.dart';
import 'package:tpms_libre/ui/tyre.dart';

/// The home screen's spacing, measured. Every element sat on its own margin
/// and every gap was whatever its widget happened to pick; these hold the
/// one margin and one scale in place.

const upright = Size(411, 914);
const side = Size(914, 411);

class Listening extends TreelScanner {
  Listening(super.model);
  @override
  ScanStatus get status => ScanStatus.scanning;
}

Future<TreelModel> car() async {
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

/// Into rotation, so the banner shows.
Future<void> rotate(WidgetTester tester) async {
  await tester.tap(find.byType(TyreCard).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Rotate this wheel'));
  await tester.pumpAndSettle();
}

/// The strip as drawn: its decoration, not the Container, whose rect also
/// covers the margin below it.
Rect banner(WidgetTester tester) => tester.getRect(
  find
      .ancestor(of: find.text('Cancel'), matching: find.byType(DecoratedBox))
      .first,
);

Rect picture(WidgetTester tester) => tester.getRect(
  find
      .ancestor(
        of: find.text('Add a photo of your vehicle'),
        matching: find.byType(DecoratedBox),
      )
      .first,
);

Rect cards(WidgetTester tester) {
  final rs = tester
      .widgetList(find.byType(TyreCard))
      .map((w) => tester.getRect(find.byWidget(w)));
  return rs.reduce((a, b) => a.expandToInclude(b));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('upright, everything shares the page margin', (tester) async {
    final model = await car();
    try {
      await show(tester, model, upright);
      await rotate(tester);
      const edge = Space.margin;
      expect(tester.getTopLeft(find.text('My vehicle')).dx, closeTo(edge, 1));
      expect(banner(tester).left, closeTo(edge, 1));
      expect(picture(tester).left, closeTo(edge, 1));
      expect(cards(tester).left, closeTo(edge, 1));
      expect(
        tester.getTopLeft(find.byIcon(Icons.warning_amber_rounded)).dx,
        closeTo(edge, 1),
        reason: 'the alert line',
      );
      expect(banner(tester).right, closeTo(upright.width - edge, 1));
      expect(cards(tester).right, closeTo(upright.width - edge, 1));
    } finally {
      model.dispose();
    }
  });

  for (final size in [upright, side]) {
    final name = size == upright ? 'upright' : 'on its side';

    testWidgets('$name, the banner stands clear of what it is about', (
      tester,
    ) async {
      final model = await car();
      try {
        await show(tester, model, size);
        await rotate(tester);
        final below = size == upright ? picture(tester) : cards(tester);
        expect(below.top - banner(tester).bottom, closeTo(Space.l, 1));
      } finally {
        model.dispose();
      }
    });

    testWidgets('$name, the readings and what they mean are a step apart', (
      tester,
    ) async {
      final model = await car();
      try {
        await show(tester, model, size);
        final alert = tester.getRect(find.textContaining('psi low'));
        expect(alert.top - cards(tester).bottom, greaterThanOrEqualTo(Space.l));
        expect(alert.top - cards(tester).bottom, lessThan(Space.l + 4));
      } finally {
        model.dispose();
      }
    });
  }

  testWidgets('on its side, both columns start from the same top', (
    tester,
  ) async {
    final model = await car();
    try {
      await show(tester, model, side);
      expect(picture(tester).top, closeTo(cards(tester).top, 1));
      await rotate(tester);
      expect(
        picture(tester).top,
        closeTo(banner(tester).top, 1),
        reason: 'with a banner, it is the right column\'s top',
      );
    } finally {
      model.dispose();
    }
  });

  testWidgets('on its side, the same margin both sides', (tester) async {
    final model = await car();
    try {
      await show(tester, model, side);
      expect(picture(tester).left, closeTo(Space.margin, 1));
      expect(cards(tester).right, closeTo(side.width - Space.margin, 1));
      expect(
        cards(tester).left - picture(tester).right,
        greaterThanOrEqualTo(Space.xl - 1),
        reason: 'the gutter between the columns',
      );
    } finally {
      model.dispose();
    }
  });
}
