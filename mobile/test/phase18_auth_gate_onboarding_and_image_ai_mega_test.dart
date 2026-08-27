import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/auth_onboarding/screens/auth_gate.dart';
import 'package:nexus/features/auth_onboarding/screens/onboarding_screen.dart';
import 'package:nexus/features/auth_onboarding/widgets/otp_verification_dialog.dart';
import 'package:nexus/features/profile/providers/client_ai_image_provider.dart';
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
        const MethodChannel('dev.fluttercommunity.plus/connectivity'),
        (call) async => ['wifi'],
      );

  setUpAll(() async {
    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        publishableKey: 'mock-anon-key',
      );
    } on Exception catch (_) {}
  });

  group('AuthGate, Onboarding & Client AI Image Mega Coverage Tests', () {
    test('ClientAIProfileState copyWith and state transitions', () {
      final state = ClientAIProfileState(
        remotePaths: ['img1.jpg', 'img2.jpg', '', '', ''],
        pendingUploads: {},
        slotSpecificVibeTags: {
          0: ['outdoor', 'smile'],
        },
        pendingDeletions: ['old1.jpg'],
      );

      expect(state.remotePaths.length, 5);
      expect(state.slotSpecificVibeTags[0], contains('outdoor'));
      expect(state.pendingDeletions, contains('old1.jpg'));
      expect(state.isProcessingAI, isFalse);
      expect(state.isSaving, isFalse);

      final updated = state.copyWith(
        isProcessingAI: true,
        isSaving: true,
        pendingDeletions: ['old1.jpg', 'old2.jpg'],
      );
      expect(updated.isProcessingAI, isTrue);
      expect(updated.isSaving, isTrue);
      expect(updated.pendingDeletions.length, 2);
    });

    testWidgets('AuthGate renders splash/gate cleanly', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: AuthGate(appName: 'Nexus'),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(AuthGate), findsOneWidget);
    });

    testWidgets('OnboardingScreen renders form fields and interactions', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      var completed = false;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: OnboardingScreen(
                onComplete: () {
                  completed = true;
                },
                verifiedMobile: '+15551234567',
                mobileVerifiedAt: DateTime.now(),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(completed, isFalse);

      // Scroll form
      await tester.drag(find.byType(OnboardingScreen), const Offset(0, -300));
      await tester.pump();
    });

    testWidgets('OtpVerificationDialog renders properly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OtpVerificationDialog(
              phone: '+15551234567',
              onVerificationSuccess: () {},
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(OtpVerificationDialog), findsOneWidget);
    });
  });
}
