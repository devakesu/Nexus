import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/features/chats/providers/chat_conversation_provider.dart';
import 'package:nexus/features/chats/widgets/event_card.dart';
import 'package:nexus/features/chats/widgets/location_picker_sheet.dart';
import 'package:nexus/features/chats/widgets/new_chat_sheet.dart';
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

  group('Phase 84 - Chat Media, Voice and Event Widgets Mega Tests', () {
    testWidgets(
      'LocationPickerSheet, NewChatSheet, and EventCard render cleanly',
      (
        tester,
      ) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: LocationPickerSheet(themeColor: Colors.pink),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(find.byType(LocationPickerSheet), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: NewChatSheet(tab: 'Dating'),
              ),
            ),
          ),
        );

        await tester.pump();
        expect(find.byType(NewChatSheet), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        const payload = EventPayload(
          title: 'Coffee at Blue Bottle',
          notes: 'See you at 3pm',
        );
        final eventInfo = ChatEventInfo(
          eventId: 'ev_test_1',
          eventTime: DateTime.parse('2026-10-15T15:00:00Z'),
          locationLat: 37.7749,
          locationLng: -122.4194,
          locationLabel: 'Blue Bottle Coffee',
          status: 'proposed',
        );

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: EventCard(
                  payload: payload,
                  eventInfo: eventInfo,
                  conversationId: 'conv_123',
                  peerUserId: 'user_2',
                  themeColor: Colors.pink,
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        expect(find.byType(EventCard), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      },
    );
  });
}
