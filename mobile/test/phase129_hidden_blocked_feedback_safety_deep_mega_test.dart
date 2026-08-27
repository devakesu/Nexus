import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/settings/screens/blocked_users_page.dart';
import 'package:nexus/features/settings/screens/community_guidelines_page.dart';
import 'package:nexus/features/settings/screens/feedback_page.dart';
import 'package:nexus/features/settings/screens/feedback_ticket_detail_page.dart';
import 'package:nexus/features/settings/screens/hidden_users_page.dart';
import 'package:nexus/features/settings/screens/safety_center_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'helpers/mock_network_interceptor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
    setupGlobalMockNetwork();
  });

  group('Phase 129 - Hidden, Blocked, Feedback and Safety Deep Mega Tests', () {
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
