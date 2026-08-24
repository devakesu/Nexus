import 'dart:async';

import 'package:nexus/core/config/app_config.dart';
import 'package:nexus/core/utils/chats_cache.dart';
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

  Map<String, dynamic> toJson() => {
    'conversation_id': conversationId,
    'matched_user_id': matchedUserId,
    'name': name,
    'age': age,
    'profile_pic': profilePic,
    'last_message_at': lastMessageAt.toIso8601String(),
    'has_unread': hasUnread,
    'unread_count': unreadCount,
  };

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
  bool _disposed = false;

  @override
  Future<List<ChatConversationSummary>> build(String tab) async {
    ref.onDispose(() {
      _disposed = true;
      _debounceTimer?.cancel();
      final ch = _channel;
      if (ch != null) {
        unawaited(Supabase.instance.client.removeChannel(ch));
      }
    });

    _ensureRealtimeSub(tab);

    final cached = await ChatsCache.read(tab);
    if (cached != null) {
      unawaited(
        _fetchAndCache(tab).then((fresh) {
          if (!_disposed) state = AsyncData(fresh);
        }),
      );
      return cached.map(ChatConversationSummary.fromJson).toList();
    }

    return _fetchAndCache(tab);
  }

  void _ensureRealtimeSub(String tab) {
    if (_channel != null) return;
    final myUserId = Supabase.instance.client.auth.currentUser?.id;
    if (myUserId == null) return;

    _channel = Supabase.instance.client.channel(
      'chats-realtime:$tab:$myUserId',
    );
    _channel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'chat_conversations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_a_id',
            value: myUserId,
          ),
          callback: (_) => _debouncedRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'chat_conversations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_b_id',
            value: myUserId,
          ),
          callback: (_) => _debouncedRefresh(),
        )
        .subscribe();
  }

  Future<List<ChatConversationSummary>> _fetchAndCache(String tab) async {
    final dio = createDio();
    await NetworkUtils.requireAccessToken();
    final response = await dio.get<Map<String, dynamic>>(
      '${AppConfig.current.backendUrl}/api/v1/chats',
      queryParameters: {'tab': tab},
    );
    final rawList = response.data?['conversations'] as List<dynamic>? ?? [];
    final maps = rawList.cast<Map<String, dynamic>>();
    unawaited(ChatsCache.write(tab, maps));
    return maps.map(ChatConversationSummary.fromJson).toList();
  }

  void _debouncedRefresh() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      unawaited(refresh());
    });
  }

  Future<void> refresh() async {
    try {
      final list = await _fetchAndCache(tab);
      if (!_disposed) state = AsyncData(list);
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
  ref.keepAlive();
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
bool hasUnreadMessages(Ref ref) {
  for (final tab in ['Dating', 'Friends', 'Professional']) {
    final convos = ref.watch(chatConversationsProvider(tab)).value ?? [];
    if (convos.any((c) => c.hasUnread)) return true;
  }
  return false;
}
