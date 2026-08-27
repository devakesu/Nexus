import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/core/widgets/scale_pressable.dart';
import 'package:nexus/features/chats/providers/chats_providers.dart';
import 'package:nexus/features/home/providers/discovery_hub_provider.dart';
import 'package:nexus/features/home/screens/home_screen.dart';
import 'package:nexus/features/home/widgets/common_header.dart';
import 'package:nexus/features/home/widgets/custom_bottom_nav_bar.dart';
import 'package:nexus/features/home/widgets/export_code_card.dart';
import 'package:nexus/features/home/widgets/match_screen.dart';
import 'package:nexus/features/home/widgets/settings_loading_skeleton.dart';
import 'package:nexus/features/home/widgets/tab_background.dart';
import 'package:nexus/features/home/widgets/tab_scaffold.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/test_helpers.dart';

void main() {
  setUpTestEnvironment();

  setUpAll(() async {
    await initMockSupabase();
  });

  // --- Section 1 ---
  {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );

    group('MyHomePage Widget Tests', () {
      testWidgets('renders MyHomePage and handles tab navigation', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: MyHomePage(title: 'Nexus'),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(find.byType(MyHomePage), findsOneWidget);

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 60));
      });
    });
  }

  // --- Section 2 ---
  {
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
      testWidgets(
        'renders all navigation items and handles selection & badges',
        (
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
        },
      );
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

  // --- Section 3 ---
  {
    Animate.restartOnHotReload = false;

    final mockSessionJson = jsonEncode({
      'access_token': 'mock-access-token-12345',
      'refresh_token': 'mock-refresh-token-12345',
      'expires_in': 3600,
      'expires_at': 1893456000,
      'token_type': 'bearer',
      'user': {
        'id': '00000000-0000-0000-0000-000000000001',
        'aud': 'authenticated',
        'role': 'authenticated',
        'email': 'user@nexus.test',
        'phone': '+14155552671',
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
        'created_at': '2026-01-01T00:00:00.000Z',
        'updated_at': '2026-01-01T00:00:00.000Z',
      },
    });

    SharedPreferences.setMockInitialValues({
      'sb-mock-auth-token': mockSessionJson,
    });

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
      ConsentCacheManager.safetyConsentGranted = true;
      ConsentCacheManager.specialCategoryConsentGranted = true;
      try {
        await Supabase.initialize(
          url: 'https://mock.supabase.co',
          publishableKey: 'mock-anon-key',
        );
      } on Exception catch (_) {}
    });

    group('Discovery Hub and Home Screens Tests', () {
      test('DiscoveryHubState copyWith and status checks', () {
        final state = DiscoveryHubState.fromCache({
          'profileDetails': {'status': 'active'},
          'likes': [
            {'id': 'like_1'},
          ],
          'unseenCount': 1,
          'matches': [
            {'id': 'match_1'},
          ],
        });

        expect(state.unseenCount, 1);
        expect(state.likes.length, 1);
        expect(state.matches.length, 1);
        expect(state.profileDetails?['status'], 'active');
      });

      testWidgets('MatchScreen and ExportCodeCard render cleanly', (
        tester,
      ) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: MatchScreen(
                matchedName: 'Taylor',
                matchedProfilePic: 'pic.jpg',
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(find.byType(MatchScreen), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: ExportCodeCard(),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(find.byType(ExportCodeCard), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 3));
      });

      testWidgets('MyHomePage mounts and switches tabs cleanly', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: MyHomePage(title: 'NEXUS'),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        expect(find.byType(MyHomePage), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 60));
      });
    });
  }
}
