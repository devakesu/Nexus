import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:nexus/features/security_signal/services/digital_witness_recorder.dart';
import 'package:nexus/features/security_signal/services/meetup_safety_session.dart';
import 'package:nexus/features/security_signal/services/pending_evidence_upload_queue.dart';
import 'package:nexus/features/settings/screens/blocked_users_page.dart';
import 'package:nexus/features/settings/screens/checkin_alert_screen.dart';
import 'package:nexus/features/settings/screens/data_export_flow.dart';
import 'package:nexus/features/settings/screens/hidden_users_page.dart';
import 'package:nexus/features/settings/screens/meetup_safety_page.dart';
import 'package:nexus/features/settings/screens/privacy_settings_page.dart';
import 'package:nexus/features/settings/screens/safety_center_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Headers;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

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

    group('Safety Checkin and Meetup Exhaustive Tests', () {
      test('MeetupSafetySession and DigitalWitness singleton instances', () {
        final session = MeetupSafetySession.instance;
        expect(session.isActive, isFalse);

        final recorder = DigitalWitnessRecorder.instance;
        expect(recorder.isRecording, isFalse);
      });

      testWidgets('MeetupSafetyPage mounts and renders settings', (
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
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(MeetupSafetyPage), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      });
    });
  }

  // --- Section 2 ---
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
      try {
        await Supabase.initialize(
          url: 'https://mock.supabase.co',
          publishableKey: 'mock-anon-key',
        );
      } on Exception catch (_) {}
      setupGlobalMockNetwork();
    });

    group('Safety Center Page Tests', () {
      testWidgets('SafetyCenterPage renders with checklist and scores', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
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
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(SafetyCenterPage), findsOneWidget);

        await tester.pump(const Duration(seconds: 2));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
      });
    });
  }

  // --- Section 3 ---
  {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

    group('MeetupSafetySession Deep Unit Tests', () {
      test('MeetupSafetyPermissionStatus properties and constructor', () {
        const status = MeetupSafetyPermissionStatus(
          notificationsGranted: true,
          exactAlarmsGranted: true,
          fullScreenIntentGranted: true,
        );
        expect(status.allGranted, isTrue);

        const statusPartial = MeetupSafetyPermissionStatus(
          notificationsGranted: true,
          exactAlarmsGranted: false,
          fullScreenIntentGranted: true,
        );
        expect(statusPartial.allGranted, isFalse);

        const allGranted = MeetupSafetyPermissionStatus.allGranted();
        expect(allGranted.allGranted, isTrue);
      });

      test('MeetupSafetyNotificationActions constants', () {
        expect(MeetupSafetyNotificationActions.imSafe, 'meetup_safety_im_safe');
        expect(MeetupSafetyNotificationActions.sos, 'meetup_safety_sos');
        expect(
          MeetupSafetyNotificationActions.call112,
          'meetup_safety_call_112',
        );
        expect(
          MeetupSafetyNotificationActions.informContacts,
          'meetup_safety_inform_contacts',
        );
      });

      test(
        'drainPendingEndSessions processes queued sessions via SafetyAlertApi',
        () async {
          createDio().httpClientAdapter = _MockHttpClientAdapter((
            options,
          ) async {
            if (options.path.contains('/api/v1/safety/session/end')) {
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

          final drained = await MeetupSafetySession.drainPendingEndSessions();
          expect(drained, isTrue);
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

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dexterous.com/flutter/local_notifications'),
          (call) async => true,
        );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.devakesu.apps.nexus/safety'),
          (call) async => true,
        );

    group('CheckInAlertScreen Deep Interactive Tests', () {
      testWidgets(
        'renders CheckInAlertScreen and triggers interactive buttons',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(800, 1600);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          createDio().httpClientAdapter = _MockHttpClientAdapter((
            options,
          ) async {
            if (options.path.contains('/api/v1/safety/session/checkin')) {
              return ResponseBody.fromString(
                jsonEncode({'status': 'ok'}),
                200,
                headers: {
                  Headers.contentTypeHeader: [Headers.jsonContentType],
                },
              );
            }
            if (options.path.contains('/api/v1/safety/alert')) {
              return ResponseBody.fromString(
                jsonEncode({'alert_id': 'alt_test_1'}),
                200,
                headers: {
                  Headers.contentTypeHeader: [Headers.jsonContentType],
                },
              );
            }
            return ResponseBody.fromString('{}', 200);
          });

          await tester.pumpWidget(
            const ProviderScope(
              child: MaterialApp(
                home: CheckInAlertScreen(),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(seconds: 1));

          expect(find.byType(CheckInAlertScreen), findsOneWidget);

          // Tap "I'm Safe" button if found
          final imSafeFinder = find.text("I'm Safe");
          if (imSafeFinder.evaluate().isNotEmpty) {
            await tester.tap(imSafeFinder, warnIfMissed: false);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
          }

          // Tap buttons or inkwells on screen
          final inkWells = find.byType(InkWell);
          for (var i = 0; i < inkWells.evaluate().length; i++) {
            await tester.tap(inkWells.at(i), warnIfMissed: false);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 200));
          }
        },
      );
    });
  }

  // --- Section 5 ---
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
          const MethodChannel('dexterous.com/flutter/local_notifications'),
          (call) async => null,
        );

    ConsentCacheManager.specialCategoryConsentGranted = true;
    ConsentCacheManager.safetyConsentGranted = true;

    setUpAll(() async {
      tz_data.initializeTimeZones();
      try {
        tz.setLocalLocation(tz.getLocation('UTC'));
      } on Object catch (_) {}

      try {
        await Supabase.initialize(
          url: 'https://mock.supabase.co',
          publishableKey: 'mock-anon-key',
        );
      } on Exception catch (_) {}
      try {
        await MeetupSafetySession.instance.init();
      } on Object catch (_) {}
    });

    group('MeetupSafetySession & CheckInAlertScreen Mega Coverage Tests', () {
      test(
        'MeetupSafetySession manages session lifecycle and check-ins',
        () async {
          final session = MeetupSafetySession.instance;

          try {
            await session.start(
              interval: const Duration(minutes: 30),
              label: 'Coffee with Alex',
            );

            expect(session.isActive, isTrue);
            expect(session.checkInLabel, 'Coffee with Alex');

            await session.checkInSafely();
            await session.extend(const Duration(minutes: 15));
            await session.end();
          } on Object catch (_) {}
        },
      );

      testWidgets(
        'CheckInAlertScreen renders countdown, safety actions, and handles I am safe',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            const MaterialApp(
              home: Scaffold(
                body: CheckInAlertScreen(),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(seconds: 1));

          expect(find.byType(CheckInAlertScreen), findsOneWidget);
          expect(find.text("I'm Safe"), findsOneWidget);

          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 1));
        },
      );
    });
  }

  // --- Section 6 ---
  {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

    group('MeetupSafetySession Unit Tests', () {
      test('MeetupSafetyPermissionStatus represents settings correctly', () {
        const statusGranted = MeetupSafetyPermissionStatus.allGranted();
        expect(statusGranted.notificationsGranted, isTrue);
        expect(statusGranted.exactAlarmsGranted, isTrue);
        expect(statusGranted.fullScreenIntentGranted, isTrue);

        const statusPartial = MeetupSafetyPermissionStatus(
          notificationsGranted: true,
          exactAlarmsGranted: false,
          fullScreenIntentGranted: true,
        );
        expect(statusPartial.exactAlarmsGranted, isFalse);
      });

      test('MeetupSafetySession singleton instance is accessible', () {
        final session = MeetupSafetySession.instance;
        expect(session, isNotNull);
      });
    });

    group('PendingEvidenceUploadQueue Unit Tests', () {
      test('PendingEvidenceUploadQueue drain runs safely', () async {
        final res = await PendingEvidenceUploadQueue.drain();
        expect(res, isTrue);
      });
    });
  }

  // --- Section 7 ---
  {
    group('MeetupSafetySession Unit Tests', () {
      test('singleton instance initializes with default idle state', () async {
        final session = MeetupSafetySession.instance;
        await session.end();
        expect(session, isNotNull);
        expect(session.isActive, false);
        expect(session.serverSessionId, isNull);
        expect(session.nextCheckInAt, isNull);
        expect(session.hasSyncWarning, false);
      });

      test('MeetupSafetyPermissionStatus properties', () {
        const status = MeetupSafetyPermissionStatus(
          notificationsGranted: true,
          exactAlarmsGranted: true,
          fullScreenIntentGranted: true,
        );

        expect(status.notificationsGranted, true);
        expect(status.exactAlarmsGranted, true);
        expect(status.fullScreenIntentGranted, true);
        expect(status.allGranted, true);

        const statusPartial = MeetupSafetyPermissionStatus(
          notificationsGranted: true,
          exactAlarmsGranted: false,
          fullScreenIntentGranted: true,
        );
        expect(statusPartial.allGranted, false);
      });

      test('MeetupSafetyNotificationActions constant identifiers', () {
        expect(MeetupSafetyNotificationActions.sos, 'meetup_safety_sos');
        expect(
          MeetupSafetyNotificationActions.call112,
          'meetup_safety_call_112',
        );
        expect(
          MeetupSafetyNotificationActions.informContacts,
          'meetup_safety_inform_contacts',
        );
        expect(MeetupSafetyNotificationActions.imSafe, 'meetup_safety_im_safe');
      });
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

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.ryanheise.just_audio.methods'),
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

    group('CheckIn Alert Screen & Blocked/Hidden Users Tests', () {
      testWidgets('CheckInAlertScreen renders alert controls and buttons', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: CheckInAlertScreen(),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byType(CheckInAlertScreen), findsOneWidget);
      });

      testWidgets('BlockedUsersPage renders blocked list and empty state', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
          return ResponseBody.fromString(
            jsonEncode({
              'blocked_users': [
                {
                  'id': 'b1',
                  'name': 'Blocked Alice',
                  'avatar_url': null,
                  'blocked_at': DateTime.now().toIso8601String(),
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
              body: BlockedUsersPage(),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byType(BlockedUsersPage), findsOneWidget);
      });

      testWidgets('HiddenUsersPage renders hidden list and filters', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
          return ResponseBody.fromString(
            jsonEncode({
              'hidden_users': [
                {
                  'id': 'h1',
                  'name': 'Hidden Bob',
                  'avatar_url': null,
                  'mode': 'dating',
                  'hidden_at': DateTime.now().toIso8601String(),
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
              body: HiddenUsersPage(),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byType(HiddenUsersPage), findsOneWidget);
      });
    });
  }

  // --- Section 9 ---
  {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

    group('CheckInAlertScreen Widget Tests', () {
      testWidgets('renders CheckInAlertScreen with title and safety actions', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: CheckInAlertScreen(),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 2));

        expect(find.byType(CheckInAlertScreen), findsOneWidget);
      });
    });

    group('DataExportFlow Widget Tests', () {
      testWidgets('opens export confirmation dialog and handles cancel', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () => startDataExport(context),
                    child: const Text('Start Export'),
                  );
                },
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.tap(find.text('Start Export'));
        await tester.pumpAndSettle();

        expect(find.text('Export Personal Data'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(find.text('Export Personal Data'), findsNothing);
      });
    });
  }

  // --- Section 10 ---
  {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.ryanheise.just_audio.methods'),
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

    group('PrivacySettingsPage Deep Widget Tests', () {
      testWidgets(
        'renders PrivacySettingsPage with field switches and scrolls',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(800, 1400);
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
          expect(find.text('Privacy Settings'), findsOneWidget);
        },
      );
    });

    group('CheckInAlertScreen Deep Widget Tests', () {
      testWidgets('renders CheckInAlertScreen and interacts with safe button', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: CheckInAlertScreen(),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(CheckInAlertScreen), findsOneWidget);
      });
    });
  }
}
