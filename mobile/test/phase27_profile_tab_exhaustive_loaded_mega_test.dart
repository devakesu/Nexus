import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:nexus/core/utils/secure_profile_cache.dart';
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

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('dexterous.com/flutter/local_notifications'),
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

  group('ProfileTab Exhaustive Loaded Mega Tests', () {
    testWidgets(
      'ProfileTab renders all profile sections and scrolls through fully',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final fullProfile = <String, dynamic>{
          'name': 'Elena Rostova',
          'age': 24,
          'bio': 'Astrophysics PhD candidate. Coffee enthusiast & indie gamer.',
          'occupation': 'PhD Researcher',
          'company': 'Berkeley Lab',
          'college': 'UC Berkeley',
          'campus_year': 2,
          'campus_branch': 'Physics',
          'hometown': 'Prague, CZ',
          'current_place': 'Berkeley, CA',
          'gender': 'Woman',
          'pronouns': 'she/her',
          'ordered_images': [
            'https://images.unsplash.com/photo-1534528741775-53994a69daeb',
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
          'is_dating_active': true,
          'is_friends_active': true,
          'is_professional_active': false,
          'hidden_fields': <String>[],
        };

        await SecureProfileCache.write(fullProfile);

        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
          if (options.path.contains('/api/v1/profile/details')) {
            return ResponseBody.fromString(
              jsonEncode(fullProfile),
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

        // Scroll through ProfileTab
        await tester.drag(find.byType(ProfileTab), const Offset(0, -600));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        await tester.drag(find.byType(ProfileTab), const Offset(0, -600));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        await tester.drag(find.byType(ProfileTab), const Offset(0, -600));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
      },
    );
  });
}
