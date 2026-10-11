import 'package:flutter/material.dart';

import '../treel/model.dart';
import 'theme.dart';

/// Switching between vehicles, and managing which ones exist.
///
/// Only worth opening when there is more than one, or when adding one — a
/// single-vehicle owner should never have to think about a garage.
class GarageSheet extends StatelessWidget {
  const GarageSheet({super.key, required this.model});

  final TreelModel model;

  IconData _iconFor(WheelLayout layout) => switch (layout) {
    WheelLayout.motorcycle => Icons.two_wheeler_rounded,
    _ => Icons.directions_car_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListenableBuilder(
        listenable: model,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Vehicles', style: TextStyle(fontSize: 19)),
            ),
            for (final v in model.vehicles)
              ListTile(
                leading: Icon(
                  _iconFor(v.layout),
                  color: v.id == model.vehicle.id
                      ? HealthColors.ok
                      : Colors.white.withValues(alpha: 0.5),
                ),
                title: Text(v.name),
                subtitle: Text(
                  '${v.layout.label} · ${v.assignments.length} of '
                  '${v.positions.length} wheels assigned',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    showDragHandle: true,
                    builder: (context) =>
                        VehicleSheet(model: model, vehicle: v),
                  ),
                ),
                selected: v.id == model.vehicle.id,
                onTap: () {
                  model.selectVehicle(v.id);
                  Navigator.pop(context);
                },
              ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.add_rounded),
              title: const Text('Add a vehicle'),
              onTap: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                showDragHandle: true,
                builder: (context) => VehicleSheet(model: model),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Adding a vehicle, or editing one. The same form either way.
class VehicleSheet extends StatefulWidget {
  const VehicleSheet({super.key, required this.model, this.vehicle});

  final TreelModel model;

  /// Null when adding.
  final Vehicle? vehicle;

  @override
  State<VehicleSheet> createState() => _VehicleSheetState();
}

class _VehicleSheetState extends State<VehicleSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.vehicle?.name ?? '',
  );
  late WheelLayout _layout = widget.vehicle?.layout ?? WheelLayout.carWithSpare;

  /// Null until the owner picks a drawing themselves; until then the name
  /// decides, so typing a known model's name gets its drawing unasked.
  late VehicleArt? _chosenArt = widget.vehicle?.art == VehicleArt.generic
      ? null
      : widget.vehicle?.art;

  bool get _editing => widget.vehicle != null;

  /// The drawing that applies right now: what was picked if it still suits
  /// the chosen shape, else what the name suggests, else the generic one.
  VehicleArt get _art {
    final chosen = _chosenArt;
    if (chosen != null && chosen.fits(_layout)) return chosen;
    final guess = VehicleArt.suggest(_name.text);
    return guess.fits(_layout) ? guess : VehicleArt.generic;
  }

  @override
  void initState() {
    super.initState();
    // The suggestion follows the name as it is typed.
    _name.addListener(() {
      if (_chosenArt == null && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_editing) {
      await widget.model.renameVehicle(widget.vehicle!.id, _name.text);
      await widget.model.setLayout(widget.vehicle!.id, _layout);
      // _chosenArt is only set by tapping one, so a drawing that merely
      // followed the name stays a guess and can be revised later.
      await widget.model.setArt(
        widget.vehicle!.id,
        _art,
        chosen: _chosenArt != null,
      );
    } else {
      await widget.model.addVehicle(
        _name.text,
        _layout,
        art: _art,
        artChosen: _chosenArt != null,
      );
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final v = widget.vehicle!;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${v.name}?'),
        content: const Text(
          'Its wheel assignments go with it. The sensors themselves are '
          'untouched and can be placed on another vehicle.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    await widget.model.removeVehicle(v.id);
    if (mounted) Navigator.pop(context);
  }

  /// Warns before a layout change throws assignments away.
  int get _losing {
    final v = widget.vehicle;
    if (v == null) return 0;
    return v.assignments.values
        .where((p) => !_layout.positions.contains(p))
        .length;
  }

  /// Only shown when there is actually a choice. A lone "Generic" radio
  /// button asks the owner to make a decision that has already been made.
  Widget _artwork(BuildContext context) {
    final options = VehicleArt.forLayout(_layout);
    if (options.length < 2) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Drawing', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'How it appears on the home screen.',
            style: TextStyle(
              fontSize: 12.5,
              color: Colors.white.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 10),
          RadioGroup<VehicleArt>(
            groupValue: _art,
            onChanged: (v) => setState(() => _chosenArt = v),
            child: Column(
              children: [
                for (final art in options)
                  RadioListTile<VehicleArt>(
                    contentPadding: EdgeInsets.zero,
                    value: art,
                    title: Text(
                      art.label,
                      style: const TextStyle(fontSize: 14),
                    ),
                    secondary: art.hasAsset
                        ? SizedBox(
                            width: 56,
                            height: 40,
                            child: Image.asset(
                              art.asset!,
                              fit: BoxFit.contain,
                              excludeFromSemantics: true,
                            ),
                          )
                        : null,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height * 1.2;
    final caption = TextStyle(
      fontSize: 12.5,
      color: Colors.white.withValues(alpha: 0.55),
    );

    final title = Text(
      _editing ? 'Edit vehicle' : 'Add a vehicle',
      style: Theme.of(context).textTheme.titleMedium,
    );
    final name = TextField(
      controller: _name,
      textCapitalization: TextCapitalization.words,
      decoration: const InputDecoration(
        // No example. The label says what the field is for, and a
        // placeholder here would only ever be somebody's real plate.
        labelText: 'Name or registration',
        border: OutlineInputBorder(),
      ),
    );
    final shape = <Widget>[
      Text('Shape', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 4),
      Text('Which wheels this vehicle has.', style: caption),
      const SizedBox(height: 10),
      RadioGroup<WheelLayout>(
        groupValue: _layout,
        onChanged: (v) => setState(() => _layout = v!),
        child: Column(
          children: [
            for (final layout in WheelLayout.values)
              RadioListTile<WheelLayout>(
                contentPadding: EdgeInsets.zero,
                // On its side every row of height counts.
                visualDensity: landscape ? VisualDensity.compact : null,
                value: layout,
                title: Text(layout.label, style: const TextStyle(fontSize: 14)),
                subtitle: Text(
                  layout.wheels,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ),
          ],
        ),
      ),
      _artwork(context),
      if (_losing > 0)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '$_losing assigned ${_losing == 1 ? 'wheel' : 'wheels'} will be '
            'unassigned, because this shape does not have them.',
            style: const TextStyle(fontSize: 12.5, color: HealthColors.watch),
          ),
        ),
    ];
    final buttons = Row(
      children: [
        if (_editing)
          TextButton.icon(
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text('Remove'),
            style: TextButton.styleFrom(foregroundColor: HealthColors.alert),
          ),
        const Spacer(),
        FilledButton(onPressed: _save, child: Text(_editing ? 'Save' : 'Add')),
      ],
    );

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        Space.margin,
        4,
        Space.margin,
        Space.xl + MediaQuery.viewInsetsOf(context).bottom,
      ),
      // On its side, stacked, the button was two screens down. Side by side
      // the whole form fits: the name on the left, then the shape and the
      // button that finishes the job on the right, where the eye ends up.
      child: landscape
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      title,
                      const SizedBox(height: Space.l),
                      name,
                    ],
                  ),
                ),
                const SizedBox(width: Space.xl),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ...shape,
                      const SizedBox(height: Space.l),
                      buttons,
                    ],
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                title,
                const SizedBox(height: Space.l),
                name,
                const SizedBox(height: Space.xl),
                ...shape,
                const SizedBox(height: Space.xl),
                buttons,
              ],
            ),
    );
  }
}
