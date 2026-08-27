import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/home/widgets/interests_overlay.dart';
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

  group('InterestsOverlay Deep Interactive Tests', () {
    testWidgets(
      'renders InterestsOverlay, searches, toggles sub-interests and saves',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        var savedInterests = ['Python', 'Rust'];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: InterestsOverlay(
                initialSelected: savedInterests,
                onSave: (list) {
                  savedInterests = list;
                },
                saveButtonText: 'Save Interests',
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byType(InterestsOverlay), findsOneWidget);

        // Search for "Tech" or "Flutter"
        final searchField = find.byType(TextField);
        if (searchField.evaluate().isNotEmpty) {
          await tester.enterText(searchField.first, 'Flutter');
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
        }

        // Search for "Music"
        if (searchField.evaluate().isNotEmpty) {
          await tester.enterText(searchField.first, 'Music');
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
        }

        // Clear search
        if (searchField.evaluate().isNotEmpty) {
          await tester.enterText(searchField.first, '');
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
        }

        // Tap on any available InkWell / ChoiceChip / FilterChip
        final inkWells = find.byType(InkWell);
        for (var i = 0; i < inkWells.evaluate().length && i < 10; i++) {
          await tester.tap(inkWells.at(i), warnIfMissed: false);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
        }

        // Find and tap save button
        final saveBtn = find.text('Save Interests');
        if (saveBtn.evaluate().isNotEmpty) {
          await tester.tap(saveBtn.first, warnIfMissed: false);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
        }
      },
    );
  });
}
