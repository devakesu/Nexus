import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nexus/core/config/app_config.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:nexus/core/widgets/nexus_toast.dart';
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
    );
    final data = response.data;
    if (data == null) throw Exception('Empty response');
    if (!context.mounted) return;

    await context.push<void>(
      '/chat-conversation',
      extra: {
        'conversationId': data['conversation_id'] as String,
        'matchedUserId': data['matched_user_id'] as String,
        'tab': data['tab'] as String,
        'name': name,
        'profilePic': profilePic,
      },
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

/// Calls `/api/v1/matches/action` (unmatch/block/report) - the same
/// endpoint the per-tab match-list overlays use, so a match dissolved from
/// inside a chat behaves identically (dissolves the match row and closes
/// the conversation).
Future<bool> recordMatchAction({
  required String targetId,
  required String action,
  required String tab,
  String? reason,
  String? reasonDetail,
}) async {
  final session = Supabase.instance.client.auth.currentSession;
  if (session == null) return false;
  try {
    final dio = createDio();
    final body = <String, dynamic>{
      'target_id': targetId,
      'action': action,
      'tab': tab,
    };
    if (reason != null) body['reason'] = reason;
    if (reasonDetail != null) body['reason_detail'] = reasonDetail;
    final response = await dio.post<void>(
      '${AppConfig.current.backendUrl}/api/v1/matches/action',
      data: body,
    );
    return response.statusCode == 200;
  } on Exception {
    return false;
  }
}
