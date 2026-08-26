import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/features/profile/widgets/place_autocomplete_field.dart';
import 'package:nexus/features/profile/widgets/stability_tracker.dart';
import 'package:nexus/features/profile/widgets/tag_chips_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlaceAutocompleteField Widget Tests', () {
    testWidgets('renders PlaceAutocompleteField with label and icon', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaceAutocompleteField(
              label: 'Hometown',
              initialValue: 'San Francisco, CA',
              hintText: 'Enter hometown',
              prefixIcon: LucideIcons.home,
              onChanged: (place) {},
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.byType(PlaceAutocompleteField), findsOneWidget);
    });
  });

  group('TagChipsEditor Widget Tests', () {
    testWidgets('renders TagChipsEditor with initial tags', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TagChipsEditor(
              label: 'Hobbies',
              currentValues: const ['Reading', 'Hiking'],
              presets: const ['Reading', 'Hiking', 'Cooking', 'Gaming'],
              icon: LucideIcons.tag,
              iconColor: Colors.blue,
              hintText: 'Select hobbies',
              onChanged: (tags) {},
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.byType(TagChipsEditor), findsOneWidget);
    });
  });

  group('StabilityTracker Widget Tests', () {
    testWidgets(
      'renders StabilityTracker with percentage indicator and criteria list',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                height: 700,
                child: Builder(
                  builder: (context) {
                    final vsync = TestVSync();
                    final controller = AnimationController(
                      vsync: vsync,
                      duration: const Duration(seconds: 1),
                    );
                    addTearDown(controller.dispose);

                    return StabilityTracker(
                      stabilityPercentage: 85,
                      imagePaths: const ['https://example.com/pic1.jpg'],
                      name: 'TestUser',
                      age: 25,
                      bio: 'Testing profile stability',
                      searchBucket: 'Women',
                      displayGender: 'Woman',
                      displaySexuality: 'Straight',
                      pronouns: 'She/Her',
                      hometown: 'San Francisco',
                      currentPlace: 'New York',
                      languages: const ['English'],
                      campusName: 'Stanford',
                      major: 'CS',
                      isStudying: true,
                      year: 3,
                      lifestyle: 'Active',
                      drinking: 'Socially',
                      smoking: 'Never',
                      religiousBeliefs: 'Spiritual',
                      pets: const ['Dog'],
                      subInterests: const {
                        'Arts': ['Photography', 'Painting'],
                      },
                      causesSupported: const ['Environment'],
                      topArtists: const ['Radiohead', 'Daft Punk'],
                      pulseController: controller,
                      onCriteriaTap: (_) {},
                    );
                  },
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        expect(find.byType(StabilityTracker), findsOneWidget);
      },
    );
  });
}

class TestVSync extends TickerProvider {
  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
}
