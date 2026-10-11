import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../treel/model.dart';
import '../treel/reading.dart';
import '../treel/scanner.dart';
import 'garage_sheet.dart';
import 'settings_sheet.dart';
import 'theme.dart';
import 'tyre.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.model, required this.scanner});

  final TreelModel model;
  final TreelScanner scanner;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// When a rotation is in progress, the wheel waiting to be swapped.
  TyrePosition? _swapFrom;

  TreelModel get model => widget.model;

  /// The rotation in progress, if it still applies: switching to another
  /// vehicle mid-rotation must not leave a banner naming a wheel it lacks.
  TyrePosition? get _rotating {
    final from = _swapFrom;
    final layout = model.vehicle.layout;
    return from != null && layout.rotates && layout.positions.contains(from)
        ? from
        : null;
  }

  void _onTyreTap(TyrePosition position) {
    final from = _rotating;
    if (from != null) {
      setState(() => _swapFrom = null);
      if (from != position) {
        model.swap(from, position);
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text('Swapped ${from.label} and ${position.label}'),
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
      return;
    }
    _showTyreSheet(position);
  }

  void _onTyreLongPress(TyrePosition position) {
    if (!model.vehicle.layout.rotates) return;
    if (!model.stateOf(position).assigned) return;
    setState(() => _swapFrom = position);
  }

  Future<void> _showTyreSheet(TyrePosition position) async {
    await showModalBottomSheet<void>(
      isScrollControlled: true,
      useSafeArea: true,
      context: context,
      showDragHandle: true,
      builder: (context) => SingleChildScrollView(
        child: _TyreSheet(
          model: model,
          position: position,
          onSwapStart: () => setState(() => _swapFrom = position),
        ),
      ),
    );
  }

  /// Pull down to have every tyre confirm itself again.
  Future<void> _refresh() async {
    model.refresh();
    // Also the recovery path. If Bluetooth or location was off and has since
    // been switched on, nothing tells us — Android does not announce that
    // location services came back. Pulling down is how the user says "try
    // again now".
    //
    // The gesture waits for the scan to restart, but not for ever: the radio
    // answers in milliseconds, and if it ever stalls the spinner should
    // still finish rather than spin until the app is killed.
    await widget.scanner.retry().timeout(
      const Duration(seconds: 3),
      onTimeout: () {},
    );
    // Long enough that the gesture is acknowledged, short enough not to
    // pretend we are fetching anything: the sensors report when they report,
    // and the tyres light up as they do.
    await Future<void>.delayed(const Duration(milliseconds: 600));
  }

  /// Tapping the picture. A vehicle we have no drawing of is wearing a
  /// borrowed one, and the owner's own photograph beats that every time —
  /// we cannot ship a drawing of every vehicle ever made, but they already
  /// have a picture of theirs.
  Future<void> _showPictureOptions() async {
    final vehicle = model.vehicle;
    final choice = await showModalBottomSheet<String>(
      isScrollControlled: true,
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => SingleChildScrollView(
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.add_photo_alternate_outlined),
                title: Text(
                  vehicle.hasPhoto
                      ? 'Choose a different photo'
                      : 'Use my photo',
                ),
                subtitle: const Text(
                  'Stays on this phone. The app has no way to send it anywhere.',
                  style: TextStyle(fontSize: 12),
                ),
                onTap: () => Navigator.pop(context, 'pick'),
              ),
              if (vehicle.hasPhoto)
                ListTile(
                  leading: Icon(
                    vehicle.art.hasAsset
                        ? Icons.undo_rounded
                        : Icons.hide_image_outlined,
                  ),
                  // Only promise a drawing when there is one to go back to.
                  title: Text(
                    vehicle.art.hasAsset
                        ? 'Back to the drawing'
                        : 'Remove photo',
                  ),
                  onTap: () => Navigator.pop(context, 'clear'),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;

    if (choice == 'clear') {
      await model.clearPhoto(vehicle.id);
      return;
    }

    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      // Read at a sane size from the start rather than pulling a 12
      // megapixel original into memory to shrink it afterwards.
      maxWidth: PhotoStore.maxEdge.toDouble(),
      maxHeight: PhotoStore.maxEdge.toDouble(),
    );
    if (picked == null || !mounted) return;

    final ok = await model.setPhoto(vehicle.id, File(picked.path));
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('That file could not be read as an image'),
        ),
      );
    }
  }

  /// [child] at the shared column's width, centred like the picture above.
  ///
  /// Padding, not a box of fixed width. The page measures its content's
  /// height in advance to decide whether to scroll, and a fixed-width box
  /// does not pass its narrower width into that measurement: text was
  /// measured at full width, wrapped less than it really does, came out
  /// short, and the page overflowed instead of scrolling at large text sizes.
  /// Padding narrows the measurement as well as the layout.
  Widget _shared(BuildContext context, Widget child) {
    final screen = MediaQuery.sizeOf(context).width;
    final side =
        (screen - _Diagram.portraitWidth(MediaQuery.sizeOf(context))) / 2;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: side),
      child: child,
    );
  }

  Future<void> _showGarage() async {
    await showModalBottomSheet<void>(
      isScrollControlled: true,
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) =>
          SingleChildScrollView(child: GarageSheet(model: model)),
    );
  }

  Future<void> _showSettings() async {
    final size = MediaQuery.sizeOf(context);
    await showModalBottomSheet<void>(
      context: context,
      // Material caps a sheet at 640 wide, too narrow for three columns of
      // settings; on its side the phone has the width to give.
      constraints: _Diagram.isLandscape(size)
          ? BoxConstraints(maxWidth: size.width - 48)
          : null,
      isScrollControlled: true,
      // Without this the sheet runs under the status bar and the first
      // heading collides with the clock.
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => ListenableBuilder(
        listenable: model,
        builder: (context, _) => SettingsSheet(
          vehicleName: model.vehicle.name,
          layout: model.vehicle.layout,
          spec: model.spec,
          onChanged: model.setSpec,
          haptics: model.haptics,
          animations: model.animations,
          onHaptics: model.setHaptics,
          onAnimations: model.setAnimations,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([model, widget.scanner]),
      builder: (context, _) {
        final spec = model.spec;
        final insets = MediaQuery.paddingOf(context);
        final landscape = _Diagram.isLandscape(MediaQuery.sizeOf(context));
        final footer = _Footer(model: model, scanner: widget.scanner);
        final banner = _Banner(
          status: widget.scanner.status,
          message: widget.scanner.message,
          swapFrom: _rotating,
          onCancelSwap: () => setState(() => _swapFrom = null),
          onRetry: widget.scanner.retry,
        );
        return Scaffold(
          appBar: AppBar(
            // On the page margin, like everything below it: the title's tap
            // target carries 6 of padding of its own.
            titleSpacing: Space.margin - 6,
            // The vehicle names the screen. With one vehicle it simply
            // reads as a title; with more it is how you change between them.
            title: InkWell(
              onTap: _showGarage,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        model.vehicle.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.expand_more_rounded,
                      size: 20,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              IconButton(
                onPressed: _showSettings,
                icon: const Icon(Icons.tune_rounded),
                tooltip: 'Target pressures',
              ),
            ],
          ),
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: _refresh,
              // The screen is a fixed layout, not a list, so it needs a
              // scrollable that fills the viewport for the gesture to exist
              // at all.
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverFillRemaining(
                    // Fills the viewport normally, and grows beyond it when
                    // the content genuinely needs more room — which happens
                    // at large system text sizes, where the banner and
                    // footer alone can exceed the screen.
                    hasScrollBody: false,
                    child: Column(
                      // Sit in the middle of whatever room there is rather
                      // than hugging the top. A bike drawn wide is only a
                      // third of a tall phone, and top-aligned it left a
                      // hole under it that read as something failing to
                      // load. When the content does outgrow the viewport
                      // this has no effect and the page simply scrolls.
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (landscape)
                          _Diagram(
                            model: model,
                            spec: spec,
                            swapFrom: _rotating,
                            onTyreTap: _onTyreTap,
                            onTyreLongPress: _onTyreLongPress,
                            onPictureTap: _showPictureOptions,
                            insets: insets,
                            above: landscape ? banner : null,
                            beside: landscape
                                ? _Footer(
                                    model: model,
                                    scanner: widget.scanner,
                                    part: _FooterPart.status,
                                  )
                                : null,
                            belowPicture: landscape
                                ? _Footer(
                                    model: model,
                                    scanner: widget.scanner,
                                    part: _FooterPart.setup,
                                  )
                                : null,
                          )
                        else ...[
                          // The banner, the picture, the readings and what
                          // they mean all share one width on the page margin,
                          // so they share a left edge. They used to sit at
                          // 14, 25.5, 29.5 and 16. See _shared for why the
                          // width comes from padding.
                          _shared(context, banner),
                          _Diagram(
                            model: model,
                            spec: spec,
                            swapFrom: _rotating,
                            onTyreTap: _onTyreTap,
                            onTyreLongPress: _onTyreLongPress,
                            onPictureTap: _showPictureOptions,
                            insets: insets,
                          ),
                          _shared(context, footer),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The vehicle and its wheels, drawn the way that vehicle reads best.
///
/// Sized from the screen rather than from whatever height is left over. The
/// old version used a LayoutBuilder against the remaining space, which meant
/// it could not report an intrinsic height, which in turn forced the page to
/// be exactly viewport-sized — and then large text had nowhere to go.
class _Diagram extends StatelessWidget {
  const _Diagram({
    required this.model,
    required this.spec,
    required this.swapFrom,
    required this.onTyreTap,
    required this.onTyreLongPress,
    required this.onPictureTap,
    required this.insets,
    this.above,
    this.beside,
    this.belowPicture,
  });

  final TreelModel model;
  final PressureSpec spec;
  final TyrePosition? swapFrom;
  final void Function(TyrePosition) onTyreTap;
  final void Function(TyrePosition) onTyreLongPress;
  final VoidCallback onPictureTap;

  /// The system's insets — status bar, navigation, a camera cutout on the
  /// side in landscape. Passed in because the diagram sits inside a SafeArea,
  /// which hides them from everything below it.
  final EdgeInsets insets;

  /// Shown above and under the readings when they sit beside the picture
  /// rather than below it: the banner -- "tap the wheel it swaps with" is
  /// about the cards -- and the status lines. Spanning the whole width
  /// instead, the banner pushed everything down and the status lines off
  /// the bottom of the screen.
  final Widget? above;
  final Widget? beside;

  /// Under the picture, on its side: sensors waiting to be placed. Setting
  /// up the vehicle reads naturally under the vehicle, and the left column
  /// has room the right one does not.
  final Widget? belowPicture;

  /// Wider than tall by a clear margin: a phone on its side, which in a car
  /// mount is a perfectly ordinary way to hold one.
  static bool isLandscape(Size s) => s.width > s.height * 1.2;

  /// The one column everything sits in, upright: the page margin either
  /// side, and no wider than reads well on a large phone.
  static double portraitWidth(Size s) =>
      math.min(s.width - 2 * Space.margin, 420.0);

  static const _cardGap = 6.0;

  bool _waking(TyrePosition p) =>
      model.wokeSensor != null && model.wokeSensor == model.stateOf(p).sensorId;

  TyreCard _card(TyrePosition position, double w, double h) => TyreCard(
    state: model.stateOf(position),
    spec: spec,
    width: w,
    height: h,
    animate: model.animations,
    waking: _waking(position),
    selected: swapFrom == position,
    onTap: () => onTyreTap(position),
    onLongPress: () => onTyreLongPress(position),
  );

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final layout = model.vehicle.layout;
    if (isLandscape(screen)) return _landscape(screen, layout);

    final w = portraitWidth(screen);
    return Center(
      child: SizedBox(
        width: w,
        child: _portrait(w, screen.height, model.vehicle.art, layout),
      ),
    );
  }

  /// The owner's photo if there is one, and the shape of whatever will be
  /// drawn in the picture slot.
  ({File? photo, double aspect}) _source(VehicleArt art) {
    final vehicle = model.vehicle;
    final photo = vehicle.hasPhoto ? model.photos.fileFor(vehicle.photo) : null;
    final aspect = photo != null
        ? vehicle.photoAspect
        : art.hasAsset
        ? art.aspect
        // The prompt is deliberately shallow: it is an invitation, not a
        // picture, and should not push the readings down the screen.
        : 2.2;
    return (photo: photo, aspect: aspect);
  }

  /// Spread across a row, but never wider than a card ought to be: two
  /// wheels sharing a whole phone's width made each card half the screen.
  double _evenWidth(double rowW, int n) =>
      math.min((rowW - _cardGap * (n - 1)) / n, 108.0);

  /// The cards across [rowW]. When they fill it, they sit flush with the
  /// column's edges and exactly [_cardGap] apart; spacing them evenly put the
  /// leftover around the outside too, so the row sat 4 in from the margin
  /// everything else is on. A pair held at full size, a motorcycle's, has
  /// room to spare and spreads evenly instead of huddling in the middle.
  Widget _evenRow(List<TyrePosition> positions, double tyreW, double rowW) {
    final n = positions.length;
    final fills = n * tyreW + (n - 1) * _cardGap >= rowW - 0.5;
    return Row(
      mainAxisAlignment: fills
          ? MainAxisAlignment.spaceBetween
          : MainAxisAlignment.spaceEvenly,
      children: [for (final p in positions) _card(p, tyreW, tyreW * 1.34)],
    );
  }

  Widget _picture(VehicleArt art, File? photo, double width, double height) =>
      Semantics(
        label: photo != null
            ? 'Your picture of this vehicle. Tap to change it.'
            : art.hasAsset
            ? 'Drawing of this vehicle. Tap to use your own picture.'
            : 'Add a photo of this vehicle.',
        button: true,
        child: InkWell(
          onTap: onPictureTap,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: width,
            height: height,
            child: photo != null
                ? Image.file(
                    photo,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                    excludeFromSemantics: true,
                    // The file was there when the vehicle loaded; if it has
                    // gone since, show nothing rather than a broken image
                    // icon over the readings.
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  )
                : art.hasAsset
                ? Image.asset(
                    art.asset!,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                    // The drawing is decoration; the readings are the
                    // content.
                    excludeFromSemantics: true,
                  )
                : const _AddPhoto(),
          ),
        ),
      );

  /// The vehicle's picture, then every reading in a single row beneath it.
  ///
  /// The cards sit below the picture rather than over it. Laying them on top
  /// would cover the wheels -- fine for a shape drawn in code, which just
  /// stops drawing there, but not for an illustration where the wheel is
  /// the most detailed part of it.
  ///
  /// Where a drawing shows both wheels, side-on, each card sits under its
  /// own. Anything else -- a car in three-quarter view with half its wheels
  /// hidden, or somebody's photograph -- has nothing to line the cards up
  /// with, so they spread evenly, which is why each card names its wheel.
  ///
  /// A vehicle with neither a photo nor a drawing shows a prompt to add a
  /// photo, in the same slot and answering the same tap.
  Widget _portrait(
    double w,
    double screenH,
    VehicleArt art,
    WheelLayout layout,
  ) {
    final (:photo, :aspect) = _source(art);

    // Height can be the binding constraint on a short screen. When it is,
    // the drawing narrows too, and anything lined up with it has to follow
    // the drawing rather than the column.
    final artW = math.min(w, screenH * 0.30 * aspect);
    final artH = artW / aspect;
    final positions = layout.positions;
    final lineUp =
        photo == null && art.wheelsAreVisible && positions.length == 2;

    final tyreW = lineUp
        ? (artW * 0.26).clamp(64.0, 108.0)
        : _evenWidth(w, positions.length);
    final tyreH = tyreW * 1.34;

    Widget cards() {
      if (!lineUp) return _evenRow(positions, tyreW, w);
      Widget under(TyrePosition p, double centre) => Positioned(
        left: (artW * centre - tyreW / 2).clamp(0.0, artW - tyreW),
        child: _card(p, tyreW, tyreH),
      );
      return SizedBox(
        height: tyreH,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            under(TyrePosition.rear, art.rearWheelX),
            under(TyrePosition.front, art.frontWheelX),
          ],
        ),
      );
    }

    return SizedBox(
      // Cards lined up with wheels have to sit in the drawing's own width;
      // a row spread evenly gets the whole column.
      width: lineUp ? artW : w,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _picture(art, photo, artW, artH),
          const SizedBox(height: Space.m),
          cards(),
        ],
      ),
    );
  }

  /// A phone on its side: the picture on the left, the readings -- and what
  /// they mean -- on the right. Stacked as in portrait, both shrank to fit a
  /// screen a third as tall and left most of its width empty.
  ///
  /// Cards never line up with wheels here: they are beside the picture, not
  /// under it.
  Widget _landscape(Size screen, WheelLayout layout) {
    const gutter = Space.xl;
    final art = model.vehicle.art;
    final (:photo, :aspect) = _source(art);
    final usableW = screen.width - insets.horizontal - 2 * Space.margin;
    final usableH = screen.height - insets.vertical - kToolbarHeight - 24;
    final column = (usableW - gutter) / 2;
    // Room for the sensors waiting to be placed, when there are any.
    final reserve = belowPicture != null && model.unassigned.isNotEmpty
        ? 96.0
        : 0.0;
    final artW = math.min(column, (usableH - reserve) * aspect);
    final artH = artW / aspect;
    final positions = layout.positions;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.margin),
      // Both columns start from the same top line. Centred separately, each
      // on its own content, the picture floated 19 to 53 above the cards.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [_picture(art, photo, artW, artH), ?belowPicture],
            ),
          ),
          const SizedBox(width: gutter),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              // Stretched, so the banner and the status lines share the
              // cards' left edge instead of being centred on their own width.
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ?above,
                _evenRow(
                  positions,
                  _evenWidth(column, positions.length),
                  column,
                ),
                ?beside,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What the picture slot shows before there is a picture.
class _AddPhoto extends StatelessWidget {
  const _AddPhoto();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        // The box has a fixed size, so large system text scales the
        // contents down rather than spilling out of it.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.add_a_photo_outlined,
                size: 30,
                color: Colors.white.withValues(alpha: 0.45),
              ),
              const SizedBox(height: 10),
              Text(
                'Add a photo of your vehicle',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.60),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.status,
    required this.message,
    required this.swapFrom,
    required this.onCancelSwap,
    required this.onRetry,
  });

  final ScanStatus status;
  final String? message;
  final TyrePosition? swapFrom;
  final VoidCallback onCancelSwap;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (swapFrom != null) {
      return _Strip(
        color: Colors.white,
        icon: Icons.swap_horiz_rounded,
        text: 'Rotating ${swapFrom!.label} — tap the wheel it swaps with',
        action: TextButton(
          onPressed: onCancelSwap,
          child: const Text('Cancel'),
        ),
      );
    }

    // Anything here stops readings arriving entirely, so say so plainly and
    // say what to do about it. Silence would look identical to a quiet car.
    final (text, detail, icon) = switch (status) {
      ScanStatus.bluetoothOff => (
        'Bluetooth is off',
        'Turn it on to hear the sensors, then pull down to refresh.',
        Icons.bluetooth_disabled_rounded,
      ),
      ScanStatus.locationServicesOff => (
        'Location is off',
        'These sensors broadcast as iBeacons, and Android classes iBeacons '
            'as location data — so it hides them until Location is on. That '
            'is the sensors\' format, not a choice of ours. This app has no '
            'internet permission and never asks where you are.',
        Icons.location_off_rounded,
      ),
      ScanStatus.noPermission => (
        'Permissions needed',
        'Nearby devices and Location are both required before Android will '
            'hand over the readings.',
        Icons.lock_outline_rounded,
      ),
      ScanStatus.unsupported => (
        'No Bluetooth LE on this device',
        null,
        Icons.error_outline_rounded,
      ),
      ScanStatus.error => ('Scan failed', message, Icons.error_outline_rounded),
      _ => (null, null, Icons.circle),
    };
    if (text == null) return const SizedBox.shrink();

    return _Strip(
      color: HealthColors.alert,
      icon: icon,
      text: text,
      detail: detail,
      action: TextButton(onPressed: onRetry, child: const Text('Retry')),
    );
  }
}

class _Strip extends StatelessWidget {
  const _Strip({
    required this.color,
    required this.icon,
    required this.text,
    this.detail,
    this.action,
  });

  final Color color;
  final IconData icon;
  final String text;
  final String? detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      // No side margin: it sits in the same column as everything else.
      // Below it, the gap to whatever it is about -- 6 to 10 before, close
      // enough to read as part of the cards.
      margin: const EdgeInsets.only(bottom: Space.l),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                if (detail != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      detail!,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // At the end of the line, at its own size. It used to share the
          // row half and half with the message, centred in its half, so it
          // floated in mid-air -- obvious once the strip was wide.
          if (action != null) ...[const SizedBox(width: 4), action!],
        ],
      ),
    );
  }
}

/// Listening state, and any sensors we can hear but have not placed.
/// Which half of the footer to show. Portrait shows both, stacked; on its
/// side the setup half goes under the picture and the status half under the
/// readings, so neither column runs off the bottom of the screen.
enum _FooterPart { all, setup, status }

class _Footer extends StatelessWidget {
  const _Footer({
    required this.model,
    required this.scanner,
    this.part = _FooterPart.all,
  });

  final TreelModel model;
  final TreelScanner scanner;
  final _FooterPart part;

  @override
  Widget build(BuildContext context) {
    final unplaced = model.unassigned;
    final known = model.knownCount;
    final liveNow = model.liveCount;
    final live = scanner.status == ScanStatus.scanning;

    // Nothing waiting to be placed: the setup half has nothing to say, and
    // an empty box would still push its padding into the layout.
    if (part == _FooterPart.setup && unplaced.isEmpty) {
      return const SizedBox.shrink();
    }

    // No side padding -- it sits in the shared column, on the page margin.
    // Above it, the gap from the readings to what they mean.
    return Padding(
      padding: const EdgeInsets.only(top: Space.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (unplaced.isNotEmpty && part != _FooterPart.status) ...[
            Text(
              '${unplaced.length} sensor${unplaced.length == 1 ? '' : 's'} '
              'not placed — tap to assign',
              style: TextStyle(
                fontSize: 11.5,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: Space.s),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: unplaced.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final r = unplaced[i];
                  return ActionChip(
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.sensors_rounded, size: 15),
                    label: Text(
                      '${r.sensorId}  ${r.psi} psi',
                      style: const TextStyle(
                        fontSize: 12,
                        fontFeatures: steadyDigits,
                      ),
                    ),
                    onPressed: () => _assign(context, r),
                  );
                },
              ),
            ),
            // A separate group from the status below it: the alert is the
            // most important line here and should not read as one more chip.
            if (part == _FooterPart.all) const SizedBox(height: Space.l),
          ],
          if (part != _FooterPart.setup) ...[
            Builder(
              builder: (context) {
                final (text, health) = model.summary;
                final colour = HealthColors.of(health);
                return Row(
                  children: [
                    Icon(
                      switch (health) {
                        TyreHealth.ok => Icons.check_circle_rounded,
                        TyreHealth.watch => Icons.error_outline_rounded,
                        TyreHealth.alert => Icons.warning_amber_rounded,
                        TyreHealth.unknown => Icons.more_horiz_rounded,
                      },
                      size: 18,
                      color: colour,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        text,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: colour,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: Space.s),
            Row(
              children: [
                _Pulse(active: live, animate: model.animations),
                const SizedBox(width: 8),
                // Both sides have to be able to give way. A Spacer between two
                // rigid Texts cannot shrink, so at larger system text sizes the
                // row simply runs off the screen.
                Flexible(
                  flex: 3,
                  child: Text(
                    live ? 'Listening' : 'Not listening',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  flex: 2,
                  child: Text(
                    known == 0
                        ? 'no sensors yet'
                        : liveNow == known
                        ? '$known live'
                        : '$liveNow of $known live',
                    textAlign: TextAlign.end,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.45),
                    ),
                  ),
                ),
              ],
            ),
            if (known == 0 && live)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Parked sensors broadcast every few minutes. Move the vehicle, '
                  'or wait.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _assign(BuildContext context, TreelReading reading) async {
    final position = await showModalBottomSheet<TyrePosition>(
      isScrollControlled: true,
      useSafeArea: true,
      context: context,
      showDragHandle: true,
      builder: (context) => SingleChildScrollView(
        child: _PositionPicker(model: model, reading: reading),
      ),
    );
    if (position != null) await model.assign(reading.sensorId, position);
  }
}

class _Pulse extends StatefulWidget {
  const _Pulse({required this.active, required this.animate});
  final bool active;
  final bool animate;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  /// A dot that breathes forever is the one thing on this screen with an
  /// ongoing cost: while it moves, the app redraws every frame and never
  /// idles. It moves only while listening, and only if both the app's own
  /// switch and Android's "Remove animations" allow it.
  bool get _moving =>
      widget.active &&
      widget.animate &&
      !MediaQuery.disableAnimationsOf(context);

  /// Starts and stops the controller itself, not just what is drawn. Merely
  /// drawing a still dot left the controller ticking -- and the screen
  /// redrawing -- after animations were switched off or scanning stopped.
  void _sync() {
    if (_moving) {
      if (!_c.isAnimating) _c.repeat(reverse: true);
    } else if (_c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_Pulse old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) {
      return const Icon(Icons.circle, size: 9, color: HealthColors.unknown);
    }
    if (!_moving) {
      return const Icon(Icons.circle, size: 9, color: HealthColors.ok);
    }
    return FadeTransition(
      opacity: Tween(begin: 0.35, end: 1.0).animate(_c),
      child: const Icon(Icons.circle, size: 9, color: HealthColors.ok),
    );
  }
}

/// Which corner does this sensor live on?
class _PositionPicker extends StatelessWidget {
  const _PositionPicker({required this.model, required this.reading});

  final TreelModel model;
  final TreelReading reading;

  @override
  Widget build(BuildContext context) {
    final landscape = _Diagram.isLandscape(MediaQuery.sizeOf(context));
    Widget tile(TyrePosition p) => ListTile(
      leading: CircleAvatar(
        radius: 15,
        backgroundColor: Colors.white.withValues(alpha: 0.08),
        child: Text(p.short, style: const TextStyle(fontSize: 11)),
      ),
      title: Text(p.label),
      subtitle: () {
        final occupant = model.stateOf(p).sensorId;
        return occupant == null
            ? null
            : Text('replaces $occupant', style: const TextStyle(fontSize: 12));
      }(),
      onTap: () => Navigator.pop(context, p),
    );

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text('Sensor ${reading.sensorId}'),
            subtitle: Text(
              '${reading.psi} psi · ${reading.celsius} °C · '
              '${shortAge(DateTime.now().difference(reading.at))}',
            ),
          ),
          const Divider(height: 1),
          // This vehicle's wheels, not every position that exists: a car
          // with a spare was being offered a motorcycle's front and rear.
          // On its side, two to a row: five wheels fit without scrolling.
          if (landscape)
            LayoutBuilder(
              builder: (context, box) => Wrap(
                children: [
                  for (final p in model.positions)
                    SizedBox(width: box.maxWidth / 2, child: tile(p)),
                ],
              ),
            )
          else
            for (final p in model.positions) tile(p),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Detail and actions for one wheel.
class _TyreSheet extends StatelessWidget {
  const _TyreSheet({
    required this.model,
    required this.position,
    required this.onSwapStart,
  });

  final TreelModel model;
  final TyrePosition position;
  final VoidCallback onSwapStart;

  @override
  Widget build(BuildContext context) {
    final state = model.stateOf(position);
    final reading = state.reading;
    final delta = state.delta(model.spec);
    final landscape = _Diagram.isLandscape(MediaQuery.sizeOf(context));

    final header = [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
        child: Row(
          children: [
            // The name gives way, not the target: at large text sizes
            // the two no longer fit side by side.
            Expanded(
              child: Text(
                position.label,
                style: Theme.of(context).textTheme.titleLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'target ${model.spec.targetFor(position)} psi',
              style: TextStyle(
                fontSize: 12.5,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    ];
    final details = [
      if (reading == null)
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 18),
          child: Text('Nothing assigned to this wheel yet.'),
        )
      else
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '${reading.psi}',
                    style: const TextStyle(
                      fontSize: 44,
                      fontWeight: FontWeight.w600,
                      fontFeatures: steadyDigits,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text('psi'),
                  ),
                  const SizedBox(width: 16),
                  if (delta != null && delta != 0)
                    // The one part of the row that can give way.
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          '${delta > 0 ? '+' : ''}$delta from target',
                          style: TextStyle(
                            fontSize: 13,
                            color: HealthColors.of(state.health(model.spec)),
                            fontFeatures: steadyDigits,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              _Fact('Temperature', '${reading.celsius} °C'),
              _Fact(
                'Also reads',
                '${reading.bar.toStringAsFixed(2)} bar · '
                    '${reading.kpa.toStringAsFixed(0)} kPa',
              ),
              _Fact('Sensor', state.sensorId ?? '—'),
              _Fact('Signal', '${reading.rssi} dBm'),
              _Fact('Last heard', shortAge(state.age)),
            ],
          ),
        ),
    ];
    final actions = [
      if (state.assigned) ...[
        if (model.vehicle.layout.rotates)
          ListTile(
            leading: const Icon(Icons.swap_horiz_rounded),
            title: const Text('Rotate this wheel'),
            subtitle: const Text('Then tap the wheel it swaps with'),
            onTap: () {
              Navigator.pop(context);
              onSwapStart();
            },
          ),
        ListTile(
          leading: const Icon(Icons.link_off_rounded),
          title: const Text('Unassign sensor'),
          onTap: () {
            model.unassign(state.sensorId!);
            Navigator.pop(context);
          },
        ),
      ] else
        ListTile(
          leading: const Icon(Icons.add_link_rounded),
          title: const Text('Assign a sensor'),
          subtitle: Text(
            model.unassigned.isEmpty
                ? 'None spare — every sensor heard is already placed'
                : '${model.unassigned.length} available',
          ),
          onTap: () async {
            final picked = await showModalBottomSheet<TreelReading>(
              isScrollControlled: true,
              useSafeArea: true,
              context: context,
              showDragHandle: true,
              builder: (context) => SingleChildScrollView(
                child: _SensorPicker(model: model, position: position),
              ),
            );
            if (picked != null) {
              await model.assign(picked.sensorId, position);
            }
            if (context.mounted) Navigator.pop(context);
          },
        ),
    ];

    // On its side the phone has width to spare and no height, so the reading
    // and what can be done with it sit side by side. Stacked, "Rotate this
    // wheel" -- the reason most people open this -- fell below the fold.
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...header,
          if (landscape)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: details,
                  ),
                ),
                // No rule between the two: one only as tall as the actions
                // stopped halfway down the reading and looked broken, and
                // stretching one to the row's height means measuring ahead of
                // layout, which overflowed whenever text wrapped. The gap
                // separates them well enough.
                Expanded(child: Column(children: actions)),
              ],
            )
          else ...[
            ...details,
            const Divider(height: 1),
            ...actions,
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        SizedBox(
          width: 108,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
        ),
        Flexible(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13.5, fontFeatures: steadyDigits),
          ),
        ),
      ],
    ),
  );
}

/// Which sensor goes on [position]?
///
/// The wheel's menu says how many sensors are free, so this leads with
/// exactly those. Sensors already on another wheel come after, under their
/// own heading and dimmed: taking one is a different, deliberate act — it
/// leaves the wheel it came from empty — and listing all of them alike under
/// "2 available" read as a mistake.
class _SensorPicker extends StatelessWidget {
  const _SensorPicker({required this.model, required this.position});
  final TreelModel model;
  final TyrePosition position;

  @override
  Widget build(BuildContext context) {
    final free = model.unassigned;
    final placed = [
      for (final r in model.allReadings)
        if (model.positionOf(r.sensorId) != null) r,
    ];
    final muted = Colors.white.withValues(alpha: 0.5);
    final landscape = _Diagram.isLandscape(MediaQuery.sizeOf(context));

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, letterSpacing: 0.4, color: muted),
      ),
    );

    String reading(TreelReading r) =>
        '${r.psi} psi · ${r.celsius} °C · '
        '${shortAge(DateTime.now().difference(r.at))}';

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            title: Text(
              'Which sensor is on the ${position.label.toLowerCase()}?',
            ),
          ),
          const Divider(height: 1),
          if (model.allReadings.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Nothing heard yet.'),
            ),
          // On its side, the two groups sit next to each other instead of
          // one long list: free on the left, as read first.
          if (landscape)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (free.isNotEmpty) ...[
                        heading('NOT ON A WHEEL · ${free.length}'),
                        for (final r in free)
                          ListTile(
                            leading: const Icon(Icons.sensors_rounded),
                            title: Text(
                              r.sensorId,
                              style: const TextStyle(
                                fontFeatures: steadyDigits,
                              ),
                            ),
                            subtitle: Text(reading(r)),
                            onTap: () => Navigator.pop(context, r),
                          ),
                      ] else if (placed.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                          child: Text(
                            'Every sensor heard is already on a wheel.',
                            style: TextStyle(fontSize: 13, color: muted),
                          ),
                        ),
                    ],
                  ),
                ),
                if (placed.isNotEmpty)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (placed.isNotEmpty) ...[
                          heading(
                            'ON ANOTHER WHEEL · MOVING ONE LEAVES THAT WHEEL EMPTY',
                          ),
                          for (final r in placed)
                            ListTile(
                              leading: Icon(
                                Icons.sensors_rounded,
                                color: muted,
                              ),
                              title: Text(
                                r.sensorId,
                                style: TextStyle(
                                  fontFeatures: steadyDigits,
                                  color: muted,
                                ),
                              ),
                              subtitle: Text(
                                'On the ${model.positionOf(r.sensorId)!.label.toLowerCase()}'
                                ' · ${reading(r)}',
                                style: TextStyle(color: muted),
                              ),
                              onTap: () => Navigator.pop(context, r),
                            ),
                        ],
                      ],
                    ),
                  ),
              ],
            )
          else ...[
            if (free.isNotEmpty) ...[
              heading('NOT ON A WHEEL · ${free.length}'),
              for (final r in free)
                ListTile(
                  leading: const Icon(Icons.sensors_rounded),
                  title: Text(
                    r.sensorId,
                    style: const TextStyle(fontFeatures: steadyDigits),
                  ),
                  subtitle: Text(reading(r)),
                  onTap: () => Navigator.pop(context, r),
                ),
            ] else if (placed.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Text(
                  'Every sensor heard is already on a wheel.',
                  style: TextStyle(fontSize: 13, color: muted),
                ),
              ),
            if (placed.isNotEmpty) ...[
              heading('ON ANOTHER WHEEL · MOVING ONE LEAVES THAT WHEEL EMPTY'),
              for (final r in placed)
                ListTile(
                  leading: Icon(Icons.sensors_rounded, color: muted),
                  title: Text(
                    r.sensorId,
                    style: TextStyle(fontFeatures: steadyDigits, color: muted),
                  ),
                  subtitle: Text(
                    'On the ${model.positionOf(r.sensorId)!.label.toLowerCase()}'
                    ' · ${reading(r)}',
                    style: TextStyle(color: muted),
                  ),
                  onTap: () => Navigator.pop(context, r),
                ),
            ],
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
