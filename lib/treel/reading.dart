/// Decoding for JK Tyre Treel TPMS sensors.  See README.md for the format.
///
/// Each sensor broadcasts a stock iBeacon frame under Apple's manufacturer
/// id, with a constant UUID and its own MAC tail in major/minor -- and the
/// pressure in the low byte of minor, in plain psi:
///
///   02 15 | ff..ff e0 | major | minor | tx
///           constant    MAC[3:5] MAC[5],psi  temperature
///
/// The sensor id lives inside the payload, so nothing here needs the BLE
/// MAC -- which Android hides behind permissions and iOS never exposes.
library;

/// Apple's company identifier.  Treel sensors advertise under it because
/// they masquerade as iBeacons; they are not Apple devices.
const int appleManufacturerId = 0x004C;

/// The UUID every Treel sensor advertises.  Constant across sensors, so it
/// is what separates them from real iBeacons.
const List<int> treelUuid = [
  0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, //
  0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xe0,
];

/// Celsius = txPower - this.  Confirmed 27-41 C against the vendor app and
/// against the ideal gas law over a drive.
const int temperatureOffset = 110;

const int _ibeaconFrameLength = 23;
const int _ibeaconType = 0x02;
const int _ibeaconLength = 0x15;

/// One decoded broadcast from one sensor.
class TreelReading {
  const TreelReading({
    required this.sensorId,
    required this.psi,
    required this.celsius,
    required this.rssi,
    required this.at,
  });

  /// Last three octets of the sensor's MAC, e.g. `f10a04`.  Stable, and the
  /// only identity available on platforms that hide the BLE address.
  final String sensorId;

  /// Gauge pressure.  The sensor reports whole psi; it jitters by +-1
  /// between frames.
  final int psi;

  /// Tyre temperature in degrees Celsius.
  final int celsius;

  final int rssi;
  final DateTime at;

  double get kpa => psi / 0.1450377;
  double get bar => psi / 14.503774;

  Map<String, dynamic> toJson() => {
    'id': sensorId,
    'psi': psi,
    'c': celsius,
    'rssi': rssi,
    't': at.millisecondsSinceEpoch,
  };

  static TreelReading? fromJson(Map<String, dynamic> j) {
    final id = j['id'], psi = j['psi'], c = j['c'], t = j['t'];
    if (id is! String || psi is! int || c is! int || t is! int) return null;
    return TreelReading(
      sensorId: id,
      psi: psi,
      celsius: c,
      rssi: j['rssi'] is int ? j['rssi'] as int : 0,
      at: DateTime.fromMillisecondsSinceEpoch(t),
    );
  }

  @override
  String toString() => 'TreelReading($sensorId, $psi psi, $celsius C)';
}

/// Decode one advertisement.
///
/// [manufacturerData] is keyed by company id, as every BLE stack reports it.
/// Returns null for anything that is not a Treel sensor -- including real
/// iBeacons, which share the manufacturer id but not the UUID.
TreelReading? decodeTreel(
  Map<int, List<int>> manufacturerData, {
  required int rssi,
  DateTime? at,
}) {
  final frame = manufacturerData[appleManufacturerId];
  if (frame == null || frame.length != _ibeaconFrameLength) return null;
  if (frame[0] != _ibeaconType || frame[1] != _ibeaconLength) return null;

  for (var i = 0; i < treelUuid.length; i++) {
    if (frame[2 + i] != treelUuid[i]) return null;
  }

  return TreelReading(
    // major (2 bytes) + minor[0] == MAC[3:6]
    sensorId: frame
        .sublist(18, 21)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(),
    psi: frame[21],
    celsius: frame[22] - temperatureOffset,
    rssi: rssi,
    at: at ?? DateTime.now(),
  );
}
