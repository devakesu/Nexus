import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/screens/chats/chat_theme.dart';
import 'package:nexus/screens/home/tabs/profile/widgets/storage_image.dart';
import 'package:nexus/widgets/aesthetic_loaders.dart';

/// Individual chat screen. Message content, Signal Protocol session
/// establishment, and the composer land in later phases - for now this
/// confirms the conversation exists and can be opened from every entry
/// point (header icon, match celebration, per-tab match lists, New Chat).
class ChatConversationPage extends StatelessWidget {
  const ChatConversationPage({
    required this.conversationId,
    required this.matchedUserId,
    required this.tab,
    required this.name,
    this.profilePic,
    super.key,
  });

  final String conversationId;
  final String matchedUserId;
  final String tab;
  final String name;
  final String? profilePic;

  @override
  Widget build(BuildContext context) {
    final theme = chatTabTheme(tab);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: _buildAppBar(context, theme),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const NexusOrbitLoader(size: 56),
              const SizedBox(height: 24),
              Text(
                'Setting up secure messaging…',
                style: GoogleFonts.manrope(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF334155),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Nexus chats are end-to-end encrypted. '
                'Messaging with $name is coming soon.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  color: const Color(0xFF94A3B8),
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, ChatTabTheme theme) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [theme.primary, theme.secondary],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: theme.primary.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leadingWidth: 44,
          leading: IconButton(
            icon: const Icon(LucideIcons.chevronLeft, color: Colors.white),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          titleSpacing: 0,
          title: Row(
            children: [
              ClipOval(
                child: SizedBox(
                  width: 34,
                  height: 34,
                  child: profilePic != null && profilePic!.isNotEmpty
                      ? StorageImage(imagePath: profilePic!)
                      : ColoredBox(
                          color: Colors.white.withValues(alpha: 0.2),
                          child: const Icon(
                            LucideIcons.user,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
