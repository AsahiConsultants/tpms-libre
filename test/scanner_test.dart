import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tpms_libre/treel/model.dart';
import 'package:tpms_libre/treel/reading.dart';
import 'package:tpms_libre/treel/scanner.dart';
import 'package:universal_ble/universal_ble.dart';

/// A Bluetooth stack with no radio: it reports whatever state it is told,
/// counts scan starts, and hands over advertisements on demand.
class FakeBle extends UniversalBlePlatform {
  AvailabilityState state = AvailabilityState.poweredOn;
  int starts = 0;
  PlatformConfig? lastConfig;
  Object? failNextStart;

  @override
  Future<AvailabilityState> getBluetoothAvailabilityState() async => state;

  @override
  Future<void> startScan({
    ScanFilter? scanFilter,
    PlatformConfig? platformConfig,
  }) async {
    final failure = failNextStart;
    failNextStart = null;
    if (failure != null) throw failure;
    starts++;
    lastConfig = platformConfig;
  }

  @override
  Future<void> stopScan() async {}

  @override
  Future<bool> isScanning() async => false;

  /// Everything else is connection machinery the scanner must never touch.
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'the scanner called ${invocation.memberName}, which it has no business '
    'calling: it only listens',
  );

  void advertise(Map<int, List<int>> manufacturerData, {int rssi = -60}) {
    updateScanResult(
      BleDevice(
        deviceId: 'fake-sensor',
        name: null,
        rssi: rssi,
        manufacturerDataList: [
          for (final e in manufacturerData.entries)
            ManufacturerData(e.key, Uint8List.fromList(e.value)),
        ],
      ),
    );
  }
}

TreelReading? heard(TreelModel m, String id) =>
    m.allReadings.where((r) => r.sensorId == id).firstOrNull;

List<int> hex(String s) => [
  for (var i = 0; i < s.length; i += 2)
    int.parse(s.substring(i, i + 2), radix: 16),
];

/// Lets streams and queued platform calls run.
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  late FakeBle ble;
  late TreelModel model;
  late TreelScanner scanner;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ble = FakeBle();
    UniversalBle.setInstance(ble);
    model = TreelModel();
    await model.load();
    scanner = TreelScanner(model);
  });

  tearDown(() {
    scanner.dispose();
    model.dispose();
  });

  test('a Treel broadcast becomes a reading', () async {
    await scanner.start();
    await settle();
    expect(scanner.status, ScanStatus.scanning);

    // Synthetic sensor id; pressure 0x23 = 35 psi, temperature 0x8a = 28 °C.
    ble.advertise({
      0x004C: hex('0215ffffffffffffffffffffffffffffffe0f10a02238a'),
    });
    await settle();

    final reading = heard(model, 'f10a02');
    expect(reading, isNotNull);
    expect(reading!.psi, 35);
    expect(reading.celsius, 28);
  });

  test('every manufacturer entry is looked at, not just the first', () async {
    await scanner.start();
    await settle();
    ble.advertise({
      0x0059: [1, 2, 3, 4],
      0x004C: hex('0215ffffffffffffffffffffffffffffffe0f10a02238a'),
    });
    await settle();
    expect(heard(model, 'f10a02'), isNotNull);
  });

  test('other devices are ignored', () async {
    await scanner.start();
    await settle();
    ble.advertise({0x0059: hex('0102030405060708090a0b0c0d')});
    await settle();
    expect(model.allReadings, isEmpty);
  });

  test('scans the way the sensors need', () async {
    await scanner.start();
    await settle();
    final android = ble.lastConfig?.android;
    expect(
      android?.requestLocationPermission,
      isTrue,
      reason: 'without location, Android strips the iBeacon frame silently',
    );
    expect(android?.scanMode, AndroidScanMode.lowLatency);
    expect(android?.callbackType, [
      AndroidScanCallbackType.allMatches,
    ], reason: 'repeat broadcasts are how a reading stays current');
  });

  test('starting twice at once starts one scan', () async {
    // The availability stream replays the current state on subscribe while
    // start() also evaluates directly; both arrive before the first scan
    // has finished starting.
    await scanner.start();
    await settle();
    expect(ble.starts, 1);
  });

  test('Bluetooth off is reported, and coming back on resumes', () async {
    ble.state = AvailabilityState.poweredOff;
    await scanner.start();
    await settle();
    expect(scanner.status, ScanStatus.bluetoothOff);
    expect(ble.starts, 0);

    ble.state = AvailabilityState.poweredOn;
    ble.updateAvailability(AvailabilityState.poweredOn);
    await settle();
    expect(scanner.status, ScanStatus.scanning);
    expect(ble.starts, 1);
  });

  test('no Bluetooth adapter at all is reported as unsupported', () async {
    ble.state = AvailabilityState.unknown;
    await scanner.start();
    await settle();
    expect(scanner.status, ScanStatus.unsupported);
  });

  test('a refused permission says so', () async {
    ble.failNextStart = UniversalBleException(
      code: UniversalBleErrorCode.bluetoothNotAllowed,
      message: 'Permissions not granted',
    );
    await scanner.start();
    await settle();
    expect(scanner.status, ScanStatus.noPermission);
  });

  test('a failed start can be retried', () async {
    ble.failNextStart = UniversalBleException(
      code: UniversalBleErrorCode.scanFailed,
      message: 'SCAN_FAILED_INTERNAL_ERROR',
    );
    await scanner.start();
    await settle();
    expect(scanner.status, ScanStatus.error);

    await scanner.retry();
    await settle();
    expect(scanner.status, ScanStatus.scanning);
  });

  test('pulling to refresh many times stays under Android\'s limit', () async {
    // Android silently stops delivering results to an app that starts more
    // than five scans in thirty seconds.
    await scanner.start();
    await settle();
    for (var i = 0; i < 8; i++) {
      await scanner.retry();
      await settle();
    }
    expect(ble.starts, TreelScanner.maxStartsPerWindow);
    expect(TreelScanner.maxStartsPerWindow, lessThan(5));
  });

  test('a long scan is renewed before Android throttles it', () {
    expect(
      TreelScanner.renewAfter,
      lessThan(const Duration(minutes: 30)),
      reason: 'Android demotes a scan once it has run for thirty minutes',
    );
  });
}
