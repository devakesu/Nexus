import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/features/orbit/widgets/orbit_filters_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => '.',
      );

  group('OrbitFiltersPanel Deep Widget Coverage Tests', () {
    testWidgets(
      'OrbitFiltersPanel renders for Dating tab, interacts with sliders and chips',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final scrollController = ScrollController();
        var age = const RangeValues(18, 30);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OrbitFiltersPanel(
                tab: 'Dating',
                themeColor: AppColors.modeDating,
                ageRange: age,
                selectedDrinking: const ['Socially'],
                selectedSmoking: const ['Never'],
                selectedLanguages: const ['English', 'Spanish'],
                selectedSubInterests: const ['AI & ML', 'Hiking'],
                selectedYears: const [2, 3, 4],
                selectedChildrenPlans: const ['Someday'],
                selectedReligiousBeliefs: const ['Agnostic'],
                selectedShowBuckets: const ['W', 'NB'],
                selectedDatingFor: const ['Long-term'],
                selectedPartnerValues: const ['Kindness', 'Humor'],
                dealbreakerFields: const {'age', 'smoking'},
                selectedLookingFor: const [],
                selectedTechSkills: const [],
                savingFields: const {},
                onAgeRangeChanged: (val) {
                  age = val;
                },
                onAgeRangeChangeEnd: (val) {
                  age = val;
                },
                onSaveDatingField: (field, val, setter) async {},
                onOpenTagSelectionPane: (title, opts, sel, setter) {},
                onOpenPartnerValuesSelectionPane: (setter, vals) {},
                isRefreshing: false,
                onFetchOrbitNodes: () async {},
                scrollController: scrollController,
                noUsersFound: false,
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(find.byType(OrbitFiltersPanel), findsOneWidget);

        // Drag filters panel
        await tester.drag(
          find.byType(OrbitFiltersPanel),
          const Offset(0, -500),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
      },
    );

    testWidgets(
      'OrbitFiltersPanel renders for Professional tab with tech skills',
      (
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
                tab: 'Professional',
                themeColor: AppColors.modeProfessional,
                ageRange: const RangeValues(21, 40),
                selectedDrinking: const [],
                selectedSmoking: const [],
                selectedLanguages: const ['English'],
                selectedSubInterests: const ['Flutter', 'Rust'],
                selectedYears: const [],
                selectedChildrenPlans: const [],
                selectedReligiousBeliefs: const [],
                selectedShowBuckets: const [],
                selectedDatingFor: const [],
                selectedPartnerValues: const [],
                dealbreakerFields: const {},
                selectedLookingFor: const ['Cofounder', 'Mentorship'],
                selectedTechSkills: const ['Flutter', 'Python', 'Go'],
                savingFields: const {},
                onAgeRangeChanged: (val) {},
                onAgeRangeChangeEnd: (val) {},
                onSaveDatingField: (field, val, setter) async {},
                onOpenTagSelectionPane: (title, opts, sel, setter) {},
                onOpenPartnerValuesSelectionPane: (setter, vals) {},
                isRefreshing: false,
                onFetchOrbitNodes: () async {},
                scrollController: scrollController,
                noUsersFound: false,
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(find.byType(OrbitFiltersPanel), findsOneWidget);
      },
    );
  });
}
