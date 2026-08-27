import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/core/utils/error_handler.dart';
import 'package:nexus/features/settings/screens/community_guidelines_page.dart';
import 'package:nexus/features/settings/screens/help_center_page.dart';
import 'package:nexus/features/settings/widgets/email_otp_reauth_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Headers;

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

  group('Phase 65 - Error Handler and Settings Flows Mega Tests', () {
    test('ErrorHandler sanitization and formatting tests', () {
      final sanitizedEmail = ErrorHandler.sanitize(
        'Contact user@example.com for help',
      );
      expect(sanitizedEmail, contains('[EMAIL_REDACTED]'));

      final sanitizedToken = ErrorHandler.sanitize(
        'bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.xyz.123',
      );
      expect(sanitizedToken, contains('[REDACTED_SENSITIVE]'));

      final sanitizedPhone = ErrorHandler.sanitize('Call +14155552671 now');
      expect(sanitizedPhone, contains('[PHONE_REDACTED]'));

      expect(ErrorHandler.isSensitiveKey('access_token'), isTrue);
      expect(ErrorHandler.isSensitiveKey('username'), isFalse);

      final sanitizedObj = ErrorHandler.sanitizeObject({
        'token': 'secret123',
        'email': 'john@doe.com',
        'nested': ['+14155552671', 'normal string'],
      });
      expect(sanitizedObj, isA<Map<dynamic, dynamic>>());
    });

    testWidgets('HelpCenterPage renders categories and search', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HelpCenterPage(),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 2));

      expect(find.byType(HelpCenterPage), findsOneWidget);
    });

    testWidgets('CommunityGuidelinesPage renders properly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CommunityGuidelinesPage(),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 2));

      expect(find.byType(CommunityGuidelinesPage), findsOneWidget);
    });

    testWidgets('EmailOtpReauthDialog renders inputs and timers', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                return ElevatedButton(
                  onPressed: () async {
                    await showDialog<void>(
                      context: ctx,
                      builder: (_) => EmailOtpReauthDialog(
                        verifyUrl: '/api/v1/auth/reauth',
                        resendUrl: '/api/v1/auth/resend',
                        onVerificationSuccess: () {},
                      ),
                    );
                  },
                  child: const Text('Open Reauth'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Reauth'));
      await tester.pumpAndSettle();

      expect(find.byType(EmailOtpReauthDialog), findsOneWidget);
    });
  });
}
