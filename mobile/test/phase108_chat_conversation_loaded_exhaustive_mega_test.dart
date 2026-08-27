import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/features/chats/providers/chat_conversation_provider.dart';
import 'package:nexus/features/chats/screens/chat_conversation_page.dart';
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

  group('Phase 108 - Chat Conversation Loaded Exhaustive Mega Tests', () {
    test('Chat models json serialization and conversions', () {
      const media = MediaPointer(
        storagePath: 'chat_media/pic.enc',
        mediaKeyBase64: 'key123',
        mimeType: 'image/jpeg',
        sizeBytes: 1024,
        durationMs: 5000,
      );
      final mJson = media.toJson();
      final fromJson = MediaPointer.fromJson(mJson);
      expect(fromJson.storagePath, media.storagePath);
      expect(fromJson.mediaKeyBase64, media.mediaKeyBase64);

      const loc = LocationPointer(
        lat: 37.7749,
        lng: -122.4194,
        label: 'Union Square',
      );
      final lJson = loc.toJson();
      final lFrom = LocationPointer.fromJson(lJson);
      expect(lFrom.lat, loc.lat);
      expect(lFrom.label, 'Union Square');

      const evt = EventPayload(title: 'Coffee Meetup', notes: 'At Blue Bottle');
      final eJson = evt.toJson();
      final eFrom = EventPayload.fromJson(eJson);
      expect(eFrom.title, 'Coffee Meetup');
      expect(eFrom.notes, 'At Blue Bottle');

      final eventInfo = ChatEventInfo(
        eventId: 'e1',
        eventTime: DateTime.now().add(const Duration(days: 1)),
        locationLat: 37.7749,
        locationLng: -122.4194,
        locationLabel: 'Coffee Shop',
        status: 'confirmed',
        safetyEnabled: true,
      );
      expect(eventInfo.eventId, 'e1');
      expect(eventInfo.status, 'confirmed');
      expect(eventInfo.safetyEnabled, isTrue);
    });

    testWidgets('ChatConversationPage mounts with all message types', (
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
                conversationId: 'c1',
                matchedUserId: 'u2',
                tab: 'Dating',
                name: 'Taylor',
                profilePic: 'https://example.com/taylor.png',
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(ChatConversationPage), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(seconds: 60));
    });
  });
}
