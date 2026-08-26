import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/chats/providers/chat_conversation_provider.dart';
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

  setUpAll(() async {
    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        publishableKey: 'mock-anon-key',
      );
    } on Exception catch (_) {}
  });

  group('Chat Models Unit Tests', () {
    test('MediaPointer serializes and deserializes accurately', () {
      const pointer = MediaPointer(
        storagePath: 'chat_media/123/img.jpg',
        mediaKeyBase64: 'abc123key==',
        mimeType: 'image/jpeg',
        sizeBytes: 1024,
        durationMs: 5000,
      );

      final json = pointer.toJson();
      expect(json['storage_path'], 'chat_media/123/img.jpg');
      expect(json['media_key'], 'abc123key==');
      expect(json['mime_type'], 'image/jpeg');
      expect(json['size_bytes'], 1024);
      expect(json['duration_ms'], 5000);

      final decoded = MediaPointer.fromJson(json);
      expect(decoded.storagePath, pointer.storagePath);
      expect(decoded.mediaKeyBase64, pointer.mediaKeyBase64);
      expect(decoded.mimeType, pointer.mimeType);
      expect(decoded.sizeBytes, 1024);
      expect(decoded.durationMs, 5000);
    });

    test('LocationPointer serializes and deserializes accurately', () {
      const loc = LocationPointer(
        lat: 37.7749,
        lng: -122.4194,
        label: 'Market St, San Francisco',
      );

      final json = loc.toJson();
      expect(json['lat'], 37.7749);
      expect(json['lng'], -122.4194);
      expect(json['label'], 'Market St, San Francisco');

      final decoded = LocationPointer.fromJson(json);
      expect(decoded.lat, 37.7749);
      expect(decoded.lng, -122.4194);
      expect(decoded.label, 'Market St, San Francisco');
    });

    test('EventPayload serializes and deserializes accurately', () {
      const event = EventPayload(
        title: 'Coffee at Blue Bottle',
        notes: 'Meet by the entrance at 3pm',
      );

      final json = event.toJson();
      expect(json['title'], 'Coffee at Blue Bottle');
      expect(json['notes'], 'Meet by the entrance at 3pm');

      final decoded = EventPayload.fromJson(json);
      expect(decoded.title, 'Coffee at Blue Bottle');
      expect(decoded.notes, 'Meet by the entrance at 3pm');
    });

    test('ChatEventInfo creates from row and copyWith works', () {
      final now = DateTime.now();
      final eventInfo = ChatEventInfo(
        eventId: 'evt_101',
        eventTime: now,
        locationLat: 37.7749,
        locationLng: -122.4194,
        locationLabel: 'Blue Bottle Coffee',
        status: 'proposed',
        safetyEnabled: true,
      );

      expect(eventInfo.eventId, 'evt_101');
      expect(eventInfo.status, 'proposed');
      expect(eventInfo.safetyEnabled, true);

      final updated = eventInfo.copyWith(status: 'accepted');
      expect(updated.status, 'accepted');
      expect(updated.eventId, 'evt_101');
    });

    test('ChatMessageView and ChatConversationState copyWith works', () {
      final msg = ChatMessageView(
        id: 'msg_1',
        senderId: 'user_1',
        isMine: true,
        createdAt: DateTime.now(),
        plaintext: 'Hello there!',
        messageType: 'text',
        decryptFailed: false,
      );

      expect(msg.id, 'msg_1');
      expect(msg.plaintext, 'Hello there!');

      final modified = msg.copyWith(
        plaintext: 'Updated text',
        decryptFailed: true,
      );
      expect(modified.plaintext, 'Updated text');
      expect(modified.decryptFailed, true);

      final state = ChatConversationState(
        messages: [msg],
        sessionReady: true,
        sending: false,
      );

      expect(state.messages.length, 1);
      expect(state.sessionReady, true);

      final nextState = state.copyWith(sending: true);
      expect(nextState.sending, true);
    });
  });

  group('ChatConversationPage Deep Widget Tests', () {
    testWidgets('renders ChatConversationPage with header and message list', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockMessages = [
        ChatMessageView(
          id: 'msg_1',
          senderId: 'other_user',
          isMine: false,
          createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
          plaintext: 'Hey! Ready for the weekend?',
          messageType: 'text',
          decryptFailed: false,
        ),
        ChatMessageView(
          id: 'msg_2',
          senderId: 'user_me',
          isMine: true,
          createdAt: DateTime.now().subtract(const Duration(minutes: 4)),
          plaintext: 'Absolutely, let’s do coffee!',
          messageType: 'text',
          decryptFailed: false,
        ),
      ];

      final mockState = ChatConversationState(
        messages: mockMessages,
        sessionReady: true,
        sending: false,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatConversationControllerProvider(
              'conv_123',
              'other_user',
            ).overrideWith(
              () => _MockChatConversationController(mockState),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: ChatConversationPage(
                conversationId: 'conv_123',
                matchedUserId: 'other_user',
                tab: 'Dating',
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
      expect(find.text('Elena Rostova'), findsWidgets);
      expect(find.text('Hey! Ready for the weekend?'), findsOneWidget);
      expect(find.text('Absolutely, let’s do coffee!'), findsOneWidget);
    });
  });
}

class _MockChatConversationController extends ChatConversationController {
  _MockChatConversationController(this._initialState);

  final ChatConversationState _initialState;

  @override
  Future<ChatConversationState> build(
    String conversationId,
    String peerUserId,
  ) async {
    return _initialState;
  }
}
