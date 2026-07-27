import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class EncryptedMedia {
  const EncryptedMedia({
    required this.ciphertext,
    required this.mediaKeyBase64,
  });

  /// nonce + ciphertext + MAC, concatenated - what actually gets uploaded
  /// to the `chat_media` Storage bucket.
  final Uint8List ciphertext;

  /// The random per-attachment AES-256 key, base64-encoded. This never
  /// touches Storage - it only ever travels inside the Signal
  /// Protocol-encrypted message pointer (see `chat_conversation_provider`'s
  /// media send/resolve methods), matching Signal's own attachment scheme:
  /// a random key per attachment, delivered through the ratchet-encrypted
  /// message channel rather than derived from ratchet state directly
  /// (which `libsignal_protocol_dart`'s public API doesn't expose anyway).
  final String mediaKeyBase64;
}

/// AES-256-GCM encryption for photo/voice attachment bytes. Deliberately a
/// fresh random key per call - see `EncryptedMedia.mediaKeyBase64` above.
class MediaCrypto {
  MediaCrypto._();

  static final MediaCrypto instance = MediaCrypto._();

  static const _nonceLength = 12;
  static const _macLength = 16;

  final _algorithm = AesGcm.with256bits();

  Future<EncryptedMedia> encrypt(Uint8List plaintext) async {
    final key = await _algorithm.newSecretKey();
    final box = await _algorithm.encrypt(plaintext, secretKey: key);
    final keyBytes = await key.extractBytes();
    return EncryptedMedia(
      ciphertext: box.concatenation(),
      mediaKeyBase64: base64Encode(keyBytes),
    );
  }

  Future<Uint8List> decrypt(Uint8List ciphertext, String mediaKeyBase64) async {
    final key = SecretKey(base64Decode(mediaKeyBase64));
    final box = SecretBox.fromConcatenation(
      ciphertext,
      nonceLength: _nonceLength,
      macLength: _macLength,
    );
    final plaintext = await _algorithm.decrypt(box, secretKey: key);
    return Uint8List.fromList(plaintext);
  }
}
