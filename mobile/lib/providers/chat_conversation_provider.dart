import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/services/signal/local_key_vault.dart';
import 'package:nexus/services/signal/media_crypto.dart';
import 'package:nexus/services/signal/message_codec.dart';
import 'package:nexus/services/signal/session_manager.dart';
import 'package:nexus/services/signal/signal_database.dart';
import 'package:nexus/services/signal/signal_key_service.dart';
import 'package:nexus/services/signal/signal_store.dart';
import 'package:nexus/utils/error_handler.dart';
import 'package:nexus/utils/network_utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

part 'chat_conversation_provider.g.dart';

/// The decrypted "message" for image/voice types is this JSON pointer,
/// not the media itself - the actual bytes live in the `chat_media`
/// Storage bucket, encrypted with [mediaKeyBase64] (a fresh random key
/// that only ever travels inside this ratchet-encrypted pointer, per
/// Signal's own attachment design - see `media_crypto.dart`).
class MediaPointer {
  const MediaPointer({
    required this.storagePath,
    required this.mediaKeyBase64,
    required this.mimeType,
    this.sizeBytes,
    this.durationMs,
  });

  factory MediaPointer.fromJson(Map<String, dynamic> json) => MediaPointer(
    storagePath: json['storage_path'] as String,
    mediaKeyBase64: json['media_key'] as String,
    mimeType: json['mime_type'] as String,
    sizeBytes: json['size_bytes'] as int?,
    durationMs: json['duration_ms'] as int?,
  );

  final String storagePath;
  final String mediaKeyBase64;
  final String mimeType;

  /// Null when the pointer JSON has no `size_bytes` - deliberately not
  /// coerced to 0, so a UI reading this can tell "unknown" apart from an
  /// actual 0-byte file.
  final int? sizeBytes;
  final int? durationMs;

  Map<String, dynamic> toJson() => {
    'storage_path': storagePath,
    'media_key': mediaKeyBase64,
    'mime_type': mimeType,
    if (sizeBytes != null) 'size_bytes': sizeBytes,
    if (durationMs != null) 'duration_ms': durationMs,
  };
}

/// A casual, fully-encrypted "here's where I am" pin - unlike [ChatEventInfo],
/// there's no reminder to schedule so nothing needs to be plaintext.
class LocationPointer {
  const LocationPointer({required this.lat, required this.lng, this.label});

  factory LocationPointer.fromJson(Map<String, dynamic> json) => LocationPointer(
    lat: (json['lat'] as num).toDouble(),
    lng: (json['lng'] as num).toDouble(),
    label: json['label'] as String?,
  );

  final double lat;
  final double lng;
  final String? label;

  Map<String, dynamic> toJson() => {
    'lat': lat,
    'lng': lng,
    if (label != null) 'label': label,
  };
}

/// The E2E-encrypted half of an event message - title/notes, decrypted via
/// the same ratchet path as a normal text message and cached the same way.
/// Paired with [ChatEventInfo] (plaintext time/location/status) to render
/// the full event card.
class EventPayload {
  const EventPayload({required this.title, this.notes});

  factory EventPayload.fromJson(Map<String, dynamic> json) => EventPayload(
    title: json['title'] as String? ?? '',
    notes: json['notes'] as String?,
  );

  final String title;
  final String? notes;

  Map<String, dynamic> toJson() => {'title': title, if (notes != null) 'notes': notes};
}

/// Balanced-storage half of an event: time/location/status live in
/// plaintext on `chat_events` (needed for reminder scheduling), so unlike
/// [ChatMessageView.plaintext] this is never cached locally - always
/// refetched/refreshed live from the server, same as [ChatMessageView.readAt].
class ChatEventInfo {
  const ChatEventInfo({
    required this.eventId,
    required this.eventTime,
    required this.locationLat,
    required this.locationLng,
    required this.locationLabel,
    required this.status,
    this.safetyEnabled = false,
  });

  factory ChatEventInfo.fromRow(Map<String, dynamic> row) => ChatEventInfo(
    eventId: row['id'] as String,
    eventTime: DateTime.parse(row['event_time'] as String),
    locationLat: (row['location_lat'] as num?)?.toDouble(),
    locationLng: (row['location_lng'] as num?)?.toDouble(),
    locationLabel: row['location_label'] as String?,
    status: row['status'] as String? ?? 'proposed',
    safetyEnabled: row['safety_enabled'] as bool? ?? false,
  );

  final String eventId;
  final DateTime eventTime;
  final double? locationLat;
  final double? locationLng;
  final String? locationLabel;
  final String status;

  /// Whether the creator auto-configured Meetup Safety for this plan at
  /// creation time - personal to them, not shared conversation state.
  final bool safetyEnabled;
}

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
    this.eventInfo,
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

  /// Only set for messageType == 'event'. See [ChatEventInfo] doc comment.
  final ChatEventInfo? eventInfo;

  ChatMessageView copyWith({DateTime? readAt, ChatEventInfo? eventInfo}) =>
      ChatMessageView(
        id: id,
        senderId: senderId,
        isMine: isMine,
        createdAt: createdAt,
        plaintext: plaintext,
        messageType: messageType,
        decryptFailed: decryptFailed,
        readAt: readAt ?? this.readAt,
        eventInfo: eventInfo ?? this.eventInfo,
      );
}

class ChatConversationState {
  const ChatConversationState({
    required this.messages,
    required this.sessionReady,
    required this.sending,
    this.isNewLocalIdentity = false,
    this.conversationClosed = false,
  });

  final List<ChatMessageView> messages;
  final bool sessionReady;
  final bool sending;

  /// See `SignalKeyService.isNewLocalIdentity` doc comment - true means
  /// this device has no local key material predating this conversation,
  /// so any of its historical messages will show as undecryptable.
  final bool isNewLocalIdentity;

  /// True once the peer has unmatched/blocked (or this user did, from
  /// another device) - detected live via a realtime listener on
  /// chat_conversations.closed_at. Disables the composer and stops the
  /// message/event realtime subscriptions once set.
  final bool conversationClosed;

  ChatConversationState copyWith({
    List<ChatMessageView>? messages,
    bool? sessionReady,
    bool? sending,
    bool? isNewLocalIdentity,
    bool? conversationClosed,
  }) {
    return ChatConversationState(
      messages: messages ?? this.messages,
      sessionReady: sessionReady ?? this.sessionReady,
      sending: sending ?? this.sending,
      isNewLocalIdentity: isNewLocalIdentity ?? this.isNewLocalIdentity,
      conversationClosed: conversationClosed ?? this.conversationClosed,
    );
  }
}

@riverpod
class ChatConversationController extends _$ChatConversationController {
  final SignalDatabase _db = SignalDatabase.instance;
  final Dio _dio = createDio();
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
    final isNewLocalIdentity = SignalKeyService.instance.isNewLocalIdentity;
    final address = SignalProtocolAddress(peerUserId, kSignalDeviceId);
    _peerAddress = address;

    final sessionReady = await SessionManager.instance.ensureSessionForConversation(
      conversationId: conversationId,
      peerUserId: peerUserId,
    );

    final conversationRow = await Supabase.instance.client
        .from('chat_conversations')
        .select('closed_at')
        .eq('id', conversationId)
        .maybeSingle();
    final conversationClosed = conversationRow?['closed_at'] != null;

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

    final timestamps = UntrustedIdentityRegistry.keyChangeTimestamps[peerUserId] ?? [];
    for (final ts in timestamps) {
      messages.add(
        ChatMessageView(
          id: 'security_alert_${ts.millisecondsSinceEpoch}',
          senderId: '',
          isMine: false,
          createdAt: ts,
          plaintext: 'Security code changed. Tap to verify.',
          messageType: 'security_alert',
          decryptFailed: false,
        ),
      );
    }
    messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    if (!conversationClosed) _subscribeRealtime(store, address);

    if (messages.any((m) => !m.isMine && m.readAt == null)) {
      unawaited(markAsRead());
    }

    return ChatConversationState(
      messages: messages,
      sessionReady: sessionReady,
      sending: false,
      isNewLocalIdentity: isNewLocalIdentity,
      conversationClosed: conversationClosed,
    );
  }

  void _subscribeRealtime(
    DriftSignalProtocolStore store,
    SignalProtocolAddress address,
  ) {
    final channel = Supabase.instance.client.channel('chat:$conversationId');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'chat_conversations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: conversationId,
          ),
          callback: _handleConversationUpdated,
        )
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
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'chat_events',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: _handleEventUpdated,
        )
        .subscribe();
    _channel = channel;
  }

  /// Fires when the peer unmatches/blocks (or this user does, from another
  /// device) while this conversation is open. Tears down the realtime
  /// subscription immediately - further chat_messages/chat_events changes
  /// can't happen once the match is dissolved, so there's nothing left to
  /// listen for.
  void _handleConversationUpdated(PostgresChangePayload payload) {
    final current = state.value;
    if (current == null) return;
    final closedAt = payload.newRecord['closed_at'];
    if (closedAt == null) return;

    state = AsyncData(current.copyWith(conversationClosed: true));
    final channel = _channel;
    if (channel != null) {
      unawaited(Supabase.instance.client.removeChannel(channel));
      _channel = null;
    }
  }

  void _handleEventUpdated(PostgresChangePayload payload) {
    final current = state.value;
    if (current == null) return;
    final row = payload.newRecord;
    final messageId = row['message_id'] as String?;
    if (messageId == null) return;
    final info = ChatEventInfo.fromRow(row);

    final updated = [
      for (final m in current.messages)
        if (m.id == messageId) m.copyWith(eventInfo: info) else m,
    ];
    state = AsyncData(current.copyWith(messages: updated));
  }

  Future<ChatEventInfo?> _fetchEventForMessage(String messageId) async {
    try {
      final row = await Supabase.instance.client
          .from('chat_events')
          .select()
          .eq('message_id', messageId)
          .maybeSingle();
      if (row == null) return null;
      return ChatEventInfo.fromRow(row);
    } on Exception {
      return null;
    }
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
      await _dio.patch<void>(
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
      final eventInfo = cached.messageType == 'event'
          ? await _fetchEventForMessage(id)
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
        eventInfo: eventInfo,
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

    final eventInfo = messageType == 'event'
        ? await _fetchEventForMessage(id)
        : null;

    return ChatMessageView(
      id: id,
      senderId: senderId,
      isMine: isMine,
      createdAt: createdAt,
      plaintext: plaintext,
      messageType: messageType,
      decryptFailed: decryptFailed,
      readAt: readAt,
      eventInfo: eventInfo,
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

  Future<bool> sendText(String text) =>
      _sendEnvelopeText(text: text, messageType: 'text', cachePlaintext: text);

  /// Encrypts [bytes] with a fresh random key, uploads the ciphertext to
  /// the `chat_media` bucket, then sends a small ratchet-encrypted pointer
  /// (see [MediaPointer]) as the actual chat message - the same pattern
  /// Signal uses for attachments.
  Future<bool> sendImage(Uint8List bytes, {required String mimeType}) =>
      _sendMedia(bytes: bytes, mimeType: mimeType, messageType: 'image');

  Future<bool> sendVoice(
    Uint8List bytes, {
    required String mimeType,
    required int durationMs,
  }) => _sendMedia(
    bytes: bytes,
    mimeType: mimeType,
    messageType: 'voice',
    durationMs: durationMs,
  );

  Future<bool> _sendMedia({
    required Uint8List bytes,
    required String mimeType,
    required String messageType,
    int? durationMs,
  }) async {
    try {
      final encrypted = await MediaCrypto.instance.encrypt(bytes);
      final storagePath = '$conversationId/${const Uuid().v4()}.enc';

      await Supabase.instance.client.storage
          .from('chat_media')
          .uploadBinary(
            storagePath,
            encrypted.ciphertext,
            fileOptions: const FileOptions(contentType: 'application/octet-stream'),
          );

      final pointer = MediaPointer(
        storagePath: storagePath,
        mediaKeyBase64: encrypted.mediaKeyBase64,
        mimeType: mimeType,
        sizeBytes: bytes.length,
        durationMs: durationMs,
      );
      final pointerJson = jsonEncode(pointer.toJson());

      return await _sendEnvelopeText(
        text: pointerJson,
        messageType: messageType,
        cachePlaintext: pointerJson,
      );
    } on Exception catch (e, st) {
      ErrorHandler.handleError(
        e,
        stackTrace: st,
        level: ErrorLevel.warning,
        customMessage: 'Failed to send $messageType message',
        showUi: false,
      );
      return false;
    }
  }

  /// Shared send path: ratchet-encrypts [text], POSTs it as a chat message,
  /// and caches [cachePlaintext] locally under the resulting message id so
  /// this device never needs to (and, for a sender, cannot) decrypt its
  /// own outbound envelope again.
  Future<bool> _sendEnvelopeText({
    required String text,
    required String messageType,
    required String cachePlaintext,
  }) async {
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

      final token = Supabase.instance.client.auth.currentSession?.accessToken;
      if (token == null) throw Exception('Not signed in');

      final response = await _dio.post<Map<String, dynamic>>(
        '${AppConfig.current.backendUrl}/api/v1/chats/$conversationId/messages',
        data: {
          'message_type': messageType,
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
        final messageCreatedAt = createdAtRaw != null
            ? DateTime.parse(createdAtRaw)
            : DateTime.now();
        await _cacheMessage(
          id: messageId,
          conversationId: conversationId,
          senderId: myUserId,
          isMine: true,
          createdAt: messageCreatedAt,
          messageType: messageType,
          plaintext: cachePlaintext,
          decryptFailed: false,
        );
        // Append the resolved view directly rather than waiting for the
        // realtime INSERT to round-trip back (self-inserts do fire
        // postgres_changes for the inserting session too, but that event
        // can arrive before the `_cacheMessage` write above lands, which
        // would make `_handleIncoming` -> `_resolveMessage` find no cache
        // entry and mark this device's own just-sent message as
        // undecryptable). We already have the plaintext in hand, so there's
        // no reason to depend on that race at all; `_handleIncoming`'s
        // existing id-dedup check skips the realtime event when it does
        // arrive.
        final latestForAppend = state.value ?? current;
        if (!latestForAppend.messages.any((m) => m.id == messageId)) {
          state = AsyncData(
            latestForAppend.copyWith(
              messages: [
                ...latestForAppend.messages,
                ChatMessageView(
                  id: messageId,
                  senderId: myUserId,
                  isMine: true,
                  createdAt: messageCreatedAt,
                  plaintext: cachePlaintext,
                  messageType: messageType,
                  decryptFailed: false,
                ),
              ],
            ),
          );
        }
      }
      return true;
    } on Exception catch (e, st) {
      ErrorHandler.handleError(
        e,
        stackTrace: st,
        level: ErrorLevel.warning,
        customMessage: 'Failed to send $messageType message',
        showUi: false,
      );
      return false;
    } finally {
      // NOTE: state.value may reflect a realtime-updated state that came in
      // during the send, since _handleIncoming can fire and update state
      // while the HTTP request is in flight. The copyWith(sending: false) on
      // this updated state is intentional to preserve any new messages.
      final latest = state.value ?? current;
      state = AsyncData(latest.copyWith(sending: false));
    }
  }

  /// A casual, fully-encrypted location pin - no chat_events row, since
  /// there's no reminder to schedule for it.
  Future<bool> sendLocation({
    required double lat,
    required double lng,
    String? label,
  }) {
    final pointerJson = jsonEncode(LocationPointer(lat: lat, lng: lng, label: label).toJson());
    return _sendEnvelopeText(
      text: pointerJson,
      messageType: 'location',
      cachePlaintext: pointerJson,
    );
  }

  /// Creates a date/plan proposal: event_time/location are sent as
  /// plaintext fields (balanced-storage decision - needed for reminder
  /// scheduling), title/notes are ratchet-encrypted exactly like a normal
  /// text message.
  Future<bool> createEvent({
    required DateTime eventTime,
    required String title,
    double? locationLat,
    double? locationLng,
    String? locationLabel,
    String? notes,
    bool safetyEnabled = false,
    int? safetyIntervalSeconds,
  }) async {
    final current = state.value;
    final store = _store;
    final address = _peerAddress;
    if (current == null || store == null || address == null) return false;

    state = AsyncData(current.copyWith(sending: true));
    try {
      final payloadJson = jsonEncode(EventPayload(title: title, notes: notes).toJson());
      final envelope = await MessageCodec.instance.encryptText(
        store: store,
        address: address,
        text: payloadJson,
      );

      final token = Supabase.instance.client.auth.currentSession?.accessToken;
      if (token == null) throw Exception('Not signed in');

      final response = await _dio.post<Map<String, dynamic>>(
        '${AppConfig.current.backendUrl}/api/v1/chats/$conversationId/events',
        data: {
          'event_time': eventTime.toUtc().toIso8601String(),
          'location_lat': locationLat,
          'location_lng': locationLng,
          'location_label': locationLabel,
          'ciphertext': envelope.ciphertextBase64,
          'ciphertext_metadata': {
            'signal_message_type': envelope.signalMessageType,
          },
          'safety_enabled': safetyEnabled,
          'safety_interval_seconds': ?safetyIntervalSeconds,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      final data = response.data;
      final messageId = data?['message_id'] as String?;
      final myUserId = Supabase.instance.client.auth.currentUser?.id;
      if (messageId != null && myUserId != null) {
        final createdAtRaw = data?['created_at'] as String?;
        await _cacheMessage(
          id: messageId,
          conversationId: conversationId,
          senderId: myUserId,
          isMine: true,
          createdAt: createdAtRaw != null
              ? DateTime.parse(createdAtRaw)
              : DateTime.now(),
          messageType: 'event',
          plaintext: payloadJson,
          decryptFailed: false,
        );
      }
      return true;
    } on Exception catch (e, st) {
      ErrorHandler.handleError(
        e,
        stackTrace: st,
        level: ErrorLevel.warning,
        customMessage: 'Failed to create event "$title"',
        showUi: false,
      );
      return false;
    } finally {
      final latest = state.value ?? current;
      state = AsyncData(latest.copyWith(sending: false));
    }
  }

  /// Confirms or cancels an existing event proposal.
  Future<bool> updateEventStatus(String eventId, String status) async {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null) return false;
    try {
      await _dio.patch<void>(
        '${AppConfig.current.backendUrl}/api/v1/chats/$conversationId/events/$eventId',
        data: {'status': status},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return true;
    } on Exception catch (e, st) {
      ErrorHandler.handleError(
        e,
        stackTrace: st,
        level: ErrorLevel.warning,
        customMessage: 'Failed to update event $eventId status to $status',
        showUi: false,
      );
      return false;
    }
  }

  /// Fetches and decrypts an attachment's bytes given its pointer -
  /// called lazily by the image/voice bubbles when they're rendered,
  /// rather than eagerly for the whole message list.
  Future<Uint8List> fetchMediaBytes(MediaPointer pointer) async {
    final ciphertext = await Supabase.instance.client.storage
        .from('chat_media')
        .download(pointer.storagePath);
    return MediaCrypto.instance.decrypt(ciphertext, pointer.mediaKeyBase64);
  }
}
