import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/screens/home/widgets/tab_scaffold.dart';

class SettingsTab extends StatelessWidget {
  const SettingsTab({required this.onOpenOrbit, super.key});

  final void Function(String, Color) onOpenOrbit;

  @override
  Widget build(BuildContext context) {
    const themeColor = Color(0xFF4EA8DE);
    return TabScaffold(
      title: 'Settings',
      themeColor: themeColor,
      chatLabel: 'System',
      onOpenOrbitPressed: () => onOpenOrbit('Settings', themeColor),
      children: [
        const Text(
          'Preferences',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        Column(
          children: [
            _buildSettingTile(
              LucideIcons.bell,
              'Notifications',
              'On',
              themeColor,
            ),
            _buildSettingTile(
              LucideIcons.shieldAlert,
              'Privacy & Safety',
              'Secure',
              themeColor,
            ),
            _buildSettingTile(
              LucideIcons.palette,
              'App Theme',
              'Dark Mode',
              themeColor,
            ),
            _buildSettingTile(
              LucideIcons.helpCircle,
              'Help & Feedback',
              '',
              themeColor,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSettingTile(
    IconData icon,
    String title,
    String subtitle,
    Color themeColor,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF161B26),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withAlpha(13)),
      ),
      child: Row(
        children: [
          Icon(icon, color: themeColor, size: 20),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
          if (subtitle.isNotEmpty)
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.white.withAlpha(102),
                fontSize: 13,
              ),
            ),
          const SizedBox(width: 8),
          const Icon(
            LucideIcons.chevronRight,
            color: Color(0x33FFFFFF),
            size: 16,
          ),
        ],
      ),
    );
  }
}
