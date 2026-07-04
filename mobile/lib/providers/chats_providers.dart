import 'package:dio/dio.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/utils/network_utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'chats_providers.g.dart';

class ChatConversationSummary {
  const ChatConversationSummary({
    required this.conversationId,
    required this.matchedUserId,
    required this.name,
    required this.age,
    required this.profilePic,
    required this.lastMessageAt,
  });

  factory ChatConversationSummary.fromJson(Map<String, dynamic> json) {
    return ChatConversationSummary(
      conversationId: json['conversation_id'] as String,
      matchedUserId: json['matched_user_id'] as String,
      name: json['name'] as String?,
      age: json['age'] as int?,
      profilePic: json['profile_pic'] as String?,
      lastMessageAt: DateTime.parse(json['last_message_at'] as String),
    );
  }

  final String conversationId;
  final String matchedUserId;
  final String? name;
  final int? age;
  final String? profilePic;
  final DateTime lastMessageAt;
}

class ChatCandidate {
  const ChatCandidate({
    required this.matchId,
    required this.matchedUserId,
    required this.name,
    required this.age,
    required this.profilePic,
    required this.matchedAt,
  });

  factory ChatCandidate.fromJson(Map<String, dynamic> json) {
    return ChatCandidate(
      matchId: json['match_id'] as String,
      matchedUserId: json['matched_user_id'] as String,
      name: json['name'] as String?,
      age: json['age'] as int?,
      profilePic: json['profile_pic'] as String?,
      matchedAt: DateTime.parse(json['matched_at'] as String),
    );
  }

  final String matchId;
  final String matchedUserId;
  final String? name;
  final int? age;
  final String? profilePic;
  final DateTime matchedAt;
}

Future<String> _requireAccessToken() async {
  final token = Supabase.instance.client.auth.currentSession?.accessToken;
  if (token == null) throw Exception('Not signed in');
  return token;
}

@riverpod
Future<List<ChatConversationSummary>> chatConversations(
  Ref ref,
  String tab,
) async {
  final dio = createDio();
  final token = await _requireAccessToken();
  final response = await dio.get<Map<String, dynamic>>(
    '${AppConfig.current.backendUrl}/api/v1/chats',
    queryParameters: {'tab': tab},
    options: Options(headers: {'Authorization': 'Bearer $token'}),
  );
  final rawList = response.data?['conversations'] as List<dynamic>? ?? [];
  return rawList
      .map(
        (e) => ChatConversationSummary.fromJson(e as Map<String, dynamic>),
      )
      .toList();
}

@riverpod
Future<List<ChatCandidate>> newChatCandidates(Ref ref, String tab) async {
  final dio = createDio();
  final token = await _requireAccessToken();
  final response = await dio.get<Map<String, dynamic>>(
    '${AppConfig.current.backendUrl}/api/v1/chats/new-chat-candidates',
    queryParameters: {'tab': tab},
    options: Options(headers: {'Authorization': 'Bearer $token'}),
  );
  final rawList = response.data?['candidates'] as List<dynamic>? ?? [];
  return rawList
      .map((e) => ChatCandidate.fromJson(e as Map<String, dynamic>))
      .toList();
}
