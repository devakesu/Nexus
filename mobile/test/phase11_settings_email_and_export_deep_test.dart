import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:nexus/features/settings/screens/data_export_flow.dart';
import 'package:nexus/features/settings/screens/email_notification_settings_page.dart';
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
  ) {
    return handler(options);
  }

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
        const MethodChannel('dev.fluttercommunity.plus/share'),
        (call) async => true,
      );

  setUpAll(() async {
    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        publishableKey: 'mock-anon-key',
      );
    } on Exception catch (_) {}
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('EmailNotificationSettingsPage Deep Interactive Tests', () {
    testWidgets('renders email notification categories and toggles settings', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
        if (options.path.contains('/api/v1/profile/email-notifications')) {
          if (options.method == 'GET') {
            return ResponseBody.fromString(
              jsonEncode({
                'email_notify_matches': true,
                'email_notify_messages': true,
                'email_notify_digest': false,
                'email_notify_product_updates': true,
                'email_notify_promotions': false,
              }),
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          }
          if (options.method == 'PATCH') {
            return ResponseBody.fromString('{"status":"ok"}', 200);
          }
        }
        return ResponseBody.fromString('Not found', 404);
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmailNotificationSettingsPage(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(EmailNotificationSettingsPage), findsOneWidget);

      // Toggle available switches
      final switches = find.byType(Switch);
      for (var i = 0; i < switches.evaluate().length; i++) {
        await tester.tap(switches.at(i));
        await tester.pump(const Duration(milliseconds: 100));
      }
    });
  });

  group('DataExportFlow Deep Tests', () {
    testWidgets('startDataExport shows confirmation dialog', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => startDataExport(context),
                child: const Text('Trigger Export'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Trigger Export'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Export Personal Data'), findsOneWidget);
    });
  });
}
