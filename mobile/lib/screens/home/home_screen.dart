import 'dart:async';
// Trigger analyzer refresh
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexus/providers/discovery_hub_provider.dart';
import 'package:nexus/screens/home/tabs/dating_tab.dart';
import 'package:nexus/screens/home/tabs/friends_tab.dart';
import 'package:nexus/screens/home/tabs/professional_tab.dart';
import 'package:nexus/screens/home/tabs/profile_tab.dart';
import 'package:nexus/screens/home/tabs/settings_tab.dart';
import 'package:nexus/screens/home/widgets/common_header.dart';
import 'package:nexus/screens/home/widgets/custom_bottom_nav_bar.dart';
import 'package:nexus/screens/orbit_screen.dart';

class MyHomePage extends ConsumerStatefulWidget {
  const MyHomePage({required this.title, super.key});

  final String title;

  @override
  ConsumerState<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends ConsumerState<MyHomePage> {
  int _currentTab = 2; // Default to My Profile (Center Tab)

  // Profile (index 2) is the default landing tab, so it's pre-visited and
  // builds eagerly. The other 4 tabs only build (and fire their initState
  // network calls) the first time the user actually navigates to them -
  // once visited, they stay in this set forever so their state/animations
  // survive future tab switches exactly like an always-built IndexedStack.
  final Set<int> _visitedTabs = {2};

  void _selectTab(int index) {
    setState(() {
      _currentTab = index;
      _visitedTabs.add(index);
    });
  }

  void _triggerOpenOrbit(String sectionName, Color themeColor) {
    final prefetch = OrbitScreen.prefetch(sectionName);
    unawaited(
      context.push<void>(
        '/orbit',
        extra: {
          'tab': sectionName,
          'themeColor': themeColor,
          'prefetchFuture': prefetch,
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          // Main tab content
          Column(
            children: [
              CommonHeader(
                appName: widget.title,
                currentTab: _currentTab,
                onChatTap: () => context.push<void>('/chats'),
              ),
              Expanded(
                child: SafeArea(
                  top: false,
                  child: IndexedStack(
                    index: _currentTab,
                    children:
                        [
                          if (_visitedTabs.contains(0))
                            DatingTab(
                              onOpenOrbit: _triggerOpenOrbit,
                              onNavigateToTab: _selectTab,
                            )
                          else
                            const SizedBox.shrink(),
                          if (_visitedTabs.contains(1))
                            FriendsTab(
                              onOpenOrbit: _triggerOpenOrbit,
                              onNavigateToTab: _selectTab,
                            )
                          else
                            const SizedBox.shrink(),
                          ProfileTab(onOpenOrbit: _triggerOpenOrbit),
                          if (_visitedTabs.contains(3))
                            ProfessionalTab(
                              onOpenOrbit: _triggerOpenOrbit,
                              onNavigateToTab: _selectTab,
                            )
                          else
                            const SizedBox.shrink(),
                          if (_visitedTabs.contains(4))
                            SettingsTab(onOpenOrbit: _triggerOpenOrbit)
                          else
                            const SizedBox.shrink(),
                        ].asMap().entries.map((entry) {
                          final index = entry.key;
                          final widgetItem = entry.value;
                          return TickerMode(
                            enabled: _currentTab == index,
                            child: widgetItem,
                          );
                        }).toList(),
                  ),
                ),
              ),
            ],
          ),

          // Custom Floating Bottom Navigation Bar
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Consumer(
              builder: (context, ref, child) {
                final datingState = ref.watch(discoveryHubControllerProvider('dating'));
                final friendsState = ref.watch(discoveryHubControllerProvider('friends'));
                final professionalState = ref.watch(discoveryHubControllerProvider('professional'));

                final datingUnseen = (datingState.value?.unseenCount ?? 0) > 0;
                final friendsUnseen = (friendsState.value?.unseenCount ?? 0) > 0;
                final professionalUnseen = (professionalState.value?.unseenCount ?? 0) > 0;

                return CustomBottomNavBar(
                  currentIndex: _currentTab,
                  onTabSelected: _selectTab,
                  showDatingBadge: datingUnseen,
                  showFriendsBadge: friendsUnseen,
                  showProfessionalBadge: professionalUnseen,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
