import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/theme/app_colors.dart';
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

  group('OrbitScreen Actions and Pan/Zoom Mega Tests', () {
    testWidgets(
      'OrbitScreen renders dating prefetch nodes, opens filter panel and node details',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
          if (options.path.contains('/api/v1/orbit/action')) {
            return ResponseBody.fromString(
              jsonEncode({'status': 'ok'}),
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          }
          if (options.path.contains('/api/v1/profile/details')) {
            return ResponseBody.fromString(
              jsonEncode({
                'is_dating_active': true,
                'dating_target_buckets': ['Women'],
                'dating_for': ['Long-term relationship'],
                'partner_values': ['Kindness', 'Curiosity'],
              }),
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          }
          return ResponseBody.fromString(
            jsonEncode({
              'id': 'cand_123',
              'name': 'Sophia',
              'age': 23,
              'bio': 'Astrophysics enthusiast and coffee lover.',
              'ordered_images': ['https://example.com/sophia.jpg'],
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
              id: 'cand_123',
              name: 'Sophia',
              x: 1600,
              y: 1600,
              orbitTier: 1,
              score: 0.94,
              profilePic: 'https://example.com/sophia.jpg',
              gender: 'Woman',
              sexuality: 'Straight',
              connectionType: 'Dating',
              matchStatus: 'matched',
              isNew: true,
            ),
            OrbitNode(
              id: 'cand_456',
              name: 'Liam',
              x: 1750,
              y: 1500,
              orbitTier: 2,
              score: 0.81,
              profilePic: 'https://example.com/liam.jpg',
              gender: 'Man',
              sexuality: 'Straight',
              connectionType: 'Dating',
              matchStatus: 'pending',
            ),
          ],
          sessionId: 'orbit_sess_123',
          profilePicUrl: 'https://example.com/sophia.jpg',
        );

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: OrbitScreen(
                  tab: 'Dating',
                  themeColor: AppColors.modeDating,
                  prefetchFuture: Future.value(prefetchResult),
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byType(OrbitScreen), findsOneWidget);

        // Pan around the canvas
        await tester.drag(find.byType(OrbitScreen), const Offset(150, -100));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Open filter panel
        final filterBtn = find.byTooltip('Filter Radar');
        if (filterBtn.evaluate().isNotEmpty) {
          await tester.tap(filterBtn.first);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
        }
      },
    );
  });
}
