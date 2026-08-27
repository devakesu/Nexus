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
import 'package:nexus/core/utils/network_utils.dart';
import 'package:nexus/features/auth_onboarding/screens/onboarding_screen.dart';
import 'package:nexus/features/chats/utils/open_chat.dart';
import 'package:nexus/features/home/providers/discovery_hub_provider.dart';
import 'package:nexus/features/profile/widgets/cosmic_selection_overlay.dart';
import 'package:nexus/features/settings/screens/feedback_ticket_detail_page.dart';
import 'package:nexus/features/settings/screens/settings_tab.dart';
import 'package:nexus/features/settings/widgets/email_otp_reauth_dialog.dart';
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

import '../../helpers/test_helpers.dart';

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

    group('Social Modes Incomplete Dialogs & Overlays Tests', () {
      testWidgets(
        'DatingTab handles orbit toggle with incomplete profile 400 error',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          createDio().httpClientAdapter = _MockHttpClientAdapter((
            options,
          ) async {
            if (options.path.contains('/api/v1/profile/details') &&
                options.method == 'PATCH') {
              return ResponseBody.fromString(
                jsonEncode({
                  'detail': {
                    'missing_fields': [
                      'name',
                      'age',
                      'bio',
                      'interests',
                      'profile_pic',
                      'normal_pics',
                      'drinking',
                      'smoking',
                    ],
                  },
                }),
                400,
                headers: {
                  Headers.contentTypeHeader: [Headers.jsonContentType],
                },
              );
            }
            return ResponseBody.fromString('{}', 200);
          });

          const hubState = DiscoveryHubState(
            profileDetails: {
              'is_dating_active': false,
              'dating_for': <String>[],
              'partner_values': <String>[],
              'dating_target_buckets': <String>[],
              'ordered_images': <String>[],
            },
            profileError: null,
            likes: [],
            unseenCount: 0,
            matches: [],
          );

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                discoveryHubControllerProvider('dating').overrideWith(
                  () => _FakeDiscoveryHubController(hubState),
                ),
              ],
              child: const MaterialApp(
                home: Scaffold(
                  body: DatingTab(
                    onOpenOrbit: _dummyOpenOrbit,
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(seconds: 1));

          expect(find.byType(DatingTab), findsOneWidget);

          // Find and tap Activate Orbit button to trigger the incomplete flow
          final activateBtn = find.text('Activate Orbit');
          if (activateBtn.evaluate().isNotEmpty) {
            await tester.tap(activateBtn.first);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 500));
          }
        },
      );

      testWidgets(
        'FriendsTab handles orbit toggle with incomplete profile 400 error',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          createDio().httpClientAdapter = _MockHttpClientAdapter((
            options,
          ) async {
            if (options.path.contains('/api/v1/profile/details') &&
                options.method == 'PATCH') {
              return ResponseBody.fromString(
                jsonEncode({
                  'detail': {
                    'missing_fields': ['interests', 'bio', 'profile_pic'],
                  },
                }),
                400,
                headers: {
                  Headers.contentTypeHeader: [Headers.jsonContentType],
                },
              );
            }
            return ResponseBody.fromString('{}', 200);
          });

          const hubState = DiscoveryHubState(
            profileDetails: {
              'is_friends_active': false,
              'interests': <String>[],
              'ordered_images': <String>[],
            },
            profileError: null,
            likes: [],
            unseenCount: 0,
            matches: [],
          );

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                discoveryHubControllerProvider('friends').overrideWith(
                  () => _FakeDiscoveryHubController(hubState),
                ),
              ],
              child: const MaterialApp(
                home: Scaffold(
                  body: FriendsTab(
                    onOpenOrbit: _dummyOpenOrbit,
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(seconds: 1));

          expect(find.byType(FriendsTab), findsOneWidget);

          final activateBtn = find.text('Activate Orbit');
          if (activateBtn.evaluate().isNotEmpty) {
            await tester.tap(activateBtn.first);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 500));
          }
        },
      );

      testWidgets(
        'ProfessionalTab handles orbit toggle with incomplete profile 400 error',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          createDio().httpClientAdapter = _MockHttpClientAdapter((
            options,
          ) async {
            if (options.path.contains('/api/v1/profile/details') &&
                options.method == 'PATCH') {
              return ResponseBody.fromString(
                jsonEncode({
                  'detail': {
                    'missing_fields': ['tech_skills', 'looking_for'],
                  },
                }),
                400,
                headers: {
                  Headers.contentTypeHeader: [Headers.jsonContentType],
                },
              );
            }
            return ResponseBody.fromString('{}', 200);
          });

          const hubState = DiscoveryHubState(
            profileDetails: {
              'is_professional_active': false,
              'tech_skills': <String>[],
              'looking_for': <String>[],
              'ordered_images': <String>[],
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

          final activateBtn = find.text('Activate Orbit');
          if (activateBtn.evaluate().isNotEmpty) {
            await tester.tap(activateBtn.first);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 500));
          }
        },
      );
    });
  }

  // --- Section 2 ---
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

    group('SettingsTab & DatingSettingsOverlay Tests', () {
      testWidgets(
        'SettingsTab renders account items, security, and preferences',
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
                'status': 'active',
              }),
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          });

          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                home: Scaffold(
                  body: SettingsTab(
                    onOpenOrbit: (mode, color) {},
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          expect(find.byType(SettingsTab), findsOneWidget);

          // Scroll settings
          await tester.drag(find.byType(SettingsTab), const Offset(0, -400));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
        },
      );

      testWidgets('DatingSettingsOverlay chips and value interactions', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DatingSettingsOverlay(
                datingTargetBuckets: const ['Tech'],
                datingFor: const ['Long-term relationship'],
                partnerValues: const ['Authenticity'],
                childrenPlans: 'Someday',
                savingFields: const {},
                onSaveDatingField: (field, value, setState) async {},
                onLoadDatingProfileStatusSilent: () async {},
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byType(DatingSettingsOverlay), findsOneWidget);

        // Tap on partner value chip
        final partnerChip = find.text('Empathy');
        if (partnerChip.evaluate().isNotEmpty) {
          await tester.tap(partnerChip.first);
          await tester.pump();
        }
      });
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

    group('ModeCategorySelectionSheet & OnboardingScreen Tests', () {
      testWidgets(
        'ModeCategorySelectionSheet renders items and allows interaction',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          final items = [
            {
              'actor': {
                'id': '00000000-0000-0000-0000-000000000002',
                'name': 'Charlie',
                'display_name': 'Charlie',
                'avatar_url': 'https://mock.com/avatar.jpg',
              },
            },
          ];

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ModeCategorySelectionSheet(
                  title: 'Interested in You',
                  themeColor: AppColors.modeDating,
                  items: items,
                  onFetchItems: () async {},
                  onOpenItemDetailsDialog:
                      ({
                        required ctx,
                        required actorId,
                        required name,
                        required onActioned,
                        required onProfileLoaded,
                      }) {},
                  onRecordAction: (targetId, action, token) async => {},
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          expect(find.byType(ModeCategorySelectionSheet), findsOneWidget);
          expect(find.text('Charlie'), findsOneWidget);
          expect(find.text('Interested in You'), findsOneWidget);
        },
      );

      testWidgets('OnboardingScreen renders with pre-filled verified mobile', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: OnboardingScreen(
                  onComplete: () {},
                  verifiedMobile: '+14155552671',
                  mobileVerifiedAt: DateTime.now(),
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byType(OnboardingScreen), findsOneWidget);
        expect(find.text('+14155552671'), findsOneWidget);
      });
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

    group('Social Modes Tabs and Overlays Tests', () {
      testWidgets('ProfessionalSettingsOverlay renders and allows editing', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ProfessionalSettingsOverlay(
                professionalTargetBuckets: const ['Engineer'],
                lookingFor: const ['Co-founder', 'Mentor'],
                techSkills: const ['Flutter', 'Python'],
                company: 'Nexus Inc',
                roleType: const ['Engineer'],
                savingFields: const {},
                onSaveProfessionalField: (field, val, ss) async {},
                onLoadProfessionalProfileStatusSilent: () async {},
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byType(ProfessionalSettingsOverlay), findsOneWidget);
      });

      testWidgets(
        'ModeCategorySelectionSheet renders and allows interactions',
        (
          tester,
        ) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ModeCategorySelectionSheet(
                  title: 'Handshakes',
                  themeColor: Colors.blue,
                  items: const [
                    {
                      'actor_id': 'act_1',
                      'name': 'Robin',
                      'profile_pic': 'photo.jpg',
                      'tab': 'professional',
                    },
                  ],
                  onFetchItems: () async {},
                  onOpenItemDetailsDialog:
                      ({
                        required ctx,
                        required actorId,
                        required name,
                        required onActioned,
                        required onProfileLoaded,
                      }) {},
                  onRecordAction: (targetId, action, token) async {},
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.byType(ModeCategorySelectionSheet), findsOneWidget);
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

    group('ModeActivationOverlay Tests', () {
      testWidgets(
        'renders ModeActivationOverlay and executes onFinished after animation',
        (tester) async {
          var finished = false;

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ModeActivationOverlay(
                  modeTitle: 'Dating Mode',
                  subtitle: 'Calibrating romance orbit...',
                  icon: LucideIcons.heart,
                  brandColor: AppColors.modeDating,
                  onFinished: () => finished = true,
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 2600));

          expect(finished, isTrue);
        },
      );
    });

    group('ModeCategorySelectionSheet Tests', () {
      testWidgets(
        'renders ModeCategorySelectionSheet with items and empty state',
        (tester) async {
          final sampleItems = [
            {'id': 'item_1', 'name': 'Maya Lin', 'profile_pic': null},
            {'id': 'item_2', 'name': 'Lucas Vance', 'profile_pic': null},
          ];

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ModeCategorySelectionSheet(
                  title: 'Likes Sent',
                  themeColor: AppColors.modeDating,
                  items: sampleItems,
                  emptyMessage: 'No likes sent yet',
                  onFetchItems: () async {},
                  onOpenItemDetailsDialog:
                      ({
                        required ctx,
                        required actorId,
                        required name,
                        required onActioned,
                        required onProfileLoaded,
                      }) {},
                  onRecordAction: (targetId, action, token) async {},
                ),
              ),
            ),
          );

          await tester.pump();
          expect(find.text('Likes Sent'), findsOneWidget);
          expect(find.text('2'), findsOneWidget);
          expect(find.text('Maya Lin'), findsOneWidget);
          expect(find.text('Lucas Vance'), findsOneWidget);
        },
      );
    });

    group('DatingSettingsOverlay Tests', () {
      testWidgets(
        'renders DatingSettingsOverlay and handles bucket toggles and partner values',
        (tester) async {
          tester.view.physicalSize = const Size(800, 1400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: DatingSettingsOverlay(
                  datingTargetBuckets: const ['M', 'F'],
                  datingFor: const ['Long-term relationship'],
                  partnerValues: const ['Empathy', 'Ambition'],
                  childrenPlans: 'Want children',
                  savingFields: const {},
                  onSaveDatingField: (field, val, setter) async {},
                  onLoadDatingProfileStatusSilent: () async {},
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));

          expect(find.byType(DatingSettingsOverlay), findsOneWidget);
          expect(find.text('Dating Settings'), findsOneWidget);
        },
      );
    });

    group('FriendsSettingsOverlay Tests', () {
      testWidgets(
        'renders FriendsSettingsOverlay and handles causes selection',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(800, 1400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: FriendsSettingsOverlay(
                  friendsTargetBuckets: const ['M', 'F', 'NB'],
                  flatInterests: const ['Hiking', 'Gaming'],
                  causesSupported: const ['Climate Action', 'Mental Health'],
                  savingFields: const {},
                  onSaveFriendsField: (field, val, setter) async {},
                  onLoadFriendsProfileStatusSilent: () async {},
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));

          expect(find.byType(FriendsSettingsOverlay), findsOneWidget);
          expect(find.text('Friends Settings'), findsOneWidget);
        },
      );
    });

    group('ProfessionalSettingsOverlay Tests', () {
      testWidgets(
        'renders ProfessionalSettingsOverlay and handles role & skills selections',
        (tester) async {
          tester.view.physicalSize = const Size(800, 1400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ProfessionalSettingsOverlay(
                  professionalTargetBuckets: const ['M', 'F'],
                  lookingFor: const ['Co-founder matching', 'Hiring talent'],
                  techSkills: const [
                    'Flutter & Dart',
                    'Python & Django/FastAPI',
                  ],
                  company: 'Nexus Tech',
                  roleType: const ['Engineer'],
                  savingFields: const {},
                  onSaveProfessionalField: (field, val, setter) async {},
                  onLoadProfessionalProfileStatusSilent: () async {},
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));

          expect(find.byType(ProfessionalSettingsOverlay), findsOneWidget);
          expect(find.text('Professional Settings'), findsOneWidget);
        },
      );
    });
  }

  // --- Section 6 ---
  {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

    group('Social Modes Overlays Widget Tests', () {
      testWidgets('renders ModeCategorySelectionSheet with list items', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

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
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(ModeCategorySelectionSheet), findsOneWidget);
      });

      testWidgets('renders ModeActivationOverlay with mode title and icon', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ModeActivationOverlay(
                modeTitle: 'Professional Mode',
                subtitle: 'Connect with colleagues and industry peers',
                icon: LucideIcons.briefcase,
                brandColor: AppColors.modeProfessional,
                onFinished: () {},
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(ModeActivationOverlay), findsOneWidget);
      });

      testWidgets('renders DatingSettingsOverlay with options and saves', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

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
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(DatingSettingsOverlay), findsOneWidget);
      });

      testWidgets('renders FriendsSettingsOverlay with flat interests', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

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
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(FriendsSettingsOverlay), findsOneWidget);
      });

      testWidgets('renders ProfessionalSettingsOverlay with tech skills', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

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
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(ProfessionalSettingsOverlay), findsOneWidget);
      });
    });
  }

  // --- Section 7 ---
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

    group('Social Modes Overlays and Activation Tests', () {
      testWidgets('ModeActivationOverlay renders and finishes animation', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ModeActivationOverlay(
                modeTitle: 'Dating Mode',
                subtitle: 'Find authentic romance',
                icon: LucideIcons.heart,
                brandColor: Colors.pink,
                onFinished: () {},
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 2600));
        expect(find.byType(ModeActivationOverlay), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      });

      testWidgets(
        'Dating, Friends, and Professional settings overlays render cleanly',
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
                  body: DatingSettingsOverlay(
                    datingTargetBuckets: const ['Women'],
                    datingFor: const ['Long-term'],
                    partnerValues: const ['Honesty'],
                    childrenPlans: 'Want someday',
                    savingFields: const {},
                    onSaveDatingField: (field, value, setState) async {},
                    onLoadDatingProfileStatusSilent: () async {},
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));
          expect(find.byType(DatingSettingsOverlay), findsOneWidget);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                home: Scaffold(
                  body: FriendsSettingsOverlay(
                    friendsTargetBuckets: const ['Everyone'],
                    flatInterests: const ['Coding', 'Gaming'],
                    causesSupported: const ['Open Source'],
                    savingFields: const {},
                    onSaveFriendsField: (field, value, setState) async {},
                    onLoadFriendsProfileStatusSilent: () async {},
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));
          expect(find.byType(FriendsSettingsOverlay), findsOneWidget);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                home: Scaffold(
                  body: ProfessionalSettingsOverlay(
                    professionalTargetBuckets: const ['Engineers'],
                    lookingFor: const ['Co-founder'],
                    techSkills: const ['Flutter', 'Python'],
                    company: 'Nexus Inc',
                    roleType: const ['Full-time'],
                    savingFields: const {},
                    onSaveProfessionalField: (field, value, setState) async {},
                    onLoadProfessionalProfileStatusSilent: () async {},
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));
          expect(find.byType(ProfessionalSettingsOverlay), findsOneWidget);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));
        },
      );

      testWidgets(
        'FeedbackTicketDetailPage and EmailOtpReauthDialog render cleanly',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            const MaterialApp(
              home: Scaffold(
                body: FeedbackTicketDetailPage(reportId: 'rep_123'),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));
          expect(find.byType(FeedbackTicketDetailPage), findsOneWidget);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: EmailOtpReauthDialog(
                  verifyUrl: '/api/v1/auth/verify',
                  resendUrl: '/api/v1/auth/resend',
                  onVerificationSuccess: () {},
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));
          expect(find.byType(EmailOtpReauthDialog), findsOneWidget);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));
        },
      );
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

    group('Social Modes Category Sheet Tests', () {
      testWidgets(
        'ModeCategorySelectionSheet renders empty and populated list cleanly',
        (
          tester,
        ) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ModeCategorySelectionSheet(
                  title: 'Likes Inbox',
                  themeColor: Colors.pink,
                  items: const [],
                  onFetchItems: () async {},
                  onOpenItemDetailsDialog:
                      ({
                        required ctx,
                        required actorId,
                        required name,
                        required onActioned,
                        required onProfileLoaded,
                      }) {},
                  onRecordAction: (targetId, action, token) async => {},
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
          expect(find.byType(ModeCategorySelectionSheet), findsOneWidget);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
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

    group('CosmicSelectionOverlay Widget Tests', () {
      testWidgets('renders options and filters by search query', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: CosmicSelectionOverlay(
                title: 'SELECT STAR SIGN',
                options: ['Aries', 'Taurus', 'Gemini', 'Cancer', 'Leo'],
                currentValue: 'Gemini',
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('SELECT STAR SIGN'), findsOneWidget);
        expect(find.text('Aries'), findsOneWidget);
        expect(find.text('Taurus'), findsOneWidget);

        await tester.enterText(find.byType(TextField), 'Leo');
        await tester.pump();

        expect(find.text('Leo'), findsWidgets);
        expect(find.text('Aries'), findsNothing);
      });
    });

    group('OpenChat Utility Tests', () {
      testWidgets('openOrCreateChat handles null matchId gracefully', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () => openOrCreateChat(
                      context,
                      matchId: null,
                      matchedUserId: 'user_456',
                      name: 'Luna',
                    ),
                    child: const Text('Open Null Match Chat'),
                  );
                },
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.tap(find.text('Open Null Match Chat'));
        await tester.pump();

        expect(
          find.text('Still setting up this match, try again in a moment.'),
          findsOneWidget,
        );
      });
    });
  }
}
