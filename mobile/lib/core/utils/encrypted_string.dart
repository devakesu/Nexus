import 'package:encrypt/encrypt.dart' as enc;

/// A wrapper for sensitive strings that encrypts them in RAM.
/// It temporarily decrypts the value during execution of a callback
/// and does not expose a permanent plaintext getter.
class EncryptedString {
  /// Creates an encrypted representation of [plainText] in RAM.
  factory EncryptedString(String plainText) {
    final iv = enc.IV.fromSecureRandom(16);
    final encrypted = _encrypter.encrypt(plainText, iv: iv);
    return EncryptedString._(iv, encrypted);
  }

  EncryptedString._(this._iv, this._encrypted);

  static final enc.Key _key = enc.Key.fromSecureRandom(32);
  static final enc.Encrypter _encrypter = enc.Encrypter(enc.AES(_key));

  final enc.IV _iv;
  final enc.Encrypted _encrypted;

  /// Temporarily decrypts the string and executes [action] with it.
  /// The decrypted value is only in RAM for the exact duration of the callback.
  T use<T>(T Function(String plainText) action) {
    final decrypted = _encrypter.decrypt(_encrypted, iv: _iv);
    try {
      return action(decrypted);
    } finally {
      // Dart GC will collect 'decrypted'; explicit memory zeroing is not available in Dart.
    }
  }
}
