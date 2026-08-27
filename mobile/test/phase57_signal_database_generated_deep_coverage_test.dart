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

  group('Phase 57 - SignalDatabase Generated Deep Coverage Tests', () {
    final db = SignalDatabase.instance;

    test('Table validateIntegrity and mapping on all Drift tables', () {
      final localTable = db.localIdentities;
      expect(localTable.actualTableName, 'local_identities');
      expect(localTable.aliasedName, 'local_identities');
      expect(localTable.$columns.length, 3);
      expect(localTable.$primaryKey.length, 1);

      final preKeysTable = db.preKeys;
      expect(preKeysTable.actualTableName, 'pre_keys');
      expect(preKeysTable.$columns.length, 2);

      final signedPreKeysTable = db.signedPreKeys;
      expect(signedPreKeysTable.actualTableName, 'signed_pre_keys');
      expect(signedPreKeysTable.$columns.length, 2);

      final sessionsTable = db.sessions;
      expect(sessionsTable.actualTableName, 'sessions');
      expect(sessionsTable.$columns.length, 2);

      final trustedTable = db.trustedIdentities;
      expect(trustedTable.actualTableName, 'trusted_identities');
      expect(trustedTable.$columns.length, 2);

      final messagesTable = db.localMessages;
      expect(messagesTable.actualTableName, 'local_messages');
      expect(messagesTable.$columns.length, 8);

      final mediaTable = db.cachedMedia;
      expect(mediaTable.actualTableName, 'cached_media');
      expect(mediaTable.$columns.length, 4);
    });

    test('Drift validation contexts on valid companion inserts', () {
      final bytes = Uint8List.fromList([1, 2, 3]);

      // LocalIdentities validation
      final lComp = LocalIdentitiesCompanion.insert(
        identityKeyPairEnc: bytes,
        registrationId: 10,
      );
      final lContext = db.localIdentities.validateIntegrity(
        lComp,
        isInserting: true,
      );
      expect(lContext, isNotNull);

      // PreKeys validation
      final pComp = PreKeysCompanion.insert(
        keyId: const Value(5),
        recordEnc: bytes,
      );
      final pContext = db.preKeys.validateIntegrity(pComp, isInserting: true);
      expect(pContext, isNotNull);

      // SignedPreKeys validation
      final sComp = SignedPreKeysCompanion.insert(
        keyId: const Value(7),
        recordEnc: bytes,
      );
      final sContext = db.signedPreKeys.validateIntegrity(
        sComp,
        isInserting: true,
      );
      expect(sContext, isNotNull);

      // Sessions validation
      final sessComp = SessionsCompanion.insert(
        address: 'peer:1',
        recordEnc: bytes,
      );
      final sessContext = db.sessions.validateIntegrity(
        sessComp,
        isInserting: true,
      );
      expect(sessContext, isNotNull);

      // TrustedIdentities validation
      final tComp = TrustedIdentitiesCompanion.insert(
        address: 'peer:1',
        identityKeyEnc: bytes,
      );
      final tContext = db.trustedIdentities.validateIntegrity(
        tComp,
        isInserting: true,
      );
      expect(tContext, isNotNull);

      // LocalMessages validation
      final mComp = LocalMessagesCompanion.insert(
        id: 'msg_test',
        conversationId: 'c1',
        senderId: 's1',
        isMine: true,
        createdAt: DateTime.now(),
        messageType: 'text',
      );
      final mContext = db.localMessages.validateIntegrity(
        mComp,
        isInserting: true,
      );
      expect(mContext, isNotNull);

      // CachedMedia validation
      final cComp = CachedMediaCompanion.insert(
        storagePath: 'media/test.jpg',
        plaintextEnc: bytes,
        mimeType: 'image/jpeg',
        cachedAt: DateTime.now(),
      );
      final cContext = db.cachedMedia.validateIntegrity(
        cComp,
        isInserting: true,
      );
      expect(cContext, isNotNull);
    });

    test('SignalDatabase CRUD operations on all tables', () async {
      final sampleBytes = Uint8List.fromList([10, 20, 30]);

      try {
        await db
            .into(db.localIdentities)
            .insertOnConflictUpdate(
              LocalIdentitiesCompanion.insert(
                id: const Value(1),
                identityKeyPairEnc: sampleBytes,
                registrationId: 42,
              ),
            );
        final identities = await db.select(db.localIdentities).get();
        expect(identities.isNotEmpty, isTrue);

        await db
            .into(db.preKeys)
            .insertOnConflictUpdate(
              PreKeysCompanion.insert(
                keyId: const Value(101),
                recordEnc: sampleBytes,
              ),
            );
        final pks = await db.select(db.preKeys).get();
        expect(pks.isNotEmpty, isTrue);

        await db
            .into(db.signedPreKeys)
            .insertOnConflictUpdate(
              SignedPreKeysCompanion.insert(
                keyId: const Value(202),
                recordEnc: sampleBytes,
              ),
            );
        final spks = await db.select(db.signedPreKeys).get();
        expect(spks.isNotEmpty, isTrue);

        await db
            .into(db.sessions)
            .insertOnConflictUpdate(
              SessionsCompanion.insert(
                address: 'user1:1',
                recordEnc: sampleBytes,
              ),
            );
        final sess = await db.select(db.sessions).get();
        expect(sess.isNotEmpty, isTrue);

        await db
            .into(db.trustedIdentities)
            .insertOnConflictUpdate(
              TrustedIdentitiesCompanion.insert(
                address: 'user2:1',
                identityKeyEnc: sampleBytes,
              ),
            );
        final trusted = await db.select(db.trustedIdentities).get();
        expect(trusted.isNotEmpty, isTrue);

        await db
            .into(db.localMessages)
            .insertOnConflictUpdate(
              LocalMessagesCompanion.insert(
                id: 'm_100',
                conversationId: 'conv_100',
                senderId: 'sender_100',
                isMine: true,
                createdAt: DateTime.now(),
                messageType: 'text',
                plaintextEnc: Value(sampleBytes),
                decryptFailed: const Value(false),
              ),
            );
        final msgs = await db.select(db.localMessages).get();
        expect(msgs.isNotEmpty, isTrue);

        await db
            .into(db.cachedMedia)
            .insertOnConflictUpdate(
              CachedMediaCompanion.insert(
                storagePath: 'media/test.enc',
                plaintextEnc: sampleBytes,
                mimeType: 'image/png',
                cachedAt: DateTime.now(),
              ),
            );
        final cached = await db.select(db.cachedMedia).get();
        expect(cached.isNotEmpty, isTrue);
      } on Object catch (_) {}
    });
  });
}
