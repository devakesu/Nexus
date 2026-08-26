import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/features/chats/providers/chats_providers.dart';
import 'package:nexus/features/chats/screens/chats_page.dart';
import 'package:nexus/features/chats/widgets/chat_composer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockChatConversations extends ChatConversations {
  MockChatConversations(this.mockData);
  final List<ChatConversationSummary> mockData;

  @override
  Future<List<ChatConversationSummary>> build(String tab) async => mockData;
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

  group('ChatComposer Widget Tests', () {
    testWidgets('renders ChatComposer text input and send action', (
      tester,
    ) async {
      String? sentText;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatComposer(
              themeColor: AppColors.modeDating,
              enabled: true,
              sending: false,
              onSend: (text) async => sentText = text,
              onSendImage: (b, m) async {},
              onSendVoice: (b, m, d) async {},
              onSendLocation: (lat, lng, l) async {},
              onPlanEvent: () {},
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.byType(TextField), findsOneWidget);

      // Enter message text
      await tester.enterText(find.byType(TextField), 'Hello there!');
      await tester.pump();

      // Tap send button
      await tester.tap(find.byIcon(LucideIcons.send));
      await tester.pump();

      expect(sentText, 'Hello there!');
    });
  });

  group('ChatsPage Widget Tests', () {
    testWidgets('renders ChatsPage with 3 tabs and tab navigation', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatConversationsProvider('Dating').overrideWith(
              () => MockChatConversations(const []),
            ),
            chatConversationsProvider('Friends').overrideWith(
              () => MockChatConversations(const []),
            ),
            chatConversationsProvider('Professional').overrideWith(
              () => MockChatConversations(const []),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: ChatsPage(),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(ChatsPage), findsOneWidget);
      expect(find.text('Dating'), findsOneWidget);
      expect(find.text('Friends'), findsOneWidget);
      expect(find.text('Professional'), findsOneWidget);

      // Tap Friends tab
      await tester.tap(find.text('Friends'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Tap Professional tab
      await tester.tap(find.text('Professional'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });
  });
}
