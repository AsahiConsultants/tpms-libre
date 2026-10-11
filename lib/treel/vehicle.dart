/// Vehicle shapes: what wheels a thing has, where they are, and what
/// pressure each should hold.
library;

/// Where a sensor sits. Cars use the four corners; two-wheelers just have a
/// front and a rear. Which of these exist is decided by [WheelLayout].
enum TyrePosition {
  frontLeft('FL', 'Front left'),
  frontRight('FR', 'Front right'),
  rearLeft('RL', 'Rear left'),
  rearRight('RR', 'Rear right'),
  front('F', 'Front'),
  rear('R', 'Rear'),
  spare('SP', 'Spare');

  const TyrePosition(this.short, this.label);

  /// Only for places too small for the full name, such as the avatar in the
  /// sensor picker. Not used on the tyre cards: a card sitting at the corner
  /// of a drawing of a car does not need telling which corner it is.
  final String short;
  final String label;

  /// Which target pressure applies. A motorcycle's front wheel wants the
  /// front figure exactly as a car's front left does.
  Axle get axle => switch (this) {
    TyrePosition.frontLeft ||
    TyrePosition.frontRight ||
    TyrePosition.front => Axle.front,
    TyrePosition.rearLeft ||
    TyrePosition.rearRight ||
    TyrePosition.rear => Axle.rear,
    TyrePosition.spare => Axle.spare,
  };

  static TyrePosition? byName(String n) =>
      TyrePosition.values.where((p) => p.name == n).firstOrNull;
}

enum Axle { front, rear, spare }

/// How the vehicle is drawn.
///
/// Cars read best from above: four corners, and you can see which is which.
/// A motorcycle from above is mostly tank and handlebars and could be any
/// bike, so it is drawn side-on, where the two wheels sit naturally front
/// and rear and the silhouette is actually recognisable.
enum Projection { topDown, sideOn }

enum WheelLayout {
  car('Car', 'Four wheels', Projection.topDown, [
    TyrePosition.frontLeft,
    TyrePosition.frontRight,
    TyrePosition.rearLeft,
    TyrePosition.rearRight,
  ]),
  carWithSpare(
    'Car with spare',
    'Four wheels and a spare',
    Projection.topDown,
    [
      TyrePosition.frontLeft,
      TyrePosition.frontRight,
      TyrePosition.rearLeft,
      TyrePosition.rearRight,
      TyrePosition.spare,
    ],
  ),
  motorcycle('Motorcycle', 'Front and rear', Projection.sideOn, [
    TyrePosition.front,
    TyrePosition.rear,
  ]);

  const WheelLayout(this.label, this.wheels, this.projection, this.positions);
  final String label;

  /// What wheels it has, in words. The projection is how we choose to draw
  /// it, which is our business and not worth telling anyone.
  final String wheels;
  final Projection projection;
  final List<TyrePosition> positions;

  bool get hasSpare => positions.contains(TyrePosition.spare);

  /// Whether its tyres can trade places. A motorcycle's front and rear
  /// tyres differ in size and construction, so they are never rotated.
  bool get rotates => this != motorcycle;

  static WheelLayout byName(String? n) =>
      WheelLayout.values.where((l) => l.name == n).firstOrNull ??
      WheelLayout.carWithSpare;
}

/// Which drawing a vehicle uses.
///
/// Nothing ships with a drawing yet: the only value is [generic], and a
/// vehicle without a picture shows a prompt to add a photo of the owner's
/// own. This is the slot drawings plug into when there are some — commissioned
/// for the purpose, since the app can only carry artwork it is free to
/// redistribute.
///
/// A drawing added here declares which shapes it suits, the names an owner
/// might type for it (so it can be offered without being looked for), its
/// aspect, and — for a side-on drawing showing both wheels — where those
/// wheels sit across the image, so a reading card can sit under each. Those
/// fractions are measured off the image, not guessed, and are tied to that
/// exact crop.
enum VehicleArt {
  generic(label: 'Generic');

  // The optional parameters are the shape of a drawing entry, unused until
  // the first one is added. Kept rather than deleted so adding a drawing is
  // one entry above, not a redesign of everything that reads these.
  // ignore_for_file: unused_element_parameter
  const VehicleArt({
    required this.label,
    this.asset,
    this.suits = const [],
    this.aliases = const [],
    this.aspect = 1.6,
    this.rearWheelX = 0,
    this.frontWheelX = 0,
  });

  final String label;

  /// Null means there is no drawing, and the screen shows a prompt instead.
  final String? asset;

  /// A drawing is of one particular vehicle, so it only fits those shapes: a
  /// picture of a bike is no use to a car. Empty on [generic], which fits
  /// everything.
  final List<WheelLayout> suits;

  /// What an owner might plausibly write in the name field. Nobody types the
  /// full label.
  final List<String> aliases;

  /// Width over height of the image file. Stored rather than read off the
  /// decoded image, because the cards have to be laid out before it loads.
  final double aspect;

  /// Wheel centres as a fraction of the image width. Only meaningful for a
  /// side-on drawing with two wheels; equal values mean the wheels cannot be
  /// lined up with, and the cards spread evenly instead.
  final double rearWheelX;
  final double frontWheelX;

  /// Whether cards can be lined up with the wheels in the drawing.
  bool get wheelsAreVisible => rearWheelX != frontWheelX;

  bool get hasAsset => asset != null;

  bool fits(WheelLayout layout) => suits.isEmpty || suits.contains(layout);

  /// What a vehicle of this shape could be drawn as, generic first.
  static List<VehicleArt> forLayout(WheelLayout layout) =>
      VehicleArt.values.where((a) => a.fits(layout)).toList();

  /// Which drawing suits a vehicle, if any: a known model matched by name.
  static VehicleArt suggest(String name) {
    String flat(String s) =>
        s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final n = flat(name);
    if (n.isEmpty) return VehicleArt.generic;
    for (final art in VehicleArt.values) {
      if (!art.hasAsset) continue;
      final keys = [art.label, ...art.aliases].map(flat);
      if (keys.any((k) => k.isNotEmpty && n.contains(k))) return art;
    }
    return VehicleArt.generic;
  }

  static VehicleArt byName(String? n) =>
      VehicleArt.values.where((a) => a.name == n).firstOrNull ??
      VehicleArt.generic;
}

/// How a tyre is doing relative to what it should be.
enum TyreHealth { ok, watch, alert, unknown }

/// What each tyre should read, and how far off is worth saying something.
///
/// The tolerances are deliberately lopsided. Under-inflation is the failure
/// that destroys tyres and causes blowouts; over-inflation mostly just rides
/// badly. On top of that, pressure climbs with temperature -- measured on
/// this very car, a 13 C rise on a drive took one tyre from 35 to 37 psi --
/// so a tight upper bound would cry wolf after every journey.
class PressureSpec {
  const PressureSpec({
    this.front = 35,
    this.rear = 35,
    this.spare = 30,
    this.underWatch = 3,
    this.underAlert = 6,
    this.overWatch = 8,
    this.overAlert = 12,
  });

  /// Cold placard pressures, per axle. The spare usually differs.
  final int front;
  final int rear;
  final int spare;

  /// How many psi below target before it is worth a glance, then a warning.
  final int underWatch;
  final int underAlert;

  /// The same above target, set wider: heat alone accounts for several psi.
  final int overWatch;
  final int overAlert;

  int targetFor(TyrePosition p) => switch (p.axle) {
    Axle.front => front,
    Axle.rear => rear,
    Axle.spare => spare,
  };

  TyreHealth classify(int psi, TyrePosition p) {
    final delta = psi - targetFor(p);
    if (delta <= -underAlert || delta >= overAlert) return TyreHealth.alert;
    if (delta <= -underWatch || delta >= overWatch) return TyreHealth.watch;
    return TyreHealth.ok;
  }

  PressureSpec copyWith({
    int? front,
    int? rear,
    int? spare,
    int? underWatch,
    int? underAlert,
    int? overWatch,
    int? overAlert,
  }) => PressureSpec(
    front: front ?? this.front,
    rear: rear ?? this.rear,
    spare: spare ?? this.spare,
    underWatch: underWatch ?? this.underWatch,
    underAlert: underAlert ?? this.underAlert,
    overWatch: overWatch ?? this.overWatch,
    overAlert: overAlert ?? this.overAlert,
  );

  Map<String, dynamic> toJson() => {
    'front': front,
    'rear': rear,
    'spare': spare,
    'underWatch': underWatch,
    'underAlert': underAlert,
    'overWatch': overWatch,
    'overAlert': overAlert,
  };

  factory PressureSpec.fromJson(Map<String, dynamic> j) => PressureSpec(
    front: j['front'] as int? ?? 35,
    rear: j['rear'] as int? ?? 35,
    spare: j['spare'] as int? ?? 30,
    underWatch: j['underWatch'] as int? ?? 3,
    underAlert: j['underAlert'] as int? ?? 6,
    overWatch: j['overWatch'] as int? ?? 8,
    overAlert: j['overAlert'] as int? ?? 12,
  );
}

/// One vehicle: what it is called, what shape it is, what its tyres should
/// read, and which sensor is bolted to which wheel.
class Vehicle {
  const Vehicle({
    required this.id,
    required this.name,
    this.layout = WheelLayout.carWithSpare,
    this.art = VehicleArt.generic,
    this.artChosen = false,
    this.photo,
    this.photoAspect = 1.5,
    this.spec = const PressureSpec(),
    this.assignments = const {},
  });

  /// Stable across renames, because assignments hang off it.
  final String id;

  /// Whatever the owner calls it.
  final String name;
  final WheelLayout layout;
  final VehicleArt art;

  /// Whether [art] is the owner's choice rather than the app's guess.
  ///
  /// Without this the two are indistinguishable once written down, and a
  /// guess of "generic" made when there was no drawing of that car would outlive
  /// the arrival of one -- the app would keep deferring to its own earlier
  /// shrug. A guess is re-made on every load; a choice is never overridden,
  /// including a deliberate choice of generic.
  final bool artChosen;

  /// A picture the owner supplied, as a bare filename inside the app's photo
  /// directory. A filename rather than a path because the sandbox directory
  /// is not stable across installs on either platform, so an absolute path
  /// stored today can be wrong tomorrow.
  ///
  /// When set it replaces the drawing. Nothing is known about where its
  /// wheels are, so the readings spread evenly rather than lining up.
  final String? photo;

  /// Width over height of [photo], measured when it was saved. Stored
  /// because the layout has to be decided before the file is decoded.
  final double photoAspect;

  bool get hasPhoto => photo != null;

  final PressureSpec spec;

  /// Sensor id to wheel. Sensor ids come out of the advertisement payload,
  /// so an assignment survives reinstalls and does not depend on the BLE
  /// address, which Android randomises.
  final Map<String, TyrePosition> assignments;

  List<TyrePosition> get positions => layout.positions;

  String? sensorAt(TyrePosition p) => assignments.entries
      .where((e) => e.value == p)
      .map((e) => e.key)
      .firstOrNull;

  TyrePosition? positionOf(String sensorId) => assignments[sensorId];

  Vehicle copyWith({
    String? name,
    WheelLayout? layout,
    VehicleArt? art,
    bool? artChosen,
    String? photo,
    double? photoAspect,
    bool clearPhoto = false,
    PressureSpec? spec,
    Map<String, TyrePosition>? assignments,
  }) => Vehicle(
    id: id,
    name: name ?? this.name,
    layout: layout ?? this.layout,
    art: art ?? this.art,
    artChosen: artChosen ?? this.artChosen,
    photo: clearPhoto ? null : (photo ?? this.photo),
    photoAspect: photoAspect ?? this.photoAspect,
    spec: spec ?? this.spec,
    assignments: assignments ?? this.assignments,
  );

  /// Drops assignments to wheels this layout does not have, which is what
  /// happens when a car with a spare becomes one without, or a motorcycle.
  Vehicle withLayout(WheelLayout next) => copyWith(
    layout: next,
    assignments: {
      for (final e in assignments.entries)
        if (next.positions.contains(e.value)) e.key: e.value,
    },
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'layout': layout.name,
    'art': art.name,
    'artChosen': artChosen,
    if (photo != null) 'photo': photo,
    if (photo != null) 'photoAspect': photoAspect,
    'spec': spec.toJson(),
    'assignments': assignments.map((k, v) => MapEntry(k, v.name)),
  };

  factory Vehicle.fromJson(Map<String, dynamic> j) {
    final assignments = <String, TyrePosition>{};
    for (final e in ((j['assignments'] as Map?) ?? const {}).entries) {
      // Skip a position this build does not know, so an assignment written
      // by a later version cannot crash an earlier one.
      final p = TyrePosition.byName(e.value as String);
      if (p != null) assignments[e.key as String] = p;
    }
    final name = j['name'] as String? ?? 'My vehicle';
    final layout = WheelLayout.byName(j['layout'] as String?);
    // Only a choice is restored. Anything else is re-guessed from the name
    // every time, so a vehicle picks up a drawing as soon as one exists --
    // whether it was saved before drawings existed at all, or saved back
    // when we had no drawing of that particular vehicle.
    final chosen = j['artChosen'] as bool? ?? false;
    final recorded = chosen
        ? VehicleArt.byName(j['art'] as String?)
        : VehicleArt.suggest(name);
    return Vehicle(
      id: j['id'] as String? ?? 'default',
      name: name,
      layout: layout,
      art: recorded.fits(layout) ? recorded : VehicleArt.generic,
      artChosen: chosen,
      photo: j['photo'] as String?,
      photoAspect: (j['photoAspect'] as num?)?.toDouble() ?? 1.5,
      spec: PressureSpec.fromJson(
        (j['spec'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      assignments: assignments,
    );
  }
}
