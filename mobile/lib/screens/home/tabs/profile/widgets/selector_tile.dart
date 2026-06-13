import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/screens/home/tabs/profile/utils/emoji_helper.dart';

class SelectorTile extends StatelessWidget {
  const SelectorTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
    required this.onTap,
    this.isSaving = false,
    super.key,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;
  final bool isSaving;

  @override
  Widget build(BuildContext context) {
    const pulsarPink = Color(0xFFFF7597);
    final isEmpty = value.isEmpty || value.toLowerCase() == 'not specified';
    final emoji = getEmojiForTag(value);
    final displayText = isEmpty
        ? 'Select...'
        : (emoji.isNotEmpty ? '$emoji  $value' : value);
    final textColor = isEmpty
        ? Colors.white.withValues(alpha: 0.3)
        : Colors.white;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.white.withValues(alpha: 0.02),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: Stack(
                children: [
                  Row(
                    children: [
                      // Left color accent bar matching the category style
                      Container(
                        width: 4,
                        height: 52,
                        decoration: BoxDecoration(
                          color: iconColor,
                          boxShadow: [
                            BoxShadow(
                              color: iconColor.withValues(alpha: 0.5),
                              blurRadius: 4,
                              spreadRadius: 0.5,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(icon, color: iconColor, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          displayText,
                          maxLines: 1,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'Outfit',
                          ),
                        ),
                      ),
                      Icon(
                        LucideIcons.chevronRight,
                        color: Colors.white.withValues(alpha: 0.35),
                        size: 14,
                      ),
                      const SizedBox(width: 12),
                    ],
                  ),
                  if (isSaving)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: SizedBox(
                        height: 2,
                        child: LinearProgressIndicator(
                          backgroundColor: Colors.transparent,
                          valueColor: AlwaysStoppedAnimation<Color>(pulsarPink),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
