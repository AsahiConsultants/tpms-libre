import 'package:flutter/material.dart';

import '../treel/model.dart';
import 'theme.dart';

/// Tread, drawn hard enough to actually see.
class _TreadPainter extends CustomPainter {
  const _TreadPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    final inset = size.height * 0.12;
    for (var i = 1; i <= 4; i++) {
      final x = size.width * i / 5;
      canvas.drawLine(Offset(x, inset), Offset(x, size.height - inset), paint);
    }
  }

  @override
  bool shouldRepaint(_TreadPainter old) => old.color != color;
}

/// One wheel: its reading, its health, and how much to trust it.
///
/// Carries its position. The label was dropped once, when every card sat at
/// its own corner of a car drawn from above and saying "FL" as well told you
/// nothing the layout had not. Every vehicle now shows its readings in a row
/// beneath a picture, where the row order is the only other clue, so the
/// label is doing real work again.
class TyreCard extends StatelessWidget {
  const TyreCard({
    super.key,
    required this.state,
    required this.spec,
    required this.width,
    required this.height,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.animate = true,
    this.waking = false,
  });

  final TyreState state;
  final PressureSpec spec;
  final double width;
  final double height;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final bool animate;

  /// Just came live. Shown for a beat alongside the haptic, so the tap has
  /// something to point at.
  final bool waking;

  @override
  Widget build(BuildContext context) {
    // The app's own switch, and Android's "Remove animations" on top of it:
    // someone who has asked their whole phone to stop moving should not
    // have to ask this app separately.
    final motion = animate && !MediaQuery.disableAnimationsOf(context);
    final health = state.health(spec);
    final accent = HealthColors.of(health);
    final reading = state.reading;
    final small = width < 86;
    final radius = BorderRadius.circular(width * 0.30);

    // A reading fades as it ages, so a twenty-minute-old number never looks
    // as convincing as one that just arrived.
    final trust = state.hasReading ? 0.45 + 0.55 * state.freshness : 1.0;

    return Semantics(
      label:
          '${state.position.label}, '
          '${reading == null ? 'no sensor' : '${reading.psi} psi, '
                    '${reading.celsius} degrees, ${shortAge(state.age)}'}',
      button: true,
      child: AnimatedContainer(
        duration: Duration(milliseconds: motion ? 260 : 0),
        curve: Curves.easeOutCubic,
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF32383F), Color(0xFF191D23)],
          ),
          border: Border.all(
            color: selected
                ? Colors.white
                : waking
                ? Color.lerp(accent, Colors.white, 0.65)!
                : accent.withValues(alpha: state.hasReading ? 0.85 : 0.30),
            width: selected || waking ? 2.6 : 1.8,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
            if (waking)
              BoxShadow(
                color: accent.withValues(alpha: 0.55),
                blurRadius: 26,
                spreadRadius: 3,
              )
            else if (selected || health == TyreHealth.alert)
              BoxShadow(
                color: (selected ? Colors.white : accent).withValues(
                  alpha: 0.3,
                ),
                blurRadius: 20,
                spreadRadius: 1,
              ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            borderRadius: radius,
            // A tap with no response reads as broken before it reads as
            // minimal.
            splashColor: accent.withValues(alpha: 0.18),
            highlightColor: Colors.white.withValues(alpha: 0.05),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _TreadPainter(
                      Colors.black.withValues(alpha: 0.14),
                    ),
                  ),
                ),
                // Which wheel this is. It was dropped once, when every card
                // sat at its own corner of a drawing of a car and the
                // position was obvious from where the card was. It is not
                // obvious any more: a vehicle with its own artwork puts all
                // the readings in a row underneath, and a rotation is a list
                // of instructions naming wheels.
                Positioned(
                  top: height * 0.07,
                  child: Text(
                    state.position.short,
                    style: TextStyle(
                      fontSize: small ? 8 : 9,
                      letterSpacing: 1.3,
                      height: 1,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.38),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(
                    left: width * 0.08,
                    right: width * 0.08,
                    // Leaves the label its own air, so the reading stays
                    // optically centred rather than sitting under a lid.
                    top: height * 0.20,
                    bottom: height * 0.08,
                  ),
                  // Never overflow, whatever the system text scale is. The
                  // diagram has a hard size budget; the detail sheet is
                  // where full text scaling applies.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: reading == null
                        ? _Empty(assigned: state.assigned, small: small)
                        : Opacity(
                            opacity: trust,
                            child: _Reading(
                              psi: reading.psi,
                              celsius: reading.celsius,
                              age: shortAge(state.age),
                              stale: state.stale,
                              small: small,
                              animate: motion,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Reading extends StatelessWidget {
  const _Reading({
    required this.psi,
    required this.celsius,
    required this.age,
    required this.stale,
    required this.small,
    required this.animate,
  });

  final int psi;
  final int celsius;
  final String age;
  final bool stale;
  final bool small;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    // The pressure is the one thing anyone actually watches, so it is the
    // one thing that moves. Everything else on the card holds still.
    Widget number = Text(
      '$psi',
      key: ValueKey(psi),
      style: TextStyle(
        fontSize: small ? 26 : 32,
        fontWeight: FontWeight.w600,
        height: 1.0,
        fontFeatures: steadyDigits,
      ),
    );
    if (animate) {
      number = AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.28),
              end: Offset.zero,
            ).animate(anim),
            child: child,
          ),
        ),
        child: number,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            number,
            const SizedBox(width: 2),
            Padding(
              padding: const EdgeInsets.only(bottom: 2.5),
              child: Text(
                'psi',
                style: TextStyle(
                  fontSize: 9,
                  color: Colors.white.withValues(alpha: 0.45),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '$celsius°C',
          style: TextStyle(
            fontSize: small ? 11 : 12.5,
            color: Colors.white.withValues(alpha: 0.55),
            fontFeatures: steadyDigits,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          age,
          maxLines: 1,
          style: TextStyle(
            fontSize: small ? 8.5 : 9.5,
            color: Colors.white.withValues(alpha: stale ? 0.6 : 0.33),
            fontStyle: stale ? FontStyle.italic : null,
          ),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.assigned, required this.small});
  final bool assigned;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          assigned ? Icons.more_horiz_rounded : Icons.add_rounded,
          size: small ? 22 : 26,
          color: Colors.white.withValues(alpha: 0.28),
        ),
        const SizedBox(height: 3),
        Text(
          assigned ? 'waiting' : 'assign',
          style: TextStyle(
            fontSize: small ? 8.5 : 9.5,
            color: Colors.white.withValues(alpha: 0.33),
          ),
        ),
      ],
    );
  }
}
