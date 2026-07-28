import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/config/app_config.dart';
import 'package:nexus/core/config/filter_options.dart';
import 'package:nexus/core/utils/app_refresh_notifier.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:nexus/core/widgets/nexus_toast.dart';
import 'package:nexus/features/profile/utils/emoji_helper.dart';
import 'package:nexus/features/profile/widgets/storage_image.dart';
import 'package:nexus/features/spotify/providers/spotify_provider.dart';
import 'package:url_launcher/url_launcher.dart';

typedef SheetSafetyCallback = Future<void> Function(BuildContext sheetCtx);

class ProfileDetailSheet extends ConsumerStatefulWidget {
  const ProfileDetailSheet({
    required this.data,
    required this.themeColor,
    required this.scrollController,
    this.actionBar,
    this.onHideTap,
    this.onBlockTap,
    this.onReportTap,
    this.onSpotifyConnectRefresh,
    this.showScoreBadge = true,
    this.showSafetyActions = true,
    super.key,
  });

  final Map<String, dynamic> data;
  final Color themeColor;
  final ScrollController scrollController;
  final Widget? actionBar;
  final SheetSafetyCallback? onHideTap;
  final SheetSafetyCallback? onBlockTap;
  final SheetSafetyCallback? onReportTap;
  final Future<void> Function()? onSpotifyConnectRefresh;
  final bool showScoreBadge;
  final bool showSafetyActions;

  @override
  ConsumerState<ProfileDetailSheet> createState() => _ProfileDetailSheetState();
}

class _ProfileDetailSheetState extends ConsumerState<ProfileDetailSheet>
    with WidgetsBindingObserver {
  late bool _viewerConnected;
  bool _awaitingSpotifyReturn = false;

  @override
  void initState() {
    super.initState();
    _viewerConnected =
        widget.data['viewer_spotify_connected'] as bool? ?? false;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingSpotifyReturn) {
      _awaitingSpotifyReturn = false;
      unawaited(_performSpotifySync());
    }
  }

  Future<void> _performSpotifySync() async {
    if (!mounted) return;
    setState(() => _viewerConnected = true);
    unawaited(ref.refresh(spotifyStatusProvider.future));
    ProfileRefreshNotifier.notifyChanged();
    if (widget.onSpotifyConnectRefresh != null) {
      await widget.onSpotifyConnectRefresh!();
    }
  }

  // ── Data helpers ───────────────────────────────────────────────────────────

  static String _str(Map<String, dynamic> d, String k) =>
      d[k]?.toString() ?? '';

  static List<String> _strList(Map<String, dynamic> d, String k) =>
      d[k] is List ? List<String>.from(d[k] as List) : <String>[];

  // ── Decoder helpers (same as orbit_screen) ────────────────────────────────

  static String _decodeLookingFor(String code) =>
      FilterOptions.lookingForOptions.firstWhere(
        (m) => m['code'] == code,
        orElse: () => {'code': code, 'label': code},
      )['label']!;

  static String _decodeDatingFor(String code) =>
      FilterOptions.datingForOptions.firstWhere(
        (m) => m['code'] == code,
        orElse: () => {'code': code, 'label': code},
      )['label']!;

  // ── Widget helpers (private, scoped to the build method) ──────────────────

  @override
  Widget build(BuildContext context) {
    final theme = widget.themeColor;
    final data = widget.data;
    // ── Extract data ─────────────────────────────────────────────────────────
    final profilePic = _str(data, 'profile_pic');
    final normalPics = _strList(data, 'normal_pics');
    final name = data['name']?.toString() ?? 'Anonymous';
    final age = data['age'];
    final score = ((data['score'] as num?) ?? 0).round();
    final tab = _str(data, 'tab').isNotEmpty ? _str(data, 'tab') : 'Dating';

    final pronouns = _str(data, 'pronouns');
    final displayGender = _str(data, 'display_gender');
    final displaySexuality = _str(data, 'display_sexuality');
    final hometown = _str(data, 'hometown');
    final currentPlace = _str(data, 'current_place');
    final bio = _str(data, 'bio');
    final campusBranch = _str(data, 'campus_branch');
    final campusYear = data['campus_year'];
    final campusName = _str(data, 'campus_name');
    final role = _str(data, 'role_at');
    final roleType = _strList(data, 'role_type');
    final drinking = _str(data, 'drinking');
    final smoking = _str(data, 'smoking');
    final lifestyle = _str(data, 'lifestyle');
    final religiousBeliefs = _str(data, 'religious_beliefs');
    final rawPartnerValues = data['partner_values'];
    final String partnerValues;
    if (rawPartnerValues is List) {
      partnerValues = rawPartnerValues.map((e) => e.toString()).join(', ');
    } else {
      partnerValues = _str(data, 'partner_values');
    }
    final childrenPlans = _str(data, 'children_plans');

    final interests = data['interests'] is Map
        ? Map<String, dynamic>.from(data['interests'] as Map)
        : <String, dynamic>{};
    final subInterests = data['sub_interests'] is Map
        ? Map<String, dynamic>.from(data['sub_interests'] as Map)
        : <String, dynamic>{};
    final interestKeys = interests.keys.toSet();
    final activities = _strList(data, 'activities');
    final languages = _strList(data, 'languages');
    final pets = _strList(data, 'pets');
    final topArtists = _strList(data, 'top_artists');
    final causesSupported = _strList(data, 'causes_supported');
    final datingFor = _strList(data, 'dating_for');
    final lookingFor = _strList(data, 'looking_for');
    final techSkills = _strList(data, 'tech_skills');

    final lookingForLabels = lookingFor.map(_decodeLookingFor).toList();
    final datingForLabels = datingFor.map(_decodeDatingFor).toList();
    final showSexuality =
        (tab == 'Dating' || tab == 'Friends') && displaySexuality.isNotEmpty;

    final musicMatchGrade = data['music_match_grade'] as int?;
    final viewerConnected = _viewerConnected;
    final candidateConnected =
        data['candidate_spotify_connected'] as bool? ?? false;
    final isSelf = !widget.showScoreBadge;

    // ── Local widget helpers ──────────────────────────────────────────────────

    Widget buildMusicMatchCard(BuildContext context) {
      final selfConnected = topArtists.isNotEmpty;
      final effectiveViewerConnected = isSelf ? selfConnected : viewerConnected;
      final effectiveCandidateConnected = isSelf
          ? selfConnected
          : candidateConnected;
      final effectiveMusicMatchGrade = isSelf
          ? (selfConnected ? 10 : null)
          : musicMatchGrade;
      final hasGrade = effectiveMusicMatchGrade != null;

      final showNudge = !effectiveViewerConnected;
      final showNoData =
          effectiveViewerConnected && !effectiveCandidateConnected;

      return Container(
        margin: const EdgeInsets.fromLTRB(18, 12, 18, 12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFFA78BFA).withValues(alpha: 0.12),
              const Color(0xFF7C3AED).withValues(alpha: 0.04),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: const Color(0xFFA78BFA).withValues(alpha: 0.24),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF7C3AED).withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      LucideIcons.music,
                      color: Color(0xFFA78BFA),
                      size: 14,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'MUSIC MATCH',
                      style: TextStyle(
                        color: const Color(0xFFA78BFA).withValues(alpha: 0.9),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.8,
                      ),
                    ),
                  ],
                ),
                if (effectiveViewerConnected &&
                    effectiveCandidateConnected &&
                    hasGrade)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF8B5CF6).withValues(alpha: 0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          LucideIcons.sparkles,
                          color: Colors.white,
                          size: 11,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$effectiveMusicMatchGrade/10',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (showNudge) ...[
              Center(
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1DB954).withValues(alpha: 0.09),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(
                            0xFF1DB954,
                          ).withValues(alpha: 0.24),
                        ),
                      ),
                      child: const Icon(
                        LucideIcons.music,
                        color: Color(0xFF1DB954),
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Unlock Music Match Grade',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Connect your Spotify account to see how your music tastes align!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1DB954),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      onPressed: () async {
                        try {
                          final config = AppConfig.current;
                          final response = await createDio()
                              .get<Map<String, dynamic>>(
                                '${config.backendUrl}/api/v1/spotify/connect',
                              );
                          final authUrl = response.data?['auth_url'] as String?;
                          if (authUrl != null) {
                            _awaitingSpotifyReturn = true;
                            await launchUrl(
                              Uri.parse(authUrl),
                              mode: LaunchMode.externalApplication,
                            );
                          }
                        } on Exception catch (_) {
                          _awaitingSpotifyReturn = false;
                          if (context.mounted) {
                            NexusToast.show(
                              context,
                              'Failed to fetch connection link.',
                              type: NexusToastType.error,
                            );
                          }
                        }
                      },
                      icon: const Icon(LucideIcons.link, size: 14),
                      label: const Text(
                        'Connect Spotify',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ] else if (showNoData) ...[
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    children: [
                      Icon(
                        LucideIcons.music,
                        color: Colors.white.withValues(alpha: 0.24),
                        size: 32,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No music data yet',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "This user hasn't connected Spotify yet.",
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              if (topArtists.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No top artists found.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 13,
                      ),
                    ),
                  ),
                )
              else ...[
                if (effectiveViewerConnected &&
                    effectiveCandidateConnected &&
                    hasGrade) ...[
                  Text(
                    isSelf
                        ? 'Your Signature Sound 🌌'
                        : effectiveMusicMatchGrade >= 8
                        ? 'Incredible Harmony! 🌌'
                        : effectiveMusicMatchGrade >= 5
                        ? 'Good Vibes Align 🎵'
                        : 'Eclectic Mixes 🎧',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: topArtists.map((artist) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFA78BFA).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(
                            0xFFA78BFA,
                          ).withValues(alpha: 0.20),
                        ),
                      ),
                      child: Text(
                        artist,
                        style: const TextStyle(
                          color: Color(0xFFC4B5FD),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ],
        ),
      );
    }

    Widget photoBlock(String path) {
      return AspectRatio(
        aspectRatio: 1,
        child: Container(
          margin: const EdgeInsets.fromLTRB(18, 6, 18, 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Stack(
              fit: StackFit.expand,
              children: [
                StorageImage(imagePath: path),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.15),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget buildSectionCard({
      required String label,
      required List<Widget> children,
      String emoji = '',
      IconData? icon,
      Color? cardThemeColor,
    }) {
      final c = cardThemeColor ?? theme;
      return Container(
        margin: const EdgeInsets.fromLTRB(18, 12, 18, 12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              c.withValues(alpha: 0.12),
              c.withValues(alpha: 0.03),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: c.withValues(alpha: 0.24),
          ),
          boxShadow: [
            BoxShadow(
              color: c.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (emoji.isNotEmpty) ...[
                  Text(emoji, style: const TextStyle(fontSize: 13)),
                  const SizedBox(width: 8),
                ] else if (icon != null) ...[
                  Icon(icon, color: c, size: 13),
                  const SizedBox(width: 8),
                ],
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    color: c.withValues(alpha: 0.9),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.8,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      );
    }

    Widget chipWrap(
      List<String> items, {
      Color? accent,
      Color? labelColor,
      bool useEmoji = false,
      bool inCard = true,
    }) {
      final c = accent ?? theme;
      final wrap = Wrap(
        spacing: 8,
        runSpacing: 8,
        children: items.map((item) {
          final tagIcon = useEmoji
              ? getTagIcon(
                  item,
                  iconSize: 13,
                  iconColor: labelColor ?? c.withValues(alpha: 0.9),
                )
              : null;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: c.withValues(alpha: 0.28)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (tagIcon != null) ...[
                  tagIcon,
                  const SizedBox(width: 5),
                ],
                Text(
                  item,
                  style: TextStyle(
                    color: labelColor ?? c.withValues(alpha: 0.9),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      );
      if (inCard) {
        return wrap;
      }
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: wrap,
      );
    }

    Widget emojiInfoRow(String emoji, String text, {bool inCard = true}) {
      return Padding(
        padding: inCard
            ? const EdgeInsets.only(bottom: 11)
            : const EdgeInsets.fromLTRB(20, 0, 20, 11),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(emoji, style: const TextStyle(fontSize: 17)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(color: Colors.white70, fontSize: 13.5),
              ),
            ),
          ],
        ),
      );
    }

    Widget locationPill(IconData icon, String label) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white38, size: 13),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ],
        ),
      );
    }

    Widget safetyBtn({
      required IconData icon,
      required String label,
      required Color color,
      required SheetSafetyCallback callback,
    }) {
      return Builder(
        builder: (ctx) => GestureDetector(
          onTap: () => callback(ctx),
          behavior: HitTestBehavior.opaque,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(height: 5),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget divider() => Container(
      width: 1,
      height: 28,
      margin: const EdgeInsets.symmetric(horizontal: 18),
      color: Colors.white.withValues(alpha: 0.08),
    );

    // ── Build ─────────────────────────────────────────────────────────────────
    final sections = <Widget>[];

    // Bio
    if (bio.isNotEmpty) {
      sections.add(
        buildSectionCard(
          label: 'About',
          icon: LucideIcons.user,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '"',
                  style: TextStyle(
                    color: theme.withValues(alpha: 0.6),
                    fontSize: 38,
                    height: 0.85,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    bio,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 14,
                      height: 1.7,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // Background - campus + role
    if (campusBranch.isNotEmpty ||
        campusYear != null ||
        campusName.isNotEmpty ||
        role.isNotEmpty ||
        roleType.isNotEmpty) {
      sections.add(
        buildSectionCard(
          label: 'Background',
          emoji: '🎓',
          cardThemeColor: const Color(0xFF6366F1),
          children: [
            if (campusBranch.isNotEmpty ||
                campusYear != null ||
                campusName.isNotEmpty)
              emojiInfoRow(
                '🏛️',
                [
                  if (campusBranch.isNotEmpty) campusBranch,
                  if (campusYear != null) 'Year $campusYear',
                  if (campusName.isNotEmpty) campusName,
                ].where((s) => s.isNotEmpty).join(' · '),
              ),
            if (roleType.isNotEmpty || role.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(
                  top:
                      (campusBranch.isNotEmpty ||
                          campusYear != null ||
                          campusName.isNotEmpty)
                      ? 12.0
                      : 0.0,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(
                        child: Text(
                          '💼',
                          style: TextStyle(fontSize: 17),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (roleType.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: roleType
                                    .map(
                                      (type) => Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 9,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(
                                            alpha: 0.08,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: Colors.white.withValues(
                                              alpha: 0.15,
                                            ),
                                          ),
                                        ),
                                        child: Text(
                                          type,
                                          style: const TextStyle(
                                            color: Colors.white60,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: 0.2,
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                          if (role.isNotEmpty)
                            Text(
                              role,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13.5,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }

    if (tab == 'Professional') {
      if (lookingForLabels.isNotEmpty) {
        sections.add(
          buildSectionCard(
            label: 'Open to',
            emoji: '🤝',
            cardThemeColor: const Color(0xFF06B6D4),
            children: [
              chipWrap(lookingForLabels, accent: const Color(0xFF06B6D4)),
            ],
          ),
        );
      }
      if (techSkills.isNotEmpty) {
        sections.add(
          buildSectionCard(
            label: 'Tech stack',
            emoji: '💻',
            cardThemeColor: const Color(0xFF06B6D4),
            children: [
              chipWrap(
                techSkills,
                accent: const Color(0xFF06B6D4),
                labelColor: const Color(0xFF22D3EE),
              ),
            ],
          ),
        );
      }
      if (activities.isNotEmpty) {
        sections.add(
          buildSectionCard(
            label: 'Activities',
            icon: LucideIcons.activity,
            cardThemeColor: const Color(0xFF94A3B8),
            children: [
              chipWrap(
                activities,
                accent: const Color(0xFF94A3B8),
                labelColor: Colors.white70,
              ),
            ],
          ),
        );
      }
      if (languages.isNotEmpty) {
        sections.add(
          buildSectionCard(
            label: 'Speaks',
            emoji: '🗣️',
            cardThemeColor: const Color(0xFF0EA5E9),
            children: [
              chipWrap(
                languages,
                accent: const Color(0xFF0EA5E9),
                labelColor: Colors.white70,
                useEmoji: true,
              ),
            ],
          ),
        );
      }
      if (interestKeys.isNotEmpty) {
        sections.add(
          buildSectionCard(
            label: 'Interests',
            emoji: '✨',
            cardThemeColor: const Color(0xFFD946EF),
            children: interestsCategories
                .where(
                  (cat) => cat.parents.any(
                    (p) => interestKeys.contains(p.name),
                  ),
                )
                .map((cat) {
                  final matchedParents = cat.parents
                      .where((p) => interestKeys.contains(p.name))
                      .toList();
                  return Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              cat.icon,
                              size: 12,
                              color: const Color(
                                0xFFD946EF,
                              ).withValues(alpha: 0.6),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              cat.name.toUpperCase(),
                              style: TextStyle(
                                color: const Color(
                                  0xFFD946EF,
                                ).withValues(alpha: 0.6),
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.5,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Container(
                                height: 1,
                                color: const Color(
                                  0xFFD946EF,
                                ).withValues(alpha: 0.1),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          children: matchedParents.map((parent) {
                            final subs = subInterests[parent.name] is List
                                ? List<String>.from(
                                    subInterests[parent.name] as List,
                                  )
                                : <String>[];
                            final parentIcon = getTagIcon(
                              parent.name,
                              iconSize: 12,
                              iconColor: const Color(
                                0xFFD946EF,
                              ).withValues(alpha: 0.95),
                            );
                            return Padding(
                              padding: const EdgeInsets.only(
                                right: 12,
                                bottom: 10,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 11,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFD946EF).withValues(
                                        alpha: 0.14,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (parentIcon != null) ...[
                                          parentIcon,
                                          const SizedBox(width: 5),
                                        ],
                                        Text(
                                          parent.name,
                                          style: TextStyle(
                                            color: const Color(0xFFD946EF)
                                                .withValues(
                                                  alpha: 0.95,
                                                ),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (subs.isNotEmpty) ...[
                                    const SizedBox(height: 5),
                                    Wrap(
                                      spacing: 5,
                                      runSpacing: 5,
                                      children: subs.map((sub) {
                                        final subIcon = getTagIcon(
                                          sub,
                                          iconSize: 11,
                                          iconColor: Colors.white60,
                                        );
                                        return Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 9,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(
                                              alpha: 0.07,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            border: Border.all(
                                              color: Colors.white.withValues(
                                                alpha: 0.12,
                                              ),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (subIcon != null) ...[
                                                subIcon,
                                                const SizedBox(width: 4),
                                              ],
                                              Text(
                                                sub,
                                                style: const TextStyle(
                                                  color: Colors.white60,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  );
                })
                .toList(),
          ),
        );
      }
      if (causesSupported.isNotEmpty) {
        sections.add(
          buildSectionCard(
            label: 'Cares about',
            emoji: '🌍',
            cardThemeColor: const Color(0xFF10B981),
            children: [
              chipWrap(
                causesSupported,
                accent: const Color(0xFF10B981),
                labelColor: const Color(0xFF6EE7B7),
                useEmoji: true,
              ),
            ],
          ),
        );
      }
    } else {
      // Dating or Friends
      if (tab == 'Dating' && datingForLabels.isNotEmpty) {
        sections.add(
          buildSectionCard(
            label: 'Here for',
            emoji: '💘',
            cardThemeColor: const Color(0xFFF43F5E),
            children: [
              chipWrap(
                datingForLabels,
                accent: const Color(0xFFF43F5E),
                labelColor: const Color(0xFFFDA4AF),
              ),
            ],
          ),
        );
      }

      if (drinking.isNotEmpty ||
          smoking.isNotEmpty ||
          lifestyle.isNotEmpty ||
          religiousBeliefs.isNotEmpty) {
        sections.add(
          buildSectionCard(
            label: 'Lifestyle',
            emoji: '🌱',
            cardThemeColor: const Color(0xFF84CC16),
            children: [
              if (drinking.isNotEmpty) emojiInfoRow('🍺', 'Drinks $drinking'),
              if (smoking.isNotEmpty) emojiInfoRow('🚬', 'Smokes $smoking'),
              if (lifestyle.isNotEmpty) emojiInfoRow('💫', lifestyle),
              if (religiousBeliefs.isNotEmpty)
                emojiInfoRow('🙏', religiousBeliefs),
            ],
          ),
        );
      }

      if (interestKeys.isNotEmpty) {
        sections.add(
          buildSectionCard(
            label: 'Interests',
            emoji: '✨',
            cardThemeColor: const Color(0xFFD946EF),
            children: interestsCategories
                .where(
                  (cat) => cat.parents.any(
                    (p) => interestKeys.contains(p.name),
                  ),
                )
                .map((cat) {
                  final matchedParents = cat.parents
                      .where((p) => interestKeys.contains(p.name))
                      .toList();
                  return Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              cat.icon,
                              size: 12,
                              color: const Color(
                                0xFFD946EF,
                              ).withValues(alpha: 0.6),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              cat.name.toUpperCase(),
                              style: TextStyle(
                                color: const Color(
                                  0xFFD946EF,
                                ).withValues(alpha: 0.6),
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.5,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Container(
                                height: 1,
                                color: const Color(
                                  0xFFD946EF,
                                ).withValues(alpha: 0.1),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          children: matchedParents.map((parent) {
                            final subs = subInterests[parent.name] is List
                                ? List<String>.from(
                                    subInterests[parent.name] as List,
                                  )
                                : <String>[];
                            final parentIcon = getTagIcon(
                              parent.name,
                              iconSize: 12,
                              iconColor: const Color(
                                0xFFD946EF,
                              ).withValues(alpha: 0.95),
                            );
                            return Padding(
                              padding: const EdgeInsets.only(
                                right: 12,
                                bottom: 10,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 11,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFD946EF).withValues(
                                        alpha: 0.14,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (parentIcon != null) ...[
                                          parentIcon,
                                          const SizedBox(width: 5),
                                        ],
                                        Text(
                                          parent.name,
                                          style: TextStyle(
                                            color: const Color(0xFFD946EF)
                                                .withValues(
                                                  alpha: 0.95,
                                                ),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (subs.isNotEmpty) ...[
                                    const SizedBox(height: 5),
                                    Wrap(
                                      spacing: 5,
                                      runSpacing: 5,
                                      children: subs.map((sub) {
                                        final subIcon = getTagIcon(
                                          sub,
                                          iconSize: 11,
                                          iconColor: Colors.white60,
                                        );
                                        return Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 9,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(
                                              alpha: 0.07,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            border: Border.all(
                                              color: Colors.white.withValues(
                                                alpha: 0.12,
                                              ),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (subIcon != null) ...[
                                                subIcon,
                                                const SizedBox(width: 4),
                                              ],
                                              Text(
                                                sub,
                                                style: const TextStyle(
                                                  color: Colors.white60,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  );
                })
                .toList(),
          ),
        );
      }

      if (causesSupported.isNotEmpty) {
        sections.add(
          buildSectionCard(
            label: 'Cares about',
            emoji: '🌍',
            cardThemeColor: const Color(0xFF10B981),
            children: [
              chipWrap(
                causesSupported,
                accent: const Color(0xFF10B981),
                labelColor: const Color(0xFF6EE7B7),
                useEmoji: true,
              ),
            ],
          ),
        );
      }

      if (tab != 'Friends' &&
          (partnerValues.isNotEmpty || childrenPlans.isNotEmpty)) {
        sections.add(
          buildSectionCard(
            label: 'Relationship',
            emoji: '❤️',
            cardThemeColor: const Color(0xFFF43F5E),
            children: [
              if (partnerValues.isNotEmpty) emojiInfoRow('💞', partnerValues),
              if (childrenPlans.isNotEmpty) emojiInfoRow('👶', childrenPlans),
            ],
          ),
        );
      }

      // Music Match
      sections.add(buildMusicMatchCard(context));

      if (languages.isNotEmpty) {
        sections.add(
          buildSectionCard(
            label: 'Speaks',
            emoji: '🗣️',
            cardThemeColor: const Color(0xFF0EA5E9),
            children: [
              chipWrap(
                languages,
                accent: const Color(0xFF0EA5E9),
                labelColor: Colors.white60,
                useEmoji: true,
              ),
            ],
          ),
        );
      }

      if (pets.isNotEmpty) {
        sections.add(
          buildSectionCard(
            label: 'Pet parent',
            emoji: '🐾',
            cardThemeColor: const Color(0xFFF59E0B),
            children: [
              chipWrap(
                pets,
                accent: const Color(0xFFF59E0B),
                labelColor: const Color(0xFFFDE68A),
                useEmoji: true,
              ),
            ],
          ),
        );
      }
    }

    // Gather photo widgets (only for Dating/Friends)
    final photoWidgets = (tab == 'Dating' || tab == 'Friends')
        ? normalPics.map<Widget>((pic) {
            return Padding(
              padding: const EdgeInsets.only(top: 20),
              child: photoBlock(pic),
            );
          }).toList()
        : <Widget>[];

    final bodyItems = <Widget>[];

    if (tab == 'Dating' || tab == 'Friends') {
      final numSections = sections.length;
      final numPhotos = photoWidgets.length;

      if (numPhotos == 0) {
        bodyItems.addAll(sections);
      } else if (numSections == 0) {
        bodyItems.addAll(photoWidgets);
      } else {
        final insertions = <int, List<Widget>>{};
        if (numPhotos <= numSections) {
          final step = (numSections + 1) / (numPhotos + 1);
          for (var i = 0; i < numPhotos; i++) {
            final target = (i + 1) * step;
            var slot = target.round().clamp(1, numSections);
            while (slot < numSections && insertions.containsKey(slot)) {
              slot++;
            }
            insertions.putIfAbsent(slot, () => <Widget>[]).add(photoWidgets[i]);
          }
        } else {
          for (var i = 0; i < numSections; i++) {
            insertions[i + 1] = [photoWidgets[i]];
          }
          final remaining = <Widget>[];
          for (var i = numSections; i < numPhotos; i++) {
            remaining.add(photoWidgets[i]);
          }
          if (remaining.isNotEmpty) {
            insertions
                .putIfAbsent(numSections, () => <Widget>[])
                .addAll(remaining);
          }
        }

        for (var i = 0; i < numSections; i++) {
          bodyItems.add(sections[i]);
          final sectionNum = i + 1;
          if (insertions.containsKey(sectionNum)) {
            bodyItems.addAll(insertions[sectionNum]!);
          }
        }
      }
    } else {
      bodyItems.addAll(sections);
    }

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF090D1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // ── Scrollable body ────────────────────────────────────────────────
          Expanded(
            child: ListView(
              controller: widget.scrollController,
              padding: EdgeInsets.zero,
              children: [
                // ═══════════════════════════════════════════════════════════
                // HERO PHOTO
                // ═══════════════════════════════════════════════════════════
                AspectRatio(
                  aspectRatio: 1,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(28),
                        ),
                        child: profilePic.isNotEmpty
                            ? StorageImage(imagePath: profilePic)
                            : Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      theme.withValues(alpha: 0.35),
                                      const Color(0xFF090D1A),
                                    ],
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                  ),
                                ),
                                child: const Center(
                                  child: Icon(
                                    LucideIcons.user,
                                    color: Colors.white12,
                                    size: 72,
                                  ),
                                ),
                              ),
                      ),
                      // Gradient overlay
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(28),
                            ),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.5),
                                const Color(0xFF090D1A),
                              ],
                              stops: const [0.0, 0.42, 0.72, 1.0],
                            ),
                          ),
                        ),
                      ),
                      // Drag handle
                      Positioned(
                        top: 12,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                      // Score badge - top right (optional)
                      if (widget.showScoreBadge)
                        Positioned(
                          top: 14,
                          right: 16,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 13,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: theme.withValues(alpha: 0.88),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: theme.withValues(alpha: 0.45),
                                  blurRadius: 18,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  LucideIcons.sparkles,
                                  color: Colors.white,
                                  size: 11,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  '$score%',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      // Name + pronouns + identity pills
                      Positioned(
                        left: 20,
                        right: 20,
                        bottom: 18,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              age != null ? '$name, $age' : name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 30,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.2,
                                shadows: [
                                  Shadow(blurRadius: 10, color: Colors.black54),
                                ],
                              ),
                            ),
                            if (pronouns.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                pronouns,
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 13,
                                  shadows: [
                                    Shadow(
                                      blurRadius: 8,
                                      color: Colors.black45,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            if (displayGender.isNotEmpty || showSexuality) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  if (displayGender.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: 0.15,
                                        ),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: Colors.white.withValues(
                                            alpha: 0.3,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          ...() {
                                            final icon = getTagIcon(
                                              displayGender,
                                              iconSize: 12,
                                              iconColor: Colors.white,
                                            );
                                            return icon != null
                                                ? [
                                                    icon,
                                                    const SizedBox(width: 4),
                                                  ]
                                                : <Widget>[];
                                          }(),
                                          Text(
                                            displayGender,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (showSexuality)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFFEC4899,
                                        ).withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: const Color(
                                            0xFFEC4899,
                                          ).withValues(alpha: 0.4),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          ...() {
                                            final icon = getTagIcon(
                                              displaySexuality,
                                              iconSize: 12,
                                              iconColor: const Color(
                                                0xFFFCCBE5,
                                              ),
                                            );
                                            return icon != null
                                                ? [
                                                    icon,
                                                    const SizedBox(width: 4),
                                                  ]
                                                : <Widget>[];
                                          }(),
                                          Text(
                                            displaySexuality,
                                            style: const TextStyle(
                                              color: Color(0xFFFCCBE5),
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // ═══════════════════════════════════════════════════════════
                // LOCATION PILLS
                // ═══════════════════════════════════════════════════════════
                if (currentPlace.isNotEmpty || hometown.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (currentPlace.isNotEmpty)
                          locationPill(LucideIcons.mapPin, currentPlace),
                        if (hometown.isNotEmpty && hometown != currentPlace)
                          locationPill(LucideIcons.home, 'From $hometown'),
                      ],
                    ),
                  ),

                ...bodyItems,
                // ═══════════════════════════════════════════════════════════
                // SAFETY ACTIONS - Hide · Block · Report
                // ═══════════════════════════════════════════════════════════
                if (widget.showSafetyActions &&
                    widget.onHideTap != null &&
                    widget.onBlockTap != null &&
                    widget.onReportTap != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 36, 20, 0),
                    child: Column(
                      children: [
                        Divider(
                          color: Colors.white.withValues(alpha: 0.07),
                          height: 1,
                        ),
                        const SizedBox(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            safetyBtn(
                              icon: LucideIcons.eyeOff,
                              label: 'Hide',
                              color: Colors.white38,
                              callback: widget.onHideTap!,
                            ),
                            divider(),
                            safetyBtn(
                              icon: LucideIcons.shieldOff,
                              label: 'Block',
                              color: Colors.orange,
                              callback: widget.onBlockTap!,
                            ),
                            divider(),
                            safetyBtn(
                              icon: LucideIcons.flag,
                              label: 'Report',
                              color: Colors.redAccent,
                              callback: widget.onReportTap!,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),

                const SizedBox(height: 28),
              ],
            ),
          ),

          // ── Sticky action bar ──────────────────────────────────────────────
          ?widget.actionBar,
        ],
      ),
    );
  }
}

// ── Shared dialog helpers ─────────────────────────────────────────────────────

Future<bool?> showProfileBlockDialog(BuildContext context, String name) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text(
        'Block user?',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      content: Text(
        "$name will no longer appear in your discovery, and you'll disappear from theirs.",
        style: const TextStyle(color: Colors.white54, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text(
            'Cancel',
            style: TextStyle(color: Colors.white38),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: Colors.orange),
          child: const Text(
            'Block',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    ),
  );
}

Future<void> showProfileReportDialog(
  BuildContext context, {
  required Future<void> Function(String reason, String? detail) onConfirmed,
  required Color themeColor,
}) async {
  String? selectedReason;
  final otherCtrl = TextEditingController();
  final otherFocusNode = FocusNode();

  const reasons = [
    ('scam', 'Scam or Fraud'),
    ('bot', 'Bot / Fake Account'),
    ('harassment', 'Harassment'),
    ('inappropriate', 'Inappropriate Content'),
    ('spam', 'Spam'),
    ('underage', 'Underage User'),
    ('other', 'Other'),
  ];

  bool isReportValid() {
    if (selectedReason == null) return false;
    if (selectedReason != 'other') return true;
    final alphaChars = otherCtrl.text.replaceAll(RegExp('[^a-zA-Z]'), '');
    return alphaChars.length >= 5;
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (dialogCtx, setDialogState) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Report & Block',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Why are you reporting this profile?',
                style: TextStyle(color: Colors.white60, fontSize: 13),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: reasons.map(((String code, String label) r) {
                  final selected = selectedReason == r.$1;
                  return ChoiceChip(
                    label: Text(r.$2),
                    selected: selected,
                    onSelected: (_) => setDialogState(() {
                      selectedReason = r.$1;
                      if (selectedReason == 'other') {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          otherFocusNode.requestFocus();
                        });
                      }
                    }),
                    selectedColor: themeColor,
                    backgroundColor: const Color(0xFF1E293B),
                    side: BorderSide(
                      color: selected
                          ? Colors.transparent
                          : Colors.white.withValues(alpha: 0.1),
                    ),
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : Colors.white60,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    showCheckmark: false,
                  );
                }).toList(),
              ),
              if (selectedReason == 'other') ...[
                const SizedBox(height: 14),
                TextField(
                  controller: otherCtrl,
                  focusNode: otherFocusNode,
                  autofocus: true,
                  onChanged: (_) => setDialogState(() {}),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  maxLines: 3,
                  maxLength: 200,
                  decoration: InputDecoration(
                    hintText: 'Describe the issue…',
                    hintStyle: const TextStyle(
                      color: Colors.white38,
                      fontSize: 13,
                    ),
                    helperText: isReportValid()
                        ? 'Reason looks good!'
                        : 'A valid reason is required',
                    helperStyle: TextStyle(
                      color: isReportValid()
                          ? Colors.greenAccent.withValues(alpha: 0.7)
                          : Colors.white38,
                      fontSize: 11,
                    ),
                    filled: true,
                    fillColor: const Color(0xFF1E293B),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    counterStyle: const TextStyle(
                      color: Colors.white24,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              const Text(
                'This profile will also be blocked.',
                style: TextStyle(color: Colors.white24, fontSize: 11),
              ),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white38),
            ),
          ),
          ElevatedButton(
            onPressed: isReportValid()
                ? () => Navigator.pop(dialogCtx, true)
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: themeColor,
              disabledBackgroundColor: Colors.white12,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text(
              'Report & Block',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    ),
  );

  final detail = (confirmed == true && selectedReason == 'other')
      ? otherCtrl.text.trim()
      : null;

  // Delay disposal to allow the dialog fade-out transition to complete safely
  Future.delayed(const Duration(milliseconds: 400), () {
    otherCtrl.dispose();
    otherFocusNode.dispose();
  });

  if (confirmed ?? false) {
    await onConfirmed(
      selectedReason!,
      (detail?.isEmpty == true) ? null : detail,
    );
  }
}
