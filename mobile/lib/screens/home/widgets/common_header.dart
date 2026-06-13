import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class CommonHeader extends StatelessWidget {
  const CommonHeader({
    required this.appName,
    required this.currentTab,
    super.key,
  });

  final String appName;
  final int currentTab;

  @override
  Widget build(BuildContext context) {
    // Determine the theme colors and labels based on the current active tab
    Color tabThemeColor;
    Color tabThemeColorSecondary;
    String chatLabel;
    IconData tabIcon;

    switch (currentTab) {
      case 0:
        tabThemeColor = const Color(0xFFFF2A54);
        tabThemeColorSecondary = const Color(0xFFFF6B8B);
        chatLabel = 'Dating';
        tabIcon = LucideIcons.heart;
      case 1:
        tabThemeColor = const Color(0xFFD32F2F); // Rich crimson/red-orange
        tabThemeColorSecondary = const Color(0xFFF57C00); // Deep orange
        chatLabel = 'Friends';
        tabIcon = LucideIcons.users;
      case 2:
        tabThemeColor = const Color(0xFF6366F1);
        tabThemeColorSecondary = const Color(0xFFA855F7);
        chatLabel = 'Personal';
        tabIcon = LucideIcons.user;
      case 3:
        tabThemeColor = const Color(0xFF00796B); // Deep teal
        tabThemeColorSecondary = const Color(0xFF0097A7); // Rich dark cyan
        chatLabel = 'Professional';
        tabIcon = LucideIcons.briefcase;
      case 4:
        tabThemeColor = const Color(0xFF0284C7);
        tabThemeColorSecondary = const Color(0xFF3B82F6);
        chatLabel = 'System';
        tabIcon = LucideIcons.settings;
      default:
        tabThemeColor = const Color(0xFFFF2A54);
        tabThemeColorSecondary = const Color(0xFFFF6B8B);
        chatLabel = 'System';
        tabIcon = LucideIcons.settings;
    }

    final statusBarHeight = MediaQuery.of(context).padding.top;

    return Container(
      padding: EdgeInsets.fromLTRB(24, 18 + statusBarHeight, 24, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [tabThemeColor, tabThemeColorSecondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: tabThemeColor.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                shape: BoxShape.circle,
              ),
              child: Icon(
                tabIcon,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  appName.toUpperCase(),
                  style: GoogleFonts.orbitron(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.5,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        offset: const Offset(0, 2),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
                Text(
                  chatLabel.toUpperCase(),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
