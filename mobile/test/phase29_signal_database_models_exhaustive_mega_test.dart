import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/security_signal/services/signal/signal_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group(
    'SignalDatabase Drift Models, Companions & Serialization Exhaustive Tests',
    () {
      test('LocalIdentity and LocalIdentitiesCompanion methods', () {
        final bytes = Uint8List.fromList([1, 2, 3, 4]);
        final identity = LocalIdentity(
          id: 1,
          identityKeyPairEnc: bytes,
          registrationId: 42,
        );

        expect(identity.id, 1);
        expect(identity.identityKeyPairEnc, bytes);
        expect(identity.registrationId, 42);
        expect(identity.toString(), contains('LocalIdentity'));
        expect(identity.hashCode, isNotNull);

        final copy = identity.copyWith(registrationId: 99);
        expect(copy.registrationId, 99);
        expect(copy.id, 1);
        expect(identity == copy, isFalse);

        final identity2 = LocalIdentity(
          id: 1,
          identityKeyPairEnc: bytes,
          registrationId: 42,
        );
        expect(identity == identity2, isTrue);

        final json = identity.toJson();
        expect(json['id'], 1);
        expect(json['registrationId'], 42);

        final fromJson = LocalIdentity.fromJson(json);
        expect(fromJson.id, 1);
        expect(fromJson.registrationId, 42);

        final companion = LocalIdentitiesCompanion.insert(
          id: const Value(1),
          identityKeyPairEnc: bytes,
          registrationId: 42,
        );
        expect(companion.registrationId.value, 42);
        expect(companion.toString(), contains('LocalIdentitiesCompanion'));
        expect(companion.copyWith(id: const Value(2)).id.value, 2);
      });

      test('PreKey and PreKeysCompanion methods', () {
        final bytes = Uint8List.fromList([5, 6, 7]);
        final preKey = PreKey(keyId: 10, recordEnc: bytes);

        expect(preKey.keyId, 10);
        expect(preKey.recordEnc, bytes);
        expect(preKey.toString(), contains('PreKey'));
        expect(preKey.hashCode, isNotNull);

        final copy = preKey.copyWith(keyId: 20);
        expect(copy.keyId, 20);
        expect(preKey == copy, isFalse);

        final preKey2 = PreKey(keyId: 10, recordEnc: bytes);
        expect(preKey == preKey2, isTrue);

        final json = preKey.toJson();
        expect(json['keyId'], 10);

        final fromJson = PreKey.fromJson(json);
        expect(fromJson.keyId, 10);

        final companion = PreKeysCompanion.insert(
          keyId: const Value(10),
          recordEnc: bytes,
        );
        expect(companion.keyId.value, 10);
        expect(companion.toString(), contains('PreKeysCompanion'));
      });

      test('SignedPreKey and SignedPreKeysCompanion methods', () {
        final bytes = Uint8List.fromList([8, 9, 10]);
        final signedKey = SignedPreKey(keyId: 100, recordEnc: bytes);

        expect(signedKey.keyId, 100);
        expect(signedKey.recordEnc, bytes);
        expect(signedKey.toString(), contains('SignedPreKey'));
        expect(signedKey.hashCode, isNotNull);

        final copy = signedKey.copyWith(keyId: 200);
        expect(copy.keyId, 200);

        final signedKey2 = SignedPreKey(keyId: 100, recordEnc: bytes);
        expect(signedKey == signedKey2, isTrue);

        final json = signedKey.toJson();
        expect(json['keyId'], 100);

        final fromJson = SignedPreKey.fromJson(json);
        expect(fromJson.keyId, 100);

        final companion = SignedPreKeysCompanion.insert(
          keyId: const Value(100),
          recordEnc: bytes,
        );
        expect(companion.keyId.value, 100);
      });

      test('Session and SessionsCompanion methods', () {
        final bytes = Uint8List.fromList([11, 12, 13]);
        final session = Session(address: 'user_123:1', recordEnc: bytes);

        expect(session.address, 'user_123:1');
        expect(session.recordEnc, bytes);
        expect(session.toString(), contains('Session'));
        expect(session.hashCode, isNotNull);

        final copy = session.copyWith(address: 'user_456:1');
        expect(copy.address, 'user_456:1');

        final session2 = Session(address: 'user_123:1', recordEnc: bytes);
        expect(session == session2, isTrue);

        final json = session.toJson();
        expect(json['address'], 'user_123:1');

        final fromJson = Session.fromJson(json);
        expect(fromJson.address, 'user_123:1');

        final companion = SessionsCompanion.insert(
          address: 'user_123:1',
          recordEnc: bytes,
        );
        expect(companion.address.value, 'user_123:1');
      });

      test('TrustedIdentity and TrustedIdentitiesCompanion methods', () {
        final bytes = Uint8List.fromList([14, 15, 16]);
        final trusted = TrustedIdentity(
          address: 'remote_user:1',
          identityKeyEnc: bytes,
        );

        expect(trusted.address, 'remote_user:1');
        expect(trusted.identityKeyEnc, bytes);
        expect(trusted.toString(), contains('TrustedIdentity'));
        expect(trusted.hashCode, isNotNull);

        final copy = trusted.copyWith(address: 'remote_user_2:1');
        expect(copy.address, 'remote_user_2:1');

        final trusted2 = TrustedIdentity(
          address: 'remote_user:1',
          identityKeyEnc: bytes,
        );
        expect(trusted == trusted2, isTrue);

        final json = trusted.toJson();
        expect(json['address'], 'remote_user:1');

        final fromJson = TrustedIdentity.fromJson(json);
        expect(fromJson.address, 'remote_user:1');

        final companion = TrustedIdentitiesCompanion.insert(
          address: 'remote_user:1',
          identityKeyEnc: bytes,
        );
        expect(companion.address.value, 'remote_user:1');
      });

      test('LocalMessage and LocalMessagesCompanion methods', () {
        final now = DateTime.now();
        final bytes = Uint8List.fromList([17, 18, 19]);
        final msg = LocalMessage(
          id: 'msg_1',
          conversationId: 'conv_1',
          senderId: 'sender_1',
          isMine: true,
          createdAt: now,
          messageType: 'text',
          plaintextEnc: bytes,
          decryptFailed: false,
        );

        expect(msg.id, 'msg_1');
        expect(msg.conversationId, 'conv_1');
        expect(msg.senderId, 'sender_1');
        expect(msg.isMine, isTrue);
        expect(msg.createdAt, now);
        expect(msg.messageType, 'text');
        expect(msg.plaintextEnc, bytes);
        expect(msg.decryptFailed, isFalse);
        expect(msg.toString(), contains('LocalMessage'));
        expect(msg.hashCode, isNotNull);

        final copy = msg.copyWith(decryptFailed: true);
        expect(copy.decryptFailed, isTrue);

        final msg2 = LocalMessage(
          id: 'msg_1',
          conversationId: 'conv_1',
          senderId: 'sender_1',
          isMine: true,
          createdAt: now,
          messageType: 'text',
          plaintextEnc: bytes,
          decryptFailed: false,
        );
        expect(msg == msg2, isTrue);

        final json = msg.toJson();
        expect(json['id'], 'msg_1');
        expect(json['conversationId'], 'conv_1');

        final fromJson = LocalMessage.fromJson(json);
        expect(fromJson.id, 'msg_1');

        final companion = LocalMessagesCompanion.insert(
          id: 'msg_1',
          conversationId: 'conv_1',
          senderId: 'sender_1',
          isMine: true,
          createdAt: now,
          messageType: 'text',
          plaintextEnc: Value(bytes),
          decryptFailed: const Value(false),
        );
        expect(companion.id.value, 'msg_1');
      });

      test('CachedMediaData and CachedMediaCompanion methods', () {
        final now = DateTime.now();
        final bytes = Uint8List.fromList([20, 21, 22]);
        final media = CachedMediaData(
          storagePath: 'conv/user/uuid.enc',
          plaintextEnc: bytes,
          mimeType: 'image/jpeg',
          cachedAt: now,
        );

        expect(media.storagePath, 'conv/user/uuid.enc');
        expect(media.plaintextEnc, bytes);
        expect(media.mimeType, 'image/jpeg');
        expect(media.cachedAt, now);
        expect(media.toString(), contains('CachedMediaData'));
        expect(media.hashCode, isNotNull);

        final copy = media.copyWith(mimeType: 'image/png');
        expect(copy.mimeType, 'image/png');

        final media2 = CachedMediaData(
          storagePath: 'conv/user/uuid.enc',
          plaintextEnc: bytes,
          mimeType: 'image/jpeg',
          cachedAt: now,
        );
        expect(media == media2, isTrue);

        final json = media.toJson();
        expect(json['storagePath'], 'conv/user/uuid.enc');
        expect(json['mimeType'], 'image/jpeg');

        final fromJson = CachedMediaData.fromJson(json);
        expect(fromJson.storagePath, 'conv/user/uuid.enc');

        final companion = CachedMediaCompanion.insert(
          storagePath: 'conv/user/uuid.enc',
          plaintextEnc: bytes,
          mimeType: 'image/jpeg',
          cachedAt: now,
        );
        expect(companion.storagePath.value, 'conv/user/uuid.enc');
      });
    },
  );
}
