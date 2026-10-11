import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tpms_libre/treel/model.dart';
import 'package:tpms_libre/treel/scanner.dart';
import 'package:tpms_libre/ui/home_page.dart';
import 'package:tpms_libre/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Anything that stops readings arriving has to say so on screen. Silence
/// looks exactly like a quiet car, and the user cannot tell the difference.

/// Pumps the home screen with the scanner forced into [status], runs
/// [checks], then disposes. Disposal happens here rather than in a tearDown
/// because the model holds timers and Flutter checks for pending ones first.
Future<void> withStatus(
  WidgetTester tester,
  ScanStatus status, {
  String? message,
  double textScale = 1.0,
  required void Function() checks,
}) async {
  tester.view.physicalSize = const Size(411, 915) * 3.0;
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  final model = TreelModel();
  try {
    await model.load();
    await model.setAnimations(false);
    final scanner = TreelScanner(model);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: HomePage(model: model, scanner: scanner),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    );
    scanner.debugSetStatus(status, message);
    await tester.pump();
    checks();
  } finally {
    model.dispose();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('bluetooth off says so, and says what to do', (tester) async {
    await withStatus(
      tester,
      ScanStatus.bluetoothOff,
      checks: () {
        expect(find.text('Bluetooth is off'), findsOneWidget);
        expect(find.textContaining('pull down to refresh'), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
      },
    );
  });

  testWidgets('location off explains why it is even needed', (tester) async {
    await withStatus(
      tester,
      ScanStatus.locationServicesOff,
      checks: () {
        expect(find.text('Location is off'), findsOneWidget);
        // The permission is Android's demand, not ours, and the app cannot
        // leak anything regardless. Worth saying on the screen that asks.
        expect(find.textContaining('no internet permission'), findsOneWidget);
      },
    );
  });

  testWidgets('missing permissions name both of them', (tester) async {
    await withStatus(
      tester,
      ScanStatus.noPermission,
      checks: () {
        expect(find.text('Permissions needed'), findsOneWidget);
        expect(find.textContaining('Nearby devices'), findsOneWidget);
      },
    );
  });

  testWidgets('a scan failure shows the reason it gave', (tester) async {
    await withStatus(
      tester,
      ScanStatus.error,
      message: 'adapter is busy',
      checks: () {
        expect(find.text('Scan failed'), findsOneWidget);
        expect(find.text('adapter is busy'), findsOneWidget);
      },
    );
  });

  testWidgets('scanning normally shows no banner at all', (tester) async {
    await withStatus(
      tester,
      ScanStatus.scanning,
      checks: () {
        expect(find.text('Retry'), findsNothing);
        expect(find.textContaining('is off'), findsNothing);
      },
    );
  });

  testWidgets('every status is handled, none falls through silently', (
    tester,
  ) async {
    // If a status is added without a banner case, the app would go quiet
    // about a condition someone thought worth naming. Scanning and idle are
    // the only two that should show nothing.
    const silent = {ScanStatus.scanning, ScanStatus.idle};
    for (final status in ScanStatus.values) {
      await withStatus(
        tester,
        status,
        message: 'because reasons',
        checks: () {
          final banner = find.text('Retry');
          if (silent.contains(status)) {
            expect(banner, findsNothing, reason: '$status should be silent');
          } else {
            expect(banner, findsOneWidget, reason: '$status needs a banner');
          }
        },
      );
    }
  });

  testWidgets('location off blames the format, not the user', (tester) async {
    await withStatus(
      tester,
      ScanStatus.locationServicesOff,
      checks: () {
        // The sensors advertise as iBeacons; Android classes iBeacons as
        // location data. That is the reason, and it is worth saying, along
        // with the fact that nothing can leave the phone.
        expect(find.textContaining('iBeacons'), findsOneWidget);
        expect(find.textContaining('no internet permission'), findsOneWidget);
        expect(find.textContaining('never asks where you are'), findsOneWidget);
      },
    );
  });

  testWidgets('the banner survives large text', (tester) async {
    for (final scale in [1.3, 2.0]) {
      await withStatus(
        tester,
        ScanStatus.locationServicesOff,
        textScale: scale,
        checks: () => expect(find.text('Location is off'), findsOneWidget),
      );
    }
  });
}
