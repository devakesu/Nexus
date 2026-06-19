import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class CommonHeader extends StatelessWidget {
  const CommonHeader({
    required this.appName,
    required this.currentTab,
    this.onChatTap,
    super.key,
  });

  final String appName;
  final int currentTab;
  final VoidCallback? onChatTap;

  @override
  Widget build(BuildContext context) {
    Color tabThemeColor;
    Color tabThemeColorSecondary;
    String? tabLabel;

    switch (currentTab) {
      case 0:
        tabThemeColor = const Color(0xFFFF2A54);
        tabThemeColorSecondary = const Color(0xFFFF6B8B);
        tabLabel = 'Dating';
      case 1:
        tabThemeColor = const Color(0xFFD32F2F);
        tabThemeColorSecondary = const Color(0xFFF57C00);
        tabLabel = 'Friends';
      case 2:
        tabThemeColor = const Color(0xFF6366F1);
        tabThemeColorSecondary = const Color(0xFFA855F7);
        tabLabel = null; // Profile tab — no tag
      case 3:
        tabThemeColor = const Color(0xFF00796B);
        tabThemeColorSecondary = const Color(0xFF0097A7);
        tabLabel = 'Professional';
      case 4:
        tabThemeColor = const Color(0xFF0284C7);
        tabThemeColorSecondary = const Color(0xFF3B82F6);
        tabLabel = null; // Settings tab — no tag
      default:
        tabThemeColor = const Color(0xFFFF2A54);
        tabThemeColorSecondary = const Color(0xFFFF6B8B);
        tabLabel = null;
    }

    final statusBarHeight = MediaQuery.of(context).padding.top;
    const iconSize = 40.0;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 14 + statusBarHeight, 20, 14),
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
      child: Row(
        children: [
          // Balancing spacer to keep title centered
          const SizedBox(width: iconSize),
          Expanded(
            child: SizedBox(
              height: 56,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'NEXUS',
                    style: GoogleFonts.orbitron(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 6,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          offset: const Offset(0, 3),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                  if (tabLabel != null) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        tabLabel.toUpperCase(),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                          color: Colors.white.withValues(alpha: 0.95),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Chat icon button
          SizedBox(
            width: iconSize,
            height: iconSize,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onChatTap,
                borderRadius: BorderRadius.circular(20),
                splashColor: Colors.white.withValues(alpha: 0.2),
                highlightColor: Colors.white.withValues(alpha: 0.1),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Icon(
                    Icons.chat_bubble_rounded,
                    color: Colors.white.withValues(alpha: 0.95),
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
