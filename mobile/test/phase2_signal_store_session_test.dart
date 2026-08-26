import 'dart:convert';

import 'package:flutter/services.dart' hide MessageCodec;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:nexus/features/security_signal/services/signal/local_key_vault.dart';
import 'package:nexus/features/security_signal/services/signal/media_crypto.dart';
import 'package:nexus/features/security_signal/services/signal/message_codec.dart';
import 'package:nexus/features/security_signal/services/signal/session_manager.dart';
import 'package:nexus/features/security_signal/services/signal/signal_database.dart';
import 'package:nexus/features/security_signal/services/signal/signal_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => '.',
      );

  late SignalDatabase db;
  late IdentityKeyPair aliceIdentityKeyPair;
  late int aliceRegId;
  late DriftSignalProtocolStore aliceStore;

  late IdentityKeyPair bobIdentityKeyPair;
  late int bobRegId;
  late DriftSignalProtocolStore bobStore;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    db = SignalDatabase.instance;
    await db.clearAllData();

    aliceIdentityKeyPair = generateIdentityKeyPair();
    aliceRegId = generateRegistrationId(false);
    aliceStore = DriftSignalProtocolStore(db, aliceIdentityKeyPair, aliceRegId);

    bobIdentityKeyPair = generateIdentityKeyPair();
    bobRegId = generateRegistrationId(false);
    bobStore = DriftSignalProtocolStore(db, bobIdentityKeyPair, bobRegId);
  });

  group('LocalKeyVault & MediaCrypto Tests', () {
    test('LocalKeyVault encrypts, decrypts and wipes keys', () async {
      final vault = LocalKeyVault.instance;
      final plaintext = Uint8List.fromList(utf8.encode('TopSecretPayload123'));

      final encrypted = await vault.encryptBytes(plaintext);
      expect(encrypted, isNot(equals(plaintext)));

      final decrypted = await vault.decryptBytes(encrypted);
      expect(decrypted, equals(plaintext));

      await vault.wipeKeys();
    });

    test('MediaCrypto encrypts and decrypts media payloads', () async {
      final mediaCrypto = MediaCrypto.instance;
      final rawData = Uint8List.fromList(
        List.generate(1024, (i) => (i * 7) % 256),
      );

      final encResult = await mediaCrypto.encrypt(rawData);
      expect(encResult.ciphertext, isNotEmpty);
      expect(encResult.mediaKeyBase64, isNotEmpty);

      final decrypted = await mediaCrypto.decrypt(
        encResult.ciphertext,
        encResult.mediaKeyBase64,
      );
      expect(decrypted, equals(rawData));
    });
  });

  group('DriftSignalProtocolStore Unit Tests', () {
    test('IdentityKeyStore operations', () async {
      expect(
        await aliceStore.getIdentityKeyPair(),
        equals(aliceIdentityKeyPair),
      );
      expect(await aliceStore.getLocalRegistrationId(), equals(aliceRegId));

      const bobAddress = SignalProtocolAddress('bob_user_id', 1);
      expect(await aliceStore.getIdentity(bobAddress), isNull);
      expect(
        await aliceStore.isTrustedIdentity(
          bobAddress,
          bobIdentityKeyPair.getPublicKey(),
          Direction.sending,
        ),
        isTrue,
      );

      final changed = await aliceStore.saveIdentity(
        bobAddress,
        bobIdentityKeyPair.getPublicKey(),
      );
      expect(changed, isTrue);

      final fetchedIdentity = await aliceStore.getIdentity(bobAddress);
      expect(fetchedIdentity, isNotNull);
      expect(
        fetchedIdentity!.serialize(),
        equals(bobIdentityKeyPair.getPublicKey().serialize()),
      );

      // Trust check sending & receiving
      expect(
        await aliceStore.isTrustedIdentity(
          bobAddress,
          bobIdentityKeyPair.getPublicKey(),
          Direction.sending,
        ),
        isTrue,
      );
      expect(
        await aliceStore.isTrustedIdentity(
          bobAddress,
          bobIdentityKeyPair.getPublicKey(),
          Direction.receiving,
        ),
        isTrue,
      );

      // Saving same identity returns false for changed
      final changedAgain = await aliceStore.saveIdentity(
        bobAddress,
        bobIdentityKeyPair.getPublicKey(),
      );
      expect(changedAgain, isFalse);
    });

    test('PreKeyStore operations (store, contains, load, remove)', () async {
      final prekeys = generatePreKeys(1, 5);
      for (final pk in prekeys) {
        await aliceStore.storePreKey(pk.id, pk);
        expect(await aliceStore.containsPreKey(pk.id), isTrue);
      }

      final loadedPk = await aliceStore.loadPreKey(1);
      expect(loadedPk.id, equals(1));

      await aliceStore.removePreKey(1);
      expect(await aliceStore.containsPreKey(1), isFalse);
    });

    test(
      'SignedPreKeyStore operations (store, load, remove, contains)',
      () async {
        final spk = generateSignedPreKey(aliceIdentityKeyPair, 10);
        await aliceStore.storeSignedPreKey(10, spk);
        expect(await aliceStore.containsSignedPreKey(10), isTrue);

        final loadedSpk = await aliceStore.loadSignedPreKey(10);
        expect(loadedSpk.id, equals(10));

        final allSpks = await aliceStore.loadSignedPreKeys();
        expect(allSpks.length, equals(1));
        expect(allSpks.first.id, equals(10));

        await aliceStore.removeSignedPreKey(10);
        expect(await aliceStore.containsSignedPreKey(10), isFalse);
      },
    );

    test(
      'SessionStore operations (store, contains, load, delete, getSubDeviceSessions)',
      () async {
        const bobAddr = SignalProtocolAddress('bob_user_id', 2);
        expect(await aliceStore.containsSession(bobAddr), isFalse);

        final sessionRecord = SessionRecord();
        await aliceStore.storeSession(bobAddr, sessionRecord);
        expect(await aliceStore.containsSession(bobAddr), isTrue);

        final loadedSession = await aliceStore.loadSession(bobAddr);
        expect(loadedSession, isNotNull);

        final subDevices = await aliceStore.getSubDeviceSessions('bob_user_id');
        expect(subDevices, contains(2));

        await aliceStore.deleteSession(bobAddr);
        expect(await aliceStore.containsSession(bobAddr), isFalse);

        await aliceStore.deleteAllSessions('bob_user_id');
      },
    );
  });

  group('Signal Protocol End-to-End Encryption Tests', () {
    test(
      'Alice & Bob perform X3DH session build and exchange encrypted text',
      () async {
        const bobAddress = SignalProtocolAddress('bob_user', 1);
        const aliceAddress = SignalProtocolAddress('alice_user', 1);

        // Bob publishes prekeys
        final bobSignedPreKey = generateSignedPreKey(bobIdentityKeyPair, 1);
        await bobStore.storeSignedPreKey(1, bobSignedPreKey);
        final bobPreKeys = generatePreKeys(1, 1);
        await bobStore.storePreKey(1, bobPreKeys.first);

        final bobBundle = PreKeyBundle(
          bobRegId,
          1,
          1,
          bobPreKeys.first.getKeyPair().publicKey,
          1,
          bobSignedPreKey.getKeyPair().publicKey,
          bobSignedPreKey.signature,
          bobIdentityKeyPair.getPublicKey(),
        );

        // Alice builds session using Bob's bundle
        final sessionBuilder = SessionBuilder(
          aliceStore,
          aliceStore,
          aliceStore,
          aliceStore,
          bobAddress,
        );
        await sessionBuilder.processPreKeyBundle(bobBundle);

        // Alice encrypts message to Bob
        const originalMessage = 'Hello Bob, cosmic greetings from Alice!';
        final encryptedEnv = await MessageCodec.instance.encryptText(
          store: aliceStore,
          address: bobAddress,
          text: originalMessage,
        );

        expect(encryptedEnv.ciphertextBase64, isNotEmpty);
        expect(encryptedEnv.signalMessageType, equals('prekey'));

        // Bob decrypts message from Alice
        final decryptedText = await MessageCodec.instance.decryptText(
          store: bobStore,
          address: aliceAddress,
          ciphertextBase64: encryptedEnv.ciphertextBase64,
          signalMessageType: encryptedEnv.signalMessageType,
        );

        expect(decryptedText, equals(originalMessage));

        // Bob replies to Alice (now ratchet whisper)
        const replyMessage =
            'Greetings Alice! Encrypted cosmic link established.';
        final replyEnv = await MessageCodec.instance.encryptText(
          store: bobStore,
          address: aliceAddress,
          text: replyMessage,
        );
        expect(replyEnv.signalMessageType, equals('whisper'));

        final aliceDecryptedReply = await MessageCodec.instance.decryptText(
          store: aliceStore,
          address: bobAddress,
          ciphertextBase64: replyEnv.ciphertextBase64,
          signalMessageType: replyEnv.signalMessageType,
        );
        expect(aliceDecryptedReply, equals(replyMessage));
      },
    );
  });

  group('UntrustedIdentityRegistry & Safety Numbers Tests', () {
    test(
      'UntrustedIdentityRegistry registers, tracks timestamps and resolves',
      () {
        final fakeKey = generateIdentityKeyPair().getPublicKey();
        expect(
          UntrustedIdentityRegistry.hasUntrustedIdentity('peer_123'),
          isFalse,
        );

        UntrustedIdentityRegistry.register('peer_123', fakeKey);
        expect(
          UntrustedIdentityRegistry.hasUntrustedIdentity('peer_123'),
          isTrue,
        );
        expect(
          UntrustedIdentityRegistry.pendingUntrustedKeys['peer_123'],
          equals(fakeKey),
        );

        UntrustedIdentityRegistry.resolve('peer_123');
        expect(
          UntrustedIdentityRegistry.hasUntrustedIdentity('peer_123'),
          isFalse,
        );
      },
    );

    test(
      'computeSafetyNumber produces deterministic 60-digit formatted string',
      () async {
        final safetyNumber1 =
            await UntrustedIdentityRegistry.computeSafetyNumber(
              aliceIdentityKeyPair,
              bobIdentityKeyPair.getPublicKey(),
            );
        final safetyNumber2 =
            await UntrustedIdentityRegistry.computeSafetyNumber(
              aliceIdentityKeyPair,
              bobIdentityKeyPair.getPublicKey(),
            );

        expect(safetyNumber1, equals(safetyNumber2));
        expect(safetyNumber1.split(' ').length, equals(12));
      },
    );
  });

  group('PrekeyExhaustionRegistry Tests', () {
    test('marks and clears exhausted peers', () {
      expect(PrekeyExhaustionRegistry.isExhausted('user_x'), isFalse);
      PrekeyExhaustionRegistry.markExhausted('user_x');
      expect(PrekeyExhaustionRegistry.isExhausted('user_x'), isTrue);
      PrekeyExhaustionRegistry.clear('user_x');
      expect(PrekeyExhaustionRegistry.isExhausted('user_x'), isFalse);
    });
  });

  group('SignalCryptoLock Tests', () {
    test('executes actions serially without throwing', () async {
      final results = <int>[];
      await Future.wait([
        SignalCryptoLock.synchronized(() async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          results.add(1);
          return 1;
        }),
        SignalCryptoLock.synchronized(() async {
          results.add(2);
          return 2;
        }),
      ]);
      expect(results, equals([1, 2]));
    });
  });
}
