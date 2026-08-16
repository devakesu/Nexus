import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:nexus/core/config/app_config.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:nexus/features/security_signal/services/signal/signal_key_service.dart';

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

  // Reused for the app's lifetime rather than creating a new Dio/HttpClient
  // per call - this class is a singleton, so there's no shorter-lived scope
  // to tie disposal to anyway.
  final Dio _dio = createDio();

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
    try {
      await sessionBuilder.processPreKeyBundle(bundle);
    } on UntrustedIdentityException catch (e) {
      final newKey = e.key;
      if (newKey == null) rethrow;
      UntrustedIdentityRegistry.register(peerUserId, newKey);
      throw UntrustedPeerIdentityException(
        peerUserId: peerUserId,
        newIdentityKey: newKey,
      );
    }

    unawaited(_notifyBackendSessionEstablished(conversationId));
    return true;
  }

  /// Explicitly trusts the pending untrusted identity key for [peerUserId]
  /// and rebuilds the Signal session after user verification.
  Future<bool> trustPeerIdentityAndRebuildSession({
    required String conversationId,
    required String peerUserId,
  }) async {
    final newKey = UntrustedIdentityRegistry.pendingUntrustedKeys[peerUserId];
    if (newKey == null) return false;

    final store = await SignalKeyService.instance.ensureBootstrapped();
    final address = SignalProtocolAddress(peerUserId, kSignalDeviceId);

    await store.saveIdentity(address, newKey);
    UntrustedIdentityRegistry.resolve(peerUserId);

    final bundle = await _fetchPeerBundle(peerUserId);
    if (bundle == null) return false;

    final sessionBuilder = SessionBuilder(store, store, store, store, address);
    await sessionBuilder.processPreKeyBundle(bundle);

    unawaited(_notifyBackendSessionEstablished(conversationId));
    return true;
  }

  Future<PreKeyBundle?> _fetchPeerBundle(String peerUserId) async {
    await NetworkUtils.requireAccessToken();
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '${AppConfig.current.backendUrl}/api/v1/chat/keys/bundle/$peerUserId',
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
      await NetworkUtils.requireAccessToken();
      await _dio.post<void>(
        '${AppConfig.current.backendUrl}/api/v1/chat/sessions/establish',
        data: {'conversation_id': conversationId},
      );
    } on Exception {
      // Diagnostics-only column; the local session is already usable
      // regardless of whether this notification succeeds.
    }
  }
}

class UntrustedIdentityRegistry {
  static final Map<String, IdentityKey> pendingUntrustedKeys = {};
  static final Map<String, List<DateTime>> keyChangeTimestamps = {};

  static const int maxKeyChangeHistoryPerPeer = 10;

  static bool hasUntrustedIdentity(String peerUserId) {
    return pendingUntrustedKeys.containsKey(peerUserId);
  }

  static void register(String peerUserId, IdentityKey key) {
    pendingUntrustedKeys[peerUserId] = key;
    final timestamps = keyChangeTimestamps.putIfAbsent(peerUserId, () => [])
      ..add(DateTime.now());
    if (timestamps.length > maxKeyChangeHistoryPerPeer) {
      timestamps.removeRange(0, timestamps.length - maxKeyChangeHistoryPerPeer);
    }
  }

  static void resolve(String peerUserId) {
    pendingUntrustedKeys.remove(peerUserId);
    keyChangeTimestamps.remove(peerUserId);
  }

  static Future<String> computeSafetyNumber(
    IdentityKeyPair local,
    IdentityKey peer,
  ) async {
    final localBytes = local.getPublicKey().serialize();
    final peerBytes = peer.serialize();

    final sorted = [localBytes, peerBytes]
      ..sort((a, b) {
        for (var i = 0; i < a.length && i < b.length; i++) {
          if (a[i] != b[i]) return a[i].compareTo(b[i]);
        }
        return a.length.compareTo(b.length);
      });

    final sha512 = Sha512();
    final hashObj = await sha512.hash([...sorted[0], ...sorted[1]]);
    final hash = hashObj.bytes;

    final buffer = StringBuffer();
    for (var i = 0; i < 12; i++) {
      final chunk =
          (hash[i * 4] << 24) |
          (hash[i * 4 + 1] << 16) |
          (hash[i * 4 + 2] << 8) |
          hash[i * 4 + 3];
      final group = (chunk.abs() % 100000).toString().padLeft(5, '0');
      buffer.write(group);
      if (i < 11) buffer.write(' ');
    }
    return buffer.toString();
  }
}

/// Thrown when a peer's identity key has changed and has not yet been confirmed
/// by the local user.
class UntrustedPeerIdentityException implements Exception {
  const UntrustedPeerIdentityException({
    required this.peerUserId,
    required this.newIdentityKey,
  });

  final String peerUserId;
  final IdentityKey newIdentityKey;

  @override
  String toString() =>
      'UntrustedPeerIdentityException: Peer $peerUserId presented an untrusted identity key. Manual user confirmation required.';
}
