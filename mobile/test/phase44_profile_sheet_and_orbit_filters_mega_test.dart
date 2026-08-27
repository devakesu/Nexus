import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/features/home/widgets/profile_detail_sheet.dart';
import 'package:nexus/features/orbit/widgets/orbit_filters_panel.dart';
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

  group('ProfileDetailSheet & OrbitFiltersPanel Mega Tests', () {
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
