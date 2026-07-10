import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:nexus/theme/app_colors.dart';

/// 1. Nexus Orbit Loader (Google Sign-In Loading Animation)
/// Features a central core with three colorful nodes (Dating, Friends, Pro)
/// orbiting in distinct elliptical paths with glow effects.
///
/// [lightMode] swaps white orbit rings / core for slate-toned equivalents so
/// the loader looks correct on light scaffold backgrounds.
class NexusOrbitLoader extends StatefulWidget {
  const NexusOrbitLoader({
    super.key,
    this.size = 80.0,
    this.lightMode = false,
  });

  final double size;
  final bool lightMode;

  @override
  State<NexusOrbitLoader> createState() => _NexusOrbitLoaderState();
}

class _NexusOrbitLoaderState extends State<NexusOrbitLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );
    unawaited(_controller.repeat());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _OrbitPainter(
              progress: _controller.value,
              lightMode: widget.lightMode,
            ),
          );
        },
      ),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter({required this.progress, this.lightMode = false});

  final double progress;
  final bool lightMode;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    final paintOrbit = Paint()
      ..color = lightMode
          ? const Color(0xFF94A3B8).withValues(alpha: 0.2)
          : Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Orbit paths
    canvas
      ..drawCircle(center, maxRadius * 0.5, paintOrbit)
      ..drawCircle(center, maxRadius * 0.8, paintOrbit);

    // Central core - proportional to canvas size
    final corePulse =
        maxRadius * 0.1 + maxRadius * 0.05 * math.sin(progress * 2 * math.pi);
    final corePaint = Paint()
      ..color = lightMode ? const Color(0xFF334155) : Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, corePulse, corePaint);

    // Particle radii proportional to size, clamped to avoid overflow at tiny sizes.
    final p1r = (maxRadius * 0.125).clamp(1.5, 7.0);
    final p2r = (maxRadius * 0.163).clamp(1.5, 8.0);
    final p3r = (maxRadius * 0.100).clamp(1.5, 6.0);

    // Orbiting particle 1: Dating (Red) - Inner orbit
    final angle1 = progress * 2 * math.pi;
    final r1 = maxRadius * 0.5;
    final p1 = center + Offset(math.cos(angle1) * r1, math.sin(angle1) * r1);
    _drawGlowingParticle(canvas, p1, AppColors.pulsarPink, p1r);

    // Orbiting particle 2: Friends (Sunset Gold) - Middle orbit, counter-clockwise
    final angle2 = -progress * 2 * math.pi + (math.pi / 3);
    final r2 = maxRadius * 0.75;
    final p2 =
        center + Offset(math.cos(angle2) * r2, math.sin(angle2) * r2 * 0.8);
    _drawGlowingParticle(canvas, p2, const Color(0xFFFFB03A), p2r);

    // Orbiting particle 3: Pro (Neon Teal) - Outer orbit, faster
    final angle3 = progress * 3 * math.pi + (math.pi * 2 / 3);
    final r3 = maxRadius * 0.95;
    final p3 =
        center + Offset(math.cos(angle3) * r3 * 0.9, math.sin(angle3) * r3);
    _drawGlowingParticle(canvas, p3, AppColors.modeProfessional, p3r);
  }

  void _drawGlowingParticle(
    Canvas canvas,
    Offset position,
    Color color,
    double radius,
  ) {
    // Outer glow
    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(position, radius * 2.2, glowPaint);

    // Inner solid core
    final corePaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(position, radius, corePaint);
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.lightMode != lightMode;
}

/// 2. Identity Scan Loader (Central Biometric Pulse + Background Face Grid + Laser Sweep)
/// Designed specifically for the "Verifying your Identity..." gate.
class IdentityScanLoader extends StatefulWidget {
  const IdentityScanLoader({super.key});

  @override
  State<IdentityScanLoader> createState() => _IdentityScanLoaderState();
}

class _IdentityScanLoaderState extends State<IdentityScanLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _sweepController;

  @override
  void initState() {
    super.initState();
    _sweepController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );
    unawaited(_sweepController.repeat(reverse: true));
  }

  @override
  void dispose() {
    _sweepController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Background Matrix / Identity mesh
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _sweepController,
            builder: (context, child) {
              return CustomPaint(
                painter: _ScanBgPainter(
                  sweepProgress: _sweepController.value,
                ),
              );
            },
          ),
        ),

        // Centered Holographic Fingerprint / Shield pulse
        Center(
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.pulsarPink.withValues(alpha: 0.05),
              border: Border.all(
                color: AppColors.pulsarPink.withValues(alpha: 0.2),
              ),
            ),
            child:
                const Icon(
                      Icons.fingerprint_rounded,
                      color: AppColors.pulsarPink,
                      size: 56,
                    )
                    .animate(
                      onPlay: (controller) => controller.repeat(reverse: true),
                    )
                    .scale(
                      begin: const Offset(0.9, 0.9),
                      end: const Offset(1.1, 1.1),
                      duration: 1200.ms,
                      curve: Curves.easeInOut,
                    )
                  ..animate(
                    onPlay: (controller) => controller.repeat(),
                  ).shimmer(duration: 2000.ms, color: Colors.white24),
          ),
        ),
      ],
    );
  }
}

class _ScanBgPainter extends CustomPainter {
  _ScanBgPainter({required this.sweepProgress});

  final double sweepProgress;

  @override
  void paint(Canvas canvas, Size size) {
    final paintGrid = Paint()
      ..color = AppColors.pulsarPink.withValues(alpha: 0.03)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    // 1. Draw static background node-mesh grid
    const cols = 10;
    const rows = 18;
    final dx = size.width / (cols - 1);
    final dy = size.height / (rows - 1);

    for (var i = 0; i < cols; i++) {
      canvas.drawLine(
        Offset(i * dx, 0),
        Offset(i * dx, size.height),
        paintGrid,
      );
    }
    for (var j = 0; j < rows; j++) {
      canvas.drawLine(Offset(0, j * dy), Offset(size.width, j * dy), paintGrid);
    }

    // 2. Draw circular biometric scan target lines around the center
    final center = Offset(size.width / 2, size.height / 2);
    final paintCircles = Paint()
      ..color = AppColors.pulsarPink.withValues(alpha: 0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas
      ..drawCircle(center, 100, paintCircles)
      ..drawCircle(
        center,
        160,
        paintCircles..color = AppColors.pulsarPink.withValues(alpha: 0.04),
      );

    // Draw tech angle ticks around circles
    final tickPaint = Paint()
      ..color = AppColors.pulsarPink.withValues(alpha: 0.2)
      ..strokeWidth = 2.0;

    for (var angleDeg = 0; angleDeg < 360; angleDeg += 45) {
      final angle = angleDeg * math.pi / 180;
      final start = center + Offset(math.cos(angle) * 96, math.sin(angle) * 96);
      final end = center + Offset(math.cos(angle) * 104, math.sin(angle) * 104);
      canvas.drawLine(start, end, tickPaint);
    }

    // 3. Draw the vertical laser sweep line
    final laserY = sweepProgress * size.height;

    // Laser glow gradient
    final rect = Rect.fromLTRB(0, laserY - 15, size.width, laserY + 1);
    final laserGlow = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppColors.pulsarPink.withValues(alpha: 0),
          AppColors.pulsarPink.withValues(alpha: 0.15),
          AppColors.pulsarPink.withValues(alpha: 0.4),
        ],
      ).createShader(rect);

    canvas.drawRect(rect, laserGlow);

    // Solid laser core line
    final laserCore = Paint()
      ..color = AppColors.pulsarPink
      ..strokeWidth = 1.5
      ..imageFilter = null;

    canvas.drawLine(Offset(0, laserY), Offset(size.width, laserY), laserCore);
  }

  @override
  bool shouldRepaint(covariant _ScanBgPainter oldDelegate) {
    return oldDelegate.sweepProgress != sweepProgress;
  }
}
