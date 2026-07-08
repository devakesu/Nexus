import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/screens/chats/open_chat.dart';
import 'package:nexus/screens/home/tabs/profile/widgets/storage_image.dart';
import 'package:nexus/screens/home/widgets/profile_detail_sheet.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WavesOverlay extends StatefulWidget {
  const WavesOverlay({
    required this.waves,
    required this.onFetchWaves,
    required this.onOpenWavesDetailsDialog,
    required this.onRecordWavesAction,
    super.key,
  });

  final List<dynamic> waves;
  final Future<void> Function() onFetchWaves;
  final void Function({
    required BuildContext ctx,
    required String actorId,
    required String name,
    required void Function(String actorId) onActioned,
  }) onOpenWavesDetailsDialog;
  final Future<Map<String, dynamic>?> Function(String targetId, String action, String accessToken) onRecordWavesAction;

  @override
  State<WavesOverlay> createState() => _WavesOverlayState();
}

class _WavesOverlayState extends State<WavesOverlay> {
  @override
  Widget build(BuildContext context) {
    const themeColor = Color(0xFF3B82F6);
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
                              LucideIcons.hand,
                              color: Color(0xFFA45E00),
                              size: 24,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Waves',
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
                            color: const Color(0xFFA45E00).withAlpha(38),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${widget.waves.length} waves',
                            style: const TextStyle(
                              color: Color(0xFFA45E00),
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
                    child: widget.waves.isEmpty
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
                                  'No waves yet',
                                  style: TextStyle(
                                    color: Colors.white.withAlpha(150),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  mainAxisSpacing: 16,
                                  crossAxisSpacing: 16,
                                  childAspectRatio: 0.82,
                                ),
                            itemCount: widget.waves.length,
                            itemBuilder: (ctx, index) {
                              final item = widget.waves[index] as Map<String, dynamic>;
                              final actorId = item['actor_id'] as String? ?? '';
                              final name = item['name'] as String? ?? 'Unknown';
                              final age = item['age'];
                              final profilePic =
                                  item['profile_pic'] as String? ?? '';
                              final isSuperwave = item['action'] == 'superlike';

                              return GestureDetector(
                                onTap: () => widget.onOpenWavesDetailsDialog(
                                  ctx: ctx,
                                  actorId: actorId,
                                  name: name,
                                  onActioned: (id) {
                                    setState(() {
                                       widget.waves.removeWhere(
                                         (dynamic i) => (i as Map<String, dynamic>)['actor_id'] == id,
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(
                                        child: ClipRRect(
                                          borderRadius:
                                              const BorderRadius.vertical(
                                                top: Radius.circular(20),
                                              ),
                                          child: profilePic.isNotEmpty
                                              ? StorageImage(
                                                  imagePath: profilePic,
                                                )
                                              : ColoredBox(
                                                  color: themeColor.withValues(alpha: 0.15),
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
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 14,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                if (isSuperwave)
                                                  const Icon(
                                                    LucideIcons.star,
                                                    color: Color(0xFFF59E0B),
                                                    size: 13,
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              isSuperwave
                                                  ? 'Super Waved you ⭐'
                                                  : 'Waved at you 👋',
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
                ],
              ),
            );
  }
}

class FriendsListOverlay extends StatefulWidget {
  const FriendsListOverlay({
    required this.friends,
    required this.onFetchFriends,
    required this.onRecordFriendAction,
    required this.onRemoveFriend,
    super.key,
  });

  final List<dynamic> friends;
  final Future<void> Function() onFetchFriends;
  final Future<bool> Function(
    String targetId,
    String action,
    String accessToken, {
    String? reason,
    String? reasonDetail,
  }) onRecordFriendAction;
  final void Function(String userId) onRemoveFriend;

  @override
  State<FriendsListOverlay> createState() => _FriendsListOverlayState();
}

class _FriendsListOverlayState extends State<FriendsListOverlay> {

  void removeFriend(String userId) {
    setState(() {
      widget.friends.removeWhere((dynamic f) => (f as Map<String, dynamic>)['matched_user_id'] == userId);
    });
  }

  @override
  Widget build(BuildContext context) {
    const themeColor = Color(0xFF3B82F6);
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
                              LucideIcons.users,
                              color: themeColor,
                              size: 24,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Friends',
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
                            '${widget.friends.length} friends',
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
                    child: widget.friends.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  LucideIcons.userX,
                                  color: Colors.white.withAlpha(50),
                                  size: 48,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No friends yet',
                                  style: TextStyle(
                                    color: Colors.white.withAlpha(150),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Wave back at someone from your inbox',
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
                            itemCount: widget.friends.length,
                            separatorBuilder: (_, _) =>
                                Divider(color: Colors.white.withAlpha(12)),
                            itemBuilder: (_, i) {
                              final friend = widget.friends[i] as Map<String, dynamic>;
                              final matchId = friend['match_id'] as String?;
                              final userId =
                                  friend['matched_user_id'] as String? ?? '';
                              final name =
                                  friend['name'] as String? ?? 'Unknown';
                              final age = friend['age'];
                              final profilePic =
                                  friend['profile_pic'] as String?;
                              final isNew = friend['is_new'] == true;
                              final displayName = age != null
                                  ? '$name, $age'
                                  : name;

                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                child: Row(
                                  children: [
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
                                            profilePic != null &&
                                                profilePic.isNotEmpty
                                            ? StorageImage(
                                                imagePath: profilePic,
                                              )
                                            : ColoredBox(
                                                 color: themeColor.withValues(alpha: 0.12),
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
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
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
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 7,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: themeColor.withAlpha(
                                                    38,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        8,
                                                      ),
                                                ),
                                                child: const Text(
                                                  'New friend ✨',
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
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(
                                            LucideIcons.messageCircle,
                                            size: 20,
                                          ),
                                          color: Colors.white54,
                                          visualDensity: VisualDensity.compact,
                                          tooltip: 'Chat',
                                          onPressed: () => openOrCreateChat(
                                            context,
                                            matchId: matchId,
                                            matchedUserId: userId,
                                            name: name,
                                            profilePic: profilePic,
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            LucideIcons.x,
                                            size: 20,
                                          ),
                                          color: Colors.white38,
                                          visualDensity: VisualDensity.compact,
                                          tooltip: 'Unfriend',
                                          onPressed: () async {
                                            final ok = await showDialog<bool>(
                                              context: context,
                                              builder: (d) => AlertDialog(
                                                backgroundColor: const Color(
                                                  0xFF1E293B,
                                                ),
                                                title: Text(
                                                  'Unfriend $name?',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 17,
                                                  ),
                                                ),
                                                content: Text(
                                                  "You won't see each other for some time.",
                                                  style: TextStyle(
                                                    color: Colors.white
                                                        .withAlpha(160),
                                                    fontSize: 14,
                                                  ),
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                          d,
                                                          false,
                                                        ),
                                                    child: Text(
                                                      'Cancel',
                                                      style: TextStyle(
                                                        color: Colors.white
                                                            .withAlpha(
                                                              160,
                                                            ),
                                                      ),
                                                    ),
                                                  ),
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                          d,
                                                          true,
                                                        ),
                                                    child: const Text(
                                                      'Unfriend',
                                                      style: TextStyle(
                                                        color: themeColor,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                            if ((ok ?? false) &&
                                                session != null) {
                                              await widget.onRecordFriendAction(
                                                userId,
                                                'unmatch',
                                                session.accessToken,
                                              );
                                              removeFriend(userId);
                                            }
                                          },
                                        ),
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
                                              final ok =
                                                  await showProfileBlockDialog(
                                                    context,
                                                    name,
                                                  );
                                              if ((ok ?? false) &&
                                                  session != null) {
                                                 await widget.onRecordFriendAction(
                                                   userId,
                                                   'block',
                                                   session.accessToken,
                                                 );
                                                removeFriend(userId);
                                              }
                                            } else if (value == 'report') {
                                              if (!context.mounted) return;
                                              unawaited(
                                                showProfileReportDialog(
                                                  context,
                                                  onConfirmed:
                                                      (reason, detail) async {
                                                         if (session == null) {
                                                           return;
                                                         }
                                                         await widget.onRecordFriendAction(
                                                           userId,
                                                           'report',
                                                           session.accessToken,
                                                           reason: reason,
                                                           reasonDetail: detail,
                                                         );
                                                        removeFriend(userId);
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
