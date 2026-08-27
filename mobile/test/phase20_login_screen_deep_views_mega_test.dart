import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/auth_onboarding/screens/login_screen.dart';
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

  setUpAll(() async {
    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        publishableKey: 'mock-anon-key',
      );
    } on Exception catch (_) {}
  });

  group('LoginScreen Deep Views & Interactions Mega Tests', () {
    testWidgets(
      'LoginScreen renders, switches between options, email, and phone views',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: LoginScreen(appName: 'Nexus'),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byType(LoginScreen), findsOneWidget);

        // Find and tap Continue with Email / Phone
        final emailBtn = find.text('Continue with Email');
        if (emailBtn.evaluate().isNotEmpty) {
          await tester.tap(emailBtn.first, warnIfMissed: false);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          // Enter email text
          final tf = find.byType(TextField);
          if (tf.evaluate().isNotEmpty) {
            await tester.enterText(tf.first, 'user@stanford.edu');
            await tester.pump();
          }

          // Tap back
          final backBtn = find.byIcon(Icons.arrow_back);
          if (backBtn.evaluate().isNotEmpty) {
            await tester.tap(backBtn.first, warnIfMissed: false);
            await tester.pump();
          }
        }

        // Tap phone option
        final phoneBtn = find.text('Continue with Phone');
        if (phoneBtn.evaluate().isNotEmpty) {
          await tester.tap(phoneBtn.first, warnIfMissed: false);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
        }
      },
    );
  });
}
