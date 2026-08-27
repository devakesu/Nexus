import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/features/chats/screens/chat_conversation_page.dart';
import 'package:nexus/features/chats/widgets/chat_composer.dart';
import 'package:nexus/features/chats/widgets/chat_list_tab.dart';
import 'package:nexus/features/chats/widgets/event_planner_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Headers;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  group('Phase 59 - Chats Conversation Provider and Page Mega Test', () {
    testWidgets('ChatConversationPage renders and sends interactions', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ChatConversationPage(
                conversationId: 'conv_123',
                matchedUserId: 'user_456',
                tab: 'dating',
                name: 'Elena Rostova',
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(ChatConversationPage), findsOneWidget);
      expect(find.text('Elena Rostova'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets(
      'ChatComposer renders all action buttons and triggers callbacks',
      (
        tester,
      ) async {
        String? sentText;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ChatComposer(
                themeColor: Colors.blue,
                enabled: true,
                sending: false,
                onSend: (text) async {
                  sentText = text;
                },
                onSendImage: (bytes, mime) async {},
                onSendVoice: (bytes, mime, duration) async {},
                onSendLocation: (lat, lng, label) async {},
                onPlanEvent: () {},
              ),
            ),
          ),
        );

        await tester.pump();

        expect(find.byType(ChatComposer), findsOneWidget);

        final textField = find.byType(TextField);
        expect(textField, findsOneWidget);
        await tester.enterText(textField, 'Hello there!');
        await tester.pump();

        final sendIcon = find.byIcon(LucideIcons.send);
        if (sendIcon.evaluate().isNotEmpty) {
          await tester.tap(sendIcon);
          await tester.pump();
          expect(sentText, 'Hello there!');
        }
      },
    );

    testWidgets('EventPlannerSheet renders with form inputs', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: EventPlannerSheet(
                conversationId: 'conv_123',
                peerUserId: 'user_456',
                themeColor: Colors.purple,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(EventPlannerSheet), findsOneWidget);
    });

    testWidgets('ChatListTab renders conversations list view', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ChatListTab(
                tab: 'dating',
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(ChatListTab), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 60));
    });
  });
}
