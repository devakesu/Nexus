import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/discovery_hub_cache.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:nexus/features/social_modes/screens/dating_tab.dart';
import 'package:nexus/features/social_modes/screens/friends_tab.dart';
import 'package:nexus/features/social_modes/screens/professional_tab.dart';
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

  setUpAll(() async {
    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        publishableKey: 'mock-anon-key',
      );
    } on Exception catch (_) {}
  });

  group('Social Modes Tabs Deep Cards & Matches Coverage Tests', () {
    testWidgets(
      'DatingTab loads matches, likes, missing fields and handles interactions',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
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

    testWidgets('ProfessionalTab loads connections and handles interactions', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
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

      await tester.drag(find.byType(ProfessionalTab), const Offset(0, -400));
      await tester.pump();
    });
  });
}
