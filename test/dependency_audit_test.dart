import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every dependency must be free software, and none may talk to the network
/// while the app is being built.
///
/// Both rules exist because of flutter_blue_plus. From 2.0 it moved to its
/// own licence — free for individuals, paid for any business — which F-Droid
/// cannot accept. From 2.3.5 it added a
/// Gradle task that, before every Android build, posted the app's id, name
/// and version to a Google Apps Script and failed silently if it could not.
/// Neither was visible from `flutter pub add`.

/// Licences that are free software, and that an MIT-licensed app can ship
/// alongside.
const _free = {
  'BSD-2-Clause': ['Redistribution and use in source and binary forms'],
  'BSD-3-Clause': [
    'Redistribution and use in source and binary forms',
    'Neither the name',
  ],
  'MIT': ['Permission is hereby granted, free of charge'],
  'Apache-2.0': ['Apache License', 'Version 2.0'],
  'MPL-2.0': ['Mozilla Public License Version 2.0'],
};

/// Phrases that mark a licence as not free software, whatever else it says.
const _unfree = [
  'commercial license is required',
  'for-profit',
  'may not be relicensed',
  'non-commercial',
  'noncommercial',
];

/// Build hooks run on the developer's machine. Each one is read before it is
/// allowed, and the reason recorded.
const _allowedBuildHooks = {
  'objective_c':
      'Dart team; compiles Objective-C for iOS and macOS only, '
      'returns immediately for Android, no network',
};

/// Network access from a Gradle script: what flutter_blue_plus's ping used.
final _network = RegExp(
  r'''openConnection|HttpURLConnection|java\.net\.|new\s+URL\s*\(|\bURL\s*\(\s*["']|URI\.create|HttpClient|script\.google\.com''',
);

String? classify(String licence) {
  final lower = licence.toLowerCase();
  if (_unfree.any(lower.contains)) return null;
  for (final MapEntry(:key, :value) in _free.entries.toList().reversed) {
    if (value.every(licence.contains)) return key;
  }
  return null;
}

List<({String name, Directory root})> _packages() {
  final config = File('.dart_tool/package_config.json');
  final decoded = jsonDecode(config.readAsStringSync());
  return [
    for (final p in (decoded['packages'] as List).cast<Map<String, dynamic>>())
      if (p['name'] != 'tpms_libre')
        (
          name: p['name'] as String,
          root: Directory.fromUri(
            Uri.parse(p['rootUri'] as String).isAbsolute
                ? Uri.parse(p['rootUri'] as String)
                : config.parent.uri.resolve(p['rootUri'] as String),
          ),
        ),
  ];
}

/// The Flutter SDK's root, found from the test binary, which lives inside
/// the SDK's cache.
final String? _flutterRoot = () {
  final exe = Platform.resolvedExecutable;
  final i = exe.indexOf(
    '${Platform.pathSeparator}bin${Platform.pathSeparator}cache',
  );
  return i < 0 ? null : exe.substring(0, i);
}();

/// The package's own licence. Flutter's SDK packages carry none of their
/// own; for those alone, the licence at the SDK's root, which covers them.
/// Everything else must ship its own — a pub package without one fails.
File? _licenceFile(Directory root) {
  final dirs = [
    root,
    if (_flutterRoot != null && root.path.startsWith(_flutterRoot!))
      Directory(_flutterRoot!),
  ];
  for (final dir in dirs) {
    for (final name in ['LICENSE', 'LICENSE.md', 'LICENSE.txt', 'COPYING']) {
      final f = File('${dir.path}/$name');
      if (f.existsSync()) return f;
    }
  }
  return null;
}

void main() {
  final hasConfig = File('.dart_tool/package_config.json').existsSync();
  final skip = hasConfig ? null : 'run `flutter pub get` first';

  group('the auditor itself', () {
    test('recognises the licence that started this', () {
      // Verbatim from flutter_blue_plus 2.3.12.
      expect(
        classify(
          'FlutterBluePlus License\nFor for-profit use and by for-profit '
          'organizations, a commercial license is required.\nPermission is '
          'hereby granted, free of charge, to any person',
        ),
        isNull,
      );
      expect(
        classify('Permission is hereby granted, free of charge, to any person'),
        'MIT',
      );
    });

    test('recognises the ping that started this', () {
      // Verbatim from flutter_blue_plus_android 9.0.3, license_ping.gradle.
      expect(
        _network.hasMatch(
          'connection = new URL("https://script.google.com/macros/s/x/exec")'
          '\n    .openConnection()',
        ),
        isTrue,
      );
      expect(_network.hasMatch("maven { url 'https://jitpack.io' }"), isFalse);
    });
  });

  test('every dependency is free software', () {
    final unfree = <String>[];
    for (final p in _packages()) {
      final f = _licenceFile(p.root);
      final kind = f == null ? null : classify(f.readAsStringSync());
      if (kind == null) {
        unfree.add('${p.name} (${f?.path ?? 'no licence file'})');
      }
    }
    expect(unfree, isEmpty, reason: 'read the licence before allowing it');
  }, skip: skip);

  test('no Android build script of any dependency touches the network', () {
    final offenders = <String>[];
    for (final p in _packages()) {
      final android = Directory('${p.root.path}/android');
      if (!android.existsSync()) continue;
      for (final f in android.listSync(recursive: true).whereType<File>()) {
        if (!(f.path.endsWith('.gradle') || f.path.endsWith('.gradle.kts'))) {
          continue;
        }
        if (_network.hasMatch(f.readAsStringSync())) {
          offenders.add('${p.name}: ${f.path}');
        }
      }
    }
    expect(offenders, isEmpty);
  }, skip: skip);

  test('every Dart build hook has been read and allowed', () {
    final unreviewed = [
      for (final p in _packages())
        if (File('${p.root.path}/hook/build.dart').existsSync() &&
            !_allowedBuildHooks.containsKey(p.name))
          p.name,
    ];
    expect(unreviewed, isEmpty, reason: 'build hooks run on your machine');
  }, skip: skip);
}
