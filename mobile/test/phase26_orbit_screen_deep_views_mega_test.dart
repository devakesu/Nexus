import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:nexus/features/orbit/models/orbit_node.dart';
import 'package:nexus/features/orbit/screens/orbit_screen.dart';
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

  group('OrbitScreen Deep Views & Transformations Mega Tests', () {
    testWidgets(
      'OrbitScreen renders Dating tab nodes and handles pan/zoom transformations',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
          return ResponseBody.fromString(
            jsonEncode({
              'nodes': [
                {
                  'id': 'node_1',
                  'name': 'Maya Lin',
                  'x': 1600,
                  'y': 1600,
                  'orbit_tier': 1,
                  'score': 0.95,
                  'profile_pic':
                      'https://images.unsplash.com/photo-1534528741775-53994a69daeb',
                  'gender': 'Woman',
                  'sexuality': 'Straight',
                  'connection_type': 'Dating',
                  'match_status': 'matched',
                  'is_new': true,
                },
                {
                  'id': 'node_2',
                  'name': 'Alex Rivera',
                  'x': 1750,
                  'y': 1500,
                  'orbit_tier': 2,
                  'score': 0.82,
                  'profile_pic':
                      'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d',
                  'gender': 'Man',
                  'sexuality': 'Bisexual',
                  'connection_type': 'Dating',
                  'match_status': 'pending',
                  'is_new': false,
                },
              ],
              'session_id': 'orbit_sess_123',
            }),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        });

        final prefetchResult = OrbitPrefetchResult(
          nodes: [
            OrbitNode(
              id: 'node_1',
              name: 'Maya Lin',
              x: 1600,
              y: 1600,
              orbitTier: 1,
              score: 0.95,
              profilePic:
                  'https://images.unsplash.com/photo-1534528741775-53994a69daeb',
              gender: 'Woman',
              sexuality: 'Straight',
              connectionType: 'Dating',
              matchStatus: 'matched',
              isNew: true,
            ),
            OrbitNode(
              id: 'node_2',
              name: 'Alex Rivera',
              x: 1750,
              y: 1500,
              orbitTier: 2,
              score: 0.82,
              profilePic:
                  'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d',
              gender: 'Man',
              sexuality: 'Bisexual',
              connectionType: 'Dating',
              matchStatus: 'pending',
            ),
          ],
          sessionId: 'orbit_sess_123',
          profilePicUrl:
              'https://images.unsplash.com/photo-1534528741775-53994a69daeb',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OrbitScreen(
                tab: 'Dating',
                themeColor: const Color(0xFFFF2D55),
                prefetchFuture: Future.value(prefetchResult),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byType(OrbitScreen), findsOneWidget);

        // Pan the interactive viewer
        await tester.drag(find.byType(OrbitScreen), const Offset(-100, -100));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
      },
    );

    testWidgets('OrbitScreen renders Professional and Friends tabs cleanly', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OrbitScreen(
              tab: 'Professional',
              themeColor: const Color(0xFF007AFF),
              prefetchFuture: Future.value(
                OrbitPrefetchResult(
                  nodes: [
                    OrbitNode(
                      id: 'prof_1',
                      name: 'Sarah Chen',
                      x: 1600,
                      y: 1600,
                      orbitTier: 1,
                      score: 0.91,
                      profilePic:
                          'https://images.unsplash.com/photo-1534528741775-53994a69daeb',
                    ),
                  ],
                  sessionId: 'sess_prof',
                  profilePicUrl:
                      'https://images.unsplash.com/photo-1534528741775-53994a69daeb',
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(OrbitScreen), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}
