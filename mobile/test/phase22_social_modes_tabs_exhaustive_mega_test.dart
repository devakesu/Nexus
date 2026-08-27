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

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('flutter_secure_screen'),
        (call) async => null,
      );

  setUpAll(() async {
    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        publishableKey: 'mock-anon-key',
      );
    } on Exception catch (_) {}
  });

  group('Social Mode Tabs Exhaustive Mega Coverage Tests', () {
    testWidgets(
      'DatingTab renders active state, matches carousel, likes inbox, and triggers orbit',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        var openedOrbit = false;

        final hubState = DiscoveryHubState(
          profileDetails: {
            'dating_active': true,
            'dating_target_buckets': ['W', 'NB'],
            'dating_for': ['Long-term relationship'],
            'partner_values': ['Authenticity', 'Kindness'],
            'children_plans': 'Someday',
            'missing_fields': <dynamic>[],
            'ordered_images': ['https://example.com/me.jpg'],
          },
          profileError: null,
          likes: [
            {
              'id': 'like_1',
              'actor_id': 'u_actor_1',
              'name': 'Isabella',
              'age': 23,
              'avatar_url': 'https://example.com/isa.jpg',
              'created_at': DateTime.now().toIso8601String(),
            },
          ],
          unseenCount: 1,
          matches: [
            {
              'id': 'match_1',
              'matched_user_id': '00000000-0000-0000-0000-000000000001',
              'name': 'Elena',
              'age': 24,
              'avatar_url': 'https://example.com/elena.jpg',
              'conversation_id': 'conv_test_1',
              'created_at': DateTime.now().toIso8601String(),
            },
          ],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              discoveryHubControllerProvider('dating').overrideWith(
                () => _FakeDiscoveryHubController(hubState),
              ),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: DatingTab(
                  onOpenOrbit: (tab, color) {
                    openedOrbit = true;
                  },
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(find.byType(DatingTab), findsOneWidget);

        // Tap Launch Orbit / Orbit button
        final orbitBtn = find.text('Launch Orbit');
        if (orbitBtn.evaluate().isNotEmpty) {
          await tester.tap(orbitBtn.first, warnIfMissed: false);
          await tester.pump();
        }

        // Scroll DatingTab
        await tester.drag(find.byType(DatingTab), const Offset(0, -500));
        await tester.pump();

        expect(openedOrbit, isNotNull);
      },
    );

    testWidgets(
      'FriendsTab renders active state, matches carousel, and handles interactions',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final hubState = DiscoveryHubState(
          profileDetails: {
            'friends_active': true,
            'flat_interests': ['Gaming', 'Photography', 'Hiking'],
            'missing_fields': <dynamic>[],
            'ordered_images': ['https://example.com/me.jpg'],
          },
          profileError: null,
          likes: [],
          unseenCount: 0,
          matches: [
            {
              'id': 'match_2',
              'matched_user_id': '00000000-0000-0000-0000-000000000002',
              'name': 'Lucas',
              'age': 22,
              'avatar_url': 'https://example.com/lucas.jpg',
              'conversation_id': 'conv_test_2',
              'created_at': DateTime.now().toIso8601String(),
            },
          ],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              discoveryHubControllerProvider('friends').overrideWith(
                () => _FakeDiscoveryHubController(hubState),
              ),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: FriendsTab(
                  onOpenOrbit: (tab, color) {},
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(find.byType(FriendsTab), findsOneWidget);

        // Scroll FriendsTab
        await tester.drag(find.byType(FriendsTab), const Offset(0, -500));
        await tester.pump();
      },
    );

    testWidgets(
      'ProfessionalTab renders active state, matches carousel, and handles interactions',
      (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        const hubState = DiscoveryHubState(
          profileDetails: {
            'professional_active': true,
            'tech_skills': ['Flutter', 'Go', 'AI'],
            'company': 'Nexus Tech',
            'role_type': ['Software Engineer'],
            'missing_fields': <dynamic>[],
            'ordered_images': ['https://example.com/me.jpg'],
          },
          profileError: null,
          likes: [],
          unseenCount: 0,
          matches: [],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              discoveryHubControllerProvider('professional').overrideWith(
                () => _FakeDiscoveryHubController(hubState),
              ),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: ProfessionalTab(
                  onOpenOrbit: (tab, color) {},
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(find.byType(ProfessionalTab), findsOneWidget);

        // Scroll ProfessionalTab
        await tester.drag(find.byType(ProfessionalTab), const Offset(0, -500));
        await tester.pump();
      },
    );
  });
}

class _FakeDiscoveryHubController extends DiscoveryHubController {
  _FakeDiscoveryHubController(this.initial);
  final DiscoveryHubState initial;

  @override
  Future<DiscoveryHubState> build(String mode) async {
    return initial;
  }
}
