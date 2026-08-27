import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/chats/utils/open_chat.dart';
import 'package:nexus/features/home/widgets/export_code_card.dart';
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

  group('ExportCodeCard & OpenChat Deep Coverage Tests', () {
    testWidgets('renders ExportCodeCard initial state', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ExportCodeCard(),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.byType(ExportCodeCard), findsOneWidget);
      expect(find.text('Export Profile Data'), findsOneWidget);
      expect(find.text('Share with your Nexus main account'), findsOneWidget);
      expect(find.text('Generate Export Code'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('openOrCreateChat handles null matchId gracefully', (
      tester,
    ) async {
      BuildContext? testContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                testContext = ctx;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      await tester.pump();
      expect(testContext, isNotNull);

      // Call openOrCreateChat with null matchId
      await openOrCreateChat(
        testContext!,
        matchId: null,
        matchedUserId: 'user_123',
        name: 'Alice',
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 3000));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
    });
  });
}
