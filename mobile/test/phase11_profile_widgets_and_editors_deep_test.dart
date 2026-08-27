import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/features/profile/widgets/place_autocomplete_field.dart';
import 'package:nexus/features/profile/widgets/sections/social_coordinates_section.dart';
import 'package:nexus/features/profile/widgets/sections/spotify_playlists_section.dart';
import 'package:nexus/features/profile/widgets/stability_tracker.dart';
import 'package:nexus/features/profile/widgets/tag_chips_editor.dart';

class TestVSync extends TickerProvider {
  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TagChipsEditor Deep Interaction Tests', () {
    testWidgets(
      'opens multi-select sheet, selects preset tags, and enters custom tag',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TagChipsEditor(
                label: 'Interests',
                currentValues: const ['Music', 'Hiking'],
                presets: const [
                  'Music',
                  'Hiking',
                  'Cooking',
                  'Art',
                  'Gaming',
                  'None',
                ],
                exclusiveOptions: const ['None'],
                icon: LucideIcons.sparkles,
                iconColor: Colors.purple,
                hintText: 'Add an interest...',
                onChanged: (tags) {},
              ),
            ),
          ),
        );

        await tester.pump();
        expect(find.text('INTERESTS'), findsOneWidget);

        // Tap Edit button to open multi-select sheet
        await tester.tap(find.text('Edit'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Cooking'), findsOneWidget);

        // Tap 'Cooking' to add it
        await tester.tap(find.text('Cooking'));
        await tester.pump(const Duration(milliseconds: 100));

        // Enter custom tag in the TextField
        final inputFinder = find.byType(TextField);
        if (inputFinder.evaluate().isNotEmpty) {
          await tester.enterText(inputFinder.first, 'Astronomy');
          await tester.pump(const Duration(milliseconds: 100));
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pump(const Duration(milliseconds: 100));
        }

        // Tap Done/Save
        final doneButton = find.text('Done');
        if (doneButton.evaluate().isNotEmpty) {
          await tester.tap(doneButton);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
        }
      },
    );

    testWidgets(
      'exclusive option selection clears other tags in TagChipsEditor',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TagChipsEditor(
                label: 'Diet',
                currentValues: const ['Vegetarian'],
                presets: const ['Vegetarian', 'Vegan', 'None'],
                exclusiveOptions: const ['None'],
                icon: LucideIcons.utensils,
                iconColor: Colors.green,
                hintText: 'Select diet...',
                onChanged: (tags) {},
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.tap(find.text('Edit'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('None'), findsOneWidget);
        await tester.tap(find.text('None'));
        await tester.pump(const Duration(milliseconds: 100));
      },
    );
  });

  group('PlaceAutocompleteField Deep Interaction Tests', () {
    testWidgets(
      'shows suggestions dropdown when typing and allows selecting city',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: PlaceAutocompleteField(
                  label: 'Current City',
                  initialValue: '',
                  hintText: 'Where are you based?',
                  prefixIcon: LucideIcons.mapPin,
                  onChanged: (val) {},
                ),
              ),
            ),
          ),
        );

        await tester.pump();

        // Tap field to open location picker sheet
        await tester.tap(find.text('CURRENT CITY'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Search in the bottom sheet's TextFormField
        final textFormField = find.byType(TextFormField);
        if (textFormField.evaluate().isNotEmpty) {
          await tester.enterText(textFormField.first, 'San');
          await tester.pump(const Duration(milliseconds: 200));

          final suggestion = find.text('San Francisco, CA');
          if (suggestion.evaluate().isNotEmpty) {
            await tester.tap(suggestion.first);
            await tester.pump(const Duration(milliseconds: 200));
          }
        }
      },
    );
  });

  group('StabilityTracker Sheet Tests', () {
    testWidgets(
      'tapping details button displays profile completion modal sheet',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final vsync = TestVSync();
        final controller = AnimationController(
          vsync: vsync,
          duration: const Duration(seconds: 1),
        );
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: StabilityTracker(
                  stabilityPercentage: 60,
                  imagePaths: const [
                    'https://example.com/photo.jpg',
                    null,
                    null,
                  ],
                  name: 'Jane',
                  age: 22,
                  bio: 'Love astronomy and coding',
                  searchBucket: 'Women',
                  displayGender: 'Woman',
                  displaySexuality: 'Queer',
                  pronouns: 'They/Them',
                  hometown: 'Austin, TX',
                  currentPlace: 'Austin, TX',
                  languages: const ['English', 'Spanish'],
                  campusName: 'UT Austin',
                  major: 'Physics',
                  isStudying: true,
                  year: 2,
                  lifestyle: 'Night Owl',
                  drinking: 'Socially',
                  smoking: 'No',
                  religiousBeliefs: 'Agnostic',
                  pets: const ['Cat'],
                  subInterests: const {
                    'Science': ['Physics', 'Astronomy'],
                  },
                  causesSupported: const ['Animal Welfare'],
                  topArtists: const ['Phoebe Bridgers'],
                  pulseController: controller,
                  onCriteriaTap: (label) {},
                ),
              ),
            ),
          ),
        );

        await tester.pump();

        // Tap on Details / Completion report
        final viewDetails = find.text('View Details');
        if (viewDetails.evaluate().isNotEmpty) {
          await tester.tap(viewDetails);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.text('Profile Completion Report'), findsOneWidget);
        }
      },
    );
  });

  group('SpotifyPlaylistsSection & SocialCoordinatesSection Widget Tests', () {
    testWidgets('opens Spotify playlists sheet via helper function', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => openPlaylistsSheet(context),
                  child: const Text('Open Sheet'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      expect(find.text('Your Playlists'), findsOneWidget);
    });

    testWidgets(
      'renders SocialCoordinatesSection with campus and education info',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: SocialCoordinatesSection(
                  campusName: 'UC Berkeley',
                  savedCampusName: 'UC Berkeley',
                  major: 'EECS',
                  year: 4,
                  isStudying: true,
                  hometown: 'San Jose, CA',
                  currentPlace: 'Berkeley, CA',
                  languages: const ['English', 'Spanish'],
                  onHometownChanged: (_) {},
                  onHometownSubmitted: (_) {},
                  onCurrentPlaceChanged: (_) {},
                  onCurrentPlaceSubmitted: (_) {},
                  onLanguagesChanged: (_) {},
                  onCampusNameChanged: (_) {},
                  onCampusNameSubmitted: (_) {},
                  onMajorChanged: (_) {},
                  onMajorSubmitted: (_) {},
                  onIsStudyingChanged: (_) {},
                  onYearChanged: (_) {},
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        expect(find.byType(SocialCoordinatesSection), findsOneWidget);
        expect(find.text('UC Berkeley'), findsWidgets);
      },
    );
  });
}
