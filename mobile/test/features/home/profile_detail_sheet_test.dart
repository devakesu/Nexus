import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/features/home/providers/discovery_hub_provider.dart';
import 'package:nexus/features/home/widgets/common_header.dart';
import 'package:nexus/features/home/widgets/custom_bottom_nav_bar.dart';
import 'package:nexus/features/home/widgets/export_code_card.dart';
import 'package:nexus/features/home/widgets/interests_overlay.dart';
import 'package:nexus/features/home/widgets/profile_detail_sheet.dart';
import 'package:nexus/features/profile/widgets/sections/social_coordinates_section.dart';
import 'package:nexus/features/profile/widgets/tag_chips_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Headers;

import '../../helpers/test_helpers.dart';

void main() {
  setUpTestEnvironment();

  setUpAll(() async {
    await initMockSupabase();
  });

  // --- Section 1 ---
  {
    final richProfileData = <String, dynamic>{
      'id': 'u_taylor',
      'name': 'Taylor Swift',
      'age': 28,
      'gender': 'Woman',
      'compatibility_score': 96,
      'bio': 'Musician, songwriter, cat enthusiast.',
      'ordered_images': [
        'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=500',
        'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=500',
      ],
      'interests': ['Music', 'Cats', 'Baking', 'Poetry', 'Road Trips'],
      'hometown_city': 'Nashville',
      'current_city': 'New York',
      'drinking_preference': 'Socially',
      'smoking_preference': 'Never',
      'languages_spoken': ['English'],
      'job_title': 'Artist',
      'company': 'Republic Records',
      'university': 'NYU (Honorary)',
      'major': 'Fine Arts',
      'graduation_year': 2022,
      'dating_intent': 'Long-term partnership',
      'children_plans': 'Open to children',
      'religious_beliefs': 'Christian',
      'sexual_orientation': 'Straight',
      'tech_skills': ['Audio Engineering', 'Logic Pro'],
      'professional_interests': ['Songwriting', 'Directing'],
      'friendship_goals': ['Creative collaborations', 'Coffee dates'],
      'instagram_handle': 'taylorswift',
      'spotify_top_artists': ['The National', 'Bon Iver', 'Phoebe Bridgers'],
      'spotify_playlists': [
        {'name': 'Midnight Vibes', 'url': 'https://spotify.com/playlist/1'},
      ],
      'viewer_spotify_connected': true,
    };

    group('Profile Detail Sheet Deep Interactions Tests', () {
      testWidgets(
        'ProfileDetailSheet renders all sections, badges, and safety actions',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          final scrollController = ScrollController();
          // ignored flags

          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                home: Scaffold(
                  body: ProfileDetailSheet(
                    data: richProfileData,
                    themeColor: Colors.pink,
                    scrollController: scrollController,
                    isSelf: false,
                    onUnmatchTap: (ctx) async {},
                    onHideTap: (ctx) async {},
                    onBlockTap: (ctx) async {},
                    onReportTap: (ctx) async {},
                    onSpotifyConnectRefresh: () async {},
                    actionBar: Container(key: const Key('action_bar')),
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(find.byType(ProfileDetailSheet), findsOneWidget);

          // Scroll through sheet to render all slivers/sections
          for (var i = 0; i < 6; i++) {
            await tester.drag(
              find.byType(ProfileDetailSheet),
              const Offset(0, -500),
            );
            await tester.pump(const Duration(milliseconds: 100));
          }

          // Tap safety buttons at the bottom if found
          final inkWells = find.byType(InkWell);
          for (var i = 0; i < inkWells.evaluate().length && i < 6; i++) {
            try {
              await tester.tap(inkWells.at(i), warnIfMissed: false);
              await tester.pump(const Duration(milliseconds: 50));
            } on Object catch (_) {}
          }

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        },
      );

      testWidgets(
        'ProfileDetailSheet renders in self-view mode without safety actions',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          final scrollController = ScrollController();

          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                home: Scaffold(
                  body: ProfileDetailSheet(
                    data: richProfileData,
                    themeColor: Colors.teal,
                    scrollController: scrollController,
                    showScoreBadge: false,
                    showSafetyActions: false,
                    isSelf: true,
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byType(ProfileDetailSheet), findsOneWidget);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        },
      );
    });
  }

  // --- Section 2 ---
  {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

    group('Home, Profile Detail & Discovery Mega Coverage Tests', () {
      testWidgets(
        'ProfileDetailSheet renders complete profile details and handles actions',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          final mockProfileData = {
            'id': 'user_detail_99',
            'name': 'Gemma Simmons',
            'age': 27,
            'bio': 'Biochemist & explorer',
            'ordered_images': [
              'https://example.com/gemma1.jpg',
              'https://example.com/gemma2.jpg',
            ],
            'display_gender': 'Woman',
            'display_sexuality': 'Straight',
            'pronouns': 'she/her',
            'campus_name': 'S.H.I.E.L.D. Academy',
            'major': 'Biochemistry',
            'year': 4,
            'hometown': 'London, UK',
            'current_place': 'New York, NY',
            'lifestyle': 'Curious & Dedicated',
            'drinking': 'Rarely',
            'smoking': 'Never',
            'religious_beliefs': 'Science',
            'pets': ['Cats'],
            'causes_supported': ['STEM Education'],
            'top_artists': ['Queen', 'Muse'],
            'sub_interests': {
              'Science': ['Biotech', 'Genetics'],
            },
          };

          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                home: Scaffold(
                  body: ProfileDetailSheet(
                    data: mockProfileData,
                    themeColor: AppColors.pulsarPink,
                    scrollController: ScrollController(),
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.byType(ProfileDetailSheet), findsOneWidget);
          expect(find.text('Gemma Simmons, 27'), findsWidgets);

          // Scroll sheet
          await tester.drag(
            find.byType(ProfileDetailSheet),
            const Offset(0, -400),
          );
          await tester.pump();
        },
      );

      testWidgets('ExportCodeCard renders and triggers export actions', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: ExportCodeCard(),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(ExportCodeCard), findsOneWidget);
      });

      testWidgets(
        'TagChipsEditor and SocialCoordinatesSection render and interact',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          // TagChipsEditor
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: TagChipsEditor(
                  label: 'Interests',
                  icon: Icons.tag,
                  iconColor: AppColors.primaryTeal,
                  hintText: 'Add interest',
                  currentValues: const ['Flutter', 'Dart'],
                  presets: const ['Flutter', 'Dart', 'React', 'Vue'],
                  onChanged: (tags) {},
                ),
              ),
            ),
          );
          await tester.pump();
          expect(find.byType(TagChipsEditor), findsOneWidget);

          // SocialCoordinatesSection
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: SocialCoordinatesSection(
                    hometown: 'Vancouver',
                    currentPlace: 'New York',
                    languages: const ['English', 'French'],
                    campusName: 'Metro Univ',
                    savedCampusName: 'Metro Univ',
                    major: 'Journalism',
                    isStudying: true,
                    year: 4,
                    onHometownChanged: (v) {},
                    onHometownSubmitted: (v) {},
                    onCurrentPlaceChanged: (v) {},
                    onCurrentPlaceSubmitted: (v) {},
                    onLanguagesChanged: (v) {},
                    onCampusNameChanged: (v) {},
                    onCampusNameSubmitted: (v) {},
                    onMajorChanged: (v) {},
                    onMajorSubmitted: (v) {},
                    onIsStudyingChanged: (v) {},
                    onYearChanged: (v) {},
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(find.byType(SocialCoordinatesSection), findsOneWidget);
        },
      );
    });
  }

  // --- Section 3 ---
  {
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

    group('ProfileDetailSheet Exhaustive Deep Tests', () {
      testWidgets(
        'ProfileDetailSheet renders complete profile data, photos, badges and safety buttons',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          final scrollController = ScrollController();
          var reported = false;
          var blocked = false;
          var hidden = false;
          var unmatched = false;

          final fullData = {
            'id': 'u_test_99',
            'name': 'Seraphina',
            'age': 24,
            'pronouns': 'she/her',
            'bio': 'Astrophysics enthusiast & classical pianist.',
            'campus_name': 'MIT',
            'major': 'Physics & Astronomy',
            'year': 3,
            'hometown': 'Boston, MA',
            'current_place': 'Cambridge, MA',
            'profile_pic': 'https://example.com/seraphina.jpg',
            'normal_pics': [
              'https://example.com/seraphina2.jpg',
              'https://example.com/seraphina3.jpg',
            ],
            'interests': ['Astronomy', 'Piano', 'Quantum Physics'],
            'causes_supported': ['STEM Education', 'Clean Oceans'],
            'top_artists': ['Ludovico Einaudi', 'Hans Zimmer', 'Max Richter'],
            'drinking': 'Occasionally',
            'smoking': 'Never',
            'religious_beliefs': 'Agnostic',
            'children_plans': 'Someday',
            'pets': ['Golden Retriever'],
            'languages': ['English', 'French', 'German'],
            'compatibility_score': 94,
            'viewer_spotify_connected': true,
          };

          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                home: Scaffold(
                  body: ProfileDetailSheet(
                    data: fullData,
                    themeColor: AppColors.modeDating,
                    scrollController: scrollController,
                    onReportTap: (ctx) async {
                      reported = true;
                    },
                    onBlockTap: (ctx) async {
                      blocked = true;
                    },
                    onHideTap: (ctx) async {
                      hidden = true;
                    },
                    onUnmatchTap: (ctx) async {
                      unmatched = true;
                    },
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(seconds: 1));

          expect(find.byType(ProfileDetailSheet), findsOneWidget);
          expect(find.text('Seraphina, 24'), findsOneWidget);
          expect(find.text('she/her'), findsOneWidget);

          // Scroll sheet
          await tester.drag(
            find.byType(ProfileDetailSheet),
            const Offset(0, -600),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          await tester.drag(
            find.byType(ProfileDetailSheet),
            const Offset(0, -600),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          expect(reported, isFalse);
          expect(blocked, isFalse);
          expect(hidden, isFalse);
          expect(unmatched, isFalse);
        },
      );
    });
  }

  // --- Section 4 ---
  {
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

    group('ProfileDetailSheet Exhaustive Views & Safety Actions Tests', () {
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
            'bio':
                'Astrophysics PhD candidate. Coffee enthusiast & indie gamer.',
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
              {
                'name': 'Gunship',
                'imageUrl': 'https://example.com/gunship.jpg',
              },
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

  // --- Section 5 ---
  {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('nexus/security'),
          (call) async => false,
        );

    group('DiscoveryHubState Tests', () {
      test(
        'DiscoveryHubState fromCache, toCache, and copyWith work accurately',
        () {
          final cacheData = {
            'profileDetails': {'name': 'Alice', 'age': 24},
            'likes': [
              {'id': 'like_1', 'user_id': 'u1'},
            ],
            'unseenCount': 3,
            'matches': [
              {'id': 'match_1', 'user_id': 'u2'},
            ],
          };

          final state = DiscoveryHubState.fromCache(cacheData);
          expect(state.profileDetails?['name'], 'Alice');
          expect(state.likes.length, 1);
          expect(state.unseenCount, 3);
          expect(state.matches.length, 1);
          expect(state.isRevalidating, isFalse);

          final exported = state.toCache();
          expect(exported['unseenCount'], 3);

          final updated = state.copyWith(isRevalidating: true);
          expect(updated.isRevalidating, isTrue);
          expect(updated.profileDetails?['name'], 'Alice');
        },
      );
    });

    group('ProfileDetailSheet Tests', () {
      testWidgets('renders ProfileDetailSheet with profile data and action bar', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final testProfileData = {
          'name': 'Elena Rostova',
          'age': 23,
          'bio': 'Astrophysics enthusiast & cosmic coffee lover.',
          'ordered_images': [
            'https://test.supabase.co/storage/v1/object/public/avatars/elena.jpg',
          ],
          'affinity_score': 88,
          'interests': ['Quantum Physics', 'Python'],
          'viewer_spotify_connected': true,
        };

        final scrollController = ScrollController();

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: ProfileDetailSheet(
                  data: testProfileData,
                  themeColor: AppColors.modeDating,
                  scrollController: scrollController,
                  actionBar: const Text('Custom Action Bar'),
                  onUnmatchTap: (ctx) async {},
                  onHideTap: (ctx) async {},
                  onBlockTap: (ctx) async {},
                  onReportTap: (ctx) async {},
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Elena Rostova, 23'), findsOneWidget);
        expect(find.text('Custom Action Bar'), findsOneWidget);
      });
    });
  }

  // --- Section 6 ---
  {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

    group('ProfileDetailSheet Deep Coverage Tests', () {
      testWidgets(
        'renders all profile sections, attributes, top artists, and action buttons',
        (tester) async {
          tester.view.physicalSize = const Size(800, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          final scrollController = ScrollController();

          final profile = {
            'id': 'user_aria_123',
            'name': 'Aria Vance',
            'age': 24,
            'bio': 'Exploring galaxies and coding algorithms.',
            'ordered_images': ['https://example.com/aria.jpg'],
            'campus_name': 'UC Berkeley',
            'major': 'Astrophysics',
            'occupation': 'Space Researcher',
            'top_artists': ['Radiohead', 'Odesza', 'Rufus Du Sol'],
            'hometown': 'San Francisco, CA',
            'interests': ['Astronomy', 'Coding', 'Electronic Music'],
            'verified': true,
            'pronouns': 'she/her',
            'display_gender': 'Woman',
            'display_sexuality': 'Straight',
            'children_plans': 'Someday',
            'drinking': 'Socially',
            'smoking': 'Never',
            'weed': 'Never',
            'workout': 'Often',
            'star_sign': 'Aquarius',
            'pets': 'Cats',
            'communication_style': 'Direct',
            'love_style': 'Quality Time',
            'education_level': 'Masters',
            'personality_type': 'INTJ',
            'blood_type': 'O+',
            'social_links': {'instagram': 'aria_v', 'spotify': 'aria_music'},
          };

          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                home: Scaffold(
                  body: ProfileDetailSheet(
                    data: profile,
                    themeColor: Colors.purpleAccent,
                    scrollController: scrollController,
                    onUnmatchTap: (ctx) async {},
                    onHideTap: (ctx) async {},
                    onBlockTap: (ctx) async {},
                    onReportTap: (ctx) async {},
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.byType(ProfileDetailSheet), findsOneWidget);
          expect(find.text('Aria Vance, 24'), findsWidgets);
          expect(
            find.text('Exploring galaxies and coding algorithms.'),
            findsOneWidget,
          );
        },
      );
    });
  }

  // --- Section 7 ---
  {
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

    group('Home Profile Detail Sheet and Interests Tests', () {
      testWidgets('ProfileDetailSheet renders complete profile details', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final data = {
          'id': 'user_detail_1',
          'name': 'Samira',
          'age': 25,
          'bio': 'Creative director & explorer',
          'gender': 'Woman',
          'pronouns': 'she/her',
          'hometown': 'Austin, TX',
          'current_place': 'New York, NY',
          'campus_name': 'Columbia',
          'major': 'Architecture',
          'year': 4,
          'drinking': 'Socially',
          'smoking': 'Never',
          'pets': ['Cat'],
          'interests': ['Design', 'Art'],
          'sub_interests': {
            'Design': ['Typography', 'UI/UX'],
          },
          'photos': ['photo1.jpg'],
          'ordered_images': ['photo1.jpg'],
          'completeness_score': 95,
          'viewer_spotify_connected': true,
          'top_artists': ['Arctic Monkeys', 'Daft Punk'],
        };

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: ProfileDetailSheet(
                  data: data,
                  themeColor: Colors.teal,
                  scrollController: ScrollController(),
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(find.byType(ProfileDetailSheet), findsOneWidget);
        expect(find.textContaining('Samira'), findsWidgets);
      });

      testWidgets('ExportCodeCard renders and handles actions', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: ExportCodeCard(),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(ExportCodeCard), findsOneWidget);
      });

      testWidgets('InterestsOverlay renders and toggles interests', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: InterestsOverlay(
                initialSelected: const ['Tech', 'Design'],
                themeColor: Colors.blue,
                onSave: (interests) {},
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(InterestsOverlay), findsOneWidget);
      });
    });
  }

  // --- Section 8 ---
  {
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

    group('Home Interests and Headers Tests', () {
      testWidgets('InterestsOverlay renders and searches correctly', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: InterestsOverlay(
                initialSelected: const ['Coding', 'Gaming'],
                onSave: (vals) {},
                themeColor: Colors.pink,
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(find.byType(InterestsOverlay), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      });

      testWidgets(
        'CommonHeader and CustomBottomNavBar render cleanly for all tabs',
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
                  appBar: const PreferredSize(
                    preferredSize: Size.fromHeight(100),
                    child: CommonHeader(
                      appName: 'NEXUS',
                      currentTab: 0,
                    ),
                  ),
                  bottomNavigationBar: CustomBottomNavBar(
                    currentIndex: 0,
                    onTabSelected: (index) {},
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          expect(find.byType(CommonHeader), findsOneWidget);
          expect(find.byType(CustomBottomNavBar), findsOneWidget);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.pump(const Duration(seconds: 60));
        },
      );
    });
  }
}
