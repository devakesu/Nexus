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
    this.onClear,
    this.isSaving = false,
    super.key,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  final bool isSaving;

  @override
  Widget build(BuildContext context) {
    const pulsarPink = Color(0xFFFF7597);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEmpty = value.isEmpty || value.toLowerCase() == 'not specified';
    final emoji = getEmojiForTag(value);
    final displayText = isEmpty
        ? 'Select...'
        : (emoji.isNotEmpty ? '$emoji  $value' : value);
    final textColor = isEmpty
        ? (isDark
              ? Colors.white.withValues(alpha: 0.3)
              : Colors.black.withValues(alpha: 0.3))
        : (isDark ? Colors.white : const Color(0xFF0F172A));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: isDark
                ? Colors.white.withValues(alpha: 0.5)
                : Colors.black.withValues(alpha: 0.5),
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
              color: isDark
                  ? Colors.white.withValues(alpha: 0.02)
                  : const Color(0xFFF3F4F6),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.08),
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
                          ),
                        ),
                      ),
                      if (!isEmpty && onClear != null)
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: onClear,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 18,
                            ),
                            child: Icon(
                              LucideIcons.x,
                              size: 13,
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.45)
                                  : Colors.black.withValues(alpha: 0.35),
                            ),
                          ),
                        )
                      else
                        Icon(
                          LucideIcons.chevronRight,
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.35)
                              : Colors.black.withValues(alpha: 0.35),
                          size: 14,
                        ),
                      const SizedBox(width: 12),
                    ],
                  ),
                  if (isSaving)
                    const Positioned(
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
