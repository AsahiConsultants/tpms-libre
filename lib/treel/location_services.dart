import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Whether Android's location services are switched on.
///
/// Needed because Android hides BLE advertisements entirely when they are
/// off, and does so silently: the scan starts, reports success, and never
/// delivers anything. The Bluetooth plugin cannot tell us, so this asks
/// LocationManager directly. Querying it requires no permission.
class LocationServices {
  static const _method = MethodChannel('tpmslibre/location');
  static const _changes = EventChannel('tpmslibre/location/changes');

  /// Null when the question does not apply — anywhere but Android — or when
  /// the platform did not answer. Callers should treat null as "unknown"
  /// and fall back to inferring from silence, not as "off".
  static Future<bool?> isEnabled() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _method.invokeMethod<bool>('isEnabled');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Emits on subscribe and again whenever the setting is toggled, so the
  /// app reacts the moment location comes back rather than a minute later.
  static Stream<bool> changes() {
    if (!Platform.isAndroid) return const Stream<bool>.empty();
    return _changes
        .receiveBroadcastStream()
        .map((e) => e == true)
        .handleError((_) {});
  }
}
