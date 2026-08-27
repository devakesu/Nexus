import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/security_signal/services/signal/signal_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => '.',
      );

  group('Signal Database Generated Exhaustive Mega Tests', () {
    late SignalDatabase db;

    setUp(() {
      db = SignalDatabase.instance;
    });

    test('Table Managers and Database Queries Execution', () {
      final managers = $SignalDatabaseManager(db);

      expect(managers.localIdentities, isNotNull);
      expect(managers.preKeys, isNotNull);
      expect(managers.signedPreKeys, isNotNull);
      expect(managers.sessions, isNotNull);
      expect(managers.trustedIdentities, isNotNull);
      expect(managers.localMessages, isNotNull);
      expect(managers.cachedMedia, isNotNull);
    });

    test('Validate Integrity and copyWithCompanion for all models', () {
      // LocalIdentitiesTable validateIntegrity
      final tableIdentities = db.localIdentities;
      final compIdentity = LocalIdentitiesCompanion(
        id: const Value(1),
        identityKeyPairEnc: Value(Uint8List.fromList([1])),
        registrationId: const Value(10),
      );
      final ctx1 = tableIdentities.validateIntegrity(
        compIdentity,
        isInserting: true,
      );
      expect(ctx1.dataValid, isTrue);

      // PreKeysTable validateIntegrity
      final tablePreKeys = db.preKeys;
      final compPreKey = PreKeysCompanion(
        keyId: const Value(2),
        recordEnc: Value(Uint8List.fromList([2])),
      );
      final ctx2 = tablePreKeys.validateIntegrity(
        compPreKey,
        isInserting: true,
      );
      expect(ctx2.dataValid, isTrue);

      // SignedPreKeysTable validateIntegrity
      final tableSignedPreKeys = db.signedPreKeys;
      final compSignedPreKey = SignedPreKeysCompanion(
        keyId: const Value(3),
        recordEnc: Value(Uint8List.fromList([3])),
      );
      final ctx3 = tableSignedPreKeys.validateIntegrity(
        compSignedPreKey,
        isInserting: true,
      );
      expect(ctx3.dataValid, isTrue);

      // SessionsTable validateIntegrity
      final tableSessions = db.sessions;
      final compSession = SessionsCompanion(
        address: const Value('u:1'),
        recordEnc: Value(Uint8List.fromList([4])),
      );
      final ctx4 = tableSessions.validateIntegrity(
        compSession,
        isInserting: true,
      );
      expect(ctx4.dataValid, isTrue);

      // TrustedIdentitiesTable validateIntegrity
      final tableTrust = db.trustedIdentities;
      final compTrust = TrustedIdentitiesCompanion(
        address: const Value('u:1'),
        identityKeyEnc: Value(Uint8List.fromList([5])),
      );
      final ctx5 = tableTrust.validateIntegrity(compTrust, isInserting: true);
      expect(ctx5.dataValid, isTrue);

      // LocalMessagesTable validateIntegrity
      final tableMessages = db.localMessages;
      final compMsg = LocalMessagesCompanion(
        id: const Value('m1'),
        conversationId: const Value('c1'),
        senderId: const Value('s1'),
        isMine: const Value(true),
        createdAt: Value(DateTime.now()),
        messageType: const Value('text'),
        plaintextEnc: Value(Uint8List.fromList([6])),
        decryptFailed: const Value(false),
      );
      final ctx6 = tableMessages.validateIntegrity(compMsg, isInserting: true);
      expect(ctx6.dataValid, isTrue);

      // CachedMediaTable validateIntegrity
      final tableMedia = db.cachedMedia;
      final compMedia = CachedMediaCompanion(
        storagePath: const Value('/tmp/1.png'),
        mimeType: const Value('image/png'),
        plaintextEnc: Value(Uint8List.fromList([7])),
        cachedAt: Value(DateTime.now()),
      );
      final ctx7 = tableMedia.validateIntegrity(compMedia, isInserting: true);
      expect(ctx7.dataValid, isTrue);

      // copyWithCompanion tests
      final msg = LocalMessage(
        id: 'm1',
        conversationId: 'c1',
        senderId: 's1',
        isMine: true,
        createdAt: DateTime.now(),
        messageType: 'text',
        plaintextEnc: Uint8List.fromList([1, 2]),
        decryptFailed: false,
      );
      final updatedMsg = msg.copyWithCompanion(
        const LocalMessagesCompanion(
          messageType: Value('image'),
          decryptFailed: Value(true),
        ),
      );
      expect(updatedMsg.messageType, 'image');
      expect(updatedMsg.decryptFailed, isTrue);

      final media = CachedMediaData(
        storagePath: '/tmp/1.png',
        mimeType: 'image/png',
        plaintextEnc: Uint8List.fromList([7]),
        cachedAt: DateTime.now(),
      );
      final updatedMedia = media.copyWithCompanion(
        const CachedMediaCompanion(
          mimeType: Value('image/jpeg'),
        ),
      );
      expect(updatedMedia.mimeType, 'image/jpeg');

      final identity = LocalIdentity(
        id: 1,
        identityKeyPairEnc: Uint8List.fromList([1]),
        registrationId: 10,
      );
      final updatedIdentity = identity.copyWithCompanion(
        const LocalIdentitiesCompanion(
          registrationId: Value(20),
        ),
      );
      expect(updatedIdentity.registrationId, 20);

      final pk = PreKey(
        keyId: 1,
        recordEnc: Uint8List.fromList([1]),
      );
      final updatedPk = pk.copyWithCompanion(
        const PreKeysCompanion(
          keyId: Value(2),
        ),
      );
      expect(updatedPk.keyId, 2);

      final spk = SignedPreKey(
        keyId: 1,
        recordEnc: Uint8List.fromList([1]),
      );
      final updatedSpk = spk.copyWithCompanion(
        const SignedPreKeysCompanion(
          keyId: Value(2),
        ),
      );
      expect(updatedSpk.keyId, 2);

      final sess = Session(
        address: 'u:1',
        recordEnc: Uint8List.fromList([1]),
      );
      final updatedSess = sess.copyWithCompanion(
        const SessionsCompanion(
          address: Value('u:2'),
        ),
      );
      expect(updatedSess.address, 'u:2');

      final trust = TrustedIdentity(
        address: 'u:1',
        identityKeyEnc: Uint8List.fromList([1]),
      );
      final updatedTrust = trust.copyWithCompanion(
        const TrustedIdentitiesCompanion(
          address: Value('u:2'),
        ),
      );
      expect(updatedTrust.address, 'u:2');
    });
  });
}
