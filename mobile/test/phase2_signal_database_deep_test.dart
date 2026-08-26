import 'package:drift/drift.dart' hide isNotNull;
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

  group('SignalDatabase Entity and Table Operations Tests', () {
    test('exposes tables and schema configuration', () {
      final db = SignalDatabase.instance;
      expect(db.schemaVersion, 2);
      expect(db.allTables.isNotEmpty, true);
      expect(db.localIdentities, isNotNull);
      expect(db.preKeys, isNotNull);
      expect(db.signedPreKeys, isNotNull);
      expect(db.sessions, isNotNull);
      expect(db.trustedIdentities, isNotNull);
      expect(db.localMessages, isNotNull);
      expect(db.cachedMedia, isNotNull);
    });

    test('table companions construct accurately', () {
      final identityComp = LocalIdentitiesCompanion.insert(
        id: const Value(1),
        identityKeyPairEnc: Uint8List.fromList([1, 2, 3, 4]),
        registrationId: 12345,
      );
      expect(identityComp.registrationId.value, 12345);

      final preKeyComp = PreKeysCompanion.insert(
        keyId: const Value(10),
        recordEnc: Uint8List.fromList([5, 6, 7, 8]),
      );
      expect(preKeyComp.keyId.value, 10);

      final signedPreKeyComp = SignedPreKeysCompanion.insert(
        keyId: const Value(20),
        recordEnc: Uint8List.fromList([9, 10, 11]),
      );
      expect(signedPreKeyComp.keyId.value, 20);

      final sessionComp = SessionsCompanion.insert(
        address: 'user_bob:1',
        recordEnc: Uint8List.fromList([12, 13, 14]),
      );
      expect(sessionComp.address.value, 'user_bob:1');

      final localMsgComp = LocalMessagesCompanion.insert(
        id: 'msg_test_1',
        conversationId: 'conv_123',
        senderId: 'user_alice',
        isMine: true,
        createdAt: DateTime(2026, 8, 26),
        messageType: 'text',
        plaintextEnc: Value(Uint8List.fromList([15, 16, 17])),
      );
      expect(localMsgComp.id.value, 'msg_test_1');

      final cachedMediaComp = CachedMediaCompanion.insert(
        storagePath: 'chat_media/img.jpg',
        plaintextEnc: Uint8List.fromList([18, 19, 20]),
        mimeType: 'image/jpeg',
        cachedAt: DateTime(2026, 8, 26),
      );
      expect(cachedMediaComp.storagePath.value, 'chat_media/img.jpg');
    });
  });
}
