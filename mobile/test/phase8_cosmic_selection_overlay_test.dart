import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/chats/utils/open_chat.dart';
import 'package:nexus/features/profile/widgets/cosmic_selection_overlay.dart';
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

  group('CosmicSelectionOverlay Widget Tests', () {
    testWidgets('renders options and filters by search query', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CosmicSelectionOverlay(
              title: 'SELECT STAR SIGN',
              options: ['Aries', 'Taurus', 'Gemini', 'Cancer', 'Leo'],
              currentValue: 'Gemini',
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('SELECT STAR SIGN'), findsOneWidget);
      expect(find.text('Aries'), findsOneWidget);
      expect(find.text('Taurus'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Leo');
      await tester.pump();

      expect(find.text('Leo'), findsWidgets);
      expect(find.text('Aries'), findsNothing);
    });
  });

  group('OpenChat Utility Tests', () {
    testWidgets('openOrCreateChat handles null matchId gracefully', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () => openOrCreateChat(
                    context,
                    matchId: null,
                    matchedUserId: 'user_456',
                    name: 'Luna',
                  ),
                  child: const Text('Open Null Match Chat'),
                );
              },
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.tap(find.text('Open Null Match Chat'));
      await tester.pump();

      expect(
        find.text('Still setting up this match, try again in a moment.'),
        findsOneWidget,
      );
    });
  });
}
