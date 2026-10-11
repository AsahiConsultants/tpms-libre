import 'dart:math' as math;

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

import 'support/fonts.dart';

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

/// Every paragraph on screen except icons, with whether it sits on a card.
List<({RenderParagraph p, bool onCard})> paragraphs(WidgetTester tester) {
  final cards = {
    for (final e in find.byType(TyreCard).evaluate()) e.renderObject,
  };
  final out = <({RenderParagraph p, bool onCard})>[];
  void walk(RenderObject ro) {
    if (ro is RenderParagraph &&
        ro.text.style?.fontFamily != 'MaterialIcons' &&
        ro.text.toPlainText().trim().isNotEmpty) {
      var onCard = false;
      for (RenderObject? a = ro; a != null; a = a.parent) {
        if (cards.contains(a)) onCard = true;
      }
      out.add((p: ro, onCard: onCard));
    }
    ro.visitChildren(walk);
  }

  walk(tester.binding.rootElement!.renderObject!);
  return out;
}

double _luminance(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

/// WCAG contrast of [fg], composited over [bg].
double contrast(Color fg, Color bg) {
  final over = Color.alphaBlend(fg, bg);
  final (a, b) = (_luminance(over), _luminance(bg));
  return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
}

/// White, grey, or translucent white: the colours text gets for being
/// secondary. Health colours are checked where they are chosen.
bool isNeutral(Color c) {
  final channels = [c.r, c.g, c.b];
  return channels.reduce(math.max) - channels.reduce(math.min) < 0.16;
}

const sheet = Color(0xFF1B1F26);

/// The lighter end of a card's gradient, where its label sits.
const cardTop = Color(0xFF32383F);

void main() {
  setUpAll(loadFonts);
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

  testWidgets('every piece of text is on the scale, and readable', (
    tester,
  ) async {
    final model = await car();
    final allowed = {
      for (final r in [
        TypeScale.title,
        TypeScale.heading,
        TypeScale.row,
        TypeScale.body,
        TypeScale.caption,
        TypeScale.overline,
      ])
        r.fontSize,
    };
    final offScale = <String>{};
    final faint = <String>{};
    final unset = <String>{};
    void check(String where) {
      for (final (:p, :onCard) in paragraphs(tester)) {
        if (onCard) continue;
        final text = p.text.toPlainText().trim();
        final style = p.text.style!;
        // Readings are numbers sized to be read at a glance.
        if (RegExp(r'^\d+$').hasMatch(text)) continue;
        // A style set in the theme replaces the inherited one, font and
        // all; list subtitles once drew in the bare default font that way.
        if (style.fontFamily != 'Roboto') {
          unset.add('$where: "$text" in ${style.fontFamily}');
        }
        if (!allowed.contains(style.fontSize)) {
          offScale.add('$where: "$text" at ${style.fontSize}');
        }
        final colour = style.color!;
        if (isNeutral(colour) && contrast(colour, sheet) < 4.5) {
          faint.add(
            '$where: "$text" at '
            '${contrast(colour, sheet).toStringAsFixed(1)}:1',
          );
        }
      }
    }

    try {
      await show(tester, model);
      check('home');
      for (final (name, open) in <(String, Future<void> Function())>[
        ('wheel', () => tester.tap(find.byType(TyreCard).first)),
        ('position picker', () => tester.tap(find.byType(ActionChip).first)),
        ('settings', () => tester.tap(find.byTooltip('Target pressures'))),
        ('photo', () => tester.tap(find.text('Add a photo of your vehicle'))),
      ]) {
        await open();
        await tester.pumpAndSettle();
        check(name);
        await close(tester);
      }

      await tester.tap(find.byType(TyreCard).last);
      await tester.pumpAndSettle();
      check('empty wheel');
      await tester.tap(find.text('Assign a sensor'));
      await tester.pumpAndSettle();
      check('sensor picker');
      await close(tester);
      await close(tester);

      await tester.tap(find.text('Weekend car'));
      await tester.pumpAndSettle();
      check('garage');
      await tester.tap(find.text('Add a vehicle'));
      await tester.pumpAndSettle();
      check('vehicle form');
    } finally {
      model.dispose();
    }
    expect(unset, isEmpty, reason: 'text without the theme\'s font');
    expect(offScale, isEmpty, reason: 'sizes outside TypeScale');
    expect(faint, isEmpty, reason: 'small text needs 4.5:1');
  });

  for (final (name, layout) in [
    ('five to a row', WheelLayout.carWithSpare),
    ('two to a row', WheelLayout.motorcycle),
  ]) {
    testWidgets('a card\'s text, $name: no smaller than 10, and readable', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(411, 914) * 2.625;
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      final model = await car();
      await model.setLayout(model.vehicle.id, layout);
      for (final (i, position) in model.positions.indexed) {
        await model.assign('d0e00${i + 1}', position);
      }
      try {
        await show(tester, model);
        final cardText = [
          for (final (:p, :onCard) in paragraphs(tester))
            if (onCard) p,
        ];
        expect(cardText, isNotEmpty);
        for (final p in cardText) {
          final text = p.text.toPlainText().trim();
          final style = p.text.style!;
          final card = find
              .ancestor(
                of: find.byWidgetPredicate(
                  (w) => w is RichText && identical(w.text, p.text),
                ),
                matching: find.byType(TyreCard),
              )
              .evaluate()
              .first
              .renderObject!;
          // The card shrinks its contents to fit; this is the size drawn.
          final scale = p.getTransformTo(card).getMaxScaleOnAxis();
          final drawn = style.fontSize! * scale;
          if (RegExp(r'^\d+$').hasMatch(text)) {
            expect(scale, closeTo(1, 0.001), reason: 'the pressure shrank');
            continue;
          }
          expect(drawn, greaterThanOrEqualTo(10 - 0.01), reason: '"$text"');
          if (isNeutral(style.color!)) {
            expect(
              contrast(style.color!, cardTop),
              greaterThanOrEqualTo(4.5),
              reason: '"$text"',
            );
          }
        }
        // Written the way the rest of the app writes it.
        expect(find.text('28°C'), findsNothing);
        expect(find.text('28\u00a0°C'), findsWidgets);
      } finally {
        model.dispose();
      }
    });
  }
}
