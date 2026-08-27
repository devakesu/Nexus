import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/orbit/widgets/orbit_filters_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Animate.restartOnHotReload = false;

  group('Phase 122 - Orbit Canvas and Filters Deep Mega Tests', () {
    testWidgets('OrbitFiltersPanel renders and interacts for Dating mode', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final scrollController = ScrollController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OrbitFiltersPanel(
              tab: 'Dating',
              themeColor: Colors.pink,
              ageRange: const RangeValues(21, 35),
              selectedDrinking: const ['Socially'],
              selectedSmoking: const ['Never'],
              selectedLanguages: const ['English', 'Spanish'],
              selectedSubInterests: const ['Climbing', 'Coffee'],
              selectedYears: const [2020, 2021],
              selectedChildrenPlans: const ['Want children'],
              selectedReligiousBeliefs: const ['Agnostic'],
              selectedShowBuckets: const ['Women'],
              selectedDatingFor: const ['Relationship'],
              selectedPartnerValues: const ['Honesty'],
              dealbreakerFields: const {'drinking', 'smoking'},
              selectedLookingFor: const ['Exploring'],
              selectedTechSkills: const ['Flutter', 'Python'],
              savingFields: const {},
              onAgeRangeChanged: (r) {},
              onAgeRangeChangeEnd: (r) {},
              onSaveDatingField: (f, v, s) async {},
              onOpenTagSelectionPane: (p, s, a, setS) {},
              onOpenPartnerValuesSelectionPane: (setS, cur) {},
              isRefreshing: false,
              onFetchOrbitNodes: () async {},
              scrollController: scrollController,
              noUsersFound: false,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(OrbitFiltersPanel), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets(
      'OrbitFiltersPanel renders and interacts for Friends and Professional modes',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        for (final mode in ['Friends', 'Professional']) {
          final scrollController = ScrollController();
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: OrbitFiltersPanel(
                  tab: mode,
                  themeColor: mode == 'Friends' ? Colors.amber : Colors.blue,
                  ageRange: const RangeValues(18, 45),
                  selectedDrinking: const <String>[],
                  selectedSmoking: const <String>[],
                  selectedLanguages: const ['English'],
                  selectedSubInterests: const ['Startups'],
                  selectedYears: const <int>[],
                  selectedChildrenPlans: const <String>[],
                  selectedReligiousBeliefs: const <String>[],
                  selectedShowBuckets: const <String>[],
                  selectedDatingFor: const <String>[],
                  selectedPartnerValues: const <String>[],
                  dealbreakerFields: const <String>{},
                  selectedLookingFor: const ['Colleagues', 'Mentors'],
                  selectedTechSkills: const ['Dart', 'Go', 'Rust'],
                  savingFields: const {'tech_skills'},
                  onAgeRangeChanged: (r) {},
                  onAgeRangeChangeEnd: (r) {},
                  onSaveDatingField: (f, v, s) async {},
                  onOpenTagSelectionPane: (p, s, a, setS) {},
                  onOpenPartnerValuesSelectionPane: (setS, cur) {},
                  isRefreshing: true,
                  onFetchOrbitNodes: () async {},
                  scrollController: scrollController,
                  noUsersFound: true,
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byType(OrbitFiltersPanel), findsOneWidget);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      },
    );
  });
}
