import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/home/providers/discovery_hub_provider.dart';
import 'package:nexus/features/social_modes/screens/dating_tab.dart';
import 'package:nexus/features/social_modes/screens/friends_tab.dart';
import 'package:nexus/features/social_modes/screens/professional_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockDiscoveryHubController extends DiscoveryHubController {
  MockDiscoveryHubController(this.mockState);
  final DiscoveryHubState mockState;

  @override
  Future<DiscoveryHubState> build(String mode) async => mockState;
}

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

  group('DatingTab Tests', () {
    testWidgets('renders DatingTab with discovery hub state and active orbit', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const sampleHubState = DiscoveryHubState(
        profileDetails: {
          'is_orbit_active': true,
          'target_demographics': ['M', 'F'],
          'dating_for': ['Long-term'],
          'partner_values': ['Loyalty', 'Empathy'],
          'children_plans': 'Want children',
        },
        profileError: null,
        likes: [
          {'id': 'like_1', 'name': 'Sophia', 'profile_pic': null},
        ],
        matches: [
          {'id': 'match_1', 'name': 'Liam', 'profile_pic': null},
        ],
        unseenCount: 1,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            discoveryHubControllerProvider('dating').overrideWith(
              () => MockDiscoveryHubController(sampleHubState),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: DatingTab(
                onOpenOrbit: (mode, color) {},
                onNavigateToTab: (tab, [sub]) {},
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(DatingTab), findsOneWidget);
    });
  });

  group('FriendsTab Tests', () {
    testWidgets('renders FriendsTab with waves and friends orbit', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const sampleHubState = DiscoveryHubState(
        profileDetails: {
          'is_orbit_active': true,
          'target_demographics': ['M', 'F', 'NB'],
          'flat_interests': ['Gaming', 'Astronomy'],
          'causes_supported': ['Climate Action'],
        },
        profileError: null,
        likes: [
          {'id': 'wave_1', 'name': 'Oliver', 'profile_pic': null},
        ],
        matches: [],
        unseenCount: 0,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            discoveryHubControllerProvider('friends').overrideWith(
              () => MockDiscoveryHubController(sampleHubState),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: FriendsTab(
                onOpenOrbit: (mode, color) {},
                onNavigateToTab: (tab, [sub]) {},
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(FriendsTab), findsOneWidget);
    });
  });

  group('ProfessionalTab Tests', () {
    testWidgets(
      'renders ProfessionalTab with network requests and professional orbit',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        const sampleHubState = DiscoveryHubState(
          profileDetails: {
            'is_orbit_active': true,
            'target_demographics': ['M', 'F'],
            'looking_for': ['Co-founder matching'],
            'tech_skills': ['Flutter & Dart'],
            'company': 'Tech Corp',
            'role_type': ['Engineer'],
          },
          profileError: null,
          likes: [],
          matches: [],
          unseenCount: 0,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              discoveryHubControllerProvider('professional').overrideWith(
                () => MockDiscoveryHubController(sampleHubState),
              ),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: ProfessionalTab(
                  onOpenOrbit: (mode, color) {},
                  onNavigateToTab: (tab, [sub]) {},
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(ProfessionalTab), findsOneWidget);
      },
    );
  });
}
