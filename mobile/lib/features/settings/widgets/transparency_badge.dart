import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/theme/app_theme.dart';

class TransparencyBadge extends StatelessWidget {
  const TransparencyBadge({super.key, this.onTap, this.expanded = false});
  final VoidCallback? onTap;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final ghostColors = Theme.of(context).extension<GhostColors>();
    final accent =
        ghostColors?.brandPrimary ?? Theme.of(context).colorScheme.primary;
    final bg = Theme.of(context).colorScheme.surface;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final mutedText = onSurface.withValues(alpha: 0.72);

    final content = AnimatedContainer(
      duration: 220.ms,
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.symmetric(
        horizontal: expanded ? 22 : 16,
        vertical: expanded ? 12 : 14,
      ),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.18),
            accent.withValues(alpha: 0.06),
            bg.withValues(alpha: 0.96),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.12),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(LucideIcons.shieldCheck, size: 18, color: accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Build transparency',
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: onSurface,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  expanded
                      ? 'Signed APK · SBOM · provenance'
                      : 'Verify build receipts, security & privacy practices',
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: mutedText,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 12),
            Icon(LucideIcons.arrowRight, size: 18, color: accent),
          ],
        ],
      ),
    );

    final child = expanded
        ? content
        : SizedBox(
            width: double.infinity,
            child: content,
          );

    if (onTap == null) return child;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: child,
      ),
    );
  }
}
