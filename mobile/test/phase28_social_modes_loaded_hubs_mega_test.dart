import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:nexus/features/home/providers/discovery_hub_provider.dart';
import 'package:nexus/features/social_modes/screens/dating_tab.dart';
import 'package:nexus/features/social_modes/screens/friends_tab.dart';
import 'package:nexus/features/social_modes/screens/professional_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Headers;

void _dummyOpenOrbit(String tab, Color color) {}

class _FakeDiscoveryHubController extends DiscoveryHubController {
  _FakeDiscoveryHubController(this.initial);
  final DiscoveryHubState initial;

  @override
  Future<DiscoveryHubState> build(String mode) async {
    return initial;
  }
}

class _MockHttpClientAdapter implements HttpClientAdapter {
  _MockHttpClientAdapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => handler(options);

  @override
  void close({bool force = false}) {}
}

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

  group('Loaded Discovery Hubs Mega Tests (Dating, Friends, Professional)', () {
    testWidgets(
      'DatingTab renders active orbit, likes inbox, matches, and scrolls',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
          return ResponseBody.fromString(
            '{}',
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        });

        final hubState = DiscoveryHubState(
          profileDetails: {
            'is_dating_active': true,
            'dating_for': ['Long-term relationship'],
            'partner_values': ['Kindness', 'Curiosity'],
            'dating_target_buckets': ['Women'],
            'children_plans': 'Someday',
            'ordered_images': ['https://example.com/p1.jpg'],
          },
          profileError: null,
          likes: [
            {
              'id': 'like_1',
              'actor_id': 'user_2',
              'name': 'Chloe Adams',
              'age': 23,
              'image': 'https://example.com/chloe.jpg',
              'created_at': DateTime.now().toIso8601String(),
              'is_seen': false,
            },
          ],
          unseenCount: 1,
          matches: [
            {
              'id': 'match_1',
              'user_id': 'user_3',
              'name': 'Sophia Loren',
              'image': 'https://example.com/sophia.jpg',
              'matched_at': DateTime.now().toIso8601String(),
              'last_message': 'Hey! How is your day?',
            },
          ],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              discoveryHubControllerProvider('dating').overrideWith(
                () => _FakeDiscoveryHubController(hubState),
              ),
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
        await tester.pump(const Duration(seconds: 1));

        expect(find.byType(DatingTab), findsOneWidget);

        // Scroll through DatingTab
        await tester.drag(find.byType(DatingTab), const Offset(0, -600));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      },
    );

    testWidgets('FriendsTab renders active hub with likes & matches', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final hubState = DiscoveryHubState(
        profileDetails: {
          'is_friends_active': true,
          'interests': ['Board Games', 'Hiking'],
          'ordered_images': ['https://example.com/p1.jpg'],
        },
        profileError: null,
        likes: [],
        unseenCount: 0,
        matches: [
          {
            'id': 'friend_match_1',
            'user_id': 'user_friend_1',
            'name': 'Lucas Miller',
            'image': 'https://example.com/lucas.jpg',
            'matched_at': DateTime.now().toIso8601String(),
          },
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            discoveryHubControllerProvider('friends').overrideWith(
              () => _FakeDiscoveryHubController(hubState),
            ),
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
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(FriendsTab), findsOneWidget);

      await tester.drag(find.byType(FriendsTab), const Offset(0, -600));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('ProfessionalTab renders active hub with projects & mentors', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const hubState = DiscoveryHubState(
        profileDetails: {
          'is_professional_active': true,
          'tech_skills': ['Flutter', 'Python'],
          'looking_for': ['Co-founders', 'Open Source Collaborators'],
          'ordered_images': ['https://example.com/p1.jpg'],
        },
        profileError: null,
        likes: [],
        unseenCount: 0,
        matches: [],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            discoveryHubControllerProvider('professional').overrideWith(
              () => _FakeDiscoveryHubController(hubState),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: ProfessionalTab(
                onOpenOrbit: _dummyOpenOrbit,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(ProfessionalTab), findsOneWidget);

      await tester.drag(find.byType(ProfessionalTab), const Offset(0, -600));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });
  });
}
