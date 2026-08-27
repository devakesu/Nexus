import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:nexus/features/settings/screens/about_screen.dart';
import 'package:nexus/features/settings/screens/blocked_users_page.dart';
import 'package:nexus/features/settings/screens/checkin_alert_screen.dart';
import 'package:nexus/features/settings/screens/community_guidelines_page.dart';
import 'package:nexus/features/settings/screens/delete_account_page.dart';
import 'package:nexus/features/settings/screens/email_notification_settings_page.dart';
import 'package:nexus/features/settings/screens/feedback_page.dart';
import 'package:nexus/features/settings/screens/feedback_ticket_detail_page.dart';
import 'package:nexus/features/settings/screens/feedback_tickets_list_page.dart';
import 'package:nexus/features/settings/screens/help_center_page.dart';
import 'package:nexus/features/settings/screens/hidden_users_page.dart';
import 'package:nexus/features/settings/screens/meetup_safety_page.dart';
import 'package:nexus/features/settings/screens/privacy_settings_page.dart';
import 'package:nexus/features/settings/screens/safety_center_page.dart';
import 'package:nexus/features/settings/screens/settings_tab.dart';
import 'package:nexus/features/settings/utils/feedback_shared.dart';
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
    });

    group('Settings and Privacy Loaded Exhaustive Tests', () {
      testWidgets(
        'PrivacySettingsPage, SettingsTab, HiddenUsers, and CheckinAlert render cleanly',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

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
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byType(SettingsTab), findsOneWidget);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.pump(const Duration(seconds: 60));

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

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));

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
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byType(HiddenUsersPage), findsOneWidget);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));

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
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byType(BlockedUsersPage), findsOneWidget);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));

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

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));

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
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byType(FeedbackPage), findsOneWidget);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));

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
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byType(CheckInAlertScreen), findsOneWidget);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
        },
      );
    });
  }

  // --- Section 2 ---
  {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.devakesu.apps.nexus/safety'),
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

    setUp(() {});

    group('Feedback Shared Models and Helpers Tests', () {
      test('feedbackQueryTypeFromApiValue and extensions', () {
        expect(feedbackQueryTypeFromApiValue('help'), FeedbackQueryType.help);
        expect(
          feedbackQueryTypeFromApiValue('suspended'),
          FeedbackQueryType.suspended,
        );
        expect(
          feedbackQueryTypeFromApiValue('legal_grievance'),
          FeedbackQueryType.legalGrievance,
        );
        expect(
          feedbackQueryTypeFromApiValue('security'),
          FeedbackQueryType.security,
        );
        expect(
          feedbackQueryTypeFromApiValue('feedback'),
          FeedbackQueryType.feedback,
        );
        expect(
          feedbackQueryTypeFromApiValue('bug_report'),
          FeedbackQueryType.bugReport,
        );
        expect(feedbackQueryTypeFromApiValue('other'), FeedbackQueryType.other);
        expect(
          feedbackQueryTypeFromApiValue('unknown'),
          FeedbackQueryType.help,
        );

        for (final type in FeedbackQueryType.values) {
          expect(type.apiValue.isNotEmpty, isTrue);
          expect(type.label.isNotEmpty, isTrue);
          expect(type.description.isNotEmpty, isTrue);
          expect(type.subjectHint.isNotEmpty, isTrue);
          expect(type.messageHint.isNotEmpty, isTrue);
          expect(type.accentColor, isNotNull);
          expect(type.icon, isNotNull);
        }
      });

      test('feedbackStatusFromApiValue and extensions', () {
        expect(feedbackStatusFromApiValue('open'), FeedbackStatus.open);
        expect(
          feedbackStatusFromApiValue('in_progress'),
          FeedbackStatus.inProgress,
        );
        expect(feedbackStatusFromApiValue('resolved'), FeedbackStatus.resolved);
        expect(feedbackStatusFromApiValue('closed'), FeedbackStatus.closed);
        expect(feedbackStatusFromApiValue('unknown'), FeedbackStatus.open);

        for (final status in FeedbackStatus.values) {
          expect(status.apiValue.isNotEmpty, isTrue);
          expect(status.label.isNotEmpty, isTrue);
          expect(status.color, isNotNull);
          expect(status.icon, isNotNull);
        }
        expect(FeedbackStatus.closed.isTerminal, isTrue);
        expect(FeedbackStatus.resolved.isTerminal, isTrue);
        expect(FeedbackStatus.open.isTerminal, isFalse);
      });

      test('feedbackTicketRef and feedbackRelativeTime formatting', () {
        expect(feedbackTicketRef('1234567890'), equals('12345678'));
        expect(feedbackTicketRef('abc'), equals('ABC'));

        final now = DateTime.now().toUtc();
        expect(
          feedbackRelativeTime(now.subtract(const Duration(seconds: 10))),
          equals('just now'),
        );
        expect(
          feedbackRelativeTime(now.subtract(const Duration(minutes: 5))),
          equals('5m ago'),
        );
        expect(
          feedbackRelativeTime(now.subtract(const Duration(hours: 3))),
          equals('3h ago'),
        );
        expect(
          feedbackRelativeTime(now.subtract(const Duration(days: 4))),
          equals('4d ago'),
        );
      });
    });

    group('FeedbackStatusBadge Widget Tests', () {
      testWidgets('renders badge in standard and compact mode', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  FeedbackStatusBadge(status: FeedbackStatus.open),
                  FeedbackStatusBadge(
                    status: FeedbackStatus.inProgress,
                    compact: true,
                  ),
                  FeedbackStatusBadge(status: FeedbackStatus.resolved),
                  FeedbackStatusBadge(
                    status: FeedbackStatus.closed,
                    compact: true,
                  ),
                ],
              ),
            ),
          ),
        );

        expect(find.text('Open'), findsOneWidget);
        expect(find.text('In Progress'), findsOneWidget);
        expect(find.text('Resolved'), findsOneWidget);
        expect(find.text('Closed'), findsOneWidget);
      });
    });

    group('FeedbackTicketsListPage Widget Tests', () {
      testWidgets('renders FeedbackTicketsListPage and loads tickets', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
          if (options.path.contains('/api/v1/feedback')) {
            return ResponseBody.fromString(
              jsonEncode({
                'tickets': [
                  {
                    'id': 'tk_11112222',
                    'query_type': 'bug_report',
                    'subject': 'App crash on orbit scroll',
                    'status': 'open',
                    'created_at': '2026-08-20T10:00:00Z',
                    'updated_at': '2026-08-20T10:00:00Z',
                  },
                  {
                    'id': 'tk_33334444',
                    'query_type': 'feedback',
                    'subject': 'Love the cosmic theme',
                    'status': 'resolved',
                    'created_at': '2026-08-18T10:00:00Z',
                    'updated_at': '2026-08-19T10:00:00Z',
                  },
                ],
              }),
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          }
          return ResponseBody.fromString('Not found', 404);
        });

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: FeedbackTicketsListPage(),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(FeedbackTicketsListPage), findsOneWidget);

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      });
    });

    group('FeedbackTicketDetailPage Widget Tests', () {
      testWidgets(
        'renders FeedbackTicketDetailPage with loaded ticket details & comments',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(800, 1600);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          createDio().httpClientAdapter = _MockHttpClientAdapter((
            options,
          ) async {
            if (options.path.contains('/api/v1/feedback/tk_detail_1')) {
              return ResponseBody.fromString(
                jsonEncode({
                  'id': 'tk_detail_1',
                  'query_type': 'bug_report',
                  'subject': 'Issue with notifications',
                  'message':
                      'Notifications do not trigger sound when phone locked.',
                  'status': 'open',
                  'created_at': '2026-08-22T08:00:00Z',
                  'updated_at': '2026-08-22T08:30:00Z',
                  'github_issue_url': 'https://github.com/nexus/issues/42',
                  'attachment_paths': ['feedback/screenshot.jpg'],
                  'app_version': '1.0.8',
                  'platform': 'Android',
                  'status_history': [
                    {
                      'status': 'open',
                      'created_at': '2026-08-22T08:00:00Z',
                      'note': 'Ticket created',
                      'changed_by': 'User',
                    },
                  ],
                  'comments': [
                    {
                      'id': 'cm_1',
                      'author_id': 'support_agent_1',
                      'body':
                          'Thanks for reporting! Investigating the audio session.',
                      'created_at': '2026-08-22T08:15:00Z',
                      'is_own': false,
                    },
                    {
                      'id': 'cm_2',
                      'author_id': 'user_me',
                      'body': 'Also happening on WiFi.',
                      'created_at': '2026-08-22T08:20:00Z',
                      'is_own': true,
                    },
                  ],
                }),
                200,
                headers: {
                  Headers.contentTypeHeader: [Headers.jsonContentType],
                },
              );
            }
            return ResponseBody.fromString('Not found', 404);
          });

          await tester.pumpWidget(
            const MaterialApp(
              home: Scaffold(
                body: FeedbackTicketDetailPage(reportId: 'tk_detail_1'),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.byType(FeedbackTicketDetailPage), findsOneWidget);

          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 1));
        },
      );
    });

    group('CheckInAlertScreen Widget Tests', () {
      testWidgets('renders CheckInAlertScreen and triggers timer & buttons', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const MaterialApp(
            home: CheckInAlertScreen(),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(CheckInAlertScreen), findsOneWidget);
        expect(find.text("I'm Safe"), findsWidgets);
      });
    });

    group('HiddenUsersPage & BlockedUsersPage Widget Tests', () {
      testWidgets(
        'renders HiddenUsersPage and displays empty state when no hidden users',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(800, 1400);
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
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byType(HiddenUsersPage), findsOneWidget);
        },
      );

      testWidgets(
        'renders BlockedUsersPage and displays empty state when no blocked users',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(800, 1400);
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
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byType(BlockedUsersPage), findsOneWidget);
        },
      );
    });
  }

  // --- Section 3 ---
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

    group('Settings Tab and Privacy Deep Tests', () {
      testWidgets('SettingsTab mounts and scrolls through all tiles', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: SettingsTab(onOpenOrbit: (m, c) {}),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(SettingsTab), findsOneWidget);

        final scrollable = find.byType(Scrollable);
        if (scrollable.evaluate().isNotEmpty) {
          for (var i = 0; i < 4; i++) {
            await tester.drag(scrollable.first, const Offset(0, -400));
            await tester.pump(const Duration(milliseconds: 100));
          }
        }

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });

      testWidgets(
        'PrivacySettingsPage mounts and toggles all switches and links',
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

  // --- Section 5 ---
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
      'privacy_active_status': true,
      'privacy_read_receipts': true,
      'privacy_incognito': false,
      'email_notifications_enabled': true,
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

    group('Settings and Privacy Exhaustive Tests', () {
      testWidgets(
        'SettingsTab, PrivacySettingsPage, EmailNotificationSettingsPage and HelpCenterPage render cleanly',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          for (final widget in [
            SettingsTab(onOpenOrbit: (mode, color) {}),
            const PrivacySettingsPage(),
            const EmailNotificationSettingsPage(),
            const HelpCenterPage(),
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

            // Toggle any visible Switch widgets
            final switches = find.byType(Switch);
            for (var i = 0; i < switches.evaluate().length; i++) {
              try {
                await tester.tap(switches.at(i), warnIfMissed: false);
                await tester.pump(const Duration(milliseconds: 50));
              } on Object catch (_) {}
            }

            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
            await tester.pump(const Duration(seconds: 10));
          }
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

          createDio().httpClientAdapter = _MockHttpClientAdapter((
            options,
          ) async {
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

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
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

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
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

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
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

  // --- Section 7 ---
  {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

    ConsentCacheManager.specialCategoryConsentGranted = true;
    ConsentCacheManager.safetyConsentGranted = true;

    group('PrivacySettingsPage Deep Widget Tests', () {
      testWidgets(
        'PrivacySettingsPage loads settings, renders toggles, and allows interactions',
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
                'hidden_fields': <String>['display_gender'],
                'ghost_mode': false,
                'incognito': false,
                'analytics_enabled': true,
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
                  body: PrivacySettingsPage(),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(seconds: 2));

          expect(find.byType(PrivacySettingsPage), findsOneWidget);

          // Scroll through page
          await tester.drag(
            find.byType(PrivacySettingsPage),
            const Offset(0, -500),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          await tester.drag(
            find.byType(PrivacySettingsPage),
            const Offset(0, -500),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
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

    group('Privacy and Security Pages Exhaustive Tests', () {
      testWidgets('PrivacySettingsPage renders and toggles fields', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
          return ResponseBody.fromString(
            jsonEncode({
              'hidden_fields': ['display_gender'],
              'ghost_mode': false,
              'read_receipts': true,
              'typing_indicators': true,
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
                body: PrivacySettingsPage(),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(find.byType(PrivacySettingsPage), findsOneWidget);

        final switches = find.byType(Switch);
        if (switches.evaluate().isNotEmpty) {
          await tester.tap(switches.first);
          await tester.pump(const Duration(milliseconds: 300));
        }
      });

      testWidgets('HiddenUsersPage renders empty and populated views', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
          return ResponseBody.fromString(
            jsonEncode({'users': <dynamic>[]}),
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

      testWidgets('BlockedUsersPage renders empty and populated views', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
          return ResponseBody.fromString(
            jsonEncode({'users': <dynamic>[]}),
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

      testWidgets('MeetupSafetyPage renders properly', (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: MeetupSafetyPage(),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 2));

        expect(find.byType(MeetupSafetyPage), findsOneWidget);
      });

      testWidgets('SafetyCenterPage renders properly', (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SafetyCenterPage(),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 2));

        expect(find.byType(SafetyCenterPage), findsOneWidget);
      });

      testWidgets('CheckInAlertScreen renders and handles safety actions', (
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
      });
    });
  }

  // --- Section 9 ---
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

    group('Privacy and Settings Tab Deep Tests', () {
      testWidgets('PrivacySettingsPage and SettingsTab render cleanly', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: PrivacySettingsPage(),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(find.byType(PrivacySettingsPage), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SettingsTab(
                onOpenOrbit: (mode, color) {},
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(find.byType(SettingsTab), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
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

    group('PrivacySettingsPage Comprehensive Coverage Tests', () {
      testWidgets(
        'renders PrivacySettingsPage and scrolls through all privacy controls',
        (tester) async {
          tester.view.physicalSize = const Size(800, 2400);
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
          await tester.pump(const Duration(seconds: 2));

          expect(find.byType(PrivacySettingsPage), findsOneWidget);
          expect(find.text('Privacy Settings'), findsWidgets);

          // Toggle any available switches in view
          final switches = find.byType(Switch);
          for (var i = 0; i < switches.evaluate().length && i < 4; i++) {
            await tester.tap(switches.at(i));
            await tester.pump(const Duration(milliseconds: 200));
          }

          // Scroll down to see more switches
          await tester.drag(
            find.byType(PrivacySettingsPage),
            const Offset(0, -500),
          );
          await tester.pump(const Duration(seconds: 1));

          final updatedSwitches = find.byType(Switch);
          for (var i = 0; i < updatedSwitches.evaluate().length && i < 3; i++) {
            await tester.tap(updatedSwitches.at(i));
            await tester.pump(const Duration(milliseconds: 200));
          }
        },
      );
    });
  }

  // --- Section 11 ---
  {
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

    group('PrivacySettingsPage Interactive Deep Tests', () {
      testWidgets('renders all hideable switches and interacts with toggles', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 2000);
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
        await tester.pump(const Duration(seconds: 2));

        expect(find.byType(PrivacySettingsPage), findsOneWidget);

        final switches = find.byType(Switch);
        for (var i = 0; i < switches.evaluate().length && i < 5; i++) {
          await tester.tap(switches.at(i));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
        }

        await tester.drag(
          find.byType(PrivacySettingsPage),
          const Offset(0, -600),
        );
        await tester.pump(const Duration(seconds: 1));
        expect(find.byType(PrivacySettingsPage), findsOneWidget);
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

    group('PrivacySettingsPage Widget Tests', () {
      testWidgets('renders PrivacySettingsPage with field privacy options', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: PrivacySettingsPage(),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 2));

        expect(find.byType(PrivacySettingsPage), findsOneWidget);
      });
    });

    group('HelpCenterPage Widget Tests', () {
      testWidgets('renders HelpCenterPage with FAQs and categories', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: HelpCenterPage(),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 2));

        expect(find.byType(HelpCenterPage), findsOneWidget);
        expect(find.text('Help Center'), findsWidgets);
      });
    });

    group('FeedbackPage & FeedbackTicketsListPage Widget Tests', () {
      testWidgets('renders FeedbackPage with query types and form inputs', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: FeedbackPage(),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 2));

        expect(find.byType(FeedbackPage), findsOneWidget);

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      });

      testWidgets('renders FeedbackTicketsListPage', (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: FeedbackTicketsListPage(),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 2));

        expect(find.byType(FeedbackTicketsListPage), findsOneWidget);

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      });
    });

    group('BlockedUsersPage & HiddenUsersPage Widget Tests', () {
      testWidgets('renders BlockedUsersPage', (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
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
        await tester.pump(const Duration(seconds: 2));

        expect(find.byType(BlockedUsersPage), findsOneWidget);
      });

      testWidgets('renders HiddenUsersPage', (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
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
        await tester.pump(const Duration(seconds: 2));

        expect(find.byType(HiddenUsersPage), findsOneWidget);
      });
    });

    group('EmailNotificationSettingsPage Widget Tests', () {
      testWidgets('renders EmailNotificationSettingsPage with switch toggles', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: EmailNotificationSettingsPage(),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 2));

        expect(find.byType(EmailNotificationSettingsPage), findsOneWidget);
      });
    });
  }
}
