import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:nexus/config/app_config.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({required this.appName, super.key});

  final String appName;

  @override
  Widget build(BuildContext context) {
    final config = AppConfig.current;

    return Scaffold(
      backgroundColor: const Color(0xFF090D0F),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Container with subtle tech shadow containing flavor-specific logo
            Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(36),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x220D9488), // Clean tech teal glow
                    blurRadius: 40,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(36),
                child: Image.asset(
                  config.logoAssetPath,
                  fit: BoxFit.cover,
                ),
              ),
            )
                .animate()
                .fade(duration: 800.ms, curve: Curves.easeOut)
                .scale(
                  begin: const Offset(0.7, 0.7),
                  end: const Offset(1, 1),
                  duration: 900.ms,
                  curve: Curves.elasticOut,
                )
                .then(delay: 100.ms)
                .shimmer(
                  duration: 1000.ms,
                  color: const Color(0x33FFFFFF),
                ),
            const SizedBox(height: 35),
            // App Title Text
            Text(
              appName.toUpperCase(),
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: 6,
                color: Colors.white,
              ),
            )
                .animate()
                .fade(delay: 400.ms, duration: 600.ms)
                .slideY(
                  begin: 0.2,
                  end: 0,
                  duration: 600.ms,
                  curve: Curves.easeOut,
                ),
            const SizedBox(height: 10),
            // Subtitle
            const Text(
              'THE FUTURE OF CONNECTIVITY',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                letterSpacing: 4,
                color: Color(0x80FFFFFF),
              ),
            ).animate().fade(delay: 600.ms, duration: 600.ms),
          ],
        ),
      ),
    );
  }
}
