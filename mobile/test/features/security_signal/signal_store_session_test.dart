import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:nexus/features/security_signal/services/signal/local_key_vault.dart';
import 'package:nexus/features/security_signal/services/signal/media_crypto.dart';
import 'package:nexus/features/security_signal/services/signal/signal_database.dart';
import 'package:nexus/features/security_signal/services/signal/signal_store.dart';

import '../../helpers/test_helpers.dart';

void main() {
  setUpTestEnvironment();

  setUpAll(() async {
    await initMockSupabase();
  });

  // --- Section 1 ---
  {
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

    setUp(() async {
      db = SignalDatabase.instance;
      try {
        await db.clearAllData();
      } on Object catch (_) {}

      aliceIdentityKeyPair = generateIdentityKeyPair();
      aliceRegId = generateRegistrationId(false);
      aliceStore = DriftSignalProtocolStore(
        db,
        aliceIdentityKeyPair,
        aliceRegId,
      );

      bobIdentityKeyPair = generateIdentityKeyPair();
      bobRegId = generateRegistrationId(false);
      DriftSignalProtocolStore(db, bobIdentityKeyPair, bobRegId);
    });

    group('LocalKeyVault & MediaCrypto Tests', () {
      test('LocalKeyVault encrypts, decrypts and wipes keys', () async {
        final vault = LocalKeyVault.instance;
        final plaintext = Uint8List.fromList(
          utf8.encode('TopSecretPayload123'),
        );

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

        final uniqueSuffix = DateTime.now().microsecondsSinceEpoch;
        final bobAddress = SignalProtocolAddress(
          'bob_user_id_$uniqueSuffix',
          1,
        );

        await aliceStore.saveIdentity(
          bobAddress,
          bobIdentityKeyPair.getPublicKey(),
        );

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
          final signedPreKey = generateSignedPreKey(aliceIdentityKeyPair, 100);
          await aliceStore.storeSignedPreKey(signedPreKey.id, signedPreKey);
          expect(await aliceStore.containsSignedPreKey(100), isTrue);

          final loaded = await aliceStore.loadSignedPreKey(100);
          expect(loaded.id, equals(100));

          final allSignedKeys = await aliceStore.loadSignedPreKeys();
          expect(allSignedKeys, isNotEmpty);

          await aliceStore.removeSignedPreKey(100);
          expect(await aliceStore.containsSignedPreKey(100), isFalse);
        },
      );

      test(
        'SessionStore operations (store, contains, load, delete, getSubDeviceSessions)',
        () async {
          final uniqueSuffix = DateTime.now().microsecondsSinceEpoch;
          final addr = SignalProtocolAddress('device_user_$uniqueSuffix', 2);
          final sessionRecord = SessionRecord();

          await aliceStore.storeSession(addr, sessionRecord);
          expect(await aliceStore.containsSession(addr), isTrue);

          final loaded = await aliceStore.loadSession(addr);
          expect(loaded.serialize(), equals(sessionRecord.serialize()));

          final subDevices = await aliceStore.getSubDeviceSessions(
            addr.getName(),
          );
          expect(subDevices, contains(2));

          await aliceStore.deleteSession(addr);
          expect(await aliceStore.containsSession(addr), isFalse);
          await aliceStore.deleteAllSessions(addr.getName());
        },
      );
    });
  }
}
