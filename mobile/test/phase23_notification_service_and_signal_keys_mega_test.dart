import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/security_signal/services/notification_service.dart';
import 'package:nexus/features/security_signal/services/signal/signal_key_service.dart';
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
        const MethodChannel('flutter_secure_screen'),
        (call) async => null,
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

  group('NotificationService & SignalKeyService Deep Mega Tests', () {
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
