import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    // Determine the theme color based on the current active tab
    Color tabThemeColor;
    String chatLabel;
    switch (currentTab) {
      case 0:
        tabThemeColor = const Color(0xFFFF4F81);
        chatLabel = 'Dating';
      case 1:
        tabThemeColor = const Color(0xFFFF9F1C);
        chatLabel = 'Friends';
      case 2:
        tabThemeColor = const Color(0xFF8B5CF6);
        chatLabel = 'Personal';
      case 3:
        tabThemeColor = const Color(0xFF00F5D4);
        chatLabel = 'Professional';
      case 4:
        tabThemeColor = const Color(0xFF4EA8DE);
        chatLabel = 'System';
      default:
        tabThemeColor = const Color(0xFFFF7597);
        chatLabel = 'System';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0D13),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withAlpha(10),
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            appName.toUpperCase(),
            style: GoogleFonts.orbitron(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              color: Colors.white,
            ),
          ),
          // Dynamic Action Button based on Tab
          if (currentTab == 2)
            IconButton(
              icon: const Icon(LucideIcons.logOut, color: Colors.white),
              tooltip: 'Sign Out',
              onPressed: () {
                unawaited(Supabase.instance.client.auth.signOut());
              },
            )
          else
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF161B26),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withAlpha(20),
                  width: 1.5,
                ),
              ),
              child: IconButton(
                icon: Icon(LucideIcons.messageSquare, color: tabThemeColor),
                tooltip: 'Open Chats',
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: const Color(0xFF161B26),
                      content: Row(
                        children: [
                          Icon(LucideIcons.messageSquare, color: tabThemeColor),
                          const SizedBox(width: 12),
                          Text(
                            'Opening $chatLabel messages channel...',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
