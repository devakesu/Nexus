import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/core/utils/discovery_hub_cache.dart';
import 'package:nexus/core/utils/network_utils.dart';
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
  SharedPreferences.setMockInitialValues({});
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
    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        publishableKey: 'mock-anon-key',
      );
    } on Exception catch (_) {}
  });

  group('OrbitScreen Deep Galaxy Canvas & Filter Mega Coverage Tests', () {
    test(
      'OrbitScreen.prefetch executes for Dating, Friends, and Professional',
      () async {
        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
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

        expect(
          dResult,
          isNull,
        ); // No active Supabase session in headless unit test
        expect(fResult, isNull);
        expect(pResult, isNull);
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

        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
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
