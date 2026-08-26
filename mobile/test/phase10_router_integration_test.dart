import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nexus/core/navigation/app_router.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/features/orbit/models/orbit_node.dart';
import 'package:nexus/features/orbit/screens/orbit_screen.dart';
import 'package:nexus/features/settings/widgets/about/attestation_section.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockAboutAttestationNotifier extends AboutAttestationNotifier {
  @override
  AboutAttestationState? build() => const AboutAttestationState(
    data: {'status': 'verified', 'commit': 'abc1234'},
  );
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

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/package_info'),
        (call) async => {
          'appName': 'Nexus',
          'packageName': 'com.nexus.app',
          'version': '1.0.0',
          'buildNumber': '1',
        },
      );

  setUpAll(() async {
    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        publishableKey: 'mock-anon-key',
      );
    } on Exception catch (_) {}
  });

  group('OrbitScreen with Prefetched Nodes Tests', () {
    testWidgets(
      'renders OrbitScreen and draws celestial constellation canvas',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final sampleNodes = <OrbitNode>[
          OrbitNode(
            id: 'user_1',
            name: 'Sarah',
            x: 0.25,
            y: -0.4,
            orbitTier: 1,
            score: 95,
            profilePic: 'https://example.com/sarah.jpg',
            gender: 'Woman',
            sexuality: 'Straight',
          ),
          OrbitNode(
            id: 'user_2',
            name: 'Maya',
            x: -0.5,
            y: 0.6,
            orbitTier: 2,
            score: 88,
            profilePic: null,
          ),
        ];

        final prefetchResult = OrbitPrefetchResult(
          nodes: sampleNodes,
          sessionId: 'session_xyz',
          profilePicUrl: null,
          showBuckets: const ['F'],
          datingFor: const ['Long-term relationship'],
          partnerValues: const ['Honesty'],
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OrbitScreen(
                tab: 'Dating',
                themeColor: AppColors.modeDating,
                prefetchFuture: Future.value(prefetchResult),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(OrbitScreen), findsOneWidget);
      },
    );
  });

  group('App Router GoRouter Configuration Tests', () {
    test('goRouter contains configured app routes', () {
      expect(goRouter.configuration.routes, isNotEmpty);
      final paths = goRouter.configuration.routes
          .whereType<GoRoute>()
          .map((r) => r.path)
          .toList();

      expect(paths, contains('/'));
      expect(paths, contains('/login'));
      expect(paths, contains('/orbit'));
      expect(paths, contains('/chats'));
      expect(paths, contains('/chat-conversation'));
      expect(paths, contains('/settings/about'));
      expect(paths, contains('/settings/privacy'));
      expect(paths, contains('/settings/safety-center'));
      expect(paths, contains('/settings/help-center'));
      expect(paths, contains('/settings/feedback'));
      expect(paths, contains('/settings/delete-account'));
      expect(paths, contains('/settings/blocked-users'));
      expect(paths, contains('/settings/hidden-users'));
      expect(paths, contains('/settings/email-notifications'));
      expect(paths, contains('/settings/community-guidelines'));
      expect(paths, contains('/legal'));
    });

    testWidgets('renders AppRouter with MaterialApp.router', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            aboutAttestationProvider.overrideWith(
              MockAboutAttestationNotifier.new,
            ),
          ],
          child: MaterialApp.router(
            routerConfig: goRouter,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(MaterialApp), findsOneWidget);
    });
  });
}
