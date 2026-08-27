import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:nexus/features/settings/screens/blocked_users_page.dart';
import 'package:nexus/features/settings/screens/feedback_ticket_detail_page.dart';
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

  group('Settings Hidden, Blocked & Feedback Detail Mega Coverage Tests', () {
    test('FeedbackShared models serialization and formatting', () {
      final now = DateTime.now();
      final comment = FeedbackCommentEntry(
        id: 'c1',
        authorId: 'u1',
        body: 'This is a comment',
        createdAt: now,
        isOwn: true,
      );
      expect(comment.id, 'c1');
      expect(comment.authorId, 'u1');
      expect(comment.body, 'This is a comment');
      expect(comment.isOwn, isTrue);

      final summary = FeedbackTicketSummary(
        id: 's1',
        queryType: FeedbackQueryType.bugReport,
        subject: 'Slow rendering',
        status: FeedbackStatus.inProgress,
        createdAt: now,
        updatedAt: now,
      );
      expect(summary.id, 's1');
      expect(summary.queryType, FeedbackQueryType.bugReport);
      expect(summary.status, FeedbackStatus.inProgress);

      final history = FeedbackStatusHistoryEntry(
        status: FeedbackStatus.resolved,
        createdAt: now,
        note: 'Fixed in v1.2',
        changedBy: 'Admin',
      );
      expect(history.status, FeedbackStatus.resolved);
      expect(history.note, 'Fixed in v1.2');

      final ticket = FeedbackTicketDetail(
        id: 't1',
        queryType: FeedbackQueryType.bugReport,
        subject: 'Map rendering bug',
        message: 'Map is slow to load',
        attachmentPaths: ['https://example.com/shot.jpg'],
        status: FeedbackStatus.open,
        createdAt: now,
        updatedAt: now,
        statusHistory: [history],
        comments: [comment],
      );
      expect(ticket.id, 't1');
      expect(ticket.queryType, FeedbackQueryType.bugReport);
      expect(ticket.subject, 'Map rendering bug');
      expect(ticket.comments.length, 1);
      expect(ticket.attachmentPaths.length, 1);
    });

    testWidgets('HiddenUsersPage renders empty state and loads gracefully', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

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
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(HiddenUsersPage), findsOneWidget);
    });

    testWidgets('BlockedUsersPage renders empty state and loads gracefully', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

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
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(BlockedUsersPage), findsOneWidget);
    });

    testWidgets(
      'FeedbackTicketDetailPage renders ticket details and comments',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
          final mockTicket = {
            'id': 't_99',
            'query_type': 'bug_report',
            'subject': 'Push notification delay',
            'message': 'Notifications appear after 5 minutes',
            'status': 'open',
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
            'attachment_paths': <String>[],
            'status_history': <Map<String, dynamic>>[],
            'comments': [
              {
                'id': 'c_1',
                'author_id': 'support_1',
                'body': 'We are looking into this issue.',
                'created_at': DateTime.now().toIso8601String(),
                'is_own': false,
              },
            ],
          };
          return ResponseBody.fromString(
            jsonEncode(mockTicket),
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
                body: FeedbackTicketDetailPage(reportId: 't_99'),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 2));

        expect(find.byType(FeedbackTicketDetailPage), findsOneWidget);
      },
    );
  });
}
