import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/features/chats/utils/open_chat.dart';
import 'package:nexus/features/profile/widgets/storage_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ModeCategorySelectionSheet extends StatefulWidget {
  const ModeCategorySelectionSheet({
    required this.title,
    required this.themeColor,
    required this.items,
    required this.onFetchItems,
    required this.onOpenItemDetailsDialog,
    required this.onRecordAction,
    this.emptyMessage = 'No interactions yet',
    this.showDecisionButtons = true,
    super.key,
  });

  final String title;
  final Color themeColor;
  final List<dynamic> items;
  final Future<void> Function() onFetchItems;
  final void Function({
    required BuildContext ctx,
    required String actorId,
    required String name,
    required void Function(String actorId) onActioned,
    required void Function() onProfileLoaded,
  })
  onOpenItemDetailsDialog;
  final Future<dynamic> Function(
    String targetId,
    String action,
    String accessToken,
  )
  onRecordAction;
  final String emptyMessage;
  final bool showDecisionButtons;

  @override
  State<ModeCategorySelectionSheet> createState() =>
      _ModeCategorySelectionSheetState();
}

class _ModeCategorySelectionSheetState
    extends State<ModeCategorySelectionSheet> {
  final Set<String> _processingIds = {};

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: widget.themeColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${widget.items.length}',
                        style: TextStyle(
                          color: widget.themeColor,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(LucideIcons.x, color: Colors.white70),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white10, height: 24),
          Expanded(
            child: widget.items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          LucideIcons.sparkles,
                          size: 48,
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          widget.emptyMessage,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: widget.onFetchItems,
                    color: widget.themeColor,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: widget.items.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final item = widget.items[index];
                        final actor = item is Map<String, dynamic>
                            ? ((item['actor'] as Map<String, dynamic>?) ?? item)
                            : (item is Map
                                  ? (item['actor'] as Map<String, dynamic>? ??
                                        {})
                                  : <String, dynamic>{});
                        final actorId =
                            (actor['id'] as String?) ??
                            (actor['matched_user_id'] as String?) ??
                            '';
                        final name =
                            (actor['display_name'] as String?) ??
                            (actor['name'] as String?) ??
                            'Nexus User';
                        final avatarUrl =
                            (actor['avatar_url'] as String?) ??
                            (actor['profile_pic'] as String?);
                        final isProcessing = _processingIds.contains(actorId);

                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => widget.onOpenItemDetailsDialog(
                                    ctx: context,
                                    actorId: actorId,
                                    name: name,
                                    onActioned: (id) {
                                      setState(() {
                                        widget.items.removeWhere(
                                          (i) =>
                                              i is Map<String, dynamic> &&
                                              (i['actor'] is Map
                                                  ? (i['actor'] as Map)['id'] ==
                                                        id
                                                  : i['matched_user_id'] == id),
                                        );
                                      });
                                    },
                                    onProfileLoaded: () {},
                                  ),
                                  child: Row(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(24),
                                        child: StorageImage(
                                          imagePath: avatarUrl ?? '',
                                          width: 48,
                                          height: 48,
                                          errorWidget: ColoredBox(
                                            color: widget.themeColor.withValues(
                                              alpha: 0.2,
                                            ),
                                            child: Icon(
                                              LucideIcons.user,
                                              color: widget.themeColor,
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
                                              name,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (isProcessing)
                                const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              else if (widget.showDecisionButtons) ...[
                                IconButton(
                                  onPressed: () async {
                                    final token =
                                        Supabase
                                            .instance
                                            .client
                                            .auth
                                            .currentSession
                                            ?.accessToken ??
                                        '';
                                    setState(() => _processingIds.add(actorId));
                                    await widget.onRecordAction(
                                      actorId,
                                      'pass',
                                      token,
                                    );
                                    if (mounted) {
                                      setState(() {
                                        _processingIds.remove(actorId);
                                        widget.items.removeAt(index);
                                      });
                                    }
                                  },
                                  icon: const Icon(
                                    LucideIcons.x,
                                    color: Colors.white38,
                                  ),
                                ),
                                IconButton(
                                  onPressed: () async {
                                    final token =
                                        Supabase
                                            .instance
                                            .client
                                            .auth
                                            .currentSession
                                            ?.accessToken ??
                                        '';
                                    setState(() => _processingIds.add(actorId));
                                    await widget.onRecordAction(
                                      actorId,
                                      'match',
                                      token,
                                    );
                                    if (mounted) {
                                      setState(() {
                                        _processingIds.remove(actorId);
                                        widget.items.removeAt(index);
                                      });
                                    }
                                  },
                                  icon: Icon(
                                    LucideIcons.check,
                                    color: widget.themeColor,
                                  ),
                                ),
                              ] else ...[
                                IconButton(
                                  onPressed: () async {
                                    final matchId =
                                        (actor['match_id'] as String?) ??
                                        (actor['id'] as String?) ??
                                        (item is Map
                                            ? (item['match_id'] as String?)
                                            : null) ??
                                        (item is Map
                                            ? (item['id'] as String?)
                                            : null);
                                    if (matchId != null && matchId.isNotEmpty) {
                                      final rootContext = Navigator.of(
                                        context,
                                        rootNavigator: true,
                                      ).context;
                                      Navigator.of(context).pop();
                                      await openOrCreateChat(
                                        rootContext,
                                        matchId: matchId,
                                        matchedUserId: actorId,
                                        name: name,
                                        profilePic: avatarUrl,
                                      );
                                    } else {
                                      widget.onOpenItemDetailsDialog(
                                        ctx: context,
                                        actorId: actorId,
                                        name: name,
                                        onActioned: (id) {
                                          setState(() {
                                            widget.items.removeWhere(
                                              (i) =>
                                                  i is Map<String, dynamic> &&
                                                  (i['actor'] is Map
                                                      ? (i['actor']
                                                                as Map)['id'] ==
                                                            id
                                                      : i['matched_user_id'] ==
                                                            id),
                                            );
                                          });
                                        },
                                        onProfileLoaded: () {},
                                      );
                                    }
                                  },
                                  icon: Icon(
                                    LucideIcons.messageCircle,
                                    color: widget.themeColor,
                                  ),
                                ),
                              ],
                            ],
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

class WavesOverlay extends StatelessWidget {
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
    required void Function() onProfileLoaded,
  })
  onOpenWavesDetailsDialog;
  final Future<dynamic> Function(
    String targetId,
    String action,
    String accessToken,
  )
  onRecordWavesAction;

  @override
  Widget build(BuildContext context) {
    return ModeCategorySelectionSheet(
      title: 'Incoming Waves',
      themeColor: AppColors.modeFriends,
      items: waves,
      onFetchItems: onFetchWaves,
      onOpenItemDetailsDialog: onOpenWavesDetailsDialog,
      onRecordAction: onRecordWavesAction,
      emptyMessage: 'No incoming waves right now',
    );
  }
}

class FriendsListOverlay extends StatelessWidget {
  const FriendsListOverlay({
    required this.friends,
    required this.onFetchFriends,
    required this.onRecordFriendAction,
    required this.onRemoveFriend,
    this.onOpenFriendDetailsDialog,
    super.key,
  });

  final List<dynamic> friends;
  final Future<void> Function() onFetchFriends;
  final Function onRecordFriendAction;
  final void Function(dynamic userId) onRemoveFriend;
  final Function? onOpenFriendDetailsDialog;

  @override
  Widget build(BuildContext context) {
    return ModeCategorySelectionSheet(
      title: 'Friends List',
      themeColor: AppColors.modeFriends,
      items: friends,
      onFetchItems: onFetchFriends,
      onOpenItemDetailsDialog:
          ({
            required ctx,
            required actorId,
            required name,
            required onActioned,
            required onProfileLoaded,
          }) {
            if (onOpenFriendDetailsDialog != null) {
              (onOpenFriendDetailsDialog as dynamic)(
                ctx: ctx,
                actorId: actorId,
                name: name,
                onActioned: onActioned,
                onProfileLoaded: onProfileLoaded,
              );
            }
          },
      onRecordAction: (id, act, tok) async =>
          (onRecordFriendAction as dynamic)(id, act, tok),
      emptyMessage: 'No active friends yet',
      showDecisionButtons: false,
    );
  }
}

class LikesOverlay extends StatelessWidget {
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
    required void Function() onProfileLoaded,
  })
  onOpenLikesDetailsDialog;
  final Future<dynamic> Function(
    String targetId,
    String action,
    String accessToken,
  )
  onRecordMatchAction;

  @override
  Widget build(BuildContext context) {
    return ModeCategorySelectionSheet(
      title: 'Incoming Likes',
      themeColor: AppColors.modeDating,
      items: likes,
      onFetchItems: onFetchLikes,
      onOpenItemDetailsDialog: onOpenLikesDetailsDialog,
      onRecordAction: onRecordMatchAction,
      emptyMessage: 'No incoming likes right now',
    );
  }
}

class MatchesOverlay extends StatelessWidget {
  const MatchesOverlay({
    required this.matches,
    required this.onFetchMatches,
    required this.onRecordMatchAction,
    this.onOpenMatchDetailsDialog,
    super.key,
  });

  final List<dynamic> matches;
  final Future<void> Function() onFetchMatches;
  final Function onRecordMatchAction;
  final Function? onOpenMatchDetailsDialog;

  @override
  Widget build(BuildContext context) {
    return ModeCategorySelectionSheet(
      title: 'Matches List',
      themeColor: AppColors.modeDating,
      items: matches,
      onFetchItems: onFetchMatches,
      onOpenItemDetailsDialog:
          ({
            required ctx,
            required actorId,
            required name,
            required onActioned,
            required onProfileLoaded,
          }) {
            if (onOpenMatchDetailsDialog != null) {
              (onOpenMatchDetailsDialog as dynamic)(
                ctx: ctx,
                actorId: actorId,
                name: name,
                onActioned: onActioned,
                onProfileLoaded: onProfileLoaded,
              );
            }
          },
      onRecordAction: (id, act, tok) async =>
          (onRecordMatchAction as dynamic)(id, act, tok),
      emptyMessage: 'No active matches yet',
      showDecisionButtons: false,
    );
  }
}

class ConnectsOverlay extends StatelessWidget {
  const ConnectsOverlay({
    required this.connects,
    required this.onFetchConnects,
    required this.onOpenConnectsDetailsDialog,
    required this.onRecordMatchAction,
    super.key,
  });

  final List<dynamic> connects;
  final Future<void> Function() onFetchConnects;
  final void Function({
    required BuildContext ctx,
    required String actorId,
    required String name,
    required void Function(String actorId) onActioned,
    required void Function() onProfileLoaded,
  })
  onOpenConnectsDetailsDialog;
  final Future<dynamic> Function(
    String targetId,
    String action,
    String accessToken,
  )
  onRecordMatchAction;

  @override
  Widget build(BuildContext context) {
    return ModeCategorySelectionSheet(
      title: 'Incoming Connects',
      themeColor: AppColors.modeProfessional,
      items: connects,
      onFetchItems: onFetchConnects,
      onOpenItemDetailsDialog: onOpenConnectsDetailsDialog,
      onRecordAction: onRecordMatchAction,
      emptyMessage: 'No incoming connects right now',
    );
  }
}

class HandshakesOverlay extends StatelessWidget {
  const HandshakesOverlay({
    required this.handshakes,
    required this.onFetchHandshakes,
    required this.onShowHandshakeProfile,
    super.key,
  });

  final List<dynamic> handshakes;
  final Future<void> Function() onFetchHandshakes;
  final Function onShowHandshakeProfile;

  @override
  Widget build(BuildContext context) {
    return ModeCategorySelectionSheet(
      title: 'Handshakes',
      themeColor: AppColors.modeProfessional,
      items: handshakes,
      onFetchItems: onFetchHandshakes,
      onOpenItemDetailsDialog:
          ({
            required ctx,
            required actorId,
            required name,
            required onActioned,
            required onProfileLoaded,
          }) {
            (onShowHandshakeProfile as dynamic)(
              ctx: ctx,
              actorId: actorId,
              name: name,
              onActioned: onActioned,
              onProfileLoaded: onProfileLoaded,
            );
          },
      onRecordAction: (id, act, tok) async {},
      emptyMessage: 'No handshakes yet',
      showDecisionButtons: false,
    );
  }
}

class ConnectionsOverlay extends StatelessWidget {
  const ConnectionsOverlay({
    required this.connections,
    required this.onFetchConnections,
    required this.onRecordConnectionAction,
    this.onOpenConnectionDetailsDialog,
    super.key,
  });

  final List<dynamic> connections;
  final Future<void> Function() onFetchConnections;
  final Function onRecordConnectionAction;
  final Function? onOpenConnectionDetailsDialog;

  @override
  Widget build(BuildContext context) {
    return ModeCategorySelectionSheet(
      title: 'Connections List',
      themeColor: AppColors.modeProfessional,
      items: connections,
      onFetchItems: onFetchConnections,
      onOpenItemDetailsDialog:
          ({
            required ctx,
            required actorId,
            required name,
            required onActioned,
            required onProfileLoaded,
          }) {
            if (onOpenConnectionDetailsDialog != null) {
              (onOpenConnectionDetailsDialog as dynamic)(
                ctx: ctx,
                actorId: actorId,
                name: name,
                onActioned: onActioned,
                onProfileLoaded: onProfileLoaded,
              );
            }
          },
      onRecordAction: (id, act, tok) async =>
          (onRecordConnectionAction as dynamic)(id, act, tok),
      emptyMessage: 'No active connections yet',
      showDecisionButtons: false,
    );
  }
}
