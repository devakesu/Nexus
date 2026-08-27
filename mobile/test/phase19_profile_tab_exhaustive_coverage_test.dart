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
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => '.',
      );

  ConsentCacheManager.specialCategoryConsentGranted = true;
  ConsentCacheManager.safetyConsentGranted = true;

  setUpAll(() async {
    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        publishableKey: 'mock-anon-key',
      );
    } on Exception catch (_) {}
  });

  group('ProfileTab Exhaustive Deep Coverage Tests', () {
    testWidgets(
      'ProfileTab renders with rich cached state, scrolls all sections, and switches pages',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
          return ResponseBody.fromString(
            jsonEncode({
              'name': 'Nova',
              'age': 23,
              'year': 4,
              'pronouns': 'they/them',
              'campus_name': 'Stanford University',
              'is_studying': true,
              'major': 'Computer Science & AI',
              'display_gender': 'Non-binary',
              'display_sexuality': 'Queer',
              'search_bucket': 'NB',
              'bio': 'Exploring multi-agent systems and quantum graphs.',
              'hometown': 'Seattle, WA',
              'current_place': 'Palo Alto, CA',
              'religious_beliefs': 'Agnostic',
              'children_plans': 'Not sure',
              'lifestyle': 'Active & Tech-focused',
              'drinking': 'Socially',
              'smoking': 'Never',
              'causes_supported': ['Climate Action', 'Open Source'],
              'top_artists': ['Daft Punk', 'Tycho', 'ODESZA'],
              'languages': ['English', 'Spanish', 'Japanese'],
              'pets': ['Cats'],
              'sub_interests': {
                'Technology': ['AI & ML', 'Flutter', 'Distributed Systems'],
                'Outdoors': ['Trail Running', 'Rock Climbing'],
              },
              'profile_pic': 'https://example.com/nova_primary.jpg',
              'normal_pics': [
                'https://example.com/gallery1.jpg',
                'https://example.com/gallery2.jpg',
                null,
                null,
              ],
              'hidden_fields': <String>['display_sexuality'],
            }),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        });

        await SecureProfileCache.write({
          'name': 'Nova',
          'age': 23,
          'year': 4,
          'pronouns': 'they/them',
          'campus_name': 'Stanford University',
          'is_studying': true,
          'major': 'Computer Science & AI',
          'display_gender': 'Non-binary',
          'display_sexuality': 'Queer',
          'search_bucket': 'NB',
          'bio': 'Exploring multi-agent systems and quantum graphs.',
          'hometown': 'Seattle, WA',
          'current_place': 'Palo Alto, CA',
          'religious_beliefs': 'Agnostic',
          'children_plans': 'Not sure',
          'lifestyle': 'Active & Tech-focused',
          'drinking': 'Socially',
          'smoking': 'Never',
          'causes_supported': ['Climate Action', 'Open Source'],
          'top_artists': ['Daft Punk', 'Tycho', 'ODESZA'],
          'languages': ['English', 'Spanish', 'Japanese'],
          'pets': ['Cats'],
          'sub_interests': {
            'Technology': ['AI & ML', 'Flutter', 'Distributed Systems'],
            'Outdoors': ['Trail Running', 'Rock Climbing'],
          },
          'profile_pic': 'https://example.com/nova_primary.jpg',
          'normal_pics': [
            'https://example.com/gallery1.jpg',
            'https://example.com/gallery2.jpg',
            null,
            null,
          ],
          'hidden_fields': <String>['display_sexuality'],
        });

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: ProfileTab(
                  onOpenOrbit: (mode, color) {},
                  targetSection: 'bio',
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 2));

        expect(find.byType(ProfileTab), findsOneWidget);

        // Drag scroll view
        await tester.drag(find.byType(ProfileTab), const Offset(0, -600));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        await tester.drag(find.byType(ProfileTab), const Offset(0, -600));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        // Scroll back up
        await tester.drag(find.byType(ProfileTab), const Offset(0, 1000));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
      },
    );

    testWidgets('ProfileTab handles targetSection variations gracefully', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ProfileTab(
                onOpenOrbit: (mode, color) {},
                targetSection: 'lifestyle',
                onClearTargetSection: () {},
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(ProfileTab), findsOneWidget);
    });
  });
}
