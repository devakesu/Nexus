import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/features/chats/providers/chats_providers.dart';
import 'package:nexus/features/chats/widgets/presence_badge.dart';
import 'package:nexus/features/profile/widgets/storage_image.dart';

class ChatListTile extends StatelessWidget {
  const ChatListTile({
    required this.conversation,
    required this.tab,
    required this.themeColor,
    super.key,
  });

  final ChatConversationSummary conversation;
  final String tab;
  final Color themeColor;

  String _relativeTime(DateTime at) {
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }

  @override
  Widget build(BuildContext context) {
    final displayName = conversation.age != null
        ? '${conversation.name ?? 'Nexus user'}, ${conversation.age}'
        : (conversation.name ?? 'Nexus user');
    final profilePic = conversation.profilePic;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: conversation.hasUnread
              ? themeColor.withValues(alpha: 0.35)
              : Colors.transparent,
          width: 1.5,
        ),
        boxShadow: [
          if (conversation.hasUnread)
            BoxShadow(
              color: themeColor.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          else
            const BoxShadow(
              color: Color(0x08000000), // black @ ~3% matching Ambient Card
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => context.push<void>(
            '/chat-conversation',
            extra: {
              'conversationId': conversation.conversationId,
              'matchedUserId': conversation.matchedUserId,
              'tab': tab,
              'name': conversation.name ?? 'Nexus user',
              'profilePic': profilePic,
            },
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ClipOval(
                  child: SizedBox(
                    width: 52,
                    height: 52,
                    child: profilePic != null && profilePic.isNotEmpty
                        ? StorageImage(imagePath: profilePic)
                        : ColoredBox(
                            color: themeColor.withValues(alpha: 0.12),
                            child: Icon(
                              LucideIcons.user,
                              color: themeColor.withValues(alpha: 0.7),
                              size: 26,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      PresenceBadge(
                        peerUserId: conversation.matchedUserId,
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          // ink-muted, not ink-faint: this is real status
                          // copy the user reads, not a placeholder/disabled
                          // state, so it needs to clear 4.5:1 AA contrast.
                          color: AppColors.inkMuted,
                        ),
                        fallback: Text(
                          'Say hi 👋',
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            color: AppColors.inkMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _relativeTime(conversation.lastMessageAt),
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        color: conversation.hasUnread
                            ? themeColor
                            : const Color(0xFFCBD5E1),
                        fontWeight: conversation.hasUnread
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    if (conversation.hasUnread) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: themeColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          conversation.unreadCount > 99
                              ? '99+'
                              : '${conversation.unreadCount}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
