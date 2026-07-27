import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/core/widgets/aesthetic_loaders.dart';
import 'package:nexus/features/chats/providers/chats_providers.dart';
import 'package:nexus/features/chats/utils/chat_theme.dart';
import 'package:nexus/features/profile/widgets/storage_image.dart';

/// Bottom sheet listing matches/friends/connections in [tab] with no conversation started yet.
/// Pops with the selected [ChatCandidate], or null if dismissed.
class NewChatSheet extends ConsumerWidget {
  const NewChatSheet({required this.tab, super.key});

  final String tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = chatTabTheme(tab);
    final candidatesAsync = ref.watch(newChatCandidatesProvider(tab));

    final String pluralNoun;
    if (tab == 'Friends') {
      pluralNoun = 'friends';
    } else if (tab == 'Professional') {
      pluralNoun = 'connections';
    } else {
      pluralNoun = 'matches';
    }

    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 5,
            decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(2.5),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Icon(
                  LucideIcons.messageCirclePlus,
                  color: theme.primary,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  'New Chat',
                  style: GoogleFonts.manrope(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: candidatesAsync.when(
              loading: () => const Center(
                child: NexusOrbitLoader(size: 64, lightMode: true),
              ),
              error: (error, stackTrace) => Center(
                child: Text(
                  'Could not load $pluralNoun',
                  style: GoogleFonts.inter(color: AppColors.inkMuted),
                ),
              ),
              data: (candidates) => _CandidatesList(
                candidates: candidates,
                theme: theme,
                tab: tab,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CandidatesList extends StatelessWidget {
  const _CandidatesList({
    required this.candidates,
    required this.theme,
    required this.tab,
  });

  final List<ChatCandidate> candidates;
  final ChatTabTheme theme;
  final String tab;

  @override
  Widget build(BuildContext context) {
    final String pluralNoun;
    final String statusText;
    if (tab == 'Friends') {
      pluralNoun = 'friends';
      statusText = 'Connected';
    } else if (tab == 'Professional') {
      pluralNoun = 'connections';
      statusText = 'Connected';
    } else {
      pluralNoun = 'matches';
      statusText = 'Matched';
    }

    if (candidates.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.usersRound,
                color: theme.primary.withValues(alpha: 0.3),
                size: 44,
              ),
              const SizedBox(height: 12),
              Text(
                'No new $pluralNoun to chat with yet',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  color: AppColors.inkMuted,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      itemCount: candidates.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
      itemBuilder: (context, index) {
        final candidate = candidates[index];
        final displayName = candidate.age != null
            ? '${candidate.name ?? 'Nexus user'}, ${candidate.age}'
            : (candidate.name ?? 'Nexus user');
        final profilePic = candidate.profilePic;

        return Material(
          color: Colors.transparent,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 4),
            leading: ClipOval(
              child: SizedBox(
                width: 48,
                height: 48,
                child: profilePic != null && profilePic.isNotEmpty
                    ? StorageImage(imagePath: profilePic)
                    : ColoredBox(
                        color: theme.primary.withValues(alpha: 0.12),
                        child: Icon(LucideIcons.user, color: theme.primary),
                      ),
              ),
            ),
            title: Text(
              displayName,
              style: GoogleFonts.manrope(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF0F172A),
              ),
            ),
            subtitle: Text(
              '$statusText · say hi 👋',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppColors.inkMuted,
              ),
            ),
            onTap: () => Navigator.of(context).pop(candidate),
          ),
        );
      },
    );
  }
}
