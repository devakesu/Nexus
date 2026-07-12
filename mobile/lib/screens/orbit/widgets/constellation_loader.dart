import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:nexus/theme/app_colors.dart';

class ConstellationLoader extends StatefulWidget {
  const ConstellationLoader({
    required this.themeColor,
    this.label = 'ALIGNING CONSTELLATIONS',
    super.key,
  });

  final Color themeColor;
  final String label;

  @override
  State<ConstellationLoader> createState() => _ConstellationLoaderState();
}

class _ConstellationLoaderState extends State<ConstellationLoader>
    with TickerProviderStateMixin {
  late final AnimationController _ring1; // 3 dots CW  3.2 s
  late final AnimationController _ring2; // 2 dots CCW 5.8 s
  late final AnimationController _ring3; // 1 dot  CW  9.0 s
  late final AnimationController _sweep; // radar sweep 4.0 s
  late final AnimationController _pulse; // center glow  2.0 s
  late final AnimationController _twinkle; // bg stars  1.4 s
  late final AnimationController _dots; // ellipsis   0.9 s

  // Null until the first didChangeDependencies pass resolves the platform's
  // reduced-motion preference; see _applyMotionPreference.
  bool? _reduceMotion;

  @override
  void initState() {
    super.initState();
    _ring1 = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );
    _ring2 = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5800),
    );
    _ring3 = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 9000),
    );
    _sweep = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    );
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _twinkle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _dots = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion == _reduceMotion) return;
    _reduceMotion = reduceMotion;
    if (reduceMotion) {
      _ring1
        ..stop()
        ..value = 0;
      _ring2
        ..stop()
        ..value = 0;
      _ring3
        ..stop()
        ..value = 0;
      _sweep
        ..stop()
        ..value = 0;
      _pulse
        ..stop()
        ..value = 0.5;
      _twinkle
        ..stop()
        ..value = 0.5;
      _dots
        ..stop()
        ..value = 0;
    } else {
      unawaited(_ring1.repeat());
      unawaited(_ring2.repeat());
      unawaited(_ring3.repeat());
      unawaited(_sweep.repeat());
      unawaited(_pulse.repeat(reverse: true));
      unawaited(_twinkle.repeat(reverse: true));
      unawaited(_dots.repeat());
    }
  }

  @override
  void dispose() {
    _ring1.dispose();
    _ring2.dispose();
    _ring3.dispose();
    _sweep.dispose();
    _pulse.dispose();
    _twinkle.dispose();
    _dots.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = _reduceMotion ?? false;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 210,
          height: 210,
          child: AnimatedBuilder(
            animation: Listenable.merge([
              _ring1,
              _ring2,
              _ring3,
              _sweep,
              _pulse,
              _twinkle,
            ]),
            builder: (context, _) => CustomPaint(
              painter: _ConstellationPainter(
                themeColor: widget.themeColor,
                ring1Angle: _ring1.value * 2 * math.pi,
                ring2Angle: -_ring2.value * 2 * math.pi,
                ring3Angle: _ring3.value * 2 * math.pi,
                sweepAngle: _sweep.value * 2 * math.pi,
                pulseValue: _pulse.value,
                twinkleValue: _twinkle.value,
              ),
              child: Center(
                child: () {
                  final icon = Icon(
                    Icons.auto_awesome_rounded,
                    color: widget.themeColor,
                    size: 26,
                  );
                  if (reduceMotion) return icon;
                  return icon
                      .animate(onPlay: (c) => c.repeat(reverse: true))
                      .scale(
                        begin: const Offset(0.88, 0.88),
                        end: const Offset(1.16, 1.16),
                        duration: 2.seconds,
                        curve: Curves.easeInOut,
                      );
                }(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 28),
        _AligningText(
          themeColor: widget.themeColor,
          dotsController: _dots,
          label: widget.label,
          reduceMotion: reduceMotion,
        ),
      ],
    );
  }
}

// ─── Animated "ALIGNING CONSTELLATIONS" + cycling dots ────────────────────────

class _AligningText extends StatelessWidget {
  const _AligningText({
    required this.themeColor,
    required this.dotsController,
    required this.label,
    required this.reduceMotion,
  });

  final Color themeColor;
  final AnimationController dotsController;
  final String label;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final glow = AppColors.tint(themeColor, 0.4);
    final labelText = Text(
      label,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.88),
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 2.8,
      ),
    );
    final animatedLabel = reduceMotion
        ? labelText
        : labelText
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .fade(
                begin: 0.45,
                end: 1,
                duration: 1600.ms,
                curve: Curves.easeInOut,
              );

    if (reduceMotion) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          animatedLabel,
          const SizedBox(width: 6),
          Text(
            '...',
            style: TextStyle(
              color: glow.withValues(alpha: 0.9),
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
        ],
      );
    }

    return AnimatedBuilder(
      animation: dotsController,
      builder: (context, _) {
        final dotCount = (dotsController.value * 3).floor() + 1;
        final dots = '•' * dotCount + ' ' * (3 - dotCount);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            animatedLabel,
            const SizedBox(width: 6),
            Text(
              dots,
              style: TextStyle(
                color: glow.withValues(alpha: 0.9),
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─── CustomPainter ─────────────────────────────────────────────────────────────

class _ConstellationPainter extends CustomPainter {
  _ConstellationPainter({
    required this.themeColor,
    required this.ring1Angle,
    required this.ring2Angle,
    required this.ring3Angle,
    required this.sweepAngle,
    required this.pulseValue,
    required this.twinkleValue,
  });

  final Color themeColor;
  final double ring1Angle;
  final double ring2Angle;
  final double ring3Angle;
  final double sweepAngle;
  final double pulseValue;
  final double twinkleValue;

  // Brightened variant of themeColor used for low-alpha glows/lines/rings
  // drawn on the near-black backdrop — Friends/Professional's mode colors
  // are dark by design (calibrated for text-on-white contrast, see
  // DESIGN.md), so at low alpha over black they'd otherwise wash out next
  // to Dating's much brighter pink.
  Color get glow => AppColors.tint(themeColor, 0.4);

  static const _r1 = 36.0;
  static const _r2 = 58.0;
  static const _r3 = 80.0;

  // Fixed background star positions (as fractions of canvas size)
  static const _stars = [
    (0.10, 0.15, 1.1, 0.00),
    (0.88, 0.12, 1.4, 0.30),
    (0.05, 0.75, 0.9, 0.60),
    (0.93, 0.70, 1.2, 0.10),
    (0.20, 0.92, 1.0, 0.50),
    (0.80, 0.90, 0.8, 0.80),
    (0.14, 0.45, 1.3, 0.20),
    (0.86, 0.40, 1.1, 0.70),
    (0.50, 0.04, 1.0, 0.40),
    (0.48, 0.96, 0.9, 0.15),
    (0.30, 0.06, 1.2, 0.65),
    (0.70, 0.08, 0.8, 0.35),
    (0.03, 0.32, 1.0, 0.55),
    (0.97, 0.28, 1.3, 0.25),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final center = Offset(cx, cy);
    final paint = Paint()..isAntiAlias = true;

    // ── Background stars ───────────────────────────────────────────────────
    for (final (fx, fy, sz, phase) in _stars) {
      final pos = Offset(fx * size.width, fy * size.height);
      final t = math.sin((twinkleValue + phase) * math.pi);
      final alpha = (t * 0.4 + 0.35).clamp(0.0, 1.0);
      paint.color = Colors.white.withValues(alpha: alpha);
      canvas.drawCircle(pos, sz, paint);
      if (sz > 1.1 && t > 0.8) {
        paint.color = Colors.white.withValues(alpha: (t - 0.8) * 1.8);
        final fl = sz * 2.5;
        canvas
          ..drawLine(pos.translate(-fl, 0), pos.translate(fl, 0), paint)
          ..drawLine(pos.translate(0, -fl), pos.translate(0, fl), paint);
      }
    }

    // ── Center glow pulse ─────────────────────────────────────────────────
    paint
      ..color = glow.withValues(alpha: 0.09 + pulseValue * 0.08)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
    canvas.drawCircle(center, 20 + pulseValue * 7, paint);
    paint.maskFilter = null;

    // ── Radar sweep ───────────────────────────────────────────────────────
    _drawRadarSweep(canvas, center, _r3 + 12, paint);

    // ── Dashed orbit rings ────────────────────────────────────────────────
    _drawDashedRing(
      canvas,
      center,
      _r1,
      glow.withValues(alpha: 0.22),
      dashLen: 5,
      gapLen: 9,
    );
    _drawDashedRing(
      canvas,
      center,
      _r2,
      glow.withValues(alpha: 0.15),
      dashLen: 7,
      gapLen: 13,
    );
    _drawDashedRing(
      canvas,
      center,
      _r3,
      glow.withValues(alpha: 0.10),
      dashLen: 9,
      gapLen: 17,
    );

    // ── Compute orbiting dot positions ────────────────────────────────────
    final r1Dots = List.generate(3, (i) => ring1Angle + i * 2 * math.pi / 3);
    final r2Dots = List.generate(2, (i) => ring2Angle + i * math.pi);
    final r3Dots = [ring3Angle];

    final r1Positions = r1Dots.map((a) => _dotPos(center, _r1, a)).toList();
    final r2Positions = r2Dots.map((a) => _dotPos(center, _r2, a)).toList();
    final r3Positions = r3Dots.map((a) => _dotPos(center, _r3, a)).toList();

    // ── Constellation lines ───────────────────────────────────────────────
    _drawConstellationLines(
      canvas,
      r1Positions,
      r2Positions,
      r3Positions,
      paint,
    );

    // ── Comet tails + dots ────────────────────────────────────────────────
    for (var i = 0; i < r1Dots.length; i++) {
      _drawCometDot(canvas, center, _r1, r1Dots[i], 4.2, true, paint);
    }
    for (var i = 0; i < r2Dots.length; i++) {
      _drawCometDot(canvas, center, _r2, r2Dots[i], 4.8, false, paint);
    }
    _drawCometDot(canvas, center, _r3, r3Dots[0], 3.6, true, paint);
  }

  // ── Radar sweep (soft glowing wedge) ─────────────────────────────────────
  void _drawRadarSweep(Canvas canvas, Offset center, double maxR, Paint paint) {
    const sweepSpan = math.pi / 5; // 36° wedge
    const tailLength = math.pi / 2; // 90° tail fades out

    // Glowing tail arc
    final tailPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..isAntiAlias = true;

    const steps = 12;
    for (var i = 0; i < steps; i++) {
      final frac = i / steps;
      final startAngle = sweepAngle - tailLength * (1 - frac);
      final alpha = frac * 0.18;
      tailPaint.color = glow.withValues(alpha: alpha);
      canvas
        ..drawArc(
          Rect.fromCircle(center: center, radius: maxR * 0.62),
          startAngle,
          tailLength / steps,
          false,
          tailPaint,
        )
        ..drawArc(
          Rect.fromCircle(center: center, radius: maxR * 0.38),
          startAngle,
          tailLength / steps,
          false,
          tailPaint,
        );
    }

    // Leading edge glow
    paint
      ..color = glow.withValues(alpha: 0.22)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: maxR * 0.55),
      sweepAngle - sweepSpan / 2,
      sweepSpan,
      false,
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    paint
      ..maskFilter = null
      ..style = PaintingStyle.fill;
  }

  // ── Dashed orbit ring ─────────────────────────────────────────────────────
  void _drawDashedRing(
    Canvas canvas,
    Offset center,
    double radius,
    Color color, {
    required double dashLen,
    required double gapLen,
  }) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..isAntiAlias = true;

    final circumference = 2 * math.pi * radius;
    final total = dashLen + gapLen;
    final count = (circumference / total).floor();
    if (count <= 0) return;
    final dashArc = (dashLen / total) * (2 * math.pi / count);
    final gapArc = (gapLen / total) * (2 * math.pi / count);

    var angle = 0.0;
    for (var i = 0; i < count; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        angle,
        dashArc,
        false,
        paint,
      );
      angle += dashArc + gapArc;
    }
  }

  // ── Single dot position ───────────────────────────────────────────────────
  Offset _dotPos(Offset center, double radius, double angle) => Offset(
    center.dx + radius * math.cos(angle),
    center.dy + radius * math.sin(angle),
  );

  // ── Orbiting dot with comet tail ──────────────────────────────────────────
  void _drawCometDot(
    Canvas canvas,
    Offset center,
    double radius,
    double angle,
    double dotR,
    bool clockwise,
    Paint paint,
  ) {
    const tailCount = 5;
    const tailStep = 0.22; // radians per tail segment
    for (var t = tailCount; t >= 1; t--) {
      final tailAngle = clockwise ? angle - t * tailStep : angle + t * tailStep;
      final pos = _dotPos(center, radius, tailAngle);
      final frac = 1 - t / (tailCount + 1);
      paint.color = glow.withValues(alpha: frac * 0.2);
      canvas.drawCircle(pos, dotR * frac * 0.55, paint);
    }

    final pos = _dotPos(center, radius, angle);

    // Glow halo
    paint
      ..color = glow.withValues(alpha: 0.28)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawCircle(pos, dotR + 2, paint);

    // White core
    paint
      ..color = Colors.white.withValues(alpha: 0.95)
      ..maskFilter = null;
    canvas.drawCircle(pos, dotR * 0.55, paint);

    // Colored inner dot
    paint.color = themeColor;
    canvas.drawCircle(pos, dotR * 0.32, paint);
  }

  // ── Constellation lines ───────────────────────────────────────────────────
  void _drawConstellationLines(
    Canvas canvas,
    List<Offset> r1,
    List<Offset> r2,
    List<Offset> r3,
    Paint paint,
  ) {
    final linePaint = Paint()
      ..color = glow.withValues(alpha: 0.13)
      ..strokeWidth = 0.7
      ..isAntiAlias = true;

    // r1 → nearest r2
    for (final p1 in r1) {
      final nearest = r2.reduce(
        (a, b) => (a - p1).distance < (b - p1).distance ? a : b,
      );
      canvas.drawLine(p1, nearest, linePaint);
    }
    // r2 → nearest r3
    for (final p3 in r3) {
      final nearest = r2.reduce(
        (a, b) => (a - p3).distance < (b - p3).distance ? a : b,
      );
      canvas.drawLine(p3, nearest, linePaint);
    }
  }

  @override
  bool shouldRepaint(_ConstellationPainter old) =>
      old.ring1Angle != ring1Angle ||
      old.ring2Angle != ring2Angle ||
      old.ring3Angle != ring3Angle ||
      old.sweepAngle != sweepAngle ||
      old.pulseValue != pulseValue ||
      old.twinkleValue != twinkleValue;
}
