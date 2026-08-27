import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/core/utils/secure_profile_cache.dart';
import 'package:nexus/features/profile/screens/profile_tab.dart';
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
      'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=500',
      'https://images.unsplash.com/photo-1517841905240-472988babdf9?w=500',
    ],
    'interests': [
      'Coding',
      'Climbing',
      'Coffee',
      'Sci-Fi',
      'Running',
      'Cooking',
    ],
    'hometown_city': 'Seattle',
    'current_city': 'San Francisco',
    'drinking_preference': 'Socially',
    'smoking_preference': 'Never',
    'languages_spoken': ['English', 'Spanish'],
    'job_title': 'Senior Engineer',
    'company': 'Tech Corp',
    'university': 'Stanford University',
    'major': 'Computer Science',
    'graduation_year': 2020,
    'dating_intent': 'Long-term partnership',
    'children_plans': 'Want children',
    'religious_beliefs': 'Agnostic',
    'sexual_orientation': 'Queer',
    'tech_skills': ['Flutter', 'Dart', 'Python', 'Go'],
    'professional_interests': ['Startups', 'AI/ML'],
    'friendship_goals': ['Explore city', 'Weekend sports'],
    'dealbreakers': ['Smoking'],
    'partner_values': ['Honesty', 'Ambition'],
    'dating_target_buckets': ['Women', 'Non-binary'],
    'dating_for': ['Relationship'],
    'is_dating_active': true,
    'is_friends_active': true,
    'is_professional_active': true,
    'dating_orbit_active': true,
    'friends_orbit_active': true,
    'professional_orbit_active': true,
    'instagram_handle': 'alex_climbs',
    'spotify_top_artists': ['Radiohead', 'Bon Iver', 'Phoebe Bridgers'],
    'spotify_playlists': [
      {'name': 'Deep Focus', 'url': 'https://open.spotify.com/playlist/123'},
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
    await SecureProfileCache.write(fullMockProfile);
  });

  group('Phase 103 - Profile Tab Full Loaded Mega Tests', () {
    testWidgets(
      'ProfileTab renders with populated SecureProfileCache and scrolls through all content',
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
                body: ProfileTab(
                  onOpenOrbit: (mode, color) {},
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(ProfileTab), findsOneWidget);

        // Scroll through the entire profile page to trigger building all lazy sections
        final scrollable = find.byType(Scrollable).first;
        for (var i = 0; i < 5; i++) {
          await tester.drag(scrollable, const Offset(0, -400));
          await tester.pump(const Duration(milliseconds: 100));
        }

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 60));
      },
    );
  });
}
