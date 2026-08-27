import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:nexus/features/settings/screens/privacy_settings_page.dart';
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

  group('PrivacySettingsPage Deep Interactive Tests', () {
    testWidgets('loads settings and toggles hideable field switches', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
        if (options.path.contains('/api/v1/profile/hidden-fields')) {
          if (options.method == 'GET') {
            return ResponseBody.fromString(
              jsonEncode({
                'hidden_fields': ['display_gender', 'hometown'],
              }),
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          } else {
            return ResponseBody.fromString(
              jsonEncode({'status': 'ok'}),
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          }
        }
        if (options.path.contains('/api/v1/settings/privacy')) {
          return ResponseBody.fromString(
            jsonEncode({
              'ghost_mode': false,
              'incognito_mode': false,
              'read_receipts': true,
              'online_status': true,
              'location_fuzzing': true,
            }),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }
        return ResponseBody.fromString('{}', 200);
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PrivacySettingsPage(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.byType(PrivacySettingsPage), findsOneWidget);

      // Find switches and toggle them
      final switches = find.byType(Switch);
      for (var i = 0; i < switches.evaluate().length && i < 4; i++) {
        await tester.tap(switches.at(i));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
      }

      // Scroll through the entire page
      await tester.drag(
        find.byType(PrivacySettingsPage),
        const Offset(0, -500),
      );
      await tester.pump(const Duration(milliseconds: 200));

      await tester.drag(
        find.byType(PrivacySettingsPage),
        const Offset(0, -500),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(PrivacySettingsPage), findsOneWidget);
    });
  });
}
