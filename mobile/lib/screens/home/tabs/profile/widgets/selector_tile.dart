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
    this.isFullWidth = true,
    this.visibilityBadge,
    super.key,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  final bool isSaving;
  final bool isFullWidth;
  final Widget? visibilityBadge;

  @override
  Widget build(BuildContext context) {
    const pulsarPink = AppColors.pulsarPink;
    final isEmpty = value.isEmpty || value.toLowerCase() == 'not specified';
    
    // Layout configurations based on width mode
    final iconSize = isFullWidth ? 15.0 : 13.0;
    final fontSize = isFullWidth ? 12.5 : 12.0;
    final leftPadding = isFullWidth ? 14.0 : 10.0;
    final iconTextGap = isFullWidth ? 8.0 : 5.0;
    final clearWidth = isFullWidth ? 44.0 : 36.0;
    final rightPadding = isFullWidth ? 12.0 : 8.0;

    final tagIcon = isEmpty ? null : getTagIcon(value, iconSize: iconSize);
    final displayText = isEmpty ? 'Select...' : value;
    final textColor = isEmpty
        ? Colors.black.withValues(alpha: 0.3)
        : const Color(0xFF0F172A);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: iconColor, size: 14),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: Colors.black.withValues(alpha: 0.5),
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            if (visibilityBadge != null) ...[
              const SizedBox(width: 6),
              visibilityBadge!,
            ],
          ],
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
                      SizedBox(width: leftPadding),
                      Expanded(
                        child: Row(
                          children: [
                            if (tagIcon != null) ...[
                              tagIcon,
                              SizedBox(width: iconTextGap),
                            ],
                            Expanded(
                              child: Text(
                                displayText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: fontSize,
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
                            child: SizedBox(
                              width: clearWidth,
                              height: 44,
                              child: const Center(
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
                      SizedBox(width: rightPadding),
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
