import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:nexus/features/security_signal/services/signal/message_codec.dart';
import 'package:nexus/features/security_signal/services/signal/session_manager.dart';

void main() {
  group('UntrustedIdentityRegistry and UntrustedPeerIdentityException', () {
    setUp(() {
      UntrustedIdentityRegistry.pendingUntrustedKeys.clear();
      UntrustedIdentityRegistry.keyChangeTimestamps.clear();
    });

    test('UntrustedPeerIdentityException holds peerId and new key', () {
      final keyPair = generateIdentityKeyPair();
      final exception = UntrustedPeerIdentityException(
        peerUserId: 'user-123',
        newIdentityKey: keyPair.getPublicKey(),
      );

      expect(exception.peerUserId, equals('user-123'));
      expect(exception.newIdentityKey, equals(keyPair.getPublicKey()));
      expect(
        exception.toString(),
        contains('Peer user-123 presented an untrusted identity key'),
      );
    });

    test('UntrustedIdentityRegistry register and resolve workflow', () {
      final keyPair = generateIdentityKeyPair();
      const peerId = 'peer-abc';

      expect(UntrustedIdentityRegistry.hasUntrustedIdentity(peerId), isFalse);

      UntrustedIdentityRegistry.register(peerId, keyPair.getPublicKey());
      expect(UntrustedIdentityRegistry.hasUntrustedIdentity(peerId), isTrue);
      expect(
        UntrustedIdentityRegistry.pendingUntrustedKeys[peerId],
        equals(keyPair.getPublicKey()),
      );
      expect(
        UntrustedIdentityRegistry.keyChangeTimestamps[peerId]?.isNotEmpty,
        isTrue,
      );

      UntrustedIdentityRegistry.resolve(peerId);
      expect(UntrustedIdentityRegistry.hasUntrustedIdentity(peerId), isFalse);
      expect(UntrustedIdentityRegistry.pendingUntrustedKeys[peerId], isNull);
    });

    test(
      'computeSafetyNumber produces deterministic formatted string',
      () async {
        final localKeyPair = generateIdentityKeyPair();
        final peerKeyPair = generateIdentityKeyPair();

        final safetyNumber1 =
            await UntrustedIdentityRegistry.computeSafetyNumber(
              localKeyPair,
              peerKeyPair.getPublicKey(),
            );
        final safetyNumber2 =
            await UntrustedIdentityRegistry.computeSafetyNumber(
              localKeyPair,
              peerKeyPair.getPublicKey(),
            );

        expect(safetyNumber1, equals(safetyNumber2));
        // Format: 12 blocks of 5 digits separated by spaces (60 digits total)
        final parts = safetyNumber1.split(' ');
        expect(parts.length, equals(12));
        for (final part in parts) {
          expect(part.length, equals(5));
          expect(int.tryParse(part), isNotNull);
        }
      },
    );

    test(
      'PrekeyExhaustionRegistry marks, checks, and clears exhausted peers',
      () {
        const peerId = 'exhausted-peer-123';
        expect(PrekeyExhaustionRegistry.isExhausted(peerId), isFalse);

        PrekeyExhaustionRegistry.markExhausted(peerId);
        expect(PrekeyExhaustionRegistry.isExhausted(peerId), isTrue);

        PrekeyExhaustionRegistry.clear(peerId);
        expect(PrekeyExhaustionRegistry.isExhausted(peerId), isFalse);
      },
    );

    test('SignalCryptoLock serializes concurrent async executions', () async {
      final order = <int>[];

      final f1 = SignalCryptoLock.synchronized(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        order.add(1);
        return 1;
      });

      final f2 = SignalCryptoLock.synchronized(() async {
        order.add(2);
        return 2;
      });

      final results = await Future.wait<int>([f1, f2]);
      expect(results, equals([1, 2]));
      expect(order, equals([1, 2]));
    });
  });
}
