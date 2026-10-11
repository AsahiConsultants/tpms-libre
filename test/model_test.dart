import 'package:flutter_test/flutter_test.dart';
import 'package:tpms_libre/treel/model.dart';
import 'package:tpms_libre/treel/reading.dart';
import 'package:shared_preferences/shared_preferences.dart';

TreelReading reading(String id, int psi, {int c = 25, DateTime? at}) =>
    TreelReading(
      sensorId: id,
      psi: psi,
      celsius: c,
      rssi: -70,
      at: at ?? DateTime.now(),
    );

TyreState state(TyrePosition p, {TreelReading? r}) =>
    TyreState(position: p, sensorId: r?.sensorId, reading: r);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('PressureSpec', () {
    const spec = PressureSpec(front: 32, rear: 30, spare: 34);

    test('targets differ per axle and for the spare', () {
      expect(spec.targetFor(TyrePosition.frontLeft), 32);
      expect(spec.targetFor(TyrePosition.frontRight), 32);
      expect(spec.targetFor(TyrePosition.rearLeft), 30);
      expect(spec.targetFor(TyrePosition.rearRight), 30);
      expect(spec.targetFor(TyrePosition.spare), 34);
    });

    test(
      'tolerance is lopsided: heat may add psi, leaks may not remove it',
      () {
        // +5 over a 32 target is a warm tyre, not a fault.
        expect(spec.classify(37, TyrePosition.frontLeft), TyreHealth.ok);
        // -5 under the same target is a tyre losing air.
        expect(spec.classify(27, TyrePosition.frontLeft), TyreHealth.watch);
        expect(spec.classify(26, TyrePosition.frontLeft), TyreHealth.alert);
      },
    );

    test('bands land where the defaults say they do', () {
      expect(spec.classify(32, TyrePosition.frontLeft), TyreHealth.ok);
      expect(spec.classify(29, TyrePosition.frontLeft), TyreHealth.watch);
      expect(spec.classify(40, TyrePosition.frontLeft), TyreHealth.watch);
      expect(spec.classify(44, TyrePosition.frontLeft), TyreHealth.alert);
    });

    test('the real stepney case: 30 psi against a 34 target is a warning', () {
      expect(spec.classify(30, TyrePosition.spare), TyreHealth.watch);
    });

    test('survives a round trip through json', () {
      final back = PressureSpec.fromJson(spec.toJson());
      expect(back.front, 32);
      expect(back.rear, 30);
      expect(back.spare, 34);
      expect(back.overAlert, spec.overAlert);
    });
  });

  group('TyreState', () {
    const spec = PressureSpec();

    test('a stale reading is not trusted, whatever it says', () {
      final old = state(
        TyrePosition.frontLeft,
        r: reading(
          'a',
          35,
          at: DateTime.now().subtract(const Duration(hours: 2)),
        ),
      );
      expect(old.stale, isTrue);
      expect(old.freshness, 0);
      expect(old.health(spec), TyreHealth.unknown);
    });

    test('freshness decays from 1 to 0 over the staleness window', () {
      final now = state(TyrePosition.frontLeft, r: reading('a', 35));
      expect(now.freshness, closeTo(1.0, 0.02));
      final half = state(
        TyrePosition.frontLeft,
        r: reading('a', 35, at: DateTime.now().subtract(staleAfter ~/ 2)),
      );
      expect(half.freshness, closeTo(0.5, 0.05));
    });

    test('a scorching tyre is an alert even at the right pressure', () {
      final hot = state(TyrePosition.frontLeft, r: reading('a', 35, c: 85));
      expect(hot.health(spec), TyreHealth.alert);
    });

    test('delta reports the shortfall against this position target', () {
      final s = state(TyrePosition.spare, r: reading('a', 30));
      expect(s.delta(const PressureSpec(spare: 34)), -4);
    });
  });

  group('TreelReading json', () {
    test('round trips', () {
      final r = reading('f10a05', 30, c: 28);
      final back = TreelReading.fromJson(r.toJson())!;
      expect(back.sensorId, 'f10a05');
      expect(back.psi, 30);
      expect(back.celsius, 28);
      expect(back.at.millisecondsSinceEpoch, r.at.millisecondsSinceEpoch);
    });

    test('rejects rubbish rather than throwing', () {
      expect(TreelReading.fromJson({'id': 'x'}), isNull);
      expect(TreelReading.fromJson({}), isNull);
      expect(
        TreelReading.fromJson({'id': 1, 'psi': 'no', 'c': 2, 't': 3}),
        isNull,
      );
    });
  });

  group('TreelModel', () {
    late TreelModel model;
    setUp(() {
      model = TreelModel();
      addTearDown(model.dispose);
    });

    test('summary picks the worst tyre and names the shortfall', () async {
      await model.load();
      await model.setSpec(const PressureSpec(front: 32, rear: 30, spare: 34));
      model.ingest(reading('fl', 32));
      model.ingest(reading('sp', 30));
      await model.assign('fl', TyrePosition.frontLeft);
      await model.assign('sp', TyrePosition.spare);

      final (text, health) = model.summary;
      expect(health, TyreHealth.watch);
      expect(text, 'Spare is 4 psi low');
    });

    test('summary says so when everything is fine', () async {
      await model.load();
      await model.setSpec(const PressureSpec(front: 32, rear: 30));
      model.ingest(reading('fl', 32));
      await model.assign('fl', TyrePosition.frontLeft);
      final (text, health) = model.summary;
      expect(health, TyreHealth.ok);
      expect(text, contains('in range'));
    });

    test('a rotation swaps two sensors and keeps the rest', () async {
      await model.load();
      await model.assign('rl', TyrePosition.rearLeft);
      await model.assign('rr', TyrePosition.rearRight);
      await model.assign('sp', TyrePosition.spare);

      await model.swap(TyrePosition.rearLeft, TyrePosition.rearRight);

      expect(model.positionOf('rl'), TyrePosition.rearRight);
      expect(model.positionOf('rr'), TyrePosition.rearLeft);
      expect(model.positionOf('sp'), TyrePosition.spare);
    });

    test(
      'assigning to an occupied corner displaces whoever was there',
      () async {
        await model.load();
        await model.assign('a', TyrePosition.frontLeft);
        await model.assign('b', TyrePosition.frontLeft);
        expect(model.stateOf(TyrePosition.frontLeft).sensorId, 'b');
        expect(model.positionOf('a'), isNull);
      },
    );

    test('readings and assignments survive a restart', () async {
      await model.load();
      model.ingest(reading('f10a05', 30, c: 28));
      await model.assign('f10a05', TyrePosition.spare);
      await model.setHaptics(false);
      // Force the debounced write rather than waiting ten seconds. This
      // exercises the real save path, not a fixture typed by hand.
      await model.flush();

      final revived = TreelModel();
      addTearDown(revived.dispose);
      await revived.load();

      expect(revived.positionOf('f10a05'), TyrePosition.spare);
      expect(revived.haptics, isFalse);
      expect(
        revived.stateOf(TyrePosition.spare).hasReading,
        isTrue,
        reason: 'the app should open knowing what it last saw',
      );
    });

    test('wakes once per sensor, not once per reading', () async {
      await model.load();
      final woken = <String>[];
      model.onSensorWake = woken.add;

      model.ingest(reading('a', 35));
      model.ingest(reading('a', 35));
      model.ingest(reading('a', 36));

      expect(woken, ['a'], reason: 'one tap per tyre per launch');
      expect(model.isLive('a'), isTrue);
      expect(model.isLive('b'), isFalse);
    });

    test('a restored reading is not live until actually heard', () async {
      await model.load();
      expect(model.isLive('f10a05'), isFalse);
    });

    test('names the sensor that just woke, then stops', () async {
      await model.load();
      expect(model.wokeSensor, isNull);

      model.ingest(reading('f10a01', 33));
      expect(
        model.wokeSensor,
        'f10a01',
        reason: 'the haptic needs something to point at',
      );

      // It is a moment, not a state: it clears itself.
      await Future<void>.delayed(const Duration(milliseconds: 1600));
      expect(model.wokeSensor, isNull);
    });

    test('a second reading from the same sensor does not wake again', () async {
      await model.load();
      model.ingest(reading('f10a01', 33));
      model.ingest(reading('f10a01', 34));
      expect(model.wokeSensor, 'f10a01');
      final woken = <String>[];
      model.onSensorWake = woken.add;
      model.ingest(reading('f10a01', 35));
      expect(woken, isEmpty, reason: 'only the first live reading counts');
    });

    test('refresh re-arms the wake without discarding anything', () async {
      await model.load();
      final at = DateTime.now().subtract(const Duration(minutes: 3));
      model.ingest(reading('f10a01', 33, at: at));
      await model.assign('f10a01', TyrePosition.frontLeft);
      expect(model.liveCount, 1);

      model.refresh();

      expect(model.liveCount, 0, reason: 'nothing counts as confirmed again');
      expect(model.wokeSensor, isNull);
      expect(model.knownCount, 1, reason: 'but the reading is still there');
      expect(
        model.stateOf(TyrePosition.frontLeft).reading!.at,
        at,
        reason: 'and its real age is untouched, not reset to now',
      );

      final woken = <String>[];
      model.onSensorWake = woken.add;
      model.ingest(reading('f10a01', 33));
      expect(woken, ['f10a01'], reason: 'so it taps again when it reports');
    });

    test('restored readings are known but not counted as heard', () async {
      await model.load();
      model.ingest(reading('a', 35));
      // The counts describe the vehicle on screen, so the sensor has to be
      // on it to be counted.
      await model.assign('a', TyrePosition.frontLeft);
      await model.flush();

      final revived = TreelModel();
      addTearDown(revived.dispose);
      await revived.load();

      expect(revived.knownCount, 1, reason: 'it knows about the sensor');
      expect(
        revived.liveCount,
        0,
        reason: 'but has not heard it this run, and must not claim to',
      );

      revived.ingest(reading('a', 35));
      expect(revived.liveCount, 1);
    });
  });
}
