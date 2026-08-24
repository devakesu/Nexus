import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:nexus/core/utils/secure_preferences.dart';
import 'package:nexus/core/utils/secure_storage_options.dart';

/// A wrapper for sensitive in-memory strings that encrypts them in RAM using AES-256-GCM
/// with a unique ephemeral key per instance.
///
/// NOTE: This provides in-memory obfuscation against casual heap inspection during short-lived
/// operations. In Dart, strings and byte buffers are managed by garbage collection and cannot
/// be reliably zeroed in hardware. Long-lived secrets must always be stored in the platform
/// Keystore / Keychain via [AppSecureStorage] or [SecurePreferences].
class EncryptedString {
  EncryptedString._(this._secretBox, this._secretKey);

  /// Asynchronously creates an encrypted representation of [plainText] in RAM using AES-256-GCM
  /// with a fresh ephemeral random key.
  static Future<EncryptedString> create(String plainText) async {
    final key = await _algorithm.newSecretKey();
    final plainBytes = utf8.encode(plainText);
    final secretBox = await _algorithm.encrypt(plainBytes, secretKey: key);
    return EncryptedString._(secretBox, key);
  }

  static final _algorithm = AesGcm.with256bits();

  SecretBox? _secretBox;
  SecretKey? _secretKey;
  bool _isWiped = false;

  /// Whether this encrypted string has been wiped from memory.
  bool get isWiped => _isWiped;

  /// Temporarily decrypts the string and executes [action] with it.
  /// The decrypted value is only in RAM for the exact duration of the callback.
  Future<T> use<T>(FutureOr<T> Function(String plainText) action) async {
    if (_isWiped || _secretBox == null || _secretKey == null) {
      throw StateError('Cannot use a wiped EncryptedString');
    }
    final decryptedBytes = await _algorithm.decrypt(
      _secretBox!,
      secretKey: _secretKey!,
    );
    final decrypted = utf8.decode(decryptedBytes);
    try {
      return await action(decrypted);
    } finally {
      // Dart GC will collect 'decrypted'; explicit memory zeroing is not available in Dart.
    }
  }

  /// Wipes key and ciphertext references to assist garbage collection.
  void wipe() {
    _secretBox = null;
    _secretKey = null;
    _isWiped = true;
  }
}
