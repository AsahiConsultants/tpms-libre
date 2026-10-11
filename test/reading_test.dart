import 'package:flutter_test/flutter_test.dart';
import 'package:tpms_libre/treel/reading.dart';

/// Frames below were captured from five real sensors and cross-checked
/// against the vendor app, with one change: the three sensor-id bytes (the
/// tail of each sensor's MAC) are replaced with synthetic ids, `f10a01` to
/// `f10a05`. A sensor's MAC is a persistent identifier for one particular
/// vehicle, and there is no reason to publish one. The pressure and
/// temperature bytes are exactly as received.
List<int> hex(String s) => [
  for (var i = 0; i < s.length; i += 2)
    int.parse(s.substring(i, i + 2), radix: 16),
];

Map<int, List<int>> apple(String frame) => {appleManufacturerId: hex(frame)};

void main() {
  group('decodeTreel', () {
    test('decodes every sensor captured from the car', () {
      final cases = {
        // frame                                             id, psi, celsius
        '0215ffffffffffffffffffffffffffffffe0f10a02238a': ('f10a02', 35, 28),
        '0215ffffffffffffffffffffffffffffffe0f10a04228a': ('f10a04', 34, 28),
        '0215ffffffffffffffffffffffffffffffe0f10a03238a': ('f10a03', 35, 28),
        '0215ffffffffffffffffffffffffffffffe0f10a012389': ('f10a01', 35, 27),
        '0215ffffffffffffffffffffffffffffffe0f10a051e8c': ('f10a05', 30, 30),
      };
      for (final entry in cases.entries) {
        final r = decodeTreel(apple(entry.key), rssi: -70);
        expect(r, isNotNull, reason: entry.key);
        expect(r!.sensorId, entry.value.$1);
        expect(r.psi, entry.value.$2);
        expect(r.celsius, entry.value.$3);
      }
    });

    test('decodes the warm frames recorded after a drive', () {
      // Same sensors after driving. f10a02 rose 35 psi/28 C -> 37 psi/41 C,
      // which the ideal gas law predicts as 37.1 psi. f10a05 is the spare
      // and barely moved, because it never rotates.
      final warm = {
        '0215ffffffffffffffffffffffffffffffe0f10a022597': ('f10a02', 37, 41),
        '0215ffffffffffffffffffffffffffffffe0f10a03248f': ('f10a03', 36, 33),
        '0215ffffffffffffffffffffffffffffffe0f10a04228f': ('f10a04', 34, 33),
        '0215ffffffffffffffffffffffffffffffe0f10a051e8b': ('f10a05', 30, 29),
      };
      for (final entry in warm.entries) {
        final r = decodeTreel(apple(entry.key), rssi: -69);
        expect(r!.sensorId, entry.value.$1);
        expect(r.psi, entry.value.$2);
        expect(r.celsius, entry.value.$3);
      }
    });

    test('converts pressure units', () {
      final r = decodeTreel(
        apple('0215ffffffffffffffffffffffffffffffe0f10a02238a'),
        rssi: -70,
      )!;
      expect(r.bar, closeTo(2.41, 0.01));
      expect(r.kpa, closeTo(241.3, 0.5));
    });

    test('rejects an iBeacon that is not a Treel sensor', () {
      // Synthetic: a real Treel frame with one bit changed in the UUID
      // (e0 -> e1). No genuine third-party iBeacon appeared in our captures,
      // so this stands in for one.
      final r = decodeTreel(
        apple('0215ffffffffffffffffffffffffffffffe1f10a02238a'),
        rssi: -70,
      );
      expect(r, isNull);
    });

    test('rejects non-Apple manufacturer data', () {
      // Some other company's device. Invented bytes: only the company id
      // matters to the decoder, so nothing real needs to stand in here.
      expect(
        decodeTreel({0x0909: hex('0102030405060708090a0b0c0d')}, rssi: -45),
        isNull,
      );
    });

    test('rejects a truncated or empty frame', () {
      expect(decodeTreel(apple('0215ffff'), rssi: -70), isNull);
      expect(decodeTreel({}, rssi: -70), isNull);
    });
  });
}
