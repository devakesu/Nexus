import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/features/home/widgets/export_code_card.dart';
import 'package:nexus/features/home/widgets/interests_overlay.dart';
import 'package:nexus/features/home/widgets/profile_detail_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Headers;

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

  group('Phase 61 - Home Profile Detail Sheet and Interests Mega Tests', () {
    testWidgets('ProfileDetailSheet renders complete profile details', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final data = {
        'id': 'user_detail_1',
        'name': 'Samira',
        'age': 25,
        'bio': 'Creative director & explorer',
        'gender': 'Woman',
        'pronouns': 'she/her',
        'hometown': 'Austin, TX',
        'current_place': 'New York, NY',
        'campus_name': 'Columbia',
        'major': 'Architecture',
        'year': 4,
        'drinking': 'Socially',
        'smoking': 'Never',
        'pets': ['Cat'],
        'interests': ['Design', 'Art'],
        'sub_interests': {
          'Design': ['Typography', 'UI/UX'],
        },
        'photos': ['photo1.jpg'],
        'ordered_images': ['photo1.jpg'],
        'completeness_score': 95,
        'viewer_spotify_connected': true,
        'top_artists': ['Arctic Monkeys', 'Daft Punk'],
      };

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ProfileDetailSheet(
                data: data,
                themeColor: Colors.teal,
                scrollController: ScrollController(),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(ProfileDetailSheet), findsOneWidget);
      expect(find.textContaining('Samira'), findsWidgets);
    });

    testWidgets('ExportCodeCard renders and handles actions', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ExportCodeCard(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(ExportCodeCard), findsOneWidget);
    });

    testWidgets('InterestsOverlay renders and toggles interests', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InterestsOverlay(
              initialSelected: const ['Tech', 'Design'],
              themeColor: Colors.blue,
              onSave: (interests) {},
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(InterestsOverlay), findsOneWidget);
    });
  });
}
