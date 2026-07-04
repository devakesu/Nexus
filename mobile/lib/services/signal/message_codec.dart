import 'dart:convert';
import 'dart:typed_data';

import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:nexus/services/signal/signal_store.dart';

class EncryptedEnvelope {
  const EncryptedEnvelope({
    required this.ciphertextBase64,
    required this.signalMessageType,
  });

  /// Base64-encoded Signal Protocol message envelope, ready to send as
  /// `chat_messages.ciphertext`.
  final String ciphertextBase64;

  /// 'prekey' or 'whisper' - goes in `chat_messages.ciphertext_metadata` so
  /// the receiver knows which message type to reconstruct.
  final String signalMessageType;
}

/// Wraps [SessionCipher] encrypt/decrypt and maps to/from the wire shape
/// used by `chat_messages`. Callers must never attempt to decrypt their own
/// outbound ciphertext - Double Ratchet message keys are single-use and
/// deleted after a successful decrypt, and encrypt/decrypt use separate
/// sending/receiving chains, so a sender cannot recover their own message
/// this way regardless. Sent plaintext must be cached at send time (see
/// `chat_conversation_provider.dart`).
class MessageCodec {
  MessageCodec._();

  static final MessageCodec instance = MessageCodec._();

  Future<EncryptedEnvelope> encryptText({
    required DriftSignalProtocolStore store,
    required SignalProtocolAddress address,
    required String text,
  }) async {
    final cipher = SessionCipher(store, store, store, store, address);
    final message = await cipher.encrypt(Uint8List.fromList(utf8.encode(text)));
    final type = message.getType() == CiphertextMessage.prekeyType
        ? 'prekey'
        : 'whisper';
    return EncryptedEnvelope(
      ciphertextBase64: base64Encode(message.serialize()),
      signalMessageType: type,
    );
  }

  /// Returns null if decryption fails (corrupt envelope, replay, or a
  /// message key that's fallen out of the skipped-key cache window).
  Future<String?> decryptText({
    required DriftSignalProtocolStore store,
    required SignalProtocolAddress address,
    required String ciphertextBase64,
    required String signalMessageType,
  }) async {
    final cipher = SessionCipher(store, store, store, store, address);
    final bytes = base64Decode(ciphertextBase64);
    try {
      final Uint8List plaintext;
      if (signalMessageType == 'prekey') {
        plaintext = await cipher.decrypt(PreKeySignalMessage(bytes));
      } else {
        plaintext = await cipher.decryptFromSignal(
          SignalMessage.fromSerialized(bytes),
        );
      }
      return utf8.decode(plaintext);
    } on Exception {
      return null;
    }
  }
}
