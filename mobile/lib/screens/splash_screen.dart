// CustomPainter math calculations benefit from explicit double literals and nested canvas calls.
// ignore_for_file: prefer_int_literals, cascade_invocations
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nexus/theme/app_colors.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({
    required this.appName,
    required this.onAnimationComplete,
    super.key,
  });

  final String appName;
  final VoidCallback onAnimationComplete;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onAnimationComplete();
      }
    });

    unawaited(_controller.forward());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0D13), // Cosmic Obsidian base
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: CoordinatePainter(progress: _controller.value),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }
}

class CoordinatePainter extends CustomPainter {
  CoordinatePainter({required this.progress});

  final double progress; // 0.0 to 1.0

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.sqrt(center.dx * center.dx + center.dy * center.dy);

    // Define colors according to Aesthetic Philosophy
    const accentColor = AppColors.pulsarPink; // Pulsar Pink
    const whiteColor = Color(0xFFFFFFFF);
    const greyColor = Color(0xFF6B7280); // Muted Slate Grey

    // Phase Calculations
    // Frame 0: Drop pinpoint (0.0 to 0.2)
    // Frame 20 (Radius Sweep): Sweep circular vector (0.2 to 0.6)
    // Frame 60 (Handoff): Zoom out / resolve grid (0.6 to 1.0)

    var scale = 1.0;
    var gridOpacity = 0.0;

    if (progress > 0.6) {
      final zoomProgress = ((progress - 0.6) / 0.4).clamp(0.0, 1.0);
      // Zoom out smoothly backwards
      scale = 1 - (0.2 * Curves.easeInOutCubic.transform(zoomProgress));
      gridOpacity = Curves.easeOut.transform(zoomProgress);
    }

    canvas.save();
    // Translate to center and apply viewport scale
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);

    // Draw Grid Lines (Resolves/fades in during Frame 60 Zoom out)
    if (gridOpacity > 0) {
      final gridPaint = Paint()
        ..color = accentColor.withValues(alpha: 0.06 * gridOpacity)
        ..strokeWidth = 0.5;

      const gridSpacing = 45;
      final halfW = size.width * 1.5; // wider area to cover zoom out
      final halfH = size.height * 1.5;

      for (var x = -halfW; x <= halfW; x += gridSpacing) {
        canvas.drawLine(Offset(x, -halfH), Offset(x, halfH), gridPaint);
      }
      for (var y = -halfH; y <= halfH; y += gridSpacing) {
        canvas.drawLine(Offset(-halfW, y), Offset(halfW, y), gridPaint);
      }
    }

    // Frame 0 (The Anchor): Glowing point coordinates vector drops directly in the mathematical center
    if (progress >= 0.0) {
      final anchorProgress = math
          .min(progress / 0.2, 1.0)
          .clamp(0.0, 1.0);
      final pointRadius = 2.5 * anchorProgress;

      // Inner sharp point
      final pointPaint = Paint()
        ..color = whiteColor.withValues(alpha: anchorProgress)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset.zero, pointRadius, pointPaint);

      // Glowing pulse outer ring
      final glowPaint = Paint()
        ..color = accentColor.withValues(alpha: 0.35 * anchorProgress)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(Offset.zero, pointRadius + 4, glowPaint);

      // Coordinate text animation: origin_x: 0.00, origin_y: 0.00
      if (anchorProgress > 0) {
        var xText = '0.00';
        var yText = '0.00';
        if (progress < 0.35) {
          // Dynamic coordinates to look like calculation/locking in
          final rand = math.Random((progress * 200).toInt());
          xText = (rand.nextDouble() * 20 - 10).toStringAsFixed(2);
          yText = (rand.nextDouble() * 20 - 10).toStringAsFixed(2);
        }

        final textSpan = TextSpan(
          text: 'origin_x: $xText, origin_y: $yText',
          style: GoogleFonts.jetBrainsMono(
            color: whiteColor.withValues(alpha: anchorProgress * 0.75),
            fontSize: 9,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w400,
          ),
        );
        final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        )..layout();
        textPainter.paint(canvas, const Offset(8, -16));
      }
    }

    // Frame 20 (The Radius Sweep): Thin, single-pixel vector ring path shoots out
    if (progress >= 0.2) {
      final sweepProgress = math
          .min((progress - 0.2) / 0.4, 1.0)
          .clamp(0.0, 1.0);
      final currentSweepRadius = sweepProgress * (maxRadius * 0.75);

      // Draw Orbit Tiers (threshold boundaries)
      final tierPaint = Paint()
        ..color = greyColor.withValues(alpha: 0.12 * sweepProgress)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5;

      final orbitTiers = [60, 120, 180];
      for (final tier in orbitTiers) {
        if (currentSweepRadius >= tier) {
          // Draw Orbit Tier circle
          canvas.drawCircle(Offset.zero, tier.toDouble(), tierPaint);

          // Draw orbital labels on first two tiers
          if (tier == 120) {
            final tierProgress = math
                .min((currentSweepRadius - tier) / 40, 1.0)
                .clamp(0.0, 1.0);
            final textSpan = TextSpan(
              text: '◉ ORBIT_TIER_02: BOUND_OK',
              style: GoogleFonts.jetBrainsMono(
                color: accentColor.withValues(alpha: 0.4 * tierProgress),
                fontSize: 6.5,
                letterSpacing: 1.2,
              ),
            );
            final textPainter = TextPainter(
              text: textSpan,
              textDirection: TextDirection.ltr,
            )..layout();
            textPainter.paint(canvas, Offset(-50, -tier.toDouble() - 10));
          }
        }
      }

      // Sweep vector ring path
      final sweepPaint = Paint()
        ..color = accentColor.withValues(alpha: (1 - sweepProgress) * 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawCircle(Offset.zero, currentSweepRadius, sweepPaint);

      // Fade-in text when sweep completes a decent path
      if (progress >= 0.4) {
        final textFadeProgress = math
            .min((progress - 0.4) / 0.25, 1.0)
            .clamp(0.0, 1.0);
        final textSpan = TextSpan(
          text: '[NEXUS_ENGINE_INITIALIZED]',
          style: GoogleFonts.jetBrainsMono(
            color: accentColor.withValues(alpha: textFadeProgress),
            fontSize: 9.5,
            fontWeight: FontWeight.bold,
            letterSpacing: 2.0,
          ),
        );
        final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        )..layout();
        textPainter.paint(canvas, Offset(-textPainter.width / 2, 40));
      }
    }

    // Bottom Coordinate Log: [x: -42.84, y: 112.50] -> Vector Identity Validated
    if (progress >= 0.5) {
      final logFade = math.min((progress - 0.5) / 0.2, 1.0).clamp(0.0, 1.0);
      final textSpan = TextSpan(
        text: '[x: -42.84, y: 112.50] -> Vector Identity Validated',
        style: GoogleFonts.jetBrainsMono(
          color: whiteColor.withValues(alpha: logFade * 0.45),
          fontSize: 8,
          letterSpacing: 0.5,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(-textPainter.width / 2, 65));
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CoordinatePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
