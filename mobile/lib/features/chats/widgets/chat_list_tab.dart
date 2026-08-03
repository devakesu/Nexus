import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/core/widgets/aesthetic_loaders.dart';
import 'package:nexus/core/widgets/scale_pressable.dart';
import 'package:nexus/features/chats/providers/chats_providers.dart';
import 'package:nexus/features/chats/providers/presence_provider.dart';
import 'package:nexus/features/chats/utils/chat_theme.dart';
import 'package:nexus/features/chats/utils/open_chat.dart';
import 'package:nexus/features/chats/widgets/chat_list_tile.dart';
import 'package:nexus/features/chats/widgets/new_chat_sheet.dart';
import 'package:nexus/features/profile/widgets/storage_image.dart';

Future<void> _openNewChatSheet(BuildContext context, String tab) async {
  final selected = await showModalBottomSheet<ChatCandidate>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => NewChatSheet(tab: tab),
  );
  if (selected != null && context.mounted) {
    await openOrCreateChat(
      context,
      matchId: selected.matchId,
      matchedUserId: selected.matchedUserId,
      name: selected.name ?? 'Nexus user',
      profilePic: selected.profilePic,
    );
  }
}

/// One tab's worth of the Chats page: active conversations for [tab], plus
/// the floating New Chat entry point for matches not yet chatting.
class ChatListTab extends ConsumerWidget {
  const ChatListTab({required this.tab, super.key});

  final String tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = chatTabTheme(tab);

    ref
      ..listen<AsyncValue<List<ChatConversationSummary>>>(
        chatConversationsProvider(tab),
        (previous, next) {
          final list = next.value;
          if (list != null && list.isNotEmpty) {
            for (final convo in list) {
              if (convo.profilePic != null && convo.profilePic!.isNotEmpty) {
                final provider = resolveStorageImageProvider(convo.profilePic);
                if (provider != null) {
                  unawaited(
                    precacheImage(provider, context).catchError((_) {}),
                  );
                }
              }
            }
            final ids = list.map((c) => c.matchedUserId).toList();
            unawaited(ref.read(batchPresenceProvider.notifier).fetch(ids));
          }
        },
      )
      ..listen<AsyncValue<List<ChatCandidate>>>(
        newChatCandidatesProvider(tab),
        (previous, next) {
          final list = next.value;
          if (list != null && list.isNotEmpty) {
            for (final candidate in list) {
              if (candidate.profilePic != null &&
                  candidate.profilePic!.isNotEmpty) {
                final provider = resolveStorageImageProvider(
                  candidate.profilePic,
                );
                if (provider != null) {
                  unawaited(
                    precacheImage(provider, context).catchError((_) {}),
                  );
                }
              }
            }
          }
        },
      );

    final conversationsAsync = ref.watch(chatConversationsProvider(tab));

    final conversations = conversationsAsync.value;
    final isRevalidating =
        conversationsAsync.isLoading && conversations != null;

    return RefreshIndicator(
      color: theme.primary,
      onRefresh: () async {
        ref
          ..invalidate(chatConversationsProvider(tab))
          ..invalidate(newChatCandidatesProvider(tab));
        await Future.wait([
          ref.read(chatConversationsProvider(tab).future),
          ref.read(newChatCandidatesProvider(tab).future),
        ]);
      },

      child: conversationsAsync.when(
        skipLoadingOnRefresh: false,
        skipLoadingOnReload: true,
        loading: () => conversations != null
            ? _buildContent(
                context,
                conversations,
                isRevalidating,
                theme.primary,
              )
            : const Center(child: NexusOrbitLoader(lightMode: true)),
        error: (error, stackTrace) => conversations != null
            ? _buildContent(context, conversations, false, theme.primary)
            : _ErrorState(
                themeColor: theme.primary,
                onRetry: () => ref.invalidate(chatConversationsProvider(tab)),
              ),
        data: (data) =>
            _buildContent(context, data, isRevalidating, theme.primary),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    List<ChatConversationSummary> conversations,
    bool isRevalidating,
    Color themeColor,
  ) {
    return Column(
      children: [
        if (isRevalidating)
          SizedBox(
            height: 2,
            child: LinearProgressIndicator(
              backgroundColor: themeColor.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation<Color>(themeColor),
            ),
          ),
        Expanded(
          child: conversations.isEmpty
              ? _EmptyState(
                  tab: tab,
                  themeColor: themeColor,
                  onNewChat: () => _openNewChatSheet(context, tab),
                )
              : Stack(
                  children: [
                    ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                      itemCount: conversations.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, index) => ChatListTile(
                        conversation: conversations[index],
                        tab: tab,
                        themeColor: themeColor,
                      ),
                    ),
                    Positioned(
                      right: 20,
                      bottom: 24,
                      child: _NewChatButton(
                        themeColor: themeColor,
                        onTap: () => _openNewChatSheet(context, tab),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _NewChatButton extends StatelessWidget {
  const _NewChatButton({required this.themeColor, required this.onTap});

  final Color themeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ScalePressable(
      onTap: onTap,
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: themeColor,
          borderRadius: BorderRadius.circular(25),
          boxShadow: [
            BoxShadow(
              color: themeColor.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              LucideIcons.messageCirclePlus,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              'New Chat',
              style: GoogleFonts.manrope(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.tab,
    required this.themeColor,
    required this.onNewChat,
  });

  final String tab;
  final Color themeColor;
  final VoidCallback onNewChat;

  @override
  Widget build(BuildContext context) {
    final String noun;
    if (tab == 'Friends') {
      noun = 'friends';
    } else if (tab == 'Professional') {
      noun = 'connections';
    } else {
      noun = '$tab matches';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.messageCircleHeart,
              color: themeColor.withValues(alpha: 0.3),
              size: 52,
            ),
            const SizedBox(height: 16),
            Text(
              'No conversations yet',
              style: GoogleFonts.manrope(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Start a chat with one of your $noun.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: const Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(height: 20),
            ScalePressable(
              onTap: onNewChat,
              child: Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  color: themeColor,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: themeColor.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      LucideIcons.messageCirclePlus,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'New Chat',
                      style: GoogleFonts.manrope(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.themeColor, required this.onRetry});

  final Color themeColor;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              LucideIcons.circleAlert,
              color: AppColors.error,
              size: 36,
            ),
            const SizedBox(height: 12),
            Text(
              'Could not load chats',
              style: GoogleFonts.inter(
                fontSize: 13.5,
                color: AppColors.inkMuted,
              ),
            ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: onRetry,
              child: Text(
                'Retry',
                style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w700,
                  color: themeColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
