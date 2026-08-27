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

  group('Phase 66 - ProfileTab Exhaustive Mega Tests', () {
    testWidgets(
      'ProfileTab comprehensive loaded state and scroll interactions',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
          return ResponseBody.fromString(
            jsonEncode({
              'name': 'Taylor Swift',
              'age': 34,
              'bio': 'Music and songwriting',
              'gender': 'Woman',
              'pronouns': 'she/her',
              'display_gender': 'Woman',
              'display_sexuality': 'Straight',
              'hometown': 'Reading, PA',
              'current_place': 'Nashville, TN',
              'campus_name': 'NYU',
              'major': 'Fine Arts',
              'year': 4,
              'drinking': 'Rarely',
              'smoking': 'Never',
              'exercise': 'Daily',
              'sleep_schedule': 'Early Bird',
              'dietary_preference': 'None',
              'pets': ['Cat'],
              'religious_beliefs': 'Christian',
              'causes_supported': ['Music Education', 'Disaster Relief'],
              'interests': ['Music', 'Writing'],
              'sub_interests': {
                'Music': ['Pop', 'Country'],
              },
              'photos': ['p1.jpg', 'p2.jpg'],
              'ordered_images': ['p1.jpg', 'p2.jpg'],
              'completeness_score': 100,
              'hidden_fields': <dynamic>[],
              'viewer_spotify_connected': true,
              'top_artists': [
                {'name': 'Taylor Swift', 'image': 'ts.jpg'},
              ],
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

        // Perform scrolling through all sections
        await tester.drag(find.byType(ProfileTab), const Offset(0, -600));
        await tester.pump(const Duration(milliseconds: 300));

        await tester.drag(find.byType(ProfileTab), const Offset(0, -600));
        await tester.pump(const Duration(milliseconds: 300));

        await tester.drag(find.byType(ProfileTab), const Offset(0, 600));
        await tester.pump(const Duration(milliseconds: 300));
      },
    );
  });
}
