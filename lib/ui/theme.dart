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
