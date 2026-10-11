import 'package:flutter/material.dart';

import '../treel/model.dart';

/// Dark by default: this gets read in a car, often at night, and a white
/// screen at a glance is worse than useless.
ThemeData buildTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF3FB27F),
        brightness: Brightness.dark,
      ).copyWith(
        surface: const Color(0xFF14171C),
        surfaceContainer: const Color(0xFF1B1F26),
        surfaceContainerHighest: const Color(0xFF232830),
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFF0E1013),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF0E1013),
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Color(0xFF1B1F26),
      surfaceTintColor: Colors.transparent,
    ),
    // On the page margin, like every heading in every sheet. Flutter's own
    // 16 left each list a few pixels inside the title above it.
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: Space.margin),
    ),
  );
}

/// Digits that do not shuffle sideways as the value changes.
const List<FontFeature> steadyDigits = [FontFeature.tabularFigures()];

class HealthColors {
  static const ok = Color(0xFF3FB27F);
  static const watch = Color(0xFFE0A030);
  static const alert = Color(0xFFE2574C);
  static const unknown = Color(0xFF5A626E);

  static Color of(TyreHealth h) => switch (h) {
    TyreHealth.ok => ok,
    TyreHealth.watch => watch,
    TyreHealth.alert => alert,
    TyreHealth.unknown => unknown,
  };
}

/// "just now", "4m", "2h" -- short enough to sit under a tyre.
String shortAge(Duration? d) {
  if (d == null) return 'never';
  if (d.inSeconds < 90) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}

/// One spacing scale for the whole app.
///
/// Before this, every part chose its own: the picture and cards sat 14 from
/// the edge, the banner 14 plus a margin of its own, the status lines 16,
/// the sheets 20 and their list rows 16, the title 22. Nothing lined up, and
/// gaps between elements were whatever each widget happened to pick.
abstract final class Space {
  /// Between lines that belong together: a hint and its chips, two status
  /// lines.
  static const s = 8.0;

  /// Between parts of one composition: the picture and its readings.
  static const m = 12.0;

  /// Between separate elements: a banner and what it is about, the readings
  /// and what they mean.
  static const l = 16.0;

  /// Between columns, and between sections of a sheet.
  static const xl = 24.0;

  /// From the screen edge to content, everywhere: the title, the picture,
  /// the readings, the status lines, the text in every sheet.
  static const margin = 20.0;
}

/// The type scale: what a piece of text is decides how it looks.
///
/// The app used to render 53 text styles in 19 sizes. A sheet's title was
/// 16, 19 or 22 depending on the sheet, a row read "Bike" at 16 in the garage
/// and "Motorcycle" at 14 one tap later in the form, and a block of four
/// facts mixed three sizes.
///
/// Readings are numbers to be read at a glance and are sized for that where
/// they appear; everything else is one of these.
abstract final class TypeScale {
  /// What a screen or sheet is about: the vehicle in the app bar, "Front
  /// left", "Vehicles", "Which sensor is on the spare?".
  static const title = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
  );

  /// A section inside a sheet, and the home screen's one-line verdict.
  static const heading = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.15,
  );

  /// One item in a list or form: a vehicle, an action, a setting. The same
  /// as the text Flutter gives a ListTile, so a hand-built row matches one.
  static const row = TextStyle(fontSize: 16, letterSpacing: 0.5);

  /// Sentences, and the values beside a label.
  static const body = TextStyle(fontSize: 14, letterSpacing: 0.25);
}
