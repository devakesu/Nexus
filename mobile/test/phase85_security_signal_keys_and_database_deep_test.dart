import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/features/security_signal/services/signal/local_key_vault.dart';
import 'package:nexus/features/security_signal/services/signal/message_codec.dart';
import 'package:nexus/features/security_signal/services/signal/signal_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final mockSessionJson = jsonEncode({
    'access_token': 'mock-access-token-12345',
    'refresh_token': 'mock-refresh-token-12345',
    'expires_in': 3600,
    'expires_at': 1893456000,
    'token_type': 'bearer',
    'user': {
      'id': '00000000-0000-0000-0000-000000000001',
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': 'user@nexus.test',
      'phone': '+14155552671',
      'app_metadata': <String, dynamic>{},
      'user_metadata': <String, dynamic>{},
      'created_at': '2026-01-01T00:00:00.000Z',
      'updated_at': '2026-01-01T00:00:00.000Z',
    },
  });

  SharedPreferences.setMockInitialValues({
    'sb-mock-auth-token': mockSessionJson,
  });
  FlutterSecureStorage.setMockInitialValues({});

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => '.',
      );

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('flutter_secure_screen'),
        (call) async => null,
      );

  setUpAll(() async {
    ConsentCacheManager.safetyConsentGranted = true;
    ConsentCacheManager.specialCategoryConsentGranted = true;
    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        publishableKey: 'mock-anon-key',
      );
    } on Exception catch (_) {}
  });

  group('Phase 85 - Security Signal Keys and Database Deep Tests', () {
    test('LocalKeyVault encrypts, decrypts, and wipes', () async {
      final vault = LocalKeyVault.instance;
      final raw = Uint8List.fromList(utf8.encode('Top Secret Signal Payload'));
      final encrypted = await vault.encryptBytes(raw);
      expect(encrypted, isNot(raw));

      final decrypted = await vault.decryptBytes(encrypted);
      expect(utf8.decode(decrypted), 'Top Secret Signal Payload');

      await vault.wipeKeys();
    });

    test(
      'EncryptedEnvelope and SignalCryptoLock execute synchronized',
      () async {
        const envelope = EncryptedEnvelope(
          ciphertextBase64: 'bW9jay1jaXBoZXJ0ZXh0',
          signalMessageType: 'whisper',
        );
        expect(envelope.signalMessageType, 'whisper');
        expect(envelope.ciphertextBase64, 'bW9jay1jaXBoZXJ0ZXh0');

        final result = await SignalCryptoLock.synchronized(() async {
          return 42;
        });
        expect(result, 42);
      },
    );

    test('SignalDatabase instance check', () {
      final db = SignalDatabase.instance;
      expect(db.schemaVersion, 2);
    });
  });
}
