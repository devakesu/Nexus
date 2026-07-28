import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/features/home/widgets/custom_bottom_nav_bar.dart';
import 'package:nexus/features/home/widgets/tab_background.dart';

class TabScaffold extends StatelessWidget {
  const TabScaffold({
    required this.title,
    required this.themeColor,
    required this.chatLabel,
    required this.onOpenOrbitPressed,
    required this.children,
    this.orbitDescription,
    this.isOrbitActive = false,
    this.onDeactivateOrbitPressed,
    this.onSettingsPressed,
    super.key,
  });

  final String title;
  final Color themeColor;
  final String chatLabel;
  final VoidCallback onOpenOrbitPressed;
  final List<Widget> children;
  final String? orbitDescription;
  final bool isOrbitActive;
  final VoidCallback? onDeactivateOrbitPressed;
  final VoidCallback? onSettingsPressed;

  @override
  Widget build(BuildContext context) {
    return TabBackground(
      accentColor: themeColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Scrollable content area
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                24,
                12,
                24,
                CustomBottomNavBar.clearance,
              ),
              children: [
                // Open Orbit action card
                Container(
                  margin: const EdgeInsets.only(bottom: 24),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        themeColor.withAlpha(38),
                        themeColor.withAlpha(5),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: themeColor.withAlpha(64),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: themeColor.withAlpha(51),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              LucideIcons.globe,
                              color: themeColor,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$title Orbit',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.ink,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: isOrbitActive
                                            ? AppColors.success
                                            : AppColors.inkMuted,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      isOrbitActive ? 'Active' : 'Inactive',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isOrbitActive
                                            ? AppColors.success
                                            : AppColors.inkMuted,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (onSettingsPressed != null)
                            IconButton(
                              icon: Icon(
                                LucideIcons.settings,
                                color: themeColor,
                                size: 20,
                              ),
                              onPressed: onSettingsPressed,
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        orbitDescription ??
                            'Activate your network scanner to search for other matches nearby.',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF334155),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isOrbitActive
                                ? AppColors.error
                                : themeColor,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: isOrbitActive
                              ? (onDeactivateOrbitPressed ?? onOpenOrbitPressed)
                              : onOpenOrbitPressed,
                          icon: Icon(
                            isOrbitActive
                                ? LucideIcons.stopCircle
                                : LucideIcons.play,
                            size: 16,
                          ),
                          label: Text(
                            isOrbitActive
                                ? 'Deactivate Orbit'
                                : 'Activate Orbit',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                      if (isOrbitActive) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'If you need a break or you need to stop being discoverable to others, you can deactivate your orbit.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.inkMuted,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                ...children,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
