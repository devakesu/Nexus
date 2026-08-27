import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/features/auth_onboarding/screens/auth_gate.dart';
import 'package:nexus/features/auth_onboarding/screens/login_screen.dart';
import 'package:nexus/features/auth_onboarding/screens/onboarding_screen.dart';
import 'package:nexus/features/auth_onboarding/screens/permissions_screen.dart';
import 'package:nexus/features/chats/screens/chat_conversation_page.dart';
import 'package:nexus/features/orbit/screens/orbit_screen.dart';
import 'package:nexus/features/profile/screens/profile_tab.dart';
import 'package:nexus/features/settings/screens/blocked_users_page.dart';
import 'package:nexus/features/settings/screens/checkin_alert_screen.dart';
import 'package:nexus/features/settings/screens/feedback_page.dart';
import 'package:nexus/features/settings/screens/hidden_users_page.dart';
import 'package:nexus/features/settings/screens/privacy_settings_page.dart';
import 'package:nexus/features/settings/screens/safety_center_page.dart';
import 'package:nexus/features/social_modes/screens/dating_tab.dart';
import 'package:nexus/features/social_modes/screens/friends_tab.dart';
import 'package:nexus/features/social_modes/screens/professional_tab.dart';
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
    'privacy_active_status': true,
    'privacy_read_receipts': true,
    'privacy_incognito': false,
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
    setupGlobalMockNetwork();
  });

  group('Phase 114 - Global Network Mocked Deep Screens Mega Tests', () {
    testWidgets('ProfileTab mounts and loads data cleanly', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ProfileTab(onOpenOrbit: (m, c) {}),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(ProfileTab), findsOneWidget);

      final scrollable = find.byType(Scrollable);
      if (scrollable.evaluate().isNotEmpty) {
        await tester.drag(scrollable.first, const Offset(0, -500));
        await tester.pump(const Duration(milliseconds: 100));
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(seconds: 60));
    });

    testWidgets('OrbitScreen mounts and loads data cleanly', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OrbitScreen(tab: 'Dating', themeColor: Colors.pink),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(OrbitScreen), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets(
      'DatingTab, FriendsTab, and ProfessionalTab mount with network mock',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        for (final widget in [
          DatingTab(onOpenOrbit: (m, c) {}),
          FriendsTab(onOpenOrbit: (m, c) {}),
          ProfessionalTab(onOpenOrbit: (m, c) {}),
        ]) {
          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                home: Scaffold(body: widget),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          final scrollable = find.byType(Scrollable);
          if (scrollable.evaluate().isNotEmpty) {
            await tester.drag(scrollable.first, const Offset(0, -300));
            await tester.pump(const Duration(milliseconds: 100));
          }

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.pump(const Duration(seconds: 60));
        }
      },
    );

    testWidgets('ChatConversationPage mounts with network mock', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ChatConversationPage(
                conversationId: 'c1',
                matchedUserId: 'u2',
                tab: 'Dating',
                name: 'Taylor',
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(ChatConversationPage), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(seconds: 60));
    });

    testWidgets('Settings pages mount and render with network mock', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      for (final widget in const [
        PrivacySettingsPage(),
        HiddenUsersPage(),
        BlockedUsersPage(),
        SafetyCenterPage(),
        FeedbackPage(),
        CheckInAlertScreen(),
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

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      }
    });

    testWidgets(
      'Auth and Onboarding pages mount and render with network mock',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        for (final widget in [
          const LoginScreen(appName: 'Nexus'),
          PermissionsScreen(onCompleted: () {}),
          OnboardingScreen(onComplete: () {}),
          const AuthGate(appName: 'Nexus'),
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

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
        }
      },
    );
  });
}
