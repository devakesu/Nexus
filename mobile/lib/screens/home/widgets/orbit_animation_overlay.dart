import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class OrbitAnimationOverlay extends StatelessWidget {
  const OrbitAnimationOverlay({
    required this.orbitName,
    required this.orbitColor,
    super.key,
  });

  final String orbitName;
  final Color orbitColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withAlpha(230),
      width: double.infinity,
      height: double.infinity,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                // Outer rotating ring
                Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: orbitColor.withAlpha(51),
                      width: 3,
                    ),
                    shape: BoxShape.circle,
                  ),
                )
                    .animate(onPlay: (controller) => controller.repeat())
                    .rotate(duration: 8.seconds),

                // Mid rotating ring
                Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: orbitColor.withAlpha(102),
                      width: 2,
                    ),
                    shape: BoxShape.circle,
                  ),
                )
                    .animate(onPlay: (controller) => controller.repeat())
                    .rotate(duration: 5.seconds, begin: 1, end: 0),

                // Pulsing central node
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: orbitColor.withAlpha(26),
                    shape: BoxShape.circle,
                    border: Border.all(color: orbitColor, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: orbitColor.withAlpha(127),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Icon(
                    LucideIcons.globe,
                    color: orbitColor,
                    size: 36,
                  ),
                )
                    .animate(
                      onPlay: (controller) => controller.repeat(reverse: true),
                    )
                    .scale(
                      begin: const Offset(0.85, 0.85),
                      end: const Offset(1.15, 1.15),
                      duration: 1.2.seconds,
                      curve: Curves.easeInOut,
                    ),

                // Orbiting satellites
                Positioned(
                  top: 30,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: orbitColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                )
                    .animate(onPlay: (controller) => controller.repeat())
                    .rotate(duration: 3.seconds),
              ],
            ),
            const SizedBox(height: 48),
            Text(
              'Opening $orbitName Orbit...',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 1.2,
              ),
            ).animate().fadeIn(duration: 500.ms).slideY(begin: 0.2, end: 0),
            const SizedBox(height: 12),
            Text(
              'Aligning signals and mapping paths',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withAlpha(127),
              ),
            ).animate().fadeIn(delay: 400.ms),
          ],
        ),
      ),
    );
  }
}
