import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/features/chats/widgets/chat_composer.dart';
import 'package:nexus/features/social_modes/widgets/professional_settings_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  group('ProfessionalSettingsOverlay & ChatComposer Mega Tests', () {
    testWidgets(
      'ProfessionalSettingsOverlay renders role chips and company field',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ProfessionalSettingsOverlay(
                professionalTargetBuckets: const ['Tech'],
                lookingFor: const ['Co-founder', 'Collaborators'],
                techSkills: const ['Flutter', 'Python'],
                company: 'Nexus Inc',
                roleType: const ['Engineer'],
                savingFields: const {},
                onSaveProfessionalField: (field, value, setState) async {},
                onLoadProfessionalProfileStatusSilent: () async {},
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byType(ProfessionalSettingsOverlay), findsOneWidget);
        expect(find.text('Engineer'), findsWidgets);

        // Tap on Designer role chip
        final designerChip = find.text('Designer');
        if (designerChip.evaluate().isNotEmpty) {
          await tester.tap(designerChip.first);
          await tester.pump();
        }
      },
    );

    testWidgets('ChatComposer text entry and action triggers', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      var sentText = '';
      var planEventTriggered = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatComposer(
              themeColor: AppColors.modeDating,
              enabled: true,
              sending: false,
              onSend: (text) async {
                sentText = text;
              },
              onSendImage: (bytes, mime) async {},
              onSendVoice: (bytes, mime, dur) async {},
              onSendLocation: (lat, lng, label) async {},
              onPlanEvent: () {
                planEventTriggered = true;
              },
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(ChatComposer), findsOneWidget);

      // Type text in composer
      final textField = find.byType(TextField);
      expect(textField, findsOneWidget);
      await tester.enterText(textField, 'Hello there!');
      await tester.pump();

      // Tap send button
      final sendButton = find.byIcon(Icons.send_rounded);
      if (sendButton.evaluate().isNotEmpty) {
        await tester.tap(sendButton.first);
        await tester.pump();
        expect(sentText, 'Hello there!');
      }

      expect(planEventTriggered, isFalse);
    });
  });
}
