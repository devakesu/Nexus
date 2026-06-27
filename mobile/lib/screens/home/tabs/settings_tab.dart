import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

const _kAuthorName = '@deva.kesu';
const _kAuthorUrl = 'https://devakesu.com';
const _kGithubUrl = 'https://github.com/devakesu/Nexus';

class SettingsTab extends StatelessWidget {
  const SettingsTab({required this.onOpenOrbit, super.key});

  // Kept for home_screen.dart compatibility — not used in this screen.
  final void Function(String, Color) onOpenOrbit;

  static const _accent = Color(0xFF0284C7);

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 120),
      children: const [
        _NexusBranding(),
        SizedBox(height: 4),
        _SettingsSection(
          title: 'Account',
          accentColor: _accent,
          tiles: [
            _TileSpec(icon: LucideIcons.userCog, label: 'Edit Profile'),
            _TileSpec(
              icon: LucideIcons.sparkles,
              label: 'Nexus+',
              badge: 'UPGRADE',
            ),
            _TileSpec(icon: LucideIcons.link, label: 'Linked Accounts'),
          ],
        ),
        _SettingsSection(
          title: 'Discovery',
          accentColor: _accent,
          tiles: [
            _TileSpec(
              icon: LucideIcons.sliders,
              label: 'Discovery Preferences',
            ),
            _TileSpec(icon: LucideIcons.eyeOff, label: 'Hide My Profile'),
            _TileSpec(
              icon: LucideIcons.pauseCircle,
              label: 'Pause Matching',
            ),
          ],
        ),
        _SettingsSection(
          title: 'Notifications',
          accentColor: _accent,
          tiles: [
            _TileSpec(icon: LucideIcons.bell, label: 'Push Notifications'),
            _TileSpec(icon: LucideIcons.mail, label: 'Email Notifications'),
          ],
        ),
        _SettingsSection(
          title: 'Privacy & Safety',
          accentColor: _accent,
          tiles: [
            _TileSpec(icon: LucideIcons.shield, label: 'Privacy Settings'),
            _TileSpec(icon: LucideIcons.ban, label: 'Blocked Users'),
            _TileSpec(icon: LucideIcons.ghost, label: 'Incognito Mode'),
            _TileSpec(
              icon: LucideIcons.heartHandshake,
              label: 'Safety Center',
            ),
          ],
        ),
        _SettingsSection(
          title: 'Help & Support',
          accentColor: _accent,
          tiles: [
            _TileSpec(icon: LucideIcons.helpCircle, label: 'Help Center'),
            _TileSpec(
              icon: LucideIcons.messageSquare,
              label: 'Send Feedback',
            ),
            _TileSpec(icon: LucideIcons.bug, label: 'Report a Bug'),
            _TileSpec(
              icon: LucideIcons.bookOpen,
              label: 'Community Guidelines',
            ),
          ],
        ),
        _SettingsSection(
          title: 'Legal',
          accentColor: _accent,
          tiles: [
            _TileSpec(icon: LucideIcons.fileText, label: 'Privacy Policy'),
            _TileSpec(icon: LucideIcons.scroll, label: 'Terms of Service'),
          ],
        ),
        SizedBox(height: 8),
        _AccountActionsSection(),
        SizedBox(height: 28),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Branding header
// ---------------------------------------------------------------------------

class _NexusBranding extends StatelessWidget {
  const _NexusBranding();

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => _launch(_kAuthorUrl),
            child: Column(
              children: [
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: GoogleFonts.manrope(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF64748B),
                      letterSpacing: 2.5,
                    ),
                    children: [
                      const TextSpan(text: 'CRAFTED WITH '),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Icon(
                          LucideIcons.heart,
                          size: 10,
                          color: Colors.pinkAccent.withValues(alpha: 0.85),
                        ),
                      ),
                      const TextSpan(text: ' BY'),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _kAuthorName.toUpperCase(),
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF0F172A),
                    letterSpacing: 4,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _BrandingChip(
                icon: LucideIcons.coffee,
                label: 'Buy me a Coffee',
                color: Colors.pinkAccent.shade700,
                onTap: () => _launch('https://buymeacoffee.com/devakesu'),
              ),
              const SizedBox(width: 8),
              _BrandingChip(
                icon: LucideIcons.star,
                label: 'Star on GitHub',
                color: Colors.amber.shade700,
                onTap: () => _launch(_kGithubUrl),
              ),
            ],
          ),

          const SizedBox(height: 20),

          Container(
            width: 32,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandingChip extends StatelessWidget {
  const _BrandingChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.18)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.manrope(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: color,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Settings section
// ---------------------------------------------------------------------------

class _TileSpec {
  const _TileSpec({required this.icon, required this.label, this.badge});
  final IconData icon;
  final String label;
  final String? badge;
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.tiles,
    required this.accentColor,
  });

  final String title;
  final List<_TileSpec> tiles;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              title.toUpperCase(),
              style: GoogleFonts.manrope(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF64748B),
                letterSpacing: 1.5,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Column(
                children: [
                  for (int i = 0; i < tiles.length; i++)
                    _SettingsTile(
                      spec: tiles[i],
                      accentColor: accentColor,
                      showDivider: i < tiles.length - 1,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.spec,
    required this.accentColor,
    required this.showDivider,
  });

  final _TileSpec spec;
  final Color accentColor;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    const effectiveLabelColor = Color(0xFF0F172A);

    return Column(
      children: [
        InkWell(
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              content: Text(
                '${spec.label} — coming soon.',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(spec.icon, color: accentColor, size: 17),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    spec.label,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: effectiveLabelColor,
                    ),
                  ),
                ),
                if (spec.badge != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: accentColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      spec.badge!,
                      style: GoogleFonts.manrope(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                const Icon(
                  LucideIcons.chevronRight,
                  color: Color(0xFFCBD5E1),
                  size: 16,
                ),
              ],
            ),
          ),
        ),
        if (showDivider)
          Container(
            margin: const EdgeInsets.only(left: 64),
            height: 0.5,
            color: const Color(0xFFE2E8F0),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Account actions (sign out / delete)
// ---------------------------------------------------------------------------

class _AccountActionsSection extends StatelessWidget {
  const _AccountActionsSection();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'ACCOUNT ACTIONS',
              style: GoogleFonts.manrope(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF64748B),
                letterSpacing: 1.5,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Column(
                children: [
                  _ActionRow(
                    icon: LucideIcons.logOut,
                    label: 'Sign Out',
                    iconColor: const Color(0xFF64748B),
                    labelColor: const Color(0xFF0F172A),
                    showDivider: true,
                    onTap: () => _confirmSignOut(context),
                  ),
                  _ActionRow(
                    icon: LucideIcons.trash2,
                    label: 'Delete Account',
                    iconColor: const Color(0xFFEF4444),
                    labelColor: const Color(0xFFEF4444),
                    showDivider: false,
                    onTap: () => _warnDeleteAccount(context),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text(
          'Sign out?',
          style: GoogleFonts.manrope(fontWeight: FontWeight.w800),
        ),
        content: const Text(
          "You'll need to sign in again to access your account.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await Supabase.instance.client.auth.signOut();
    }
  }

  void _warnDeleteAccount(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: const Text(
          'Account deletion coming soon. Contact support to proceed.',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.iconColor,
    required this.labelColor,
    required this.showDivider,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color iconColor;
  final Color labelColor;
  final bool showDivider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, color: iconColor, size: 17),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: labelColor,
                    ),
                  ),
                ),
                Icon(
                  LucideIcons.chevronRight,
                  color: iconColor.withValues(alpha: 0.4),
                  size: 16,
                ),
              ],
            ),
          ),
        ),
        if (showDivider)
          Container(
            margin: const EdgeInsets.only(left: 64),
            height: 0.5,
            color: const Color(0xFFE2E8F0),
          ),
      ],
    );
  }
}
