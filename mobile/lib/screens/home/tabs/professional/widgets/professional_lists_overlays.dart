import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/screens/chats/open_chat.dart';
import 'package:nexus/screens/home/tabs/profile/widgets/storage_image.dart';
import 'package:nexus/screens/home/widgets/profile_detail_sheet.dart';
import 'package:nexus/utils/responsive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HandshakesOverlay extends StatefulWidget {
  const HandshakesOverlay({
    required this.handshakes,
    required this.onFetchHandshakes,
    required this.onShowHandshakeProfile,
    super.key,
  });

  final List<dynamic> handshakes;
  final Future<void> Function() onFetchHandshakes;
  final void Function({
    required BuildContext ctx,
    required String actorId,
    required String name,
    required void Function(String actorId) onActioned,
  })
  onShowHandshakeProfile;

  @override
  State<HandshakesOverlay> createState() => _HandshakesOverlayState();
}

class _HandshakesOverlayState extends State<HandshakesOverlay> {
  @override
  Widget build(BuildContext context) {
    const themeColor = Color(0xFF007E6D);
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
                      LucideIcons.handshake,
                      color: themeColor,
                      size: 24,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Handshakes',
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
                    '${widget.handshakes.length} handshakes',
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
          const SizedBox(height: 24),
          Expanded(
            child: widget.handshakes.isEmpty
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
                          'No handshakes yet',
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
                      itemCount: widget.handshakes.length,
                      itemBuilder: (ctx, index) {
                        final item =
                            widget.handshakes[index] as Map<String, dynamic>;
                        final actorId = item['actor_id'] as String? ?? '';
                        final name = item['name'] as String? ?? 'Unknown';
                        final age = item['age'];
                        final profilePic = item['profile_pic'] as String? ?? '';
                        final isSuperConnect = item['action'] == 'superlike';

                        return GestureDetector(
                          onTap: () => widget.onShowHandshakeProfile(
                            ctx: ctx,
                            actorId: actorId,
                            name: name,
                            onActioned: (id) {
                              setState(() {
                                widget.handshakes.removeWhere(
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
                                          if (isSuperConnect)
                                            const Icon(
                                              LucideIcons.star,
                                              color: Color(0xFFF59E0B),
                                              size: 13,
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        isSuperConnect
                                            ? 'Super Connected you ⭐'
                                            : 'Handshaked you 🤝',
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

class ConnectionsOverlay extends StatefulWidget {
  const ConnectionsOverlay({
    required this.connections,
    required this.onFetchConnections,
    required this.onRecordConnectionAction,
    super.key,
  });

  final List<dynamic> connections;
  final Future<void> Function() onFetchConnections;
  final Future<bool> Function(
    String targetId,
    String action,
    String accessToken, {
    String? reason,
    String? reasonDetail,
  })
  onRecordConnectionAction;

  @override
  State<ConnectionsOverlay> createState() => _ConnectionsOverlayState();
}

class _ConnectionsOverlayState extends State<ConnectionsOverlay> {
  void removeConnection(String userId) {
    setState(() {
      widget.connections.removeWhere(
        (dynamic c) => (c as Map<String, dynamic>)['matched_user_id'] == userId,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    const themeColor = Color(0xFF007E6D);
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
                      LucideIcons.network,
                      color: themeColor,
                      size: 24,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Connections',
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
                    '${widget.connections.length} connected',
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
            child: widget.connections.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          LucideIcons.network,
                          color: Colors.white.withAlpha(50),
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No connections yet',
                          style: TextStyle(
                            color: Colors.white.withAlpha(150),
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Connect back from your handshakes inbox',
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
                    itemCount: widget.connections.length,
                    separatorBuilder: (_, _) =>
                        Divider(color: Colors.white.withAlpha(12)),
                    itemBuilder: (_, i) {
                      final connection =
                          widget.connections[i] as Map<String, dynamic>;
                      final matchId = connection['match_id'] as String?;
                      final userId =
                          connection['matched_user_id'] as String? ?? '';
                      final name = connection['name'] as String? ?? 'Unknown';
                      final age = connection['age'];
                      final profilePic = connection['profile_pic'] as String?;
                      final isNew = connection['is_new'] == true;
                      final displayName = age != null ? '$name, $age' : name;

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
                                    profilePic != null && profilePic.isNotEmpty
                                    ? StorageImage(
                                        imagePath: profilePic,
                                      )
                                    : ColoredBox(
                                        color: themeColor.withAlpha(30),
                                        child: Center(
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
                            ),
                            const SizedBox(width: 12),
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
                                          'New connection ✨',
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
                                  constraints: const BoxConstraints(
                                    minWidth: 44,
                                    minHeight: 44,
                                  ),
                                  tooltip: 'Message',
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
                                  constraints: const BoxConstraints(
                                    minWidth: 44,
                                    minHeight: 44,
                                  ),
                                  tooltip: 'Disconnect',
                                  onPressed: () async {
                                    final ok = await showDialog<bool>(
                                      context: context,
                                      builder: (d) => AlertDialog(
                                        backgroundColor: const Color(
                                          0xFF1E293B,
                                        ),
                                        title: Text(
                                          'Disconnect from $name?',
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
                                            onPressed: () => Navigator.pop(
                                              d,
                                              false,
                                            ),
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
                                            onPressed: () => Navigator.pop(
                                              d,
                                              true,
                                            ),
                                            child: const Text(
                                              'Disconnect',
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
                                      await widget.onRecordConnectionAction(
                                        userId,
                                        'unmatch',
                                        session.accessToken,
                                      );
                                      removeConnection(userId);
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
                                      final ok = await showProfileBlockDialog(
                                        context,
                                        name,
                                      );
                                      if ((ok ?? false) && session != null) {
                                        await widget.onRecordConnectionAction(
                                          userId,
                                          'block',
                                          session.accessToken,
                                        );
                                        removeConnection(userId);
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
                                            await widget
                                                .onRecordConnectionAction(
                                                  userId,
                                                  'report',
                                                  session.accessToken,
                                                  reason: reason,
                                                  reasonDetail: detail,
                                                );
                                            removeConnection(
                                              userId,
                                            );
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
