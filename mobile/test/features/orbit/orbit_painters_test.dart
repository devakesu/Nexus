import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/features/orbit/models/orbit_node.dart';
import 'package:nexus/features/orbit/widgets/constellation_loader.dart';
import 'package:nexus/features/orbit/widgets/orbit_interactive.dart';
import 'package:nexus/features/orbit/widgets/orbit_painters.dart';
import 'package:nexus/features/orbit/widgets/orbit_ui_helpers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/test_helpers.dart';

void main() {
  setUpTestEnvironment();

  setUpAll(() async {
    await initMockSupabase();
  });

  // --- Section 1 ---
  {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

    group('OrbitNode & OrbitPrefetchResult Model Tests', () {
      test('OrbitNode serialization, deserialization, and copyWith', () {
        final json = {
          'id': 'node_123',
          'name': 'Sarah Chen',
          'x': 120.5,
          'y': -85.2,
          'orbit_tier': 1,
          'score': 94.5,
          'profile_pic': 'https://example.com/pic.jpg',
          'gender': 'F',
          'sexuality': 'Straight',
          'connection_type': 'Long-term',
          'match_status': 'liked',
          'is_new': true,
        };

        final node = OrbitNode.fromJson(json);
        expect(node.id, 'node_123');
        expect(node.name, 'Sarah Chen');
        expect(node.x, 120.5);
        expect(node.y, -85.2);
        expect(node.orbitTier, 1);
        expect(node.score, 94.5);
        expect(node.profilePic, 'https://example.com/pic.jpg');
        expect(node.gender, 'F');
        expect(node.isNew, isTrue);

        final exported = node.toJson();
        expect(exported['id'], 'node_123');
        expect(exported['name'], 'Sarah Chen');
        expect(exported['score'], 94.5);

        final copied = node.copyWith(name: 'Sarah C.', score: 98);
        expect(copied.name, 'Sarah C.');
        expect(copied.score, 98.0);
        expect(copied.id, 'node_123');
      });

      test('OrbitPrefetchResult model fields', () {
        final prefetch = OrbitPrefetchResult(
          nodes: [
            OrbitNode(
              id: 'n1',
              name: 'Alex',
              x: 50,
              y: 50,
              orbitTier: 1,
              score: 80,
              profilePic: null,
            ),
          ],
          sessionId: 'session_abc',
          profilePicUrl: 'https://example.com/me.jpg',
          showBuckets: ['M', 'F'],
        );

        expect(prefetch.nodes.length, 1);
        expect(prefetch.sessionId, 'session_abc');
        expect(prefetch.profilePicUrl, 'https://example.com/me.jpg');
        expect(prefetch.showBuckets, contains('M'));
      });
    });

    group('Celestial & Constellation CustomPainters Tests', () {
      test('CelestialBackgroundPainter paint and shouldRepaint', () {
        final painter1 = CelestialBackgroundPainter(
          themeColor: AppColors.modeDating,
          pulseValue: 0.5,
        );
        final painter2 = CelestialBackgroundPainter(
          themeColor: AppColors.modeDating,
          pulseValue: 0.8,
        );
        final painter3 = CelestialBackgroundPainter(
          themeColor: AppColors.modeDating,
          pulseValue: 0.5,
        );

        expect(painter1.shouldRepaint(painter2), isTrue);
        expect(painter1.shouldRepaint(painter3), isFalse);

        final recorder = PictureRecorder();
        final canvas = Canvas(recorder);
        painter1.paint(canvas, const Size(400, 800));
        final picture = recorder.endRecording();
        expect(picture, isNotNull);
      });

      test('ConstellationLinesPainter paint and shouldRepaint', () {
        final nodes = [
          OrbitNode(
            id: 'n1',
            name: 'N1',
            x: 100,
            y: 100,
            orbitTier: 1,
            score: 90,
            profilePic: null,
          ),
          OrbitNode(
            id: 'n2',
            name: 'N2',
            x: -150,
            y: 50,
            orbitTier: 2,
            score: 85,
            profilePic: null,
          ),
          OrbitNode(
            id: 'n3',
            name: 'N3',
            x: 0,
            y: -200,
            orbitTier: 3,
            score: 75,
            profilePic: null,
          ),
        ];

        final painter1 = ConstellationLinesPainter(
          nodes: nodes,
          themeColor: AppColors.modeFriends,
          pulseValue: 0.3,
        );
        final painterEmpty = ConstellationLinesPainter(
          nodes: const [],
          themeColor: AppColors.modeFriends,
        );

        final recorder = PictureRecorder();
        final canvas = Canvas(recorder);
        painterEmpty.paint(canvas, const Size(400, 800));
        painter1.paint(canvas, const Size(400, 800));
        final picture = recorder.endRecording();
        expect(picture, isNotNull);
      });

      test(
        'OrbitGridPainter and DashedOrbitRingPainter paint and shouldRepaint',
        () {
          final gridPainter1 = OrbitGridPainter(
            themeColor: AppColors.modeProfessional,
            sweepValue: 0.2,
          );
          final gridPainter2 = OrbitGridPainter(
            themeColor: AppColors.modeProfessional,
            sweepValue: 0.6,
          );

          expect(gridPainter1.shouldRepaint(gridPainter2), isTrue);

          final ringPainter1 = DashedOrbitRingPainter(
            color: AppColors.pulsarPink,
          );
          final ringPainter2 = DashedOrbitRingPainter(color: Colors.white);
          expect(ringPainter1.shouldRepaint(ringPainter2), isTrue);

          final recorder = PictureRecorder();
          final canvas = Canvas(recorder);
          gridPainter1.paint(canvas, const Size(400, 800));
          ringPainter1.paint(canvas, const Size(100, 100));
          final picture = recorder.endRecording();
          expect(picture, isNotNull);
        },
      );
    });

    group('ConstellationLoader & Orbit UI Helpers Tests', () {
      testWidgets(
        'renders ConstellationLoader with pulsating animations and label',
        (tester) async {
          await tester.pumpWidget(
            const MaterialApp(
              home: Scaffold(
                body: ConstellationLoader(
                  themeColor: AppColors.modeDating,
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));

          expect(find.text('ALIGNING CONSTELLATIONS'), findsOneWidget);
          expect(find.byType(ConstellationLoader), findsOneWidget);
        },
      );

      testWidgets('renders OrbitEdgeFade on all edges', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  OrbitEdgeFade(alignment: Alignment.topCenter),
                  OrbitEdgeFade(alignment: Alignment.bottomCenter),
                  OrbitEdgeFade(alignment: Alignment.centerLeft),
                  OrbitEdgeFade(alignment: Alignment.centerRight),
                ],
              ),
            ),
          ),
        );

        await tester.pump();
        expect(find.byType(OrbitEdgeFade), findsNWidgets(4));
      });

      testWidgets('renders OrbitHeaderIconButton and handles tap', (
        tester,
      ) async {
        var iconTapped = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OrbitHeaderIconButton(
                icon: LucideIcons.slidersHorizontal,
                glowColor: AppColors.modeDating,
                semanticLabel: 'Filter orbits',
                onPressed: () => iconTapped = true,
              ),
            ),
          ),
        );

        await tester.pump();
        expect(find.byIcon(LucideIcons.slidersHorizontal), findsOneWidget);

        await tester.tap(find.byType(OrbitHeaderIconButton));
        await tester.pump();
        expect(iconTapped, isTrue);
      });

      testWidgets('renders InteractiveOrbitNode and triggers tap', (
        tester,
      ) async {
        var nodeTapped = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: InteractiveOrbitNode(
                onTap: () => nodeTapped = true,
                child: const Text('Orbit Node Avatar'),
              ),
            ),
          ),
        );

        await tester.pump();
        expect(find.text('Orbit Node Avatar'), findsOneWidget);

        await tester.tap(find.text('Orbit Node Avatar'));
        await tester.pump();
        expect(nodeTapped, isTrue);
      });
    });
  }

  // --- Section 2 ---
  {
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

    group('Orbit and Painters Deep Tests', () {
      testWidgets('ConstellationLoader renders smoothly and unmounts', (
        tester,
      ) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: ConstellationLoader(
                themeColor: Colors.pink,
                label: 'ALIGNING STARS',
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(find.byType(ConstellationLoader), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      });

      testWidgets(
        'CelestialBackgroundPainter and Orbit Painters paint cleanly',
        (
          tester,
        ) async {
          final painter = CelestialBackgroundPainter(
            themeColor: Colors.pink,
            pulseValue: 0.5,
          );
          expect(painter.themeColor, Colors.pink);
          expect(painter.pulseValue, 0.5);

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: CustomPaint(
                  painter: painter,
                  size: const Size(400, 800),
                ),
              ),
            ),
          );

          await tester.pump();
          expect(find.byType(CustomPaint), findsWidgets);
        },
      );
    });
  }
}
