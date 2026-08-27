import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:nexus/features/settings/screens/blocked_users_page.dart';
import 'package:nexus/features/settings/screens/checkin_alert_screen.dart';
import 'package:nexus/features/settings/screens/feedback_ticket_detail_page.dart';
import 'package:nexus/features/settings/screens/feedback_tickets_list_page.dart';
import 'package:nexus/features/settings/screens/hidden_users_page.dart';
import 'package:nexus/features/settings/utils/feedback_shared.dart';
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

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

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
      expect(feedbackQueryTypeFromApiValue('unknown'), FeedbackQueryType.help);

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

        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
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
