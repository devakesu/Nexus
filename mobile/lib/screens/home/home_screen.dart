import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nexus/screens/chats/chats_page.dart';
import 'package:nexus/screens/home/tabs/dating_tab.dart';
import 'package:nexus/screens/home/tabs/friends_tab.dart';
import 'package:nexus/screens/home/tabs/professional_tab.dart';
import 'package:nexus/screens/home/tabs/profile_tab.dart';
import 'package:nexus/screens/home/tabs/settings_tab.dart';
import 'package:nexus/screens/home/widgets/common_header.dart';
import 'package:nexus/screens/home/widgets/custom_bottom_nav_bar.dart';
import 'package:nexus/screens/orbit_screen.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({required this.title, super.key});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _currentTab = 2; // Default to My Profile (Center Tab)

  void _triggerOpenOrbit(String sectionName, Color themeColor) {
    final prefetch = OrbitScreen.prefetch(sectionName);
    unawaited(
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (context) => OrbitScreen(
            tab: sectionName,
            themeColor: themeColor,
            prefetchFuture: prefetch,
          ),
        ),
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
                onChatTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ChatsPage(),
                  ),
                ),
              ),
              Expanded(
                child: SafeArea(
                  top: false,
                  child: IndexedStack(
                    index: _currentTab,
                    children: [
                      DatingTab(
                        onOpenOrbit: _triggerOpenOrbit,
                        onNavigateToTab: (index) {
                          setState(() {
                            _currentTab = index;
                          });
                        },
                      ),
                      FriendsTab(
                        onOpenOrbit: _triggerOpenOrbit,
                        onNavigateToTab: (index) {
                          setState(() {
                            _currentTab = index;
                          });
                        },
                      ),
                      ProfileTab(onOpenOrbit: _triggerOpenOrbit),
                      ProfessionalTab(
                        onOpenOrbit: _triggerOpenOrbit,
                        onNavigateToTab: (index) {
                          setState(() {
                            _currentTab = index;
                          });
                        },
                      ),
                      SettingsTab(onOpenOrbit: _triggerOpenOrbit),
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
            child: CustomBottomNavBar(
              currentIndex: _currentTab,
              onTabSelected: (index) {
                setState(() {
                  _currentTab = index;
                });
              },
            ),
          ),

        ],
      ),
    );
  }
}
