import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

import 'location_services.dart';
import 'model.dart';
import 'reading.dart';

enum ScanStatus {
  idle,
  unsupported,
  bluetoothOff,
  locationServicesOff,
  noPermission,
  scanning,
  error,
}

/// Listens for Treel broadcasts and feeds them to the model.
///
/// Two things have to be true before Android will hand over an
/// advertisement: Bluetooth on, and location services on. Both are treated
/// the same way — a plain state we watch and report — because the app can do
/// nothing useful while either is off, and guessing from symptoms was worse
/// than asking.
///
/// Nothing is ever connected to. Everything needed is in the advertisement.
class TreelScanner extends ChangeNotifier {
  TreelScanner(this.model);

  final TreelModel model;

  ScanStatus _status = ScanStatus.idle;
  String? _message;
  AvailabilityState _adapter = AvailabilityState.unknown;
  bool _locationOn = true; // until told otherwise; only Android reports it

  /// Whether a scan is running on the platform. Kept apart from [status],
  /// which is what the screen shows: restarting a scan should not flash a
  /// banner.
  bool _active = false;

  StreamSubscription<BleDevice>? _results;
  StreamSubscription<AvailabilityState>? _adapterChanges;
  StreamSubscription<bool>? _location;
  Timer? _renew;
  Timer? _deferred;

  /// When each recent scan was started.
  ///
  /// Android quietly stops returning results to an app that starts scanning
  /// more than five times in thirty seconds — no error, just silence — and
  /// pull to refresh restarts the scan. One start is held in reserve.
  final List<DateTime> _starts = [];
  static const maxStartsPerWindow = 4;
  static const startWindow = Duration(seconds: 30);

  /// Android moves a scan that has run for thirty minutes into a mode that
  /// only sees what other apps happen to be scanning for, so a phone left on
  /// the dashboard for a long drive would slowly go quiet. Restarting before
  /// then resets the clock.
  static const renewAfter = Duration(minutes: 25);

  ScanStatus get status => _status;
  String? get message => _message;

  void _set(ScanStatus s, [String? m]) {
    if (_status == s && _message == m) return;
    _status = s;
    _message = m;
    notifyListeners();
  }

  Future<void> start() async {
    // Nothing here may throw: it runs at launch and on every pull to
    // refresh, and a platform answering oddly should leave a message on
    // screen rather than take the app down.
    try {
      _adapterChanges ??= UniversalBle.availabilityStream.listen((state) {
        _adapter = state;
        _evaluate();
      });
      _location ??= LocationServices.changes().listen((on) {
        _locationOn = on;
        _evaluate();
      });

      _adapter = await UniversalBle.getBluetoothAvailabilityState();
      _locationOn = await LocationServices.isEnabled() ?? true;
      await _evaluate();
    } catch (e) {
      _set(ScanStatus.error, e.toString());
    }
  }

  /// One place that decides what state we are in. Both preconditions are
  /// checked the same way and reported the same way.
  Future<void> _evaluate() async {
    switch (_adapter) {
      case AvailabilityState.unknown:
      case AvailabilityState.unsupported:
        // On Android "unknown" means there is no Bluetooth adapter at all.
        await _stop();
        _set(ScanStatus.unsupported, 'This device has no Bluetooth LE.');
        return;
      case AvailabilityState.resetting:
        // Turning on or off. The next event says which; until then there
        // is nothing to scan with, and nothing worth telling anyone.
        await _stop();
        return;
      case AvailabilityState.poweredOff:
        await _stop();
        _set(ScanStatus.bluetoothOff);
        return;
      case AvailabilityState.unauthorized:
        await _stop();
        _set(ScanStatus.noPermission);
        return;
      case AvailabilityState.poweredOn:
        break;
    }
    if (!_locationOn) {
      await _stop();
      _set(ScanStatus.locationServicesOff);
      return;
    }
    await _beginScan();
  }

  /// Whether starting another scan now would trip Android's limit. If it
  /// would, the start is put off until the oldest one leaves the window.
  bool _mayStart() {
    final now = DateTime.now();
    _starts.removeWhere((t) => now.difference(t) >= startWindow);
    if (_starts.length < maxStartsPerWindow) return true;
    _deferred?.cancel();
    _deferred = Timer(startWindow - now.difference(_starts.first), _evaluate);
    return false;
  }

  Future<void> _stop() async {
    _renew?.cancel();
    _active = false;
    try {
      await UniversalBle.stopScan();
    } catch (_) {
      // Nothing to stop is fine.
    }
  }

  Future<void> _beginScan() async {
    if (_active || !_mayStart()) return;
    // Claimed before the await, not after: start() both subscribes to the
    // availability stream, which replays the current state at once, and
    // evaluates directly, so two calls can arrive while the first is still
    // waiting on the platform. Without this both would start a scan.
    _active = true;
    try {
      _results ??= UniversalBle.scanStream.listen(_onDevice);
      _starts.add(DateTime.now());
      await UniversalBle.startScan(
        platformConfig: PlatformConfig(
          android: AndroidOptions(
            // Measured at the car: without location, Android strips the
            // iBeacon frame the readings live in, silently. This asks for it
            // alongside the Bluetooth permissions. See README.md.
            requestLocationPermission: true,
            scanMode: AndroidScanMode.lowLatency,
            // Every advertisement, not one per sensor: a sensor
            // re-broadcasting the same value is how we know the reading is
            // still current rather than merely remembered.
            callbackType: [AndroidScanCallbackType.allMatches],
          ),
        ),
      );
      _set(ScanStatus.scanning);
      _renew?.cancel();
      _renew = Timer(renewAfter, _renewScan);
    } on UniversalBleException catch (e) {
      _active = false;
      final s = _statusFor(e);
      _set(s, s == ScanStatus.error ? e.message : null);
    } catch (e) {
      _active = false;
      final text = e.toString();
      _set(
        text.toLowerCase().contains('permission')
            ? ScanStatus.noPermission
            : ScanStatus.error,
        text,
      );
    }
  }

  ScanStatus _statusFor(UniversalBleException e) => switch (e.code) {
    UniversalBleErrorCode.bluetoothNotAllowed ||
    UniversalBleErrorCode.bluetoothUnauthorized ||
    UniversalBleErrorCode.accessDenied => ScanStatus.noPermission,
    UniversalBleErrorCode.bluetoothNotEnabled => ScanStatus.bluetoothOff,
    UniversalBleErrorCode.bluetoothNotAvailable ||
    UniversalBleErrorCode.notSupported => ScanStatus.unsupported,
    _ =>
      e.message.toLowerCase().contains('permission')
          ? ScanStatus.noPermission
          : ScanStatus.error,
  };

  /// Restarts a long-running scan without the screen noticing.
  Future<void> _renewScan() async {
    if (!_active) return;
    await _stop();
    await _beginScan();
  }

  void _onDevice(BleDevice device) {
    final reading = decodeTreel({
      for (final m in device.manufacturerDataList) m.companyId: m.payload,
    }, rssi: device.rssi ?? -127);
    if (reading != null) model.ingest(reading);
  }

  /// Re-check everything and start again. Used by pull to refresh, and it is
  /// the only way to recover a scan that began while something was off.
  Future<void> retry() async {
    await _stop();
    _set(ScanStatus.idle);
    await start();
  }

  @visibleForTesting
  void debugSetStatus(ScanStatus status, [String? message]) =>
      _set(status, message);

  @override
  void dispose() {
    _deferred?.cancel();
    _renew?.cancel();
    _location?.cancel();
    _adapterChanges?.cancel();
    _results?.cancel();
    _stop();
    super.dispose();
  }
}
