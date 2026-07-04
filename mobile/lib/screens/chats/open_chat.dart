import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/screens/chats/chat_conversation_page.dart';
import 'package:nexus/utils/network_utils.dart';
import 'package:nexus/widgets/nexus_toast.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Idempotently creates (or fetches) the conversation for a match, then
/// pushes the chat screen. Used from the match-celebration screen, the
/// per-tab match-list overlays, and the New Chat picker - anywhere a user
/// can start a conversation with a match.
Future<void> openOrCreateChat(
  BuildContext context, {
  required String? matchId,
  required String matchedUserId,
  required String name,
  String? profilePic,
}) async {
  if (matchId == null) {
    NexusToast.show(
      context,
      'Still setting up this match, try again in a moment.',
    );
    return;
  }

  final session = Supabase.instance.client.auth.currentSession;
  if (session == null) return;

  try {
    final dio = createDio();
    final response = await dio.post<Map<String, dynamic>>(
      '${AppConfig.current.backendUrl}/api/v1/chats',
      data: {'match_id': matchId},
      options: Options(
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
      ),
    );
    final data = response.data;
    if (data == null) throw Exception('Empty response');
    if (!context.mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatConversationPage(
          conversationId: data['conversation_id'] as String,
          matchedUserId: data['matched_user_id'] as String,
          tab: data['tab'] as String,
          name: name,
          profilePic: profilePic,
        ),
      ),
    );
  } on Exception catch (_) {
    if (context.mounted) {
      NexusToast.show(
        context,
        'Could not open chat. Please try again.',
        type: NexusToastType.error,
      );
    }
  }
}
