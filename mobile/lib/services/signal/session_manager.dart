import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/services/signal/signal_key_service.dart';
import 'package:nexus/utils/network_utils.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Fixed device id used everywhere in this app - single-device-per-user for
/// v1 (see the chat feature plan's Risks section for the multi-device
/// tradeoff this implies).
const kSignalDeviceId = 1;

/// Establishes (or confirms) a Double Ratchet session toward a conversation
/// peer. Either side of a match can call this as soon as they open the
/// chat screen - both proactively completing X3DH toward each other before
/// a single message is sent is exactly how Signal clients "pre-warm" a
/// conversation, and the protocol's multi-state SessionRecord is designed
/// to handle both sides initiating independently.
class SessionManager {
  SessionManager._();

  static final SessionManager instance = SessionManager._();

  /// Returns true once this device has a session ready to encrypt outbound
  /// messages to [peerUserId]. False means the peer hasn't set up secure
  /// messaging yet (no identity key on the server) - nothing to do until
  /// they open their own chat screen for the first time.
  Future<bool> ensureSessionForConversation({
    required String conversationId,
    required String peerUserId,
  }) async {
    final store = await SignalKeyService.instance.ensureBootstrapped();
    final address = SignalProtocolAddress(peerUserId, kSignalDeviceId);

    if (await store.containsSession(address)) {
      return true;
    }

    final bundle = await _fetchPeerBundle(peerUserId);
    if (bundle == null) return false;

    final sessionBuilder = SessionBuilder(store, store, store, store, address);
    await sessionBuilder.processPreKeyBundle(bundle);

    unawaited(_notifyBackendSessionEstablished(conversationId));
    return true;
  }

  Future<PreKeyBundle?> _fetchPeerBundle(String peerUserId) async {
    final dio = createDio();
    final token = await _requireToken();
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '${AppConfig.current.backendUrl}/api/v1/chat/keys/bundle/$peerUserId',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data;
      if (data == null) return null;

      final identityKey = IdentityKey(
        Curve.decodePoint(
          base64Decode(data['identity_public_key'] as String),
          0,
        ),
      );
      final signedPreKeyPublic = Curve.decodePoint(
        base64Decode(data['signed_prekey_public'] as String),
        0,
      );
      final oneTimePrekeyId = data['one_time_prekey_id'] as int?;
      final oneTimePrekeyPublicRaw = data['one_time_prekey_public'] as String?;
      final oneTimePrekeyPublic = oneTimePrekeyPublicRaw != null
          ? Curve.decodePoint(base64Decode(oneTimePrekeyPublicRaw), 0)
          : null;

      return PreKeyBundle(
        data['registration_id'] as int,
        kSignalDeviceId,
        oneTimePrekeyId,
        oneTimePrekeyPublic,
        data['signed_prekey_id'] as int,
        signedPreKeyPublic,
        base64Decode(data['signed_prekey_signature'] as String),
        identityKey,
      );
    } on DioException catch (e) {
      // 404: peer hasn't set up secure messaging yet. 403: no active match
      // (shouldn't happen from a real chat screen, but fail closed either way).
      if (e.response?.statusCode == 404 || e.response?.statusCode == 403) {
        return null;
      }
      rethrow;
    }
  }

  Future<void> _notifyBackendSessionEstablished(String conversationId) async {
    try {
      final dio = createDio();
      final token = await _requireToken();
      await dio.post<void>(
        '${AppConfig.current.backendUrl}/api/v1/chat/sessions/establish',
        data: {'conversation_id': conversationId},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } on Exception {
      // Diagnostics-only column; the local session is already usable
      // regardless of whether this notification succeeds.
    }
  }

  Future<String> _requireToken() async {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null) throw Exception('Not signed in');
    return token;
  }
}
