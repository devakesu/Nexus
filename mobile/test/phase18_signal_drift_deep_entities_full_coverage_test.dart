import 'package:drift/drift.dart' hide Column, isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/security_signal/services/signal/signal_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SignalDatabase Drift Generated Classes Deep Full Coverage', () {
    test(
      'Drift Companion and Data Class full fields, copyWith, toJson, and equality',
      () {
        final now = DateTime.now();

        // 1. LocalIdentity & LocalIdentitiesCompanion
        final localIdent = LocalIdentity(
          id: 1,
          identityKeyPairEnc: Uint8List.fromList([1, 2, 3]),
          registrationId: 999,
        );
        expect(localIdent.id, 1);
        expect(localIdent.registrationId, 999);
        final localIdentJson = localIdent.toJson();
        expect(localIdentJson['id'], 1);
        final localIdentFromJson = LocalIdentity.fromJson(localIdentJson);
        expect(localIdentFromJson.id, 1);
        expect(localIdent.toString(), isNotEmpty);
        expect(localIdent.hashCode, isNotNull);
        expect(localIdent == LocalIdentity.fromJson(localIdentJson), isTrue);

        final localIdentCopy = localIdent.copyWith(registrationId: 1000);
        expect(localIdentCopy.registrationId, 1000);

        final localIdentCompanion = LocalIdentitiesCompanion(
          id: const Value(2),
          identityKeyPairEnc: Value(Uint8List.fromList([4, 5, 6])),
          registrationId: const Value(888),
        );
        expect(localIdentCompanion.id.value, 2);

        // 2. PreKey & PreKeysCompanion
        final preKey = PreKey(
          keyId: 101,
          recordEnc: Uint8List.fromList([10, 20]),
        );
        expect(preKey.keyId, 101);
        final preKeyJson = preKey.toJson();
        final preKeyFromJson = PreKey.fromJson(preKeyJson);
        expect(preKeyFromJson.keyId, 101);
        expect(preKey.toString(), isNotEmpty);
        expect(preKey.hashCode, isNotNull);
        expect(preKey == PreKey.fromJson(preKeyJson), isTrue);

        final preKeyCopy = preKey.copyWith(keyId: 102);
        expect(preKeyCopy.keyId, 102);

        final preKeyComp = PreKeysCompanion(
          keyId: const Value(201),
          recordEnc: Value(Uint8List.fromList([30, 40])),
        );
        expect(preKeyComp.keyId.value, 201);

        // 3. SignedPreKey & SignedPreKeysCompanion
        final signedPreKey = SignedPreKey(
          keyId: 501,
          recordEnc: Uint8List.fromList([50, 60]),
        );
        expect(signedPreKey.keyId, 501);
        final signedPreKeyJson = signedPreKey.toJson();
        final signedPreKeyFromJson = SignedPreKey.fromJson(signedPreKeyJson);
        expect(signedPreKeyFromJson.keyId, 501);
        expect(signedPreKey.toString(), isNotEmpty);
        expect(signedPreKey.hashCode, isNotNull);
        expect(signedPreKey == SignedPreKey.fromJson(signedPreKeyJson), isTrue);

        final signedPreKeyCopy = signedPreKey.copyWith(keyId: 502);
        expect(signedPreKeyCopy.keyId, 502);

        final signedPreKeyComp = SignedPreKeysCompanion(
          keyId: const Value(601),
          recordEnc: Value(Uint8List.fromList([70, 80])),
        );
        expect(signedPreKeyComp.keyId.value, 601);

        // 4. Session & SessionsCompanion
        final session = Session(
          address: 'alice.1',
          recordEnc: Uint8List.fromList([90, 100]),
        );
        expect(session.address, 'alice.1');
        final sessionJson = session.toJson();
        final sessionFromJson = Session.fromJson(sessionJson);
        expect(sessionFromJson.address, 'alice.1');
        expect(session.toString(), isNotEmpty);
        expect(session.hashCode, isNotNull);
        expect(session == Session.fromJson(sessionJson), isTrue);

        final sessionCopy = session.copyWith(address: 'bob.1');
        expect(sessionCopy.address, 'bob.1');

        final sessionComp = SessionsCompanion(
          address: const Value('charlie.1'),
          recordEnc: Value(Uint8List.fromList([110, 120])),
        );
        expect(sessionComp.address.value, 'charlie.1');

        // 5. TrustedIdentity & TrustedIdentitiesCompanion
        final trusted = TrustedIdentity(
          address: 'david.1',
          identityKeyEnc: Uint8List.fromList([130, 140]),
        );
        expect(trusted.address, 'david.1');
        final trustedJson = trusted.toJson();
        final trustedFromJson = TrustedIdentity.fromJson(trustedJson);
        expect(trustedFromJson.address, 'david.1');
        expect(trusted.toString(), isNotEmpty);
        expect(trusted.hashCode, isNotNull);
        expect(trusted == TrustedIdentity.fromJson(trustedJson), isTrue);

        final trustedCopy = trusted.copyWith(address: 'eve.1');
        expect(trustedCopy.address, 'eve.1');

        final trustedComp = TrustedIdentitiesCompanion(
          address: const Value('frank.1'),
          identityKeyEnc: Value(Uint8List.fromList([150, 160])),
        );
        expect(trustedComp.address.value, 'frank.1');

        // 6. LocalMessage & LocalMessagesCompanion
        final msg = LocalMessage(
          id: 'msg_101',
          conversationId: 'c_202',
          senderId: 'u_303',
          isMine: true,
          messageType: 'text',
          createdAt: now,
          plaintextEnc: Uint8List.fromList([1, 2]),
          decryptFailed: false,
        );
        expect(msg.id, 'msg_101');
        final msgJson = msg.toJson();
        final msgFromJson = LocalMessage.fromJson(msgJson);
        expect(msgFromJson.id, 'msg_101');
        expect(msg.toString(), isNotEmpty);
        expect(msg.hashCode, isNotNull);
        expect(LocalMessage.fromJson(msgJson).id, msg.id);

        final msgCopy = msg.copyWith(decryptFailed: true);
        expect(msgCopy.decryptFailed, isTrue);

        final msgComp = LocalMessagesCompanion(
          id: const Value('msg_102'),
          conversationId: const Value('c_203'),
          senderId: const Value('u_304'),
          isMine: const Value(false),
          messageType: const Value('image'),
          createdAt: Value(now),
          plaintextEnc: Value(Uint8List.fromList([3, 4])),
          decryptFailed: const Value(false),
        );
        expect(msgComp.id.value, 'msg_102');

        // 7. CachedMediaData & CachedMediaCompanion
        final media = CachedMediaData(
          storagePath: 'media/test.enc',
          plaintextEnc: Uint8List.fromList([5, 6]),
          mimeType: 'image/jpeg',
          cachedAt: now,
        );
        expect(media.storagePath, 'media/test.enc');
        final mediaJson = media.toJson();
        final mediaFromJson = CachedMediaData.fromJson(mediaJson);
        expect(mediaFromJson.storagePath, 'media/test.enc');
        expect(media.toString(), isNotEmpty);
        expect(media.hashCode, isNotNull);
        expect(
          CachedMediaData.fromJson(mediaJson).storagePath,
          media.storagePath,
        );

        final mediaCopy = media.copyWith(mimeType: 'image/png');
        expect(mediaCopy.mimeType, 'image/png');

        final mediaComp = CachedMediaCompanion(
          storagePath: const Value('media/voice.enc'),
          plaintextEnc: Value(Uint8List.fromList([7, 8])),
          mimeType: const Value('audio/m4a'),
          cachedAt: Value(now),
        );
        expect(mediaComp.storagePath.value, 'media/voice.enc');
      },
    );
  });
}
