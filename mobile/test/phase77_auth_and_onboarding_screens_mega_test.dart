import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/features/auth_onboarding/screens/auth_gate.dart';
import 'package:nexus/features/auth_onboarding/screens/login_screen.dart';
import 'package:nexus/features/auth_onboarding/screens/onboarding_screen.dart';
import 'package:nexus/features/auth_onboarding/screens/permissions_screen.dart';
import 'package:nexus/features/profile/widgets/place_autocomplete_field.dart';
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

  group('Phase 77 - Auth and Onboarding Screens Mega Tests', () {
    testWidgets('PlaceAutocompleteField renders and interacts', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaceAutocompleteField(
              label: 'Hometown',
              initialValue: 'Seattle, WA',
              hintText: 'Enter your hometown',
              prefixIcon: LucideIcons.mapPin,
              onChanged: (val) {},
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(PlaceAutocompleteField), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('AuthGate and LoginScreen mount cleanly', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: LoginScreen(appName: 'NEXUS'),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(LoginScreen), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: AuthGate(appName: 'NEXUS'),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(AuthGate), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('OnboardingScreen and PermissionsScreen mount cleanly', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: OnboardingScreen(onComplete: () {}),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(OnboardingScreen), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PermissionsScreen(onCompleted: () {}),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(PermissionsScreen), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
    });
  });
}
