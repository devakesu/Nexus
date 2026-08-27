import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/features/orbit/models/orbit_node.dart';
import 'package:nexus/features/orbit/screens/orbit_screen.dart';
import 'package:nexus/features/social_modes/screens/dating_tab.dart';
import 'package:nexus/features/social_modes/screens/friends_tab.dart';
import 'package:nexus/features/social_modes/screens/professional_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  group('Phase 72 - Orbit and Social Modes Tabs Mega Tests', () {
    testWidgets(
      'OrbitScreen renders all three modes with populated prefetch nodes',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        for (final mode in ['Dating', 'Friends', 'Professional']) {
          final prefetch = OrbitPrefetchResult(
            nodes: [
              OrbitNode(
                id: 'node_${mode}_1',
                name: 'Sample User',
                x: 1600,
                y: 1600,
                orbitTier: 1,
                score: 0.95,
                profilePic: 'pic.jpg',
                gender: 'Woman',
                sexuality: 'Straight',
                connectionType: mode,
                matchStatus: 'none',
                isNew: true,
              ),
            ],
            sessionId: 'sess_123',
            profilePicUrl: 'pic.jpg',
          );

          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                home: Scaffold(
                  body: OrbitScreen(
                    tab: mode,
                    themeColor: mode == 'Dating'
                        ? Colors.pink
                        : (mode == 'Friends' ? Colors.amber : Colors.blue),
                    prefetchFuture: Future.value(prefetch),
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          expect(find.byType(OrbitScreen), findsOneWidget);

          await tester.drag(find.byType(OrbitScreen), const Offset(50, 50));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
        }
      },
    );

    testWidgets(
      'Social Modes tabs DatingTab, FriendsTab, and ProfessionalTab render and interact',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        // 1. DatingTab
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: DatingTab(
                  onOpenOrbit: (mode, color) {},
                  onNavigateToTab: (index, [target]) {},
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(DatingTab), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        // 2. FriendsTab
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: FriendsTab(
                  onOpenOrbit: (mode, color) {},
                  onNavigateToTab: (index, [target]) {},
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(FriendsTab), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        // 3. ProfessionalTab
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: ProfessionalTab(
                  onOpenOrbit: (mode, color) {},
                  onNavigateToTab: (index, [target]) {},
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(ProfessionalTab), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  });
}
