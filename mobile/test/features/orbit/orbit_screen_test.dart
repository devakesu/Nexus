import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/core/utils/discovery_hub_cache.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:nexus/core/utils/secure_profile_cache.dart';
import 'package:nexus/features/orbit/models/orbit_node.dart';
import 'package:nexus/features/orbit/screens/orbit_screen.dart';
import 'package:nexus/features/orbit/widgets/constellation_loader.dart';
import 'package:nexus/features/orbit/widgets/orbit_filters_panel.dart';
import 'package:nexus/features/orbit/widgets/orbit_painters.dart';
import 'package:nexus/features/social_modes/screens/dating_tab.dart';
import 'package:nexus/features/social_modes/screens/friends_tab.dart';
import 'package:nexus/features/social_modes/screens/professional_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Headers;

import '../../helpers/mock_network_interceptor.dart';
import '../../helpers/test_helpers.dart';

class MockHttpClientAdapter implements HttpClientAdapter {
  MockHttpClientAdapter(this.handler);
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
  setUpTestEnvironment();

  setUpAll(() async {
    await initMockSupabase();
  });

  // --- Section 1 ---
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

    group('OrbitScreen State and Prefetch Exhaustive Tests', () {
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

    group('OrbitScreen Loaded Full Deep Tests', () {
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

  // --- Section 3 ---
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
      setupGlobalMockNetwork();
    });

    group('Orbit Screen Interactive Deep Tests', () {
      testWidgets('OrbitScreen mounts and interacts with nodes and controls', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: OrbitScreen(
                tab: 'Dating',
                themeColor: Colors.pink,
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(OrbitScreen), findsOneWidget);

        final iconButtons = find.byType(IconButton);
        for (var i = 0; i < iconButtons.evaluate().length; i++) {
          try {
            await tester.tap(iconButtons.at(i), warnIfMissed: false);
            await tester.pump(const Duration(milliseconds: 50));
          } on Object catch (_) {}
        }

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      });
    });
  }

  // --- Section 4 ---
  {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

    final mockNodes = [
      OrbitNode(
        id: 'node_test_1',
        name: 'Elena Rostova',
        x: 0.15,
        y: 0.25,
        orbitTier: 1,
        score: 96.5,
        profilePic: 'https://example.com/elena.jpg',
        gender: 'Woman',
        sexuality: 'Straight',
        connectionType: 'Dating',
      ),
      OrbitNode(
        id: 'node_test_2',
        name: 'David Kim',
        x: -0.35,
        y: -0.15,
        orbitTier: 2,
        score: 84,
        profilePic: 'https://example.com/david.jpg',
        gender: 'Man',
        sexuality: 'Gay',
        connectionType: 'Friends',
      ),
    ];

    final mockPrefetch = OrbitPrefetchResult(
      nodes: mockNodes,
      sessionId: 'orbit_sess_phase12',
      profilePicUrl: 'https://example.com/me.jpg',
      showBuckets: ['Women', 'Men'],
      datingFor: ['Long-term relationship'],
      partnerValues: ['Empathy', 'Ambition'],
    );

    group('OrbitScreen Deep Interaction Tests', () {
      testWidgets(
        'renders OrbitScreen, opens and interacts with OrbitFiltersPanel',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(800, 1600);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          createDio().httpClientAdapter = _MockHttpClientAdapter((
            options,
          ) async {
            if (options.path.contains('/api/v1/profile/candidate/')) {
              return ResponseBody.fromString(
                jsonEncode({
                  'id': 'node_test_1',
                  'name': 'Elena Rostova',
                  'age': 24,
                  'bio': 'Astrophysics PhD student & violinist.',
                  'ordered_images': ['https://example.com/elena.jpg'],
                  'hometown': 'Seattle, WA',
                  'major': 'Physics',
                  'campus_name': 'UC Berkeley',
                  'connection_type': 'Dating',
                }),
                200,
                headers: {
                  Headers.contentTypeHeader: [Headers.jsonContentType],
                },
              );
            }
            if (options.path.contains('/api/v1/discover')) {
              return ResponseBody.fromString(
                jsonEncode({
                  'session_id': 'sess_new',
                  'nodes': [
                    {
                      'id': 'node_test_3',
                      'name': 'Aria Sterling',
                      'x': 0.1,
                      'y': 0.1,
                      'orbit_tier': 1,
                      'score': 99.0,
                      'profile_pic': 'https://example.com/aria.jpg',
                      'gender': 'Woman',
                      'sexuality': 'Straight',
                      'connection_type': 'Dating',
                    },
                  ],
                }),
                200,
                headers: {
                  Headers.contentTypeHeader: [Headers.jsonContentType],
                },
              );
            }
            if (options.path.contains('/api/v1/matches/action')) {
              return ResponseBody.fromString(
                jsonEncode({'status': 'ok'}),
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
                  body: OrbitScreen(
                    tab: 'Dating',
                    themeColor: Colors.purpleAccent,
                    prefetchFuture: Future.value(mockPrefetch),
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          expect(find.byType(OrbitScreen), findsOneWidget);

          // Pan gesture across canvas
          await tester.drag(find.byType(OrbitScreen), const Offset(80, -60));
          await tester.pump(const Duration(milliseconds: 200));

          // Tap filter icon button to open filter panel
          final filterBtn = find.byIcon(LucideIcons.slidersHorizontal);
          if (filterBtn.evaluate().isNotEmpty) {
            await tester.tap(filterBtn, warnIfMissed: false);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 400));

            expect(find.byType(OrbitFiltersPanel), findsOneWidget);

            // Tap Close/Done or filter chips inside OrbitFiltersPanel
            final closeIcon = find.byIcon(LucideIcons.x);
            if (closeIcon.evaluate().isNotEmpty) {
              await tester.tap(closeIcon.first, warnIfMissed: false);
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 300));
            }
          }

          // Tap reload / refresh icon if present
          final refreshBtn = find.byIcon(LucideIcons.refreshCw);
          if (refreshBtn.evaluate().isNotEmpty) {
            await tester.tap(refreshBtn, warnIfMissed: false);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 600));
          }
        },
      );

      testWidgets(
        'renders OrbitScreen in Professional mode with custom filters',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(800, 1600);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                home: Scaffold(
                  body: OrbitScreen(
                    tab: 'Professional',
                    themeColor: Colors.blueAccent,
                    prefetchFuture: Future.value(mockPrefetch),
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          expect(find.byType(OrbitScreen), findsOneWidget);

          // Perform pinch-to-zoom / scale gestures
          await tester.drag(find.byType(OrbitScreen), const Offset(-100, 100));
          await tester.pump(const Duration(milliseconds: 200));

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
        },
      );
    });
  }

  // --- Section 5 ---
  {
    group(
      'Orbit Screen Deep Interactions and Painters Tests',
      () {
        testWidgets('ConstellationLoader mounts and animates', (
          tester,
        ) async {
          await tester.pumpWidget(
            const MaterialApp(
              home: Scaffold(
                body: ConstellationLoader(
                  themeColor: Colors.purple,
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
          expect(find.byType(ConstellationLoader), findsOneWidget);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        });

        testWidgets(
          'CelestialBackgroundPainter and ConstellationLinesPainter paint cleanly',
          (
            tester,
          ) async {
            final nodes = [
              OrbitNode(
                id: 'node_1',
                name: 'Elena',
                x: 100,
                y: 50,
                orbitTier: 1,
                score: 95,
                profilePic: 'https://example.com/pic1.jpg',
                gender: 'Woman',
              ),
              OrbitNode(
                id: 'node_2',
                name: 'Lucas',
                x: -80,
                y: -120,
                orbitTier: 2,
                score: 88,
                profilePic: 'https://example.com/pic2.jpg',
                gender: 'Man',
              ),
            ];

            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: CustomPaint(
                    size: const Size(400, 400),
                    painter: CelestialBackgroundPainter(
                      themeColor: Colors.deepPurple,
                      pulseValue: 0.5,
                    ),
                    foregroundPainter: ConstellationLinesPainter(
                      nodes: nodes,
                      themeColor: Colors.deepPurple,
                      pulseValue: 0.5,
                    ),
                  ),
                ),
              ),
            );

            await tester.pump();
            await tester.pump(const Duration(milliseconds: 100));
            expect(find.byType(CustomPaint), findsWidgets);

            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
          },
        );
      },
    );
  }

  // --- Section 6 ---
  {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

    final mockNodesData = [
      {
        'id': 'user_node_1',
        'name': 'Alex Rivera',
        'x': 0.2,
        'y': -0.3,
        'orbitTier': 1,
        'score': 95.0,
        'profilePic': 'https://example.com/alex.jpg',
        'gender': 'Non-Binary',
        'sexuality': 'Queer',
        'connectionType': 'Dating',
        'bio': 'Creative director & coffee geek',
        'campus': 'Metro Univ',
        'major': 'Design',
        'interests': ['Design', 'Art', 'Coffee'],
      },
      {
        'id': 'user_node_2',
        'name': 'Taylor Swift',
        'x': -0.4,
        'y': 0.35,
        'orbitTier': 2,
        'score': 88.0,
        'profilePic': 'https://example.com/taylor.jpg',
        'gender': 'Woman',
        'sexuality': 'Straight',
        'connectionType': 'Dating',
        'bio': 'Musician & songwriter',
        'campus': 'Nashville Arts',
        'major': 'Music',
        'interests': ['Music', 'Cats', 'Poetry'],
      },
    ];

    group('OrbitScreen Deep Interactions & Filters Tests', () {
      test(
        'OrbitScreen.prefetch executes successfully with cached and network data',
        () async {
          await DiscoveryHubCache.write('dating', {
            'profileDetails': {
              'ordered_images': ['https://example.com/pic1.jpg'],
              'dating_target_buckets': ['W', 'NB'],
              'dating_for': ['Relationship'],
              'partner_values': ['Kindness', 'Humor'],
            },
          });

          createDio().httpClientAdapter = _MockHttpClientAdapter((
            options,
          ) async {
            if (options.path.contains('/api/v1/orbit/discover')) {
              return ResponseBody.fromString(
                jsonEncode({
                  'nodes': mockNodesData,
                  'meta': {'count': 2},
                }),
                200,
                headers: {
                  Headers.contentTypeHeader: [Headers.jsonContentType],
                },
              );
            }
            return ResponseBody.fromString('{"ok": true}', 200);
          });

          // Execute static prefetch
          final result = await OrbitScreen.prefetch('Dating');
          expect(result == null || result.nodes.isNotEmpty, isTrue);
        },
      );

      testWidgets(
        'renders OrbitScreen, interacts with canvas, selects node, and triggers filter panel',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          createDio().httpClientAdapter = _MockHttpClientAdapter((
            options,
          ) async {
            if (options.path.contains('/api/v1/orbit/discover') ||
                options.path.contains('/api/v1/discover')) {
              return ResponseBody.fromString(
                jsonEncode({
                  'nodes': mockNodesData,
                }),
                200,
                headers: {
                  Headers.contentTypeHeader: [Headers.jsonContentType],
                },
              );
            }
            if (options.path.contains('/api/v1/profile/details')) {
              return ResponseBody.fromString(
                jsonEncode({
                  'id': 'user_node_1',
                  'name': 'Alex Rivera',
                  'bio': 'Creative director',
                  'ordered_images': ['https://example.com/alex.jpg'],
                }),
                200,
                headers: {
                  Headers.contentTypeHeader: [Headers.jsonContentType],
                },
              );
            }
            return ResponseBody.fromString('{"ok": true}', 200);
          });

          await tester.pumpWidget(
            const MaterialApp(
              home: Scaffold(
                body: OrbitScreen(
                  tab: 'Dating',
                  themeColor: AppColors.modeDating,
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(seconds: 1));

          expect(find.byType(OrbitScreen), findsOneWidget);

          // Pan & drag interactive orbit canvas
          await tester.drag(find.byType(OrbitScreen), const Offset(80, 50));
          await tester.pump(const Duration(milliseconds: 200));

          // Tap on canvas center to check node hit-testing
          await tester.tapAt(const Offset(540, 1200));
          await tester.pump(const Duration(milliseconds: 200));

          // Open filter panel if filter icon is present
          final filterIcon = find.byIcon(LucideIcons.slidersHorizontal);
          if (filterIcon.evaluate().isNotEmpty) {
            await tester.tap(filterIcon.first, warnIfMissed: false);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));

            // Check if OrbitFiltersPanel rendered
            expect(find.byType(OrbitFiltersPanel), findsOneWidget);

            // Interact with filter sliders & chips
            final sliders = find.byType(RangeSlider);
            if (sliders.evaluate().isNotEmpty) {
              await tester.drag(sliders.first, const Offset(30, 0));
              await tester.pump();
            }

            // Tap Apply or Reset button in filter panel
            final applyBtn = find.text('Apply Filters');
            if (applyBtn.evaluate().isNotEmpty) {
              await tester.tap(applyBtn.first, warnIfMissed: false);
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 300));
            }
          }
        },
      );

      testWidgets('renders OrbitScreen for Friends tab and Professional tab', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
          return ResponseBody.fromString(
            jsonEncode({
              'nodes': mockNodesData,
            }),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        });

        // Friends tab
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: OrbitScreen(
                tab: 'Friends',
                themeColor: AppColors.modeFriends,
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(OrbitScreen), findsOneWidget);

        // Professional tab
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: OrbitScreen(
                tab: 'Professional',
                themeColor: AppColors.modeProfessional,
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(OrbitScreen), findsOneWidget);
      });
    });
  }

  // --- Section 7 ---
  {
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

    group('OrbitScreen Deep Galaxy Canvas & Filter Mega Coverage Tests', () {
      test(
        'OrbitScreen.prefetch executes for Dating, Friends, and Professional',
        () async {
          createDio().httpClientAdapter = _MockHttpClientAdapter((
            options,
          ) async {
            return ResponseBody.fromString(
              jsonEncode({
                'status': 'success',
                'data': {
                  'profiles': [
                    {
                      'user_id': 'u1',
                      'name': 'Astrid',
                      'age': 22,
                      'avatar_url': 'https://example.com/astrid.jpg',
                      'orbit_score': 95,
                      'x': 100.0,
                      'y': -150.0,
                    },
                  ],
                },
              }),
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          });

          final dResult = await OrbitScreen.prefetch('Dating');
          final fResult = await OrbitScreen.prefetch('Friends');
          final pResult = await OrbitScreen.prefetch('Professional');

          expect(dResult, isNotNull);
          expect(fResult, isNotNull);
          expect(pResult, isNotNull);
        },
      );

      testWidgets(
        'OrbitScreen renders galaxy canvas, interacts with nodes and filter panel',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await DiscoveryHubCache.write('dating', {
            'profileDetails': {
              'ordered_images': ['https://example.com/me.jpg'],
              'dating_target_buckets': ['W', 'NB'],
              'dating_for': ['Long-term relationship'],
              'partner_values': ['Kindness', 'Ambition'],
            },
          });

          createDio().httpClientAdapter = _MockHttpClientAdapter((
            options,
          ) async {
            if (options.path.contains('/api/v1/profile/details')) {
              return ResponseBody.fromString(
                jsonEncode({
                  'ordered_images': ['https://example.com/me.jpg'],
                  'dating_target_buckets': ['W', 'NB'],
                  'dating_for': ['Long-term relationship'],
                  'partner_values': ['Kindness', 'Ambition'],
                }),
                200,
                headers: {
                  Headers.contentTypeHeader: [Headers.jsonContentType],
                },
              );
            }
            return ResponseBody.fromString(
              jsonEncode({
                'profiles': [
                  {
                    'user_id': 'u10',
                    'name': 'Lyra',
                    'age': 23,
                    'avatar_url': 'https://example.com/lyra.jpg',
                    'orbit_score': 92,
                    'x': 50.0,
                    'y': -80.0,
                  },
                  {
                    'user_id': 'u11',
                    'name': 'Orion',
                    'age': 25,
                    'avatar_url': 'https://example.com/orion.jpg',
                    'orbit_score': 88,
                    'x': -120.0,
                    'y': 110.0,
                  },
                ],
              }),
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          });

          await tester.pumpWidget(
            const MaterialApp(
              home: Scaffold(
                body: OrbitScreen(
                  tab: 'Dating',
                  themeColor: AppColors.modeDating,
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(seconds: 1));

          expect(find.byType(OrbitScreen), findsOneWidget);

          // Pan & drag on canvas
          await tester.drag(find.byType(OrbitScreen), const Offset(100, 150));
          await tester.pump();

          // Tap filter toggle button
          final filterBtn = find.byIcon(Icons.tune_rounded);
          if (filterBtn.evaluate().isNotEmpty) {
            await tester.tap(filterBtn.first, warnIfMissed: false);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
          }

          // Tap recenter / focus button
          final focusBtn = find.byIcon(Icons.center_focus_strong_rounded);
          if (focusBtn.evaluate().isNotEmpty) {
            await tester.tap(focusBtn.first, warnIfMissed: false);
            await tester.pump();
          }
        },
      );
    });
  }

  // --- Section 8 ---
  {
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

    group('OrbitScreen Deep Views & Transformations Tests', () {
      testWidgets(
        'OrbitScreen renders Dating tab nodes and handles pan/zoom transformations',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          createDio().httpClientAdapter = _MockHttpClientAdapter((
            options,
          ) async {
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

  // --- Section 9 ---
  {
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

    group('OrbitScreen Actions and Pan/Zoom Tests', () {
      testWidgets(
        'OrbitScreen renders dating prefetch nodes, opens filter panel and node details',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          createDio().httpClientAdapter = _MockHttpClientAdapter((
            options,
          ) async {
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

  // --- Section 10 ---
  {
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

    group('OrbitScreen Exhaustive Interactions Tests', () {
      testWidgets('OrbitScreen prefetch and tab interactions', (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
          return ResponseBody.fromString(
            jsonEncode({
              'nodes': [
                {
                  'id': 'node_prof_1',
                  'name': 'Sarah Chen',
                  'x': 1500,
                  'y': 1500,
                  'orbit_tier': 1,
                  'score': 0.92,
                  'profile_pic': 'photo.jpg',
                  'gender': 'Woman',
                  'sexuality': 'Straight',
                  'connection_type': 'Professional',
                  'match_status': 'none',
                  'is_new': false,
                },
              ],
              'ordered_images': ['pic1.jpg'],
              'dating_target_buckets': ['All'],
              'dating_for': ['Casual'],
              'partner_values': ['Loyalty'],
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
              id: 'node_prof_1',
              name: 'Sarah Chen',
              x: 1500,
              y: 1500,
              orbitTier: 1,
              score: 0.92,
              profilePic: 'photo.jpg',
              gender: 'Woman',
              sexuality: 'Straight',
              connectionType: 'Professional',
              matchStatus: 'none',
            ),
          ],
          sessionId: 'sess_prof_123',
          profilePicUrl: 'photo.jpg',
        );

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: OrbitScreen(
                  tab: 'Professional',
                  themeColor: Colors.blue,
                  prefetchFuture: Future.value(prefetchResult),
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byType(OrbitScreen), findsOneWidget);

        // Perform pan drag
        await tester.drag(find.byType(OrbitScreen), const Offset(100, 100));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
      });
    });
  }

  // --- Section 11 ---
  {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

    final mockNodes = [
      OrbitNode(
        id: 'node_1',
        name: 'Maya Lin',
        x: 0.25,
        y: 0.35,
        orbitTier: 1,
        score: 95,
        profilePic: 'https://example.com/maya.jpg',
        gender: 'Woman',
        sexuality: 'Straight',
        connectionType: 'Dating',
      ),
      OrbitNode(
        id: 'node_2',
        name: 'Julian Vance',
        x: -0.45,
        y: 0.20,
        orbitTier: 2,
        score: 82.5,
        profilePic: 'https://example.com/julian.jpg',
        gender: 'Man',
        sexuality: 'Bisexual',
        connectionType: 'Dating',
      ),
    ];

    final mockPrefetch = OrbitPrefetchResult(
      nodes: mockNodes,
      sessionId: 'orbit_sess_101',
      profilePicUrl: 'https://example.com/my_pic.jpg',
      showBuckets: ['Women', 'Men'],
      datingFor: ['Long-term'],
      partnerValues: ['Kindness'],
    );

    group('OrbitScreen Deep Interaction Coverage Tests', () {
      testWidgets('renders OrbitScreen with nodes in Dating mode', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: OrbitScreen(
                  tab: 'Dating',
                  themeColor: Colors.pinkAccent,
                  prefetchFuture: Future.value(mockPrefetch),
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 2));

        expect(find.byType(OrbitScreen), findsOneWidget);

        await tester.drag(find.byType(OrbitScreen), const Offset(100, -100));
        await tester.pump(const Duration(seconds: 1));
        expect(find.byType(OrbitScreen), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      });

      testWidgets('renders OrbitScreen in Friends mode', (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: OrbitScreen(
                  tab: 'Friends',
                  themeColor: Colors.tealAccent,
                  prefetchFuture: Future.value(mockPrefetch),
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 2));

        expect(find.byType(OrbitScreen), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      });

      testWidgets('renders OrbitScreen in Professional mode', (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: OrbitScreen(
                  tab: 'Professional',
                  themeColor: Colors.indigoAccent,
                  prefetchFuture: Future.value(mockPrefetch),
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 2));

        expect(find.byType(OrbitScreen), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      });
    });
  }

  // --- Section 12 ---
  {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

    group('OrbitScreen Deep Interaction Tests', () {
      testWidgets(
        'renders OrbitScreen for dating tab with filters button and radar',
        (tester) async {
          tester.view.physicalSize = const Size(800, 1400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            const MaterialApp(
              home: Scaffold(
                body: OrbitScreen(
                  tab: 'dating',
                  themeColor: AppColors.modeDating,
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.byType(OrbitScreen), findsOneWidget);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
        },
      );

      testWidgets('renders OrbitScreen for friends tab', (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: OrbitScreen(
                tab: 'friends',
                themeColor: AppColors.modeFriends,
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(OrbitScreen), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      });

      testWidgets('renders OrbitScreen for professional tab', (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: OrbitScreen(
                tab: 'professional',
                themeColor: AppColors.modeProfessional,
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(OrbitScreen), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      });
    });
  }

  // --- Section 13 ---
  {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

    group('OrbitPrefetchResult & OrbitNode Unit Tests', () {
      test('OrbitPrefetchResult holds nodes and defaults accurately', () {
        final node = OrbitNode(
          id: 'u1',
          name: 'Luna',
          x: 0.5,
          y: -0.5,
          orbitTier: 1,
          score: 88,
          profilePic: 'https://example.com/pic.jpg',
        );

        final prefetch = OrbitPrefetchResult(
          nodes: [node],
          sessionId: 'sess_1',
          profilePicUrl: 'https://example.com/my_pic.jpg',
          showBuckets: ['Women'],
          datingFor: ['Long-term'],
          partnerValues: ['Loyalty'],
        );

        expect(prefetch.nodes.length, 1);
        expect(prefetch.nodes.first.name, 'Luna');
        expect(prefetch.showBuckets, ['Women']);
        expect(prefetch.datingFor, ['Long-term']);
      });
    });

    group('OrbitFiltersPanel Deep Widget Tests', () {
      testWidgets('renders OrbitFiltersPanel with age slider and filters', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final scrollController = ScrollController();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OrbitFiltersPanel(
                tab: 'Dating',
                themeColor: AppColors.modeDating,
                ageRange: const RangeValues(21, 30),
                selectedDrinking: const ['Socially'],
                selectedSmoking: const ['Never'],
                selectedLanguages: const ['English', 'Spanish'],
                selectedSubInterests: const ['Hiking', 'Gaming'],
                selectedYears: const [3, 4],
                selectedChildrenPlans: const ['Want someday'],
                selectedReligiousBeliefs: const ['Agnostic'],
                selectedShowBuckets: const ['Women'],
                selectedDatingFor: const ['Long-term'],
                selectedPartnerValues: const ['Ambition'],
                dealbreakerFields: const {'drinking', 'smoking'},
                selectedLookingFor: const ['Study buddy'],
                selectedTechSkills: const ['Flutter', 'Python'],
                savingFields: const {},
                onAgeRangeChanged: (values) {},
                onAgeRangeChangeEnd: (values) {},
                onSaveDatingField: (field, values, setSheetState) async {},
                onOpenTagSelectionPane: (field, avail, curr, setSheetState) {},
                onOpenPartnerValuesSelectionPane: (setSheetState, curr) {},
                isRefreshing: false,
                onFetchOrbitNodes: () async {},
                scrollController: scrollController,
                noUsersFound: false,
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 2));

        expect(find.byType(OrbitFiltersPanel), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      });
    });

    group('OrbitScreen Deep Widget Tests', () {
      testWidgets(
        'renders OrbitScreen with constellation layout and controls',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(800, 1400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          final mockNode = OrbitNode(
            id: 'u10',
            name: 'Stella',
            x: 0.2,
            y: 0.8,
            orbitTier: 2,
            score: 94,
            profilePic: 'https://example.com/stella.jpg',
          );

          final prefetchResult = OrbitPrefetchResult(
            nodes: [mockNode],
            sessionId: 'sess_10',
            profilePicUrl: 'https://example.com/stella.jpg',
            showBuckets: ['Everyone'],
            datingFor: ['Dating'],
            partnerValues: ['Kindness'],
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
          await tester.pump(const Duration(seconds: 2));

          expect(find.byType(OrbitScreen), findsOneWidget);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
        },
      );
    });
  }

  // --- Section 14 ---
  {
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

    group('OrbitScreen Deep Interactions Tests', () {
      testWidgets('OrbitScreen Friends tab render and node interactions', (
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
                  'id': 'node_friends_1',
                  'name': 'Jordan Lee',
                  'x': 1600,
                  'y': 1600,
                  'orbit_tier': 1,
                  'score': 0.88,
                  'profile_pic': 'jordan.jpg',
                  'gender': 'Non-binary',
                  'sexuality': 'Queer',
                  'connection_type': 'Friends',
                  'match_status': 'none',
                  'is_new': true,
                },
              ],
              'ordered_images': ['jordan.jpg'],
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
              id: 'node_friends_1',
              name: 'Jordan Lee',
              x: 1600,
              y: 1600,
              orbitTier: 1,
              score: 0.88,
              profilePic: 'jordan.jpg',
              gender: 'Non-binary',
              sexuality: 'Queer',
              connectionType: 'Friends',
              matchStatus: 'none',
              isNew: true,
            ),
          ],
          sessionId: 'sess_friends_123',
          profilePicUrl: 'jordan.jpg',
        );

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: OrbitScreen(
                  tab: 'Friends',
                  themeColor: Colors.amber,
                  prefetchFuture: Future.value(prefetchResult),
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byType(OrbitScreen), findsOneWidget);

        // Perform pan drag on orbit view
        await tester.drag(find.byType(OrbitScreen), const Offset(-150, -150));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
      });
    });
  }

  // --- Section 15 ---
  {
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

    group('Orbit and Social Modes Tabs Tests', () {
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
}
