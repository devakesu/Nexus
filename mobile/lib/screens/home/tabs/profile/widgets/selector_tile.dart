import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/screens/home/tabs/profile/utils/emoji_helper.dart';
import 'package:nexus/theme/app_colors.dart';

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
    const pulsarPink = AppColors.pulsarPink;
    final isEmpty = value.isEmpty || value.toLowerCase() == 'not specified';
    final tagIcon = isEmpty ? null : getTagIcon(value);
    final displayText = isEmpty ? 'Select...' : value;
    final textColor = isEmpty
        ? Colors.black.withValues(alpha: 0.3)
        : const Color(0xFF0F172A);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.black.withValues(alpha: 0.5),
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
              color: const Color(0xFFF3F4F6),
              border: Border.all(
                color: Colors.black.withValues(alpha: 0.08),
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
                        child: Row(
                          children: [
                            if (tagIcon != null) ...[
                              tagIcon,
                              const SizedBox(width: 6),
                            ],
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
                          ],
                        ),
                      ),
                      if (!isEmpty && onClear != null)
                        Semantics(
                          button: true,
                          label: 'Clear $label',
                          excludeSemantics: true,
                          onTap: onClear,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: onClear,
                            // 44px minimum touch target; the icon itself
                            // stays 13px, centered within.
                            child: const SizedBox(
                              width: 44,
                              height: 44,
                              child: Center(
                                child: Icon(
                                  LucideIcons.x,
                                  size: 13,
                                  color: Color(0x59000000),
                                ),
                              ),
                            ),
                          ),
                        )
                      else
                        Icon(
                          LucideIcons.chevronRight,
                          color: Colors.black.withValues(alpha: 0.35),
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
