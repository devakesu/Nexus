import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/features/home/providers/discovery_hub_provider.dart';
import 'package:nexus/features/social_modes/screens/dating_tab.dart';
import 'package:nexus/features/social_modes/screens/friends_tab.dart';
import 'package:nexus/features/social_modes/screens/professional_tab.dart';
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

  group('Social Modes Full Loaded State Mega Tests', () {
    test('DiscoveryHubState fromCache and toCache roundtrip', () {
      final json = {
        'profileDetails': {'name': 'Test'},
        'likes': [
          {'id': '1'},
        ],
        'unseenCount': 2,
        'matches': [
          {'id': '2'},
        ],
      };

      final state = DiscoveryHubState.fromCache(json);
      expect(state.profileDetails?['name'], 'Test');
      expect(state.unseenCount, 2);
      expect(state.likes.length, 1);
      expect(state.matches.length, 1);

      final cache = state.toCache();
      expect(cache['unseenCount'], 2);

      final modified = state.copyWith(isRevalidating: true);
      expect(modified.isRevalidating, isTrue);
    });

    testWidgets(
      'DatingTab renders full active loaded state with matches and likes',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        const state = DiscoveryHubState(
          profileDetails: {
            'is_active': true,
            'dating_target_buckets': ['Tech'],
            'dating_for': ['Long-term relationship'],
            'partner_values': ['Authenticity'],
            'children_plans': 'Someday',
          },
          profileError: null,
          likes: [
            {
              'actor': {
                'id': 'u2',
                'name': 'Emma',
                'age': 23,
              },
            },
          ],
          unseenCount: 1,
          matches: [
            {
              'id': 'm1',
              'matched_user_id': 'u3',
              'name': 'Lucas',
              'age': 25,
              'is_new': true,
            },
          ],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              discoveryHubControllerProvider(
                'dating',
              ).overrideWith(() => _MockDiscoveryHubController(state)),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: DatingTab(
                  onOpenOrbit: (mode, color) {},
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byType(DatingTab), findsOneWidget);
      },
    );

    testWidgets('FriendsTab renders full active loaded state', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const state = DiscoveryHubState(
        profileDetails: {
          'is_active': true,
          'friends_target_buckets': ['Tech'],
          'flat_interests': ['Hiking'],
          'causes_supported': ['Climate Action'],
        },
        profileError: null,
        likes: [],
        unseenCount: 0,
        matches: [],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            discoveryHubControllerProvider(
              'friends',
            ).overrideWith(() => _MockDiscoveryHubController(state)),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: FriendsTab(
                onOpenOrbit: (mode, color) {},
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(FriendsTab), findsOneWidget);
    });

    testWidgets('ProfessionalTab renders full active loaded state', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const state = DiscoveryHubState(
        profileDetails: {
          'is_active': true,
          'professional_target_buckets': ['Tech'],
          'looking_for': ['Co-founder'],
          'tech_skills': ['Flutter'],
          'company': 'Nexus',
          'role_type': ['Engineer'],
        },
        profileError: null,
        likes: [],
        unseenCount: 0,
        matches: [],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            discoveryHubControllerProvider(
              'professional',
            ).overrideWith(() => _MockDiscoveryHubController(state)),
          ],
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
    });
  });
}

class _MockDiscoveryHubController extends DiscoveryHubController {
  _MockDiscoveryHubController(this.mockState);
  final DiscoveryHubState mockState;

  @override
  Future<DiscoveryHubState> build(String mode) async {
    return mockState;
  }
}
