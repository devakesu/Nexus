import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:nexus/theme/app_colors.dart';

class FuturisticBackgroundPainter extends CustomPainter {
  const FuturisticBackgroundPainter({this.accentColor});

  /// When provided, the orbit/star palette is derived from this color
  /// instead of the default cyan/pink/indigo triad, so each tab can carry
  /// its own accent while reusing the same futuristic motif.
  final Color? accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    const gridAlpha = 0.08;

    final Color primaryOrbitColor;
    final Color secondaryOrbitColor;
    final Color tertiaryOrbitColor;
    final accent = accentColor;
    if (accent != null) {
      final hsl = HSLColor.fromColor(accent);
      primaryOrbitColor = hsl
          .withSaturation(0.75)
          .withLightness(0.42)
          .toColor();
      secondaryOrbitColor = hsl
          .withHue((hsl.hue + 40) % 360)
          .withSaturation(0.70)
          .withLightness(0.48)
          .toColor();
      tertiaryOrbitColor = hsl
          .withHue((hsl.hue - 40 + 360) % 360)
          .withSaturation(0.65)
          .withLightness(0.45)
          .toColor();
    } else {
      primaryOrbitColor = AppColors.primaryTeal;
      secondaryOrbitColor = const Color(0xFFE91E63);
      tertiaryOrbitColor = const Color(0xFF4F46E5);
    }

    const lineAlpha = 0.16;
    const glowAlpha = 0.12;
    const starAlpha = 0.40;

    // 1. Grid/Matrix Coordinate Dots
    final dotPaint = Paint()
      ..color = Colors.black.withValues(alpha: gridAlpha * 0.8)
      ..style = PaintingStyle.fill;

    const spacing = 45.0;
    for (var x = spacing / 2; x < size.width; x += spacing) {
      for (var y = spacing / 2; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.2, dotPaint);
      }
    }

    final center = Offset(size.width * 0.5, size.height * 0.12);

    // 2. Radial Telemetry Rays (Faint rays from center coordinate)
    final rayPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.02)
      ..strokeWidth = 0.8;
    const rayCount = 12;
    const angleStep = (2 * 3.1415926535) / rayCount;
    for (var i = 0; i < rayCount; i++) {
      final angle = i * angleStep;
      canvas.drawLine(
        center,
        Offset(
          center.dx +
              size.height *
                  0.8 *
                  double.parse(center.dx.sign.toString()) *
                  0.5 +
              300 * math.cos(angle),
          center.dy + size.height * 0.8 + 300 * math.sin(angle),
        ),
        rayPaint,
      );
    }

    // 3. Multi-colored Cosmic Orbits (Concentric dashed circles)
    final colors = [
      primaryOrbitColor,
      secondaryOrbitColor,
      tertiaryOrbitColor,
      primaryOrbitColor,
    ];
    final radii = [110.0, 230.0, 350.0, 480.0];

    for (var r = 0; r < radii.length; r++) {
      final radius = radii[r];
      final orbitPaint = Paint()
        ..color = colors[r].withValues(alpha: lineAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;

      // Draw dashed circle
      const dashCount = 80;
      const sweepAngle = (2 * 3.1415926535) / dashCount;
      for (var i = 0; i < dashCount; i++) {
        if (i.isEven) {
          canvas.drawArc(
            Rect.fromCircle(center: center, radius: radius),
            i * sweepAngle,
            sweepAngle,
            false,
            orbitPaint,
          );
        }
      }
    }

    // 4. Constellations & Star Coordinate Nodes
    final pathPaint = Paint()
      ..color = secondaryOrbitColor.withValues(alpha: lineAlpha * 1.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final starPaint = Paint()
      ..color = primaryOrbitColor.withValues(alpha: starAlpha)
      ..style = PaintingStyle.fill;

    final starGlowPaint = Paint()
      ..color = primaryOrbitColor.withValues(alpha: glowAlpha)
      ..style = PaintingStyle.fill;

    final nodes = [
      Offset(size.width * 0.12, size.height * 0.25),
      Offset(size.width * 0.26, size.height * 0.40),
      Offset(size.width * 0.08, size.height * 0.58),
      Offset(size.width * 0.88, size.height * 0.28),
      Offset(size.width * 0.74, size.height * 0.45),
      Offset(size.width * 0.90, size.height * 0.62),
      Offset(size.width * 0.20, size.height * 0.78),
      Offset(size.width * 0.38, size.height * 0.88),
    ];

    // Connect constellations
    canvas
      ..drawLine(nodes[0], nodes[1], pathPaint)
      ..drawLine(nodes[1], nodes[2], pathPaint)
      ..drawLine(nodes[3], nodes[4], pathPaint)
      ..drawLine(nodes[4], nodes[5], pathPaint)
      ..drawLine(nodes[6], nodes[7], pathPaint);

    // Draw nodes
    for (final node in nodes) {
      canvas
        ..drawCircle(node, 8, starGlowPaint) // Outer glow ring
        ..drawCircle(node, 3.5, starPaint); // Core coordinate star
    }

    // 5. Technical Corner Brackets (Corner design elements)
    final bracketPaint = Paint()
      ..color = tertiaryOrbitColor.withValues(alpha: lineAlpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    const bracketSize = 14.0;
    const margin = 12.0;

    // Top Left & Right Brackets
    canvas
      ..drawLine(
        const Offset(margin, margin),
        const Offset(margin + bracketSize, margin),
        bracketPaint,
      )
      ..drawLine(
        const Offset(margin, margin),
        const Offset(margin, margin + bracketSize),
        bracketPaint,
      )
      ..drawLine(
        Offset(size.width - margin, margin),
        Offset(size.width - margin - bracketSize, margin),
        bracketPaint,
      )
      ..drawLine(
        Offset(size.width - margin, margin),
        Offset(size.width - margin, margin + bracketSize),
        bracketPaint,
      );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    if (oldDelegate is FuturisticBackgroundPainter) {
      return oldDelegate.accentColor != accentColor;
    }
    return true;
  }
}
