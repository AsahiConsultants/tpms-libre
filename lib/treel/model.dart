import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'photos.dart';
import 'reading.dart';
import 'vehicle.dart';

export 'photos.dart';
export 'vehicle.dart';

/// A reading stops being trustworthy long before it stops being displayed.
/// Sensors are quiet for minutes at a time when parked, so the age of a
/// reading matters as much as its value.
const Duration staleAfter = Duration(minutes: 15);

class TyreState {
  const TyreState({required this.position, this.sensorId, this.reading});

  final TyrePosition position;
  final String? sensorId;
  final TreelReading? reading;

  bool get assigned => sensorId != null;
  bool get hasReading => reading != null;

  Duration? get age =>
      reading == null ? null : DateTime.now().difference(reading!.at);

  /// 1.0 for a reading that just arrived, falling to 0 as it goes stale.
  double get freshness {
    final a = age;
    if (a == null) return 0;
    final t = a.inSeconds / staleAfter.inSeconds;
    return (1.0 - t).clamp(0.0, 1.0);
  }

  bool get stale => (age ?? Duration.zero) > staleAfter;

  TyreHealth health(PressureSpec spec) {
    final r = reading;
    if (r == null || stale) return TyreHealth.unknown;
    // A tyre this hot is a problem regardless of what the gauge says.
    if (r.celsius >= 80) return TyreHealth.alert;
    return spec.classify(r.psi, position);
  }

  /// How far from target, for showing the user the actual shortfall.
  int? delta(PressureSpec spec) =>
      reading == null ? null : reading!.psi - spec.targetFor(position);
}

/// Live readings plus which sensor is bolted to which corner.
///
/// Sensor ids come out of the advertisement payload, so an assignment
/// survives reinstalls and does not depend on the BLE address, which
/// Android randomises.
class TreelModel extends ChangeNotifier {
  /// [photos] is injectable so a test can point the store at a temporary
  /// directory instead of the platform's, which it cannot ask for.
  TreelModel({PhotoStore? photos}) : photos = photos ?? PhotoStore() {
    // Ages are shown to the user, so the UI has to keep ticking even when
    // no sensor has spoken.
    _tick = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_latest.isNotEmpty) notifyListeners();
    });
  }

  // Pre-vehicles keys, read once at load so an existing install keeps its
  // wheels and targets instead of starting over.
  static const _kVehicles = 'vehicles';
  static const _kActiveVehicle = 'activeVehicle';
  static const _kReadings = 'lastReadings';
  static const _kHaptics = 'haptics';
  static const _kAnimations = 'animations';

  final Map<String, TreelReading> _latest = {};
  List<Vehicle> _vehicles = const [];
  String? _activeId;
  Timer? _tick;
  Timer? _saveDebounce;
  bool _loaded = false;
  bool _haptics = true;
  bool _animations = true;

  /// Sensors that have reported live since the app opened. A sensor restored
  /// from storage is not in here until it is actually heard again.
  final Set<String> _liveThisSession = {};
  DateTime? _lastWake;

  /// The sensor that woke a moment ago, for the UI to mark. A tap you cannot
  /// attribute to a tyre is just a buzz; the point is the pairing.
  String? _wokeSensor;
  Timer? _wokeClear;

  /// Called the first time each sensor reports live in this session, so the
  /// UI can mark the moment. Kept as a callback rather than firing haptics
  /// from here: the model should not know what a phone feels like.
  void Function(String sensorId)? onSensorWake;

  List<Vehicle> get vehicles => List.unmodifiable(_vehicles);

  /// The vehicle being shown. Never null once loaded: a first run creates
  /// one, because an app with no vehicle has nothing to say.
  Vehicle get vehicle => _vehicles.firstWhere(
    (v) => v.id == _activeId,
    orElse: () => _vehicles.isEmpty
        ? const Vehicle(id: 'default', name: 'My vehicle')
        : _vehicles.first,
  );

  PressureSpec get spec => vehicle.spec;
  List<TyrePosition> get positions => vehicle.positions;
  bool get loaded => _loaded;
  bool get haptics => _haptics;
  bool get animations => _animations;

  /// Whether this sensor has been heard live since the app opened, as
  /// opposed to being restored from the last session.
  bool isLive(String sensorId) => _liveThisSession.contains(sensorId);

  /// The sensor that just came live, if that was recent enough to still be
  /// worth showing. Null the rest of the time.
  String? get wokeSensor => _wokeSensor;

  /// Sensors on *this* vehicle that we have a reading for.
  ///
  /// Scoped to the vehicle on screen. A motorcycle page reporting "0 of 5"
  /// because the car has five sensors is counting wheels that are not
  /// there.
  int get knownCount =>
      vehicle.assignments.keys.where((id) => _latest.containsKey(id)).length;

  /// How many of those have actually reported since the app opened.
  /// Restored readings do not count: saying "heard" over a value loaded from
  /// disk is the same lie the per-tyre ages exist to prevent.
  int get liveCount => vehicle.assignments.keys
      .where((id) => _liveThisSession.contains(id))
      .length;

  /// Every sensor heard this session, newest reading first.
  List<TreelReading> get allReadings {
    final all = _latest.values.toList()..sort((a, b) => b.at.compareTo(a.at));
    return all;
  }

  /// Sensors we have heard but not placed on *any* vehicle. A sensor on the
  /// motorcycle should not show up as spare capacity for the car.
  List<TreelReading> get unassigned {
    final placed = {for (final v in _vehicles) ...v.assignments.keys};
    return allReadings.where((r) => !placed.contains(r.sensorId)).toList();
  }

  TyreState stateOf(TyrePosition position) {
    final sensorId = vehicle.sensorAt(position);
    return TyreState(
      position: position,
      sensorId: sensorId,
      reading: sensorId == null ? null : _latest[sensorId],
    );
  }

  TyrePosition? positionOf(String sensorId) => vehicle.positionOf(sensorId);

  Future<void> _replaceVehicle(Vehicle next) async {
    _vehicles = [
      for (final v in _vehicles)
        if (v.id == next.id) next else v,
    ];
    notifyListeners();
    await _save();
  }

  void ingest(TreelReading reading) {
    _latest[reading.sensorId] = reading;
    if (_liveThisSession.add(reading.sensorId)) {
      // First time this tyre has spoken since the app opened: the stale
      // number on screen just became real. Debounced, because sensors
      // arriving together should feel like one event, not a burst.
      final now = DateTime.now();
      if (_lastWake == null ||
          now.difference(_lastWake!) > const Duration(milliseconds: 400)) {
        _lastWake = now;
        _wokeSensor = reading.sensorId;
        _wokeClear?.cancel();
        _wokeClear = Timer(const Duration(milliseconds: 1400), () {
          _wokeSensor = null;
          notifyListeners();
        });
        onSensorWake?.call(reading.sensorId);
      }
    }
    _saveReadingsSoon();
    notifyListeners();
  }

  /// Readings arrive many times a second when the car is close, so writing
  /// on every one would be absurd. Losing the last few seconds on a kill is
  /// of no consequence.
  void _saveReadingsSoon() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(seconds: 10), _saveReadings);
  }

  /// Write pending readings now. Called when the app is backgrounded, so a
  /// swipe-away does not throw away the last few seconds.
  Future<void> flush() async {
    _saveDebounce?.cancel();
    await _saveReadings();
  }

  Future<void> _saveReadings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kReadings,
      jsonEncode(_latest.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }

  /// Owner-supplied vehicle pictures. Exposed so the UI can turn a stored
  /// filename into something it can draw.
  final PhotoStore photos;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    final raw = prefs.getString(_kVehicles);
    if (raw != null) {
      _vehicles = [
        for (final v in jsonDecode(raw) as List)
          Vehicle.fromJson((v as Map).cast<String, dynamic>()),
      ];
    }
    if (_vehicles.isEmpty) {
      _vehicles = [const Vehicle(id: 'default', name: 'My vehicle')];
    }
    _activeId = prefs.getString(_kActiveVehicle) ?? _vehicles.first.id;

    final readingsRaw = prefs.getString(_kReadings);
    if (readingsRaw != null) {
      final decoded = jsonDecode(readingsRaw) as Map<String, dynamic>;
      for (final e in decoded.entries) {
        final r = TreelReading.fromJson(e.value as Map<String, dynamic>);
        // Never let a value off disk overwrite one already heard live: load
        // is async and a sensor can report before it finishes.
        if (r != null && !_liveThisSession.contains(e.key)) {
          _latest[e.key] = r;
        }
      }
    }
    _haptics = prefs.getBool(_kHaptics) ?? true;
    _animations = prefs.getBool(_kAnimations) ?? true;

    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kVehicles,
      jsonEncode([for (final v in _vehicles) v.toJson()]),
    );
    await prefs.setString(_kActiveVehicle, vehicle.id);
  }

  Future<void> assign(String sensorId, TyrePosition position) async {
    final next = {...vehicle.assignments}
      // One sensor per corner: whatever was there is displaced. And a sensor
      // cannot be in two places, so its old wheel is vacated too.
      ..removeWhere((id, p) => p == position || id == sensorId)
      ..[sensorId] = position;
    await _replaceVehicle(vehicle.copyWith(assignments: next));
  }

  Future<void> unassign(String sensorId) async {
    final next = {...vehicle.assignments}..remove(sensorId);
    await _replaceVehicle(vehicle.copyWith(assignments: next));
  }

  /// A tyre rotation, in the sense a garage means it: two wheels change
  /// places, so their sensors do too.
  Future<void> swap(TyrePosition a, TyrePosition b) async {
    if (a == b) return;
    final sa = vehicle.sensorAt(a);
    final sb = vehicle.sensorAt(b);
    final next = {...vehicle.assignments};
    if (sa != null) next[sa] = b;
    if (sb != null) next[sb] = a;
    await _replaceVehicle(vehicle.copyWith(assignments: next));
  }

  /// The one thing worth saying about the whole vehicle.
  ///
  /// Five tyres is too many to scan when the answer is usually "fine" and
  /// occasionally "one of them is low".
  (String, TyreHealth) get summary {
    final placed = positions.map(stateOf).where((s) => s.assigned).toList();
    if (placed.isEmpty) return ('Nothing assigned yet', TyreHealth.unknown);

    final live = placed.where((s) => s.hasReading && !s.stale).toList();
    if (live.isEmpty) return ('Waiting for a reading', TyreHealth.unknown);

    TyreState? worst;
    var worstRank = -1;
    for (final s in live) {
      final rank = switch (s.health(spec)) {
        TyreHealth.alert => 3,
        TyreHealth.watch => 2,
        _ => 0,
      };
      if (rank > worstRank) {
        worstRank = rank;
        worst = s;
      }
    }

    final stale = placed.length - live.length;
    if (worstRank == 0) {
      final all = 'All ${live.length} in range';
      return (
        stale == 0 ? all : '$all, $stale not heard recently',
        TyreHealth.ok,
      );
    }

    final w = worst!;
    final delta = w.delta(spec)!;
    return (
      '${w.position.label} is ${delta.abs()} psi ${delta < 0 ? 'low' : 'high'}',
      w.health(spec),
    );
  }

  // --- the garage ---------------------------------------------------------

  Future<void> addVehicle(
    String name,
    WheelLayout layout, {
    VehicleArt art = VehicleArt.generic,
    bool artChosen = false,
  }) async {
    final v = Vehicle(
      id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
      name: name.trim().isEmpty ? 'My vehicle' : name.trim(),
      layout: layout,
      art: art,
      artChosen: artChosen,
    );
    _vehicles = [..._vehicles, v];
    _activeId = v.id;
    notifyListeners();
    await _save();
  }

  Future<void> renameVehicle(String id, String name) async {
    final v = _vehicles.firstWhere((v) => v.id == id);
    await _replaceVehicle(
      v.copyWith(name: name.trim().isEmpty ? v.name : name.trim()),
    );
  }

  /// [chosen] false means this is the app's guess from the name, which a
  /// later build is free to revisit; true means the owner picked it.
  Future<void> setArt(String id, VehicleArt art, {bool chosen = true}) async {
    final v = _vehicles.firstWhere((v) => v.id == id);
    await _replaceVehicle(v.copyWith(art: art, artChosen: chosen));
  }

  /// Finds the photo directory and drops references to pictures that are no
  /// longer there.
  ///
  /// Deliberately not awaited by [load]. Asking the platform for a directory
  /// is a channel call, and in a widget test nothing answers it — awaiting
  /// that inside load would hang every test that builds a screen. Photos
  /// simply appear a frame later than the rest of the state.
  Future<void> openPhotos() async {
    await photos.open();
    if (!photos.ready) return;

    // A picture can go missing: app data cleared, or a restore onto a new
    // phone. Forget the reference rather than leaving the screen trying to
    // draw a file that is not there.
    final lost = [
      for (final v in _vehicles)
        if (v.hasPhoto && !photos.exists(v.photo)) v.id,
    ];
    if (lost.isNotEmpty) {
      _vehicles = [
        for (final v in _vehicles)
          lost.contains(v.id) ? v.copyWith(clearPhoto: true) : v,
      ];
      await _save();
    }
    notifyListeners();
  }

  /// Stores [source] as this vehicle's picture, replacing any previous one.
  ///
  /// Returns false when the file could not be read as an image, so the
  /// caller can say so instead of silently doing nothing.
  Future<bool> setPhoto(String id, File source) async {
    final v = _vehicles.firstWhere((v) => v.id == id);
    final saved = await photos.save(id, source);
    if (saved == null) return false;
    final old = v.photo;
    await _replaceVehicle(
      v.copyWith(photo: saved.name, photoAspect: saved.aspect),
    );
    // Only after the new one is recorded, so a crash in between leaves the
    // old picture in place rather than none at all.
    await photos.delete(old);
    return true;
  }

  Future<void> clearPhoto(String id) async {
    final v = _vehicles.firstWhere((v) => v.id == id);
    if (!v.hasPhoto) return;
    final old = v.photo;
    await _replaceVehicle(v.copyWith(clearPhoto: true));
    await photos.delete(old);
  }

  /// Changing shape drops assignments to wheels that no longer exist.
  Future<void> setLayout(String id, WheelLayout layout) async {
    final v = _vehicles.firstWhere((v) => v.id == id);
    await _replaceVehicle(v.withLayout(layout));
  }

  Future<void> removeVehicle(String id) async {
    _vehicles = _vehicles.where((v) => v.id != id).toList();
    if (_activeId == id) _activeId = _vehicles.firstOrNull?.id;
    if (_vehicles.isEmpty) {
      _vehicles = [const Vehicle(id: 'default', name: 'My vehicle')];
      _activeId = 'default';
    }
    notifyListeners();
    await _save();
  }

  Future<void> selectVehicle(String id) async {
    if (_activeId == id) return;
    _activeId = id;
    // Wheels belong to the vehicle, so the wake highlights do too.
    _wokeClear?.cancel();
    _wokeSensor = null;
    notifyListeners();
    await _save();
  }

  Future<void> setSpec(PressureSpec spec) async =>
      _replaceVehicle(vehicle.copyWith(spec: spec));

  /// Forget which sensors have been heard this session, so every tyre wakes
  /// again — highlight and tap — as it next reports. Nothing is discarded:
  /// the readings and their real ages stay exactly as they were. This asks
  /// "show me each of these confirmed again", not "pretend you know less".
  void refresh() {
    _liveThisSession.clear();
    _wokeClear?.cancel();
    _wokeSensor = null;
    _lastWake = null;
    notifyListeners();
  }

  Future<void> setHaptics(bool on) async {
    _haptics = on;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHaptics, on);
  }

  Future<void> setAnimations(bool on) async {
    _animations = on;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAnimations, on);
  }

  @override
  void dispose() {
    _tick?.cancel();
    _saveDebounce?.cancel();
    _wokeClear?.cancel();
    super.dispose();
  }
}
