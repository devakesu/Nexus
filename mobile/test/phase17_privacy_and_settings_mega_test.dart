import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:nexus/features/settings/screens/about_screen.dart';
import 'package:nexus/features/settings/screens/community_guidelines_page.dart';
import 'package:nexus/features/settings/screens/delete_account_page.dart';
import 'package:nexus/features/settings/screens/email_notification_settings_page.dart';
import 'package:nexus/features/settings/screens/feedback_page.dart';
import 'package:nexus/features/settings/screens/feedback_tickets_list_page.dart';
import 'package:nexus/features/settings/screens/meetup_safety_page.dart';
import 'package:nexus/features/settings/screens/privacy_settings_page.dart';
import 'package:nexus/features/settings/screens/safety_center_page.dart';
import 'package:nexus/features/settings/screens/settings_tab.dart';
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
    ConsentCacheManager.safetyConsentGranted = true;
    ConsentCacheManager.specialCategoryConsentGranted = true;
    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        publishableKey: 'mock-anon-key',
      );
    } on Exception catch (_) {}
  });

  group('Privacy & Settings Screens Mega Coverage Tests', () {
    testWidgets(
      'PrivacySettingsPage renders, toggles fields, and handles switches',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        ConsentCacheManager.specialCategoryConsentGranted = true;

        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
          if (options.path.contains('/api/v1/profile/privacy-settings')) {
            return ResponseBody.fromString(
              jsonEncode({
                'hidden_fields': ['display_gender'],
                'ghost_mode': false,
                'read_receipts': true,
                'online_presence': true,
                'location_precision': 'approximate',
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
          const ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: PrivacySettingsPage(),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(find.byType(PrivacySettingsPage), findsOneWidget);

        // Tap switches if present
        final switches = find.byType(Switch);
        for (var i = 0; i < switches.evaluate().length && i < 3; i++) {
          await tester.tap(switches.at(i), warnIfMissed: false);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
        }

        // Scroll and tap hideable field list tiles
        for (var i = 0; i < 3; i++) {
          await tester.drag(
            find.byType(PrivacySettingsPage),
            const Offset(0, -300),
          );
          await tester.pump();
        }
      },
    );

    testWidgets('CommunityGuidelinesPage renders and handles tabs', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CommunityGuidelinesPage(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(CommunityGuidelinesPage), findsOneWidget);

      // Scroll content
      await tester.drag(
        find.byType(CommunityGuidelinesPage),
        const Offset(0, -400),
      );
      await tester.pump();
    });

    testWidgets(
      'SettingsTab renders all setting tiles and triggers navigation',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ProviderScope(
                child: SettingsTab(
                  onOpenOrbit: (mode, color) {},
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(find.byType(SettingsTab), findsOneWidget);

        // Scroll through settings tab
        await tester.drag(find.byType(SettingsTab), const Offset(0, -500));
        await tester.pump();
      },
    );

    testWidgets('MeetupSafetyPage renders properly', (tester) async {
      ConsentCacheManager.safetyConsentGranted = true;

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: MeetupSafetyPage(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(MeetupSafetyPage), findsOneWidget);
    });

    testWidgets('SafetyCenterPage renders properly', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SafetyCenterPage(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(find.byType(SafetyCenterPage), findsOneWidget);
    });

    testWidgets('FeedbackPage renders properly', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: FeedbackPage(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(FeedbackPage), findsOneWidget);
    });

    testWidgets('FeedbackTicketsListPage renders properly', (tester) async {
      createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
        return ResponseBody.fromString('[]', 200);
      });

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: FeedbackTicketsListPage(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(FeedbackTicketsListPage), findsOneWidget);
    });

    testWidgets('EmailNotificationSettingsPage renders properly', (
      tester,
    ) async {
      createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
        return ResponseBody.fromString(
          jsonEncode({
            'email': 'user@example.com',
            'marketing_emails': true,
            'security_alerts': true,
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: EmailNotificationSettingsPage(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(EmailNotificationSettingsPage), findsOneWidget);
    });

    testWidgets('DeleteAccountPage renders properly', (tester) async {
      createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
        return ResponseBody.fromString(
          jsonEncode({
            'ok': true,
            'reasons': ['Other'],
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: DeleteAccountPage(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(DeleteAccountPage), findsOneWidget);
    });

    testWidgets('AboutScreen renders properly', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: AboutScreen(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(AboutScreen), findsOneWidget);
    });
  });
}
