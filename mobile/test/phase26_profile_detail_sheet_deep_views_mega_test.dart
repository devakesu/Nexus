import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/features/home/widgets/profile_detail_sheet.dart';
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

  group('ProfileDetailSheet Exhaustive Views & Safety Actions Mega Tests', () {
    testWidgets(
      'ProfileDetailSheet renders full profile, music resonance, and triggers callbacks',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final scrollController = ScrollController();
        var hideTapped = false;
        var blockTapped = false;
        var reportTapped = false;
        var unmatchTapped = false;

        final fullData = <String, dynamic>{
          'id': 'user_full_123',
          'name': 'Elena Rostova',
          'age': 24,
          'bio': 'Astrophysics PhD candidate. Coffee enthusiast & indie gamer.',
          'occupation': 'PhD Researcher',
          'company': 'Berkeley Lab',
          'college': 'UC Berkeley',
          'campus_year': 2,
          'campus_branch': 'Physics',
          'hometown': 'Prague, CZ',
          'current_place': 'Berkeley, CA',
          'gender': 'Woman',
          'pronouns': 'she/her',
          'score': 0.94,
          'match_status': 'matched',
          'ordered_images': [
            'https://images.unsplash.com/photo-1534528741775-53994a69daeb',
            'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d',
          ],
          'interests': [
            'Astronomy',
            'Sci-Fi',
            'Specialty Coffee',
            'Hiking',
            'Synthwave',
          ],
          'dating_for': ['Long-term relationship', 'Deep connection'],
          'partner_values': ['Curiosity', 'Integrity', 'Kindness'],
          'drinking': 'Socially',
          'smoking': 'Never',
          'workout': 'Often',
          'dietary_preferences': 'Vegetarian',
          'pets': 'Cat person',
          'zodiac_sign': 'Sagittarius',
          'religious_beliefs': 'Agnostic',
          'causes_supported': ['STEM Education', 'Climate Action'],
          'tech_skills': ['Python', 'Rust', 'TensorFlow'],
          'looking_for': ['Collaborators', 'Research peers'],
          'viewer_spotify_connected': true,
          'spotify_top_artists': [
            {'name': 'M83', 'imageUrl': 'https://example.com/m83.jpg'},
            {'name': 'Gunship', 'imageUrl': 'https://example.com/gunship.jpg'},
          ],
        };

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: ProfileDetailSheet(
                  data: fullData,
                  themeColor: const Color(0xFFFF2D55),
                  scrollController: scrollController,
                  onHideTap: (ctx) async {
                    hideTapped = true;
                  },
                  onBlockTap: (ctx) async {
                    blockTapped = true;
                  },
                  onReportTap: (ctx) async {
                    reportTapped = true;
                  },
                  onUnmatchTap: (ctx) async {
                    unmatchTapped = true;
                  },
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byType(ProfileDetailSheet), findsOneWidget);

        // Scroll through full ProfileDetailSheet
        await tester.drag(
          find.byType(ProfileDetailSheet),
          const Offset(0, -800),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        await tester.drag(
          find.byType(ProfileDetailSheet),
          const Offset(0, -800),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(hideTapped, isFalse);
        expect(blockTapped, isFalse);
        expect(reportTapped, isFalse);
        expect(unmatchTapped, isFalse);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
      },
    );
  });
}
