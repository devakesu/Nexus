import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/screens/home/widgets/tab_scaffold.dart';

class FriendsTab extends StatelessWidget {
  const FriendsTab({required this.onOpenOrbit, super.key});

  final void Function(String, Color) onOpenOrbit;

  @override
  Widget build(BuildContext context) {
    const themeColor = Color(0xFFFF9F1C);
    return TabScaffold(
      title: 'Friends',
      themeColor: themeColor,
      chatLabel: 'Friends',
      onOpenOrbitPressed: () => onOpenOrbit('Friends', themeColor),
      children: [
        const Text(
          'Active Hangouts',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        Column(
          children: List.generate(3, (index) {
            final titles = [
              'Board Games Night',
              'Study Group - Calculus',
              'Weekend Hiking',
            ];
            final counts = ['3/5 active', '2/4 active', '5/8 active'];
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
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(LucideIcons.users, color: themeColor),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titles[index],
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          counts[index],
                          style: TextStyle(
                            color: Colors.white.withAlpha(127),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    LucideIcons.chevronRight,
                    color: Color(0x66FFFFFF),
                    size: 16,
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
