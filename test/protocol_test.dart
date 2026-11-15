import 'package:flutter_test/flutter_test.dart';
import 'package:tpms_libre/treel/reading.dart';

List<int> hex(String s) => [
  for (var i = 0; i < s.length; i += 2)
    int.parse(s.substring(i, i + 2), radix: 16),
];

void main() {
  test('recognises Tesla sleep advertisements without inventing readings', () {
    final frame = hex('01FE03');
    expect(isTeslaTpmsAdvertisement(frame), isTrue);
    expect(
      decodeTeslaAdvertisement(
        {teslaManufacturerId: frame},
        rssi: -60,
        deviceId: 'tesla-sensor',
      ),
      isNull,
    );
  });

  test('decodes Tesla awake advertisements', () {
    final reading = decodeTeslaAdvertisement(
      {teslaManufacturerId: hex('0102051E0245EA0B')},
      rssi: -60,
      deviceId: 'BC:6A:29:10:20:30',
    );
    expect(reading, isNotNull);
    expect(reading!.sensorId, 'tesla-bc6a29102030');
    expect(reading.psi, 64);
    expect(reading.celsius, 19);
  });

  test('rejects truncated Tesla awake advertisements', () {
    final frame = hex('0102051E02450B');
    expect(isTeslaTpmsAdvertisement(frame), isFalse);
    expect(
      decodeTeslaAdvertisement(
        {teslaManufacturerId: frame},
        rssi: -60,
        deviceId: 'BC:6A:29:10:20:30',
      ),
      isNull,
    );
  });

  test('decodes Tesla TPData GATT indications', () {
    final reading = decodeTeslaTpData(
      hex('1208E20105089E041026'),
    );
    expect(reading, isNotNull);
    expect(reading!.psi, 64);
    expect(reading.celsius, 19);
  });

  test('builds Tesla TPData request candidates', () {
    expect(teslaTpDataRequests.first, [0x08, 0x01]);
    expect(teslaTpDataRequests, hasLength(8));
  });

  test('decodes ZEEPIN TP630 manufacturer payload', () {
    final reading = decodeZeepin({
      0x0001: hex('80EACA108A78E36D0000E60A00005B00'),
    }, rssi: -60);

    expect(reading, isNotNull);
    expect(reading!.sensorId, '80eaca108a78');
    expect(reading.psi, 4);
    expect(reading.celsius, 28);
  });

  test('rejects malformed ZEEPIN manufacturer payload', () {
    expect(decodeZeepin({0x0001: hex('80EACA')}, rssi: -60), isNull);
  });

  test('decodes the BR manufacturer payload using upstream scaling', () {
    final reading = decodeBr(
      {0x1d28: hex('130105A376')},
      rssi: -60,
      deviceId: 'AC:15:85:12:34:56',
    );

    expect(reading, isNotNull);
    expect(reading!.sensorId, 'br-ac1585123456');
    expect(reading.celsius, 19);
    expect(reading.psi, 12);
  });

  test('automatic detection recognises Treel and ZEEPIN signatures', () {
    final treel = decodeSensor({
      0x004c: hex('0215ffffffffffffffffffffffffffffffe0f10a02238a'),
    }, rssi: -60, protocol: SensorProtocol.automatic, deviceId: 'treel');
    expect(treel?.sensorId, 'f10a02');

    final zeepin = decodeSensor({
      0x0001: hex('80EACA108A78E36D0000E60A00005B00'),
    }, rssi: -60, protocol: SensorProtocol.automatic, deviceId: 'zeepin');
    expect(zeepin?.sensorId, '80eaca108a78');
  });

  test('automatic detection recognises BR manufacturer signature', () {
    final br = decodeSensor({
      0x1d28: hex('130105A376'),
    }, rssi: -60, protocol: SensorProtocol.automatic, deviceId: 'AC:15:85:12:34:56');
    expect(br?.sensorId, 'br-ac1585123456');
  });

  test('manual protocol selection does not decode a different format', () {
    expect(
      decodeSensor(
        {0x1d28: hex('130105A376')},
        rssi: -60,
        protocol: SensorProtocol.treel,
        deviceId: 'br',
      ),
      isNull,
    );
  });
  test('decodes TPMSII Type A advertisement', () {
    final frame = List<int>.filled(16, 0);
    frame.setRange(0, 2, [1, 2]);
    frame.setRange(6, 10, [0x78, 0x94, 0x03, 0x00]);
    frame.setRange(10, 14, [0xd0, 0x07, 0x00, 0x00]);
    final reading = decodeTpmsBleA({0x0100: frame}, rssi: -60, deviceId: 'a');
    expect(reading, isNotNull);
    expect(reading!.sensorId, 'tpms-a-010200000000');
    expect(reading.celsius, 20);
    expect(reading.psi, 34);
  });

  test('decodes Michelin Type C pressure frames', () {
    final reading = decodeTpmsBleC({
      0x0828: [0x01, 0x03, 80, 190, 0xfc, 0x08, ...List<int>.filled(8, 0)],
    }, rssi: -60, deviceId: 'michelin');
    expect(reading, isNotNull);
    expect(reading!.celsius, 20);
    expect(reading.psi, 19);
    expect(
      decodeTpmsBleC({0x0828: [0x01, 0x02, 80, 190]}, rssi: -60, deviceId: 'x'),
      isNull,
    );
  });

  test('decodes WODHMIEY Type D and embedded sensor address', () {
    final frame = List<int>.filled(15, 0);
    frame[0] = 168;
    frame[1] = 74;
    frame[2] = 75;
    frame[6] = 0;
    frame.setRange(9, 15, [6, 5, 4, 3, 2, 1]);
    final reading = decodeTpmsBleD({0x00ac: frame}, rssi: -60, deviceId: 'x');
    expect(reading, isNotNull);
    expect(reading!.sensorId, 'itpms-010203040506');
    expect(reading.celsius, 20);
    expect(reading.psi, 34);
  });

  test('decodes FOBO Type E manufacturer and service data', () {
    final manufacturer = decodeTpmsBleE(
      {0x0127: [0, 70, 0x74, 0xf0]},
      const {},
      rssi: -60,
      deviceId: 'fobo',
    );
    expect(manufacturer, isNotNull);
    expect(manufacturer!.celsius, 20);
    expect(manufacturer.psi, 35);

    final service = decodeTpmsBleE(
      const {},
      {'0000012a-0000-1000-8000-00805f9b34fb': [0, 60, 0x74, 0xf0]},
      rssi: -60,
      deviceId: 'fobo',
    );
    expect(service, isNotNull);
    expect(service!.celsius, 20);
  });

  test('decodes Bekubee Type F advertisement', () {
    final reading = decodeTpmsBleF({
      0x0002: [168, 70, 0x01, 0x54, 0, 0, 0, 0, 0],
    }, rssi: -60, deviceId: 'BE:KU:BE:EF',
      services: [tpmsBleTypeFServiceUuid]);
    expect(reading, isNotNull);
    expect(reading!.celsius, 20);
    expect(reading.psi, 35);
  });

  test('decodes AI TPMS Type G and TC.TPMS Type H', () {
    final typeG = decodeTpmsBleG(
      {0x1d00: [20, 0x01, 0xe7]},
      rssi: -60,
      deviceId: 'AI-sensor',
      services: [tpmsBleTypeGServiceUuid],
    );
    expect(typeG, isNotNull);
    expect(typeG!.celsius, 20);
    expect(typeG.psi, 34);

    final typeH = decodeTpmsBleH(
      {0x1d00: [20, 0x01, 0xe6, 1, 2, 3, 4, 5, 6]},
      rssi: -60,
      deviceId: 'tc',
      services: [tpmsBleTypeHServiceUuid],
    );
    expect(typeH, isNotNull);
    expect(typeH!.sensorId, 'tc-tpms-010203040506');
    expect(typeH.psi, 34);
  });

  test('decodes Sysgration and Bekubee TPMS payloads', () {
    final sysgration = List<int>.filled(16, 0);
    sysgration[0] = 0x80;
    sysgration[1] = 0xea;
    sysgration[2] = 0xca;
    sysgration.setRange(3, 6, [1, 2, 3]);
    sysgration.setRange(6, 10, [0x28, 0x92, 0x03, 0x00]);
    sysgration.setRange(10, 14, [0xd0, 0x07, 0x00, 0x00]);
    final located = decodeSysgration(
      {0xffff: sysgration},
      rssi: -60,
      services: [tpmsBleSysgrationServiceUuid],
    );
    expect(located, isNotNull);
    expect(located!.sensorId, 'sysgration-010203');
    expect(located.celsius, 20);
    expect(located.psi, 34);

    final bekubee = decodeBekubeeTpms(
      {0x0002: hex('AF4500A7002D56A8B4')},
      rssi: -60,
      deviceId: 'bekubee',
      name: 'TPMS',
      services: [tpmsBleTypeFServiceUuid],
    );
    expect(bekubee, isNotNull);
    expect(bekubee!.sensorId, 'bekubee-562d00');
    expect(bekubee.celsius, 19);
    expect(bekubee.psi, 10);
  });

  test('recognises the Pecham/SYTPMS Type B company-id variant', () {
    final reading = decodeBr(
      {0x1b10: hex('0F026AB017')},
      rssi: -60,
      deviceId: 'D8:42:00:00:E7:68',
      services: [brServiceUuid],
      name: 'BR',
    );
    expect(reading, isNotNull);
    expect(reading!.celsius, 15);
    expect(reading.psi, 47);
  });
}