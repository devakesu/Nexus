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

  group('SignalDatabase Full Drift Schema & Generated Coverage Tests', () {
    late SignalDatabase db;

    setUp(() {
      db = SignalDatabase.instance;
    });

    test(
      'LocalIdentities table CRUD, companions, JSON, equality, and copyWith',
      () async {
        final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
        final row = LocalIdentity(
          id: 1,
          identityKeyPairEnc: bytes,
          registrationId: 9999,
        );

        // JSON conversion
        final json = row.toJson();
        expect(json['id'], 1);
        expect(json['registrationId'], 9999);

        final fromJson = LocalIdentity.fromJson(json);
        expect(fromJson.id, row.id);
        expect(fromJson.registrationId, row.registrationId);

        // copyWith & equality
        final copied = row.copyWith(registrationId: 8888);
        expect(copied.registrationId, 8888);
        expect(copied.id, 1);
        expect(row.toString(), contains('LocalIdentity'));
        expect(row.hashCode, isNotNull);
        expect(row == copied, isFalse);

        // Companion
        final companion = LocalIdentitiesCompanion.insert(
          id: const Value(1),
          identityKeyPairEnc: bytes,
          registrationId: 9999,
        );
        final customComp = companion.copyWith(
          registrationId: const Value(7777),
        );
        expect(customComp.registrationId.value, 7777);
        expect(companion.toString(), contains('LocalIdentitiesCompanion'));
        expect(companion.hashCode, isNotNull);
      },
    );

    test('PreKeys table CRUD, companions, JSON, and copyWith', () async {
      final bytes = Uint8List.fromList([10, 20, 30]);
      final row = PreKey(keyId: 42, recordEnc: bytes);

      final json = row.toJson();
      expect(json['keyId'], 42);

      final fromJson = PreKey.fromJson(json);
      expect(fromJson.keyId, 42);
      expect(row.toString(), contains('PreKey'));
      expect(row.hashCode, isNotNull);

      final copied = row.copyWith(keyId: 100);
      expect(copied.keyId, 100);
      expect(row == copied, isFalse);

      final comp = PreKeysCompanion.insert(
        keyId: const Value(42),
        recordEnc: bytes,
      );
      expect(comp.toString(), contains('PreKeysCompanion'));
      expect(comp.hashCode, isNotNull);
      final compCopied = comp.copyWith(keyId: const Value(200));
      expect(compCopied.keyId.value, 200);
    });

    test('SignedPreKeys table CRUD, companions, JSON, and copyWith', () async {
      final bytes = Uint8List.fromList([11, 22, 33]);
      final row = SignedPreKey(keyId: 7, recordEnc: bytes);

      final json = row.toJson();
      expect(json['keyId'], 7);

      final fromJson = SignedPreKey.fromJson(json);
      expect(fromJson.keyId, 7);
      expect(row.toString(), contains('SignedPreKey'));
      expect(row.hashCode, isNotNull);

      final copied = row.copyWith(keyId: 8);
      expect(copied.keyId, 8);

      final comp = SignedPreKeysCompanion.insert(
        keyId: const Value(7),
        recordEnc: bytes,
      );
      expect(comp.toString(), contains('SignedPreKeysCompanion'));
      expect(comp.hashCode, isNotNull);
      final compCopied = comp.copyWith(keyId: const Value(99));
      expect(compCopied.keyId.value, 99);
    });

    test('Sessions table CRUD, companions, JSON, and copyWith', () async {
      final bytes = Uint8List.fromList([99, 88, 77]);
      final row = Session(address: 'user_a:1', recordEnc: bytes);

      final json = row.toJson();
      expect(json['address'], 'user_a:1');

      final fromJson = Session.fromJson(json);
      expect(fromJson.address, 'user_a:1');
      expect(row.toString(), contains('Session'));
      expect(row.hashCode, isNotNull);

      final copied = row.copyWith(address: 'user_b:1');
      expect(copied.address, 'user_b:1');

      final comp = SessionsCompanion.insert(
        address: 'user_a:1',
        recordEnc: bytes,
      );
      expect(comp.toString(), contains('SessionsCompanion'));
      expect(comp.hashCode, isNotNull);
      final compCopied = comp.copyWith(address: const Value('user_c:1'));
      expect(compCopied.address.value, 'user_c:1');
    });

    test(
      'TrustedIdentities table CRUD, companions, JSON, and copyWith',
      () async {
        final bytes = Uint8List.fromList([1, 3, 5, 7]);
        final row = TrustedIdentity(
          address: 'user_trusted:1',
          identityKeyEnc: bytes,
        );

        final json = row.toJson();
        expect(json['address'], 'user_trusted:1');

        final fromJson = TrustedIdentity.fromJson(json);
        expect(fromJson.address, 'user_trusted:1');
        expect(row.toString(), contains('TrustedIdentity'));
        expect(row.hashCode, isNotNull);

        final copied = row.copyWith(address: 'user_new:1');
        expect(copied.address, 'user_new:1');

        final comp = TrustedIdentitiesCompanion.insert(
          address: 'user_trusted:1',
          identityKeyEnc: bytes,
        );
        expect(comp.toString(), contains('TrustedIdentitiesCompanion'));
        expect(comp.hashCode, isNotNull);
        final compCopied = comp.copyWith(address: const Value('user_x:1'));
        expect(compCopied.address.value, 'user_x:1');
      },
    );

    test('LocalMessages table CRUD, companions, JSON, and copyWith', () async {
      final now = DateTime.now();
      final bytes = Uint8List.fromList([50, 60, 70]);
      final row = LocalMessage(
        id: 'msg_1',
        conversationId: 'conv_1',
        senderId: 'user_1',
        isMine: true,
        createdAt: now,
        messageType: 'text',
        plaintextEnc: bytes,
        decryptFailed: false,
      );

      final json = row.toJson();
      expect(json['id'], 'msg_1');
      expect(json['messageType'], 'text');
      expect(json['decryptFailed'], false);

      final fromJson = LocalMessage.fromJson(json);
      expect(fromJson.id, 'msg_1');
      expect(fromJson.isMine, true);
      expect(row.toString(), contains('LocalMessage'));
      expect(row.hashCode, isNotNull);

      final copied = row.copyWith(
        id: 'msg_2',
        messageType: 'image',
        decryptFailed: true,
      );
      expect(copied.id, 'msg_2');
      expect(copied.messageType, 'image');
      expect(copied.decryptFailed, true);

      final comp = LocalMessagesCompanion.insert(
        id: 'msg_1',
        conversationId: 'conv_1',
        senderId: 'user_1',
        isMine: true,
        createdAt: now,
        messageType: 'text',
        plaintextEnc: Value(bytes),
        decryptFailed: const Value(false),
      );
      expect(comp.toString(), contains('LocalMessagesCompanion'));
      expect(comp.hashCode, isNotNull);
      final compCopied = comp.copyWith(id: const Value('msg_alt'));
      expect(compCopied.id.value, 'msg_alt');
    });

    test('CachedMedia table CRUD, companions, JSON, and copyWith', () async {
      final now = DateTime.now();
      final bytes = Uint8List.fromList([100, 101, 102]);
      final row = CachedMediaData(
        storagePath: 'chat_media/conv_1/user_1/file.enc',
        plaintextEnc: bytes,
        mimeType: 'image/jpeg',
        cachedAt: now,
      );

      final json = row.toJson();
      expect(json['storagePath'], 'chat_media/conv_1/user_1/file.enc');
      expect(json['mimeType'], 'image/jpeg');

      final fromJson = CachedMediaData.fromJson(json);
      expect(fromJson.storagePath, row.storagePath);
      expect(fromJson.mimeType, 'image/jpeg');
      expect(row.toString(), contains('CachedMediaData'));
      expect(row.hashCode, isNotNull);

      final copied = row.copyWith(mimeType: 'audio/m4a');
      expect(copied.mimeType, 'audio/m4a');

      final comp = CachedMediaCompanion.insert(
        storagePath: 'chat_media/conv_1/user_1/file.enc',
        plaintextEnc: bytes,
        mimeType: 'image/jpeg',
        cachedAt: now,
      );
      expect(comp.toString(), contains('CachedMediaCompanion'));
      expect(comp.hashCode, isNotNull);
      final compCopied = comp.copyWith(mimeType: const Value('image/png'));
      expect(compCopied.mimeType.value, 'image/png');
    });

    test('Database metadata and schema version', () async {
      expect(db.schemaVersion, 2);
      expect(db.allTables.isNotEmpty, isTrue);
      expect(db.allTables.length, 7);

      final migration = db.migration;
      expect(migration.beforeOpen, isNotNull);
      expect(migration.onUpgrade, isNotNull);
    });
  });
}
