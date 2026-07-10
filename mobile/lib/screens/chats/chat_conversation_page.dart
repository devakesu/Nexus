import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/providers/chat_conversation_provider.dart';
import 'package:nexus/providers/presence_provider.dart';
import 'package:nexus/screens/chats/chat_theme.dart';
import 'package:nexus/screens/chats/open_chat.dart';
import 'package:nexus/screens/chats/widgets/chat_composer.dart';
import 'package:nexus/screens/chats/widgets/event_planner_sheet.dart';
import 'package:nexus/screens/chats/widgets/message_bubble.dart';
import 'package:nexus/screens/chats/widgets/presence_badge.dart';
import 'package:nexus/screens/home/tabs/profile/widgets/storage_image.dart';
import 'package:nexus/screens/home/widgets/profile_detail_sheet.dart';
import 'package:nexus/services/signal/session_manager.dart';
import 'package:nexus/services/signal/signal_key_service.dart';
import 'package:nexus/theme/app_colors.dart';
import 'package:nexus/widgets/aesthetic_loaders.dart';
import 'package:nexus/widgets/nexus_toast.dart';

/// Individual chat screen: establishes the Signal Protocol session on open
/// (see `session_manager.dart`), then shows the live, end-to-end encrypted
/// message list with a text + emoji composer. Photos, voice, location, and
/// events land in later phases.
class ChatConversationPage extends ConsumerStatefulWidget {
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
  ConsumerState<ChatConversationPage> createState() =>
      _ChatConversationPageState();
}

class _ChatConversationPageState extends ConsumerState<ChatConversationPage>
    with WidgetsBindingObserver {
  final _scrollController = ScrollController();
  Timer? _heartbeatTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startHeartbeat();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    unawaited(PresenceHeartbeat.beat(isOnline: false));
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startHeartbeat();
      unawaited(SignalKeyService.instance.replenishOneTimePrekeysIfNeeded());
    } else {
      _heartbeatTimer?.cancel();
      unawaited(PresenceHeartbeat.beat(isOnline: false));
    }
  }

  void _startHeartbeat() {
    unawaited(PresenceHeartbeat.beat());
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => unawaited(PresenceHeartbeat.beat()),
    );
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    unawaited(
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      ),
    );
  }

  Future<void> _handleSend(String text) async {
    final provider = chatConversationControllerProvider(
      widget.conversationId,
      widget.matchedUserId,
    );
    final ok = await ref.read(provider.notifier).sendText(text);
    if (!ok && mounted) {
      NexusToast.show(
        context,
        'Could not send message. Please try again.',
        type: NexusToastType.error,
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  Future<void> _handleSendImage(Uint8List bytes, String mimeType) async {
    final provider = chatConversationControllerProvider(
      widget.conversationId,
      widget.matchedUserId,
    );
    final ok = await ref
        .read(provider.notifier)
        .sendImage(bytes, mimeType: mimeType);
    if (!ok && mounted) {
      NexusToast.show(
        context,
        'Could not send photo. Please try again.',
        type: NexusToastType.error,
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  Future<void> _handleSendVoice(
    Uint8List bytes,
    String mimeType,
    int durationMs,
  ) async {
    final provider = chatConversationControllerProvider(
      widget.conversationId,
      widget.matchedUserId,
    );
    final ok = await ref
        .read(provider.notifier)
        .sendVoice(bytes, mimeType: mimeType, durationMs: durationMs);
    if (!ok && mounted) {
      NexusToast.show(
        context,
        'Could not send voice message. Please try again.',
        type: NexusToastType.error,
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  Future<void> _handleSendLocation(
    double lat,
    double lng,
    String? label,
  ) async {
    final provider = chatConversationControllerProvider(
      widget.conversationId,
      widget.matchedUserId,
    );
    final ok = await ref
        .read(provider.notifier)
        .sendLocation(lat: lat, lng: lng, label: label);
    if (!ok && mounted) {
      NexusToast.show(
        context,
        'Could not share location. Please try again.',
        type: NexusToastType.error,
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _handlePlanEvent() {
    final theme = chatTabTheme(widget.tab);
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => EventPlannerSheet(
          conversationId: widget.conversationId,
          peerUserId: widget.matchedUserId,
          themeColor: theme.primary,
        ),
      ),
    );
  }

  Future<void> _confirmUnmatch(ChatTabTheme theme) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Unmatch from ${widget.name}?',
          style: const TextStyle(color: Colors.white, fontSize: 17),
        ),
        content: Text(
          "You won't see each other for some time.",
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(d, true),
            child: Text(
              'Unmatch',
              style: TextStyle(
                color: theme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _runMatchAction(action: 'unmatch');
  }

  Future<void> _handleBlock() async {
    final ok = await showProfileBlockDialog(context, widget.name);
    if (ok != true || !mounted) return;
    await _runMatchAction(action: 'block');
  }

  Future<void> _handleReport() async {
    final theme = chatTabTheme(widget.tab);
    await showProfileReportDialog(
      context,
      themeColor: theme.primary,
      onConfirmed: (reason, detail) => _runMatchAction(
        action: 'report',
        reason: reason,
        reasonDetail: detail,
      ),
    );
  }

  Future<void> _runMatchAction({
    required String action,
    String? reason,
    String? reasonDetail,
  }) async {
    final success = await recordMatchAction(
      targetId: widget.matchedUserId,
      action: action,
      tab: widget.tab,
      reason: reason,
      reasonDetail: reasonDetail,
    );
    if (!mounted) return;
    if (success) {
      Navigator.of(context).pop();
    } else {
      NexusToast.show(
        context,
        'Could not complete that action. Please try again.',
        type: NexusToastType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = chatTabTheme(widget.tab);
    final asyncState = ref.watch(
      chatConversationControllerProvider(
        widget.conversationId,
        widget.matchedUserId,
      ),
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: _buildAppBar(context, theme),
      body: SafeArea(
        child: asyncState.when(
          loading: () => Center(child: _statusMessage(theme, loading: true)),
          error: (error, stackTrace) => Center(
            child: _statusMessage(
              theme,
              text: 'Could not load this chat. Please try again.',
              icon: LucideIcons.circleAlert,
              iconColor: AppColors.error,
            ),
          ),
          data: (chatState) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _scrollToBottom(),
            );
            final showNewDeviceBanner =
                chatState.isNewLocalIdentity &&
                chatState.messages.any((m) => m.decryptFailed);
            return Column(
              children: [
                if (showNewDeviceBanner) _newDeviceBanner(theme),
                if (chatState.conversationClosed)
                  _conversationClosedBanner(theme),
                Expanded(
                  child: chatState.messages.isEmpty
                      ? Center(
                          child: _statusMessage(
                            theme,
                            text: 'Say hi to ${widget.name} 👋',
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
                          itemCount: chatState.messages.length,
                          itemBuilder: (_, i) => MessageBubble(
                            message: chatState.messages[i],
                            themeColor: theme.primary,
                            conversationId: widget.conversationId,
                            peerUserId: widget.matchedUserId,
                            onSecurityAlertTapped: _showSafetyNumberDialog,
                          ),
                        ),
                ),
                if (!chatState.sessionReady && !chatState.conversationClosed)
                  _waitingBanner(theme),
                ChatComposer(
                  themeColor: theme.primary,
                  enabled:
                      chatState.sessionReady && !chatState.conversationClosed,
                  sending: chatState.sending,
                  onSend: _handleSend,
                  onSendImage: _handleSendImage,
                  onSendVoice: _handleSendVoice,
                  onSendLocation: _handleSendLocation,
                  onPlanEvent: _handlePlanEvent,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _statusMessage(
    ChatTabTheme theme, {
    String? text,
    IconData? icon,
    Color? iconColor,
    bool loading = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading)
            const NexusOrbitLoader(size: 48)
          else if (icon != null)
            Icon(icon, size: 40, color: iconColor ?? theme.primary),
          if (text != null) ...[
            const SizedBox(height: 16),
            Text(
              text,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: const Color(0xFF94A3B8),
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _waitingBanner(ChatTabTheme theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: theme.primary.withValues(alpha: 0.08),
      child: Row(
        children: [
          Icon(LucideIcons.clock, size: 15, color: theme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${widget.name} needs to open this chat before you can send a message.',
              style: GoogleFonts.inter(fontSize: 12, color: theme.primary),
            ),
          ),
        ],
      ),
    );
  }

  /// Shown when this device generated a brand-new Signal identity (fresh
  /// install/reinstall) but the conversation already has history from
  /// before - that history is permanently undecryptable by design (private
  /// keys never leave the device), so we say so plainly instead of just
  /// showing a wall of "Could not decrypt" bubbles with no explanation.
  Widget _newDeviceBanner(ChatTabTheme theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: const Color(0xFFFEF3C7),
      child: const Row(
        children: [
          Icon(LucideIcons.shieldAlert, size: 15, color: Color(0xFFB45309)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'This is a new device. Messages sent before you set up Nexus '
              "chat here can't be decrypted.",
              style: TextStyle(fontSize: 12, color: Color(0xFFB45309)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _conversationClosedBanner(ChatTabTheme theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: const Color(0xFFF1F5F9),
      child: const Row(
        children: [
          Icon(LucideIcons.circleOff, size: 15, color: Color(0xFF64748B)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'This conversation has ended. You can no longer send messages here.',
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
          ),
        ],
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
                  child:
                      widget.profilePic != null && widget.profilePic!.isNotEmpty
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.name,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    PresenceBadge(peerUserId: widget.matchedUserId),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(LucideIcons.moreVertical, color: Colors.white),
              onSelected: (value) {
                switch (value) {
                  case 'unmatch':
                    unawaited(_confirmUnmatch(theme));
                  case 'block':
                    unawaited(_handleBlock());
                  case 'report':
                    unawaited(_handleReport());
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'unmatch', child: Text('Unmatch')),
                PopupMenuItem(value: 'block', child: Text('Block')),
                PopupMenuItem(value: 'report', child: Text('Report & Block')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSafetyNumberDialog() async {
    final theme = chatTabTheme(widget.tab);
    final peerUserId = widget.matchedUserId;
    final newKey = UntrustedIdentityRegistry.pendingUntrustedKeys[peerUserId];
    if (newKey == null) return;

    final store = await SignalKeyService.instance.ensureBootstrapped();
    final localKeyPair = await store.getIdentityKeyPair();

    final safetyNumber = await UntrustedIdentityRegistry.computeSafetyNumber(
      localKeyPair,
      newKey,
    );

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Verify Safety Number',
          style: GoogleFonts.manrope(
            fontWeight: FontWeight.w800,
            color: Colors.white,
            fontSize: 18,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'To verify the security of your end-to-end encryption with ${widget.name}, '
              'confirm that the safety number below matches the number on their screen.',
              style: GoogleFonts.inter(
                fontSize: 13.5,
                color: Colors.white70,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black38,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: SelectableText(
                safetyNumber,
                textAlign: TextAlign.center,
                // JetBrains Mono, not Space Mono — DESIGN.md's one mono
                // family, used everywhere else the app shows a code.
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: theme.primary,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'If the numbers match, the session is secure. If they do not match, '
              'the connection may have been intercepted.',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                color: Colors.white60,
                height: 1.4,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'OK',
              style: GoogleFonts.manrope(
                color: theme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
