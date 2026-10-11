import 'package:flutter_test/flutter_test.dart';
import 'package:tpms_libre/treel/model.dart';
import 'package:tpms_libre/treel/reading.dart';
import 'package:shared_preferences/shared_preferences.dart';

TreelReading reading(String id, int psi) => TreelReading(
  sensorId: id,
  psi: psi,
  celsius: 25,
  rssi: -70,
  at: DateTime.now(),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('layouts', () {
    test('a bike has two wheels and is drawn from the side', () {
      expect(WheelLayout.motorcycle.positions, [
        TyrePosition.front,
        TyrePosition.rear,
      ]);
      expect(WheelLayout.motorcycle.projection, Projection.sideOn);
      expect(WheelLayout.motorcycle.hasSpare, isFalse);
    });

    test('a car is drawn from above, with or without a spare', () {
      expect(WheelLayout.car.positions, hasLength(4));
      expect(WheelLayout.carWithSpare.positions, hasLength(5));
      expect(WheelLayout.car.projection, Projection.topDown);
      expect(WheelLayout.carWithSpare.hasSpare, isTrue);
    });

    test('shapes describe their wheels, not how we draw them', () {
      // The projection is an implementation detail. Telling someone adding
      // a vehicle that it is "drawn from above" answers a question nobody
      // asked.
      for (final l in WheelLayout.values) {
        expect(l.wheels.toLowerCase(), isNot(contains('drawn')));
        expect(l.wheels.toLowerCase(), isNot(contains('above')));
        expect(l.wheels.toLowerCase(), isNot(contains('side')));
      }
      expect(WheelLayout.motorcycle.wheels, 'Front and rear');
      expect(WheelLayout.carWithSpare.wheels, 'Four wheels and a spare');
    });

    test("a bike's front wheel wants the front pressure", () {
      const spec = PressureSpec(front: 36, rear: 42, spare: 30);
      expect(spec.targetFor(TyrePosition.front), 36);
      expect(spec.targetFor(TyrePosition.rear), 42);
      // Same figure as a car's front left, because it is the same axle.
      expect(spec.targetFor(TyrePosition.frontLeft), 36);
    });
  });

  group('Vehicle', () {
    const car = Vehicle(
      id: 'a',
      name: 'Test vehicle',
      layout: WheelLayout.carWithSpare,
      assignments: {
        'f10a01': TyrePosition.frontLeft,
        'f10a05': TyrePosition.spare,
      },
    );

    test('changing shape drops wheels that no longer exist', () {
      final noSpare = car.withLayout(WheelLayout.car);
      expect(noSpare.positionOf('f10a01'), TyrePosition.frontLeft);
      expect(
        noSpare.positionOf('f10a05'),
        isNull,
        reason: 'a car without a spare cannot have a sensor on one',
      );
    });

    test('becoming a motorcycle keeps nothing, since no corner survives', () {
      expect(car.withLayout(WheelLayout.motorcycle).assignments, isEmpty);
    });

    test('survives a round trip', () {
      final back = Vehicle.fromJson(car.toJson());
      expect(back.id, 'a');
      expect(back.name, 'Test vehicle');
      expect(back.layout, WheelLayout.carWithSpare);
      expect(back.positionOf('f10a05'), TyrePosition.spare);
    });

    test('ignores a position written by a newer version', () {
      final json = car.toJson();
      (json['assignments'] as Map)['zzz'] = 'sidecar';
      expect(Vehicle.fromJson(json).positionOf('zzz'), isNull);
      expect(
        Vehicle.fromJson(json).positionOf('f10a01'),
        TyrePosition.frontLeft,
      );
    });
  });

  group('the garage', () {
    late TreelModel model;
    setUp(() {
      model = TreelModel();
      addTearDown(model.dispose);
    });

    test('a first run always has a vehicle to show', () async {
      await model.load();
      expect(model.vehicles, hasLength(1));
      expect(model.positions, WheelLayout.carWithSpare.positions);
    });

    test('adding one selects it', () async {
      await model.load();
      await model.addVehicle('Touring bike', WheelLayout.motorcycle);
      expect(model.vehicles, hasLength(2));
      expect(model.vehicle.name, 'Touring bike');
      expect(model.positions, hasLength(2));
    });

    test('a sensor on one vehicle is not spare capacity on another', () async {
      await model.load();
      final car = model.vehicle.id;
      model.ingest(reading('f10a01', 33));
      await model.assign('f10a01', TyrePosition.frontLeft);

      await model.addVehicle('Katana', WheelLayout.motorcycle);
      expect(
        model.unassigned.map((r) => r.sensorId),
        isNot(contains('f10a01')),
        reason: 'it is bolted to the car',
      );

      await model.selectVehicle(car);
      expect(model.stateOf(TyrePosition.frontLeft).sensorId, 'f10a01');
    });

    test('one sensor cannot be on two wheels at once', () async {
      await model.load();
      await model.assign('x', TyrePosition.frontLeft);
      await model.assign('x', TyrePosition.rearRight);
      expect(model.stateOf(TyrePosition.frontLeft).sensorId, isNull);
      expect(model.stateOf(TyrePosition.rearRight).sensorId, 'x');
    });

    test(
      'the footer counts this vehicle, not every sensor in the house',
      () async {
        await model.load();
        for (final (i, p) in model.positions.indexed) {
          model.ingest(reading('car$i', 32));
          await model.assign('car$i', p);
        }
        expect(model.knownCount, 5);

        await model.addVehicle('Katana', WheelLayout.motorcycle);
        expect(
          model.knownCount,
          0,
          reason: 'a two-wheeler does not have five wheels to report on',
        );

        model.ingest(reading('bike0', 36));
        await model.assign('bike0', TyrePosition.front);
        expect(model.knownCount, 1);
        expect(model.liveCount, 1);
      },
    );

    test('removing the last vehicle leaves one behind', () async {
      await model.load();
      await model.removeVehicle(model.vehicle.id);
      expect(
        model.vehicles,
        hasLength(1),
        reason: 'an app with no vehicle has nothing to say',
      );
    });

    test('vehicles survive a restart, with the same one selected', () async {
      await model.load();
      await model.addVehicle('Katana', WheelLayout.motorcycle);
      await model.assign('sensor1', TyrePosition.front);

      final revived = TreelModel();
      addTearDown(revived.dispose);
      await revived.load();

      expect(revived.vehicles, hasLength(2));
      expect(revived.vehicle.name, 'Katana');
      expect(revived.stateOf(TyrePosition.front).sensorId, 'sensor1');
    });
  });

  group('artwork', () {
    test('with no drawings shipped, every shape is offered just generic', () {
      for (final layout in WheelLayout.values) {
        expect(VehicleArt.forLayout(layout), [VehicleArt.generic]);
        expect(VehicleArt.generic.fits(layout), isTrue);
      }
    });

    test('no name suggests a drawing that does not exist', () {
      for (final name in ['Hatchback', 'Sport tourer', 'The car', '']) {
        expect(VehicleArt.suggest(name), VehicleArt.generic, reason: name);
      }
    });

    test('any drawing that claims an asset gives usable geometry', () {
      // Vacuous until the first drawing is added, and then it is the check
      // that its numbers were filled in.
      for (final art in VehicleArt.values.where((a) => a.hasAsset)) {
        expect(art.aspect, greaterThan(0), reason: art.name);
        if (!art.wheelsAreVisible) continue;
        expect(art.rearWheelX, inExclusiveRange(0, 1), reason: art.name);
        expect(art.frontWheelX, inExclusiveRange(0, 1), reason: art.name);
        expect(
          art.rearWheelX,
          lessThan(art.frontWheelX),
          reason: '${art.name} is drawn facing right',
        );
      }
    });

    test('a deliberate choice survives being saved and read back', () {
      const v = Vehicle(id: 'x', name: 'Car', artChosen: true);
      final back = Vehicle.fromJson(v.toJson());
      expect(back.art, VehicleArt.generic);
      expect(back.artChosen, isTrue);
    });

    test('a guess is never mistaken for a choice on the way back', () {
      // A drawing that merely followed the name must stay revisable, so a
      // vehicle picks up a drawing as soon as one exists for it.
      const v = Vehicle(id: 'x', name: 'Car');
      expect(Vehicle.fromJson(v.toJson()).artChosen, isFalse);
    });

    test('a drawing this build does not have reads back as generic', () {
      // Written by a build with a drawing this one lacks, or by a future
      // one. Must degrade, not crash.
      for (final name in ['someFutureDrawing', 'notADrawing', null]) {
        final j = {
          'id': 'x',
          'name': 'Bike',
          'layout': 'motorcycle',
          'art': name,
          'artChosen': true,
        };
        expect(Vehicle.fromJson(j).art, VehicleArt.generic, reason: '$name');
      }
    });
  });
}
