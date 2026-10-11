import 'package:flutter/material.dart';

import '../treel/model.dart';
import 'theme.dart';

/// Editing what "correct" means for this vehicle.
class SettingsSheet extends StatefulWidget {
  const SettingsSheet({
    super.key,
    required this.layout,
    required this.spec,
    required this.onChanged,
    required this.haptics,
    required this.animations,
    required this.onHaptics,
    required this.onAnimations,
  });

  /// What wheels this vehicle has. A motorcycle has no spare, and offering
  /// a target pressure for one invites someone to set a number that can
  /// never apply to anything.
  final WheelLayout layout;

  final PressureSpec spec;
  final ValueChanged<PressureSpec> onChanged;
  final bool haptics;
  final bool animations;
  final ValueChanged<bool> onHaptics;
  final ValueChanged<bool> onAnimations;

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  late PressureSpec _spec = widget.spec;

  void _update(PressureSpec next) {
    setState(() => _spec = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final twoWheeler = widget.layout == WheelLayout.motorcycle;
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height * 1.2;

    final target = <Widget>[
      Text('Target pressure', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      Text(
        twoWheeler
            ? 'Cold pressure from the manufacturer\'s plate, usually on '
                  'the swingarm or under the seat.'
            : 'Cold pressure from the door placard. The spare is often '
                  'set higher or lower than the road wheels.',
        style: TextStyle(
          fontSize: 12.5,
          color: Colors.white.withValues(alpha: 0.55),
        ),
      ),
      const SizedBox(height: 12),
      _Stepper(
        label: twoWheeler ? 'Front wheel' : 'Front axle',
        value: _spec.front,
        suffix: 'psi',
        min: 15,
        max: 60,
        onChanged: (v) => _update(_spec.copyWith(front: v)),
      ),
      _Stepper(
        label: twoWheeler ? 'Rear wheel' : 'Rear axle',
        value: _spec.rear,
        suffix: 'psi',
        min: 15,
        max: 60,
        onChanged: (v) => _update(_spec.copyWith(rear: v)),
      ),
      if (widget.layout.hasSpare)
        _Stepper(
          label: 'Spare',
          value: _spec.spare,
          suffix: 'psi',
          min: 15,
          max: 60,
          onChanged: (v) => _update(_spec.copyWith(spare: v)),
        ),
    ];
    final tolerance = <Widget>[
      Text('Tolerance', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      Text(
        'Deliberately lopsided. Losing pressure is what ruins tyres, '
        'while heat alone adds a couple of psi on any decent drive — '
        'a 13 °C rise is worth about 2 psi — so the upper bound has to '
        'be loose or it cries wolf after every trip.',
        style: TextStyle(
          fontSize: 12.5,
          color: Colors.white.withValues(alpha: 0.55),
        ),
      ),
      const SizedBox(height: 12),
      _Stepper(
        label: 'Watch if under by',
        value: _spec.underWatch,
        suffix: 'psi',
        min: 1,
        max: 20,
        accent: HealthColors.watch,
        onChanged: (v) => _update(
          _spec.copyWith(
            underWatch: v,
            underAlert: v >= _spec.underAlert ? v + 1 : null,
          ),
        ),
      ),
      _Stepper(
        label: 'Alert if under by',
        value: _spec.underAlert,
        suffix: 'psi',
        min: 2,
        max: 25,
        accent: HealthColors.alert,
        onChanged: (v) => _update(
          _spec.copyWith(
            underAlert: v,
            underWatch: v <= _spec.underWatch ? v - 1 : null,
          ),
        ),
      ),
      const SizedBox(height: 8),
      _Stepper(
        label: 'Watch if over by',
        value: _spec.overWatch,
        suffix: 'psi',
        min: 1,
        max: 25,
        accent: HealthColors.watch,
        onChanged: (v) => _update(
          _spec.copyWith(
            overWatch: v,
            overAlert: v >= _spec.overAlert ? v + 1 : null,
          ),
        ),
      ),
      _Stepper(
        label: 'Alert if over by',
        value: _spec.overAlert,
        suffix: 'psi',
        min: 2,
        max: 30,
        accent: HealthColors.alert,
        onChanged: (v) => _update(
          _spec.copyWith(
            overAlert: v,
            overWatch: v <= _spec.overWatch ? v - 1 : null,
          ),
        ),
      ),
    ];
    final preview = <Widget>[
      _Preview(spec: _spec, hasSpare: widget.layout.hasSpare),
    ];
    final feel = <Widget>[
      Text('Feel', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: widget.haptics,
        onChanged: widget.onHaptics,
        title: const Text('Haptics', style: TextStyle(fontSize: 14)),
        subtitle: Text(
          'A small tap the first time each tyre reports after opening',
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.5),
          ),
        ),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: widget.animations,
        onChanged: widget.onAnimations,
        title: const Text('Animations', style: TextStyle(fontSize: 14)),
        // When Android's own switch has already stopped everything,
        // say so: otherwise this one looks broken.
        subtitle: Text(
          MediaQuery.disableAnimationsOf(context)
              ? 'Off for now: "Remove animations" is on in Android\'s '
                    'accessibility settings'
              : 'Readings change without movement when off',
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.5),
          ),
        ),
      ),
    ];

    Widget column(List<Widget> children) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        // On its side the phone has width and no height: three columns
        // instead of one, so the whole sheet is most of a screen rather than
        // three of them. Targets first, then the tolerance that applies to
        // them, then what that will look like and how the app should feel.
        child: landscape
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: column(target)),
                  const SizedBox(width: 24),
                  Expanded(child: column(tolerance)),
                  const SizedBox(width: 24),
                  Expanded(
                    child: column([
                      ...preview,
                      const SizedBox(height: 18),
                      ...feel,
                    ]),
                  ),
                ],
              )
            : column([
                ...target,
                const SizedBox(height: 24),
                ...tolerance,
                const SizedBox(height: 18),
                ...preview,
                const SizedBox(height: 24),
                ...feel,
              ]),
      ),
    );
  }
}

/// Spelling out the bands in real numbers, so the settings above are not
/// abstract arithmetic.
class _Preview extends StatelessWidget {
  const _Preview({required this.spec, required this.hasSpare});
  final PressureSpec spec;
  final bool hasSpare;

  @override
  Widget build(BuildContext context) {
    Widget row(String label, int target) {
      final alertLo = target - spec.underAlert;
      final watchLo = target - spec.underWatch;
      final watchHi = target + spec.overWatch;
      final alertHi = target + spec.overAlert;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            SizedBox(
              width: 58,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
            ),
            Expanded(
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _Chip('≤$alertLo', HealthColors.alert),
                  _Chip('${alertLo + 1}–$watchLo', HealthColors.watch),
                  _Chip('${watchLo + 1}–${watchHi - 1}', HealthColors.ok),
                  _Chip('$watchHi–${alertHi - 1}', HealthColors.watch),
                  _Chip('≥$alertHi', HealthColors.alert),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What you will see',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.45),
            ),
          ),
          const SizedBox(height: 8),
          row('Front', spec.front),
          row('Rear', spec.rear),
          if (hasSpare) row('Spare', spec.spare),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 11, color: color, fontFeatures: steadyDigits),
    ),
  );
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.suffix,
    required this.min,
    required this.max,
    required this.onChanged,
    this.accent,
  });

  final String label;
  final int value;
  final String suffix;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              color: accent ?? Colors.transparent,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
          IconButton(
            onPressed: value > min ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove_circle_outline_rounded),
            visualDensity: VisualDensity.compact,
          ),
          SizedBox(
            width: 30,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                fontFeatures: steadyDigits,
              ),
            ),
          ),
          IconButton(
            onPressed: value < max ? () => onChanged(value + 1) : null,
            icon: const Icon(Icons.add_circle_outline_rounded),
            visualDensity: VisualDensity.compact,
          ),
          // Sized for "psi". It was 82 wide from when the suffix read
          // "psi → watch", which left a dead gap after every number.
          SizedBox(
            width: 30,
            child: Text(
              suffix,
              style: TextStyle(
                fontSize: 11.5,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
