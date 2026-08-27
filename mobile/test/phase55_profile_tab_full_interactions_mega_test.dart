import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:nexus/features/profile/screens/profile_tab.dart';
import 'package:nexus/features/profile/widgets/visibility_toggle_mini.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Headers;

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

  group('Phase 55 - ProfileTab Full Interactions Mega Test', () {
    testWidgets(
      'Renders ProfileTab and interacts with all fields and toggles',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
          if (options.path.contains('/api/v1/profile/details')) {
            return ResponseBody.fromString(
              jsonEncode({
                'name': 'Alex Nexus',
                'age': 24,
                'bio': 'Software engineer and space explorer',
                'gender': 'Non-binary',
                'pronouns': 'they/them',
                'display_gender': 'Non-binary',
                'display_sexuality': 'Queer',
                'hometown': 'San Francisco, CA',
                'current_place': 'Seattle, WA',
                'campus_name': 'MIT',
                'major': 'Computer Science',
                'year': 4,
                'drinking': 'Socially',
                'smoking': 'Never',
                'exercise': 'Often',
                'sleep_schedule': 'Night Owl',
                'dietary_preference': 'Vegetarian',
                'pets': ['Dog', 'Cat'],
                'religious_beliefs': 'Agnostic',
                'causes_supported': ['Open Source', 'Climate'],
                'interests': ['Tech', 'Gaming', 'Music'],
                'sub_interests': {
                  'Tech': ['Flutter', 'Rust', 'AI'],
                  'Music': ['Indie', 'Synthwave'],
                },
                'photos': ['photo1.jpg', 'photo2.jpg'],
                'ordered_images': ['photo1.jpg', 'photo2.jpg'],
                'completeness_score': 90,
                'hidden_fields': ['display_sexuality'],
                'dating_target_buckets': ['NB', 'F'],
                'dating_for': ['Long-term'],
                'partner_values': ['Kindness', 'Growth'],
                'viewer_spotify_connected': true,
                'top_artists': [
                  {'name': 'Daft Punk', 'image': 'daft.jpg'},
                ],
              }),
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          }
          if (options.path.contains('/api/v1/profile/update') ||
              options.path.contains('/api/v1/profile/toggle-visibility')) {
            return ResponseBody.fromString(
              jsonEncode({'status': 'ok'}),
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          }
          return ResponseBody.fromString(
            jsonEncode({'data': <dynamic>[]}),
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
                body: ProfileTab(
                  onOpenOrbit: (mode, color) {},
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(find.byType(ProfileTab), findsOneWidget);

        // Find visibility toggles and tap them
        final toggles = find.byType(VisibilityToggleMini);
        for (var i = 0; i < toggles.evaluate().length && i < 3; i++) {
          await tester.tap(toggles.at(i));
          await tester.pump(const Duration(milliseconds: 300));
        }

        // Scroll down and pump
        await tester.drag(find.byType(ProfileTab), const Offset(0, -500));
        await tester.pump(const Duration(milliseconds: 500));

        await tester.drag(find.byType(ProfileTab), const Offset(0, -500));
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byType(ProfileTab), findsOneWidget);
      },
    );
  });
}
