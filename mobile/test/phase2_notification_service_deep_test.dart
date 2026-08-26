import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/security_signal/services/notification_service.dart';
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

  group('NotificationService Unit Tests', () {
    test('cleanStaleNotificationAvatars executes without throwing', () async {
      await NotificationService.cleanStaleNotificationAvatars();
    });

    test(
      'clearNotificationsForConversation executes without throwing',
      () async {
        await NotificationService.clearNotificationsForConversation(
          'conv_dummy',
        );
      },
    );

    test('dispose cleans up timers and stream subscriptions safely', () async {
      await NotificationService.dispose();
    });
  });
}
