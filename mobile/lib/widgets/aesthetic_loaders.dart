import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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

    // Use slightly thicker and more visible orbit lines when large/full-page on light background
    final strokeWidth = 1.0 + (size.width > 50.0 ? 0.4 : 0.0);
    final paintOrbit = Paint()
      ..color = lightMode
          ? const Color(0xFF64748B).withValues(alpha: 0.38)
          : Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    // Orbit paths
    canvas
      ..drawCircle(center, maxRadius * 0.5, paintOrbit)
      ..drawCircle(center, maxRadius * 0.8, paintOrbit);

    // Central core - proportional to canvas size
    final corePulse =
        maxRadius * 0.1 + maxRadius * 0.05 * math.sin(progress * 2 * math.pi);
    final corePaint = Paint()
      ..color = lightMode ? const Color(0xFF1E293B) : Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, corePulse, corePaint);

    // Particle radii proportional to size, clamped to avoid overflow at tiny sizes.
    final p1r = (maxRadius * 0.125).clamp(1.5, 7.0);
    final p2r = (maxRadius * 0.163).clamp(1.5, 8.0);
    final p3r = (maxRadius * 0.100).clamp(1.5, 6.0);

    // Orbiting particle 1: Dating (Red/Rose) - Inner orbit
    // Use slightly deeper Rose for light backgrounds for distinct visibility
    final angle1 = progress * 2 * math.pi;
    final r1 = maxRadius * 0.5;
    final p1 = center + Offset(math.cos(angle1) * r1, math.sin(angle1) * r1);
    _drawGlowingParticle(
      canvas,
      p1,
      lightMode ? const Color(0xFFE11D48) : AppColors.pulsarPink,
      p1r,
    );

    // Orbiting particle 2: Friends (Sunset Gold/Amber) - Middle orbit, counter-clockwise
    // Use darker Amber on white background to avoid washing out
    final angle2 = -progress * 2 * math.pi + (math.pi / 3);
    final r2 = maxRadius * 0.75;
    final p2 =
        center + Offset(math.cos(angle2) * r2, math.sin(angle2) * r2 * 0.8);
    _drawGlowingParticle(
      canvas,
      p2,
      lightMode ? const Color(0xFFD97706) : const Color(0xFFFFB03A),
      p2r,
    );

    // Orbiting particle 3: Pro (Teal) - Outer orbit, faster
    // Use deep Teal on white background
    final angle3 = progress * 3 * math.pi + (math.pi * 2 / 3);
    final r3 = maxRadius * 0.95;
    final p3 =
        center + Offset(math.cos(angle3) * r3 * 0.9, math.sin(angle3) * r3);
    _drawGlowingParticle(
      canvas,
      p3,
      lightMode ? const Color(0xFF0D9488) : AppColors.modeProfessional,
      p3r,
    );
  }

  void _drawGlowingParticle(
    Canvas canvas,
    Offset position,
    Color color,
    double radius,
  ) {
    // Outer glow - slightly reduced alpha on light backgrounds to preserve core contrast
    final glowPaint = Paint()
      ..color = color.withValues(alpha: lightMode ? 0.15 : 0.3)
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

/// 2. Constellation Align Loader
/// Replaces the old biometric scan gate. Designed for the bootstrapping phase
/// where Nexus is locating and aligning the user's constellation in the
/// network. Features a twinkling starfield, expanding signal-ripple rings,
/// and the NexusOrbitLoader at center radiating soft glow. Cosmic, warm,
/// inviting - not a security checkpoint.
class ConstellationAlignLoader extends StatefulWidget {
  const ConstellationAlignLoader({super.key});

  @override
  State<ConstellationAlignLoader> createState() =>
      _ConstellationAlignLoaderState();
}

class _ConstellationAlignLoaderState extends State<ConstellationAlignLoader>
    with TickerProviderStateMixin {
  late AnimationController _rippleController;
  late AnimationController _twinkleController;
  late AnimationController _statusController;

  // Cycling status phrases rendered in JetBrains Mono below the orbit loader.
  static const _statusPhrases = [
    'locating your star...',
    'aligning constellation...',
    'mapping orbit path...',
    'syncing with the cosmos...',
    'almost there...',
  ];
  int _currentPhrase = 0;
  Timer? _phraseTimer;

  @override
  void initState() {
    super.initState();

    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );
    unawaited(_rippleController.repeat());

    _twinkleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    );
    unawaited(_twinkleController.repeat());

    _statusController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    // Cycle through status phrases every 2.5 s with a brief fade transition.
    _phraseTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      if (mounted) {
        unawaited(
          _statusController.forward(from: 0).then((_) {
            if (mounted) {
              setState(() {
                _currentPhrase = (_currentPhrase + 1) % _statusPhrases.length;
              });
              unawaited(_statusController.reverse());
            }
          }),
        );
      }
    });
  }

  @override
  void dispose() {
    _phraseTimer?.cancel();
    _rippleController.dispose();
    _twinkleController.dispose();
    _statusController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Layer 0: twinkling starfield
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _twinkleController,
            builder: (context, child) => CustomPaint(
              painter: _StarfieldPainter(
                twinkleProgress: _twinkleController.value,
              ),
            ),
          ),
        ),

        // Layer 1: expanding signal ripples
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _rippleController,
            builder: (context, child) => CustomPaint(
              painter: _RipplePainter(
                progress: _rippleController.value,
              ),
            ),
          ),
        ),

        // Layer 2: central orbit loader inside a soft pink radial glow
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Glow halo behind the orbit loader
              Stack(
                alignment: Alignment.center,
                children: [
                  // Outer soft glow bloom
                  Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          AppColors.pulsarPink.withValues(alpha: 0.15),
                          AppColors.pulsarPink.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                  // Orbit animation
                  const NexusOrbitLoader(size: 110),
                ],
              ),

              const SizedBox(height: 32),

              // Status text - fades between phrases
              AnimatedBuilder(
                animation: _statusController,
                builder: (context, child) {
                  // _statusController goes 0→1 on phrase-out, 1→0 on phrase-in.
                  // Opacity is low when controller value is high (mid-transition).
                  final opacity = (1.0 - _statusController.value).clamp(
                    0.0,
                    1.0,
                  );
                  return Opacity(
                    opacity: opacity,
                    child: Text(
                      _statusPhrases[_currentPhrase],
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 1.6,
                        color: AppColors.pulsarPink.withValues(alpha: 0.75),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Paints a field of ~90 stars at stable seeded positions. Each star's alpha
/// oscillates with a per-star phase offset derived from its index, producing a
/// natural asynchronous twinkle without any randomness on each frame.
class _StarfieldPainter extends CustomPainter {
  _StarfieldPainter({required this.twinkleProgress});

  final double twinkleProgress;

  // One-time seeded positions: generated lazily and cached across repaints.
  static List<_Star>? _stars;

  static List<_Star> _buildStars() {
    final rng = math.Random(0xC057A1C); // fixed seed - same starfield every run
    return List.generate(90, (i) {
      return _Star(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        // Radius in logical pixels: mostly tiny (0.8–1.8) with ~10% larger
        radius: rng.nextDouble() < 0.1
            ? 1.8 + rng.nextDouble() * 0.6
            : 0.8 + rng.nextDouble() * 1.0,
        phase: rng.nextDouble(), // twinkle phase offset 0–1
        speed: 0.4 + rng.nextDouble() * 0.6, // relative twinkle speed
      );
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    _stars ??= _buildStars();
    final stars = _stars!;
    final paint = Paint()..style = PaintingStyle.fill;

    for (final star in stars) {
      // Each star oscillates between dim and bright using its own phase.
      final t = (twinkleProgress * star.speed + star.phase) % 1.0;
      final brightness = 0.2 + 0.65 * math.sin(t * math.pi);
      paint.color = Colors.white.withValues(alpha: brightness.clamp(0.0, 1.0));
      canvas.drawCircle(
        Offset(star.x * size.width, star.y * size.height),
        star.radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StarfieldPainter old) =>
      old.twinkleProgress != twinkleProgress;
}

class _Star {
  const _Star({
    required this.x,
    required this.y,
    required this.radius,
    required this.phase,
    required this.speed,
  });

  final double x;
  final double y;
  final double radius;
  final double phase;
  final double speed;
}

/// Paints three concentric ripple rings that expand from the center and fade
/// out as they grow, staggered by 1/3 of the cycle so there's always a ring
/// in motion. Mimics a signal radiating outward through the constellation.
class _RipplePainter extends CustomPainter {
  _RipplePainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // Max radius reaches roughly to the corner so the outermost ring fills
    // the full screen before fading.
    final maxR =
        math.sqrt(
          center.dx * center.dx + center.dy * center.dy,
        ) *
        0.85;

    const ringCount = 3;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    for (var i = 0; i < ringCount; i++) {
      // Each ring is offset by 1/3 of the cycle.
      final t = (progress + i / ringCount) % 1.0;
      // Ease-out: ring accelerates at first, slows at the edge.
      final easedT = Curves.easeOut.transform(t);
      final radius = easedT * maxR;
      // Alpha fades from ~40% when small to 0% at the edge.
      final alpha = (1.0 - easedT) * 0.38;
      paint.color = AppColors.pulsarPink.withValues(alpha: alpha);
      canvas.drawCircle(center, radius.clamp(0.0, maxR), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RipplePainter old) => old.progress != progress;
}
