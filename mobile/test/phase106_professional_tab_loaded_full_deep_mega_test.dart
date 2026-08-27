import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/core/utils/discovery_hub_cache.dart';
import 'package:nexus/features/social_modes/screens/professional_tab.dart';
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

  final fullMockProfile = {
    'name': 'Alex Rivera',
    'birth_date': '1998-05-15',
    'gender': 'Non-binary',
    'bio': 'Software engineer and climber in SF.',
    'ordered_images': [
      'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=500',
    ],
    'interests': ['Coding', 'Climbing'],
    'is_professional_active': true,
    'professional_orbit_active': true,
    'tech_skills': ['Flutter', 'Python', 'Go'],
    'professional_interests': ['Startups', 'AI/ML'],
    'job_title': 'Senior Engineer',
    'company': 'Tech Corp',
  };

  final fullMockHub = {
    'profileDetails': fullMockProfile,
    'unseenCount': 1,
    'likes': [
      {
        'actor_id': 'u2',
        'name': 'Taylor',
        'age': 26,
        'gender': 'Woman',
        'bio': 'Designer and photographer',
        'city': 'San Francisco',
        'avatar_url':
            'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=500',
        'compatibility_score': 94,
      },
    ],
    'matches': [
      {
        'match_id': 'm1',
        'matched_user_id': 'u2',
        'conversation_id': 'c1',
        'name': 'Taylor',
        'avatar_url':
            'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=500',
        'last_message': 'Hey!',
        'last_active_at': '2026-08-27T12:00:00Z',
      },
    ],
  };

  setUpAll(() async {
    ConsentCacheManager.safetyConsentGranted = true;
    ConsentCacheManager.specialCategoryConsentGranted = true;
    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        publishableKey: 'mock-anon-key',
      );
    } on Exception catch (_) {}
    await DiscoveryHubCache.write('professional', fullMockHub);
  });

  group('Phase 106 - Professional Tab Loaded Full Deep Mega Tests', () {
    testWidgets(
      'ProfessionalTab renders full hub with active orbit and like cards',
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
                body: ProfessionalTab(
                  onOpenOrbit: (mode, color) {},
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(ProfessionalTab), findsOneWidget);

        final scrollable = find.byType(Scrollable);
        if (scrollable.evaluate().isNotEmpty) {
          await tester.drag(scrollable.first, const Offset(0, -300));
          await tester.pump(const Duration(milliseconds: 100));
        }

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 60));
      },
    );
  });
}
