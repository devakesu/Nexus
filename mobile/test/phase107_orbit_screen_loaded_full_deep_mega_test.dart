import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/core/utils/discovery_hub_cache.dart';
import 'package:nexus/core/utils/secure_profile_cache.dart';
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

  final fullMockProfile = {
    'name': 'Alex Rivera',
    'birth_date': '1998-05-15',
    'gender': 'Non-binary',
    'bio': 'Software engineer and climber in SF.',
    'ordered_images': [
      'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=500',
    ],
    'interests': ['Coding', 'Climbing'],
    'dating_target_buckets': ['Women'],
    'dating_for': ['Relationship'],
    'partner_values': ['Honesty'],
  };

  setUpAll(() async {
    ConsentCacheManager.safetyConsentGranted = true;
    ConsentCacheManager.specialCategoryConsentGranted = true;
    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        publishableKey: 'mock-anon-key',
      );
    } on Exception catch (_) {}
    await SecureProfileCache.write(fullMockProfile);
    await DiscoveryHubCache.write('dating', {
      'profileDetails': fullMockProfile,
    });
  });

  group('Phase 107 - OrbitScreen Loaded Full Deep Mega Tests', () {
    testWidgets(
      'OrbitScreen renders with prefetch result containing multiple nodes and interacts',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final nodes = [
          OrbitNode(
            id: 'n1',
            name: 'Sarah',
            x: 100,
            y: 200,
            orbitTier: 1,
            score: 92,
            profilePic:
                'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=500',
          ),
          OrbitNode(
            id: 'n2',
            name: 'Jordan',
            x: -150,
            y: 150,
            orbitTier: 2,
            score: 85,
            profilePic:
                'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=500',
          ),
        ];

        final prefetch = OrbitPrefetchResult(
          nodes: nodes,
          sessionId: 'sess-123',
          profilePicUrl:
              'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=500',
          showBuckets: const ['Women'],
          datingFor: const ['Relationship'],
          partnerValues: const ['Honesty'],
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OrbitScreen(
                tab: 'Dating',
                themeColor: Colors.pink,
                prefetchFuture: Future.value(prefetch),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(OrbitScreen), findsOneWidget);

        // Pan/Zoom around the orbit canvas to trigger interaction handling
        final center = tester.getCenter(find.byType(OrbitScreen));
        await tester.dragFrom(center, const Offset(100, 100));
        await tester.pump(const Duration(milliseconds: 100));

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      },
    );
  });
}
