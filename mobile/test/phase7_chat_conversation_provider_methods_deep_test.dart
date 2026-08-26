import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/chats/providers/chat_conversation_provider.dart';
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

  group('ChatConversationController Provider Deep Tests', () {
    test('non-UUID peerId returns closed state immediately', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = await container.read(
        chatConversationControllerProvider('conv_test', 'non-uuid-peer').future,
      );

      expect(state.messages.isEmpty, isTrue);
      expect(state.sessionReady, isFalse);
      expect(state.sending, isFalse);
      expect(state.conversationClosed, isTrue);
    });

    test(
      'valid UUID peerId initializes state with revalidating shell',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        const validUuid = '11111111-1111-1111-1111-111111111111';
        final state = await container.read(
          chatConversationControllerProvider(
            'conv_uuid_test',
            validUuid,
          ).future,
        );

        expect(state.messages.isEmpty, isTrue);
        expect(state.sessionReady, isFalse);
        expect(state.sending, isFalse);
      },
    );
  });
}
