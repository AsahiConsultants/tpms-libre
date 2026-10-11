import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tpms_libre/treel/model.dart';
import 'package:tpms_libre/treel/reading.dart';
import 'package:tpms_libre/treel/scanner.dart';
import 'package:tpms_libre/ui/home_page.dart';
import 'package:tpms_libre/ui/settings_sheet.dart';
import 'package:tpms_libre/ui/theme.dart';
import 'package:tpms_libre/ui/tyre.dart';

/// What moves, and what stops it. The only animation with an ongoing cost
/// is the breathing "Listening" dot: while it moves the app redraws every
/// frame and never idles, so "off" has to mean the screen genuinely rests.

Future<(TreelModel, TreelScanner)> listening() async {
  final model = TreelModel();
  await model.load();
  await model.assign('d0e001', TyrePosition.frontLeft);
  model.ingest(
    TreelReading(
      sensorId: 'd0e001',
      psi: 33,
      celsius: 28,
      rssi: -60,
      at: DateTime.now(),
    ),
  );
  final scanner = TreelScanner(model)..debugSetStatus(ScanStatus.scanning);
  return (model, scanner);
}

Future<void> show(
  WidgetTester tester,
  TreelModel model,
  TreelScanner scanner, {
  bool systemSaysNoMotion = false,
}) async {
  tester.view.physicalSize = const Size(411, 915) * 3.0;
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(),
      home: HomePage(model: model, scanner: scanner),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(disableAnimations: systemSaysNoMotion),
        child: child!,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Whether anything is still asking for frames.
bool idle(WidgetTester tester) => !tester.binding.hasScheduledFrame;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('listening, with motion allowed, the dot breathes', (
    tester,
  ) async {
    final (model, scanner) = await listening();
    try {
      await show(tester, model, scanner);
      expect(idle(tester), isFalse, reason: 'the dot is animating');
    } finally {
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    }
  });

  testWidgets('the app\'s own switch lets the screen rest', (tester) async {
    final (model, scanner) = await listening();
    try {
      await model.setAnimations(false);
      await show(tester, model, scanner);
      expect(idle(tester), isTrue);
    } finally {
      model.dispose();
    }
  });

  testWidgets('Android\'s "Remove animations" lets it rest too', (
    tester,
  ) async {
    final (model, scanner) = await listening();
    try {
      expect(model.animations, isTrue, reason: 'the app switch is still on');
      await show(tester, model, scanner, systemSaysNoMotion: true);
      expect(idle(tester), isTrue);
    } finally {
      model.dispose();
    }
  });

  testWidgets('switching off mid-breath really stops it', (tester) async {
    // The dot used to swap to a still picture while its animation kept
    // ticking underneath, so the screen went on redrawing regardless.
    final (model, scanner) = await listening();
    try {
      await show(tester, model, scanner);
      expect(idle(tester), isFalse);

      await model.setAnimations(false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(idle(tester), isTrue);
    } finally {
      model.dispose();
    }
  });

  testWidgets('when listening stops, so does the dot', (tester) async {
    final (model, scanner) = await listening();
    try {
      await show(tester, model, scanner);
      expect(idle(tester), isFalse);

      scanner.debugSetStatus(ScanStatus.bluetoothOff);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(idle(tester), isTrue);
    } finally {
      model.dispose();
    }
  });

  testWidgets('with "Remove animations" on, a new reading just appears', (
    tester,
  ) async {
    final (model, scanner) = await listening();
    try {
      await show(tester, model, scanner, systemSaysNoMotion: true);
      final card = find.byType(TyreCard).first;
      expect(
        find.descendant(of: card, matching: find.byType(AnimatedSwitcher)),
        findsNothing,
        reason: 'the number swaps without sliding',
      );
    } finally {
      model.dispose();
    }
  });

  testWidgets('settings says why its switch has no effect', (tester) async {
    tester.view.physicalSize = const Size(411, 915) * 3.0;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Scaffold(
          body: SettingsSheet(
            vehicleName: 'My car',
            layout: WheelLayout.car,
            spec: const PressureSpec(),
            onChanged: (_) {},
            haptics: true,
            animations: true,
            onHaptics: (_) {},
            onAnimations: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('"Remove animations" is on'), findsOneWidget);
  });
}
