import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/features/chats/providers/chat_conversation_provider.dart';
import 'package:nexus/features/chats/providers/chats_providers.dart';
import 'package:nexus/features/chats/utils/chat_theme.dart';
import 'package:nexus/features/chats/utils/open_chat.dart';
import 'package:nexus/features/chats/widgets/chat_list_tile.dart';
import 'package:nexus/features/chats/widgets/event_card.dart';
import 'package:nexus/features/chats/widgets/image_message_bubble.dart';
import 'package:nexus/features/chats/widgets/location_message_bubble.dart';
import 'package:nexus/features/chats/widgets/message_bubble.dart';
import 'package:nexus/features/chats/widgets/presence_badge.dart';
import 'package:nexus/features/chats/widgets/voice_message_bubble.dart';
import 'package:nexus/features/home/widgets/export_code_card.dart';
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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

    group('ExportCodeCard & OpenChat Deep Coverage Tests', () {
      testWidgets('renders ExportCodeCard initial state', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ExportCodeCard(),
              ),
            ),
          ),
        );

        await tester.pump();
        expect(find.byType(ExportCodeCard), findsOneWidget);
        expect(find.text('Export Profile Data'), findsOneWidget);
        expect(find.text('Share with your Nexus main account'), findsOneWidget);
        expect(find.text('Generate Export Code'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 300));
      });

      testWidgets('openOrCreateChat handles null matchId gracefully', (
        tester,
      ) async {
        BuildContext? testContext;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) {
                  testContext = ctx;
                  return const SizedBox();
                },
              ),
            ),
          ),
        );

        await tester.pump();
        expect(testContext, isNotNull);

        // Call openOrCreateChat with null matchId
        await openOrCreateChat(
          testContext!,
          matchId: null,
          matchedUserId: 'user_123',
          name: 'Alice',
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 3000));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));
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
      ConsentCacheManager.safetyConsentGranted = true;
      ConsentCacheManager.specialCategoryConsentGranted = true;
      try {
        await Supabase.initialize(
          url: 'https://mock.supabase.co',
          publishableKey: 'mock-anon-key',
        );
      } on Exception catch (_) {}
    });

    group('MessageBubble Exhaustive Tests', () {
      testWidgets('renders outgoing text message bubble', (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final msg = ChatMessageView(
          id: 'msg-1',
          senderId: '00000000-0000-0000-0000-000000000001',
          isMine: true,
          createdAt: DateTime(2026, 1, 1, 14, 30),
          messageType: 'text',
          plaintext: 'Hello from Nexus!',
          decryptFailed: false,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MessageBubble(
                message: msg,
                themeColor: AppColors.modeDating,
                conversationId: 'conv-1',
                peerUserId: 'user-2',
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(MessageBubble), findsOneWidget);
        expect(find.text('Hello from Nexus!'), findsOneWidget);
        expect(find.text('2:30 PM'), findsOneWidget);
      });

      testWidgets(
        'renders security alert bubble and triggers callback on tap',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          var securityAlertTapped = false;

          final msg = ChatMessageView(
            id: 'msg-2',
            senderId: '00000000-0000-0000-0000-000000000002',
            isMine: false,
            createdAt: DateTime(2026, 1, 1, 15, 45),
            messageType: 'security_alert',
            plaintext: 'Security code changed. Tap to verify.',
            decryptFailed: false,
          );

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: MessageBubble(
                  message: msg,
                  themeColor: AppColors.modeDating,
                  conversationId: 'conv-1',
                  peerUserId: 'user-2',
                  onSecurityAlertTapped: () {
                    securityAlertTapped = true;
                  },
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.byType(MessageBubble), findsOneWidget);
          expect(
            find.text('Security code changed. Tap to verify.'),
            findsOneWidget,
          );

          // Tap on security alert bubble
          await tester.tap(find.text('Security code changed. Tap to verify.'));
          await tester.pump();
          expect(securityAlertTapped, isTrue);
        },
      );
    });
  }

  // --- Section 3 ---
  {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

    group('LocationMessageBubble Widget Tests', () {
      testWidgets(
        'renders LocationMessageBubble with pin coordinates and label',
        (tester) async {
          const pointer = LocationPointer(
            lat: 37.7749,
            lng: -122.4194,
            label: 'Blue Bottle Coffee',
          );

          await tester.pumpWidget(
            const MaterialApp(
              home: Scaffold(
                body: Column(
                  children: [
                    LocationMessageBubble(
                      pointer: pointer,
                      isMine: true,
                    ),
                    LocationMessageBubble(
                      pointer: pointer,
                      isMine: false,
                    ),
                  ],
                ),
              ),
            ),
          );

          await tester.pump();

          expect(find.byType(LocationMessageBubble), findsNWidgets(2));
          expect(find.text('Blue Bottle Coffee'), findsNWidgets(2));
        },
      );
    });

    group('EventCard Widget Tests', () {
      testWidgets('renders EventCard with event title, datetime, and status', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        const payload = EventPayload(
          title: 'Dinner & Astronomy Talk',
          notes: 'Meet outside the planetarium at 7pm.',
        );

        final eventInfo = ChatEventInfo(
          eventId: 'event_1',
          eventTime: DateTime(2026, 9, 15, 19),
          locationLat: 34.1184,
          locationLng: -118.3004,
          locationLabel: 'Griffith Observatory',
          status: 'pending',
        );

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 320,
                    child: EventCard(
                      payload: payload,
                      eventInfo: eventInfo,
                      conversationId: 'conv_123',
                      peerUserId: 'user_bob',
                      themeColor: AppColors.modeDating,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(EventCard), findsOneWidget);
        expect(find.text('Dinner & Astronomy Talk'), findsOneWidget);
        expect(find.text('Griffith Observatory'), findsOneWidget);
        expect(
          find.text('Meet outside the planetarium at 7pm.'),
          findsOneWidget,
        );
      });
    });
  }

  // --- Section 4 ---
  {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

    group('Chat Models & Serialization Tests', () {
      test('MediaPointer serialization and deserialization', () {
        final json = {
          'storage_path': 'chat_media/img_123.jpg.enc',
          'media_key': 'bWVkaWFrZXkxMjM0NTY3ODkwMTI=',
          'mime_type': 'image/jpeg',
          'size_bytes': 10240,
          'duration_ms': 5000,
        };

        final pointer = MediaPointer.fromJson(json);
        expect(pointer.storagePath, 'chat_media/img_123.jpg.enc');
        expect(pointer.mediaKeyBase64, 'bWVkaWFrZXkxMjM0NTY3ODkwMTI=');
        expect(pointer.mimeType, 'image/jpeg');
        expect(pointer.sizeBytes, 10240);
        expect(pointer.durationMs, 5000);

        final exported = pointer.toJson();
        expect(exported['storage_path'], 'chat_media/img_123.jpg.enc');
        expect(exported['size_bytes'], 10240);
      });

      test('LocationPointer serialization and deserialization', () {
        final json = {
          'lat': 37.7749,
          'lng': -122.4194,
          'label': 'Mission Dolores Park',
        };

        final loc = LocationPointer.fromJson(json);
        expect(loc.lat, 37.7749);
        expect(loc.lng, -122.4194);
        expect(loc.label, 'Mission Dolores Park');

        final exported = loc.toJson();
        expect(exported['lat'], 37.7749);
        expect(exported['label'], 'Mission Dolores Park');
      });

      test('ChatConversationSummary and ChatCandidate serialization', () {
        final summaryJson = {
          'conversation_id': 'conv_1',
          'matched_user_id': 'user_1',
          'name': 'Alex',
          'age': 28,
          'profile_pic': 'https://example.com/alex.jpg',
          'last_message_at': '2026-08-26T12:00:00.000Z',
          'has_unread': true,
          'unread_count': 3,
        };

        final summary = ChatConversationSummary.fromJson(summaryJson);
        expect(summary.conversationId, 'conv_1');
        expect(summary.name, 'Alex');
        expect(summary.age, 28);
        expect(summary.hasUnread, isTrue);
        expect(summary.unreadCount, 3);

        final exported = summary.toJson();
        expect(exported['conversation_id'], 'conv_1');

        final candidateJson = {
          'match_id': 'match_10',
          'matched_user_id': 'user_10',
          'name': 'Taylor',
          'age': 25,
          'profile_pic': null,
          'matched_at': '2026-08-26T10:00:00.000Z',
        };
        final candidate = ChatCandidate.fromJson(candidateJson);
        expect(candidate.matchId, 'match_10');
        expect(candidate.name, 'Taylor');
      });

      test('ChatTabTheme returns valid color mappings', () {
        final datingTheme = chatTabTheme('Dating');
        expect(datingTheme.primary, AppColors.modeDating);

        final friendsTheme = chatTabTheme('Friends');
        expect(friendsTheme.primary, AppColors.modeFriends);

        final proTheme = chatTabTheme('Professional');
        expect(proTheme.primary, AppColors.modeProfessional);

        final fallback = chatTabTheme('Unknown');
        expect(fallback.primary, AppColors.modeDating);
      });
    });

    group('PresenceBadge & ChatListTile Widget Tests', () {
      testWidgets('renders PresenceBadge with peer id', (tester) async {
        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: PresenceBadge(
                  peerUserId: 'user_123',
                  poll: false,
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        expect(find.byType(PresenceBadge), findsOneWidget);
      });

      testWidgets(
        'renders ChatListTile with conversation summary and tap callback',
        (tester) async {
          final summary = ChatConversationSummary(
            conversationId: 'conv_1',
            matchedUserId: 'user_1',
            name: 'Alex Rivera',
            age: 26,
            profilePic: null,
            lastMessageAt: DateTime.now().subtract(const Duration(minutes: 5)),
            hasUnread: true,
            unreadCount: 2,
          );

          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                home: Scaffold(
                  body: ChatListTile(
                    conversation: summary,
                    tab: 'Dating',
                    themeColor: AppColors.modeDating,
                  ),
                ),
              ),
            ),
          );

          await tester.pump();

          expect(find.text('Alex Rivera, 26'), findsOneWidget);
          expect(find.text('2'), findsOneWidget);
        },
      );
    });

    group('MessageBubble Widget Tests', () {
      testWidgets('renders MessageBubble text message and format time', (
        tester,
      ) async {
        final msg = ChatMessageView(
          id: 'msg_1',
          senderId: 'user_me',
          isMine: true,
          createdAt: DateTime(2026, 8, 26, 14, 30),
          plaintext: 'Hello from Signal E2EE!',
          messageType: 'text',
          decryptFailed: false,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MessageBubble(
                message: msg,
                themeColor: AppColors.modeDating,
                conversationId: 'conv_123',
                peerUserId: 'user_peer',
              ),
            ),
          ),
        );

        await tester.pump();

        expect(find.text('Hello from Signal E2EE!'), findsOneWidget);
        expect(find.text('2:30 PM'), findsOneWidget);
      });

      testWidgets(
        'renders MessageBubble decryption failure with alert callback',
        (tester) async {
          final failedMsg = ChatMessageView(
            id: 'msg_fail',
            senderId: 'user_peer',
            isMine: false,
            createdAt: DateTime.now(),
            plaintext: null,
            messageType: 'text',
            decryptFailed: true,
          );

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: MessageBubble(
                  message: failedMsg,
                  themeColor: AppColors.modeDating,
                  conversationId: 'conv_123',
                  peerUserId: 'user_peer',
                  onSecurityAlertTapped: () {},
                ),
              ),
            ),
          );

          await tester.pump();

          expect(find.text('Could not decrypt this message'), findsOneWidget);
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
          const MethodChannel('com.ryanheise.just_audio.methods'),
          (call) async => null,
        );

    group('VoiceMessageBubble & ImageMessageBubble Widget Tests', () {
      testWidgets(
        'renders VoiceMessageBubble with play/pause controls and handles tap',
        (tester) async {
          tester.view.physicalSize = const Size(800, 1400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          const pointer = MediaPointer(
            storagePath: 'voice/audio_123.enc',
            mimeType: 'audio/m4a',
            mediaKeyBase64: 'MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY=',
            durationMs: 4500,
          );

          await tester.pumpWidget(
            const ProviderScope(
              child: MaterialApp(
                home: Scaffold(
                  body: VoiceMessageBubble(
                    pointer: pointer,
                    conversationId: 'conv_123',
                    peerUserId: 'user_456',
                    isMine: true,
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.byType(VoiceMessageBubble), findsOneWidget);

          await tester.tap(find.byType(VoiceMessageBubble));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
        },
      );

      testWidgets('renders ImageMessageBubble with preview placeholder', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        const pointer = MediaPointer(
          storagePath: 'photos/photo_123.enc',
          mimeType: 'image/jpeg',
          mediaKeyBase64: 'MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY=',
        );

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: ImageMessageBubble(
                  pointer: pointer,
                  conversationId: 'conv_123',
                  peerUserId: 'user_456',
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(ImageMessageBubble), findsOneWidget);
      });
    });
  }
}
