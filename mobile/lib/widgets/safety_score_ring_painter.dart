import 'dart:math' as math;

import 'package:flutter/material.dart';

// Progress ring used for the safety score and for an active check-in's
// remaining-time indicator.
class SafetyScoreRingPainter extends CustomPainter {
  SafetyScoreRingPainter({required this.progress});

  final double progress;

  static const _track = Color(0xFFE2E8F0);
  static const _teal = Color(0xFF0D9488);
  static const _accent = Color(0xFF0284C7);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;
    final trackPaint = Paint()
      ..color = _track
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);

    if (progress <= 0) return;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final progressPaint = Paint()
      ..shader = SweepGradient(
        colors: const [_accent, _teal, _accent],
        startAngle: -math.pi / 2,
        endAngle: -math.pi / 2 + math.pi * 2 * progress,
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant SafetyScoreRingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
