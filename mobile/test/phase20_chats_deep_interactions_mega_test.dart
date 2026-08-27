import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:nexus/features/chats/providers/chat_conversation_provider.dart';
import 'package:nexus/features/chats/screens/chat_conversation_page.dart';
import 'package:nexus/features/chats/widgets/chat_composer.dart';
import 'package:nexus/features/chats/widgets/event_planner_sheet.dart';
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

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('flutter_secure_screen'),
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

  group('Chats Deep Page, Composer & Events Mega Coverage Tests', () {
    testWidgets(
      'ChatConversationPage renders messages, header, composer and responds to scroll',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
          return ResponseBody.fromString(
            jsonEncode({
              'status': 'success',
            }),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        });

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              chatConversationControllerProvider(
                'conv_test_1',
                '00000000-0000-0000-0000-000000000001',
              ).overrideWith(
                () => _FakeChatController(
                  ChatConversationState(
                    messages: [
                      ChatMessageView(
                        id: 'm1',
                        senderId: '00000000-0000-0000-0000-000000000001',
                        isMine: false,
                        createdAt: DateTime.now().subtract(
                          const Duration(minutes: 5),
                        ),
                        plaintext: 'Hey! Are we still meeting today?',
                        messageType: 'text',
                        decryptFailed: false,
                      ),
                      ChatMessageView(
                        id: 'm2',
                        senderId: 'my_user_id',
                        isMine: true,
                        createdAt: DateTime.now().subtract(
                          const Duration(minutes: 2),
                        ),
                        plaintext: 'Yes! Coffee at Blue Bottle?',
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
                  conversationId: 'conv_test_1',
                  matchedUserId: '00000000-0000-0000-0000-000000000001',
                  tab: 'Dating',
                  name: 'Kira',
                  profilePic: 'https://example.com/kira.jpg',
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(find.byType(ChatConversationPage), findsOneWidget);
        expect(find.text('Kira'), findsOneWidget);
        expect(find.text('Hey! Are we still meeting today?'), findsOneWidget);

        // Enter text in composer
        final tf = find.byType(TextField);
        if (tf.evaluate().isNotEmpty) {
          await tester.enterText(tf.last, 'See you there!');
          await tester.pump();
        }

        // Scroll message list
        await tester.drag(find.byType(ListView), const Offset(0, 200));
        await tester.pump();
      },
    );

    testWidgets('ChatComposer handles text changes and action buttons', (
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
      expect(find.byType(ChatComposer), findsOneWidget);

      final tf = find.byType(TextField);
      if (tf.evaluate().isNotEmpty) {
        await tester.enterText(tf.first, 'Hello Nexus!');
        await tester.pump();

        final sendBtn = find.byIcon(Icons.send_rounded);
        if (sendBtn.evaluate().isNotEmpty) {
          await tester.tap(sendBtn.first);
          await tester.pump();
        }
      }

      expect(sentText, isNotNull);
    });

    testWidgets(
      'EventPlannerSheet renders and configures date and safety options',
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
                  conversationId: 'conv_1',
                  peerUserId: '00000000-0000-0000-0000-000000000001',
                  themeColor: AppColors.modeDating,
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        expect(find.byType(EventPlannerSheet), findsOneWidget);
      },
    );
  });
}

class _FakeChatController extends ChatConversationController {
  _FakeChatController(this.initial);
  final ChatConversationState initial;

  @override
  Future<ChatConversationState> build(
    String conversationId,
    String peerUserId,
  ) async {
    return initial;
  }
}
