import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The perforated speaker grille from the cabinet front.
///
/// Drawn rather than shipped as an image so it stays crisp at any size and can
/// take its colours from the theme. Used at low opacity behind the now-playing
/// panel, where it reads as texture rather than decoration.
class GrillePainter extends CustomPainter {
  const GrillePainter({
    required this.perforation,
    this.spacing = 9.0,
    this.radius = 1.6,
    this.opacity = 1.0,
  });

  final Color perforation;
  final double spacing;
  final double radius;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = perforation.withValues(alpha: perforation.a * opacity)
      ..isAntiAlias = true;

    // Offset every other row by half a step - the real grille is a staggered
    // matrix, not a square one.
    var row = 0;
    for (var y = spacing / 2; y < size.height; y += spacing) {
      final xOffset = row.isEven ? 0.0 : spacing / 2;
      for (var x = spacing / 2 + xOffset; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
      row++;
    }
  }

  @override
  bool shouldRepaint(GrillePainter old) =>
      old.perforation != perforation ||
      old.spacing != spacing ||
      old.radius != radius ||
      old.opacity != opacity;
}

/// Convenience wrapper: a grille panel with a soft vignette, as if lit from
/// the front left like the product photo.
class GrillePanel extends StatelessWidget {
  const GrillePanel({
    super.key,
    required this.perforation,
    this.opacity = 1.0,
    this.child,
  });

  final Color perforation;
  final double opacity;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: GrillePainter(perforation: perforation, opacity: opacity),
      child: child,
    );
  }
}

/// A thin brushed-metal separator, echoing the trim between cabinet and grille.
class CabinetSeam extends StatelessWidget {
  const CabinetSeam({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    final base = color ?? Theme.of(context).colorScheme.outlineVariant;
    return Container(
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [base.withValues(alpha: 0), base, base.withValues(alpha: 0)],
          stops: const [0, 0.5, 1],
        ),
      ),
    );
  }
}

/// Small helper for the tick marks around the volume knob.
Offset polarOffset(Offset center, double radius, double radians) => Offset(
  center.dx + radius * math.cos(radians),
  center.dy + radius * math.sin(radians),
);
