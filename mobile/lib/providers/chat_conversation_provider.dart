import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/services/signal/local_key_vault.dart';
import 'package:nexus/services/signal/message_codec.dart';
import 'package:nexus/services/signal/session_manager.dart';
import 'package:nexus/services/signal/signal_database.dart';
import 'package:nexus/services/signal/signal_key_service.dart';
import 'package:nexus/services/signal/signal_store.dart';
import 'package:nexus/utils/network_utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'chat_conversation_provider.g.dart';

class ChatMessageView {
  const ChatMessageView({
    required this.id,
    required this.senderId,
    required this.isMine,
    required this.createdAt,
    required this.plaintext,
    required this.messageType,
    required this.decryptFailed,
    this.readAt,
  });

  final String id;
  final String senderId;
  final bool isMine;
  final DateTime createdAt;
  final String? plaintext;
  final String messageType;
  final bool decryptFailed;

  /// Metadata-only, refetched from the server every time (never cached
  /// locally) - unlike plaintext, there's no forward-secrecy concern with
  /// re-reading a timestamp. Null if unread, or if the reader has Read
  /// Receipts turned off (the server won't have written it).
  final DateTime? readAt;

  ChatMessageView copyWith({DateTime? readAt}) => ChatMessageView(
    id: id,
    senderId: senderId,
    isMine: isMine,
    createdAt: createdAt,
    plaintext: plaintext,
    messageType: messageType,
    decryptFailed: decryptFailed,
    readAt: readAt ?? this.readAt,
  );
}

class ChatConversationState {
  const ChatConversationState({
    required this.messages,
    required this.sessionReady,
    required this.sending,
  });

  final List<ChatMessageView> messages;
  final bool sessionReady;
  final bool sending;

  ChatConversationState copyWith({
    List<ChatMessageView>? messages,
    bool? sessionReady,
    bool? sending,
  }) {
    return ChatConversationState(
      messages: messages ?? this.messages,
      sessionReady: sessionReady ?? this.sessionReady,
      sending: sending ?? this.sending,
    );
  }
}

@riverpod
class ChatConversationController extends _$ChatConversationController {
  final SignalDatabase _db = SignalDatabase.instance;
  DriftSignalProtocolStore? _store;
  SignalProtocolAddress? _peerAddress;
  RealtimeChannel? _channel;

  @override
  Future<ChatConversationState> build(
    String conversationId,
    String peerUserId,
  ) async {
    ref.onDispose(() {
      final channel = _channel;
      if (channel != null) {
        unawaited(Supabase.instance.client.removeChannel(channel));
      }
    });

    final store = await SignalKeyService.instance.ensureBootstrapped();
    _store = store;
    final address = SignalProtocolAddress(peerUserId, kSignalDeviceId);
    _peerAddress = address;

    final sessionReady = await SessionManager.instance.ensureSessionForConversation(
      conversationId: conversationId,
      peerUserId: peerUserId,
    );

    final rawRows = await Supabase.instance.client
        .from('chat_messages')
        .select()
        .eq('conversation_id', conversationId)
        .order('created_at');
    final rows = List<Map<String, dynamic>>.from(rawRows as List);

    final messages = <ChatMessageView>[];
    for (final row in rows) {
      messages.add(await _resolveMessage(row, store, address));
    }

    _subscribeRealtime(store, address);

    if (messages.any((m) => !m.isMine && m.readAt == null)) {
      unawaited(markAsRead());
    }

    return ChatConversationState(
      messages: messages,
      sessionReady: sessionReady,
      sending: false,
    );
  }

  void _subscribeRealtime(
    DriftSignalProtocolStore store,
    SignalProtocolAddress address,
  ) {
    final channel = Supabase.instance.client.channel('chat:$conversationId');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chat_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (payload) => unawaited(_handleIncoming(payload.newRecord, store, address)),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'chat_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (payload) => _handleUpdated(payload.newRecord),
        )
        .subscribe();
    _channel = channel;
  }

  Future<void> _handleIncoming(
    Map<String, dynamic> row,
    DriftSignalProtocolStore store,
    SignalProtocolAddress address,
  ) async {
    final current = state.value;
    if (current == null) return;
    final id = row['id'] as String;
    if (current.messages.any((m) => m.id == id)) return;

    final view = await _resolveMessage(row, store, address);
    final latest = state.value ?? current;
    state = AsyncData(
      latest.copyWith(
        messages: [...latest.messages, view],
        sessionReady: latest.sessionReady || !view.decryptFailed,
      ),
    );
    // A message just arrived while this conversation is open - mark it
    // (and anything else unread) read right away.
    if (!view.isMine) unawaited(markAsRead());
  }

  void _handleUpdated(Map<String, dynamic> row) {
    final current = state.value;
    if (current == null) return;
    final id = row['id'] as String;
    final rawReadAt = row['read_at'] as String?;
    if (rawReadAt == null) return;
    final readAt = DateTime.parse(rawReadAt);

    final updated = [
      for (final m in current.messages)
        if (m.id == id) m.copyWith(readAt: readAt) else m,
    ];
    state = AsyncData(current.copyWith(messages: updated));
  }

  /// Marks the peer's messages in this conversation as read. No-ops
  /// server-side (without erroring) if this user has Read Receipts off.
  Future<void> markAsRead() async {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null) return;
    try {
      final dio = createDio();
      await dio.patch<void>(
        '${AppConfig.current.backendUrl}/api/v1/chats/$conversationId/messages/read',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } on Exception {
      // Best-effort - failing to mark read is not user-visible.
    }
  }

  /// Resolves a raw `chat_messages` row to a view, decrypting/encrypting at
  /// most once ever per message id (see `LocalMessages` table doc comment).
  Future<ChatMessageView> _resolveMessage(
    Map<String, dynamic> row,
    DriftSignalProtocolStore store,
    SignalProtocolAddress address,
  ) async {
    final id = row['id'] as String;
    final rawReadAt = row['read_at'] as String?;
    final readAt = rawReadAt != null ? DateTime.parse(rawReadAt) : null;

    final cached = await (_db.select(
      _db.localMessages,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (cached != null) {
      final plaintextEnc = cached.plaintextEnc;
      final plaintext = plaintextEnc != null
          ? utf8.decode(
              await LocalKeyVault.instance.decryptBytes(
                Uint8List.fromList(plaintextEnc),
              ),
            )
          : null;
      return ChatMessageView(
        id: id,
        senderId: cached.senderId,
        isMine: cached.isMine,
        createdAt: cached.createdAt,
        plaintext: plaintext,
        messageType: cached.messageType,
        decryptFailed: cached.decryptFailed,
        readAt: readAt,
      );
    }

    final senderId = row['sender_id'] as String;
    final myUserId = Supabase.instance.client.auth.currentUser?.id;
    final isMine = senderId == myUserId;
    final createdAt = DateTime.parse(row['created_at'] as String);
    final messageType = row['message_type'] as String? ?? 'text';

    String? plaintext;
    var decryptFailed = false;
    if (isMine) {
      // Our own historical message with no local cache entry (e.g. sent
      // from a different device) - its plaintext cannot be recovered here.
      decryptFailed = true;
    } else {
      final ciphertext = row['ciphertext'] as String;
      final metadata = row['ciphertext_metadata'] as Map<String, dynamic>? ?? {};
      final signalType = metadata['signal_message_type'] as String? ?? 'whisper';
      plaintext = await MessageCodec.instance.decryptText(
        store: store,
        address: address,
        ciphertextBase64: ciphertext,
        signalMessageType: signalType,
      );
      decryptFailed = plaintext == null;
    }

    await _cacheMessage(
      id: id,
      conversationId: row['conversation_id'] as String,
      senderId: senderId,
      isMine: isMine,
      createdAt: createdAt,
      messageType: messageType,
      plaintext: plaintext,
      decryptFailed: decryptFailed,
    );

    return ChatMessageView(
      id: id,
      senderId: senderId,
      isMine: isMine,
      createdAt: createdAt,
      plaintext: plaintext,
      messageType: messageType,
      decryptFailed: decryptFailed,
      readAt: readAt,
    );
  }

  Future<void> _cacheMessage({
    required String id,
    required String conversationId,
    required String senderId,
    required bool isMine,
    required DateTime createdAt,
    required String messageType,
    required String? plaintext,
    required bool decryptFailed,
  }) async {
    final encrypted = plaintext != null
        ? await LocalKeyVault.instance.encryptBytes(
            Uint8List.fromList(utf8.encode(plaintext)),
          )
        : null;
    await _db
        .into(_db.localMessages)
        .insertOnConflictUpdate(
          LocalMessagesCompanion.insert(
            id: id,
            conversationId: conversationId,
            senderId: senderId,
            isMine: isMine,
            createdAt: createdAt,
            messageType: messageType,
            plaintextEnc: Value(encrypted),
            decryptFailed: Value(decryptFailed),
          ),
        );
  }

  Future<bool> sendText(String text) async {
    final current = state.value;
    final store = _store;
    final address = _peerAddress;
    if (current == null || store == null || address == null) return false;

    state = AsyncData(current.copyWith(sending: true));
    try {
      final envelope = await MessageCodec.instance.encryptText(
        store: store,
        address: address,
        text: text,
      );

      final dio = createDio();
      final token = Supabase.instance.client.auth.currentSession?.accessToken;
      if (token == null) throw Exception('Not signed in');

      final response = await dio.post<Map<String, dynamic>>(
        '${AppConfig.current.backendUrl}/api/v1/chats/$conversationId/messages',
        data: {
          'message_type': 'text',
          'ciphertext': envelope.ciphertextBase64,
          'ciphertext_metadata': {
            'signal_message_type': envelope.signalMessageType,
          },
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      final messageId = response.data?['message_id'] as String?;
      final createdAtRaw = response.data?['created_at'] as String?;
      final myUserId = Supabase.instance.client.auth.currentUser?.id;
      if (messageId != null && myUserId != null) {
        await _cacheMessage(
          id: messageId,
          conversationId: conversationId,
          senderId: myUserId,
          isMine: true,
          createdAt: createdAtRaw != null
              ? DateTime.parse(createdAtRaw)
              : DateTime.now(),
          messageType: 'text',
          plaintext: text,
          decryptFailed: false,
        );
      }
      // The realtime subscription will deliver the row itself and append
      // it (self-inserts fire postgres_changes for the inserting session
      // too), reading straight from the cache we just wrote above.
      return true;
    } on Exception {
      return false;
    } finally {
      final latest = state.value ?? current;
      state = AsyncData(latest.copyWith(sending: false));
    }
  }
}
