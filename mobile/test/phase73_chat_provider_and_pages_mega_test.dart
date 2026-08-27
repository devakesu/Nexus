import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/features/chats/providers/chat_conversation_provider.dart';
import 'package:nexus/features/chats/widgets/chat_composer.dart';
import 'package:nexus/features/chats/widgets/chat_list_tab.dart';
import 'package:nexus/features/chats/widgets/event_planner_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    ConsentCacheManager.safetyConsentGranted = true;
    ConsentCacheManager.specialCategoryConsentGranted = true;
    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        publishableKey: 'mock-anon-key',
      );
    } on Exception catch (_) {}
  });

  group('Phase 73 - Chat Provider and Pages Mega Tests', () {
    test('Chat Models deep serialization and copyWith', () {
      const media = MediaPointer(
        storagePath: 'media/test.jpg',
        mediaKeyBase64: 'mock-key-123',
        mimeType: 'image/jpeg',
        sizeBytes: 1024,
        durationMs: 500,
      );
      expect(
        MediaPointer.fromJson(media.toJson()).storagePath,
        'media/test.jpg',
      );

      const loc = LocationPointer(
        lat: 37.7749,
        lng: -122.4194,
        label: 'San Francisco',
      );
      expect(LocationPointer.fromJson(loc.toJson()).lat, 37.7749);

      const eventPayload = EventPayload(
        title: 'Coffee Meetup',
        notes: 'Casual chat',
      );
      expect(
        EventPayload.fromJson(eventPayload.toJson()).title,
        'Coffee Meetup',
      );

      final eventInfo = ChatEventInfo(
        eventId: 'ev_123',
        eventTime: DateTime.parse('2026-10-01T18:00:00Z'),
        locationLat: 37.7749,
        locationLng: -122.4194,
        locationLabel: 'Coffee shop',
        status: 'proposed',
      );
      expect(eventInfo.copyWith(status: 'accepted').status, 'accepted');

      final msgView = ChatMessageView(
        id: 'msg_1',
        senderId: 'user_1',
        isMine: true,
        createdAt: DateTime.now(),
        plaintext: 'Hello World',
        messageType: 'text',
        decryptFailed: false,
      );
      expect(
        msgView.copyWith(plaintext: 'New content').plaintext,
        'New content',
      );

      final convState = ChatConversationState(
        messages: [msgView],
        sessionReady: true,
        sending: false,
      );
      expect(convState.messages.length, 1);
    });

    testWidgets('ChatComposer renders cleanly', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatComposer(
              themeColor: Colors.pink,
              enabled: true,
              sending: false,
              onSend: (text) async {},
              onSendImage: (bytes, mime) async {},
              onSendVoice: (bytes, mime, duration) async {},
              onSendLocation: (lat, lng, label) async {},
              onPlanEvent: () {},
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(find.byType(ChatComposer), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('EventPlannerSheet and ChatListTab render correctly', (
      tester,
    ) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: EventPlannerSheet(
                conversationId: 'conv_123',
                peerUserId: 'user_peer_1',
                themeColor: Colors.pink,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(find.byType(EventPlannerSheet), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ChatListTab(tab: 'Dating'),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(find.byType(ChatListTab), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(seconds: 60));
    });
  });
}
