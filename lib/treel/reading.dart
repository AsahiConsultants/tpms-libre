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

/// ZEEPIN / TP630 manufacturer company identifier.
const int zeepinManufacturerId = 0x0001;

/// BR TPMS advertises the 16-bit service UUID 0x27a5.
const String brServiceUuid = '000027a5-0000-1000-8000-00805f9b34fb';

/// Sensor protocol selection. Automatic uses advertisement signatures.
enum SensorProtocol {
  automatic('Automatic', 'automatic'),
  treel('JK Tyre Treel', 'treel'),
  zeepin('ZEEPIN / TP630', 'zeepin'),
  br('BR / SYTPMS / Pecham / Bekubee KY', 'br'),
  tpmsBleA('TPMSII Type A', 'tpms_ble_a'),
  tpmsBleC('Michelin TMS Type C', 'tpms_ble_c'),
  tpmsBleD('WODHMIEY / ITPMS K Type D', 'tpms_ble_d'),
  tpmsBleE('Salutica FOBO Type E', 'tpms_ble_e'),
  tpmsBleF('Bekubee HRTPMS Type F', 'tpms_ble_f'),
  tpmsBleG('Ai TPMS AI-8000 Type G', 'tpms_ble_g'),
  tpmsBleH('TC.TPMS Type H', 'tpms_ble_h'),
  sysgration('Sysgration', 'sysgration'),
  bekubeeTpms('Bekubee TPMS', 'bekubee_tpms'),
  tesla('Tesla / Autel BLE', 'tesla');

  const SensorProtocol(this.label, this.id);
  final String label;
  final String id;
}

/// Decode the ZEEPIN / TP630 manufacturer payload.
///
/// universal_ble separates the two-byte company id from this 16-byte value.
/// Integer fields are little-endian, as in ra6070/BLE-TPMS.
TreelReading? decodeZeepin(
  Map<int, List<int>> manufacturerData, {
  required int rssi,
  DateTime? at,
}) {
  final frame = manufacturerData[zeepinManufacturerId];
  if (frame == null || frame.length != 16) return null;
  if (frame[0] < 0x80 || frame[0] > 0x8f) return null;
  if (frame[1] != 0xea || frame[2] != 0xca) return null;

  final pressureMilliKpa =
      frame[6] | (frame[7] << 8) | (frame[8] << 16) | (frame[9] << 24);
  final temperatureCenti =
      frame[10] | (frame[11] << 8) | (frame[12] << 16) | (frame[13] << 24);
  final pressureKpa = pressureMilliKpa / 1000.0;
  final psi = (pressureKpa * 0.1450377377).round();
  final celsius = (temperatureCenti / 100.0).round();
  if (psi < 0 || psi > 200 || celsius < -50 || celsius > 150) return null;

  return TreelReading(
    sensorId: frame
        .sublist(0, 6)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(),
    psi: psi,
    celsius: celsius,
    rssi: rssi,
    at: at ?? DateTime.now(),
  );
}

/// Decode the BR advertisement documented by andi38/TPMS.
///
/// The Bluetooth company id is 0x1d28 and the manufacturer payload is five
/// bytes. The upstream Python example reads temperature from byte 0 and
/// pressure from bytes 1-2. The final two bytes are not validated because the
/// repository does not document their checksum algorithm.
TreelReading? decodeBr(
  Map<int, List<int>> manufacturerData, {
  required int rssi,
  required String deviceId,
  List<String> services = const [],
  Map<String, List<int>> serviceData = const {},
  String? name,
  DateTime? at,
}) {
  List<int>? frame;
  for (final entry in manufacturerData.entries) {
    if (entry.value.length == 5 &&
        (entry.key == 0x1d28 ||
            services.any((uuid) => _tpmsUuidMatches(uuid, brServiceUuid)) ||
            name == 'BR' ||
            name == 'KY')) {
      frame = entry.value;
      break;
    }
  }
  if (frame == null) return null;

  final celsius = frame[0];
  final pressureRaw = (frame[1] << 8) | frame[2];
  final pressureBar = (pressureRaw - 145) / 145.0;
  final psi = (pressureBar * 14.503774).round();
  if (psi < 0 || psi > 200 || celsius > 150) return null;

  final stableId = deviceId.toLowerCase().replaceAll(
    RegExp(r'[^a-z0-9]'),
    '',
  );
  final simulatorId = _tpmsServiceData(serviceData, tpmsBleTypeBIdServiceUuid);
  final sensorSuffix = simulatorId != null && simulatorId.length >= 3
      ? _tpmsHex(simulatorId.take(3))
      : stableId;
  return TreelReading(
    sensorId: 'br-$sensorSuffix',
    psi: psi,
    celsius: celsius,
    rssi: rssi,
    at: at ?? DateTime.now(),
  );
}



const String tpmsBleTypeGServiceUuid =
    '0000a829-0000-1000-8000-00805f9b34fb';
const String tpmsBleBekubeeServiceUuid =
    '0000a82a-0000-1000-8000-00805f9b34fb';
const String tpmsBleTypeHServiceUuid =
    '0000a828-0000-1000-8000-00805f9b34fb';
const String tpmsBleTypeFServiceUuid =
    '0000a827-0000-1000-8000-00805f9b34fb';
const String tpmsBleSysgrationServiceUuid =
    '0000fbb0-0000-1000-8000-00805f9b34fb';
const String tpmsBleFoboServiceUuid =
    '0000012a-0000-1000-8000-00805f9b34fb';
const String tpmsBleTypeBIdServiceUuid = '0000a82b-0000-1000-8000-00805f9b34fb';
const String tpmsBleTypeCIdServiceUuid = '0000a82c-0000-1000-8000-00805f9b34fb';
const String tpmsBleTypeEIdServiceUuid = '0000a82e-0000-1000-8000-00805f9b34fb';
const String tpmsBleTypeFIdServiceUuid = '0000a82f-0000-1000-8000-00805f9b34fb';

String _tpmsDeviceId(String deviceId) =>
    deviceId.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

String _tpmsHex(Iterable<int> bytes) => bytes
    .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
    .join();

bool _tpmsUuidMatches(String candidate, String expected) {
  final value = candidate.toLowerCase().replaceFirst(RegExp(r'^0x'), '');
  if (value == expected) return true;
  if (value.length == 4) return value == expected.substring(4, 8);
  if (value.length == 8) return value == expected.substring(0, 8);
  return false;
}

List<int>? _tpmsServiceData(
  Map<String, List<int>> serviceData,
  String expectedUuid,
) {
  for (final entry in serviceData.entries) {
    if (_tpmsUuidMatches(entry.key, expectedUuid)) return entry.value;
  }
  return null;
}

int _signedInt32Le(List<int> bytes, int offset) {
  final value = bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);
  return value >= 0x80000000 ? value - 0x100000000 : value;
}

TreelReading? _tpmsReading({
  required String sensorId,
  required double pressureBar,
  required double celsius,
  required int rssi,
  DateTime? at,
}) {
  final psi = (pressureBar * 14.503774).round();
  final temperature = celsius.round();
  if (!pressureBar.isFinite || pressureBar < 0 || psi > 200) return null;
  if (!celsius.isFinite || temperature < -50 || temperature > 150) return null;
  return TreelReading(
    sensorId: sensorId,
    psi: psi,
    celsius: temperature,
    rssi: rssi,
    at: at ?? DateTime.now(),
  );
}

TreelReading? decodeTpmsBleA(
  Map<int, List<int>> manufacturerData, {
  required int rssi,
  required String deviceId,
  DateTime? at,
}) {
  final frame = manufacturerData[0x0100];
  if (frame == null || frame.length != 16) return null;
  final pressureBar = _signedInt32Le(frame, 6) / 100000.0;
  final celsius = _signedInt32Le(frame, 10) / 100.0;
  final sensorId = _tpmsHex(frame.sublist(0, 6));
  return _tpmsReading(
    sensorId: 'tpms-a-$sensorId',
    pressureBar: pressureBar,
    celsius: celsius,
    rssi: rssi,
    at: at,
  );
}

TreelReading? decodeTpmsBleC(
  Map<int, List<int>> manufacturerData, {
  required int rssi,
  required String deviceId,
  Map<String, List<int>> serviceData = const {},
  DateTime? at,
}) {
  final frame = manufacturerData[0x0828];
  if (frame == null || frame.length < 4 || frame[0] != 0x01) return null;
  final frameType = frame[1];
  int? rawPressure;
  int rawTemperature;
  if (frameType == 0x02 || frameType == 0x06) {
    rawTemperature = frame[2] - 60;
  } else if (frameType == 0x03 || frameType == 0x04 || frameType == 0x0c) {
    if (frame.length < 6) return null;
    rawTemperature = frame[2] - 60;
    rawPressure = frame[4] | (frame[5] << 8);
  } else if (frameType == 0x05) {
    if (frame.length < 14) return null;
    rawTemperature = frame[2] - 60;
    rawPressure = frame[12] | (frame[13] << 8);
  } else {
    return null;
  }
  if (rawPressure == null) return null;
  final pressureBar = (rawPressure / 1000.0 - 1.0).clamp(0.0, 20.0).toDouble();
  final sensorSuffix = _tpmsServiceData(serviceData, tpmsBleTypeCIdServiceUuid);
  final sensorId = sensorSuffix != null && sensorSuffix.length >= 3
      ? _tpmsHex(sensorSuffix.take(3))
      : _tpmsDeviceId(deviceId);
  return _tpmsReading(
    sensorId: 'michelin-$sensorId',
    pressureBar: pressureBar,
    celsius: rawTemperature.toDouble(),
    rssi: rssi,
    at: at,
  );
}

TreelReading? decodeTpmsBleD(
  Map<int, List<int>> manufacturerData, {
  required int rssi,
  required String deviceId,
  DateTime? at,
}) {
  final frame = manufacturerData[0x00ac];
  if (frame == null || frame.length < 7) return null;
  final temperature = frame[2] - 55;
  double pressureBar;
  if (frame[6] == 0 || frame[6] == 1) {
    final rawPressure = frame[1] + (frame[6] == 1 ? 256 : 0);
    pressureBar = rawPressure * 0.03144;
  } else if (frame.length >= 8) {
    pressureBar = ((frame[7] - 2) / 103.0).clamp(0.0, 20.0).toDouble();
  } else {
    return null;
  }
  final sensorId = frame.length == 15
      ? _tpmsHex(frame.sublist(9, 15).reversed)
      : _tpmsDeviceId(deviceId);
  return _tpmsReading(
    sensorId: 'itpms-$sensorId',
    pressureBar: pressureBar,
    celsius: temperature.toDouble(),
    rssi: rssi,
    at: at,
  );
}

TreelReading? decodeTpmsBleE(
  Map<int, List<int>> manufacturerData,
  Map<String, List<int>> serviceData, {
  required int rssi,
  required String deviceId,
  DateTime? at,
}) {
  List<int>? frame;
  var temperatureOffset = 50;
  for (final entry in serviceData.entries) {
    if (_tpmsUuidMatches(entry.key, tpmsBleFoboServiceUuid)) {
      frame = entry.value;
      temperatureOffset = 40;
      break;
    }
  }
  frame ??= manufacturerData[0x0127];
  if (frame == null || frame.length < 4) return null;
  final payload = frame.sublist(frame.length - 4);
  final temperature = (payload[1] & 0x7f) - temperatureOffset;
  final rawValue = (payload[2] << 8) | payload[3];
  final pressureKpa = rawValue & 0x03ff;
  final sensorSuffix = _tpmsServiceData(serviceData, tpmsBleTypeEIdServiceUuid);
  final sensorId = sensorSuffix != null && sensorSuffix.length >= 3
      ? _tpmsHex(sensorSuffix.take(3))
      : _tpmsDeviceId(deviceId);
  return _tpmsReading(
    sensorId: 'fobo-$sensorId',
    pressureBar: pressureKpa / 100.0,
    celsius: temperature.toDouble(),
    rssi: rssi,
    at: at,
  );
}

TreelReading? decodeTpmsBleF(
  Map<int, List<int>> manufacturerData, {
  required int rssi,
  required String deviceId,
  List<String> services = const [],
  Map<String, List<int>> serviceData = const {},
  DateTime? at,
}) {
  if (!services.any((uuid) => _tpmsUuidMatches(uuid, tpmsBleTypeFServiceUuid))) {
    return null;
  }
  List<int>? frame;
  for (final entry in manufacturerData.entries) {
    if (entry.value.length == 9) {
      frame = entry.value;
      break;
    }
  }
  if (frame == null) return null;
  final temperature = frame[1] - 50;
  final rawPressure = (frame[2] << 8) | frame[3];
  final sensorSuffix = _tpmsServiceData(serviceData, tpmsBleTypeFIdServiceUuid);
  final sensorId = sensorSuffix != null && sensorSuffix.length >= 3
      ? _tpmsHex(sensorSuffix.take(3))
      : _tpmsDeviceId(deviceId);
  return _tpmsReading(
    sensorId: 'hrtpms-$sensorId',
    pressureBar: (rawPressure - 100) * 0.01,
    celsius: temperature.toDouble(),
    rssi: rssi,
    at: at,
  );
}

TreelReading? decodeTpmsBleG(
  Map<int, List<int>> manufacturerData, {
  required int rssi,
  required String deviceId,
  String? name,
  List<String> services = const [],
  Map<String, List<int>> serviceData = const {},
  DateTime? at,
}) {
  final serviceMatch = services.any(
    (uuid) => _tpmsUuidMatches(uuid, tpmsBleTypeGServiceUuid),
  ) || _tpmsServiceData(serviceData, tpmsBleTypeGServiceUuid) != null;
  final addressMatch = deviceId.toUpperCase().startsWith('12:30:AF');
  if (!serviceMatch && !addressMatch && !(name?.startsWith('AI-') ?? false)) {
    return null;
  }
  for (final entry in manufacturerData.entries) {
    if (entry.value.length != 3) continue;
    final battery = (entry.key >> 8) & 0xff;
    if (battery < 15 || battery > 43) continue;
    final rawAbsolutePsi = (entry.value[1] << 8) | entry.value[2];
    final pressureBar = ((rawAbsolutePsi / 10.0) - 14.696) * 0.0689476;
    final sensorSuffix = _tpmsServiceData(serviceData, tpmsBleTypeGServiceUuid);
    final sensorId = sensorSuffix != null && sensorSuffix.length >= 3
        ? _tpmsHex(sensorSuffix.take(3))
        : _tpmsDeviceId(deviceId);
    return _tpmsReading(
      sensorId: 'ai-tpms-$sensorId',
      pressureBar: pressureBar.clamp(0.0, 20.0).toDouble(),
      celsius: entry.value[0].toDouble(),
      rssi: rssi,
      at: at,
    );
  }
  return null;
}

TreelReading? decodeTpmsBleH(
  Map<int, List<int>> manufacturerData, {
  required int rssi,
  required String deviceId,
  List<String> services = const [],
  DateTime? at,
}) {
  if (!services.any(
    (uuid) => _tpmsUuidMatches(uuid, tpmsBleTypeHServiceUuid),
  )) {
    return null;
  }
  for (final entry in manufacturerData.entries) {
    if (entry.value.length != 9) continue;
    final frame = [entry.key & 0xff, (entry.key >> 8) & 0xff, ...entry.value];
    if (frame.length != 11) continue;
    final rawAbsolutePsi = (frame[3] << 8) | frame[4];
    final pressureBar = ((rawAbsolutePsi / 10.0) - 14.6) * 0.0689476;
    return _tpmsReading(
      sensorId: 'tc-tpms-${_tpmsHex(frame.sublist(5, 11))}',
      pressureBar: pressureBar.clamp(0.0, 20.0).toDouble(),
      celsius: frame[2].toDouble(),
      rssi: rssi,
      at: at,
    );
  }
  return null;
}

TreelReading? decodeSysgration(
  Map<int, List<int>> manufacturerData, {
  required int rssi,
  List<String> services = const [],
  DateTime? at,
}) {
  if (!services.any(
    (uuid) => _tpmsUuidMatches(uuid, tpmsBleSysgrationServiceUuid),
  )) {
    return null;
  }
  for (final frame in manufacturerData.values) {
    if (frame.length != 16 || frame[1] != 0xea || frame[2] != 0xca) {
      continue;
    }
    final location = frame[0];
    if (location < 0x80 || location > 0x83) continue;
    final pressureKpa = _signedInt32Le(frame, 6) / 1000.0;
    final celsius = _signedInt32Le(frame, 10) / 100.0;
    return _tpmsReading(
      sensorId: 'sysgration-${_tpmsHex(frame.sublist(3, 6))}',
      pressureBar: pressureKpa / 100.0,
      celsius: celsius,
      rssi: rssi,
      at: at,
    );
  }
  return null;
}

TreelReading? decodeBekubeeTpms(
  Map<int, List<int>> manufacturerData, {
  required int rssi,
  required String deviceId,
  List<String> services = const [],
  String? name,
  DateTime? at,
}) {
  final hasBekubeeMarker = services.any(
    (uuid) => _tpmsUuidMatches(uuid, tpmsBleBekubeeServiceUuid),
  );
  if (!hasBekubeeMarker && name?.trim() != 'TPMS') return null;
  if (!services.any(
    (uuid) => _tpmsUuidMatches(uuid, tpmsBleTypeFServiceUuid),
  )) {
    return null;
  }
  for (final frame in manufacturerData.values) {
    if (frame.length < 9) continue;
    final pressureKpa = ((frame[2] << 8) | frame[3]) - 100;
    final temperature = frame[1] - 50;
    final sensorId = (frame[4] | (frame[5] << 8) | (frame[6] << 16))
        .toRadixString(16)
        .padLeft(6, '0');
    return _tpmsReading(
      sensorId: 'bekubee-$sensorId',
      pressureBar: pressureKpa / 100.0,
      celsius: temperature.toDouble(),
      rssi: rssi,
      at: at,
    );
  }
  return null;
}


/// Tesla's Bluetooth SIG company identifier.
const int teslaManufacturerId = 0x022B;

class TeslaTpmsPayload {
  const TeslaTpmsPayload({required this.psi, required this.celsius});

  final int psi;
  final int celsius;
}

bool isTeslaTpmsAdvertisement(List<int>? frame) {
  if (frame == null || frame.length < 3) return false;
  if (frame[2] < 0x05) return frame.length <= 16;
  if (frame.length < 8) return false;
  final batteryMv = frame[6] | (frame[7] << 8);
  return batteryMv >= 1500 && batteryMv <= 4300;
}

TreelReading? decodeTeslaAdvertisement(
  Map<int, List<int>> manufacturerData, {
  required int rssi,
  required String deviceId,
  DateTime? at,
}) {
  final frame = manufacturerData[teslaManufacturerId];
  if (!isTeslaTpmsAdvertisement(frame) || frame![2] < 0x05) return null;
  final rawPressureKpa = frame[3] | (frame[4] << 8);
  final psi = ((rawPressureKpa - 100) * 0.1450377377).round();
  final celsius = frame[5] - 50;
  if (psi < 0 || psi > 200 || celsius < -50 || celsius > 150) return null;
  final id = deviceId.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  return TreelReading(
    sensorId: 'tesla-$id',
    psi: psi,
    celsius: celsius,
    rssi: rssi,
    at: at ?? DateTime.now(),
  );
}

int? _readTeslaVarint(List<int> bytes, int start) {
  var shift = 0;
  var value = 0;
  var index = start;
  while (index < bytes.length && shift <= 63) {
    final byte = bytes[index++];
    value |= (byte & 0x7f) << shift;
    if ((byte & 0x80) == 0) return value;
    shift += 7;
  }
  return null;
}

({Map<int, int> values, List<List<int>> nested}) _teslaProtoFields(
  List<int> bytes,
) {
  final values = <int, int>{};
  final nested = <List<int>>[];
  var index = 0;
  while (index < bytes.length) {
    final tag = _readTeslaVarint(bytes, index);
    if (tag == null || tag == 0) break;
    final tagBytes = _teslaVarintLength(tag);
    index += tagBytes;
    final field = tag >> 3;
    switch (tag & 7) {
      case 0:
        final value = _readTeslaVarint(bytes, index);
        if (value == null) return (values: values, nested: nested);
        values[field] = value;
        index += _teslaVarintLength(value);
      case 1:
        if (index + 8 > bytes.length) return (values: values, nested: nested);
        index += 8;
      case 2:
        final length = _readTeslaVarint(bytes, index);
        if (length == null) return (values: values, nested: nested);
        index += _teslaVarintLength(length);
        if (length < 0 || index + length > bytes.length) {
          return (values: values, nested: nested);
        }
        nested.add(bytes.sublist(index, index + length));
        index += length;
      case 5:
        if (index + 4 > bytes.length) return (values: values, nested: nested);
        index += 4;
      default:
        return (values: values, nested: nested);
    }
  }
  return (values: values, nested: nested);
}

int _teslaVarintLength(int value) {
  var length = 1;
  while (value >= 0x80) {
    value >>= 7;
    length++;
  }
  return length;
}

({int pressure, int? temperature})? _findTeslaTpData(
  List<int> bytes, [
  int depth = 0,
]) {
  if (depth > 5) return null;
  final fields = _teslaProtoFields(bytes);
  if (fields.values.containsKey(1)) {
    return (pressure: fields.values[1]!, temperature: fields.values[2]);
  }
  for (final nested in fields.nested) {
    final result = _findTeslaTpData(nested, depth + 1);
    if (result != null) return result;
  }
  return null;
}

TeslaTpmsPayload? decodeTeslaTpData(List<int> payload) {
  final fields = _findTeslaTpData(payload);
  if (fields == null || fields.pressure < 0 || fields.pressure > 100000) {
    return null;
  }
  final pressurePsi =
      ((fields.pressure - 101.325) * 0.1450377377).round();
  final temperature = fields.temperature == null
      ? null
      : ((fields.temperature! >> 1) ^ -(fields.temperature! & 1));
  if (pressurePsi < 0 || pressurePsi > 200) return null;
  if (temperature != null && (temperature < -50 || temperature > 150)) {
    return null;
  }
  if (temperature == null) return null;
  return TeslaTpmsPayload(psi: pressurePsi, celsius: temperature);
}

List<List<int>> get teslaTpDataRequests {
  const inner = [0x08, 0x01];
  final frames = <List<int>>[
    inner,
    [0x0a, 0x02, ...inner],
    [0x12, 0x02, ...inner],
    [0x1a, 0x02, ...inner],
  ];
  return [
    ...frames,
    for (final frame in frames) [0x00, frame.length, ...frame],
  ];
}

/// Decode an advertisement using the selected or automatically detected
/// sensor protocol.
TreelReading? decodeSensor(
  Map<int, List<int>> manufacturerData, {
  required int rssi,
  required SensorProtocol protocol,
  required String deviceId,
  String? name,
  List<String> services = const [],
  Map<String, List<int>> serviceData = const {},
  DateTime? at,
}) {
  TreelReading? decode(SensorProtocol selected) {
    switch (selected) {
      case SensorProtocol.treel:
        return decodeTreel(manufacturerData, rssi: rssi, at: at);
      case SensorProtocol.zeepin:
        return decodeZeepin(manufacturerData, rssi: rssi, at: at);
      case SensorProtocol.tesla:
        return decodeTeslaAdvertisement(manufacturerData, rssi: rssi, deviceId: deviceId, at: at);
      case SensorProtocol.br:
        return decodeBr(manufacturerData, rssi: rssi, deviceId: deviceId, services: services, serviceData: serviceData, name: name, at: at);
      case SensorProtocol.tpmsBleA:
        return decodeTpmsBleA(manufacturerData, rssi: rssi, deviceId: deviceId, at: at);
      case SensorProtocol.tpmsBleC:
        return decodeTpmsBleC(manufacturerData, rssi: rssi, deviceId: deviceId, serviceData: serviceData, at: at);
      case SensorProtocol.tpmsBleD:
        return decodeTpmsBleD(manufacturerData, rssi: rssi, deviceId: deviceId, at: at);
      case SensorProtocol.tpmsBleE:
        return decodeTpmsBleE(manufacturerData, serviceData, rssi: rssi, deviceId: deviceId, at: at);
      case SensorProtocol.tpmsBleF:
        return decodeTpmsBleF(manufacturerData, rssi: rssi, deviceId: deviceId, services: services, serviceData: serviceData, at: at);
      case SensorProtocol.tpmsBleG:
        return decodeTpmsBleG(manufacturerData, rssi: rssi, deviceId: deviceId, name: name, services: services, serviceData: serviceData, at: at);
      case SensorProtocol.tpmsBleH:
        return decodeTpmsBleH(manufacturerData, rssi: rssi, deviceId: deviceId, services: services, at: at);
      case SensorProtocol.sysgration:
        return decodeSysgration(manufacturerData, rssi: rssi, services: services, at: at);
      case SensorProtocol.bekubeeTpms:
        return decodeBekubeeTpms(manufacturerData, rssi: rssi, deviceId: deviceId, services: services, name: name, at: at);
      case SensorProtocol.automatic:
        return null;
    }
  }

  if (protocol != SensorProtocol.automatic) return decode(protocol);

  final candidates = <TreelReading?>[
    decodeTeslaAdvertisement(manufacturerData, rssi: rssi, deviceId: deviceId, at: at),
    decodeTreel(manufacturerData, rssi: rssi, at: at),
    decodeZeepin(manufacturerData, rssi: rssi, at: at),
    decodeTpmsBleA(manufacturerData, rssi: rssi, deviceId: deviceId, at: at),
    decodeTpmsBleC(manufacturerData, rssi: rssi, deviceId: deviceId, serviceData: serviceData, at: at),
    decodeTpmsBleD(manufacturerData, rssi: rssi, deviceId: deviceId, at: at),
    decodeTpmsBleE(manufacturerData, serviceData, rssi: rssi, deviceId: deviceId, at: at),
    decodeTpmsBleH(manufacturerData, rssi: rssi, deviceId: deviceId, services: services, at: at),
    decodeTpmsBleG(manufacturerData, rssi: rssi, deviceId: deviceId, name: name, services: services, serviceData: serviceData, at: at),
    decodeSysgration(manufacturerData, rssi: rssi, services: services, at: at),
    decodeBekubeeTpms(manufacturerData, rssi: rssi, deviceId: deviceId, services: services, name: name, at: at),
    decodeTpmsBleF(manufacturerData, rssi: rssi, deviceId: deviceId, services: services, serviceData: serviceData, at: at),
  ];
  for (final reading in candidates) {
    if (reading != null) return reading;
  }
  final hasBrService = services.any(
    (uuid) => _tpmsUuidMatches(uuid, brServiceUuid),
  );
  if (hasBrService || manufacturerData[0x1d28]?.length == 5 || name == 'BR' || name == 'KY') {
    return decodeBr(
      manufacturerData,
      rssi: rssi,
      deviceId: deviceId,
      services: services,
      serviceData: serviceData,
      name: name,
      at: at,
    );
  }
  return null;
}
