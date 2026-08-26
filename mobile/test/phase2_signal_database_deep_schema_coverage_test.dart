import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/security_signal/services/signal/signal_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SignalDatabase Deep Data Class & Companion Coverage Tests', () {
    test('LocalIdentity data class and companion operations', () {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final model = LocalIdentity(
        id: 1,
        identityKeyPairEnc: bytes,
        registrationId: 12345,
      );

      expect(model.id, 1);
      expect(model.registrationId, 12345);
      expect(model.identityKeyPairEnc, bytes);

      final copy = model.copyWith(registrationId: 54321);
      expect(copy.registrationId, 54321);
      expect(model.toString(), isNotEmpty);
      expect(model.hashCode != 0, true);
      expect(model == copy, false);

      final json = model.toJson();
      expect(json['id'], 1);
      expect(json['registrationId'], 12345);
      final fromJson = LocalIdentity.fromJson(json);
      expect(fromJson.id, 1);

      final companion = LocalIdentitiesCompanion(
        id: const Value(1),
        identityKeyPairEnc: Value(bytes),
        registrationId: const Value(12345),
      );
      expect(companion.id.value, 1);
      expect(companion.toString(), isNotEmpty);
      expect(companion.toColumns(true), isNotEmpty);

      final companionInsert = LocalIdentitiesCompanion.insert(
        identityKeyPairEnc: bytes,
        registrationId: 9999,
      );
      expect(companionInsert.registrationId.value, 9999);
      final companionCopy = companion.copyWith(id: const Value(2));
      expect(companionCopy.id.value, 2);
    });

    test('PreKey data class and companion operations', () {
      final bytes = Uint8List.fromList([5, 6, 7]);
      final model = PreKey(
        keyId: 42,
        recordEnc: bytes,
      );

      expect(model.keyId, 42);
      expect(model.recordEnc, bytes);

      final copy = model.copyWith(keyId: 43);
      expect(copy.keyId, 43);
      expect(model.toString(), isNotEmpty);
      expect(model.hashCode != 0, true);

      final json = model.toJson();
      expect(json['keyId'], 42);
      final fromJson = PreKey.fromJson(json);
      expect(fromJson.keyId, 42);

      final companion = PreKeysCompanion(
        keyId: const Value(42),
        recordEnc: Value(bytes),
      );
      expect(companion.keyId.value, 42);
      expect(companion.toColumns(true), isNotEmpty);

      final companionInsert = PreKeysCompanion.insert(
        keyId: const Value(10),
        recordEnc: bytes,
      );
      expect(companionInsert.recordEnc.value, bytes);
      final companionCopy = companion.copyWith(keyId: const Value(45));
      expect(companionCopy.keyId.value, 45);
    });

    test('SignedPreKey data class and companion operations', () {
      final bytes = Uint8List.fromList([8, 9, 10]);
      final model = SignedPreKey(
        keyId: 99,
        recordEnc: bytes,
      );

      expect(model.keyId, 99);
      expect(model.recordEnc, bytes);

      final copy = model.copyWith(keyId: 100);
      expect(copy.keyId, 100);
      expect(model.toString(), isNotEmpty);
      expect(model.hashCode != 0, true);

      final json = model.toJson();
      expect(json['keyId'], 99);
      final fromJson = SignedPreKey.fromJson(json);
      expect(fromJson.keyId, 99);

      final companion = SignedPreKeysCompanion(
        keyId: const Value(99),
        recordEnc: Value(bytes),
      );
      expect(companion.keyId.value, 99);
      expect(companion.toColumns(true), isNotEmpty);

      final companionInsert = SignedPreKeysCompanion.insert(
        keyId: const Value(20),
        recordEnc: bytes,
      );
      expect(companionInsert.recordEnc.value, bytes);
      final companionCopy = companion.copyWith(keyId: const Value(101));
      expect(companionCopy.keyId.value, 101);
    });

    test('Session data class and companion operations', () {
      final bytes = Uint8List.fromList([11, 12, 13]);
      final model = Session(
        address: 'user_1:1',
        recordEnc: bytes,
      );

      expect(model.address, 'user_1:1');
      expect(model.recordEnc, bytes);

      final copy = model.copyWith(address: 'user_2:1');
      expect(copy.address, 'user_2:1');
      expect(model.toString(), isNotEmpty);
      expect(model.hashCode != 0, true);

      final json = model.toJson();
      expect(json['address'], 'user_1:1');
      final fromJson = Session.fromJson(json);
      expect(fromJson.address, 'user_1:1');

      final companion = SessionsCompanion(
        address: const Value('user_1:1'),
        recordEnc: Value(bytes),
      );
      expect(companion.address.value, 'user_1:1');
      expect(companion.toColumns(true), isNotEmpty);

      final companionInsert = SessionsCompanion.insert(
        address: 'user_new:1',
        recordEnc: bytes,
      );
      expect(companionInsert.address.value, 'user_new:1');
      final companionCopy = companion.copyWith(
        address: const Value('user_3:1'),
      );
      expect(companionCopy.address.value, 'user_3:1');
    });

    test('TrustedIdentity data class and companion operations', () {
      final bytes = Uint8List.fromList([14, 15, 16]);
      final model = TrustedIdentity(
        address: 'user_3:1',
        identityKeyEnc: bytes,
      );

      expect(model.address, 'user_3:1');
      expect(model.identityKeyEnc, bytes);

      final copy = model.copyWith(address: 'user_4:1');
      expect(copy.address, 'user_4:1');
      expect(model.toString(), isNotEmpty);
      expect(model.hashCode != 0, true);

      final json = model.toJson();
      expect(json['address'], 'user_3:1');
      final fromJson = TrustedIdentity.fromJson(json);
      expect(fromJson.address, 'user_3:1');

      final companion = TrustedIdentitiesCompanion(
        address: const Value('user_3:1'),
        identityKeyEnc: Value(bytes),
      );
      expect(companion.address.value, 'user_3:1');
      expect(companion.toColumns(true), isNotEmpty);

      final companionInsert = TrustedIdentitiesCompanion.insert(
        address: 'user_5:1',
        identityKeyEnc: bytes,
      );
      expect(companionInsert.address.value, 'user_5:1');
      final companionCopy = companion.copyWith(
        address: const Value('user_6:1'),
      );
      expect(companionCopy.address.value, 'user_6:1');
    });

    test('LocalMessage data class and companion operations', () {
      final now = DateTime.now();
      final bytes = Uint8List.fromList([17, 18, 19]);
      final model = LocalMessage(
        id: 'msg_101',
        conversationId: 'conv_555',
        senderId: 'user_sender',
        isMine: true,
        createdAt: now,
        messageType: 'text',
        plaintextEnc: bytes,
        decryptFailed: false,
      );

      expect(model.id, 'msg_101');
      expect(model.conversationId, 'conv_555');
      expect(model.senderId, 'user_sender');
      expect(model.isMine, true);
      expect(model.messageType, 'text');
      expect(model.decryptFailed, false);
      expect(model.plaintextEnc, bytes);

      final copy = model.copyWith(decryptFailed: true);
      expect(copy.decryptFailed, true);
      expect(model.toString(), isNotEmpty);
      expect(model.hashCode != 0, true);

      final json = model.toJson();
      expect(json['id'], 'msg_101');
      final fromJson = LocalMessage.fromJson(json);
      expect(fromJson.id, 'msg_101');

      final companion = LocalMessagesCompanion(
        id: const Value('msg_101'),
        conversationId: const Value('conv_555'),
        senderId: const Value('user_sender'),
        isMine: const Value(true),
        createdAt: Value(now),
        messageType: const Value('text'),
        plaintextEnc: Value(bytes),
        decryptFailed: const Value(false),
      );
      expect(companion.id.value, 'msg_101');
      expect(companion.toColumns(true), isNotEmpty);

      final companionInsert = LocalMessagesCompanion.insert(
        id: 'msg_102',
        conversationId: 'conv_555',
        senderId: 'user_sender',
        isMine: false,
        createdAt: now,
        messageType: 'image',
      );
      expect(companionInsert.id.value, 'msg_102');
      final companionCopy = companion.copyWith(id: const Value('msg_103'));
      expect(companionCopy.id.value, 'msg_103');
    });

    test('CachedMediaData data class and companion operations', () {
      final now = DateTime.now();
      final bytes = Uint8List.fromList([20, 21, 22]);
      final model = CachedMediaData(
        storagePath: 'conv_555/user_sender/media_1.enc',
        plaintextEnc: bytes,
        mimeType: 'image/jpeg',
        cachedAt: now,
      );

      expect(model.storagePath, 'conv_555/user_sender/media_1.enc');
      expect(model.mimeType, 'image/jpeg');
      expect(model.plaintextEnc, bytes);

      final copy = model.copyWith(mimeType: 'image/png');
      expect(copy.mimeType, 'image/png');
      expect(model.toString(), isNotEmpty);
      expect(model.hashCode != 0, true);

      final json = model.toJson();
      expect(json['storagePath'], 'conv_555/user_sender/media_1.enc');
      final fromJson = CachedMediaData.fromJson(json);
      expect(fromJson.storagePath, 'conv_555/user_sender/media_1.enc');

      final companion = CachedMediaCompanion(
        storagePath: const Value('conv_555/user_sender/media_1.enc'),
        plaintextEnc: Value(bytes),
        mimeType: const Value('image/jpeg'),
        cachedAt: Value(now),
      );
      expect(companion.storagePath.value, 'conv_555/user_sender/media_1.enc');
      expect(companion.toColumns(true), isNotEmpty);

      final companionInsert = CachedMediaCompanion.insert(
        storagePath: 'path_new.enc',
        plaintextEnc: bytes,
        mimeType: 'audio/mp4',
        cachedAt: now,
      );
      expect(companionInsert.storagePath.value, 'path_new.enc');
      final companionCopy = companion.copyWith(
        storagePath: const Value('path_other.enc'),
      );
      expect(companionCopy.storagePath.value, 'path_other.enc');
    });
  });
}
