import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/services/signal/local_key_vault.dart';
import 'package:nexus/services/signal/signal_database.dart';
import 'package:nexus/services/signal/signal_store.dart';
import 'package:nexus/utils/network_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Bootstraps this device's Signal Protocol identity: generates the
/// identity key pair, a signed prekey, and a pool of one-time prekeys on
/// first use, uploads only the public halves to the backend bulletin
/// board, and keeps the one-time prekey pool topped up.
class SignalKeyService {
  SignalKeyService._();

  static final SignalKeyService instance = SignalKeyService._();

  static const _oneTimePrekeyBatchSize = 100;
  static const _oneTimePrekeyLowWaterMark = 20;
  static const _prefsNextPreKeyId = 'signal_next_prekey_id';
  static const _prefsNextSignedPreKeyId = 'signal_next_signed_prekey_id';

  final SignalDatabase _db = SignalDatabase.instance;
  DriftSignalProtocolStore? _store;
  bool _isNewLocalIdentity = false;

  /// True if this device generated a brand-new Signal identity on this
  /// `ensureBootstrapped()` call chain rather than loading an existing one
  /// - i.e. a fresh install/reinstall/device wipe. Since private keys and
  /// ratchet state never leave the device by design, this means any
  /// server-side conversation history predating this identity is
  /// permanently undecryptable (see `chat_conversation_page.dart`'s "new
  /// device" banner) - correct behavior for E2E encryption, but it must be
  /// surfaced honestly rather than silently showing decrypt failures.
  bool get isNewLocalIdentity => _isNewLocalIdentity;

  /// Idempotent: safe to call every time a chat screen opens.
  Future<DriftSignalProtocolStore> ensureBootstrapped() async {
    final cached = _store;
    if (cached != null) return cached;

    final (identityKeyPair, registrationId) = await _loadOrCreateIdentity();
    final store = DriftSignalProtocolStore(_db, identityKeyPair, registrationId);
    _store = store;

    await _ensureSignedPreKey(store);
    unawaited(replenishOneTimePrekeysIfNeeded());

    return store;
  }

  Future<(IdentityKeyPair, int)> _loadOrCreateIdentity() async {
    final row = await _db.select(_db.localIdentities).getSingleOrNull();
    if (row != null) {
      _isNewLocalIdentity = false;
      final decrypted = await LocalKeyVault.instance.decryptBytes(
        Uint8List.fromList(row.identityKeyPairEnc),
      );
      return (IdentityKeyPair.fromSerialized(decrypted), row.registrationId);
    }

    _isNewLocalIdentity = true;
    final identityKeyPair = generateIdentityKeyPair();
    final registrationId = generateRegistrationId(false);
    final encrypted = await LocalKeyVault.instance.encryptBytes(
      identityKeyPair.serialize(),
    );
    await _db
        .into(_db.localIdentities)
        .insert(
          LocalIdentitiesCompanion.insert(
            id: const Value(0),
            identityKeyPairEnc: encrypted,
            registrationId: registrationId,
          ),
        );

    await _uploadIdentityKey(identityKeyPair, registrationId);
    return (identityKeyPair, registrationId);
  }

  Future<void> _uploadIdentityKey(
    IdentityKeyPair identityKeyPair,
    int registrationId,
  ) async {
    final dio = createDio();
    final token = await _requireToken();
    await dio.put<void>(
      '${AppConfig.current.backendUrl}/api/v1/chat/keys/identity',
      data: {
        'identity_public_key': base64Encode(
          identityKeyPair.getPublicKey().serialize(),
        ),
        'registration_id': registrationId,
      },
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  }

  Future<void> _ensureSignedPreKey(DriftSignalProtocolStore store) async {
    final existing = await store.loadSignedPreKeys();
    // Rotation policy lands in a later phase; for now, one signed prekey
    // for the lifetime of the local identity is enough to unblock X3DH.
    if (existing.isNotEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final keyId = prefs.getInt(_prefsNextSignedPreKeyId) ?? 1;
    final identityKeyPair = await store.getIdentityKeyPair();
    final signedPreKey = generateSignedPreKey(identityKeyPair, keyId);
    await store.storeSignedPreKey(keyId, signedPreKey);
    await prefs.setInt(_prefsNextSignedPreKeyId, keyId + 1);

    final dio = createDio();
    final token = await _requireToken();
    final publicKey = signedPreKey.getKeyPair().publicKey;
    await dio.put<void>(
      '${AppConfig.current.backendUrl}/api/v1/chat/keys/signed-prekey',
      data: {
        'key_id': keyId,
        'public_key': base64Encode(publicKey.serialize()),
        'signature': base64Encode(signedPreKey.signature),
      },
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  }

  /// Tops up the server-side one-time prekey pool when it runs low. Safe to
  /// call opportunistically (e.g. on app foreground) - it no-ops when the
  /// pool is already healthy.
  Future<void> replenishOneTimePrekeysIfNeeded() async {
    final store = await ensureBootstrapped();
    final dio = createDio();
    final token = await _requireToken();

    final countResponse = await dio.get<Map<String, dynamic>>(
      '${AppConfig.current.backendUrl}/api/v1/chat/keys/one-time-prekeys/count',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    final count = countResponse.data?['count'] as int? ?? 0;
    if (count >= _oneTimePrekeyLowWaterMark) return;

    final prefs = await SharedPreferences.getInstance();
    final startId = prefs.getInt(_prefsNextPreKeyId) ?? 1;
    final newKeys = generatePreKeys(startId, _oneTimePrekeyBatchSize);
    for (final key in newKeys) {
      await store.storePreKey(key.id, key);
    }
    await prefs.setInt(_prefsNextPreKeyId, startId + _oneTimePrekeyBatchSize);

    await dio.post<void>(
      '${AppConfig.current.backendUrl}/api/v1/chat/keys/one-time-prekeys',
      data: {
        'prekeys': newKeys
            .map(
              (key) => {
                'key_id': key.id,
                'public_key': base64Encode(key.getKeyPair().publicKey.serialize()),
              },
            )
            .toList(),
      },
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  }

  Future<String> _requireToken() async {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null) throw Exception('Not signed in');
    return token;
  }
}
