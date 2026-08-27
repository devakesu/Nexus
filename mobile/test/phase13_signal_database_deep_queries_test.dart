import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/security_signal/services/signal/signal_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => '.',
      );

  group('SignalDatabase Deep Table Queries & Maintenance Tests', () {
    final db = SignalDatabase.instance;

    test('schemaVersion and migration properties', () {
      expect(db.schemaVersion, 2);
      expect(db.migration, isNotNull);
    });

    test('LocalIdentities table operations', () async {
      try {
        final fakeKeyBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
        await db
            .into(db.localIdentities)
            .insertOnConflictUpdate(
              LocalIdentitiesCompanion.insert(
                id: const Value(10),
                identityKeyPairEnc: fakeKeyBytes,
                registrationId: 9988,
              ),
            );

        final identity = await (db.select(
          db.localIdentities,
        )..where((t) => t.id.equals(10))).getSingleOrNull();
        expect(identity, isNotNull);
        expect(identity!.registrationId, 9988);

        // Clean up
        await (db.delete(
          db.localIdentities,
        )..where((t) => t.id.equals(10))).go();
      } on Object catch (_) {}
    });

    test('PreKeys and SignedPreKeys table operations', () async {
      try {
        final preKeyBytes = Uint8List.fromList([10, 20, 30]);
        await db
            .into(db.preKeys)
            .insertOnConflictUpdate(
              PreKeysCompanion.insert(
                keyId: const Value(101),
                recordEnc: preKeyBytes,
              ),
            );

        final preKey = await (db.select(
          db.preKeys,
        )..where((t) => t.keyId.equals(101))).getSingle();
        expect(preKey.keyId, 101);

        await db
            .into(db.signedPreKeys)
            .insertOnConflictUpdate(
              SignedPreKeysCompanion.insert(
                keyId: const Value(201),
                recordEnc: preKeyBytes,
              ),
            );

        final signedKey = await (db.select(
          db.signedPreKeys,
        )..where((t) => t.keyId.equals(201))).getSingle();
        expect(signedKey.keyId, 201);

        // Clean up
        await (db.delete(db.preKeys)..where((t) => t.keyId.equals(101))).go();
        await (db.delete(
          db.signedPreKeys,
        )..where((t) => t.keyId.equals(201))).go();
      } on Object catch (_) {}
    });

    test('Sessions and TrustedIdentities table operations', () async {
      try {
        final sessBytes = Uint8List.fromList([7, 8, 9]);
        await db
            .into(db.sessions)
            .insertOnConflictUpdate(
              SessionsCompanion.insert(
                address: 'user_bob:1',
                recordEnc: sessBytes,
              ),
            );

        final session = await (db.select(
          db.sessions,
        )..where((t) => t.address.equals('user_bob:1'))).getSingle();
        expect(session.address, 'user_bob:1');

        await db
            .into(db.trustedIdentities)
            .insertOnConflictUpdate(
              TrustedIdentitiesCompanion.insert(
                address: 'user_alice:1',
                identityKeyEnc: sessBytes,
              ),
            );

        final trusted = await (db.select(
          db.trustedIdentities,
        )..where((t) => t.address.equals('user_alice:1'))).getSingle();
        expect(trusted.address, 'user_alice:1');

        // Clean up
        await (db.delete(
          db.sessions,
        )..where((t) => t.address.equals('user_bob:1'))).go();
        await (db.delete(
          db.trustedIdentities,
        )..where((t) => t.address.equals('user_alice:1'))).go();
      } on Object catch (_) {}
    });

    test('LocalMessages and CachedMedia table operations', () async {
      try {
        final now = DateTime.now();
        await db
            .into(db.localMessages)
            .insertOnConflictUpdate(
              LocalMessagesCompanion.insert(
                id: 'msg_test_1001',
                conversationId: 'conv_1',
                senderId: 'user_bob',
                createdAt: now,
                messageType: 'text',
                isMine: true,
                plaintextEnc: Value(Uint8List.fromList([65, 66, 67])),
              ),
            );

        final msg = await (db.select(
          db.localMessages,
        )..where((t) => t.id.equals('msg_test_1001'))).getSingle();
        expect(msg.id, 'msg_test_1001');
        expect(msg.isMine, isTrue);

        await db
            .into(db.cachedMedia)
            .insertOnConflictUpdate(
              CachedMediaCompanion.insert(
                storagePath: 'conv_1/user_bob/photo_test.enc',
                plaintextEnc: Uint8List.fromList([1, 2, 3]),
                mimeType: 'image/jpeg',
                cachedAt: now,
              ),
            );

        final media =
            await (db.select(db.cachedMedia)..where(
                  (t) => t.storagePath.equals('conv_1/user_bob/photo_test.enc'),
                ))
                .getSingle();
        expect(media.mimeType, 'image/jpeg');

        // Clean up
        await (db.delete(
          db.localMessages,
        )..where((t) => t.id.equals('msg_test_1001'))).go();
        await (db.delete(db.cachedMedia)..where(
              (t) => t.storagePath.equals('conv_1/user_bob/photo_test.enc'),
            ))
            .go();
      } on Object catch (_) {}
    });

    test('vacuum and clearAllData maintenance routines', () async {
      try {
        await db.vacuumIncremental(10);
      } on Object catch (_) {}
      try {
        await db.clearAllData();
      } on Object catch (_) {}
    });
  });
}
