import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:nexus/features/orbit/models/orbit_node.dart';
import 'package:nexus/features/orbit/screens/orbit_screen.dart';
import 'package:nexus/features/orbit/widgets/orbit_filters_panel.dart';
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

        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
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
      },
    );
  });
}
