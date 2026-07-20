import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:nexus/screens/orbit_screen.dart';
import 'package:nexus/theme/app_colors.dart';

class CelestialBackgroundPainter extends CustomPainter {
  CelestialBackgroundPainter({
    required this.themeColor,
    required this.pulseValue,
  });

  final Color themeColor;
  final double pulseValue;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..isAntiAlias = true;
    final glow = AppColors.tint(themeColor, 0.3);

    // 0. Ambient Nebula Glow
    final nebulaPaint = Paint()
      ..shader =
          RadialGradient(
            colors: [
              themeColor.withValues(alpha: 0.04),
              themeColor.withValues(alpha: 0.01),
              Colors.transparent,
            ],
          ).createShader(
            Rect.fromCircle(center: center, radius: size.shortestSide * 0.8),
          );
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), nebulaPaint);

    // 1. Draw Starfield (Deterministic based on coordinates)
    for (var i = 0; i < 150; i++) {
      final x = (math.sin(i * 12345.67) * 0.5 + 0.5) * size.width;
      final y = (math.cos(i * 98765.43) * 0.5 + 0.5) * size.height;
      final starSize = (math.sin(i * 4567.89) * 0.5 + 0.5) * 1.8 + 0.4;

      // Twinkle animation
      final twinklePhase = math.sin(pulseValue * 2.0 * math.pi + i);
      final alpha = (twinklePhase * 0.4 + 0.6).clamp(0.1, 1.0);

      paint.color = Colors.white.withValues(alpha: alpha * 0.55);
      canvas.drawCircle(Offset(x, y), starSize, paint);

      // Occasional star flares for larger stars
      if (starSize > 1.8 && twinklePhase > 0.85) {
        paint.color = Colors.white.withValues(
          alpha: (twinklePhase - 0.85) * 2.0,
        );
        canvas
          ..drawLine(Offset(x - 4, y), Offset(x + 4, y), paint)
          ..drawLine(Offset(x, y - 4), Offset(x, y + 4), paint);
      }
    }

    // 1.5. Draw Shooting Stars (Meteors)
    final meteor1Progress = (pulseValue * 2.2) % 3.0;
    if (meteor1Progress < 1.0) {
      final startPos = Offset(size.width * 0.15, size.height * 0.2);
      final endPos = Offset(size.width * 0.8, size.height * 0.6);
      final currentPos = Offset.lerp(startPos, endPos, meteor1Progress)!;

      final meteorPaint = Paint()
        ..shader =
            LinearGradient(
              colors: [
                Colors.white.withValues(alpha: 0.65),
                Colors.transparent,
              ],
            ).createShader(
              Rect.fromPoints(
                currentPos,
                Offset.lerp(currentPos, startPos, 0.12)!,
              ),
            )
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(
        currentPos,
        Offset.lerp(currentPos, startPos, 0.12)!,
        meteorPaint,
      );
    }

    final meteor2Progress = ((pulseValue + 0.4) * 2.2) % 3.0;
    if (meteor2Progress < 1.0) {
      final startPos = Offset(size.width * 0.85, size.height * 0.15);
      final endPos = Offset(size.width * 0.35, size.height * 0.7);
      final currentPos = Offset.lerp(startPos, endPos, meteor2Progress)!;

      final meteorPaint = Paint()
        ..shader =
            LinearGradient(
              colors: [Colors.white.withValues(alpha: 0.5), Colors.transparent],
            ).createShader(
              Rect.fromPoints(
                currentPos,
                Offset.lerp(currentPos, startPos, 0.15)!,
              ),
            )
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(
        currentPos,
        Offset.lerp(currentPos, startPos, 0.15)!,
        meteorPaint,
      );
    }

    // 2. High-Tech Grid Coordinate Rings & Crosshairs
    final gridPaint = Paint()
      ..color = glow.withValues(alpha: 0.08)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Cardinal axis lines
    canvas
      ..drawLine(
        Offset(0, center.dy),
        Offset(size.width, center.dy),
        gridPaint,
      )
      ..drawLine(
        Offset(center.dx, 0),
        Offset(center.dx, size.height),
        gridPaint,
      );

    // Diagonal coordinate sweeps
    final diagonalPaint = Paint()
      ..color = glow.withValues(alpha: 0.03)
      ..strokeWidth = 0.8;
    canvas
      ..drawLine(
        Offset.zero,
        Offset(size.width, size.height),
        diagonalPaint,
      )
      ..drawLine(
        Offset(size.width, 0),
        Offset(0, size.height),
        diagonalPaint,
      );

    // 3. Tick marks on cardinal lines
    for (var r = 100.0; r <= 600.0; r += 100.0) {
      canvas
        ..drawCircle(
          Offset(center.dx + r, center.dy),
          2,
          paint..color = glow.withValues(alpha: 0.35),
        )
        ..drawCircle(Offset(center.dx - r, center.dy), 2, paint)
        ..drawCircle(Offset(center.dx, center.dy + r), 2, paint)
        ..drawCircle(Offset(center.dx, center.dy - r), 2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CelestialBackgroundPainter oldDelegate) {
    return oldDelegate.pulseValue != pulseValue ||
        oldDelegate.themeColor != themeColor;
  }
}

class ConstellationLinesPainter extends CustomPainter {
  ConstellationLinesPainter({
    required this.nodes,
    required this.themeColor,
    this.pulseValue = 0.0,
  });

  final List<OrbitNode> nodes;
  final Color themeColor;
  final double pulseValue;

  @override
  void paint(Canvas canvas, Size size) {
    if (nodes.isEmpty) return;
    final center = Offset(size.width / 2, size.height / 2);
    const maxRadius = 450.0;

    // Draw circular orbit lines centered at canvas center for each node's distance.
    // Deduplicate distances to avoid painting overlapping circles twice.
    final uniqueDistances = nodes
        .map((node) => math.sqrt(node.x * node.x + node.y * node.y))
        .toSet();

    // Use extremely faint white lines for the orbit tracks to sit quietly in the background
    const orbitColor = Colors.white;
    for (final distance in uniqueDistances) {
      final proximity = (1 - (distance / maxRadius)).clamp(0.0, 1.0);
      final alpha = (0.14 + proximity * 0.08).clamp(0.03, 0.22);

      final orbitPaint = Paint()
        ..color = orbitColor.withValues(alpha: alpha)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(center, distance, orbitPaint);
    }

    // Lines from center to a subset of nodes (Option C)
    // Deterministically select 1 in 3 nodes to anchor the constellation without creating a crowded sunburst.
    final centerPaint = Paint()
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    for (final node in nodes) {
      final nodePos = Offset(center.dx + node.x, center.dy + node.y);
      final distance = math.sqrt(node.x * node.x + node.y * node.y);
      final proximity = (1 - (distance / maxRadius)).clamp(0.0, 1.0);
      final alpha = (0.18 + proximity * 0.18).clamp(0.09, 0.30);

      if (node.id.hashCode % 3 == 0) {
        canvas.drawLine(
          center,
          nodePos,
          centerPaint..color = themeColor.withValues(alpha: alpha * 0.45),
        );
      }

      // Draw traveling comet pulse along the connection line (Option C)
      final offset = (node.id.hashCode.abs() % 100) / 100.0;
      final progress = (pulseValue + offset) % 1.0;
      final pulsePos = Offset.lerp(center, nodePos, progress)!;

      // Pulse fades in/out smoothly along the line trajectory
      final pulseAlpha = math.sin(progress * math.pi) * (0.2 + proximity * 0.5);
      final pulseAlphaVal = pulseAlpha.clamp(0.0, 1.0);

      if (pulseAlphaVal > 0.05) {
        final glowColor = AppColors.tint(themeColor, 0.6);
        final glowPaint = Paint()
          ..color = glowColor.withValues(alpha: pulseAlphaVal * 0.45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3)
          ..isAntiAlias = true;

        final corePaint = Paint()
          ..color = Colors.white.withValues(alpha: pulseAlphaVal * 0.9)
          ..isAntiAlias = true;

        // 1. Glow Halo & 2. White Core (Option C)
        canvas
          ..drawCircle(pulsePos, 4.5, glowPaint)
          ..drawCircle(pulsePos, 1.8, corePaint);
      }
    }

    // Lines between nearby nodes to form constellations (connecting each node to its 2 nearest neighbors)
    final meshPaint = Paint()
      ..color = themeColor.withValues(alpha: 0.22)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    for (var i = 0; i < nodes.length; i++) {
      final p1 = Offset(center.dx + nodes[i].x, center.dy + nodes[i].y);

      // Find distances to all other nodes
      final targets = <({int index, double distance})>[];
      for (var j = 0; j < nodes.length; j++) {
        if (i == j) continue;
        final p2 = Offset(center.dx + nodes[j].x, center.dy + nodes[j].y);
        targets.add((index: j, distance: (p1 - p2).distance));
      }

      // Sort by distance and connect to the 2 nearest neighbors
      targets.sort((a, b) => a.distance.compareTo(b.distance));

      final connectionsCount = math.min(2, targets.length);
      for (var k = 0; k < connectionsCount; k++) {
        final neighborIndex = targets[k].index;
        if (i < neighborIndex) {
          final p2 = Offset(
            center.dx + nodes[neighborIndex].x,
            center.dy + nodes[neighborIndex].y,
          );
          canvas.drawLine(p1, p2, meshPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant ConstellationLinesPainter oldDelegate) {
    return oldDelegate.nodes != nodes ||
        oldDelegate.themeColor != themeColor ||
        oldDelegate.pulseValue != pulseValue;
  }
}

class OrbitGridPainter extends CustomPainter {
  OrbitGridPainter({
    required this.themeColor,
    required this.sweepValue,
  });

  final Color themeColor;
  final double sweepValue;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final glow = AppColors.tint(themeColor, 0.3);
    final gridPaint = Paint()
      ..color = glow.withValues(alpha: 0.08)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Cardinal axis lines
    canvas
      ..drawLine(
        Offset(0, center.dy),
        Offset(size.width, center.dy),
        gridPaint,
      )
      ..drawLine(
        Offset(center.dx, 0),
        Offset(center.dx, size.height),
        gridPaint,
      );

    // Diagonal coordinate sweeps
    final diagonalPaint = Paint()
      ..color = glow.withValues(alpha: 0.03)
      ..strokeWidth = 0.8;
    canvas
      ..drawLine(
        Offset.zero,
        Offset(size.width, size.height),
        diagonalPaint,
      )
      ..drawLine(
        Offset(size.width, 0),
        Offset(0, size.height),
        diagonalPaint,
      );

    // Tick marks on cardinal lines
    final paint = Paint()..isAntiAlias = true;
    for (var r = 100.0; r <= 600.0; r += 100.0) {
      canvas
        ..drawCircle(
          Offset(center.dx + r, center.dy),
          2,
          paint..color = glow.withValues(alpha: 0.35),
        )
        ..drawCircle(Offset(center.dx - r, center.dy), 2, paint)
        ..drawCircle(Offset(center.dx, center.dy + r), 2, paint)
        ..drawCircle(Offset(center.dx, center.dy - r), 2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant OrbitGridPainter oldDelegate) {
    return oldDelegate.themeColor != themeColor ||
        oldDelegate.sweepValue != sweepValue;
  }
}

class DashedOrbitRingPainter extends CustomPainter {
  DashedOrbitRingPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..isAntiAlias = true;

    final radius = size.width / 2;
    final center = Offset(size.width / 2, size.height / 2);

    // Draw 12 segment dashes
    final dashLength = (2 * math.pi * radius) / 24;
    final dashArc = (dashLength / (2 * math.pi * radius)) * 2 * math.pi;

    for (var i = 0; i < 12; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        i * 2 * dashArc,
        dashArc,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant DashedOrbitRingPainter oldDelegate) =>
      oldDelegate.color != color;
}
