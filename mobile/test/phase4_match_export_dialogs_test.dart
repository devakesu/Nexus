import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/features/home/widgets/export_code_card.dart';
import 'package:nexus/features/home/widgets/interests_overlay.dart';
import 'package:nexus/features/home/widgets/match_screen.dart';
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

  group('MatchScreen Tests', () {
    testWidgets('renders MatchScreen with match celebration and buttons', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<bool>(
              builder: (ctx) => const MatchScreen(
                matchedName: 'Sophia',
                subtitleText: 'You and Sophia liked each other',
              ),
            ),
          ),
        ),
      );

      // Animate controller forward (850ms duration)
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));

      expect(find.text("It's a Match! 💘"), findsOneWidget);
      expect(find.text('You and Sophia liked each other'), findsOneWidget);
      expect(find.text('Send a message'), findsOneWidget);
      expect(find.text('Keep browsing'), findsOneWidget);

      // Tap Send a message
      await tester.tap(find.text('Send a message'));
      await tester.pumpAndSettle();
    });
  });

  group('ExportCodeCard Tests', () {
    testWidgets('renders ExportCodeCard and handles generate code button', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ExportCodeCard(),
          ),
        ),
      );

      await tester.pump();
      expect(find.byType(ExportCodeCard), findsOneWidget);
      expect(find.text('Export Profile Data'), findsOneWidget);

      // Tap generate code button
      await tester.tap(find.text('Export Profile Data'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    });
  });

  group('InterestsOverlay & SubInterest Tests', () {
    test('SubInterest model test', () {
      const sub = SubInterest('Artificial Intelligence');
      expect(sub.name, 'Artificial Intelligence');
    });

    testWidgets(
      'renders InterestsOverlay, handles search and category toggle',
      (tester) async {
        var savedInterests = <String>[];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: InterestsOverlay(
                initialSelected: const ['Python', 'Web Development'],
                themeColor: AppColors.modeProfessional,
                onSave: (interests) => savedInterests = interests,
              ),
            ),
          ),
        );

        await tester.pump();

        expect(find.text('Affinity & Interests'), findsOneWidget);
        expect(find.text('Save Alignments'), findsOneWidget);

        // Search for Python
        await tester.enterText(find.byType(TextField), 'Python');
        await tester.pump();

        // Clear search
        await tester.enterText(find.byType(TextField), '');
        await tester.pump();

        // Tap save alignments
        await tester.tap(find.text('Save Alignments'));
        await tester.pump();

        expect(savedInterests, contains('Python'));
        expect(savedInterests, contains('Web Development'));
      },
    );
  });
}
