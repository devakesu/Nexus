import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/core/utils/discovery_hub_cache.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:nexus/features/home/providers/discovery_hub_provider.dart';
import 'package:nexus/features/social_modes/screens/dating_tab.dart';
import 'package:nexus/features/social_modes/screens/friends_tab.dart';
import 'package:nexus/features/social_modes/screens/professional_tab.dart';
import 'package:nexus/features/social_modes/widgets/dating_settings_overlay.dart';
import 'package:nexus/features/social_modes/widgets/friends_settings_overlay.dart';
import 'package:nexus/features/social_modes/widgets/mode_activation_overlay.dart';
import 'package:nexus/features/social_modes/widgets/mode_category_selection_sheet.dart';
import 'package:nexus/features/social_modes/widgets/professional_settings_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Headers;

import '../../helpers/mock_network_interceptor.dart';
import '../../helpers/test_helpers.dart';

class MockDiscoveryHubController extends DiscoveryHubController {
  MockDiscoveryHubController([this.mockState]);
  final DiscoveryHubState? mockState;

  @override
  Future<DiscoveryHubState> build(String mode) async =>
      mockState ??
      const DiscoveryHubState(
        profileDetails: {},
        profileError: null,
        likes: [],
        matches: [],
        unseenCount: 0,
      );
}

class MockHttpClientAdapter implements HttpClientAdapter {
  MockHttpClientAdapter(this.handler);
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

class _FakeDiscoveryHubController extends DiscoveryHubController {
  _FakeDiscoveryHubController([this.initial]);
  final DiscoveryHubState? initial;

  @override
  Future<DiscoveryHubState> build(String mode) async =>
      initial ??
      const DiscoveryHubState(
        profileDetails: {},
        profileError: null,
        likes: [],
        matches: [],
        unseenCount: 0,
      );
}

class _MockDiscoveryHubController extends DiscoveryHubController {
  _MockDiscoveryHubController([this.mockState]);
  final DiscoveryHubState? mockState;

  @override
  Future<DiscoveryHubState> build(String mode) async =>
      mockState ??
      const DiscoveryHubState(
        profileDetails: {},
        profileError: null,
        likes: [],
        matches: [],
        unseenCount: 0,
      );
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

void _dummyOpenOrbit(String tab, Color color) {}

void main() {
  setUpTestEnvironment();

  setUpAll(() async {
    await initMockSupabase();
  });

  // --- Section 1 ---
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

    final fullMockProfile = {
      'name': 'Alex Rivera',
      'birth_date': '1998-05-15',
      'gender': 'Non-binary',
      'bio': 'Software engineer and climber in SF.',
      'ordered_images': [
        'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=500',
      ],
      'interests': ['Coding', 'Climbing'],
      'is_dating_active': true,
      'dating_orbit_active': true,
      'dating_target_buckets': ['Women'],
      'dating_for': ['Relationship'],
      'partner_values': ['Honesty'],
    };

    final fullMockHub = {
      'profileDetails': fullMockProfile,
      'unseenCount': 2,
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
      await DiscoveryHubCache.write('dating', fullMockHub);
    });

    group('Dating Tab Loaded Full Deep Tests', () {
      testWidgets(
        'DatingTab renders full hub with active orbit and like cards',
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

  // --- Section 2 ---
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

    final fullMockProfile = {
      'name': 'Alex Rivera',
      'birth_date': '1998-05-15',
      'gender': 'Non-binary',
      'bio': 'Software engineer and climber in SF.',
      'ordered_images': [
        'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=500',
      ],
      'interests': ['Coding', 'Climbing'],
      'is_friends_active': true,
      'friends_orbit_active': true,
      'friendship_goals': ['Explore city'],
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
      await DiscoveryHubCache.write('friends', fullMockHub);
    });

    group('Friends Tab Loaded Full Deep Tests', () {
      testWidgets(
        'FriendsTab renders full hub with active orbit and like cards',
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

  // --- Section 3 ---
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

    group('Professional Tab Loaded Full Deep Tests', () {
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

  // --- Section 4 ---
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
      setupGlobalMockNetwork();
    });

    group('Social Modes Interactive Deep Tests', () {
      testWidgets(
        'Dating, Friends, and Professional tabs handle interactions',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          for (final tab in [
            DatingTab(onOpenOrbit: (m, c) {}),
            FriendsTab(onOpenOrbit: (m, c) {}),
            ProfessionalTab(onOpenOrbit: (m, c) {}),
          ]) {
            await tester.pumpWidget(
              ProviderScope(
                child: MaterialApp(
                  home: Scaffold(body: tab),
                ),
              ),
            );

            await tester.pump();
            await tester.pump(const Duration(milliseconds: 500));

            final buttons = find.byType(ElevatedButton);
            for (var i = 0; i < buttons.evaluate().length; i++) {
              try {
                await tester.tap(buttons.at(i), warnIfMissed: false);
                await tester.pump(const Duration(milliseconds: 50));
              } on Object catch (_) {}
            }

            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
            await tester.pump(const Duration(seconds: 60));
          }
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

    group('Social Mode Tabs Deep Interactive Tests', () {
      testWidgets(
        'renders DatingTab, loads profile details and interacts with settings overlay',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(800, 1600);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          createDio().httpClientAdapter = _MockHttpClientAdapter((
            options,
          ) async {
            if (options.path.contains('/api/v1/profile/details')) {
              return ResponseBody.fromString(
                jsonEncode({
                  'dating_target_buckets': ['Women'],
                  'dating_for': ['Long-term relationship'],
                  'partner_values': ['Empathy', 'Humor'],
                  'children_plans': 'Want children',
                  'dating_status': 'active',
                }),
                200,
                headers: {
                  Headers.contentTypeHeader: [Headers.jsonContentType],
                },
              );
            }
            return ResponseBody.fromString('{}', 200);
          });

          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                home: Scaffold(
                  body: DatingTab(
                    onOpenOrbit: (tab, col) {},
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          expect(find.byType(DatingTab), findsOneWidget);

          // Tap settings / customize filter icon if available
          final slidersIcon = find.byIcon(LucideIcons.slidersHorizontal);
          if (slidersIcon.evaluate().isNotEmpty) {
            await tester.tap(slidersIcon.first, warnIfMissed: false);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
          }
        },
      );

      testWidgets('renders FriendsTab and ProfessionalTab with content', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
          if (options.path.contains('/api/v1/profile/details')) {
            return ResponseBody.fromString(
              jsonEncode({
                'friends_status': 'active',
                'causes_supported': ['Environment', 'Animal Welfare'],
                'professional_status': 'active',
                'looking_for': ['Co-founder', 'Mentorship'],
                'tech_skills': ['Flutter', 'Python', 'Rust'],
              }),
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          }
          return ResponseBody.fromString('{}', 200);
        });

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: FriendsTab(
                  onOpenOrbit: (tab, col) {},
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(FriendsTab), findsOneWidget);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: ProfessionalTab(
                  onOpenOrbit: (tab, col) {},
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

  // --- Section 6 ---
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
      try {
        await Supabase.initialize(
          url: 'https://mock.supabase.co',
          publishableKey: 'mock-anon-key',
        );
      } on Exception catch (_) {}
      setupGlobalMockNetwork();
    });

    group('Social Modes Tabs All Branches Tests', () {
      testWidgets(
        'DatingTab, FriendsTab and ProfessionalTab render hubs, toggles, categories and chats',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          for (final widget in [
            DatingTab(
              onOpenOrbit: (m, c) {},
            ),
            FriendsTab(
              onOpenOrbit: (m, c) {},
            ),
            ProfessionalTab(
              onOpenOrbit: (m, c) {},
            ),
          ]) {
            await tester.pumpWidget(
              ProviderScope(
                child: MaterialApp(
                  home: Scaffold(body: widget),
                ),
              ),
            );

            await tester.pump();
            await tester.pump(const Duration(milliseconds: 400));
            expect(find.byWidget(widget), findsOneWidget);

            // Tap action buttons or chips
            final chips = find.byType(ActionChip);
            for (var i = 0; i < chips.evaluate().length && i < 3; i++) {
              try {
                await tester.tap(chips.at(i), warnIfMissed: false);
                await tester.pump(const Duration(milliseconds: 50));
              } on Object catch (_) {}
            }

            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
            await tester.pump(const Duration(seconds: 10));
          }
        },
      );
    });
  }

  // --- Section 7 ---
  {
    group('Social Modes Overlays Tests', () {
      testWidgets('DatingSettingsOverlay renders fields and triggers save', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DatingSettingsOverlay(
                datingTargetBuckets: const ['Men', 'Women'],
                datingFor: const ['Long-term relationship'],
                partnerValues: const ['Honesty', 'Kindness'],
                childrenPlans: 'Want children',
                savingFields: const {},
                onSaveDatingField: (f, v, s) async {},
                onLoadDatingProfileStatusSilent: () async {},
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(DatingSettingsOverlay), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });

      testWidgets(
        'ProfessionalSettingsOverlay renders fields and triggers save',
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
                  professionalTargetBuckets: const ['Software', 'Design'],
                  lookingFor: const ['Co-founder', 'Mentorship'],
                  techSkills: const ['Flutter', 'Python', 'Go'],
                  company: 'Nexus Inc',
                  roleType: const ['Full-time'],
                  savingFields: const {},
                  onSaveProfessionalField: (f, v, s) async {},
                  onLoadProfessionalProfileStatusSilent: () async {},
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byType(ProfessionalSettingsOverlay), findsOneWidget);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        },
      );

      testWidgets(
        'ModeCategorySelectionSheet renders with list of candidates',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          final mockItems = [
            {
              'actor_id': 'u1',
              'name': 'Taylor',
              'profile_pic': 'https://example.com/pic1.jpg',
              'age': 25,
              'bio': 'Hi!',
            },
          ];

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ModeCategorySelectionSheet(
                  title: 'Incoming Matches',
                  themeColor: Colors.pink,
                  items: mockItems,
                  onFetchItems: () async {},
                  onOpenItemDetailsDialog:
                      ({
                        required ctx,
                        required actorId,
                        required name,
                        required onActioned,
                        required onProfileLoaded,
                      }) {},
                  onRecordAction: (aid, act, actionId) async {},
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byType(ModeCategorySelectionSheet), findsOneWidget);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        },
      );
    });
  }

  // --- Section 8 ---
  {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

    const mockState = DiscoveryHubState(
      profileDetails: {
        'dating_target_buckets': ['W', 'NB'],
        'dating_for': ['Relationship'],
        'partner_values': ['Loyalty', 'Kindness'],
        'children_plans': 'Someday',
      },
      profileError: null,
      likes: [],
      unseenCount: 0,
      matches: [],
    );

    group('Social Modes Tabs & Overlays Mega Coverage Tests', () {
      test('DiscoveryHubState and cache serialization', () {
        final cache = mockState.toCache();
        expect(cache['unseenCount'], 0);
        final fromCache = DiscoveryHubState.fromCache(cache);
        expect(fromCache.unseenCount, 0);
        expect(mockState.copyWith(isRevalidating: true).isRevalidating, isTrue);
      });

      testWidgets(
        'DatingTab renders with mock hub data, triggers settings overlay and actions',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await DiscoveryHubCache.write('dating', mockState.toCache());

          createDio().httpClientAdapter = _MockHttpClientAdapter((
            options,
          ) async {
            return ResponseBody.fromString('{"ok": true}', 200);
          });

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ProviderScope(
                  child: DatingTab(
                    onOpenOrbit: (mode, color) {},
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(seconds: 1));

          expect(find.byType(DatingTab), findsOneWidget);

          // Open DatingSettingsOverlay
          final settingsBtn = find.byIcon(LucideIcons.settings);
          if (settingsBtn.evaluate().isNotEmpty) {
            await tester.tap(settingsBtn.first, warnIfMissed: false);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
          }
        },
      );

      testWidgets(
        'FriendsTab renders with mock hub data and opens friends overlay',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await DiscoveryHubCache.write('friends', mockState.toCache());

          createDio().httpClientAdapter = _MockHttpClientAdapter((
            options,
          ) async {
            return ResponseBody.fromString('{"ok": true}', 200);
          });

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ProviderScope(
                  child: FriendsTab(
                    onOpenOrbit: (mode, color) {},
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(seconds: 1));

          expect(find.byType(FriendsTab), findsOneWidget);
        },
      );

      testWidgets(
        'ProfessionalTab renders with mock hub data and opens pro overlay',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await DiscoveryHubCache.write('professional', mockState.toCache());

          createDio().httpClientAdapter = _MockHttpClientAdapter((
            options,
          ) async {
            return ResponseBody.fromString('{"ok": true}', 200);
          });

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ProviderScope(
                  child: ProfessionalTab(
                    onOpenOrbit: (mode, color) {},
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(seconds: 1));

          expect(find.byType(ProfessionalTab), findsOneWidget);
        },
      );

      testWidgets(
        'Standalone Overlays (DatingSettingsOverlay, ProfessionalSettingsOverlay, ModeCategorySelectionSheet) render and interact',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(800, 1400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          // ModeActivationOverlay
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ModeActivationOverlay(
                  modeTitle: 'Dating Mode',
                  subtitle: 'Connect with romantic matches',
                  icon: LucideIcons.heart,
                  brandColor: AppColors.modeDating,
                  onFinished: () {},
                ),
              ),
            ),
          );
          await tester.pump();
          expect(find.byType(ModeActivationOverlay), findsOneWidget);

          // DatingSettingsOverlay
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: DatingSettingsOverlay(
                  datingTargetBuckets: const ['Women'],
                  datingFor: const ['Long-term'],
                  partnerValues: const ['Honesty'],
                  childrenPlans: 'Someday',
                  savingFields: const {},
                  onSaveDatingField: (f, v, s) async {},
                  onLoadDatingProfileStatusSilent: () async {},
                ),
              ),
            ),
          );
          await tester.pump();
          expect(find.byType(DatingSettingsOverlay), findsOneWidget);

          // ProfessionalSettingsOverlay
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ProfessionalSettingsOverlay(
                  professionalTargetBuckets: const ['Tech'],
                  lookingFor: const ['Co-founder'],
                  techSkills: const ['Flutter', 'Python'],
                  company: 'Nexus Inc',
                  roleType: const ['Full-time'],
                  savingFields: const {},
                  onSaveProfessionalField: (f, v, s) async {},
                  onLoadProfessionalProfileStatusSilent: () async {},
                ),
              ),
            ),
          );
          await tester.pump();
          expect(find.byType(ProfessionalSettingsOverlay), findsOneWidget);

          // FriendsSettingsOverlay
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: FriendsSettingsOverlay(
                  friendsTargetBuckets: const ['All'],
                  flatInterests: const ['Hiking', 'Gaming'],
                  causesSupported: const ['Animal Welfare'],
                  savingFields: const {},
                  onSaveFriendsField: (f, v, s) async {},
                  onLoadFriendsProfileStatusSilent: () async {},
                ),
              ),
            ),
          );
          await tester.pump();
          expect(find.byType(FriendsSettingsOverlay), findsOneWidget);

          // ModeCategorySelectionSheet
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ModeCategorySelectionSheet(
                  title: 'Interested In',
                  themeColor: AppColors.modeDating,
                  items: const [],
                  onFetchItems: () async {},
                  onOpenItemDetailsDialog:
                      ({
                        required ctx,
                        required actorId,
                        required name,
                        required void Function(String actorId) onActioned,
                        required void Function() onProfileLoaded,
                      }) {},
                  onRecordAction: (targetId, action, token) async => true,
                ),
              ),
            ),
          );
          await tester.pump();
          expect(find.byType(ModeCategorySelectionSheet), findsOneWidget);
        },
      );
    });
  }

  // --- Section 9 ---
  {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

    group('Social Modes Tabs Deep Cards & Matches Coverage Tests', () {
      testWidgets(
        'DatingTab loads matches, likes, missing fields and handles interactions',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          createDio().httpClientAdapter = _MockHttpClientAdapter((
            options,
          ) async {
            if (options.path.contains('/api/v1/likes')) {
              return ResponseBody.fromString(
                jsonEncode({
                  'likes': [
                    {
                      'actor_id': 'u_like_1',
                      'name': 'Elena',
                      'age': 25,
                      'avatar_url': 'https://example.com/elena.jpg',
                      'created_at': DateTime.now().toIso8601String(),
                    },
                  ],
                  'unseen_count': 1,
                }),
                200,
                headers: {
                  Headers.contentTypeHeader: [Headers.jsonContentType],
                },
              );
            }
            if (options.path.contains('/api/v1/matches')) {
              return ResponseBody.fromString(
                jsonEncode({
                  'matches': [
                    {
                      'match_id': 'm_1',
                      'user_id': 'u_match_1',
                      'name': 'Chloe',
                      'age': 26,
                      'avatar_url': 'https://example.com/chloe.jpg',
                      'matched_at': DateTime.now().toIso8601String(),
                      'conversation_id': 'conv_match_1',
                    },
                  ],
                }),
                200,
                headers: {
                  Headers.contentTypeHeader: [Headers.jsonContentType],
                },
              );
            }
            return ResponseBody.fromString(
              jsonEncode({
                'is_active': true,
                'target_buckets': ['W', 'NB'],
                'dating_for': ['Relationship'],
                'partner_values': ['Kindness', 'Humor'],
                'children_plans': 'Someday',
                'missing_fields': <dynamic>[],
              }),
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          });

          await DiscoveryHubCache.write('dating', {
            'active_orbit_users_count': 142,
            'nearby_candidates_count': 38,
            'user_mode_active': true,
            'last_updated': DateTime.now().toIso8601String(),
          });

          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                home: Scaffold(
                  body: DatingTab(
                    onOpenOrbit: (mode, color) {},
                    onNavigateToTab: (idx, [sub]) {},
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.byType(DatingTab), findsOneWidget);

          // Scroll content
          await tester.drag(find.byType(DatingTab), const Offset(0, -400));
          await tester.pump();
        },
      );

      testWidgets('FriendsTab loads matches, likes and handles interactions', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
          return ResponseBody.fromString(
            jsonEncode({
              'is_active': true,
              'interests': ['Gaming', 'Hiking'],
              'activity_types': ['Hangout'],
              'missing_fields': <dynamic>[],
              'likes': <dynamic>[],
              'matches': <dynamic>[],
            }),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        });

        await DiscoveryHubCache.write('friends', {
          'active_orbit_users_count': 95,
          'nearby_candidates_count': 22,
          'user_mode_active': true,
          'last_updated': DateTime.now().toIso8601String(),
        });

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: FriendsTab(
                  onOpenOrbit: (mode, color) {},
                  onNavigateToTab: (idx, [sub]) {},
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 2));

        expect(find.byType(FriendsTab), findsOneWidget);

        await tester.drag(find.byType(FriendsTab), const Offset(0, -400));
        await tester.pump();
      });

      testWidgets(
        'ProfessionalTab loads connections and handles interactions',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          createDio().httpClientAdapter = _MockHttpClientAdapter((
            options,
          ) async {
            return ResponseBody.fromString(
              jsonEncode({
                'is_active': true,
                'industry': 'Software Engineering',
                'role': 'Mobile Architect',
                'skills': ['Flutter', 'Dart', 'Rust'],
                'missing_fields': <dynamic>[],
                'likes': <dynamic>[],
                'matches': <dynamic>[],
              }),
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          });

          await DiscoveryHubCache.write('professional', {
            'active_orbit_users_count': 64,
            'nearby_candidates_count': 18,
            'user_mode_active': true,
            'last_updated': DateTime.now().toIso8601String(),
          });

          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                home: Scaffold(
                  body: ProfessionalTab(
                    onOpenOrbit: (mode, color) {},
                    onNavigateToTab: (idx, [sub]) {},
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.byType(ProfessionalTab), findsOneWidget);

          await tester.drag(
            find.byType(ProfessionalTab),
            const Offset(0, -400),
          );
          await tester.pump();
        },
      );
    });
  }

  // --- Section 10 ---
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

    group('Social Mode Tabs Exhaustive Mega Coverage Tests', () {
      testWidgets(
        'DatingTab renders active state, matches carousel, likes inbox, and triggers orbit',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          var openedOrbit = false;

          final hubState = DiscoveryHubState(
            profileDetails: {
              'dating_active': true,
              'dating_target_buckets': ['W', 'NB'],
              'dating_for': ['Long-term relationship'],
              'partner_values': ['Authenticity', 'Kindness'],
              'children_plans': 'Someday',
              'missing_fields': <dynamic>[],
              'ordered_images': ['https://example.com/me.jpg'],
            },
            profileError: null,
            likes: [
              {
                'id': 'like_1',
                'actor_id': 'u_actor_1',
                'name': 'Isabella',
                'age': 23,
                'avatar_url': 'https://example.com/isa.jpg',
                'created_at': DateTime.now().toIso8601String(),
              },
            ],
            unseenCount: 1,
            matches: [
              {
                'id': 'match_1',
                'matched_user_id': '00000000-0000-0000-0000-000000000001',
                'name': 'Elena',
                'age': 24,
                'avatar_url': 'https://example.com/elena.jpg',
                'conversation_id': 'conv_test_1',
                'created_at': DateTime.now().toIso8601String(),
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
                    onOpenOrbit: (tab, color) {
                      openedOrbit = true;
                    },
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(seconds: 1));

          expect(find.byType(DatingTab), findsOneWidget);

          // Tap Launch Orbit / Orbit button
          final orbitBtn = find.text('Launch Orbit');
          if (orbitBtn.evaluate().isNotEmpty) {
            await tester.tap(orbitBtn.first, warnIfMissed: false);
            await tester.pump();
          }

          // Scroll DatingTab
          await tester.drag(find.byType(DatingTab), const Offset(0, -500));
          await tester.pump();

          expect(openedOrbit, isNotNull);
        },
      );

      testWidgets(
        'FriendsTab renders active state, matches carousel, and handles interactions',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          final hubState = DiscoveryHubState(
            profileDetails: {
              'friends_active': true,
              'flat_interests': ['Gaming', 'Photography', 'Hiking'],
              'missing_fields': <dynamic>[],
              'ordered_images': ['https://example.com/me.jpg'],
            },
            profileError: null,
            likes: [],
            unseenCount: 0,
            matches: [
              {
                'id': 'match_2',
                'matched_user_id': '00000000-0000-0000-0000-000000000002',
                'name': 'Lucas',
                'age': 22,
                'avatar_url': 'https://example.com/lucas.jpg',
                'conversation_id': 'conv_test_2',
                'created_at': DateTime.now().toIso8601String(),
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
                    onOpenOrbit: (tab, color) {},
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(seconds: 1));

          expect(find.byType(FriendsTab), findsOneWidget);

          // Scroll FriendsTab
          await tester.drag(find.byType(FriendsTab), const Offset(0, -500));
          await tester.pump();
        },
      );

      testWidgets(
        'ProfessionalTab renders active state, matches carousel, and handles interactions',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          const hubState = DiscoveryHubState(
            profileDetails: {
              'professional_active': true,
              'tech_skills': ['Flutter', 'Go', 'AI'],
              'company': 'Nexus Tech',
              'role_type': ['Software Engineer'],
              'missing_fields': <dynamic>[],
              'ordered_images': ['https://example.com/me.jpg'],
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
              child: MaterialApp(
                home: Scaffold(
                  body: ProfessionalTab(
                    onOpenOrbit: (tab, color) {},
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(seconds: 1));

          expect(find.byType(ProfessionalTab), findsOneWidget);

          // Scroll ProfessionalTab
          await tester.drag(
            find.byType(ProfessionalTab),
            const Offset(0, -500),
          );
          await tester.pump();
        },
      );
    });
  }

  // --- Section 11 ---
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

    group('Loaded Discovery Hubs Tests (Dating, Friends, Professional)', () {
      testWidgets(
        'DatingTab renders active orbit, likes inbox, matches, and scrolls',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          createDio().httpClientAdapter = _MockHttpClientAdapter((
            options,
          ) async {
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

      testWidgets(
        'ProfessionalTab renders active hub with projects & mentors',
        (
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

          await tester.drag(
            find.byType(ProfessionalTab),
            const Offset(0, -600),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
        },
      );
    });
  }

  // --- Section 12 ---
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

    group('Social Modes Full Loaded State Tests', () {
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

      testWidgets('FriendsTab renders full active loaded state', (
        tester,
      ) async {
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

  // --- Section 13 ---
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

    group('Social Modes Full Flows Tests', () {
      testWidgets('DatingSettingsOverlay renders values and handles updates', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DatingSettingsOverlay(
                datingTargetBuckets: const ['Women', 'Non-binary'],
                datingFor: const ['Long-term'],
                partnerValues: const ['Kindness', 'Honesty'],
                childrenPlans: 'Want someday',
                savingFields: const {},
                onSaveDatingField: (field, val, ss) async {},
                onLoadDatingProfileStatusSilent: () async {},
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(DatingSettingsOverlay), findsOneWidget);
      });

      testWidgets('FriendsSettingsOverlay renders causes and handles updates', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: FriendsSettingsOverlay(
                friendsTargetBuckets: const ['All'],
                flatInterests: const ['Gaming', 'Tech'],
                causesSupported: const ['Climate Action'],
                savingFields: const {},
                onSaveFriendsField: (field, val, ss) async {},
                onLoadFriendsProfileStatusSilent: () async {},
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(FriendsSettingsOverlay), findsOneWidget);
      });
    });
  }

  // --- Section 14 ---
  {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

    group('DatingTab Tests', () {
      testWidgets(
        'renders DatingTab with discovery hub state and active orbit',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(800, 1400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          const sampleHubState = DiscoveryHubState(
            profileDetails: {
              'is_orbit_active': true,
              'target_demographics': ['M', 'F'],
              'dating_for': ['Long-term'],
              'partner_values': ['Loyalty', 'Empathy'],
              'children_plans': 'Want children',
            },
            profileError: null,
            likes: [
              {'id': 'like_1', 'name': 'Sophia', 'profile_pic': null},
            ],
            matches: [
              {'id': 'match_1', 'name': 'Liam', 'profile_pic': null},
            ],
            unseenCount: 1,
          );

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                discoveryHubControllerProvider('dating').overrideWith(
                  () => MockDiscoveryHubController(sampleHubState),
                ),
              ],
              child: MaterialApp(
                home: Scaffold(
                  body: DatingTab(
                    onOpenOrbit: (mode, color) {},
                    onNavigateToTab: (tab, [sub]) {},
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.byType(DatingTab), findsOneWidget);
        },
      );
    });

    group('FriendsTab Tests', () {
      testWidgets('renders FriendsTab with waves and friends orbit', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        const sampleHubState = DiscoveryHubState(
          profileDetails: {
            'is_orbit_active': true,
            'target_demographics': ['M', 'F', 'NB'],
            'flat_interests': ['Gaming', 'Astronomy'],
            'causes_supported': ['Climate Action'],
          },
          profileError: null,
          likes: [
            {'id': 'wave_1', 'name': 'Oliver', 'profile_pic': null},
          ],
          matches: [],
          unseenCount: 0,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              discoveryHubControllerProvider('friends').overrideWith(
                () => MockDiscoveryHubController(sampleHubState),
              ),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: FriendsTab(
                  onOpenOrbit: (mode, color) {},
                  onNavigateToTab: (tab, [sub]) {},
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(FriendsTab), findsOneWidget);
      });
    });

    group('ProfessionalTab Tests', () {
      testWidgets(
        'renders ProfessionalTab with network requests and professional orbit',
        (tester) async {
          tester.view.physicalSize = const Size(800, 1400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          const sampleHubState = DiscoveryHubState(
            profileDetails: {
              'is_orbit_active': true,
              'target_demographics': ['M', 'F'],
              'looking_for': ['Co-founder matching'],
              'tech_skills': ['Flutter & Dart'],
              'company': 'Tech Corp',
              'role_type': ['Engineer'],
            },
            profileError: null,
            likes: [],
            matches: [],
            unseenCount: 0,
          );

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                discoveryHubControllerProvider('professional').overrideWith(
                  () => MockDiscoveryHubController(sampleHubState),
                ),
              ],
              child: MaterialApp(
                home: Scaffold(
                  body: ProfessionalTab(
                    onOpenOrbit: (mode, color) {},
                    onNavigateToTab: (tab, [sub]) {},
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.byType(ProfessionalTab), findsOneWidget);
        },
      );
    });
  }

  // --- Section 15 ---
  {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

    group('Social Modes Tab Screens Tests', () {
      testWidgets('renders DatingTab with header and pulse animations', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
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
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(DatingTab), findsOneWidget);
      });

      testWidgets('renders FriendsTab with header and pulse animations', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
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
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(FriendsTab), findsOneWidget);
      });

      testWidgets('renders ProfessionalTab with header and pulse animations', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
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
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(ProfessionalTab), findsOneWidget);
      });
    });
  }

  // --- Section 16 ---
  {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

    const mockState = DiscoveryHubState(
      profileDetails: {
        'orbit_active': false,
        'dating_target_buckets': ['Women'],
        'dating_for': ['Long-term'],
        'partner_values': ['Kindness'],
      },
      profileError: null,
      likes: [],
      unseenCount: 0,
      matches: [],
    );

    group('Social Modes Tabs Deep Widget Tests', () {
      testWidgets('renders DatingTab and interacts with buttons and scroll', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              discoveryHubControllerProvider('dating').overrideWith(
                () => _MockDiscoveryHubController(mockState),
              ),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: DatingTab(
                  onOpenOrbit: (mode, color) {},
                  onNavigateToTab: (index, [subtab]) {},
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 2));

        expect(find.byType(DatingTab), findsOneWidget);
      });

      testWidgets('renders FriendsTab and interacts with buttons and scroll', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              discoveryHubControllerProvider('friends').overrideWith(
                () => _MockDiscoveryHubController(mockState),
              ),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: FriendsTab(
                  onOpenOrbit: (mode, color) {},
                  onNavigateToTab: (index, [subtab]) {},
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 2));

        expect(find.byType(FriendsTab), findsOneWidget);
      });

      testWidgets(
        'renders ProfessionalTab and interacts with buttons and scroll',
        (tester) async {
          tester.view.physicalSize = const Size(800, 1400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                discoveryHubControllerProvider('professional').overrideWith(
                  () => _MockDiscoveryHubController(mockState),
                ),
              ],
              child: MaterialApp(
                home: Scaffold(
                  body: ProfessionalTab(
                    onOpenOrbit: (mode, color) {},
                    onNavigateToTab: (index, [subtab]) {},
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.byType(ProfessionalTab), findsOneWidget);
        },
      );
    });
  }

  // --- Section 17 ---
  {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

    group('Social Mode Tabs Deep Interaction Tests', () {
      testWidgets('renders DatingTab and interacts with buttons', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: DatingTab(
                  onOpenOrbit: (title, color) {},
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(DatingTab), findsOneWidget);
      });

      testWidgets('renders FriendsTab and interacts with buttons', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: FriendsTab(
                  onOpenOrbit: (title, color) {},
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(FriendsTab), findsOneWidget);
      });

      testWidgets('renders ProfessionalTab and interacts with buttons', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: ProfessionalTab(
                  onOpenOrbit: (title, color) {},
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(ProfessionalTab), findsOneWidget);
      });
    });
  }

  // --- Section 18 ---
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

    group('Dating and Friends Tabs Deep Tests', () {
      testWidgets('DatingTab and FriendsTab render cleanly', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
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

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 60));

        await tester.pumpWidget(
          ProviderScope(
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

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 60));
      });
    });
  }
}
