import 'package:flutter/material.dart';

import 'package:nexus/features/profile/widgets/futuristic_background_painter.dart';

/// Shared ambient background for the main tabs - reuses the Profile tab's
/// futuristic grid/orbit motif, tinted with each tab's own accent color.
class TabBackground extends StatelessWidget {
  const TabBackground({
    required this.accentColor,
    required this.child,
    super.key,
  });

  final Color accentColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Container(color: Theme.of(context).scaffoldBackgroundColor),
        ),
        Positioned.fill(
          child: CustomPaint(
            painter: FuturisticBackgroundPainter(accentColor: accentColor),
          ),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.8, -0.7),
                radius: 1.2,
                colors: [
                  accentColor.withAlpha(26),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.9, 0.9),
                radius: 1.3,
                colors: [
                  accentColor.withAlpha(15),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
