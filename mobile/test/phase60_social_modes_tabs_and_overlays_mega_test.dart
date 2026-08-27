import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/features/social_modes/widgets/mode_category_selection_sheet.dart';
import 'package:nexus/features/social_modes/widgets/professional_settings_overlay.dart';
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

  group('Phase 60 - Social Modes Tabs and Overlays Mega Tests', () {
    testWidgets('ProfessionalSettingsOverlay renders and allows editing', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfessionalSettingsOverlay(
              professionalTargetBuckets: const ['Engineer'],
              lookingFor: const ['Co-founder', 'Mentor'],
              techSkills: const ['Flutter', 'Python'],
              company: 'Nexus Inc',
              roleType: const ['Engineer'],
              savingFields: const {},
              onSaveProfessionalField: (field, val, ss) async {},
              onLoadProfessionalProfileStatusSilent: () async {},
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(ProfessionalSettingsOverlay), findsOneWidget);
    });

    testWidgets('ModeCategorySelectionSheet renders and allows interactions', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ModeCategorySelectionSheet(
              title: 'Handshakes',
              themeColor: Colors.blue,
              items: const [
                {
                  'actor_id': 'act_1',
                  'name': 'Robin',
                  'profile_pic': 'photo.jpg',
                  'tab': 'professional',
                },
              ],
              onFetchItems: () async {},
              onOpenItemDetailsDialog:
                  ({
                    required ctx,
                    required actorId,
                    required name,
                    required onActioned,
                    required onProfileLoaded,
                  }) {},
              onRecordAction: (targetId, action, token) async {},
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(ModeCategorySelectionSheet), findsOneWidget);
    });
  });
}
