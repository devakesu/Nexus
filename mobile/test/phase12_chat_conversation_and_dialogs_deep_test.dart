import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:nexus/features/chats/providers/chat_conversation_provider.dart';
import 'package:nexus/features/chats/screens/chat_conversation_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Headers;

class _MockHttpClientAdapter implements HttpClientAdapter {
  _MockHttpClientAdapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => handler(options);

  @override
  void close({bool force = false}) {}
}

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

  group('ChatConversationPage Deep Dialog & Menu Tests', () {
    testWidgets(
      'renders ChatConversationPage, opens popup menu and interacts with composer',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
          if (options.path.contains('/api/v1/profile/candidate/')) {
            return ResponseBody.fromString(
              jsonEncode({
                'id': 'matched_usr_12',
                'name': 'Kira Nerys',
                'age': 28,
                'bio': 'Deep space logistics manager.',
                'ordered_images': ['https://example.com/kira.jpg'],
              }),
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          }
          return ResponseBody.fromString('{}', 200);
        });

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              chatConversationControllerProvider(
                'conv_test_12',
                'matched_usr_12',
              ).overrideWith(
                () => _MockChatConversationController(
                  ChatConversationState(
                    messages: [
                      ChatMessageView(
                        id: 'msg_1',
                        senderId: 'matched_usr_12',
                        plaintext: 'Hey there! Nice to meet you.',
                        createdAt: DateTime.now().subtract(
                          const Duration(minutes: 5),
                        ),
                        isMine: false,
                        messageType: 'text',
                        decryptFailed: false,
                      ),
                      ChatMessageView(
                        id: 'msg_2',
                        senderId: 'current_user',
                        plaintext: 'Hi Kira! Love your taste in music.',
                        createdAt: DateTime.now().subtract(
                          const Duration(minutes: 2),
                        ),
                        isMine: true,
                        messageType: 'text',
                        decryptFailed: false,
                      ),
                    ],
                    sessionReady: true,
                    sending: false,
                  ),
                ),
              ),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: ChatConversationPage(
                  conversationId: 'conv_test_12',
                  matchedUserId: 'matched_usr_12',
                  tab: 'Dating',
                  name: 'Kira Nerys',
                  profilePic: 'https://example.com/kira.jpg',
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        expect(find.byType(ChatConversationPage), findsOneWidget);
        expect(find.text('Kira Nerys'), findsWidgets);

        // Tap more actions popup menu button
        final moreBtn = find.byIcon(LucideIcons.ellipsisVertical);
        if (moreBtn.evaluate().isNotEmpty) {
          await tester.tap(moreBtn);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          // Dismiss popup menu
          await tester.tapAt(const Offset(10, 10));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
        }

        // Enter text into ChatComposer
        final composerInput = find.byType(TextField);
        if (composerInput.evaluate().isNotEmpty) {
          await tester.enterText(
            composerInput.first,
            'How is the weather today?',
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));

          final sendBtn = find.byIcon(LucideIcons.arrowUp);
          if (sendBtn.evaluate().isNotEmpty) {
            await tester.tap(sendBtn, warnIfMissed: false);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
          }
        }
      },
    );
  });
}

class _MockChatConversationController extends ChatConversationController {
  _MockChatConversationController(this.initialState);
  final ChatConversationState initialState;

  @override
  Future<ChatConversationState> build(
    String conversationId,
    String peerUserId,
  ) async {
    return initialState;
  }
}
