import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'grille.dart';

/// The orange knob, made turnable.
///
/// Grab the rim and it tracks the angle of your finger around the centre,
/// accumulating the delta - so it behaves like real hardware: you can spin
/// past the edge of the widget and keep turning. Grab the middle, where the
/// angle is too unstable to steer by, and it acts as a fader instead: right
/// and up to raise, left and down to lower. Either way it responds, which is
/// the whole point - a control that ignores half the ways you touch it reads
/// as a readout, not a knob.
class VolumeKnob extends StatefulWidget {
  const VolumeKnob({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.accent,
    this.size = 132,
    this.enabled = true,
    this.muted = false,
  });

  /// 0-100.
  final int value;
  final ValueChanged<int> onChanged;
  final ValueChanged<int>? onChangeEnd;
  final Color? accent;
  final double size;
  final bool enabled;
  final bool muted;

  @override
  State<VolumeKnob> createState() => _VolumeKnobState();
}

class _VolumeKnobState extends State<VolumeKnob> {
  /// 270 degrees of travel, leaving a gap at the bottom like a real dial.
  static const _sweep = math.pi * 1.5;
  static const _startAngle = math.pi * 0.75; // bottom-left

  double? _lastAngle;
  double _accumulated = 0;
  bool _dragging = false;

  /// Where the finger first touched down, before the drag threshold was met.
  Offset? _downLocal;

  /// Grabbing the middle steers the knob like a fader; grabbing the rim turns
  /// it. The choice is made once, from the touch-down point, and held for the
  /// whole gesture. Deciding it per-event meant a drag out from the centre
  /// flipped into rotary mode partway - and pulling straight outwards is
  /// radial motion, which changes the angle almost not at all, so the knob
  /// sat there doing nothing.
  bool _linearMode = false;

  double get _knobRadius => widget.size / 2;

  /// Inside this radius the angle is too unstable to steer by. It is never a
  /// place where the knob stops responding: the centre is the most inviting
  /// part to grab, so a grip there gets fader behaviour instead of nothing.
  double get _deadZone => _knobRadius * 0.34;

  Offset _vectorFromCentre(Offset local) =>
      local - Offset(_knobRadius, _knobRadius);

  void _onPanDown(DragDownDetails d) => _downLocal = d.localPosition;

  void _onPanStart(DragStartDetails d) {
    if (!widget.enabled) return;

    // Judge the grip from the touch-down point, not from here: the drag
    // threshold has already carried the pointer ~18px away by the time this
    // fires, far enough to leave the centre and misread a middle grab.
    final origin = _vectorFromCentre(_downLocal ?? d.localPosition);
    final current = _vectorFromCentre(d.localPosition);

    setState(() {
      _dragging = true;
      _accumulated = widget.value.toDouble();
      _linearMode = origin.distance <= _deadZone;
      _lastAngle = _linearMode ? null : math.atan2(current.dy, current.dx);
    });
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (!widget.enabled || !_dragging) return;

    final double next;

    if (_linearMode) {
      // Right and up turn it up, left and down turn it down.
      final step = (d.delta.dx - d.delta.dy) * 0.35;
      next = (_accumulated + step).clamp(0.0, 100.0);
    } else {
      final v = _vectorFromCentre(d.localPosition);
      // Too close to the centre to read an angle from; wait for the finger to
      // come back out rather than lurching.
      if (v.distance <= _deadZone * 0.5) return;

      final angle = math.atan2(v.dy, v.dx);
      if (_lastAngle == null) {
        _lastAngle = angle;
        return;
      }
      // Shortest signed difference, so crossing the -pi/pi seam doesn't jump.
      var delta = angle - _lastAngle!;
      if (delta > math.pi) delta -= math.pi * 2;
      if (delta < -math.pi) delta += math.pi * 2;
      _lastAngle = angle;
      next = (_accumulated + (delta / _sweep) * 100).clamp(0.0, 100.0);
    }

    if (next.round() != _accumulated.round()) {
      // A soft tick at each step - the closest we get to a detent.
      HapticFeedback.selectionClick();
      widget.onChanged(next.round());
    }
    setState(() => _accumulated = next);
  }

  void _onPanEnd(DragEndDetails _) {
    if (!_dragging) return;
    setState(() {
      _dragging = false;
      _lastAngle = null;
      _downLocal = null;
    });
    widget.onChangeEnd?.call(widget.value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = widget.accent ?? theme.colorScheme.primary;

    // Volume must stay reachable without a rotary gesture. Flutter requires
    // increased/decreasedValue alongside value whenever those actions exist -
    // omitting them trips an assertion as soon as a screen reader attaches.
    final stepUp = (widget.value + 5).clamp(0, 100);
    final stepDown = (widget.value - 5).clamp(0, 100);

    return Semantics(
      label: 'Volume',
      slider: true,
      value: '${widget.value} percent',
      increasedValue: '$stepUp percent',
      decreasedValue: '$stepDown percent',
      onIncrease: widget.enabled ? () => widget.onChanged(stepUp) : null,
      onDecrease: widget.enabled ? () => widget.onChanged(stepDown) : null,
      child: GestureDetector(
        // The cabinet is pinned outside the scrolling station list, so nothing
        // competes for this drag any more. Opaque hit-testing is still needed:
        // without it the detector defers to its children, and a drag starting
        // on the centre readout arrives with localPosition measured from the
        // Text rather than from the knob, so every angle comes out wrong.
        behavior: HitTestBehavior.opaque,
        onPanDown: _onPanDown,
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            painter: _KnobPainter(
              value: widget.value / 100,
              accent: accent,
              scheme: theme.colorScheme,
              startAngle: _startAngle,
              sweep: _sweep,
              active: _dragging,
              enabled: widget.enabled,
              muted: widget.muted,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.muted ? '—' : '${widget.value}',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: widget.enabled
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                      fontWeight: FontWeight.w600,
                      letterSpacing: -1,
                    ),
                  ),
                  Text(
                    'VOLUME',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      letterSpacing: 1.6,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _KnobPainter extends CustomPainter {
  const _KnobPainter({
    required this.value,
    required this.accent,
    required this.scheme,
    required this.startAngle,
    required this.sweep,
    required this.active,
    required this.enabled,
    required this.muted,
  });

  final double value;
  final Color accent;
  final ColorScheme scheme;
  final double startAngle;
  final double sweep;
  final bool active;
  final bool enabled;
  final bool muted;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    final trackRadius = radius - 6;
    final dim = enabled ? 1.0 : 0.4;

    // Tick marks around the travel, denser than the value steps so the dial
    // reads as an instrument rather than a progress bar.
    final tickPaint = Paint()
      ..color = scheme.onSurfaceVariant.withValues(alpha: 0.45 * dim)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    const tickCount = 28;
    for (var i = 0; i <= tickCount; i++) {
      final t = i / tickCount;
      final a = startAngle + sweep * t;
      final long = i % 7 == 0;
      canvas.drawLine(
        polarOffset(center, trackRadius + 1, a),
        polarOffset(center, trackRadius + (long ? 7 : 4), a),
        tickPaint,
      );
    }

    // Unfilled travel.
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = scheme.outlineVariant.withValues(alpha: dim);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: trackRadius - 8),
      startAngle,
      sweep,
      false,
      trackPaint,
    );

    // Filled travel, in the accent.
    if (value > 0 && !muted) {
      final fillPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = active ? 5 : 3.5
        ..strokeCap = StrokeCap.round
        ..color = accent.withValues(alpha: dim);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: trackRadius - 8),
        startAngle,
        sweep * value,
        false,
        fillPaint,
      );
    }

    // The knob body: a shallow vertical gradient, lighter at the top, the way
    // the machined cap catches the light in the photo.
    final bodyRadius = trackRadius - 18;
    final bodyRect = Rect.fromCircle(center: center, radius: bodyRadius);
    canvas.drawCircle(
      center.translate(0, 2),
      bodyRadius,
      Paint()
        ..color = scheme.shadow.withValues(alpha: 0.18 * dim)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(
      center,
      bodyRadius,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(scheme.surfaceContainerHighest, Colors.white, 0.16)!,
            scheme.surfaceContainerHigh,
          ],
        ).createShader(bodyRect),
    );
    canvas.drawCircle(
      center,
      bodyRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = scheme.outlineVariant.withValues(alpha: 0.8 * dim),
    );

    // Knurling around the rim. Real knobs are milled like this so fingers can
    // grip them, and that is precisely the cue that says "turn me" - without
    // it the dial reads as a gauge showing a number back at you.
    final knurlPaint = Paint()
      ..color = scheme.onSurfaceVariant.withValues(
        alpha: (active ? 0.5 : 0.32) * dim,
      )
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    const knurlCount = 36;
    for (var i = 0; i < knurlCount; i++) {
      final a = (math.pi * 2 / knurlCount) * i;
      canvas.drawLine(
        polarOffset(center, bodyRadius - 7, a),
        polarOffset(center, bodyRadius - 2, a),
        knurlPaint,
      );
    }

    // The pointer: the one part that is unmistakably orange.
    final pointerAngle = startAngle + sweep * value;
    canvas.drawLine(
      polarOffset(center, bodyRadius * 0.52, pointerAngle),
      polarOffset(center, bodyRadius - 5, pointerAngle),
      Paint()
        ..color = (muted ? scheme.onSurfaceVariant : accent).withValues(
          alpha: dim,
        )
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_KnobPainter old) =>
      old.value != value ||
      old.accent != accent ||
      old.active != active ||
      old.enabled != enabled ||
      old.muted != muted ||
      old.scheme != scheme;
}
