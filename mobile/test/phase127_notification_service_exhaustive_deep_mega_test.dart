import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/security_signal/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'helpers/mock_network_interceptor.dart';

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
        const MethodChannel('dexterous.com/flutter/local_notifications'),
        (call) async => true,
      );

  setUpAll(() async {
    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        publishableKey: 'mock-anon-key',
      );
    } on Exception catch (_) {}
    setupGlobalMockNetwork();
  });

  group('Phase 127 - Notification Service Exhaustive Mega Tests', () {
    test(
      'NotificationService handles chat, match, and safety push messages',
      () async {
        // 1. Safety Alert Push
        const safetyMsg = RemoteMessage(
          messageId: 'fcm_001',
          data: {
            'type': 'safety_alert',
            'alert_id': 'alt_999',
            'sender_name': 'Emergency Contact',
          },
        );
        await NotificationService.handlePushMessage(safetyMsg);

        // 2. New Match Push
        const matchMsg = RemoteMessage(
          messageId: 'fcm_002',
          data: {
            'type': 'match',
            'match_id': 'm_888',
            'sender_name': 'Taylor',
            'tab': 'dating',
          },
        );
        await NotificationService.handlePushMessage(matchMsg);

        // 3. New Message Push
        const chatMsg = RemoteMessage(
          messageId: 'fcm_003',
          data: {
            'type': 'new_message',
            'conversation_id': 'c_777',
            'sender_id': '00000000-0000-0000-0000-000000000002',
            'sender_name': 'Jordan',
            'ciphertext': 'abc123ciphertext',
            'message_type': 'text',
          },
        );
        await NotificationService.handlePushMessage(chatMsg);
      },
    );
  });
}
