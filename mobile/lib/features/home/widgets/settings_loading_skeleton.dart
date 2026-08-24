import 'package:flutter/material.dart';

/// Shimmer skeleton shown while profile settings data loads.
/// Matches the shape of the Dating / Friends / Professional settings overlays.
class SettingsLoadingSkeleton extends StatelessWidget {
  const SettingsLoadingSkeleton({required this.themeColor, super.key});

  final Color themeColor;

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    return _Shimmer(
      child: Container(
        height: h * 0.85,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── Header row ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      _Bone(
                        width: 26,
                        height: 26,
                        radius: 6,
                        color: themeColor.withValues(alpha: 0.14),
                      ),
                      const SizedBox(width: 10),
                      const _Bone(width: 140, height: 22, radius: 6),
                    ],
                  ),
                  _Bone(
                    width: 72,
                    height: 36,
                    radius: 12,
                    color: themeColor.withValues(alpha: 0.14),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Orbit toggle card ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _card(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Bone(width: 110, height: 14, radius: 4),
                        SizedBox(height: 6),
                        _Bone(width: 170, height: 10, radius: 4),
                      ],
                    ),
                    _Bone(
                      width: 50,
                      height: 26,
                      radius: 13,
                      color: themeColor.withValues(alpha: 0.12),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // ── Who are you interested in ─────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _card(
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Bone(width: 160, height: 13, radius: 4),
                    SizedBox(height: 6),
                    _Bone(width: 220, height: 10, radius: 4),
                    SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _Bone(width: 60, height: 30, radius: 20),
                        _Bone(width: 72, height: 30, radius: 20),
                        _Bone(width: 88, height: 30, radius: 20),
                        _Bone(width: 76, height: 30, radius: 20),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // ── Looking for ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _card(
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Bone(width: 130, height: 13, radius: 4),
                    SizedBox(height: 6),
                    _Bone(width: 200, height: 10, radius: 4),
                    SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _Bone(width: 74, height: 30, radius: 20),
                        _Bone(width: 92, height: 30, radius: 20),
                        _Bone(width: 60, height: 30, radius: 20),
                        _Bone(width: 84, height: 30, radius: 20),
                        _Bone(width: 66, height: 30, radius: 20),
                        _Bone(width: 96, height: 30, radius: 20),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // ── Third section ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _card(
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Bone(width: 110, height: 13, radius: 4),
                    SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _Bone(width: 80, height: 30, radius: 20),
                        _Bone(width: 64, height: 30, radius: 20),
                        _Bone(width: 90, height: 30, radius: 20),
                        _Bone(width: 70, height: 30, radius: 20),
                        _Bone(width: 56, height: 30, radius: 20),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8EDF2)),
      ),
      child: child,
    );
  }
}

// ── Skeleton placeholder block ────────────────────────────────────────────────

class _Bone extends StatelessWidget {
  const _Bone({
    required this.width,
    required this.height,
    required this.radius,
    this.color,
  });

  final double width;
  final double height;
  final double radius;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color ?? const Color(0xFFE8EDF2),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

// ── Shimmer sweep that covers the entire skeleton ─────────────────────────────

class _Shimmer extends StatefulWidget {
  const _Shimmer({required this.child});
  final Widget child;

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    );
    _ctrl.repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      child: widget.child,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment(_ctrl.value * 3 - 1.5, 0),
          end: Alignment(_ctrl.value * 3 - 0.8, 0),
          colors: [
            Colors.transparent,
            Colors.white.withValues(alpha: 0.55),
            Colors.transparent,
          ],
        ).createShader(bounds),
        child: child,
      ),
    );
  }
}
