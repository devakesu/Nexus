import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/chats/providers/chat_conversation_provider.dart';
import 'package:nexus/features/chats/providers/presence_provider.dart';
import 'package:nexus/features/chats/screens/chat_conversation_page.dart';
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

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('dexterous.com/flutter/local_notifications'),
        (call) async => null,
      );

  setUpAll(() async {
    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        publishableKey: 'mock-anon-key',
      );
    } on Exception catch (_) {}
  });

  const convId = 'conv_interactive_101';
  const peerId = 'user_interactive_peer';

  final now = DateTime.now();
  final messages = [
    ChatMessageView(
      id: 'msg_1',
      senderId: peerId,
      isMine: false,
      createdAt: now.subtract(const Duration(minutes: 5)),
      plaintext: 'Hey! Are you free for coffee later?',
      messageType: 'text',
      decryptFailed: false,
    ),
    ChatMessageView(
      id: 'msg_2',
      senderId: 'my_user_id',
      isMine: true,
      createdAt: now.subtract(const Duration(minutes: 4)),
      plaintext: 'Sure, I would love to! 2pm works?',
      messageType: 'text',
      decryptFailed: false,
      readAt: now.subtract(const Duration(minutes: 3)),
    ),
    ChatMessageView(
      id: 'msg_3',
      senderId: peerId,
      isMine: false,
      createdAt: now.subtract(const Duration(minutes: 2)),
      plaintext: 'Perfect, see you at Blue Bottle!',
      messageType: 'text',
      decryptFailed: false,
    ),
  ];

  final mockState = ChatConversationState(
    messages: messages,
    sessionReady: true,
    sending: false,
    hasMoreHistory: false,
  );

  group('ChatConversationPage Interactive Full Tests', () {
    testWidgets(
      'renders conversation with messages, presence, and handles text input',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              chatConversationControllerProvider(convId, peerId).overrideWith(
                () => _MockChatConversationController(mockState),
              ),
              peerPresenceProvider(peerId).overrideWith(
                () => _MockPeerPresence(
                  const PresenceInfo(isOnline: true, lastActiveAt: null),
                ),
              ),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: ChatConversationPage(
                  conversationId: convId,
                  matchedUserId: peerId,
                  tab: 'dating',
                  name: 'Elena Rostova',
                  profilePic: 'https://example.com/elena.jpg',
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 2));

        expect(find.byType(ChatConversationPage), findsOneWidget);
        expect(find.text('Elena Rostova'), findsOneWidget);
        expect(
          find.text('Hey! Are you free for coffee later?'),
          findsOneWidget,
        );
        expect(find.text('Sure, I would love to! 2pm works?'), findsOneWidget);

        final textField = find.byType(TextField);
        if (textField.evaluate().isNotEmpty) {
          await tester.enterText(textField.first, 'See you there!');
          await tester.pump();
        }
      },
    );
  });
}

class _MockChatConversationController extends ChatConversationController {
  _MockChatConversationController(this._state);

  final ChatConversationState _state;

  @override
  Future<ChatConversationState> build(
    String conversationId,
    String matchedUserId,
  ) async => _state;
}

class _MockPeerPresence extends PeerPresence {
  _MockPeerPresence(this._info);

  final PresenceInfo _info;

  @override
  Future<PresenceInfo> build(String peerUserId) async => _info;
}
