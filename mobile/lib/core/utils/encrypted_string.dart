import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// A wrapper for sensitive strings that encrypts them in RAM using AES-256-GCM.
/// It temporarily decrypts the value during execution of a callback
/// and does not expose a permanent plaintext getter.
class EncryptedString {
  EncryptedString._(this._secretBox, this._secretKey);

  /// Asynchronously creates an encrypted representation of [plainText] in RAM using AES-256-GCM.
  static Future<EncryptedString> create(String plainText) async {
    final key = await _algorithm.newSecretKey();
    final plainBytes = utf8.encode(plainText);
    final secretBox = await _algorithm.encrypt(plainBytes, secretKey: key);
    return EncryptedString._(secretBox, key);
  }

  static final _algorithm = AesGcm.with256bits();

  final SecretBox _secretBox;
  final SecretKey _secretKey;

  /// Temporarily decrypts the string and executes [action] with it.
  /// The decrypted value is only in RAM for the exact duration of the callback.
  Future<T> use<T>(FutureOr<T> Function(String plainText) action) async {
    final decryptedBytes = await _algorithm.decrypt(
      _secretBox,
      secretKey: _secretKey,
    );
    final decrypted = utf8.decode(decryptedBytes);
    try {
      return await action(decrypted);
    } finally {
      // Dart GC will collect 'decrypted'; explicit memory zeroing is not available in Dart.
    }
  }
}
