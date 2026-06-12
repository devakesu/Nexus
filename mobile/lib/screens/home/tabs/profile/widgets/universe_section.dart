import 'package:flutter/material.dart';

class UniverseSection extends StatelessWidget {
  const UniverseSection({
    required this.icon,
    required this.title,
    required this.description,
    required this.child,
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const deepPurple = Color(0xFF7C3AED);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF161B26).withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: deepPurple.withValues(alpha: 0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: deepPurple.withValues(alpha: 0.05),
            blurRadius: 15,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: const Color(0xFFFF7597),
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFFE2D9F3),
                        fontSize: 15,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Outfit',
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}
