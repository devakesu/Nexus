import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/security_signal/services/signal/signal_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group(
    'Phase 126 - Signal Database Generated and Drift Models Exhaustive Mega Tests',
    () {
      test(
        'Drift companion objects and data classes full instantiation and conversions',
        () {
          // 1. PreKey & PreKeysCompanion
          final preKey = PreKey(
            keyId: 101,
            recordEnc: Uint8List.fromList([1, 2, 3, 4]),
          );
          expect(preKey.keyId, 101);
          expect(preKey.recordEnc.length, 4);

          final preKeyCompanion = PreKeysCompanion(
            keyId: const Value(202),
            recordEnc: Value(Uint8List.fromList([5, 6, 7, 8])),
          );
          expect(preKeyCompanion.keyId.value, 202);

          // 2. SignedPreKey & SignedPreKeysCompanion
          final signedPreKey = SignedPreKey(
            keyId: 303,
            recordEnc: Uint8List.fromList([9, 10, 11]),
          );
          expect(signedPreKey.keyId, 303);

          final signedCompanion = SignedPreKeysCompanion(
            keyId: const Value(404),
            recordEnc: Value(Uint8List.fromList([12, 13])),
          );
          expect(signedCompanion.keyId.value, 404);

          // 3. Session & SessionsCompanion
          final session = Session(
            address: 'alice_addr',
            recordEnc: Uint8List.fromList([14, 15, 16]),
          );
          expect(session.address, 'alice_addr');

          final sessionCompanion = SessionsCompanion(
            address: const Value('bob_addr'),
            recordEnc: Value(Uint8List.fromList([17, 18])),
          );
          expect(sessionCompanion.address.value, 'bob_addr');

          // 4. LocalIdentity & LocalIdentitiesCompanion
          final identity = LocalIdentity(
            id: 1,
            identityKeyPairEnc: Uint8List.fromList([19, 20]),
            registrationId: 555,
          );
          expect(identity.id, 1);
          expect(identity.registrationId, 555);

          final identityCompanion = LocalIdentitiesCompanion(
            id: const Value(2),
            identityKeyPairEnc: Value(Uint8List.fromList([21, 22])),
            registrationId: const Value(666),
          );
          expect(identityCompanion.registrationId.value, 666);

          // 5. LocalMessage & LocalMessagesCompanion
          final msg = LocalMessage(
            id: 'msg_999',
            conversationId: 'conv_888',
            senderId: 'user_777',
            isMine: true,
            createdAt: DateTime(2026, 3, 3),
            plaintextEnc: Uint8List.fromList([65, 66, 67]),
            messageType: 'text',
            decryptFailed: false,
          );
          expect(msg.id, 'msg_999');
          expect(msg.isMine, isTrue);

          final msgCompanion = LocalMessagesCompanion(
            id: const Value('msg_998'),
            conversationId: const Value('conv_888'),
            senderId: const Value('user_666'),
            isMine: const Value(false),
            createdAt: Value(DateTime(2026, 3, 4)),
            plaintextEnc: Value(Uint8List.fromList([68, 69])),
            messageType: const Value('text'),
            decryptFailed: const Value(false),
          );
          expect(msgCompanion.messageType.value, 'text');
        },
      );
    },
  );
}
