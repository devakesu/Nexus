import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nexus/core/utils/secure_storage_options.dart';

/// Encrypts/decrypts the Signal Protocol local store's key material and
/// session (ratchet) state before it touches disk. The AES-256 data key
/// itself lives in the platform Keystore/Keychain via [AppSecureStorage]
/// - the same secure-storage backing already used for the Supabase session
/// in `secure_session_storage.dart`. This gives every sensitive blob in the
/// local Signal database (private keys, chain keys, message-key caches)
/// application-layer encryption at rest, independent of OS disk encryption.
class LocalKeyVault {
  LocalKeyVault._();

  static final LocalKeyVault instance = LocalKeyVault._();

  static const _storageKey = 'nexus_signal_db_key_v1';
  static const _nonceLength = 12;
  static const _macLength = 16;

  static const FlutterSecureStorage _secureStorage = AppSecureStorage.instance;

  final _algorithm = AesGcm.with256bits();
  SecretKey? _cachedKey;

  Future<SecretKey> _getOrCreateKey() async {
    final cached = _cachedKey;
    if (cached != null) return cached;

    final existing = await _secureStorage.read(key: _storageKey);
    if (existing != null) {
      final key = SecretKey(base64Decode(existing));
      _cachedKey = key;
      return key;
    }

    final newKey = await _algorithm.newSecretKey();
    final bytes = await newKey.extractBytes();
    await _secureStorage.write(key: _storageKey, value: base64Encode(bytes));
    _cachedKey = newKey;
    return newKey;
  }

  Future<Uint8List> encryptBytes(Uint8List plaintext) async {
    final key = await _getOrCreateKey();
    final box = await _algorithm.encrypt(plaintext, secretKey: key);
    return box.concatenation();
  }

  Future<Uint8List> decryptBytes(Uint8List ciphertext) async {
    final key = await _getOrCreateKey();
    final box = SecretBox.fromConcatenation(
      ciphertext,
      nonceLength: _nonceLength,
      macLength: _macLength,
    );
    final plaintext = await _algorithm.decrypt(box, secretKey: key);
    return Uint8List.fromList(plaintext);
  }

  Future<void> wipeKeys() async {
    _cachedKey = null;
    await _secureStorage.delete(key: _storageKey);
  }
}
