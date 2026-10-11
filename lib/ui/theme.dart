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
