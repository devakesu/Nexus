import 'dart:async';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/screens/home/widgets/custom_bottom_nav_bar.dart';
import 'package:nexus/screens/home/widgets/tab_background.dart';
import 'package:nexus/screens/settings/data_export_flow.dart';
import 'package:nexus/services/notification_service.dart';
import 'package:nexus/services/signal/signal_key_service.dart';
import 'package:nexus/theme/app_colors.dart';
import 'package:nexus/utils/error_handler.dart';
import 'package:nexus/utils/network_utils.dart';
import 'package:nexus/utils/orbit_refresh_notifier.dart';
import 'package:nexus/widgets/aesthetic_loaders.dart';
import 'package:nexus/widgets/nexus_toast.dart';
import 'package:nexus/widgets/scale_pressable.dart';
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
  // Settings Signal - matches the Settings tab's own nav color. Was
  // previously Safety Blue (#0284C7), which broke the Mode Signal Rule and
  // leaked the Safety Duo onto a non-safety surface.
  static const Color _accent = AppColors.modeSettings;

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
      AuthorizationStatus.authorized || AuthorizationStatus.provisional =>
        const _StatusDot(label: 'Enabled', color: AppColors.success),
      AuthorizationStatus.denied => const _StatusDot(
        label: 'Disabled',
        color: AppColors.error,
      ),
      _ => const Icon(
        LucideIcons.chevronRight,
        color: Color(0xFFCBD5E1),
        size: 16,
      ),
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
      );
      if (mounted) setState(() => _pauseStatus = _PauseStatus.paused);
      OrbitRefreshNotifier.notifyDeactivated();
    } on Exception catch (e, stackTrace) {
      if (mounted) {
        setState(() => _pauseStatus = _PauseStatus.error);
        NexusToast.show(
          context,
          'Failed to pause matching. Please try again.',
          type: NexusToastType.error,
        );
        ErrorHandler.handleError(
          e,
          stackTrace: stackTrace,
          customMessage: 'Failed to pause matching.',
          showUi: false,
        );
      }
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
            'To resume, activate individual Orbits from their tabs. '
            "You can still chat with people you've already matched with.",
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
              color: AppColors.modeDating,
            ),
            const _OrbitBullet(
              label: 'Friends',
              color: AppColors.modeFriends,
            ),
            const _OrbitBullet(
              label: 'Professional',
              color: AppColors.modeProfessional,
            ),
            const SizedBox(height: 12),
            Text(
              "You won't be visible to others and won't be able to discover new profiles until you re-activate an Orbit. "
              "You'll still be able to chat with people you've already matched with.",
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
              backgroundColor: AppColors.warning,
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
        color: AppColors.success,
      ),
      _PauseStatus.paused => const _StatusDot(
        label: 'Paused',
        color: AppColors.warning,
      ),
      _PauseStatus.error => const Icon(
        LucideIcons.alertCircle,
        color: AppColors.error,
        size: 18,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return TabBackground(
      accentColor: _accent,
      child: ListView(
        padding: const EdgeInsets.only(bottom: CustomBottomNavBar.clearance),
        children: [
          const _NexusBranding(),
          const _NexusPlusPromoCard(accentColor: _accent),
          const SizedBox(height: 6),
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
              _TileSpec(
                icon: LucideIcons.mail,
                label: 'Email Notifications',
                onTap: () =>
                    context.push<void>('/settings/email-notifications'),
              ),
            ],
          ),
          _SettingsSection(
            title: 'Privacy & Safety',
            accentColor: _accent,
            tiles: [
              _TileSpec(
                icon: LucideIcons.pauseCircle,
                label: 'Pause Matching',
                trailing: _buildPauseIndicator(),
                onTap: _handlePauseTap,
              ),
              _TileSpec(
                icon: LucideIcons.shield,
                label: 'Privacy Settings',
                onTap: () => context.push<void>('/settings/privacy'),
              ),
              _TileSpec(
                icon: LucideIcons.heartHandshake,
                label: 'Safety Center',
                onTap: () => context.push<void>('/settings/safety-center'),
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
            ],
          ),
          _SettingsSection(
            title: 'Help & Support',
            accentColor: _accent,
            tiles: [
              _TileSpec(
                icon: LucideIcons.helpCircle,
                label: 'Help Center',
                onTap: () => context.push<void>('/settings/help-center'),
              ),
              _TileSpec(
                icon: LucideIcons.messageSquare,
                label: 'Help, Feedback & Bug Report',
                onTap: () => context.push<void>('/settings/feedback'),
              ),
            ],
          ),
          _SettingsSection(
            title: 'Legal',
            accentColor: _accent,
            tiles: [
              _TileSpec(
                icon: LucideIcons.scroll,
                label: 'Terms & Privacy Policy',
                onTap: () => context.push<void>('/legal/terms'),
              ),
              _TileSpec(
                icon: LucideIcons.bookOpen,
                label: 'Community Guidelines',
                onTap: () =>
                    context.push<void>('/settings/community-guidelines'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const _AccountActionsSection(),
          const SizedBox(height: 28),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Premium Nexus+ Promo Card
// ---------------------------------------------------------------------------

class _NexusPlusPromoCard extends StatelessWidget {
  const _NexusPlusPromoCard({required this.accentColor});

  final Color accentColor;

  void _showNexusPlusOverlay(BuildContext context) {
    unawaited(
      showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'NexusPlus',
        barrierColor: Colors.black.withValues(alpha: 0.65),
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (context, animation, secondaryAnimation) {
          return _NexusPlusOverlay(accentColor: accentColor);
        },
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          final curvedValue = Curves.easeOutQuart.transform(animation.value);
          return FadeTransition(
            opacity: animation,
            child: Transform.scale(
              scale: 0.94 + 0.06 * curvedValue,
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: ScalePressable(
        onTap: () => _showNexusPlusOverlay(context),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF4F46E5),
                const Color(0xFF7C3AED),
                accentColor,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7C3AED).withValues(alpha: 0.25),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned(
                right: -20,
                top: -20,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        LucideIcons.sparkles,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Upgrade to Nexus+',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Unlock premium filters, advanced interactions, and profile aesthetics.',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.9),
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'UPGRADE',
                        style: GoogleFonts.manrope(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF7C3AED),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NexusPlusOverlay extends StatelessWidget {
  const _NexusPlusOverlay({required this.accentColor});

  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // 1. Backdrop Blur
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                color: const Color(0xFF070B19).withValues(alpha: 0.88),
              ),
            ),
          ),
          // 2. Cosmic Ambient Gradients
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF7C3AED).withValues(alpha: 0.15),
              ),
            ),
          ),
          Positioned(
            bottom: 100,
            right: -150,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFF7597).withValues(alpha: 0.12),
              ),
            ),
          ),
          // 3. Content Layout
          SafeArea(
            child: Column(
              children: [
                // Close button at top right
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 20, top: 10),
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                        child: const Icon(
                          LucideIcons.x,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'NEXUS+',
                  style: GoogleFonts.orbitron(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 6,
                    shadows: [
                      Shadow(
                        color: const Color(0xFFFF7597).withValues(alpha: 0.4),
                        blurRadius: 15,
                      ),
                      Shadow(
                        color: const Color(0xFF7C3AED).withValues(alpha: 0.3),
                        blurRadius: 30,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'REDEFINE YOUR ORBIT',
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF94A3B8),
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 36),
                // Feature List
                const Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        _FeatureRow(
                          icon: LucideIcons.magnet,
                          title: 'Gravity Pull',
                          description:
                              'Dynamically align your orbit based on shared music taste and Spotify compatibility.',
                          iconBg: Color(0x26FF7597),
                          iconColor: Color(0xFFFF7597),
                        ),
                        _FeatureRow(
                          icon: LucideIcons.send,
                          title: 'Stardust Messages',
                          description:
                              'Attach a brief icebreaker note that shoots across their screen as a shooting star.',
                          iconBg: Color(0x267C3AED),
                          iconColor: Color(0xFF7C3AED),
                        ),
                        _FeatureRow(
                          icon: LucideIcons.eyeOff,
                          title: 'Dark Nebula',
                          description:
                              'Explore orbits completely invisibly. You only appear to users you like or message.',
                          iconBg: Color(0x264EA8DE),
                          iconColor: Color(0xFF4EA8DE),
                        ),
                        _FeatureRow(
                          icon: LucideIcons.history,
                          title: 'Retrograde',
                          description:
                              'Accidentally passed a star? Spin the coordinate grid back to undo your last action.',
                          iconBg: Color(0x26007E6D),
                          iconColor: Color(0xFF007E6D),
                        ),
                        _FeatureRow(
                          icon: LucideIcons.palette,
                          title: 'Chroma Orbit',
                          description:
                              'Personalize your profile with custom cosmic gradients and dynamic star trails.',
                          iconBg: Color(0x26FF4F81),
                          iconColor: Color(0xFFFF4F81),
                        ),
                        _FeatureRow(
                          icon: LucideIcons.badgeCheck,
                          title: 'Verified Badge',
                          description:
                              'Display a verified checkmark on your profile showing authenticity (subject to ID verification).',
                          iconBg: Color(0x2660A5FA),
                          iconColor: Color(0xFF60A5FA),
                        ),
                        SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
                // Pinned Bottom Button
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF070B19).withValues(alpha: 0.9),
                    border: Border(
                      top: BorderSide(
                        color: Colors.white.withValues(alpha: 0.05),
                      ),
                    ),
                  ),
                  child: ScalePressable(
                    onTap: () {
                      NexusToast.show(
                        context,
                        'Nexus+ Subscriptions - coming soon.',
                      );
                    },
                    child: Container(
                      width: double.infinity,
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFFFF7597),
                            Color(0xFF7C3AED),
                            Color(0xFF4EA8DE),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF7C3AED,
                            ).withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Coming Soon...',
                        style: GoogleFonts.manrope(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.description,
    required this.iconBg,
    required this.iconColor,
  });

  final IconData icon;
  final String title;
  final String description;
  final Color iconBg;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: iconColor.withValues(alpha: 0.25),
              ),
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.manrope(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: const Color(0xFF94A3B8),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
      padding: const EdgeInsets.fromLTRB(24, 38, 24, 20),
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
                bgColor: const Color(0xFFFFDD00),
                textColor: const Color(0xFF0F172A),
                iconColor: const Color(0xFF0F172A),
                onTap: () => _launch('https://buymeacoffee.com/devakesu'),
              ),
              const SizedBox(width: 8),
              _BrandingChip(
                icon: LucideIcons.star,
                label: 'Star on GitHub',
                bgColor: const Color(0xFF24292F),
                textColor: Colors.white,
                iconColor: const Color(0xFFFCD34D),
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
    required this.bgColor,
    required this.textColor,
    required this.iconColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color bgColor;
  final Color textColor;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ScalePressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: bgColor.withValues(alpha: 0.15)),
          boxShadow: [
            BoxShadow(
              color: bgColor.withValues(alpha: 0.18),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: iconColor),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: textColor,
                letterSpacing: 0.2,
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
    this.trailing,
    this.onTap,
  });
  final IconData icon;
  final String label;
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
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Row(
              children: [
                Container(
                  width: 3.5,
                  height: 12,
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1E293B),
                    letterSpacing: 0.2,
                    shadows: const [
                      Shadow(
                        color: Color(0xFFF4F6FA),
                        blurRadius: 8,
                      ),
                      Shadow(
                        color: Color(0xFFF4F6FA),
                        blurRadius: 4,
                      ),
                      Shadow(
                        color: Color(0xFFF4F6FA),
                        offset: Offset(1, 1),
                      ),
                      Shadow(
                        color: Color(0xFFF4F6FA),
                        offset: Offset(-1, -1),
                      ),
                    ],
                  ),
                ),
              ],
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
                    icon: LucideIcons.download,
                    label: 'Export My Data',
                    iconColor: const Color(0xFF64748B),
                    labelColor: const Color(0xFF0F172A),
                    showDivider: true,
                    onTap: () => unawaited(startDataExport(context)),
                  ),
                  _ActionRow(
                    icon: LucideIcons.trash2,
                    label: 'Delete Account',
                    iconColor: AppColors.error,
                    labelColor: AppColors.error,
                    showDivider: false,
                    onTap: () => _openDeleteAccount(context),
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
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      LucideIcons.logOut,
                      color: AppColors.error,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Sign out?',
                      style: GoogleFonts.manrope(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                "You'll need to sign in again to access your account.",
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppColors.inkMuted,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.manrope(
                          fontWeight: FontWeight.w700,
                          color: AppColors.inkMuted,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.of(ctx).pop(true),
                        borderRadius: BorderRadius.circular(14),
                        child: Ink(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            color: const Color(0xFF0F172A),
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Center(
                              child: Text(
                                'Sign out',
                                style: GoogleFonts.manrope(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed == true && context.mounted) {
      await SignalKeyService.instance.wipeLocalData();
      await Supabase.instance.client.auth.signOut();
    }
  }

  void _openDeleteAccount(BuildContext context) {
    unawaited(context.push<void>('/settings/delete-account'));
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
