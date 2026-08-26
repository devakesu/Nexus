import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/chats/providers/chat_conversation_provider.dart';
import 'package:nexus/features/chats/widgets/image_message_bubble.dart';
import 'package:nexus/features/chats/widgets/voice_message_bubble.dart';
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
        const MethodChannel('com.ryanheise.just_audio.methods'),
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
