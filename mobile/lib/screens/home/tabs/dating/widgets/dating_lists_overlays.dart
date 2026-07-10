import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/screens/chats/open_chat.dart';
import 'package:nexus/screens/home/tabs/profile/widgets/storage_image.dart';
import 'package:nexus/screens/home/widgets/profile_detail_sheet.dart';
import 'package:nexus/theme/app_colors.dart';
import 'package:nexus/utils/responsive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Let's import showProfileBlockDialog / showProfileReportDialog if they are defined globally or helper imports.
// Note: they are globally visible if they are part of another file, or they can be imported.
// In the dating_tab.dart they might be imported or defined elsewhere. Let's see: dating_tab.dart imports interests_overlay, profile_detail_sheet, etc.

class LikesOverlay extends StatefulWidget {
  const LikesOverlay({
    required this.likes,
    required this.onFetchLikes,
    required this.onOpenLikesDetailsDialog,
    required this.onRecordMatchAction,
    super.key,
  });

  final List<dynamic> likes;
  final Future<void> Function() onFetchLikes;
  final void Function({
    required BuildContext ctx,
    required String actorId,
    required String name,
    required void Function(String actorId) onActioned,
  })
  onOpenLikesDetailsDialog;
  final Future<void> Function(
    String targetId,
    String action,
    String accessToken,
  )
  onRecordMatchAction;

  @override
  State<LikesOverlay> createState() => _LikesOverlayState();
}

class _LikesOverlayState extends State<LikesOverlay> {
  @override
  Widget build(BuildContext context) {
    const themeColor = AppColors.modeDating;
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(50),
              borderRadius: BorderRadius.circular(2.5),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(
                      LucideIcons.heart,
                      color: AppColors.modeDating,
                      size: 24,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Likes',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.modeDating.withAlpha(38),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${widget.likes.length} likes',
                    style: const TextStyle(
                      color: AppColors.modeDating,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: widget.likes.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          LucideIcons.sparkles,
                          color: Colors.white.withAlpha(50),
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No likes yet',
                          style: TextStyle(
                            color: Colors.white.withAlpha(150),
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) => GridView.builder(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: gridColumnsForWidth(
                          constraints.maxWidth,
                        ),
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: 0.82,
                      ),
                      itemCount: widget.likes.length,
                      itemBuilder: (ctx, index) {
                        final item =
                            widget.likes[index] as Map<String, dynamic>;
                        final actorId = item['actor_id'] as String? ?? '';
                        final name = item['name'] as String? ?? 'Unknown';
                        final age = item['age'];
                        final profilePic = item['profile_pic'] as String? ?? '';
                        final isSuperlike = item['action'] == 'superlike';

                        return GestureDetector(
                          onTap: () => widget.onOpenLikesDetailsDialog(
                            ctx: ctx,
                            actorId: actorId,
                            name: name,
                            onActioned: (id) {
                              setState(() {
                                widget.likes.removeWhere(
                                  (dynamic i) =>
                                      (i as Map<String, dynamic>)['actor_id'] ==
                                      id,
                                );
                              });
                              setState(() {});
                            },
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withAlpha(20),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(20),
                                    ),
                                    child: profilePic.isNotEmpty
                                        ? StorageImage(
                                            imagePath: profilePic,
                                          )
                                        : ColoredBox(
                                            color: themeColor.withAlpha(
                                              40,
                                            ),
                                            child: const Center(
                                              child: Icon(
                                                LucideIcons.user,
                                                color: Colors.white38,
                                                size: 36,
                                              ),
                                            ),
                                          ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              age != null
                                                  ? '$name, $age'
                                                  : name,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (isSuperlike)
                                            const Icon(
                                              LucideIcons.star,
                                              color: AppColors.warning,
                                              size: 13,
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        isSuperlike
                                            ? 'Superliked you ⭐'
                                            : 'Liked you ❤️',
                                        style: TextStyle(
                                          color: Colors.white.withAlpha(
                                            140,
                                          ),
                                          fontSize: 11,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class MatchesOverlay extends StatefulWidget {
  const MatchesOverlay({
    required this.matches,
    required this.onFetchMatches,
    required this.onRecordMatchAction,
    super.key,
  });

  final List<dynamic> matches;
  final Future<void> Function() onFetchMatches;
  final Future<void> Function(
    String userId,
    String action,
    String token, {
    String? reason,
    String? reasonDetail,
  })
  onRecordMatchAction;

  @override
  State<MatchesOverlay> createState() => _MatchesOverlayState();
}

class _MatchesOverlayState extends State<MatchesOverlay> {
  void removeMatch(String userId) {
    setState(() {
      widget.matches.removeWhere(
        (dynamic m) => (m as Map<String, dynamic>)['matched_user_id'] == userId,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    const themeColor = AppColors.modeDating;
    final session = Supabase.instance.client.auth.currentSession;
    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(50),
              borderRadius: BorderRadius.circular(2.5),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(
                      LucideIcons.heartHandshake,
                      color: themeColor,
                      size: 24,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Matches',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: themeColor.withAlpha(38),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${widget.matches.length} matched',
                    style: const TextStyle(
                      color: themeColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: widget.matches.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          LucideIcons.heartOff,
                          color: Colors.white.withAlpha(50),
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No matches yet',
                          style: TextStyle(
                            color: Colors.white.withAlpha(150),
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Like someone back from your inbox',
                          style: TextStyle(
                            color: Colors.white.withAlpha(80),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(24, 4, 12, 32),
                    itemCount: widget.matches.length,
                    separatorBuilder: (context, index) =>
                        Divider(color: Colors.white.withAlpha(12)),
                    itemBuilder: (_, i) {
                      final match = widget.matches[i] as Map<String, dynamic>;
                      final matchId = match['match_id'] as String?;
                      final userId = match['matched_user_id'] as String? ?? '';
                      final name = match['name'] as String? ?? 'Unknown';
                      final age = match['age'];
                      final profilePic = match['profile_pic'] as String?;
                      final isNew = match['is_new'] == true;
                      final displayName = age != null ? '$name, $age' : name;

                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 6,
                        ),
                        child: Row(
                          children: [
                            // Avatar
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: themeColor.withAlpha(80),
                                  width: 2,
                                ),
                              ),
                              child: ClipOval(
                                child:
                                    profilePic != null && profilePic.isNotEmpty
                                    ? StorageImage(
                                        imagePath: profilePic,
                                      )
                                    : ColoredBox(
                                        color: themeColor.withAlpha(30),
                                        child: Icon(
                                          LucideIcons.user,
                                          color: themeColor.withAlpha(
                                            160,
                                          ),
                                          size: 26,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Name + new badge
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    displayName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (isNew)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        top: 3,
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: themeColor.withAlpha(
                                            38,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: const Text(
                                          'New match ✨',
                                          style: TextStyle(
                                            color: themeColor,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            // Action buttons
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Chat
                                IconButton(
                                  icon: const Icon(
                                    LucideIcons.messageCircle,
                                    size: 20,
                                  ),
                                  color: Colors.white54,
                                  visualDensity: VisualDensity.compact,
                                  constraints: const BoxConstraints(
                                    minWidth: 44,
                                    minHeight: 44,
                                  ),
                                  tooltip: 'Chat',
                                  onPressed: () => openOrCreateChat(
                                    context,
                                    matchId: matchId,
                                    matchedUserId: userId,
                                    name: name,
                                    profilePic: profilePic,
                                  ),
                                ),
                                // Unmatch
                                IconButton(
                                  icon: const Icon(
                                    LucideIcons.x,
                                    size: 20,
                                  ),
                                  color: Colors.white38,
                                  visualDensity: VisualDensity.compact,
                                  constraints: const BoxConstraints(
                                    minWidth: 44,
                                    minHeight: 44,
                                  ),
                                  tooltip: 'Unmatch',
                                  onPressed: () async {
                                    final ok = await showDialog<bool>(
                                      context: context,
                                      builder: (d) => AlertDialog(
                                        backgroundColor: const Color(
                                          0xFF1E293B,
                                        ),
                                        title: Text(
                                          'Unmatch from $name?',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 17,
                                          ),
                                        ),
                                        content: Text(
                                          "You won't see each other for some time.",
                                          style: TextStyle(
                                            color: Colors.white.withAlpha(160),
                                            fontSize: 14,
                                          ),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(d, false),
                                            child: Text(
                                              'Cancel',
                                              style: TextStyle(
                                                color: Colors.white.withAlpha(
                                                  160,
                                                ),
                                              ),
                                            ),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(d, true),
                                            child: const Text(
                                              'Unmatch',
                                              style: TextStyle(
                                                color: themeColor,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                    if ((ok ?? false) && session != null) {
                                      await widget.onRecordMatchAction(
                                        userId,
                                        'unmatch',
                                        session.accessToken,
                                      );
                                      removeMatch(userId);
                                    }
                                  },
                                ),
                                // Block / Report
                                PopupMenuButton<String>(
                                  icon: const Icon(
                                    LucideIcons.moreVertical,
                                    size: 20,
                                    color: Colors.white38,
                                  ),
                                  color: const Color(0xFF1E293B),
                                  padding: EdgeInsets.zero,
                                  onSelected: (value) async {
                                    if (value == 'block') {
                                      final ok = await showProfileBlockDialog(
                                        context,
                                        name,
                                      );
                                      if ((ok ?? false) && session != null) {
                                        await widget.onRecordMatchAction(
                                          userId,
                                          'block',
                                          session.accessToken,
                                        );
                                        removeMatch(userId);
                                      }
                                    } else if (value == 'report') {
                                      if (!context.mounted) return;
                                      unawaited(
                                        showProfileReportDialog(
                                          context,
                                          themeColor: themeColor,
                                          onConfirmed: (reason, detail) async {
                                            if (session == null) {
                                              return;
                                            }
                                            await widget.onRecordMatchAction(
                                              userId,
                                              'report',
                                              session.accessToken,
                                              reason: reason,
                                              reasonDetail: detail,
                                            );
                                            removeMatch(userId);
                                          },
                                        ),
                                      );
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(
                                      value: 'block',
                                      child: Text(
                                        'Block',
                                        style: TextStyle(
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'report',
                                      child: Text(
                                        'Report',
                                        style: TextStyle(
                                          color: Colors.redAccent,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
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
