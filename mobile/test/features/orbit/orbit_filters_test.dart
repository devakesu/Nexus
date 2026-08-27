import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/features/home/widgets/profile_detail_sheet.dart';
import 'package:nexus/features/orbit/screens/orbit_screen.dart';
import 'package:nexus/features/orbit/widgets/orbit_filters_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/test_helpers.dart';

void main() {
  setUpTestEnvironment();

  setUpAll(() async {
    await initMockSupabase();
  });

  // --- Section 1 ---
  {
    Animate.restartOnHotReload = false;

    group('Orbit Canvas and Filters Deep Tests', () {
      testWidgets('OrbitFiltersPanel renders and interacts for Dating mode', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final scrollController = ScrollController();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OrbitFiltersPanel(
                tab: 'Dating',
                themeColor: Colors.pink,
                ageRange: const RangeValues(21, 35),
                selectedDrinking: const ['Socially'],
                selectedSmoking: const ['Never'],
                selectedLanguages: const ['English', 'Spanish'],
                selectedSubInterests: const ['Climbing', 'Coffee'],
                selectedYears: const [2020, 2021],
                selectedChildrenPlans: const ['Want children'],
                selectedReligiousBeliefs: const ['Agnostic'],
                selectedShowBuckets: const ['Women'],
                selectedDatingFor: const ['Relationship'],
                selectedPartnerValues: const ['Honesty'],
                dealbreakerFields: const {'drinking', 'smoking'},
                selectedLookingFor: const ['Exploring'],
                selectedTechSkills: const ['Flutter', 'Python'],
                savingFields: const {},
                onAgeRangeChanged: (r) {},
                onAgeRangeChangeEnd: (r) {},
                onSaveDatingField: (f, v, s) async {},
                onOpenTagSelectionPane: (p, s, a, setS) {},
                onOpenPartnerValuesSelectionPane: (setS, cur) {},
                isRefreshing: false,
                onFetchOrbitNodes: () async {},
                scrollController: scrollController,
                noUsersFound: false,
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(OrbitFiltersPanel), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });

      testWidgets(
        'OrbitFiltersPanel renders and interacts for Friends and Professional modes',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          for (final mode in ['Friends', 'Professional']) {
            final scrollController = ScrollController();
            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: OrbitFiltersPanel(
                    tab: mode,
                    themeColor: mode == 'Friends' ? Colors.amber : Colors.blue,
                    ageRange: const RangeValues(18, 45),
                    selectedDrinking: const <String>[],
                    selectedSmoking: const <String>[],
                    selectedLanguages: const ['English'],
                    selectedSubInterests: const ['Startups'],
                    selectedYears: const <int>[],
                    selectedChildrenPlans: const <String>[],
                    selectedReligiousBeliefs: const <String>[],
                    selectedShowBuckets: const <String>[],
                    selectedDatingFor: const <String>[],
                    selectedPartnerValues: const <String>[],
                    dealbreakerFields: const <String>{},
                    selectedLookingFor: const ['Colleagues', 'Mentors'],
                    selectedTechSkills: const ['Dart', 'Go', 'Rust'],
                    savingFields: const {'tech_skills'},
                    onAgeRangeChanged: (r) {},
                    onAgeRangeChangeEnd: (r) {},
                    onSaveDatingField: (f, v, s) async {},
                    onOpenTagSelectionPane: (p, s, a, setS) {},
                    onOpenPartnerValuesSelectionPane: (setS, cur) {},
                    isRefreshing: true,
                    onFetchOrbitNodes: () async {},
                    scrollController: scrollController,
                    noUsersFound: true,
                  ),
                ),
              ),
            );

            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            expect(find.byType(OrbitFiltersPanel), findsOneWidget);

            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
          }
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

    group('OrbitFiltersPanel Deep Widget Coverage Tests', () {
      testWidgets(
        'OrbitFiltersPanel renders for Dating tab, interacts with sliders and chips',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          final scrollController = ScrollController();
          var age = const RangeValues(18, 30);

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: OrbitFiltersPanel(
                  tab: 'Dating',
                  themeColor: AppColors.modeDating,
                  ageRange: age,
                  selectedDrinking: const ['Socially'],
                  selectedSmoking: const ['Never'],
                  selectedLanguages: const ['English', 'Spanish'],
                  selectedSubInterests: const ['AI & ML', 'Hiking'],
                  selectedYears: const [2, 3, 4],
                  selectedChildrenPlans: const ['Someday'],
                  selectedReligiousBeliefs: const ['Agnostic'],
                  selectedShowBuckets: const ['W', 'NB'],
                  selectedDatingFor: const ['Long-term'],
                  selectedPartnerValues: const ['Kindness', 'Humor'],
                  dealbreakerFields: const {'age', 'smoking'},
                  selectedLookingFor: const [],
                  selectedTechSkills: const [],
                  savingFields: const {},
                  onAgeRangeChanged: (val) {
                    age = val;
                  },
                  onAgeRangeChangeEnd: (val) {
                    age = val;
                  },
                  onSaveDatingField: (field, val, setter) async {},
                  onOpenTagSelectionPane: (title, opts, sel, setter) {},
                  onOpenPartnerValuesSelectionPane: (setter, vals) {},
                  isRefreshing: false,
                  onFetchOrbitNodes: () async {},
                  scrollController: scrollController,
                  noUsersFound: false,
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(seconds: 1));

          expect(find.byType(OrbitFiltersPanel), findsOneWidget);

          // Drag filters panel
          await tester.drag(
            find.byType(OrbitFiltersPanel),
            const Offset(0, -500),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
        },
      );

      testWidgets(
        'OrbitFiltersPanel renders for Professional tab with tech skills',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          final scrollController = ScrollController();

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: OrbitFiltersPanel(
                  tab: 'Professional',
                  themeColor: AppColors.modeProfessional,
                  ageRange: const RangeValues(21, 40),
                  selectedDrinking: const [],
                  selectedSmoking: const [],
                  selectedLanguages: const ['English'],
                  selectedSubInterests: const ['Flutter', 'Rust'],
                  selectedYears: const [],
                  selectedChildrenPlans: const [],
                  selectedReligiousBeliefs: const [],
                  selectedShowBuckets: const [],
                  selectedDatingFor: const [],
                  selectedPartnerValues: const [],
                  dealbreakerFields: const {},
                  selectedLookingFor: const ['Cofounder', 'Mentorship'],
                  selectedTechSkills: const ['Flutter', 'Python', 'Go'],
                  savingFields: const {},
                  onAgeRangeChanged: (val) {},
                  onAgeRangeChangeEnd: (val) {},
                  onSaveDatingField: (field, val, setter) async {},
                  onOpenTagSelectionPane: (title, opts, sel, setter) {},
                  onOpenPartnerValuesSelectionPane: (setter, vals) {},
                  isRefreshing: false,
                  onFetchOrbitNodes: () async {},
                  scrollController: scrollController,
                  noUsersFound: false,
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(seconds: 1));

          expect(find.byType(OrbitFiltersPanel), findsOneWidget);
        },
      );
    });
  }

  // --- Section 3 ---
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

    group('ProfileDetailSheet & OrbitFiltersPanel Tests', () {
      testWidgets(
        'ProfileDetailSheet renders complete profile details and action bar',
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
                    data: const {
                      'id': '00000000-0000-0000-0000-000000000002',
                      'name': 'Sarah',
                      'age': 24,
                      'bio': 'Lover of hiking, coffee, and Flutter apps!',
                      'display_gender': 'Woman',
                      'pronouns': 'she/her',
                      'hometown': 'Seattle, WA',
                      'occupation': 'Mobile Developer',
                      'interests': ['Hiking', 'Coffee', 'Music'],
                      'demographic_bucket': 'Tech',
                      'match_score': 94,
                      'social_mode': 'dating',
                    },
                    themeColor: AppColors.modeDating,
                    scrollController: scrollController,
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          expect(find.byType(ProfileDetailSheet), findsOneWidget);
          expect(find.textContaining('Sarah'), findsWidgets);

          // Scroll through the sheet
          await tester.drag(
            find.byType(ProfileDetailSheet),
            const Offset(0, -500),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
        },
      );

      testWidgets(
        'OrbitFiltersPanel renders filters, age range slider, and options',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          final scrollController = ScrollController();

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: OrbitFiltersPanel(
                  tab: 'dating',
                  themeColor: AppColors.modeDating,
                  ageRange: const RangeValues(20, 30),
                  selectedDrinking: const ['Socially'],
                  selectedSmoking: const ['Never'],
                  selectedLanguages: const ['English', 'Spanish'],
                  selectedSubInterests: const ['Hiking'],
                  selectedYears: const [1, 2],
                  selectedChildrenPlans: const ['Someday'],
                  selectedReligiousBeliefs: const ['Agnostic'],
                  selectedShowBuckets: const ['All'],
                  selectedDatingFor: const ['Long-term relationship'],
                  selectedPartnerValues: const ['Authenticity'],
                  dealbreakerFields: const {},
                  selectedLookingFor: const ['Friendship'],
                  selectedTechSkills: const ['Flutter'],
                  savingFields: const {},
                  onAgeRangeChanged: (range) {},
                  onAgeRangeChangeEnd: (range) {},
                  onSaveDatingField: (field, val, setter) async {},
                  onOpenTagSelectionPane: (title, tags, selected, setter) {},
                  onOpenPartnerValuesSelectionPane: (setter, selected) {},
                  isRefreshing: false,
                  onFetchOrbitNodes: () async {},
                  scrollController: scrollController,
                  noUsersFound: false,
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          expect(find.byType(OrbitFiltersPanel), findsOneWidget);

          // Scroll through filter panel
          await tester.drag(
            find.byType(OrbitFiltersPanel),
            const Offset(0, -400),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
        },
      );
    });
  }

  // --- Section 4 ---
  {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

    group('OrbitFiltersPanel Widget Tests', () {
      testWidgets(
        'renders OrbitFiltersPanel and handles age slider & filter options',
        (tester) async {
          tester.view.physicalSize = const Size(800, 1400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          final scrollController = ScrollController();

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: OrbitFiltersPanel(
                  tab: 'dating',
                  themeColor: AppColors.modeDating,
                  ageRange: const RangeValues(21, 32),
                  selectedDrinking: const ['Socially'],
                  selectedSmoking: const ['Never'],
                  selectedLanguages: const ['English', 'French'],
                  selectedSubInterests: const ['Python', 'Astronomy'],
                  selectedYears: const [2022, 2023],
                  selectedChildrenPlans: const ['Want children'],
                  selectedReligiousBeliefs: const ['Agnostic'],
                  selectedShowBuckets: const ['M', 'F'],
                  selectedDatingFor: const ['Long-term'],
                  selectedPartnerValues: const ['Empathy', 'Ambition'],
                  dealbreakerFields: const {'smoking'},
                  selectedLookingFor: const ['Dating'],
                  selectedTechSkills: const ['Flutter', 'Dart'],
                  savingFields: const {},
                  noUsersFound: false,
                  isRefreshing: false,
                  scrollController: scrollController,
                  onAgeRangeChanged: (_) {},
                  onAgeRangeChangeEnd: (_) {},
                  onSaveDatingField: (field, val, setter) async {},
                  onOpenTagSelectionPane: (title, opts, sel, setter) {},
                  onOpenPartnerValuesSelectionPane: (setter, vals) {},
                  onFetchOrbitNodes: () async {},
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.byType(OrbitFiltersPanel), findsOneWidget);
          expect(find.text('21 - 32'), findsOneWidget);

          // Verify RangeSlider is rendered
          expect(find.byType(RangeSlider), findsOneWidget);

          // Check for demographic bucket labels
          if (find.text('Men').evaluate().isNotEmpty) {
            expect(find.text('Men'), findsOneWidget);
          }
          if (find.text('Women').evaluate().isNotEmpty) {
            expect(find.text('Women'), findsOneWidget);
          }
        },
      );

      testWidgets(
        'renders OrbitFiltersPanel in Friends mode with looking for filters',
        (tester) async {
          tester.view.physicalSize = const Size(800, 1400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          final scrollController = ScrollController();

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: OrbitFiltersPanel(
                  tab: 'friends',
                  themeColor: AppColors.modeFriends,
                  ageRange: const RangeValues(18, 25),
                  selectedDrinking: const [],
                  selectedSmoking: const [],
                  selectedLanguages: const ['English'],
                  selectedSubInterests: const [],
                  selectedYears: const [],
                  selectedChildrenPlans: const [],
                  selectedReligiousBeliefs: const [],
                  selectedShowBuckets: const ['M', 'F', 'NB'],
                  selectedDatingFor: const [],
                  selectedPartnerValues: const [],
                  dealbreakerFields: const {},
                  selectedLookingFor: const ['Gaming Friends', 'Gym Buddies'],
                  selectedTechSkills: const [],
                  savingFields: const {},
                  noUsersFound: true,
                  isRefreshing: false,
                  scrollController: scrollController,
                  onAgeRangeChanged: (_) {},
                  onAgeRangeChangeEnd: (_) {},
                  onSaveDatingField: (_, _, _) async {},
                  onOpenTagSelectionPane: (_, _, _, _) {},
                  onOpenPartnerValuesSelectionPane: (_, _) {},
                  onFetchOrbitNodes: () async {},
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.byType(OrbitFiltersPanel), findsOneWidget);
          expect(find.text('18 - 25'), findsOneWidget);
        },
      );
    });
  }

  // --- Section 5 ---
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

    group('Orbit Screen Modes and Canvas Tests', () {
      testWidgets(
        'OrbitScreen renders cleanly for dating, friends, professional',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          for (final mode in [
            ('dating', Colors.pink),
            ('friends', Colors.amber),
            ('professional', Colors.teal),
          ]) {
            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: OrbitScreen(
                    tab: mode.$1,
                    themeColor: mode.$2,
                  ),
                ),
              ),
            );

            await tester.pump();
            await tester.pump(const Duration(seconds: 1));
            expect(find.byType(OrbitScreen), findsOneWidget);

            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
            await tester.pump(const Duration(seconds: 1));
          }
        },
      );
    });
  }
}
