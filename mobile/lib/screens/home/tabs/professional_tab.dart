import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/screens/home/widgets/tab_scaffold.dart';

class ProfessionalTab extends StatelessWidget {
  const ProfessionalTab({required this.onOpenOrbit, super.key});

  final void Function(String, Color) onOpenOrbit;

  @override
  Widget build(BuildContext context) {
    const themeColor = Color(0xFF00F5D4);
    return TabScaffold(
      title: 'Professional',
      themeColor: themeColor,
      chatLabel: 'Professional',
      onOpenOrbitPressed: () => onOpenOrbit('Professional', themeColor),
      children: [
        const Text(
          'Career & Projects',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        Column(
          children: List.generate(2, (index) {
            final companies = ['Nexus Labs', 'Tech Innovations'];
            final roles = ['Flutter Developer', 'UI/UX Intern'];
            final periods = ['Jan 2026 - Present', 'Jun 2025 - Dec 2025'];
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF161B26),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withAlpha(13)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: themeColor.withAlpha(26),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(LucideIcons.briefcase, color: themeColor),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          roles[index],
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          companies[index],
                          style: TextStyle(
                            color: Colors.white.withAlpha(178),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          periods[index],
                          style: TextStyle(
                            color: Colors.white.withAlpha(102),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      ],
    );
  }
}
