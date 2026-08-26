import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/features/chats/providers/chat_conversation_provider.dart';
import 'package:nexus/features/chats/providers/chats_providers.dart';
import 'package:nexus/features/chats/utils/chat_theme.dart';
import 'package:nexus/features/chats/widgets/chat_list_tile.dart';
import 'package:nexus/features/chats/widgets/message_bubble.dart';
import 'package:nexus/features/chats/widgets/presence_badge.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
