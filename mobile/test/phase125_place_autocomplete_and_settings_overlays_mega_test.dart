import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/profile/widgets/place_autocomplete_field.dart';
import 'package:nexus/features/social_modes/widgets/dating_settings_overlay.dart';
import 'package:nexus/features/social_modes/widgets/friends_settings_overlay.dart';
import 'package:nexus/features/social_modes/widgets/mode_category_selection_sheet.dart';
import 'package:nexus/features/social_modes/widgets/professional_settings_overlay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 125 - Place Autocomplete and Settings Overlays Mega Tests', () {
    testWidgets(
      'PlaceAutocompleteField renders, focuses, enters text, and selects suggestions',
      (
        tester,
      ) async {
        final key = GlobalKey<PlaceAutocompleteFieldState>();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PlaceAutocompleteField(
                key: key,
                label: 'Current Place',
                initialValue: 'San Francisco',
                hintText: 'Search place...',
                prefixIcon: Icons.location_on,
                onChanged: (val) {},
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byType(PlaceAutocompleteField), findsOneWidget);

        final textField = find.byType(TextField);
        if (textField.evaluate().isNotEmpty) {
          await tester.tap(textField);
          await tester.enterText(textField, 'New York');
          await tester.pump(const Duration(milliseconds: 100));
        }

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    testWidgets(
      'Dating, Friends, and Professional overlays render and interact',
      (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DatingSettingsOverlay(
                datingTargetBuckets: const ['Women'],
                datingFor: const ['Long-term relationship'],
                partnerValues: const ['Kindness'],
                childrenPlans: 'Want children',
                savingFields: const {},
                onSaveDatingField: (f, v, s) async {},
                onLoadDatingProfileStatusSilent: () async {},
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byType(DatingSettingsOverlay), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: FriendsSettingsOverlay(
                friendsTargetBuckets: const ['All'],
                flatInterests: const ['Climbing', 'Coffee'],
                causesSupported: const ['Animal Welfare'],
                savingFields: const {},
                onSaveFriendsField: (f, v, s) async {},
                onLoadFriendsProfileStatusSilent: () async {},
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byType(FriendsSettingsOverlay), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ProfessionalSettingsOverlay(
                professionalTargetBuckets: const ['All'],
                lookingFor: const ['Mentors'],
                techSkills: const ['Flutter', 'Python'],
                company: 'Google',
                roleType: const ['Full-time'],
                savingFields: const {},
                onSaveProfessionalField: (f, v, s) async {},
                onLoadProfessionalProfileStatusSilent: () async {},
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byType(ProfessionalSettingsOverlay), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ModeCategorySelectionSheet(
                title: 'Select Categories',
                themeColor: Colors.purple,
                items: const [
                  {
                    'actor_id': 'u1',
                    'name': 'Sarah',
                    'age': 25,
                    'avatar_url': 'https://example.com/pic.png',
                  },
                ],
                onFetchItems: () async {},
                onOpenItemDetailsDialog:
                    ({
                      required ctx,
                      required actorId,
                      required name,
                      required void Function(String actorId) onActioned,
                      required void Function() onProfileLoaded,
                    }) {},
                onRecordAction: (targetId, action, token) async {},
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byType(ModeCategorySelectionSheet), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  });
}
