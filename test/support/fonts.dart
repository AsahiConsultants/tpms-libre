import 'dart:io';

import 'package:flutter/services.dart';

/// Loads real fonts into the test runner, which otherwise ships none and
/// draws every glyph as a filled box.
///
/// Roboto and the Material icon font come from the Flutter SDK itself, so this
/// works on any machine with Flutter installed — and Roboto is what the app
/// actually renders in on Android, so a screenshot taken here looks like the
/// device. System fonts are only a fallback.
Future<void> loadFonts() async {
  final sdkFonts = _materialFontsDir();
  if (sdkFonts != null) {
    await _load('Roboto', [
      for (final w in ['Regular', 'Medium', 'Bold'])
        '${sdkFonts.path}/Roboto-$w.ttf',
    ]);
    await _load('MaterialIcons', [
      '${sdkFonts.path}/MaterialIcons-Regular.otf',
    ]);
    return;
  }
  for (final path in const [
    '/System/Library/Fonts/Supplemental/Arial.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
  ]) {
    if (File(path).existsSync()) {
      await _load('Roboto', [path]);
      return;
    }
  }
}

/// The test binary lives inside the SDK's cache, so the SDK root is found by
/// walking back from it rather than trusting an environment variable.
Directory? _materialFontsDir() {
  final exe = Platform.resolvedExecutable;
  final i = exe.indexOf(
    '${Platform.pathSeparator}bin${Platform.pathSeparator}cache',
  );
  if (i < 0) return null;
  final dir = Directory(
    '${exe.substring(0, i)}/bin/cache/artifacts/material_fonts',
  );
  return dir.existsSync() ? dir : null;
}

Future<void> _load(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final p in paths) {
    final f = File(p);
    if (!f.existsSync()) continue;
    // Synchronous on purpose: a widget test runs on a fake clock, and real
    // asynchronous file I/O inside it never completes.
    loader.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
  }
  await loader.load();
}
