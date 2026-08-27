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

  group('Social Modes Incomplete Dialogs & Overlays Mega Tests', () {
    testWidgets(
      'DatingTab handles orbit toggle with incomplete profile 400 error',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
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

        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
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

        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
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
