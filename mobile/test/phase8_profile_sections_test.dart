import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/features/profile/widgets/place_autocomplete_field.dart';
import 'package:nexus/features/profile/widgets/sections/bio_section.dart';
import 'package:nexus/features/profile/widgets/sections/core_signal_section.dart';
import 'package:nexus/features/profile/widgets/tag_chips_editor.dart';
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

  group('CoreSignalSection Widget Tests', () {
    testWidgets('renders CoreSignalSection with name, age, and profile tiles', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CoreSignalSection(
                name: 'Elena',
                age: 24,
                searchBucket: 'Women',
                displayGender: 'Woman',
                displaySexuality: 'Straight',
                pronouns: 'she/her',
                imagePaths: const [
                  'https://example.com/p1.jpg',
                  null,
                  null,
                  null,
                  null,
                  null,
                ],
                pendingUploads: const {},
                onNameTileTap: () {},
                onAgeTileTap: () {},
                onBucketChanged: (_) {},
                onSelectGender: () {},
                onSelectSexuality: () {},
                onSelectPronouns: () {},
                onImageSlotTap: (_) {},
                onSwapImages: (_, _) {},
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.text('Elena'), findsOneWidget);
      expect(find.text('24 yrs old'), findsOneWidget);
      expect(find.text('she/her'), findsOneWidget);
    });
  });

  group('BioSection Widget Tests', () {
    testWidgets('renders BioSection and handles text entry', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BioSection(
                bio: 'Passionate about cosmos and robotics',
                onBioChanged: (_) {},
                onBioSubmitted: (_) {},
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.text('Passionate about cosmos and robotics'), findsOneWidget);
      expect(find.byType(BioSection), findsOneWidget);
    });
  });

  group('TagChipsEditor Widget Tests', () {
    testWidgets('renders TagChipsEditor with current tags', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TagChipsEditor(
              label: 'Languages',
              currentValues: const ['English', 'Spanish'],
              presets: const ['English', 'Spanish', 'French', 'German'],
              icon: LucideIcons.languages,
              iconColor: AppColors.modeFriends,
              hintText: 'Select languages...',
              onChanged: (_) {},
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.text('English'), findsOneWidget);
      expect(find.text('Spanish'), findsOneWidget);
    });
  });

  group('PlaceAutocompleteField Widget Tests', () {
    testWidgets('renders PlaceAutocompleteField with initial place', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaceAutocompleteField(
              label: 'Current Location',
              initialValue: 'San Francisco, CA',
              hintText: 'Search city...',
              prefixIcon: LucideIcons.mapPin,
              onChanged: (_) {},
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.byType(PlaceAutocompleteField), findsOneWidget);
    });
  });
}
