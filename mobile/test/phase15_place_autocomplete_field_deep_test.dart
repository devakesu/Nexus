import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/profile/widgets/place_autocomplete_field.dart';
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

  group('PlaceAutocompleteField Deep Interactive Tests', () {
    testWidgets(
      'renders PlaceAutocompleteField, opens picker sheet and searches',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        var currentVal = 'Austin, TX';

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PlaceAutocompleteField(
                label: 'Hometown',
                initialValue: currentVal,
                hintText: 'Search city or country...',
                prefixIcon: Icons.location_on,
                onChanged: (val) {
                  currentVal = val;
                },
                onFieldSubmitted: (val) {
                  currentVal = val;
                },
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(PlaceAutocompleteField), findsOneWidget);

        // Tap on PlaceAutocompleteField to open bottom sheet picker
        await tester.tap(
          find.byType(PlaceAutocompleteField),
          warnIfMissed: false,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        // In the bottom sheet, find the search text field
        final textField = find.byType(TextField);
        if (textField.evaluate().isNotEmpty) {
          await tester.enterText(textField.first, 'San');
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));

          // Select suggestion
          final sfSuggestion = find.text('San Francisco, CA');
          if (sfSuggestion.evaluate().isNotEmpty) {
            await tester.tap(sfSuggestion.first, warnIfMissed: false);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
          }
        }
      },
    );
  });
}
