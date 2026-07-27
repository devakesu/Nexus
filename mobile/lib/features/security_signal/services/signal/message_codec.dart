import 'dart:convert';
import 'dart:typed_data';

import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:nexus/core/utils/error_handler.dart';
import 'package:nexus/features/security_signal/services/signal/session_manager.dart';
import 'package:nexus/features/security_signal/services/signal/signal_store.dart';

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
    final plaintext = Uint8List.fromList(utf8.encode(text));
    final message = await _withIdentityRepin(
      store: store,
      address: address,
      action: () =>
          SessionCipher(store, store, store, store, address).encrypt(plaintext),
    );
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
    final bytes = base64Decode(ciphertextBase64);
    try {
      final plaintext = await _withIdentityRepin(
        store: store,
        address: address,
        action: () {
          final cipher = SessionCipher(store, store, store, store, address);
          if (signalMessageType == 'prekey') {
            return cipher.decrypt(PreKeySignalMessage(bytes));
          }
          return cipher.decryptFromSignal(SignalMessage.fromSerialized(bytes));
        },
      );
      return utf8.decode(plaintext);
    } on Object catch (e, st) {
      // Catches `Error`s too, not just `Exception`s - a malformed envelope
      // can throw either, and both need forensic visibility even though
      // both fail the same way from the caller's perspective (return null).
      ErrorHandler.handleError(
        e,
        stackTrace: st,
        level: ErrorLevel.warning,
        customMessage:
            'Signal decryptText failed for $address (${e.runtimeType})',
        showUi: false,
      );
      return null;
    }
  }

  /// Runs [action] once; if it fails because the peer's pinned identity key
  /// no longer matches (`UntrustedIdentityException` - libsignal's
  /// trust-on-first-use guard), re-pins the new key and retries exactly
  /// once.
  ///
  /// This app has no safety-number verification screen, so a rejected
  /// identity change is never surfaced to either user and can never be
  /// manually accepted - in practice it almost always just means the peer
  /// reinstalled the app or wiped their device (see
  /// `SignalKeyService.isNewLocalIdentity`), not an active MITM. Without
  /// this, the strict pinning check would permanently and silently break
  /// every future message in the conversation the moment either side's
  /// identity changes, with no user-facing way to recover. If a real
  /// verification flow is added later, this auto-accept should be gated
  /// behind it instead of applying unconditionally.
  Future<T> _withIdentityRepin<T>({
    required DriftSignalProtocolStore store,
    required SignalProtocolAddress address,
    required Future<T> Function() action,
  }) async {
    try {
      return await action();
    } on UntrustedIdentityException catch (e) {
      final newKey = e.key;
      if (newKey == null) rethrow;
      UntrustedIdentityRegistry.register(address.getName(), newKey);
      await store.saveIdentity(address, newKey);
      return action();
    }
  }
}
