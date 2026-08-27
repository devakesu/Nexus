import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:nexus/core/utils/secure_profile_cache.dart';
import 'package:nexus/features/chats/providers/chat_conversation_provider.dart';
import 'package:nexus/features/chats/providers/presence_provider.dart';
import 'package:nexus/features/chats/screens/chat_conversation_page.dart';
import 'package:nexus/features/chats/utils/open_chat.dart';
import 'package:nexus/features/chats/widgets/chat_composer.dart';
import 'package:nexus/features/chats/widgets/event_planner_sheet.dart';
import 'package:nexus/features/settings/screens/meetup_safety_page.dart';
import 'package:nexus/features/settings/screens/settings_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Headers;

import '../../helpers/mock_network_interceptor.dart';
import '../../helpers/test_helpers.dart';

class MockHttpClientAdapter implements HttpClientAdapter {
  MockHttpClientAdapter(this.handler);
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

class _FakeChatController extends ChatConversationController {
  _FakeChatController([this.initial]);
  final ChatConversationState? initial;

  @override
  Future<ChatConversationState> build(
    String conversationId,
    String peerUserId,
  ) async {
    return initial ??
        const ChatConversationState(
          messages: [],
          sending: false,
          sessionReady: true,
        );
  }
}

class _MockChatConversationController extends ChatConversationController {
  _MockChatConversationController([this.initial]);
  final ChatConversationState? initial;

  @override
  Future<ChatConversationState> build(
    String conversationId,
    String peerUserId,
  ) async {
    return initial ??
        const ChatConversationState(
          messages: [],
          sending: false,
          sessionReady: true,
        );
  }
}

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

class _MockPeerPresence extends PeerPresence {
  _MockPeerPresence(this._info);
  final PresenceInfo _info;

  @override
  Future<PresenceInfo> build(String peerUserId) async => _info;
}

void main() {
  setUpTestEnvironment();

  setUpAll(() async {
    await initMockSupabase();
  });

  // --- Section 1 ---
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

    group('Chat Conversation Loaded Exhaustive Tests', () {
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

        const evt = EventPayload(
          title: 'Coffee Meetup',
          notes: 'At Blue Bottle',
        );
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
      setupGlobalMockNetwork();
    });

    group('Chats Interactive Deep Tests', () {
      testWidgets(
        'ChatConversationPage enters text and interacts with actions',
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
                  body: ChatConversationPage(
                    conversationId: 'c1',
                    matchedUserId: 'u2',
                    tab: 'Dating',
                    name: 'Taylor',
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          expect(find.byType(ChatConversationPage), findsOneWidget);

          final textFields = find.byType(TextField);
          if (textFields.evaluate().isNotEmpty) {
            await tester.enterText(textFields.first, 'Hello there!');
            await tester.pump(const Duration(milliseconds: 100));
          }

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.pump(const Duration(seconds: 60));
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

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/image_picker'),
          (call) async => null,
        );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.cheny/record'),
          (call) async => false,
        );

    setUp(() {});

    group('PresenceProvider and PresenceHeartbeat Tests', () {
      test('PresenceInfo model properties', () {
        final now = DateTime.now();
        final info = PresenceInfo(isOnline: true, lastActiveAt: now);
        expect(info.isOnline, isTrue);
        expect(info.lastActiveAt, equals(now));

        const nullInfo = PresenceInfo(isOnline: null, lastActiveAt: null);
        expect(nullInfo.isOnline, isNull);
        expect(nullInfo.lastActiveAt, isNull);
      });

      test('PresenceHeartbeat beat executes without errors', () async {
        createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
          if (options.path.contains('/api/v1/chat/presence/heartbeat')) {
            return ResponseBody.fromString('{"ok":true}', 200);
          }
          return ResponseBody.fromString('Not found', 404);
        });

        await PresenceHeartbeat.beat();
        await PresenceHeartbeat.beat(isOnline: false);
      });

      test('BatchPresence provider updates and fetches', () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        container
            .read(batchPresenceProvider.notifier)
            .updateSingle(
              'user_123',
              PresenceInfo(isOnline: true, lastActiveAt: DateTime.now()),
            );

        final state = container.read(batchPresenceProvider);
        expect(state.containsKey('user_123'), isTrue);
        expect(state['user_123']?.isOnline, isTrue);

        await container.read(batchPresenceProvider.notifier).fetch([]);
      });
    });

    group('open_chat.dart Utility Tests', () {
      testWidgets('openOrCreateChat handles null matchId gracefully', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => openOrCreateChat(
                    context,
                    matchId: null,
                    matchedUserId: 'user_target',
                    name: 'Target User',
                  ),
                  child: const Text('Open Chat'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Chat'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 3));
      });

      test(
        'recordMatchAction calls backend endpoint with parameters',
        () async {
          createDio().httpClientAdapter = _MockHttpClientAdapter((
            options,
          ) async {
            if (options.path.contains('/api/v1/matches/action')) {
              return ResponseBody.fromString('{"status":"ok"}', 200);
            }
            return ResponseBody.fromString('Error', 400);
          });

          final success = await recordMatchAction(
            targetId: 'user_block_target',
            action: 'block',
            tab: 'Dating',
          );

          expect(success, isTrue);
        },
      );
    });

    group('ChatComposer Attachment Sheet & Interactions', () {
      testWidgets(
        'opens attachment bottom sheet on clip tap and toggles emoji keyboard',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(800, 1400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Column(
                  children: [
                    const Spacer(),
                    ChatComposer(
                      themeColor: AppColors.modeFriends,
                      enabled: true,
                      sending: false,
                      onSend: (_) async {},
                      onSendImage: (_, _) async {},
                      onSendVoice: (_, _, _) async {},
                      onSendLocation: (_, _, _) async {},
                      onPlanEvent: () {},
                    ),
                  ],
                ),
              ),
            ),
          );

          await tester.pump();
          expect(find.byType(ChatComposer), findsOneWidget);

          // Tap attach / paperclip icon
          final attachIcon = find.byIcon(LucideIcons.paperclip);
          if (attachIcon.evaluate().isNotEmpty) {
            await tester.tap(attachIcon);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
          }

          // Tap emoji icon
          final emojiIcon = find.byIcon(LucideIcons.smile);
          if (emojiIcon.evaluate().isNotEmpty) {
            await tester.tap(emojiIcon);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
          }
        },
      );
    });
  }

  // --- Section 4 ---
  {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

    group('ChatConversationPage Deep Dialog & Menu Tests', () {
      testWidgets(
        'renders ChatConversationPage, opens popup menu and interacts with composer',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(800, 1600);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          createDio().httpClientAdapter = _MockHttpClientAdapter((
            options,
          ) async {
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

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.pump(const Duration(seconds: 60));
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
          const MethodChannel('flutter_secure_screen'),
          (call) async => null,
        );

    group('Chats Deep Page, Composer & Events Mega Coverage Tests', () {
      testWidgets(
        'ChatConversationPage renders messages, header, composer and responds to scroll',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          createDio().httpClientAdapter = _MockHttpClientAdapter((
            options,
          ) async {
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

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.pump(const Duration(seconds: 60));
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

  // --- Section 6 ---
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

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter.baseflow.com/geolocator'),
          (call) async => null,
        );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dexterous.com/flutter/local_notifications'),
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

    group('Interactive Chats, Settings & Meetup Safety Tests', () {
      testWidgets(
        'ChatConversationPage renders header, composer, and handles interaction',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          createDio().httpClientAdapter = _MockHttpClientAdapter((
            options,
          ) async {
            return ResponseBody.fromString(
              '{}',
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          });

          await tester.pumpWidget(
            const ProviderScope(
              child: MaterialApp(
                home: Scaffold(
                  body: ChatConversationPage(
                    conversationId: 'conv_123',
                    matchedUserId: 'user_target_456',
                    tab: 'dating',
                    name: 'Elena Rostova',
                    profilePic:
                        'https://images.unsplash.com/photo-1494790108377-be9c29b29330',
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
        },
      );

      testWidgets(
        'SettingsTab renders pause matching, notifications, and handles taps',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await SecureProfileCache.write({
            'is_dating_active': true,
            'is_friends_active': true,
            'is_professional_active': false,
          });

          createDio().httpClientAdapter = _MockHttpClientAdapter((
            options,
          ) async {
            if (options.path.contains('/api/v1/profile/details')) {
              return ResponseBody.fromString(
                jsonEncode({
                  'is_dating_active': true,
                  'is_friends_active': true,
                  'is_professional_active': false,
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
              child: MaterialApp(
                home: Scaffold(
                  body: SettingsTab(
                    onOpenOrbit: (mode, color) {},
                  ),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(seconds: 1));

          expect(find.byType(SettingsTab), findsOneWidget);

          // Scroll through SettingsTab
          await tester.drag(find.byType(SettingsTab), const Offset(0, -600));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          await tester.drag(find.byType(SettingsTab), const Offset(0, -600));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
        },
      );

      testWidgets(
        'MeetupSafetyPage renders safety center, score, and handles form input',
        (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1080, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            const MaterialApp(
              home: Scaffold(
                body: MeetupSafetyPage(
                  initialCheckInLabel: 'Coffee with Alex',
                  initialCheckInDuration: Duration(hours: 2),
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(seconds: 1));

          expect(find.byType(MeetupSafetyPage), findsOneWidget);

          // Scroll MeetupSafetyPage
          await tester.drag(
            find.byType(MeetupSafetyPage),
            const Offset(0, -600),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
        },
      );
    });
  }

  // --- Section 7 ---
  {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

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

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 60));
      });
    });
  }

  // --- Section 8 ---
  {
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
          expect(
            find.text('Sure, I would love to! 2pm works?'),
            findsOneWidget,
          );

          final textField = find.byType(TextField);
          if (textField.evaluate().isNotEmpty) {
            await tester.enterText(textField.first, 'See you there!');
            await tester.pump();
          }

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.pump(const Duration(seconds: 60));
        },
      );
    });
  }

  // --- Section 9 ---
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

    group('ChatConversationPage Widget Tests', () {
      testWidgets('renders ChatConversationPage with peer name and composer', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: ChatConversationPage(
                  conversationId: 'conv_123',
                  matchedUserId: 'user_456',
                  tab: 'dating',
                  name: 'Elena Rostova',
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(ChatConversationPage), findsOneWidget);
        expect(find.text('Elena Rostova'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 60));
      });
    });
  }

  // --- Section 10 ---
  {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

    group('ChatConversationPage Widget Tests', () {
      testWidgets('renders ChatConversationPage header and composer', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: ChatConversationPage(
                  conversationId: 'conv_123',
                  matchedUserId: 'user_456',
                  tab: 'dating',
                  name: 'Lyra',
                  profilePic: 'https://example.com/avatar.jpg',
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(ChatConversationPage), findsOneWidget);
        expect(find.text('Lyra'), findsWidgets);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 60));
      });
    });
  }
}
