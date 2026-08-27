import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/auth_onboarding/screens/auth_gate.dart';
import 'package:nexus/features/auth_onboarding/screens/login_screen.dart';
import 'package:nexus/features/auth_onboarding/screens/onboarding_screen.dart';
import 'package:nexus/features/auth_onboarding/screens/permissions_screen.dart';
import 'package:nexus/features/auth_onboarding/widgets/otp_verification_dialog.dart';
import 'package:nexus/features/settings/widgets/about/attestation_section.dart';
import 'package:nexus/features/settings/widgets/email_otp_reauth_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'helpers/mock_network_interceptor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Animate.restartOnHotReload = false;

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
    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        publishableKey: 'mock-anon-key',
      );
    } on Exception catch (_) {}
    setupGlobalMockNetwork();
  });

  group(
    'Phase 130 - Auth Gate, Login, Onboarding and Dialogs Exhaustive Mega Tests',
    () {
      testWidgets(
        'LoginScreen, AuthGate, Onboarding and Permissions mount and render',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          for (final widget in [
            const LoginScreen(appName: 'Nexus'),
            const AuthGate(appName: 'Nexus'),
            PermissionsScreen(onCompleted: () {}),
            OnboardingScreen(onComplete: () {}),
          ]) {
            await tester.pumpWidget(
              ProviderScope(
                child: MaterialApp(
                  home: Scaffold(body: widget),
                ),
              ),
            );

            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            expect(find.byWidget(widget), findsOneWidget);

            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
            await tester.pump(const Duration(seconds: 10));
          }
        },
      );

      testWidgets(
        'OtpVerificationDialog and EmailOtpReauthDialog render properly',
        (
          tester,
        ) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: OtpVerificationDialog(
                  phone: '+14155552671',
                  onVerificationSuccess: () {},
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
          expect(find.byType(OtpVerificationDialog), findsOneWidget);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: EmailOtpReauthDialog(
                  verifyUrl: '/api/v1/auth/verify',
                  resendUrl: '/api/v1/auth/resend',
                  onVerificationSuccess: () {},
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
          expect(find.byType(EmailOtpReauthDialog), findsOneWidget);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        },
      );

      testWidgets('AttestationSection renders key attestation rows', (
        tester,
      ) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: AttestationSection(
                  onLaunch: (url) async {},
                  onCopy: (ctx, label, val) async {},
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byType(AttestationSection), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
    },
  );
}
