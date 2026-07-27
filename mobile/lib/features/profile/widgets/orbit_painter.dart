import 'dart:math' as math;
import 'package:flutter/material.dart';

class OrbitPainter extends CustomPainter {
  OrbitPainter({required this.color, required this.progress});

  final Color color;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Draw background ring
    final paint = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(center, radius, paint);

    // Draw rotating dashed elements
    final dashedPaint = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final circumference = 2 * math.pi * radius;
    const double dashLength = 10;
    const double gapLength = 8;
    final sweepAngle = (dashLength / circumference) * 2 * math.pi;
    final gapAngle = (gapLength / circumference) * 2 * math.pi;

    final dashCount = (2 * math.pi / (sweepAngle + gapAngle)).floor();
    final rotationAngle = progress * 2 * math.pi;

    for (var i = 0; i < dashCount; i++) {
      final startAngle = rotationAngle + i * (sweepAngle + gapAngle);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        dashedPaint,
      );
    }

    // Draw 3 orbiting glowing nodes
    final nodePaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final shadowPaint = Paint()
      ..color = color.withValues(alpha: 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)
      ..style = PaintingStyle.fill;

    for (var i = 0; i < 3; i++) {
      final angle = rotationAngle + (i * 2 * math.pi / 3);
      final x = center.dx + radius * math.cos(angle);
      final y = center.dy + radius * math.sin(angle);
      final nodeOffset = Offset(x, y);

      // Shadow glow and main node
      canvas
        ..drawCircle(nodeOffset, 6, shadowPaint)
        ..drawCircle(nodeOffset, 3.5, nodePaint);
    }
  }

  @override
  bool shouldRepaint(covariant OrbitPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
