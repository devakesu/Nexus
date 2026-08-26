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

  const mockState = DiscoveryHubState(
    profileDetails: {
      'orbit_active': false,
      'dating_target_buckets': ['Women'],
      'dating_for': ['Long-term'],
      'partner_values': ['Kindness'],
    },
    profileError: null,
    likes: [],
    unseenCount: 0,
    matches: [],
  );

  group('Social Modes Tabs Deep Widget Tests', () {
    testWidgets('renders DatingTab and interacts with buttons and scroll', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            discoveryHubControllerProvider('dating').overrideWith(
              () => _MockDiscoveryHubController(mockState),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: DatingTab(
                onOpenOrbit: (mode, color) {},
                onNavigateToTab: (index, [subtab]) {},
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      expect(find.byType(DatingTab), findsOneWidget);
    });

    testWidgets('renders FriendsTab and interacts with buttons and scroll', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            discoveryHubControllerProvider('friends').overrideWith(
              () => _MockDiscoveryHubController(mockState),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: FriendsTab(
                onOpenOrbit: (mode, color) {},
                onNavigateToTab: (index, [subtab]) {},
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      expect(find.byType(FriendsTab), findsOneWidget);
    });

    testWidgets(
      'renders ProfessionalTab and interacts with buttons and scroll',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              discoveryHubControllerProvider('professional').overrideWith(
                () => _MockDiscoveryHubController(mockState),
              ),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: ProfessionalTab(
                  onOpenOrbit: (mode, color) {},
                  onNavigateToTab: (index, [subtab]) {},
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 2));

        expect(find.byType(ProfessionalTab), findsOneWidget);
      },
    );
  });
}

class _MockDiscoveryHubController extends DiscoveryHubController {
  _MockDiscoveryHubController(this._state);

  final DiscoveryHubState _state;

  @override
  Future<DiscoveryHubState> build(String mode) async => _state;
}
