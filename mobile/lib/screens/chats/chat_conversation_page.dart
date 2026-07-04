import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/screens/chats/chat_theme.dart';
import 'package:nexus/screens/home/tabs/profile/widgets/storage_image.dart';
import 'package:nexus/services/signal/session_manager.dart';
import 'package:nexus/widgets/aesthetic_loaders.dart';

enum _SessionState { loading, established, waitingForPeer, error }

/// Individual chat screen. On open, silently performs X3DH key agreement
/// toward the peer (see `session_manager.dart`) so this device is ready to
/// encrypt outbound messages the moment the composer ships in a later
/// phase. Message content/UI itself lands in Phase 3.
class ChatConversationPage extends StatefulWidget {
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
  State<ChatConversationPage> createState() => _ChatConversationPageState();
}

class _ChatConversationPageState extends State<ChatConversationPage> {
  _SessionState _state = _SessionState.loading;

  @override
  void initState() {
    super.initState();
    unawaited(_establishSession());
  }

  Future<void> _establishSession() async {
    setState(() => _state = _SessionState.loading);
    try {
      final ready = await SessionManager.instance.ensureSessionForConversation(
        conversationId: widget.conversationId,
        peerUserId: widget.matchedUserId,
      );
      if (!mounted) return;
      setState(
        () => _state = ready ? _SessionState.established : _SessionState.waitingForPeer,
      );
    } on Exception {
      if (!mounted) return;
      setState(() => _state = _SessionState.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = chatTabTheme(widget.tab);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: _buildAppBar(context, theme),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: _buildBody(theme),
        ),
      ),
    );
  }

  Widget _buildBody(ChatTabTheme theme) {
    switch (_state) {
      case _SessionState.loading:
        return Column(
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
            _hint(
              'Nexus chats are end-to-end encrypted. '
              'Messaging with ${widget.name} is coming soon.',
            ),
          ],
        );
      case _SessionState.established:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.shieldCheck, color: theme.primary, size: 48),
            const SizedBox(height: 20),
            Text(
              'Secure connection established',
              style: GoogleFonts.manrope(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 8),
            _hint(
              'This device is ready to send end-to-end encrypted messages '
              'to ${widget.name}. The message composer is coming soon.',
            ),
          ],
        );
      case _SessionState.waitingForPeer:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.clock, color: theme.primary, size: 48),
            const SizedBox(height: 20),
            Text(
              'Waiting for ${widget.name}',
              style: GoogleFonts.manrope(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 8),
            _hint(
              '${widget.name} needs to open this chat once before a secure '
              "connection can be set up. We'll be ready as soon as they do.",
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _establishSession,
              child: Text(
                'Check again',
                style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w700,
                  color: theme.primary,
                ),
              ),
            ),
          ],
        );
      case _SessionState.error:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.circleAlert, color: Color(0xFFEF4444), size: 44),
            const SizedBox(height: 16),
            _hint('Could not set up secure messaging. Please try again.'),
            const SizedBox(height: 14),
            TextButton(
              onPressed: _establishSession,
              child: Text(
                'Retry',
                style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w700,
                  color: theme.primary,
                ),
              ),
            ),
          ],
        );
    }
  }

  Widget _hint(String text) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: GoogleFonts.inter(
        fontSize: 12.5,
        color: const Color(0xFF94A3B8),
        height: 1.5,
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
                  child: widget.profilePic != null && widget.profilePic!.isNotEmpty
                      ? StorageImage(imagePath: widget.profilePic!)
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
                  widget.name,
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
