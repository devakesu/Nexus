import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/theme/app_colors.dart';

/// A compact inline badge shown beside profile field labels to indicate
/// which discovery tabs (Dating / Friends / Professional) will display
/// that field to other users.
///
/// Usage: drop it inside a [Row] next to the existing label text.
class ProfileVisibilityBadge extends StatelessWidget {
  const ProfileVisibilityBadge({
    required this.text,
    this.color,
    super.key,
  });

  /// Short human-readable string, e.g. "Dating & Friends".
  final String text;

  /// Override accent colour. Defaults to a neutral amber/amber-ish tone.
  final Color? color;

  // ── Convenience constructors ──────────────────────────────────────────────

  /// "Only visible in Dating & Friends"
  static Widget datingAndFriends() => const ProfileVisibilityBadge(
        text: 'Dating & Friends',
        color: Color(0xFFE67E22),
      );

  /// "Only visible in Dating"
  static Widget datingOnly() => const ProfileVisibilityBadge(
        text: 'Dating only',
        color: AppColors.modeDating,
      );

  /// Visible across all three tabs (Dating, Friends & Professional).
  static Widget allTabs() => const ProfileVisibilityBadge(
        text: 'All tabs',
        color: AppColors.success,
      );

  @override
  Widget build(BuildContext context) {
    final c = color ?? const Color(0xFFE67E22);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.eye, size: 8, color: c.withValues(alpha: 0.8)),
          const SizedBox(width: 3),
          Text(
            text,
            style: TextStyle(
              color: c.withValues(alpha: 0.9),
              fontSize: 8.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
