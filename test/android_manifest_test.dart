import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The permissions are the app's privacy promise, and two of them have
/// already been got wrong once in ways nothing else would catch.

String _manifest() =>
    File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

/// The XML with comments removed, so a warning about a flag is not
/// mistaken for the flag.
String _withoutComments(String xml) =>
    xml.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

/// The flag itself, as an attribute value, not the word.
final _neverForLocation = RegExp(
  r'usesPermissionFlags\s*=\s*"[^"]*neverForLocation',
);

void main() {
  test('BLUETOOTH_SCAN never carries neverForLocation', () {
    // Declaring it is what makes Android strip iBeacon data from scan
    // results — silently, while every other advertisement still arrives.
    // The readings are inside an iBeacon frame. Plugin READMEs recommend it.
    expect(_neverForLocation.hasMatch(_withoutComments(_manifest())), isFalse);
  });

  test('no dependency slips neverForLocation in through the merge', () {
    // A library's manifest is merged into the app's, so a plugin update
    // declaring the flag would reintroduce the stripping with no change here.
    final config = File('.dart_tool/package_config.json');
    if (!config.existsSync()) {
      markTestSkipped('run `flutter pub get` first');
      return;
    }
    final packages = (jsonDecode(config.readAsStringSync())['packages'] as List)
        .cast<Map<String, dynamic>>();
    final offenders = <String>[];
    for (final p in packages) {
      // The app's own manifest is the test above; its build output is not
      // a dependency.
      if (p['name'] == 'tpms_libre') continue;
      final root = Directory.fromUri(
        Uri.parse(p['rootUri'] as String).isAbsolute
            ? Uri.parse(p['rootUri'] as String)
            : config.parent.uri.resolve(p['rootUri'] as String),
      );
      for (final f
          in root
              .listSync(recursive: true, followLinks: false)
              .whereType<File>()
              .where((f) => f.path.endsWith('AndroidManifest.xml'))) {
        if (_neverForLocation.hasMatch(
              _withoutComments(f.readAsStringSync()),
            ) &&
            !f.path.contains('/example/')) {
          offenders.add('${p['name']}: ${f.path}');
        }
      }
    }
    expect(offenders, isEmpty);
  });

  test('location is declared, because the readings need it', () {
    expect(_manifest(), contains('android.permission.ACCESS_FINE_LOCATION'));
    expect(_manifest(), contains('android.permission.BLUETOOTH_SCAN'));
  });

  test('INTERNET is removed from the merged manifest', () {
    expect(
      RegExp(r'android\.permission\.INTERNET"\s+tools:node="remove"')
          .hasMatch(_manifest()),
      isTrue,
    );
  });

  test('nothing asks to advertise', () {
    expect(_manifest(), isNot(contains('BLUETOOTH_ADVERTISE')));
  });
}
