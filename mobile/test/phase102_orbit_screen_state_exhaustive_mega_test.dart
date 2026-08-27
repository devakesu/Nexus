import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/features/orbit/models/orbit_node.dart';
import 'package:nexus/features/orbit/screens/orbit_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

  group('Phase 102 - OrbitScreen State and Prefetch Exhaustive Mega Tests', () {
    test('OrbitPrefetchResult model instantiation and getters', () {
      final sampleNodes = <OrbitNode>[
        OrbitNode(
          id: 'n1',
          name: 'Sarah',
          x: 100,
          y: 200,
          orbitTier: 1,
          score: 92,
          profilePic: 'https://example.com/sarah.png',
        ),
      ];

      final prefetch = OrbitPrefetchResult(
        nodes: sampleNodes,
        sessionId: 'sess-123',
        profilePicUrl: 'https://example.com/my-pic.png',
        showBuckets: const ['Women'],
        datingFor: const ['Long-term'],
        partnerValues: const ['Honesty', 'Kindness'],
      );

      expect(prefetch.nodes.length, 1);
      expect(prefetch.sessionId, 'sess-123');
      expect(prefetch.profilePicUrl, 'https://example.com/my-pic.png');
      expect(prefetch.showBuckets.length, 1);
      expect(prefetch.datingFor.length, 1);
      expect(prefetch.partnerValues.length, 2);
    });

    testWidgets('OrbitScreen mounts with prefetchFuture', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final prefetchFuture = Future.value(
        OrbitPrefetchResult(
          nodes: [
            OrbitNode(
              id: 'n1',
              name: 'Sarah',
              x: 100,
              y: 200,
              orbitTier: 1,
              score: 92,
              profilePic: 'https://example.com/sarah.png',
            ),
          ],
          sessionId: 'sess-123',
          profilePicUrl: 'https://example.com/my-pic.png',
          showBuckets: const ['Women'],
          datingFor: const ['Long-term'],
          partnerValues: const ['Honesty'],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OrbitScreen(
              tab: 'Dating',
              themeColor: Colors.pink,
              prefetchFuture: prefetchFuture,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(OrbitScreen), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
