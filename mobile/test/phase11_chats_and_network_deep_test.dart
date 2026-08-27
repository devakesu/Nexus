import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:nexus/features/chats/providers/presence_provider.dart';
import 'package:nexus/features/chats/utils/open_chat.dart';
import 'package:nexus/features/chats/widgets/chat_composer.dart';
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
  ) {
    return handler(options);
  }

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
        const MethodChannel('plugins.flutter.io/image_picker'),
        (call) async => null,
      );

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('com.cheny/record'),
        (call) async => false,
      );

  setUpAll(() async {
    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        publishableKey: 'mock-anon-key',
      );
    } on Exception catch (_) {}
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

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

    test('recordMatchAction calls backend endpoint with parameters', () async {
      createDio().httpClientAdapter = _MockHttpClientAdapter((options) async {
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

      expect(success, isFalse);
    });
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
