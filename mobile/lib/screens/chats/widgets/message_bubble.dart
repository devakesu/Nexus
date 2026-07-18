import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/providers/chat_conversation_provider.dart';
import 'package:nexus/screens/chats/widgets/event_card.dart';
import 'package:nexus/screens/chats/widgets/image_message_bubble.dart';
import 'package:nexus/screens/chats/widgets/location_message_bubble.dart';
import 'package:nexus/screens/chats/widgets/voice_message_bubble.dart';
import 'package:nexus/theme/app_colors.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    required this.message,
    required this.themeColor,
    required this.conversationId,
    required this.peerUserId,
    this.onSecurityAlertTapped,
    super.key,
  });

  final ChatMessageView message;
  final Color themeColor;
  final String conversationId;
  final String peerUserId;
  final VoidCallback? onSecurityAlertTapped;

  String _formatTime(DateTime at) {
    final local = at.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final suffix = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  MediaPointer? _parseMediaPointer() {
    final raw = message.plaintext;
    if (raw == null) return null;
    try {
      return MediaPointer.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Exception {
      return null;
    }
  }

  LocationPointer? _parseLocationPointer() {
    final raw = message.plaintext;
    if (raw == null) return null;
    try {
      return LocationPointer.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Exception {
      return null;
    }
  }

  EventPayload? _parseEventPayload() {
    final raw = message.plaintext;
    if (raw == null) return null;
    try {
      return EventPayload.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Exception {
      return null;
    }
  }

  Widget _buildContent(Color textColor) {
    if (message.decryptFailed) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            LucideIcons.shieldAlert,
            size: 14,
            color: AppColors.error,
          ),
          const SizedBox(width: 6),
          Text(
            'Could not decrypt this message',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontStyle: FontStyle.italic,
              color: AppColors.error,
            ),
          ),
        ],
      );
    }

    switch (message.messageType) {
      case 'image':
        final pointer = _parseMediaPointer();
        if (pointer == null) break;
        return ImageMessageBubble(
          pointer: pointer,
          conversationId: conversationId,
          peerUserId: peerUserId,
        );
      case 'voice':
        final pointer = _parseMediaPointer();
        if (pointer == null) break;
        return VoiceMessageBubble(
          pointer: pointer,
          conversationId: conversationId,
          peerUserId: peerUserId,
          isMine: message.isMine,
          themeColor: themeColor,
        );
      case 'location':
        final pointer = _parseLocationPointer();
        if (pointer == null) break;
        return LocationMessageBubble(pointer: pointer, isMine: message.isMine);
    }

    return Text(
      message.plaintext ?? '',
      style: GoogleFonts.inter(fontSize: 14.5, color: textColor, height: 1.35),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (message.messageType == 'security_alert') {
      return Center(
        child: GestureDetector(
          onTap: onSecurityAlertTapped,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  LucideIcons.lock,
                  size: 14,
                  color: Color(0xFFB45309),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    message.plaintext ??
                        'Security code changed. Tap to verify.',
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFB45309),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final isMine = message.isMine;
    final failed = message.decryptFailed;

    // Event cards are self-contained (their own card chrome, status badge,
    // action buttons) rather than living inside the usual colored bubble.
    if (!failed && message.messageType == 'event') {
      final eventInfo = message.eventInfo;
      final payload = _parseEventPayload();
      if (eventInfo != null && payload != null) {
        return Align(
          alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: EventCard(
              payload: payload,
              eventInfo: eventInfo,
              conversationId: conversationId,
              peerUserId: peerUserId,
              themeColor: themeColor,
            ),
          ),
        );
      }
    }

    final bubbleColor = isMine ? themeColor : Colors.white;
    final textColor = isMine ? Colors.white : const Color(0xFF0F172A);

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: failed ? const Color(0xFFFEF2F2) : bubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isMine ? 16 : 4),
              bottomRight: Radius.circular(isMine ? 4 : 16),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildContent(textColor),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatTime(message.createdAt),
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
                      color: isMine
                          ? Colors.white.withValues(alpha: 0.7)
                          : const Color(0xFF94A3B8),
                    ),
                  ),
                  if (isMine) ...[
                    const SizedBox(width: 4),
                    Icon(
                      message.readAt != null
                          ? LucideIcons.checkCheck
                          : LucideIcons.check,
                      size: 13,
                      color: Colors.white.withValues(
                        alpha: message.readAt != null ? 1 : 0.7,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
