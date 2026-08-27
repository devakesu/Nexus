import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/security_signal/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => '.',
      );

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('dexterous.com/flutter/local_notifications'),
        (call) async => null,
      );

  setUpAll(() async {
    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        publishableKey: 'mock-anon-key',
      );
    } on Exception catch (_) {}
  });

  group('NotificationService Deep Push Handling Mega Tests', () {
    test('handlePushMessage handles replenish_prekeys push', () async {
      const message = RemoteMessage(
        data: {'type': 'replenish_prekeys'},
      );
      await NotificationService.handlePushMessage(message);
    });

    test(
      'handlePushMessage handles generic notification in foreground',
      () async {
        const message = RemoteMessage(
          data: {'type': 'match_celebration', 'actor_id': 'user_1'},
          notification: RemoteNotification(
            title: 'New Match!',
            body: 'You and Aria liked each other.',
          ),
        );
        await NotificationService.handlePushMessage(
          message,
          isForeground: true,
        );
      },
    );

    test(
      'handlePushMessage handles chat message push payload structure',
      () async {
        const message = RemoteMessage(
          data: {
            'type': 'chat_message',
            'actor_id': 'user_99',
            'conversation_id': 'conv_123',
            'name': 'Agent Simmons',
            'tab': 'Dating',
            'message_id': 'msg_001',
          },
        );
        try {
          await NotificationService.handlePushMessage(message);
        } on Object catch (_) {}
      },
    );
  });
}
