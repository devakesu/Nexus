import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:nexus/core/config/app_config.dart';
import 'package:nexus/core/utils/error_handler.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:nexus/features/security_signal/services/signal/local_key_vault.dart';
import 'package:nexus/features/security_signal/services/signal/signal_database.dart';
import 'package:nexus/features/security_signal/services/signal/signal_store.dart';

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
  static const _prefsIdentityUploadConfirmedRegId =
      'signal_identity_upload_confirmed_reg_id';
  static const _prefsSignedPreKeyConfirmedKeyId =
      'signal_signed_prekey_confirmed_key_id';

  // Prekey ID counters live in secure storage rather than SharedPreferences:
  // on a rooted/jailbroken device an attacker who rewinds a plaintext
  // counter could make the app re-upload already-used prekey IDs.
  static const _secureStorage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  final SignalDatabase _db = SignalDatabase.instance;
  // Reused for the app's lifetime rather than creating a new Dio/HttpClient
  // per call - this class is a singleton (SignalKeyService.instance), so
  // there's no shorter-lived scope to tie disposal to anyway.
  final Dio _dio = createDio();
  DriftSignalProtocolStore? _store;
  Future<DriftSignalProtocolStore>? _inFlight;
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

  /// Idempotent: safe to call every time a chat screen opens. Concurrent
  /// callers (e.g. the eager post-login call racing a chat screen opened via
  /// a deep link) share one in-flight attempt instead of racing duplicate
  /// identity-row inserts or duplicate uploads.
  Future<DriftSignalProtocolStore> ensureBootstrapped() {
    final cached = _store;
    if (cached != null) return Future.value(cached);
    return _inFlight ??= _doEnsureBootstrapped();
  }

  Future<DriftSignalProtocolStore> _doEnsureBootstrapped() async {
    try {
      await NetworkUtils.requireAccessToken();
      final (identityKeyPair, registrationId) = await _loadOrCreateIdentity();
      final store = DriftSignalProtocolStore(
        _db,
        identityKeyPair,
        registrationId,
      );

      await _ensureSignedPreKey(store);
      // Only cache once the full sequence has actually succeeded - caching
      // any earlier would mean a mid-sequence failure permanently skips
      // retrying the rest on every subsequent call for the remainder of
      // this process's lifetime.
      _store = store;
      unawaited(replenishOneTimePrekeysIfNeeded());

      return store;
    } finally {
      _inFlight = null;
    }
  }

  /// Fire-and-forget variant for callers (e.g. right after login) that must
  /// not await and must not throw. Failures are logged, not surfaced to the
  /// user, and simply left for the next opportunistic retry - a chat screen
  /// open, an app foreground, or the 6h background task - all of which call
  /// the now-retry-safe `ensureBootstrapped()` again.
  Future<void> ensureBootstrappedInBackground() async {
    try {
      await ensureBootstrapped();
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        // Expected if the user hasn't completed onboarding yet.
        return;
      }
      ErrorHandler.handleError(
        e,
        level: ErrorLevel.warning,
        showUi: false,
        customMessage:
            'Eager Signal key bootstrap failed post-login; will retry lazily.',
      );
    } on Object catch (e, stackTrace) {
      ErrorHandler.handleError(
        e,
        stackTrace: stackTrace,
        level: ErrorLevel.warning,
        showUi: false,
        customMessage:
            'Eager Signal key bootstrap failed post-login; will retry lazily.',
      );
    }
  }

  Future<(IdentityKeyPair, int)> _loadOrCreateIdentity() async {
    final row = await _db.select(_db.localIdentities).getSingleOrNull();
    if (row != null) {
      _isNewLocalIdentity = false;
      final decrypted = await LocalKeyVault.instance.decryptBytes(
        Uint8List.fromList(row.identityKeyPairEnc),
      );
      final identityKeyPair = IdentityKeyPair.fromSerialized(decrypted);

      // A previous run may have written this row but died/failed before
      // confirming the upload (e.g. offline signup) - retry it here rather
      // than assuming an existing local row means the server already has
      // it. Storing the registration id itself (not a bare bool) makes this
      // self-invalidating after wipeLocalData() generates a new identity.
      final confirmed = await _secureStorage.read(
        key: _prefsIdentityUploadConfirmedRegId,
      );
      if (confirmed != row.registrationId.toString()) {
        await _uploadIdentityKey(identityKeyPair, row.registrationId);
        await _secureStorage.write(
          key: _prefsIdentityUploadConfirmedRegId,
          value: row.registrationId.toString(),
        );
      }

      return (identityKeyPair, row.registrationId);
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
    await _secureStorage.write(
      key: _prefsIdentityUploadConfirmedRegId,
      value: registrationId.toString(),
    );
    return (identityKeyPair, registrationId);
  }

  Future<void> _uploadIdentityKey(
    IdentityKeyPair identityKeyPair,
    int registrationId,
  ) async {
    await NetworkUtils.requireAccessToken();
    await _dio.put<void>(
      '${AppConfig.current.backendUrl}/api/v1/chat/keys/identity',
      data: {
        'identity_public_key': base64Encode(
          identityKeyPair.getPublicKey().serialize(),
        ),
        'registration_id': registrationId,
      },
    );
  }

  Future<void> _ensureSignedPreKey(DriftSignalProtocolStore store) async {
    final existing = await store.loadSignedPreKeys();

    SignedPreKeyRecord? latest;
    if (existing.isNotEmpty) {
      latest = existing.reduce(
        (curr, next) =>
            curr.timestamp.toInt() > next.timestamp.toInt() ? curr : next,
      );
    }

    final confirmedIdRaw = await _secureStorage.read(
      key: _prefsSignedPreKeyConfirmedKeyId,
    );
    final confirmedId = int.tryParse(confirmedIdRaw ?? '');
    final isLatestConfirmed = latest != null && confirmedId == latest.id;

    // Rotate the signed prekey periodically (weekly/7 days) to enforce
    // forward secrecy and prevent stale keys - or immediately, regardless of
    // age, if the latest local key was never confirmed uploaded. A brand
    // new key_id is minted below rather than retrying the unconfirmed one,
    // since the backend enforces UNIQUE(user_id, key_id) with a plain
    // INSERT (no ON CONFLICT) - resending the same key_id after an
    // ambiguous failure (upload actually landed, response just got lost)
    // would 503 instead of silently succeeding.
    var needsRotation = true;
    if (latest != null && isLatestConfirmed) {
      final age =
          DateTime.now().millisecondsSinceEpoch - latest.timestamp.toInt();
      if (age < const Duration(days: 7).inMilliseconds) {
        needsRotation = false;
      }
    }

    if (!needsRotation) {
      if (existing.length > 1 && latest != null) {
        for (final key in existing) {
          if (key.id != latest.id) {
            await store.removeSignedPreKey(key.id);
          }
        }
      }
      return;
    }

    final keyId =
        int.tryParse(
          await _secureStorage.read(key: _prefsNextSignedPreKeyId) ?? '',
        ) ??
        1;
    final identityKeyPair = await store.getIdentityKeyPair();
    final signedPreKey = generateSignedPreKey(identityKeyPair, keyId);
    await store.storeSignedPreKey(keyId, signedPreKey);
    await _secureStorage.write(
      key: _prefsNextSignedPreKeyId,
      value: '${keyId + 1}',
    );

    await NetworkUtils.requireAccessToken();
    final publicKey = signedPreKey.getKeyPair().publicKey;
    await _dio.put<void>(
      '${AppConfig.current.backendUrl}/api/v1/chat/keys/signed-prekey',
      data: {
        'key_id': keyId,
        'public_key': base64Encode(publicKey.serialize()),
        'signature': base64Encode(signedPreKey.signature),
      },
    );
    await _secureStorage.write(
      key: _prefsSignedPreKeyConfirmedKeyId,
      value: '$keyId',
    );

    // Clean up old signed prekeys so they don't accumulate in SQLite
    final remainingKeys = await store.loadSignedPreKeys();
    for (final key in remainingKeys) {
      if (key.id != keyId) {
        await store.removeSignedPreKey(key.id);
      }
    }
  }

  /// Tops up the server-side one-time prekey pool when it runs low. Safe to
  /// call opportunistically (e.g. on app foreground) - it no-ops when the
  /// pool is already healthy.
  Future<void> replenishOneTimePrekeysIfNeeded() async {
    final store = await ensureBootstrapped();
    await NetworkUtils.requireAccessToken();

    final countResponse = await _dio.get<Map<String, dynamic>>(
      '${AppConfig.current.backendUrl}/api/v1/chat/keys/one-time-prekeys/count',
    );
    final count = countResponse.data?['count'] as int? ?? 0;
    if (count >= _oneTimePrekeyLowWaterMark) return;

    final startId =
        int.tryParse(
          await _secureStorage.read(key: _prefsNextPreKeyId) ?? '',
        ) ??
        1;
    final newKeys = generatePreKeys(startId, _oneTimePrekeyBatchSize);

    // Upload first: if the network call fails, local state remains untouched
    // and the next retry will reuse the same startId without orphaning keys.
    await _dio.post<void>(
      '${AppConfig.current.backendUrl}/api/v1/chat/keys/one-time-prekeys',
      data: {
        'prekeys': newKeys
            .map(
              (key) => {
                'key_id': key.id,
                'public_key': base64Encode(
                  key.getKeyPair().publicKey.serialize(),
                ),
              },
            )
            .toList(),
      },
    );

    for (final key in newKeys) {
      await store.storePreKey(key.id, key);
    }
    await _secureStorage.write(
      key: _prefsNextPreKeyId,
      value: '${startId + _oneTimePrekeyBatchSize}',
    );
  }

  Future<void> wipeLocalData() async {
    _store = null;
    _inFlight = null;
    await _db.clearAllData();
    await _secureStorage.delete(key: _prefsNextPreKeyId);
    await _secureStorage.delete(key: _prefsNextSignedPreKeyId);
    await _secureStorage.delete(key: _prefsIdentityUploadConfirmedRegId);
    await _secureStorage.delete(key: _prefsSignedPreKeyConfirmedKeyId);
    await LocalKeyVault.instance.wipeKeys();
  }
}
