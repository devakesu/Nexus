import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/core/widgets/scale_pressable.dart';
import 'package:nexus/features/chats/providers/chats_providers.dart';
import 'package:nexus/features/home/widgets/common_header.dart';
import 'package:nexus/features/home/widgets/custom_bottom_nav_bar.dart';
import 'package:nexus/features/home/widgets/settings_loading_skeleton.dart';
import 'package:nexus/features/home/widgets/tab_background.dart';
import 'package:nexus/features/home/widgets/tab_scaffold.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => '.',
      );

  group('CommonHeader Tests', () {
    testWidgets(
      'renders CommonHeader with NEXUS title and chat action across all tabs',
      (tester) async {
        var chatTapped = false;

        // Test Dating tab (currentTab = 0)
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              hasUnreadMessagesProvider.overrideWith((ref) => false),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: CommonHeader(
                  appName: 'NEXUS',
                  currentTab: 0,
                  onChatTap: () => chatTapped = true,
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        expect(find.text('NEXUS'), findsOneWidget);
        expect(find.text('DATING'), findsOneWidget);

        // Tap chat button
        await tester.tap(find.byType(ScalePressable));
        await tester.pump();
        expect(chatTapped, isTrue);

        // Test Friends tab (currentTab = 1)
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              hasUnreadMessagesProvider.overrideWith((ref) => true),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: CommonHeader(
                  appName: 'NEXUS',
                  currentTab: 1,
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        expect(find.text('FRIENDS'), findsOneWidget);

        // Test Profile tab (currentTab = 2)
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              hasUnreadMessagesProvider.overrideWith((ref) => false),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: CommonHeader(
                  appName: 'NEXUS',
                  currentTab: 2,
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        expect(find.text('NEXUS'), findsOneWidget);

        // Test Professional tab (currentTab = 3)
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              hasUnreadMessagesProvider.overrideWith((ref) => false),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: CommonHeader(
                  appName: 'NEXUS',
                  currentTab: 3,
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        expect(find.text('PROFESSIONAL'), findsOneWidget);

        // Test Settings tab (currentTab = 4)
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              hasUnreadMessagesProvider.overrideWith((ref) => false),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: CommonHeader(
                  appName: 'NEXUS',
                  currentTab: 4,
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        expect(find.text('NEXUS'), findsOneWidget);
      },
    );
  });

  group('CustomBottomNavBar Tests', () {
    testWidgets('renders all navigation items and handles selection & badges', (
      tester,
    ) async {
      var selectedTab = -1;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: CustomBottomNavBar(
              currentIndex: 0,
              showDatingBadge: true,
              showFriendsBadge: true,
              showProfessionalBadge: true,
              onTabSelected: (index) => selectedTab = index,
            ),
          ),
        ),
      );

      await tester.pump();

      expect(CustomBottomNavBar.navHeight, 72.0);
      expect(CustomBottomNavBar.bottomMargin, 20.0);
      expect(CustomBottomNavBar.clearance, 110.0);

      // Verify icons
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
      expect(find.byIcon(Icons.all_inclusive_rounded), findsOneWidget);
      expect(find.byIcon(Icons.fingerprint_rounded), findsOneWidget);
      expect(find.byIcon(Icons.work_rounded), findsOneWidget);
      expect(find.byIcon(Icons.blur_circular_rounded), findsOneWidget);

      // Tap friends tab (index 1)
      await tester.tap(find.byIcon(Icons.all_inclusive_rounded));
      await tester.pump();
      expect(selectedTab, 1);

      // Tap center profile tab (index 2)
      await tester.tap(find.byIcon(Icons.fingerprint_rounded));
      await tester.pump();
      expect(selectedTab, 2);

      // Tap professional tab (index 3)
      await tester.tap(find.byIcon(Icons.work_rounded));
      await tester.pump();
      expect(selectedTab, 3);

      // Tap settings tab (index 4)
      await tester.tap(find.byIcon(Icons.blur_circular_rounded));
      await tester.pump();
      expect(selectedTab, 4);

      // Tap dating tab (index 0)
      await tester.tap(find.byIcon(Icons.favorite_rounded));
      await tester.pump();
      expect(selectedTab, 0);
    });
  });

  group('TabScaffold & TabBackground Tests', () {
    testWidgets('renders TabScaffold with Orbit controls and children', (
      tester,
    ) async {
      var openOrbitCalled = false;
      var deactivateOrbitCalled = false;

      // Inactive Orbit
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TabScaffold(
              title: 'Dating',
              themeColor: AppColors.modeDating,
              chatLabel: 'Dating Chats',
              onOpenOrbitPressed: () => openOrbitCalled = true,
              onDeactivateOrbitPressed: () => deactivateOrbitCalled = true,
              onSettingsPressed: () {},
              children: const [
                Text('Tab Content Child 1'),
                Text('Tab Content Child 2'),
              ],
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.text('Dating Orbit'), findsOneWidget);
      expect(find.text('Tab Content Child 1'), findsOneWidget);
      expect(find.text('Tab Content Child 2'), findsOneWidget);
      expect(find.text('Activate Orbit'), findsOneWidget);

      // Tap Activate Orbit
      await tester.tap(find.text('Activate Orbit'));
      await tester.pump();
      expect(openOrbitCalled, isTrue);

      // Active Orbit
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TabScaffold(
              title: 'Dating',
              themeColor: AppColors.modeDating,
              chatLabel: 'Dating Chats',
              isOrbitActive: true,
              onOpenOrbitPressed: () => openOrbitCalled = true,
              onDeactivateOrbitPressed: () => deactivateOrbitCalled = true,
              onSettingsPressed: () {},
              children: const [
                Text('Tab Content Child 1'),
              ],
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.text('Deactivate Orbit'), findsOneWidget);

      // Tap Deactivate Orbit
      await tester.tap(find.text('Deactivate Orbit'));
      await tester.pump();
      expect(deactivateOrbitCalled, isTrue);
    });

    testWidgets('renders TabBackground directly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TabBackground(
              accentColor: AppColors.modeFriends,
              child: Center(child: Text('Background Inner')),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.text('Background Inner'), findsOneWidget);
    });
  });

  group('SettingsLoadingSkeleton Tests', () {
    testWidgets('renders SettingsLoadingSkeleton with shimmer cards', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SettingsLoadingSkeleton(
              themeColor: AppColors.modeSettings,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(SettingsLoadingSkeleton), findsOneWidget);
    });
  });
}
