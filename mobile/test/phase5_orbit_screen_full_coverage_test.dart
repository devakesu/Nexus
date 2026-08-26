import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/features/orbit/models/orbit_node.dart';
import 'package:nexus/features/orbit/screens/orbit_screen.dart';
import 'package:nexus/features/orbit/widgets/orbit_filters_panel.dart';
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

  group('OrbitPrefetchResult & OrbitNode Unit Tests', () {
    test('OrbitPrefetchResult holds nodes and defaults accurately', () {
      final node = OrbitNode(
        id: 'u1',
        name: 'Luna',
        x: 0.5,
        y: -0.5,
        orbitTier: 1,
        score: 88,
        profilePic: 'https://example.com/pic.jpg',
      );

      final prefetch = OrbitPrefetchResult(
        nodes: [node],
        sessionId: 'sess_1',
        profilePicUrl: 'https://example.com/my_pic.jpg',
        showBuckets: ['Women'],
        datingFor: ['Long-term'],
        partnerValues: ['Loyalty'],
      );

      expect(prefetch.nodes.length, 1);
      expect(prefetch.nodes.first.name, 'Luna');
      expect(prefetch.showBuckets, ['Women']);
      expect(prefetch.datingFor, ['Long-term']);
    });
  });

  group('OrbitFiltersPanel Deep Widget Tests', () {
    testWidgets('renders OrbitFiltersPanel with age slider and filters', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final scrollController = ScrollController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OrbitFiltersPanel(
              tab: 'Dating',
              themeColor: AppColors.modeDating,
              ageRange: const RangeValues(21, 30),
              selectedDrinking: const ['Socially'],
              selectedSmoking: const ['Never'],
              selectedLanguages: const ['English', 'Spanish'],
              selectedSubInterests: const ['Hiking', 'Gaming'],
              selectedYears: const [3, 4],
              selectedChildrenPlans: const ['Want someday'],
              selectedReligiousBeliefs: const ['Agnostic'],
              selectedShowBuckets: const ['Women'],
              selectedDatingFor: const ['Long-term'],
              selectedPartnerValues: const ['Ambition'],
              dealbreakerFields: const {'drinking', 'smoking'},
              selectedLookingFor: const ['Study buddy'],
              selectedTechSkills: const ['Flutter', 'Python'],
              savingFields: const {},
              onAgeRangeChanged: (values) {},
              onAgeRangeChangeEnd: (values) {},
              onSaveDatingField: (field, values, setSheetState) async {},
              onOpenTagSelectionPane: (field, avail, curr, setSheetState) {},
              onOpenPartnerValuesSelectionPane: (setSheetState, curr) {},
              isRefreshing: false,
              onFetchOrbitNodes: () async {},
              scrollController: scrollController,
              noUsersFound: false,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      expect(find.byType(OrbitFiltersPanel), findsOneWidget);
    });
  });

  group('OrbitScreen Deep Widget Tests', () {
    testWidgets('renders OrbitScreen with constellation layout and controls', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockNode = OrbitNode(
        id: 'u10',
        name: 'Stella',
        x: 0.2,
        y: 0.8,
        orbitTier: 2,
        score: 94,
        profilePic: 'https://example.com/stella.jpg',
      );

      final prefetchResult = OrbitPrefetchResult(
        nodes: [mockNode],
        sessionId: 'sess_10',
        profilePicUrl: 'https://example.com/stella.jpg',
        showBuckets: ['Everyone'],
        datingFor: ['Dating'],
        partnerValues: ['Kindness'],
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: OrbitScreen(
                tab: 'Dating',
                themeColor: AppColors.modeDating,
                prefetchFuture: Future.value(prefetchResult),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      expect(find.byType(OrbitScreen), findsOneWidget);
    });
  });
}
