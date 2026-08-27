import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/features/security_signal/services/notification_service.dart';
import 'package:nexus/features/security_signal/services/signal/local_key_vault.dart';
import 'package:nexus/features/security_signal/services/signal/message_codec.dart';
import 'package:nexus/features/security_signal/services/signal/session_manager.dart';
import 'package:nexus/features/security_signal/services/signal/signal_database.dart';
import 'package:nexus/features/security_signal/services/signal/signal_key_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Headers, Session;

import '../../helpers/test_helpers.dart';

void main() {
  setUpTestEnvironment();

  setUpAll(() async {
    await initMockSupabase();
  });

  // --- Section 1 ---
  {
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

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dexterous.com/flutter/local_notifications'),
          (call) async => null,
        );

    group('NotificationService & SignalKeyService Deep Tests', () {
      test('NotificationService handles match push message cleanly', () async {
        const message = RemoteMessage(
          data: {
            'type': 'match',
            'actor_name': 'Sophia',
            'title': 'New Match!',
            'body': 'You and Sophia liked each other.',
            'conversation_id': 'conv_match_1',
          },
        );

        // Should run without throwing
        await NotificationService.handlePushMessage(message);
      });

      test(
        'NotificationService handles safety alert push message cleanly',
        () async {
          const message = RemoteMessage(
            data: {
              'type': 'safety_alert',
              'actor_name': 'Alex',
              'title': 'Safety Alert Triggered',
              'body': 'Your emergency contact has triggered an alert.',
              'alert_id': 'alert_99',
            },
          );

          await NotificationService.handlePushMessage(message);
        },
      );

      test(
        'NotificationService handles generic system push message cleanly',
        () async {
          const message = RemoteMessage(
            data: {
              'type': 'system',
              'title': 'Nexus Update',
              'body': 'New features are now live.',
            },
          );

          await NotificationService.handlePushMessage(message);
        },
      );

      test(
        'SignalKeyService handles background bootstrap without throwing',
        () async {
          final service = SignalKeyService.instance;
          expect(service.isNewLocalIdentity, isA<bool>());

          // Should complete gracefully without crashing
          await service.ensureBootstrappedInBackground();
        },
      );
    });
  }

  // --- Section 2 ---
  {
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

    group('Signal Keys and Session Manager Tests', () {
      test(
        'SignalKeyService and SessionManager singleton instances and constants',
        () {
          expect(kSignalDeviceId, 1);
          final keyService = SignalKeyService.instance;
          expect(keyService.isNewLocalIdentity, isA<bool>());

          final sessionManager = SessionManager.instance;
          expect(sessionManager, isNotNull);

          final db = SignalDatabase.instance;
          expect(db.schemaVersion, 2);
        },
      );
    });
  }

  // --- Section 3 ---
  {
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

    group('Security Signal Keys and Database Deep Tests', () {
      test('LocalKeyVault encrypts, decrypts, and wipes', () async {
        final vault = LocalKeyVault.instance;
        final raw = Uint8List.fromList(
          utf8.encode('Top Secret Signal Payload'),
        );
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
}
