import 'dart:async';

import 'package:nexus/core/config/app_config.dart';
import 'package:nexus/core/utils/error_handler.dart';
import 'package:nexus/core/utils/network_utils.dart';
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
    required this.hasUnread,
    required this.unreadCount,
  });

  factory ChatConversationSummary.fromJson(Map<String, dynamic> json) {
    return ChatConversationSummary(
      conversationId: json['conversation_id'] as String,
      matchedUserId: json['matched_user_id'] as String,
      name: json['name'] as String?,
      age: json['age'] as int?,
      profilePic: json['profile_pic'] as String?,
      lastMessageAt: DateTime.parse(json['last_message_at'] as String),
      hasUnread: json['has_unread'] as bool? ?? false,
      unreadCount: json['unread_count'] as int? ?? 0,
    );
  }

  final String conversationId;
  final String matchedUserId;
  final String? name;
  final int? age;
  final String? profilePic;
  final DateTime lastMessageAt;
  final bool hasUnread;
  final int unreadCount;
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

@riverpod
class ChatConversations extends _$ChatConversations {
  RealtimeChannel? _channel;
  Timer? _debounceTimer;

  @override
  Future<List<ChatConversationSummary>> build(String tab) async {
    ref.onDispose(() {
      _debounceTimer?.cancel();
      final ch = _channel;
      if (ch != null) {
        unawaited(Supabase.instance.client.removeChannel(ch));
      }
    });

    final dio = createDio();
    await NetworkUtils.requireAccessToken();
    final response = await dio.get<Map<String, dynamic>>(
      '${AppConfig.current.backendUrl}/api/v1/chats',
      queryParameters: {'tab': tab},
    );
    final rawList = response.data?['conversations'] as List<dynamic>? ?? [];

    if (_channel == null) {
      _channel = Supabase.instance.client.channel('chats-realtime:$tab');
      _channel!
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'chat_messages',
            callback: (_) => _debouncedRefresh(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'chat_conversations',
            callback: (_) => _debouncedRefresh(),
          )
          .subscribe();
    }

    return rawList
        .map(
          (e) => ChatConversationSummary.fromJson(e as Map<String, dynamic>),
        )
        .toList();
  }

  void _debouncedRefresh() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      unawaited(refresh());
    });
  }

  Future<void> refresh() async {
    try {
      final dio = createDio();
      final response = await dio.get<Map<String, dynamic>>(
        '${AppConfig.current.backendUrl}/api/v1/chats',
        queryParameters: {'tab': tab},
      );
      final rawList = response.data?['conversations'] as List<dynamic>? ?? [];
      final list = rawList
          .map(
            (e) => ChatConversationSummary.fromJson(e as Map<String, dynamic>),
          )
          .toList();
      state = AsyncData(list);
    } on Object catch (e, stackTrace) {
      // Retain old state if update fails.
      ErrorHandler.handleError(
        e,
        stackTrace: stackTrace,
        level: ErrorLevel.warning,
        showUi: false,
        customMessage: 'Failed to refresh chat list for tab: $tab',
      );
    }
  }
}

@riverpod
Future<List<ChatCandidate>> newChatCandidates(Ref ref, String tab) async {
  final dio = createDio();
  await NetworkUtils.requireAccessToken();
  final response = await dio.get<Map<String, dynamic>>(
    '${AppConfig.current.backendUrl}/api/v1/chats/new-chat-candidates',
    queryParameters: {'tab': tab},
  );
  final rawList = response.data?['candidates'] as List<dynamic>? ?? [];
  return rawList
      .map((e) => ChatCandidate.fromJson(e as Map<String, dynamic>))
      .toList();
}

@riverpod
class HasUnreadMessages extends _$HasUnreadMessages {
  RealtimeChannel? _channel;
  Timer? _debounceTimer;

  @override
  Future<bool> build() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return false;
    final userId = session.user.id;

    ref.onDispose(() {
      _debounceTimer?.cancel();
      final ch = _channel;
      if (ch != null) {
        unawaited(Supabase.instance.client.removeChannel(ch));
      }
    });

    if (_channel == null) {
      _channel = Supabase.instance.client.channel('global-unread-messages');
      _channel!
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'chat_messages',
            callback: (_) => _debouncedRefresh(),
          )
          .subscribe();
    }

    return _fetch(userId);
  }

  void _debouncedRefresh() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      unawaited(refresh());
    });
  }

  Future<void> refresh() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return;
    final val = await _fetch(session.user.id);
    state = AsyncData(val);
  }

  Future<bool> _fetch(String userId) async {
    try {
      final res = await Supabase.instance.client
          .from('chat_messages')
          .select('id')
          .neq('sender_id', userId)
          .filter('read_at', 'is', null)
          .limit(1);
      return (res as List).isNotEmpty;
    } on Object catch (_) {
      return false;
    }
  }
}
