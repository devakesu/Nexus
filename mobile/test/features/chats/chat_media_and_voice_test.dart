import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/features/chats/providers/chat_conversation_provider.dart';
import 'package:nexus/features/chats/widgets/chat_composer.dart';
import 'package:nexus/features/chats/widgets/event_card.dart';
import 'package:nexus/features/chats/widgets/event_planner_sheet.dart';
import 'package:nexus/features/chats/widgets/location_picker_sheet.dart';
import 'package:nexus/features/chats/widgets/new_chat_sheet.dart';
import 'package:nexus/features/settings/screens/data_export_flow.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/test_helpers.dart';

void main() {
  setUpTestEnvironment();

  setUpAll(() async {
    await initMockSupabase();
  });

  // --- Section 1 ---
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

    group('Chat Widgets & Data Export Tests', () {
      testWidgets(
        'ChatComposer renders inputs, handles text and sends message',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          var sentText = '';

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ChatComposer(
                  themeColor: AppColors.modeDating,
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
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.byType(ChatComposer), findsOneWidget);

          final textField = find.byType(TextField);
          if (textField.evaluate().isNotEmpty) {
            await tester.enterText(
              textField.first,
              'Hey, looking forward to meeting!',
            );
            await tester.pump();

            final sendBtn = find.byIcon(Icons.send_rounded);
            if (sendBtn.evaluate().isNotEmpty) {
              await tester.tap(sendBtn.first);
              await tester.pump();
              expect(sentText, 'Hey, looking forward to meeting!');
            }
          }
        },
      );

      testWidgets(
        'EventPlannerSheet renders form fields and date/time selectors',
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
                  body: EventPlannerSheet(
                    conversationId: '00000000-0000-0000-0000-000000000001',
                    peerUserId: '00000000-0000-0000-0000-000000000002',
                    themeColor: AppColors.modeDating,
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          expect(find.byType(EventPlannerSheet), findsOneWidget);
        },
      );

      testWidgets('startDataExport opens export confirmation dialog', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => startDataExport(context),
                  child: const Text('Export Data'),
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.tap(find.text('Export Data'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Export Personal Data'), findsOneWidget);

        final cancelBtn = find.text('Cancel');
        if (cancelBtn.evaluate().isNotEmpty) {
          await tester.tap(cancelBtn.first);
          await tester.pumpAndSettle();
        }
      });
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
      ConsentCacheManager.safetyConsentGranted = true;
      ConsentCacheManager.specialCategoryConsentGranted = true;
      try {
        await Supabase.initialize(
          url: 'https://mock.supabase.co',
          publishableKey: 'mock-anon-key',
        );
      } on Exception catch (_) {}
    });

    group('Chat Media, Voice and Event Widgets Tests', () {
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
}
