import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/config/filter_options.dart';
import 'package:nexus/screens/home/tabs/profile/utils/emoji_helper.dart';
import 'package:nexus/screens/home/tabs/profile/widgets/storage_image.dart';

// ---------------------------------------------------------------------------
// Shared profile detail sheet - used by OrbitScreen and the Likes inbox.
//
// Callers wrap this in a DraggableScrollableSheet builder and pass:
//   • data          - decrypted profile map from the server
//   • themeColor    - accent colour (tab-specific)
//   • scrollController - from the DraggableScrollableSheet builder
//   • actionBar     - the sticky bottom row (different for orbit vs likes)
//   • onHideTap / onBlockTap / onReportTap - safety-action callbacks that
//     receive the sheet's BuildContext so they can pop / show dialogs
// ---------------------------------------------------------------------------

typedef SheetSafetyCallback = Future<void> Function(BuildContext sheetCtx);

class ProfileDetailSheet extends StatelessWidget {
  const ProfileDetailSheet({
    required this.data,
    required this.themeColor,
    required this.scrollController,
    this.actionBar,
    this.onHideTap,
    this.onBlockTap,
    this.onReportTap,
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
  final bool showScoreBadge;
  final bool showSafetyActions;

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
    final theme = themeColor;
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
    final partnerValues = _str(data, 'partner_values');
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

    // ── Local widget helpers ──────────────────────────────────────────────────

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

    Widget sectionLabel(String label, {String emoji = '', IconData? icon}) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
        child: Row(
          children: [
            if (emoji.isNotEmpty) ...[
              Text(emoji, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 7),
            ] else if (icon != null) ...[
              Icon(icon, color: theme, size: 13),
              const SizedBox(width: 7),
            ],
            Text(
              label.toUpperCase(),
              style: TextStyle(
                color: theme.withValues(alpha: 0.75),
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.8,
              ),
            ),
          ],
        ),
      );
    }

    Widget chipWrap(
      List<String> items, {
      Color? accent,
      Color? labelColor,
      bool useEmoji = false,
    }) {
      final c = accent ?? theme;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items.map((item) {
            final emoji = useEmoji ? getEmojiForTag(item) : '';
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: c.withValues(alpha: 0.28)),
              ),
              child: Text(
                emoji.isNotEmpty ? '$emoji $item' : item,
                style: TextStyle(
                  color: labelColor ?? c.withValues(alpha: 0.9),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          }).toList(),
        ),
      );
    }

    Widget emojiInfoRow(String emoji, String text) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 11),
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
              controller: scrollController,
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
                      if (showScoreBadge)
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
                                      child: Text(
                                        '${getEmojiForTag(displayGender)} $displayGender',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
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
                                      child: Text(
                                        '${getEmojiForTag(displaySexuality)} $displaySexuality',
                                        style: const TextStyle(
                                          color: Color(0xFFFCCBE5),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
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

                // ═══════════════════════════════════════════════════════════
                // BIO
                // ═══════════════════════════════════════════════════════════
                if (bio.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 20, 18, 0),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                      decoration: BoxDecoration(
                        color: theme.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: theme.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Row(
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
                    ),
                  ),

                // ═══════════════════════════════════════════════════════════
                // BACKGROUND - campus + role
                // ═══════════════════════════════════════════════════════════
                if (campusBranch.isNotEmpty ||
                    campusYear != null ||
                    campusName.isNotEmpty ||
                    role.isNotEmpty ||
                    roleType.isNotEmpty) ...[
                  sectionLabel('Background', emoji: '🎓'),
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
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 11),
                      child: Row(
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
                                  Wrap(
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
                                              borderRadius:
                                                  BorderRadius.circular(8),
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
                                if (role.isNotEmpty) ...[
                                  if (roleType.isNotEmpty)
                                    const SizedBox(height: 5),
                                  Text(
                                    role,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],

                // ═══════════════════════════════════════════════════════════
                // DATING FOR (Dating only)
                // ═══════════════════════════════════════════════════════════
                if (tab == 'Dating' && datingForLabels.isNotEmpty) ...[
                  sectionLabel('Here for', emoji: '💘'),
                  chipWrap(
                    datingForLabels,
                    accent: const Color(0xFFEC4899),
                    labelColor: const Color(0xFFFCCBE5),
                  ),
                ],

                // PHOTO BREAK 1
                if ((tab == 'Dating' || tab == 'Friends') &&
                    normalPics.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  photoBlock(normalPics[0]),
                ],

                // ═══════════════════════════════════════════════════════════
                // LIFESTYLE - Dating & Friends (after 1st pic, before interests)
                // ═══════════════════════════════════════════════════════════
                if ((tab == 'Dating' || tab == 'Friends') &&
                    (drinking.isNotEmpty ||
                        smoking.isNotEmpty ||
                        lifestyle.isNotEmpty ||
                        religiousBeliefs.isNotEmpty)) ...[
                  sectionLabel('Lifestyle', emoji: '🌱'),
                  if (drinking.isNotEmpty)
                    emojiInfoRow('🍺', 'Drinks $drinking'),
                  if (smoking.isNotEmpty) emojiInfoRow('🚬', 'Smokes $smoking'),
                  if (lifestyle.isNotEmpty) emojiInfoRow('💫', lifestyle),
                  if (religiousBeliefs.isNotEmpty)
                    emojiInfoRow('🙏', religiousBeliefs),
                ],

                // ═══════════════════════════════════════════════════════════
                // INTERESTS - organized by category (Dating / Friends)
                // ═══════════════════════════════════════════════════════════
                if (tab != 'Professional' && interestKeys.isNotEmpty) ...[
                  sectionLabel('Interests', emoji: '✨'),
                  ...interestsCategories
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
                          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Category rule header
                              Row(
                                children: [
                                  Icon(
                                    cat.icon,
                                    size: 12,
                                    color: theme.withValues(alpha: 0.6),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    cat.name.toUpperCase(),
                                    style: TextStyle(
                                      color: theme.withValues(alpha: 0.6),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Container(
                                      height: 1,
                                      color: theme.withValues(alpha: 0.1),
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
                                  final parentEmoji = getEmojiForTag(
                                    parent.name,
                                  );
                                  return Padding(
                                    padding: const EdgeInsets.only(
                                      right: 12,
                                      bottom: 10,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Parent chip - solid fill, no border
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 11,
                                            vertical: 5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: theme.withValues(
                                              alpha: 0.14,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: Text(
                                            parentEmoji.isNotEmpty
                                                ? '$parentEmoji ${parent.name}'
                                                : parent.name,
                                            style: TextStyle(
                                              color: theme.withValues(
                                                alpha: 0.95,
                                              ),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        if (subs.isNotEmpty) ...[
                                          const SizedBox(height: 5),
                                          Wrap(
                                            spacing: 5,
                                            runSpacing: 5,
                                            children: subs.map((sub) {
                                              final emoji = getEmojiForTag(sub);
                                              return Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 9,
                                                      vertical: 3,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.white
                                                      .withValues(
                                                        alpha: 0.07,
                                                      ),
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                  border: Border.all(
                                                    color: Colors.white
                                                        .withValues(
                                                          alpha: 0.12,
                                                        ),
                                                  ),
                                                ),
                                                child: Text(
                                                  emoji.isNotEmpty
                                                      ? '$emoji $sub'
                                                      : sub,
                                                  style: const TextStyle(
                                                    color: Colors.white60,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w500,
                                                  ),
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
                      }),
                ],

                // PHOTO BREAK 2
                if ((tab == 'Dating' || tab == 'Friends') &&
                    normalPics.length >= 2) ...[
                  const SizedBox(height: 20),
                  photoBlock(normalPics[1]),
                ],

                // ═══════════════════════════════════════════════════════════
                // CAUSES (Dating / Friends)
                // ═══════════════════════════════════════════════════════════
                if (tab != 'Professional' && causesSupported.isNotEmpty) ...[
                  sectionLabel('Cares about', emoji: '🌍'),
                  chipWrap(
                    causesSupported,
                    accent: const Color(0xFF34D399),
                    labelColor: const Color(0xFF6EE7B7),
                    useEmoji: true,
                  ),
                ],

                // ═══════════════════════════════════════════════════════════
                // RELATIONSHIP - partner values + family plans (Dating)
                // ═══════════════════════════════════════════════════════════
                if (tab == 'Dating' &&
                    (partnerValues.isNotEmpty || childrenPlans.isNotEmpty)) ...[
                  sectionLabel('Relationship', emoji: '❤️'),
                  if (partnerValues.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFEC4899,
                          ).withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: const Color(
                              0xFFEC4899,
                            ).withValues(alpha: 0.18),
                          ),
                        ),
                        child: Text(
                          partnerValues,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 14,
                            height: 1.65,
                          ),
                        ),
                      ),
                    ),
                  if (partnerValues.isNotEmpty && childrenPlans.isNotEmpty)
                    const SizedBox(height: 14),
                  if (childrenPlans.isNotEmpty)
                    emojiInfoRow('👶', childrenPlans),
                ],

                // PHOTO BREAK 3
                if ((tab == 'Dating' || tab == 'Friends') &&
                    normalPics.length >= 3) ...[
                  const SizedBox(height: 20),
                  photoBlock(normalPics[2]),
                ],

                // ═══════════════════════════════════════════════════════════
                // LANGUAGES (Dating / Friends)
                // ═══════════════════════════════════════════════════════════
                if (tab != 'Professional' && languages.isNotEmpty) ...[
                  sectionLabel('Speaks', emoji: '🗣️'),
                  chipWrap(
                    languages,
                    accent: Colors.white,
                    labelColor: Colors.white60,
                    useEmoji: true,
                  ),
                ],

                // PHOTO BREAK 4
                if ((tab == 'Dating' || tab == 'Friends') &&
                    normalPics.length >= 4) ...[
                  const SizedBox(height: 20),
                  photoBlock(normalPics[3]),
                ],

                // ═══════════════════════════════════════════════════════════
                // SOUNDTRACK + PETS (Dating / Friends)
                // ═══════════════════════════════════════════════════════════
                if ((tab == 'Dating' || tab == 'Friends') &&
                    topArtists.isNotEmpty) ...[
                  sectionLabel('Soundtrack', emoji: '🎵'),
                  chipWrap(
                    topArtists,
                    accent: const Color(0xFFA78BFA),
                    labelColor: const Color(0xFFC4B5FD),
                  ),
                ],
                if ((tab == 'Dating' || tab == 'Friends') &&
                    pets.isNotEmpty) ...[
                  sectionLabel('Pet parent', emoji: '🐾'),
                  chipWrap(
                    pets,
                    accent: const Color(0xFFFBBF24),
                    labelColor: const Color(0xFFFDE68A),
                    useEmoji: true,
                  ),
                ],

                // ═══════════════════════════════════════════════════════════
                // PROFESSIONAL: Open to · Tech stack · Activities ·
                //               Speaks · Interests · Cares about
                // ═══════════════════════════════════════════════════════════
                if (tab == 'Professional') ...[
                  if (lookingForLabels.isNotEmpty) ...[
                    sectionLabel('Open to', emoji: '🤝'),
                    chipWrap(lookingForLabels),
                  ],
                  if (techSkills.isNotEmpty) ...[
                    sectionLabel('Tech stack', emoji: '💻'),
                    chipWrap(
                      techSkills,
                      accent: Colors.cyanAccent,
                      labelColor: Colors.cyanAccent,
                    ),
                  ],
                  if (activities.isNotEmpty) ...[
                    sectionLabel('Activities', icon: LucideIcons.activity),
                    chipWrap(
                      activities,
                      accent: Colors.white,
                      labelColor: Colors.white60,
                    ),
                  ],
                  if (languages.isNotEmpty) ...[
                    sectionLabel('Speaks', emoji: '🗣️'),
                    chipWrap(
                      languages,
                      accent: Colors.white,
                      labelColor: Colors.white60,
                      useEmoji: true,
                    ),
                  ],
                  if (interestKeys.isNotEmpty) ...[
                    sectionLabel('Interests', emoji: '✨'),
                    ...interestsCategories
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
                            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      cat.icon,
                                      size: 12,
                                      color: theme.withValues(alpha: 0.6),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      cat.name.toUpperCase(),
                                      style: TextStyle(
                                        color: theme.withValues(alpha: 0.6),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1.5,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Container(
                                        height: 1,
                                        color: theme.withValues(alpha: 0.1),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  children: matchedParents.map((parent) {
                                    final subs =
                                        subInterests[parent.name] is List
                                        ? List<String>.from(
                                            subInterests[parent.name] as List,
                                          )
                                        : <String>[];
                                    final parentEmoji = getEmojiForTag(
                                      parent.name,
                                    );
                                    return Padding(
                                      padding: const EdgeInsets.only(
                                        right: 12,
                                        bottom: 10,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 11,
                                              vertical: 5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: theme.withValues(
                                                alpha: 0.14,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              parentEmoji.isNotEmpty
                                                  ? '$parentEmoji ${parent.name}'
                                                  : parent.name,
                                              style: TextStyle(
                                                color: theme.withValues(
                                                  alpha: 0.95,
                                                ),
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          if (subs.isNotEmpty) ...[
                                            const SizedBox(height: 5),
                                            Wrap(
                                              spacing: 5,
                                              runSpacing: 5,
                                              children: subs.map((sub) {
                                                final emoji = getEmojiForTag(
                                                  sub,
                                                );
                                                return Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 9,
                                                        vertical: 3,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white
                                                        .withValues(
                                                          alpha: 0.07,
                                                        ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                    border: Border.all(
                                                      color: Colors.white
                                                          .withValues(
                                                            alpha: 0.12,
                                                          ),
                                                    ),
                                                  ),
                                                  child: Text(
                                                    emoji.isNotEmpty
                                                        ? '$emoji $sub'
                                                        : sub,
                                                    style: const TextStyle(
                                                      color: Colors.white60,
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
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
                        }),
                  ],
                  if (causesSupported.isNotEmpty) ...[
                    sectionLabel('Cares about', emoji: '🌍'),
                    chipWrap(
                      causesSupported,
                      accent: const Color(0xFF34D399),
                      labelColor: const Color(0xFF6EE7B7),
                      useEmoji: true,
                    ),
                  ],
                ],

                // REMAINING PHOTOS (5th+)
                if (tab == 'Dating' || tab == 'Friends')
                  ...normalPics
                      .skip(4)
                      .map(
                        (pic) => Padding(
                          padding: const EdgeInsets.only(top: 20),
                          child: photoBlock(pic),
                        ),
                      ),

                // ═══════════════════════════════════════════════════════════
                // SAFETY ACTIONS - Hide · Block · Report
                // ═══════════════════════════════════════════════════════════
                if (showSafetyActions &&
                    onHideTap != null &&
                    onBlockTap != null &&
                    onReportTap != null)
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
                              callback: onHideTap!,
                            ),
                            divider(),
                            safetyBtn(
                              icon: LucideIcons.shieldOff,
                              label: 'Block',
                              color: Colors.orange,
                              callback: onBlockTap!,
                            ),
                            divider(),
                            safetyBtn(
                              icon: LucideIcons.flag,
                              label: 'Report',
                              color: Colors.redAccent,
                              callback: onReportTap!,
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
          ?actionBar,
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

  const reasons = [
    ('scam', 'Scam or Fraud'),
    ('bot', 'Bot / Fake Account'),
    ('harassment', 'Harassment'),
    ('inappropriate', 'Inappropriate Content'),
    ('spam', 'Spam'),
    ('underage', 'Underage User'),
    ('other', 'Other'),
  ];

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
                    onSelected: (_) =>
                        setDialogState(() => selectedReason = r.$1),
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
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  maxLines: 3,
                  maxLength: 200,
                  decoration: InputDecoration(
                    hintText: 'Describe the issue…',
                    hintStyle: const TextStyle(
                      color: Colors.white38,
                      fontSize: 13,
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
            onPressed: selectedReason == null
                ? null
                : () => Navigator.pop(dialogCtx, true),
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
  Future.delayed(const Duration(milliseconds: 400), otherCtrl.dispose);

  if (confirmed ?? false) {
    await onConfirmed(
      selectedReason!,
      (detail?.isEmpty == true) ? null : detail,
    );
  }
}
