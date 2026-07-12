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
  });

  final List<OrbitNode> nodes;
  final Color themeColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (nodes.isEmpty) return;
    final center = Offset(size.width / 2, size.height / 2);
    final baseColor = AppColors.tint(themeColor, 0.3);
    const maxRadius = 450.0;

    // Lines from center to each node, fading with distance so the closest
    // (best) matches read as more strongly "connected" than distant ones,
    // instead of a flat-alpha line to every node competing equally.
    final centerPaint = Paint()
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    for (final node in nodes) {
      final nodePos = Offset(center.dx + node.x, center.dy + node.y);
      final distance = math.sqrt(node.x * node.x + node.y * node.y);
      final proximity = (1 - (distance / maxRadius)).clamp(0.0, 1.0);
      final alpha = (0.04 + proximity * 0.10).clamp(0.03, 0.14);
      canvas.drawLine(
        center,
        nodePos,
        centerPaint..color = baseColor.withValues(alpha: alpha),
      );
    }

    // Lines between nearby nodes — tighter radius and a lower alpha ceiling
    // than the center lines, since this is the O(n^2) mesh that produces the
    // densest crossing web at higher node counts.
    final meshPaint = Paint()
      ..color = baseColor.withValues(alpha: 0.06)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    const maxDistSq = 115.0 * 115.0;
    for (var i = 0; i < nodes.length; i++) {
      final p1 = Offset(center.dx + nodes[i].x, center.dy + nodes[i].y);

      for (var j = i + 1; j < nodes.length; j++) {
        final p2 = Offset(center.dx + nodes[j].x, center.dy + nodes[j].y);

        final dx = p1.dx - p2.dx;
        final dy = p1.dy - p2.dy;
        if (dx * dx + dy * dy <= maxDistSq) {
          canvas.drawLine(p1, p2, meshPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant ConstellationLinesPainter oldDelegate) {
    return oldDelegate.nodes != nodes || oldDelegate.themeColor != themeColor;
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
