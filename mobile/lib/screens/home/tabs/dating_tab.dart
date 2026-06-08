import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/screens/home/widgets/tab_scaffold.dart';

class DatingTab extends StatelessWidget {
  const DatingTab({required this.onOpenOrbit, super.key});

  final void Function(String, Color) onOpenOrbit;

  @override
  Widget build(BuildContext context) {
    const themeColor = Color(0xFFFF4F81);
    return TabScaffold(
      title: 'Dating',
      themeColor: themeColor,
      chatLabel: 'Dating',
      onOpenOrbitPressed: () => onOpenOrbit('Dating', themeColor),
      children: [
        const Text(
          'Featured Matches',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 0.85,
          ),
          itemCount: 4,
          itemBuilder: (context, index) {
            final names = ['Sophia', 'Liam', 'Olivia', 'Ethan'];
            final ages = ['21', '22', '20', '23'];
            final tags = ['Art', 'Music', 'Tech', 'Nature'];

            return Container(
              decoration: BoxDecoration(
                color: const Color(0xFF161B26),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withAlpha(13)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: themeColor.withAlpha(26),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(20),
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          LucideIcons.heart,
                          color: themeColor.withAlpha(127),
                          size: 36,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              names[index],
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              ages[index],
                              style: TextStyle(
                                color: Colors.white.withAlpha(127),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: themeColor.withAlpha(26),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            tags[index],
                            style: const TextStyle(
                              color: themeColor,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
