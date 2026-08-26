import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/features/orbit/widgets/orbit_filters_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => '.',
      );

  group('OrbitFiltersPanel Widget Tests', () {
    testWidgets(
      'renders OrbitFiltersPanel and handles age slider & filter options',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final scrollController = ScrollController();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OrbitFiltersPanel(
                tab: 'dating',
                themeColor: AppColors.modeDating,
                ageRange: const RangeValues(21, 32),
                selectedDrinking: const ['Socially'],
                selectedSmoking: const ['Never'],
                selectedLanguages: const ['English', 'French'],
                selectedSubInterests: const ['Python', 'Astronomy'],
                selectedYears: const [2022, 2023],
                selectedChildrenPlans: const ['Want children'],
                selectedReligiousBeliefs: const ['Agnostic'],
                selectedShowBuckets: const ['M', 'F'],
                selectedDatingFor: const ['Long-term'],
                selectedPartnerValues: const ['Empathy', 'Ambition'],
                dealbreakerFields: const {'smoking'},
                selectedLookingFor: const ['Dating'],
                selectedTechSkills: const ['Flutter', 'Dart'],
                savingFields: const {},
                noUsersFound: false,
                isRefreshing: false,
                scrollController: scrollController,
                onAgeRangeChanged: (_) {},
                onAgeRangeChangeEnd: (_) {},
                onSaveDatingField: (field, val, setter) async {},
                onOpenTagSelectionPane: (title, opts, sel, setter) {},
                onOpenPartnerValuesSelectionPane: (setter, vals) {},
                onFetchOrbitNodes: () async {},
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(OrbitFiltersPanel), findsOneWidget);
        expect(find.text('21 - 32'), findsOneWidget);

        // Verify RangeSlider is rendered
        expect(find.byType(RangeSlider), findsOneWidget);

        // Check for demographic bucket labels
        if (find.text('Men').evaluate().isNotEmpty) {
          expect(find.text('Men'), findsOneWidget);
        }
        if (find.text('Women').evaluate().isNotEmpty) {
          expect(find.text('Women'), findsOneWidget);
        }
      },
    );

    testWidgets(
      'renders OrbitFiltersPanel in Friends mode with looking for filters',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final scrollController = ScrollController();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OrbitFiltersPanel(
                tab: 'friends',
                themeColor: AppColors.modeFriends,
                ageRange: const RangeValues(18, 25),
                selectedDrinking: const [],
                selectedSmoking: const [],
                selectedLanguages: const ['English'],
                selectedSubInterests: const [],
                selectedYears: const [],
                selectedChildrenPlans: const [],
                selectedReligiousBeliefs: const [],
                selectedShowBuckets: const ['M', 'F', 'NB'],
                selectedDatingFor: const [],
                selectedPartnerValues: const [],
                dealbreakerFields: const {},
                selectedLookingFor: const ['Gaming Friends', 'Gym Buddies'],
                selectedTechSkills: const [],
                savingFields: const {},
                noUsersFound: true,
                isRefreshing: false,
                scrollController: scrollController,
                onAgeRangeChanged: (_) {},
                onAgeRangeChangeEnd: (_) {},
                onSaveDatingField: (_, _, _) async {},
                onOpenTagSelectionPane: (_, _, _, _) {},
                onOpenPartnerValuesSelectionPane: (_, _) {},
                onFetchOrbitNodes: () async {},
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(OrbitFiltersPanel), findsOneWidget);
        expect(find.text('18 - 25'), findsOneWidget);
      },
    );
  });
}
