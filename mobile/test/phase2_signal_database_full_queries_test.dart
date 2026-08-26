import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/security_signal/services/signal/signal_database.dart';

void main() {
  group('SignalDatabase Generated Models & Companions Deep Tests', () {
    test('LocalIdentitiesCompanion and LocalIdentity data operations', () {
      final blob = Uint8List.fromList([1, 2, 3, 4, 5]);
      final identity = LocalIdentity(
        id: 1,
        identityKeyPairEnc: blob,
        registrationId: 4321,
      );

      expect(identity.id, 1);
      expect(identity.identityKeyPairEnc, blob);
      expect(identity.registrationId, 4321);

      final companion = LocalIdentitiesCompanion.insert(
        id: const Value(1),
        identityKeyPairEnc: blob,
        registrationId: 4321,
      );

      expect(companion.id.value, 1);
      expect(companion.registrationId.value, 4321);

      final json = identity.toJson();
      expect(json['id'], 1);
      expect(json['registrationId'], 4321);

      final copy = identity.copyWith(registrationId: 9999);
      expect(copy.registrationId, 9999);
      expect(copy.id, 1);
    });

    test('PreKeysCompanion and PreKey data operations', () {
      final blob = Uint8List.fromList([10, 20, 30]);
      final preKey = PreKey(keyId: 101, recordEnc: blob);

      expect(preKey.keyId, 101);
      expect(preKey.recordEnc, blob);

      final companion = PreKeysCompanion.insert(
        keyId: const Value(101),
        recordEnc: blob,
      );
      expect(companion.keyId.value, 101);

      final json = preKey.toJson();
      expect(json['keyId'], 101);

      final copy = preKey.copyWith(keyId: 202);
      expect(copy.keyId, 202);
    });

    test('SignedPreKeysCompanion and SignedPreKey data operations', () {
      final blob = Uint8List.fromList([50, 60, 70]);
      final signedPreKey = SignedPreKey(keyId: 501, recordEnc: blob);

      expect(signedPreKey.keyId, 501);
      expect(signedPreKey.recordEnc, blob);

      final companion = SignedPreKeysCompanion.insert(
        keyId: const Value(501),
        recordEnc: blob,
      );
      expect(companion.keyId.value, 501);

      final json = signedPreKey.toJson();
      expect(json['keyId'], 501);

      final copy = signedPreKey.copyWith(keyId: 602);
      expect(copy.keyId, 602);
    });

    test('SessionsCompanion and Session data operations', () {
      final blob = Uint8List.fromList([11, 22, 33]);
      final session = Session(address: 'user_a:1', recordEnc: blob);

      expect(session.address, 'user_a:1');
      expect(session.recordEnc, blob);

      final companion = SessionsCompanion.insert(
        address: 'user_a:1',
        recordEnc: blob,
      );
      expect(companion.address.value, 'user_a:1');

      final json = session.toJson();
      expect(json['address'], 'user_a:1');

      final copy = session.copyWith(address: 'user_b:1');
      expect(copy.address, 'user_b:1');
    });

    test('TrustedIdentitiesCompanion and TrustedIdentity data operations', () {
      final blob = Uint8List.fromList([99, 88, 77]);
      final trusted = TrustedIdentity(
        address: 'user_c:1',
        identityKeyEnc: blob,
      );

      expect(trusted.address, 'user_c:1');
      expect(trusted.identityKeyEnc, blob);

      final companion = TrustedIdentitiesCompanion.insert(
        address: 'user_c:1',
        identityKeyEnc: blob,
      );
      expect(companion.address.value, 'user_c:1');

      final json = trusted.toJson();
      expect(json['address'], 'user_c:1');

      final copy = trusted.copyWith(address: 'user_d:1');
      expect(copy.address, 'user_d:1');
    });

    test('LocalMessagesCompanion and LocalMessage data operations', () {
      final now = DateTime.now();
      final blob = Uint8List.fromList([1, 2, 3]);
      final msg = LocalMessage(
        id: 'msg_100',
        conversationId: 'conv_1',
        senderId: 'user_me',
        isMine: true,
        createdAt: now,
        messageType: 'text',
        plaintextEnc: blob,
        decryptFailed: false,
      );

      expect(msg.id, 'msg_100');
      expect(msg.conversationId, 'conv_1');
      expect(msg.isMine, true);
      expect(msg.decryptFailed, false);

      final companion = LocalMessagesCompanion.insert(
        id: 'msg_100',
        conversationId: 'conv_1',
        senderId: 'user_me',
        isMine: true,
        createdAt: now,
        messageType: 'text',
        plaintextEnc: Value(blob),
      );
      expect(companion.id.value, 'msg_100');

      final json = msg.toJson();
      expect(json['id'], 'msg_100');
      expect(json['conversationId'], 'conv_1');

      final copy = msg.copyWith(decryptFailed: true);
      expect(copy.decryptFailed, true);
    });

    test('CachedMediaCompanion and CachedMediaData data operations', () {
      final now = DateTime.now();
      final blob = Uint8List.fromList([7, 8, 9]);
      final media = CachedMediaData(
        storagePath: 'chat_media/c1/img.jpg',
        plaintextEnc: blob,
        mimeType: 'image/jpeg',
        cachedAt: now,
      );

      expect(media.storagePath, 'chat_media/c1/img.jpg');
      expect(media.mimeType, 'image/jpeg');

      final companion = CachedMediaCompanion.insert(
        storagePath: 'chat_media/c1/img.jpg',
        plaintextEnc: blob,
        mimeType: 'image/jpeg',
        cachedAt: now,
      );
      expect(companion.storagePath.value, 'chat_media/c1/img.jpg');

      final json = media.toJson();
      expect(json['storagePath'], 'chat_media/c1/img.jpg');
      expect(json['mimeType'], 'image/jpeg');

      final copy = media.copyWith(mimeType: 'image/png');
      expect(copy.mimeType, 'image/png');
    });
  });
}
