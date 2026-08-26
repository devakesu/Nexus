import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/security_signal/services/security_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  const channel = MethodChannel('com.devakesu.apps.nexus/security');
  final methodCalls = <MethodCall>[];

  setUp(() {
    methodCalls.clear();
    SecurityService.resetSensitiveScreenCountForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          methodCalls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('SecurityService Lifecycle & Sensitive Screen Management', () {
    test('enterSensitiveScreen sets FLAG_SECURE and tracks count', () async {
      expect(SecurityService.isSensitiveScreenActive, isFalse);
      expect(SecurityService.sensitiveScreenCount, 0);

      await SecurityService.enterSensitiveScreen();
      expect(SecurityService.isSensitiveScreenActive, isTrue);
      expect(SecurityService.sensitiveScreenCount, 1);
      expect(methodCalls.last.method, 'setSecureFlag');
      expect(methodCalls.last.arguments, {'secure': true});

      // Nested sensitive screen
      await SecurityService.enterSensitiveScreen();
      expect(SecurityService.sensitiveScreenCount, 2);
      expect(SecurityService.isSensitiveScreenActive, isTrue);

      // Exit first sensitive screen - should still remain secure
      await SecurityService.exitSensitiveScreen();
      expect(SecurityService.sensitiveScreenCount, 1);
      expect(SecurityService.isSensitiveScreenActive, isTrue);

      // Exit second sensitive screen - should now clear secure flag
      await SecurityService.exitSensitiveScreen();
      expect(SecurityService.sensitiveScreenCount, 0);
      expect(SecurityService.isSensitiveScreenActive, isFalse);
      expect(methodCalls.last.arguments, {'secure': false});
    });

    test(
      'handleAppLifecycleState handles inactive, paused, and resumed states',
      () async {
        expect(SecurityService.isSensitiveScreenActive, isFalse);

        await SecurityService.handleAppLifecycleState(
          AppLifecycleState.inactive,
        );
        expect(methodCalls.last.arguments, {'secure': true});

        await SecurityService.handleAppLifecycleState(
          AppLifecycleState.resumed,
        );
        expect(methodCalls.last.arguments, {'secure': false});

        await SecurityService.enterSensitiveScreen();
        expect(methodCalls.last.arguments, {'secure': true});

        await SecurityService.handleAppLifecycleState(AppLifecycleState.paused);
        expect(methodCalls.last.arguments, {'secure': true});

        await SecurityService.handleAppLifecycleState(
          AppLifecycleState.resumed,
        );
        expect(methodCalls.last.arguments, {'secure': true});

        await SecurityService.exitSensitiveScreen();
        expect(methodCalls.last.arguments, {'secure': false});
      },
    );
  });
}
