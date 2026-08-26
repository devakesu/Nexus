import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/auth_onboarding/screens/login_screen.dart';
import 'package:nexus/features/auth_onboarding/screens/onboarding_screen.dart';
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
        const MethodChannel('nexus/security'),
        (call) async => false,
      );

  setUpAll(() async {
    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        publishableKey: 'mock-anon-key',
      );
    } on Exception catch (_) {}
  });

  group('LoginScreen Widget Tests', () {
    testWidgets('renders login options screen with app name and buttons', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: LoginScreen(appName: 'NEXUS'),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('N E X U S'), findsOneWidget);
      expect(find.text('Sign in with Email'), findsOneWidget);
      expect(find.text('Sign in with Phone'), findsOneWidget);

      // Switch to email view
      await tester.tap(find.text('Sign in with Email'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Welcome!'), findsOneWidget);
      expect(find.text('Login with Email Link/Code'), findsOneWidget);

      // Enter email
      await tester.enterText(find.byType(TextField), 'test@nexus.app');
      await tester.pump();

      // Go back to options
      await tester.tap(find.text('Back to Login Options'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Sign in with Email'), findsOneWidget);

      // Switch to phone view
      await tester.tap(find.text('Sign in with Phone'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Sign in with Phone'), findsWidgets);
      await tester.enterText(find.byType(TextField), '+15551234567');
      await tester.pump();
    });
  });

  group('OnboardingScreen Widget Tests', () {
    testWidgets('renders onboarding form and handles name & phone input', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OnboardingScreen(
              onComplete: () {},
              verifiedMobile: '+15551234567',
              mobileVerifiedAt: DateTime.now(),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('YOUR NAME'), findsOneWidget);
      expect(find.text('AGE'), findsOneWidget);

      // Enter name
      await tester.enterText(find.byType(TextFormField).first, 'Alex Mercer');
      await tester.pump();

      // Select demographic bucket if present
      if (find.text('Men').evaluate().isNotEmpty) {
        await tester.tap(find.text('Men'));
        await tester.pump();
      }

      await tester.pump(const Duration(milliseconds: 350));
    });
  });
}
