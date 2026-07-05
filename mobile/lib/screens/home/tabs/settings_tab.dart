import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/services/notification_service.dart';
import 'package:nexus/utils/network_utils.dart';
import 'package:nexus/utils/orbit_refresh_notifier.dart';
import 'package:nexus/widgets/aesthetic_loaders.dart';
import 'package:nexus/widgets/nexus_toast.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

const _kAuthorName = '@deva.kesu';
const _kAuthorUrl = 'https://devakesu.com';
const _kGithubUrl = 'https://github.com/devakesu/Nexus';

enum _PauseStatus { loading, active, paused, error }

class SettingsTab extends StatefulWidget {
  const SettingsTab({required this.onOpenOrbit, super.key});

  // Kept for home_screen.dart compatibility - not used in this screen.
  final void Function(String, Color) onOpenOrbit;

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> with WidgetsBindingObserver {
  static const _accent = Color(0xFF0284C7);

  _PauseStatus _pauseStatus = _PauseStatus.loading;
  AuthorizationStatus? _notifPermission;
  late final Dio _dio;
  final SupabaseClient _client = Supabase.instance.client;
  StreamSubscription<bool>? _orbitSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _dio = createDio();
    unawaited(_loadPauseStatus());
    unawaited(_loadNotifPermission());
    _orbitSub = OrbitRefreshNotifier.stream.listen(_onOrbitChange);
  }

  void _onOrbitChange(bool activated) {
    if (!mounted) return;
    if (activated) {
      setState(() => _pauseStatus = _PauseStatus.active);
    } else {
      unawaited(_loadPauseStatus());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_loadNotifPermission());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_orbitSub?.cancel());
    super.dispose();
  }

  Future<void> _loadNotifPermission() async {
    final status = await NotificationService.getPermissionStatus();
    if (mounted) setState(() => _notifPermission = status);
  }

  Widget _buildNotifTrailing() {
    return switch (_notifPermission) {
      AuthorizationStatus.authorized ||
      AuthorizationStatus.provisional =>
        const _StatusDot(label: 'Enabled', color: Color(0xFF16A34A)),
      AuthorizationStatus.denied =>
        const _StatusDot(label: 'Disabled', color: Color(0xFFEF4444)),
      _ => const Icon(LucideIcons.chevronRight, color: Color(0xFFCBD5E1), size: 16),
    };
  }

  Future<void> _handleNotifTap() async {
    if (_notifPermission == AuthorizationStatus.denied) {
      if (!mounted) return;
      await NotificationService.showPermissionDeniedDialog(context);
    } else {
      await NotificationService.openNotificationSettings();
    }
  }

  Future<void> _loadPauseStatus() async {
    try {
      final session = _client.auth.currentSession;
      if (session == null) {
        if (mounted) setState(() => _pauseStatus = _PauseStatus.error);
        return;
      }
      final data = await NetworkUtils.fetchProfileDetails(
        _dio,
        session.accessToken,
      );
      if (!mounted) return;
      if (data == null) {
        setState(() => _pauseStatus = _PauseStatus.error);
        return;
      }
      final isDatingActive = data['is_dating_active'] == true;
      final isFriendsActive = data['is_friends_active'] == true;
      final isProfessionalActive = data['is_professional_active'] == true;
      final isAnyActive =
          isDatingActive || isFriendsActive || isProfessionalActive;
      setState(
        () => _pauseStatus = isAnyActive
            ? _PauseStatus.active
            : _PauseStatus.paused,
      );
    } on Exception catch (_) {
      if (mounted) setState(() => _pauseStatus = _PauseStatus.error);
    }
  }

  Future<void> _pauseMatching() async {
    setState(() => _pauseStatus = _PauseStatus.loading);
    try {
      final session = _client.auth.currentSession;
      if (session == null) throw Exception('Not signed in');
      await _dio.patch<void>(
        '${AppConfig.current.backendUrl}/api/v1/profile/details',
        data: {
          'is_dating_active': false,
          'is_friends_active': false,
          'is_professional_active': false,
        },
        options: Options(
          headers: {'Authorization': 'Bearer ${session.accessToken}'},
        ),
      );
      if (mounted) setState(() => _pauseStatus = _PauseStatus.paused);
      OrbitRefreshNotifier.notifyDeactivated();
    } on Exception catch (_) {
      if (mounted) setState(() => _pauseStatus = _PauseStatus.error);
    }
  }

  Future<void> _handlePauseTap() async {
    if (_pauseStatus == _PauseStatus.loading) return;

    if (_pauseStatus == _PauseStatus.paused) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Matching is Paused',
            style: GoogleFonts.manrope(fontWeight: FontWeight.w800),
          ),
          content: Text(
            "You're not visible to others and won't appear in anyone's Orbit. "
            'To resume, activate individual Orbits from their tabs.',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: const Color(0xFF475569),
            ),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Got it'),
            ),
          ],
        ),
      );
      return;
    }

    // _pauseStatus == active (or error - treat as active to allow retry)
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Pause Matching?',
          style: GoogleFonts.manrope(fontWeight: FontWeight.w800),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'All 3 Orbits will be deactivated:',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: const Color(0xFF475569),
              ),
            ),
            const SizedBox(height: 10),
            const _OrbitBullet(
              label: 'Dating',
              color: Color(0xFFFF2A54),
            ),
            const _OrbitBullet(
              label: 'Friends',
              color: Color(0xFFD32F2F),
            ),
            const _OrbitBullet(
              label: 'Professional',
              color: Color(0xFF00796B),
            ),
            const SizedBox(height: 12),
            Text(
              "You won't be visible to others and won't be able to discover new profiles until you re-activate an Orbit.",
              style: GoogleFonts.inter(
                fontSize: 13,
                color: const Color(0xFF64748B),
                height: 1.45,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF59E0B),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Pause',
              style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _pauseMatching();
    }
  }

  Widget _buildPauseIndicator() {
    return switch (_pauseStatus) {
      _PauseStatus.loading => const NexusOrbitLoader(size: 20, lightMode: true),
      _PauseStatus.active => const _StatusDot(
        label: 'Active',
        color: Color(0xFF16A34A),
      ),
      _PauseStatus.paused => const _StatusDot(
        label: 'Paused',
        color: Color(0xFFF59E0B),
      ),
      _PauseStatus.error => const Icon(
        LucideIcons.chevronRight,
        color: Color(0xFFCBD5E1),
        size: 16,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        const _NexusBranding(),
        const SizedBox(height: 4),
        const _SettingsSection(
          title: 'Account',
          accentColor: _accent,
          tiles: [
            _TileSpec(
              icon: LucideIcons.sparkles,
              label: 'Nexus+',
              badge: 'UPGRADE',
            ),
            _TileSpec(icon: LucideIcons.link, label: 'Linked Accounts'),
          ],
        ),
        _SettingsSection(
          title: 'Notifications',
          accentColor: _accent,
          tiles: [
            _TileSpec(
              icon: LucideIcons.bell,
              label: 'Push Notifications',
              trailing: _buildNotifTrailing(),
              onTap: _handleNotifTap,
            ),
            const _TileSpec(icon: LucideIcons.mail, label: 'Email Notifications'),
          ],
        ),
        _SettingsSection(
          title: 'Privacy & Safety',
          accentColor: _accent,
          tiles: [
            _TileSpec(
              icon: LucideIcons.shield,
              label: 'Privacy Settings',
              onTap: () => context.push<void>('/settings/privacy'),
            ),
            _TileSpec(
              icon: LucideIcons.ban,
              label: 'Blocked Users',
              onTap: () => context.push<void>('/settings/blocked-users'),
            ),
            _TileSpec(
              icon: LucideIcons.eyeOff,
              label: 'Hidden Users',
              onTap: () => context.push<void>('/settings/hidden-users'),
            ),
            _TileSpec(
              icon: LucideIcons.pauseCircle,
              label: 'Pause Matching',
              trailing: _buildPauseIndicator(),
              onTap: _handlePauseTap,
            ),
            _TileSpec(
              icon: LucideIcons.heartHandshake,
              label: 'Safety Center',
              onTap: () => context.push<void>('/settings/safety-center'),
            ),
          ],
        ),
        const _SettingsSection(
          title: 'Help & Support',
          accentColor: _accent,
          tiles: [
            _TileSpec(icon: LucideIcons.helpCircle, label: 'Help Center'),
            _TileSpec(
              icon: LucideIcons.messageSquare,
              label: 'Feedback & Bug Report',
            ),
          ],
        ),
        const _SettingsSection(
          title: 'Legal',
          accentColor: _accent,
          tiles: [
            _TileSpec(icon: LucideIcons.fileText, label: 'Privacy Policy'),
            _TileSpec(icon: LucideIcons.scroll, label: 'Terms of Service'),
            _TileSpec(
              icon: LucideIcons.bookOpen,
              label: 'Community Guidelines',
            ),
          ],
        ),
        const SizedBox(height: 8),
        const _AccountActionsSection(),
        const SizedBox(height: 28),
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
  const _TileSpec({
    required this.icon,
    required this.label,
    this.badge,
    this.trailing,
    this.onTap,
  });
  final IconData icon;
  final String label;
  final String? badge;
  // Overrides the badge + chevron area when set.
  final Widget? trailing;
  final VoidCallback? onTap;
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
          onTap:
              spec.onTap ??
              () => NexusToast.show(context, '${spec.label} - coming soon.'),
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
                if (spec.trailing != null)
                  spec.trailing!
                else ...[
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
// Pause Matching helper widgets
// ---------------------------------------------------------------------------

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _OrbitBullet extends StatelessWidget {
  const _OrbitBullet({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF334155),
            ),
          ),
        ],
      ),
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
    NexusToast.show(
      context,
      'Account deletion coming soon. Contact support to proceed.',
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
