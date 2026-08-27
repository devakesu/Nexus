import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/features/settings/screens/feedback_ticket_detail_page.dart';
import 'package:nexus/features/settings/widgets/email_otp_reauth_dialog.dart';
import 'package:nexus/features/social_modes/widgets/dating_settings_overlay.dart';
import 'package:nexus/features/social_modes/widgets/friends_settings_overlay.dart';
import 'package:nexus/features/social_modes/widgets/mode_activation_overlay.dart';
import 'package:nexus/features/social_modes/widgets/professional_settings_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    ConsentCacheManager.safetyConsentGranted = true;
    ConsentCacheManager.specialCategoryConsentGranted = true;
    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        publishableKey: 'mock-anon-key',
      );
    } on Exception catch (_) {}
  });

  group('Phase 78 - Social Modes Overlays and Activation Mega Tests', () {
    testWidgets('ModeActivationOverlay renders and finishes animation', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ModeActivationOverlay(
              modeTitle: 'Dating Mode',
              subtitle: 'Find authentic romance',
              icon: LucideIcons.heart,
              brandColor: Colors.pink,
              onFinished: () {},
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 2600));
      expect(find.byType(ModeActivationOverlay), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets(
      'Dating, Friends, and Professional settings overlays render cleanly',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: DatingSettingsOverlay(
                  datingTargetBuckets: const ['Women'],
                  datingFor: const ['Long-term'],
                  partnerValues: const ['Honesty'],
                  childrenPlans: 'Want someday',
                  savingFields: const {},
                  onSaveDatingField: (field, value, setState) async {},
                  onLoadDatingProfileStatusSilent: () async {},
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        expect(find.byType(DatingSettingsOverlay), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: FriendsSettingsOverlay(
                  friendsTargetBuckets: const ['Everyone'],
                  flatInterests: const ['Coding', 'Gaming'],
                  causesSupported: const ['Open Source'],
                  savingFields: const {},
                  onSaveFriendsField: (field, value, setState) async {},
                  onLoadFriendsProfileStatusSilent: () async {},
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        expect(find.byType(FriendsSettingsOverlay), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: ProfessionalSettingsOverlay(
                  professionalTargetBuckets: const ['Engineers'],
                  lookingFor: const ['Co-founder'],
                  techSkills: const ['Flutter', 'Python'],
                  company: 'Nexus Inc',
                  roleType: const ['Full-time'],
                  savingFields: const {},
                  onSaveProfessionalField: (field, value, setState) async {},
                  onLoadProfessionalProfileStatusSilent: () async {},
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        expect(find.byType(ProfessionalSettingsOverlay), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
      },
    );

    testWidgets(
      'FeedbackTicketDetailPage and EmailOtpReauthDialog render cleanly',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: FeedbackTicketDetailPage(reportId: 'rep_123'),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        expect(find.byType(FeedbackTicketDetailPage), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));

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
        await tester.pump(const Duration(seconds: 2));
        expect(find.byType(EmailOtpReauthDialog), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
      },
    );
  });
}
