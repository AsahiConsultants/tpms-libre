import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tpms_libre/treel/model.dart';
import 'package:tpms_libre/treel/reading.dart';
import 'package:tpms_libre/treel/scanner.dart';
import 'package:tpms_libre/ui/home_page.dart';
import 'package:tpms_libre/ui/settings_sheet.dart';
import 'package:tpms_libre/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The settings sheet is long — three targets, four tolerances, a preview
/// and two switches — so it is the screen most likely to collide with
/// something. It ran under the status bar in the first build.

const sizes = <String, Size>{
  'small phone': Size(320, 600),
  'pixel': Size(411, 915),
  'short screen': Size(400, 640),
};

Future<void> pumpSheet(
  WidgetTester tester, {
  required Size size,
  required double textScale,
  WheelLayout layout = WheelLayout.carWithSpare,
}) async {
  tester.view.physicalSize = size * 3.0;
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: SettingsSheet(
          vehicleName: 'My vehicle',
          layout: layout,
          spec: const PressureSpec(front: 32, rear: 30, spare: 34),
          onChanged: (_) {},
          haptics: true,
          animations: true,
          onHaptics: (_) {},
          onAnimations: (_) {},
        ),
      ),
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
  group('what the vehicle actually has', () {
    testWidgets('a motorcycle is offered no spare pressure', (tester) async {
      // Setting a target for a wheel that does not exist is a number that
      // can never apply to anything.
      await pumpSheet(
        tester,
        size: const Size(411, 915),
        textScale: 1.0,
        layout: WheelLayout.motorcycle,
      );
      expect(find.text('Spare'), findsNothing);
      expect(find.text('Front wheel'), findsOneWidget);
      expect(find.text('Rear wheel'), findsOneWidget);
      expect(find.textContaining('door placard'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a car with a spare is offered one', (tester) async {
      await pumpSheet(tester, size: const Size(411, 915), textScale: 1.0);
      // Twice: the stepper that sets it, and the preview that shows what
      // the bands will look like.
      expect(find.text('Spare'), findsNWidgets(2));
      expect(find.text('Front axle'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a car without a spare is not', (tester) async {
      await pumpSheet(
        tester,
        size: const Size(411, 915),
        textScale: 1.0,
        layout: WheelLayout.car,
      );
      expect(find.text('Spare'), findsNothing);
      expect(find.text('Front axle'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('settings sheet never overflows', () {
    for (final entry in sizes.entries) {
      for (final scale in [1.0, 1.3, 2.0]) {
        for (final layout in WheelLayout.values) {
          testWidgets('${entry.key}, text x$scale, ${layout.name}', (
            tester,
          ) async {
            await pumpSheet(
              tester,
              size: entry.value,
              textScale: scale,
              layout: layout,
            );
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  });

  testWidgets('it scrolls rather than clipping its contents', (tester) async {
    await pumpSheet(tester, size: const Size(400, 640), textScale: 1.0);
    expect(find.text('Target pressure'), findsOneWidget);

    // The switches live at the bottom of a long sheet; they must be
    // reachable, not merely present.
    await tester.dragUntilVisible(
      find.text('Haptics'),
      find.byType(SingleChildScrollView),
      const Offset(0, -120),
    );
    expect(find.text('Haptics'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNWidgets(2));
  });

  testWidgets('the preview spells out the bands in real numbers', (
    tester,
  ) async {
    await pumpSheet(tester, size: const Size(411, 915), textScale: 1.0);
    // Front target 32, watch at -3 and +8, alert at -6 and +12.
    expect(find.text('≤26'), findsOneWidget);
    expect(find.text('30–39'), findsOneWidget);
    expect(find.text('≥44'), findsOneWidget);
  });

  testWidgets('opened for real, it clears the status bar', (tester) async {
    // The bug this exists for: showModalBottomSheet leaves useSafeArea off
    // by default, so a scroll-controlled sheet slides under the status bar
    // and the first heading lands on top of the clock. Pumping the sheet on
    // its own never shows that — it only appears when the sheet is actually
    // presented over a screen with an inset.
    SharedPreferences.setMockInitialValues({});
    const statusBar = 48.0;
    tester.view.physicalSize = const Size(411, 915) * 3.0;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final model = TreelModel();
    try {
      await model.load();
      await model.setAnimations(false);
      model.ingest(
        TreelReading(
          sensorId: 'a',
          psi: 32,
          celsius: 24,
          rssi: -70,
          at: DateTime.now(),
        ),
      );
      await model.assign('a', TyrePosition.frontLeft);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: HomePage(model: model, scanner: TreelScanner(model)),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(padding: const EdgeInsets.only(top: statusBar)),
            child: child!,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.tune_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Target pressure'), findsOneWidget);
      final top = tester.getTopLeft(find.text('Target pressure')).dy;
      expect(
        top,
        greaterThanOrEqualTo(statusBar),
        reason: 'the first heading must not sit under the status bar',
      );
      expect(tester.takeException(), isNull);
    } finally {
      model.dispose();
    }
  });
}
