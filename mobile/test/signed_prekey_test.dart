import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:nexus/features/security_signal/services/signal/signal_database.dart';
import 'package:nexus/features/security_signal/services/signal/signal_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => '.',
      );

  group('Signed PreKey Storage & Pruning', () {
    late SignalDatabase db;
    late DriftSignalProtocolStore store;
    late IdentityKeyPair identityKeyPair;

    setUp(() {
      identityKeyPair = generateIdentityKeyPair();
      db = SignalDatabase.instance;
      store = DriftSignalProtocolStore(db, identityKeyPair, 1234);
    });

    test('stores multiple signed prekeys and prunes older keys', () async {
      final preKey1 = generateSignedPreKey(identityKeyPair, 1);
      final preKey2 = generateSignedPreKey(identityKeyPair, 2);
      final preKey3 = generateSignedPreKey(identityKeyPair, 3);

      await store.storeSignedPreKey(1, preKey1);
      await store.storeSignedPreKey(2, preKey2);
      await store.storeSignedPreKey(3, preKey3);

      var keys = await store.loadSignedPreKeys();
      expect(keys.length, equals(3));

      // Simulate pruning all except key 3
      const confirmedId = 3;
      for (final key in keys) {
        if (key.id != confirmedId) {
          await store.removeSignedPreKey(key.id);
        }
      }

      keys = await store.loadSignedPreKeys();
      expect(keys.length, equals(1));
      expect(keys.first.id, equals(3));

      // Cleanup
      await store.removeSignedPreKey(3);
    });
  });
}
