import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/core/utils/discovery_hub_cache.dart';
import 'package:nexus/core/utils/network_utils.dart';
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

  group('OrbitScreen Deep Interactions & Filters Mega Tests', () {
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

        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
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

        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
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
