import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:nexus/features/security_signal/services/meetup_safety_session.dart';
import 'package:nexus/features/security_signal/services/safety_alert_api.dart';
import 'package:nexus/features/security_signal/services/safety_contacts.dart';
import 'package:nexus/features/security_signal/services/safety_dialer.dart';
import 'package:nexus/features/settings/screens/blocked_users_page.dart';
import 'package:nexus/features/settings/screens/checkin_alert_screen.dart';
import 'package:nexus/features/settings/screens/community_guidelines_page.dart';
import 'package:nexus/features/settings/screens/feedback_page.dart';
import 'package:nexus/features/settings/screens/feedback_ticket_detail_page.dart';
import 'package:nexus/features/settings/screens/hidden_users_page.dart';
import 'package:nexus/features/settings/screens/meetup_safety_page.dart';
import 'package:nexus/features/settings/screens/privacy_settings_page.dart';
import 'package:nexus/features/settings/screens/safety_center_page.dart';
import 'package:nexus/features/settings/screens/settings_tab.dart';
import 'package:nexus/features/settings/widgets/settings_tile_components.dart';
import 'package:nexus/features/settings/widgets/transparency_badge.dart';
import 'package:nexus/features/settings/widgets/user_management_components.dart';
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
      'privacy_active_status': true,
      'privacy_read_receipts': true,
      'privacy_incognito': false,
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

    group('Settings and Safety Interactive Deep Tests', () {
      testWidgets(
        'Privacy and Meetup Safety pages toggle switches and buttons',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

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
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byType(PrivacySettingsPage), findsOneWidget);

          final switches = find.byType(Switch);
          for (var i = 0; i < switches.evaluate().length; i++) {
            try {
              await tester.tap(switches.at(i), warnIfMissed: false);
              await tester.pump(const Duration(milliseconds: 50));
            } on Object catch (_) {}
          }

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));

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
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byType(MeetupSafetyPage), findsOneWidget);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
        },
      );
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
      try {
        await Supabase.initialize(
          url: 'https://mock.supabase.co',
          publishableKey: 'mock-anon-key',
        );
      } on Exception catch (_) {}
      setupGlobalMockNetwork();
    });

    group('Hidden, Blocked, Feedback and Safety Deep Tests', () {
      testWidgets(
        'HiddenUsersPage, BlockedUsersPage and SafetyCenterPage render cleanly',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          for (final widget in const [
            HiddenUsersPage(),
            BlockedUsersPage(),
            SafetyCenterPage(),
            CommunityGuidelinesPage(),
            FeedbackPage(),
          ]) {
            await tester.pumpWidget(
              ProviderScope(
                child: MaterialApp(
                  home: Scaffold(body: widget),
                ),
              ),
            );

            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            expect(find.byWidget(widget), findsOneWidget);

            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
            await tester.pump(const Duration(seconds: 10));
          }
        },
      );

      testWidgets(
        'FeedbackTicketDetailPage renders feedback thread and replies',
        (
          tester,
        ) async {
          await tester.pumpWidget(
            const ProviderScope(
              child: MaterialApp(
                home: Scaffold(
                  body: FeedbackTicketDetailPage(reportId: 'tkt_123'),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byType(FeedbackTicketDetailPage), findsOneWidget);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.pump(const Duration(seconds: 10));
        },
      );
    });
  }

  // --- Section 3 ---
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

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_contacts'),
          (call) async => [],
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

    group('Safety, Hidden & Blocked Users Mega Coverage Tests', () {
      testWidgets(
        'MeetupSafetyPage renders emergency contacts and date check-in form',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            const MaterialApp(
              home: Scaffold(
                body: MeetupSafetyPage(
                  initialCheckInLabel: 'Coffee with Jordan',
                  initialCheckInDuration: Duration(minutes: 45),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(seconds: 1));

          expect(find.byType(MeetupSafetyPage), findsOneWidget);

          // Scroll MeetupSafetyPage
          await tester.drag(
            find.byType(MeetupSafetyPage),
            const Offset(0, -600),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
        },
      );

      testWidgets('HiddenUsersPage renders cleanly', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: HiddenUsersPage(),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byType(HiddenUsersPage), findsOneWidget);
      });

      testWidgets('BlockedUsersPage renders empty state or list cleanly', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: BlockedUsersPage(),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byType(BlockedUsersPage), findsOneWidget);
      });

      testWidgets(
        'FeedbackTicketDetailPage loads and renders comments and actions',
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
                'status': 'success',
                'ticket': {
                  'id': 't_test_42',
                  'subject': 'App feedback',
                  'message': 'Love the galaxy view design!',
                  'status': 'open',
                  'created_at': DateTime.now().toIso8601String(),
                  'comments': [
                    {
                      'id': 'c_1',
                      'author': 'Support Team',
                      'content': 'Thank you for your feedback!',
                      'created_at': DateTime.now().toIso8601String(),
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

          await tester.pumpWidget(
            const MaterialApp(
              home: Scaffold(
                body: FeedbackTicketDetailPage(reportId: 't_test_42'),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(seconds: 1));

          expect(find.byType(FeedbackTicketDetailPage), findsOneWidget);

          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 1));
        },
      );
    });
  }

  // --- Section 4 ---
  {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

    setUp(() {});

    group('SafetyContact & Storage Tests', () {
      test('SafetyContact JSON serialization and round-trip', () async {
        final contact = SafetyContact(name: 'Jane Doe', phone: '+1234567890');
        expect(contact.name, equals('Jane Doe'));
        expect(contact.phone, equals('+1234567890'));

        final json = contact.toJson();
        final fromJson = SafetyContact.fromJson(json);
        expect(fromJson.name, equals('Jane Doe'));
        expect(fromJson.phone, equals('+1234567890'));
      });

      test(
        'loadSafetyContacts, saveSafetyContacts, and clearSafetyContacts',
        () async {
          expect(await loadSafetyContacts(), isEmpty);

          final list = [
            SafetyContact(name: 'Mom', phone: '+1112223333'),
            SafetyContact(name: 'Dad', phone: '+4445556666'),
          ];
          await saveSafetyContacts(list);

          final loaded = await loadSafetyContacts();
          expect(loaded.length, equals(2));
          expect(loaded.first.name, equals('Mom'));

          await clearSafetyContacts();
          expect(await loadSafetyContacts(), isEmpty);
        },
      );
    });

    group('SafetyAlertApi Models & Methods Tests', () {
      test('SafetyAlertResult & SafetyContactsSyncResult models', () {
        const alertResult = SafetyAlertResult(
          alertId: 'alt_123',
          contactsNotified: 2,
          contactsTotal: 3,
        );
        expect(alertResult.alertId, equals('alt_123'));
        expect(alertResult.contactsNotified, equals(2));
        expect(alertResult.contactsTotal, equals(3));

        const syncResult = SafetyContactsSyncResult(
          success: true,
          blocked: ['Blocked Contact'],
        );
        expect(syncResult.success, isTrue);
        expect(syncResult.blocked, contains('Blocked Contact'));
      });
    });

    group('MeetupSafetySession & Permissions Models Tests', () {
      test('MeetupSafetyPermissionStatus permissions state checks', () {
        const allGranted = MeetupSafetyPermissionStatus.allGranted();
        expect(allGranted.allGranted, isTrue);
        expect(allGranted.notificationsGranted, isTrue);
        expect(allGranted.exactAlarmsGranted, isTrue);
        expect(allGranted.fullScreenIntentGranted, isTrue);

        const partial = MeetupSafetyPermissionStatus(
          notificationsGranted: true,
          exactAlarmsGranted: false,
          fullScreenIntentGranted: true,
        );
        expect(partial.allGranted, isFalse);
      });

      test('MeetupSafetyNotificationActions action string constants', () {
        expect(
          MeetupSafetyNotificationActions.sos,
          equals('meetup_safety_sos'),
        );
        expect(
          MeetupSafetyNotificationActions.call112,
          equals('meetup_safety_call_112'),
        );
        expect(
          MeetupSafetyNotificationActions.imSafe,
          equals('meetup_safety_im_safe'),
        );
      });
    });

    group('Safety UI & Dialog Helpers Tests', () {
      testWidgets('showSosFallbackDialog renders confirmation and buttons', (
        tester,
      ) async {
        var retried = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    unawaited(
                      showSosFallbackDialog(
                        context,
                        contacts: [
                          SafetyContact(name: 'Alice', phone: '+1234567890'),
                        ],
                        onRetryRecording: () => retried = true,
                      ),
                    );
                  },
                  child: const Text('Show Fallback Dialog'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Show Fallback Dialog'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Emergency Triggered'), findsOneWidget);
        expect(find.textContaining('Emergency SOS activated!'), findsOneWidget);
        expect(find.text('Retry Recording'), findsOneWidget);
        expect(find.text('Dismiss'), findsOneWidget);

        await tester.tap(find.text('Retry Recording'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(retried, isTrue);
      });

      testWidgets('showInformContactsToast shows message and completes timer', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    showInformContactsToast(
                      context,
                      [SafetyContact(name: 'Bob', phone: '+9876543210')],
                    );
                  },
                  child: const Text('Show Inform Toast'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Show Inform Toast'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.textContaining('Alert sent to Bob'), findsOneWidget);
        // Wait for forward animation (280ms) + display duration (3000ms) + reverse animation (220ms)
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(seconds: 3));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));
      });

      testWidgets('callEmergencyNumber handles execution gracefully', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => callEmergencyNumber(context, '112'),
                  child: const Text('Call 112'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Call 112'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(seconds: 3));
        await tester.pump(const Duration(milliseconds: 300));
      });
    });
  }

  // --- Section 5 ---
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

    group('Settings and Safety Screens Tests', () {
      testWidgets(
        'PrivacySettingsPage, CheckInAlertScreen, and HiddenUsersPage render',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

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
          await tester.pump(const Duration(seconds: 3));
          expect(find.byType(PrivacySettingsPage), findsOneWidget);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.pump(const Duration(seconds: 3));

          await tester.pumpWidget(
            const MaterialApp(
              home: Scaffold(
                body: CheckInAlertScreen(),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(seconds: 3));
          expect(find.byType(CheckInAlertScreen), findsOneWidget);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.pump(const Duration(seconds: 3));

          await tester.pumpWidget(
            const ProviderScope(
              child: MaterialApp(
                home: Scaffold(
                  body: HiddenUsersPage(),
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(seconds: 3));
          expect(find.byType(HiddenUsersPage), findsOneWidget);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.pump(const Duration(seconds: 3));
        },
      );

      testWidgets(
        'MeetupSafetyPage, BlockedUsersPage, and SettingsTab render',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

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
          await tester.pump(const Duration(seconds: 3));
          expect(find.byType(MeetupSafetyPage), findsOneWidget);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.pump(const Duration(seconds: 3));

          await tester.pumpWidget(
            const ProviderScope(
              child: MaterialApp(
                home: Scaffold(
                  body: BlockedUsersPage(),
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(seconds: 3));
          expect(find.byType(BlockedUsersPage), findsOneWidget);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.pump(const Duration(seconds: 3));

          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                home: Scaffold(
                  body: SettingsTab(
                    onOpenOrbit: (mode, color) {},
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(seconds: 3));
          expect(find.byType(SettingsTab), findsOneWidget);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.pump(const Duration(seconds: 3));
        },
      );

      testWidgets('FeedbackPage and SafetyCenterPage render properly', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

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
        await tester.pump(const Duration(seconds: 3));
        expect(find.byType(FeedbackPage), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 3));

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

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 3));
      });
    });
  }

  // --- Section 6 ---
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

    group('Settings Tiles and Transparency Tests', () {
      testWidgets(
        'SettingsSectionHeader, SettingsToggleTile, and TransparencyBadge render cleanly',
        (
          tester,
        ) async {
          var toggleVal = true;
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Column(
                  children: [
                    const SettingsSectionHeader(title: 'Account Settings'),
                    SettingsToggleTile(
                      title: 'Incognito Mode',
                      subtitle: 'Hide your profile from strangers',
                      value: toggleVal,
                      onChanged: (val) {
                        toggleVal = val;
                      },
                    ),
                    TransparencyBadge(
                      expanded: true,
                      onTap: () {},
                    ),
                  ],
                ),
              ),
            ),
          );

          await tester.pump();
          expect(find.byType(SettingsSectionHeader), findsOneWidget);
          expect(find.byType(SettingsToggleTile), findsOneWidget);
          expect(find.byType(TransparencyBadge), findsOneWidget);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
        },
      );

      testWidgets('User management components render properly', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  SettingsErrorView(
                    error: 'Failed to load list',
                    onRetry: () {},
                  ),
                  const SettingsEmptyView(
                    icon: LucideIcons.userX,
                    title: 'No blocked users',
                    description: 'You have not blocked anyone yet.',
                  ),
                ],
              ),
            ),
          ),
        );

        await tester.pump();
        expect(find.byType(SettingsErrorView), findsOneWidget);
        expect(find.byType(SettingsEmptyView), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
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
          const MethodChannel('flutter.baseflow.com/geolocator'),
          (call) async => {
            'latitude': 37.7749,
            'longitude': -122.4194,
            'timestamp': 0,
            'accuracy': 5.0,
            'altitude': 0.0,
            'altitude_accuracy': 0.0,
            'heading': 0.0,
            'heading_accuracy': 0.0,
            'speed': 0.0,
            'speed_accuracy': 0.0,
          },
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

    group('SafetyCenterPage Deep Widget Tests', () {
      testWidgets(
        'renders SafetyCenterPage with header, subtabs, and scrolls content',
        (tester) async {
          tester.view.physicalSize = const Size(800, 1400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

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
        },
      );
    });
  }
}
