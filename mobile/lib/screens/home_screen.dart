import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/utils/error_handler.dart';
import 'package:nexus/utils/network_utils.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({required this.title, super.key});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _currentTab = 2; // Default to My Profile (Center Tab)
  bool _isOrbitOpening = false;
  String _activeOrbitName = '';
  Color _activeOrbitColor = Colors.purple;

  void _triggerOpenOrbit(String sectionName, Color themeColor) {
    setState(() {
      _activeOrbitName = sectionName;
      _activeOrbitColor = themeColor;
      _isOrbitOpening = true;
    });

    // Simulate opening the orbit with a beautiful animation duration
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _isOrbitOpening = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: themeColor,
            content: Row(
              children: [
                const Icon(LucideIcons.globe, color: Colors.white),
                const SizedBox(width: 12),
                Text(
                  '$sectionName Orbit is now open and transmitting!',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090D0F),
      body: Stack(
        children: [
          // Main tab content
          SafeArea(
            bottom: false,
            child: IndexedStack(
              index: _currentTab,
              children: [
                _DatingTab(onOpenOrbit: _triggerOpenOrbit),
                _FriendsTab(onOpenOrbit: _triggerOpenOrbit),
                _ProfileTab(onOpenOrbit: _triggerOpenOrbit),
                _ProfessionalTab(onOpenOrbit: _triggerOpenOrbit),
                _SettingsTab(onOpenOrbit: _triggerOpenOrbit),
              ],
            ),
          ),

          // Custom Floating Bottom Navigation Bar
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: _CustomBottomNavBar(
              currentIndex: _currentTab,
              onTabSelected: (index) {
                setState(() {
                  _currentTab = index;
                });
              },
            ),
          ),

          // Open Orbit Animation Overlay
          if (_isOrbitOpening)
            _OrbitAnimationOverlay(
              orbitName: _activeOrbitName,
              orbitColor: _activeOrbitColor,
            ),
        ],
      ),
    );
  }
}

// ── Custom Bottom Navigation Bar ─────────────────────────────────────────────

class _CustomBottomNavBar extends StatelessWidget {
  const _CustomBottomNavBar({
    required this.currentIndex,
    required this.onTabSelected,
  });

  final int currentIndex;
  final ValueChanged<int> onTabSelected;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomCenter,
      children: [
        // Bottom nav bar container
        Container(
          height: 76,
          decoration: BoxDecoration(
            color: const Color(0xE6111619), // Translucent dark
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withAlpha(20), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(102),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Left Tabs
              Expanded(child: _buildNavItem(0, LucideIcons.heart, 'Dating', const Color(0xFFFF4F81))),
              Expanded(child: _buildNavItem(1, LucideIcons.users, 'Friends', const Color(0xFFFF9F1C))),

              // Space for the center item (My Profile)
              const Expanded(child: SizedBox.shrink()),

              // Right Tabs
              Expanded(child: _buildNavItem(3, LucideIcons.briefcase, 'Pro', const Color(0xFF00F5D4))),
              Expanded(child: _buildNavItem(4, LucideIcons.settings, 'Settings', const Color(0xFF4EA8DE))),
            ],
          ),
        ),

        // Floating Center Item (My Profile)
        Positioned(
          bottom: 12,
          child: _buildCenterNavItem(),
        ),
      ],
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label, Color activeColor) {
    final isSelected = currentIndex == index;
    return GestureDetector(
      onTap: () => onTabSelected(index),
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? activeColor.withAlpha(38) : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              icon,
              color: isSelected ? activeColor : const Color(0x80FFFFFF),
              size: 22,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
              color: isSelected ? activeColor : const Color(0x66FFFFFF),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCenterNavItem() {
    final isSelected = currentIndex == 2;
    const activeColor = Color(0xFF8B5CF6); // Violet/Purple

    return GestureDetector(
      onTap: () => onTabSelected(2),
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [activeColor, Color(0xFFEC4899)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? Colors.white : Colors.white.withAlpha(102),
                width: 2.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: activeColor.withAlpha(isSelected ? 153 : 76),
                  blurRadius: 16,
                  spreadRadius: 2,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              LucideIcons.user,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'My Profile',
            style: TextStyle(
              fontSize: 10,
              fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
              color: isSelected ? const Color(0xFFD8B4FE) : const Color(0x80FFFFFF),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Open Orbit Animation Overlay ─────────────────────────────────────────────

class _OrbitAnimationOverlay extends StatelessWidget {
  const _OrbitAnimationOverlay({
    required this.orbitName,
    required this.orbitColor,
  });

  final String orbitName;
  final Color orbitColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withAlpha(230),
      width: double.infinity,
      height: double.infinity,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                // Outer rotating ring
                Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    border: Border.all(color: orbitColor.withAlpha(51), width: 3),
                    shape: BoxShape.circle,
                  ),
                ).animate(onPlay: (controller) => controller.repeat()).rotate(duration: 8.seconds),

                // Mid rotating ring
                Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    border: Border.all(color: orbitColor.withAlpha(102), width: 2),
                    shape: BoxShape.circle,
                  ),
                ).animate(onPlay: (controller) => controller.repeat()).rotate(duration: 5.seconds, begin: 1, end: 0),

                // Pulsing central node
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: orbitColor.withAlpha(26),
                    shape: BoxShape.circle,
                    border: Border.all(color: orbitColor, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: orbitColor.withAlpha(127),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Icon(
                    LucideIcons.globe,
                    color: orbitColor,
                    size: 36,
                  ),
                ).animate(onPlay: (controller) => controller.repeat(reverse: true)).scale(
                      begin: const Offset(0.85, 0.85),
                      end: const Offset(1.15, 1.15),
                      duration: 1.2.seconds,
                      curve: Curves.easeInOut,
                    ),

                // Orbiting satellites
                Positioned(
                  top: 30,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: orbitColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ).animate(onPlay: (controller) => controller.repeat()).rotate(duration: 3.seconds),
              ],
            ),
            const SizedBox(height: 48),
            Text(
              'Opening $orbitName Orbit...',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 1.2,
              ),
            ).animate().fadeIn(duration: 500.ms).slideY(begin: 0.2, end: 0),
            const SizedBox(height: 12),
            Text(
              'Aligning signals and mapping paths',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withAlpha(127),
              ),
            ).animate().fadeIn(delay: 400.ms),
          ],
        ),
      ),
    );
  }
}

// ── Tab Base Widgets Helper ──────────────────────────────────────────────────

class _TabScaffold extends StatelessWidget {
  const _TabScaffold({
    required this.title,
    required this.themeColor,
    required this.chatLabel,
    required this.onOpenOrbitPressed,
    required this.children,
  });

  final String title;
  final Color themeColor;
  final String chatLabel;
  final VoidCallback onOpenOrbitPressed;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Custom Header
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
              // Dedicated Chat Icon
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF111619),
                  shape: BoxShape.circle,
                  border: Border.all(color: themeColor.withAlpha(76), width: 1.5),
                ),
                child: IconButton(
                  icon: Icon(LucideIcons.messageSquare, color: themeColor),
                  tooltip: 'Open Chats',
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: const Color(0xFF111619),
                        content: Row(
                          children: [
                            Icon(LucideIcons.messageSquare, color: themeColor),
                            const SizedBox(width: 12),
                            Text(
                              'Opening $chatLabel messages channel...',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),

        // Scrollable content area
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 110),
            children: [
              // Open Orbit action card
              Container(
                margin: const EdgeInsets.only(bottom: 24),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [themeColor.withAlpha(38), themeColor.withAlpha(5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: themeColor.withAlpha(64), width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: themeColor.withAlpha(51),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(LucideIcons.globe, color: themeColor, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$title Orbit',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              'Status: Disconnected',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withAlpha(127),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Activate your local gravitational pool to scan for matches and synchronize with nearby nodes.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withAlpha(178),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: themeColor,
                          foregroundColor: Colors.white,
                          elevation: 8,
                          shadowColor: themeColor.withAlpha(127),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: onOpenOrbitPressed,
                        icon: const Icon(LucideIcons.play, size: 16),
                        label: const Text(
                          'Open Orbit',
                          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              ...children,
            ],
          ),
        ),
      ],
    );
  }
}

// ── Dating Tab Screen ────────────────────────────────────────────────────────

class _DatingTab extends StatelessWidget {
  const _DatingTab({required this.onOpenOrbit});

  final void Function(String, Color) onOpenOrbit;

  @override
  Widget build(BuildContext context) {
    const themeColor = Color(0xFFFF4F81);
    return _TabScaffold(
      title: 'Dating',
      themeColor: themeColor,
      chatLabel: 'Dating',
      onOpenOrbitPressed: () => onOpenOrbit('Dating', themeColor),
      children: [
        const Text(
          'Featured Matches',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 0.85,
          ),
          itemCount: 4,
          itemBuilder: (context, index) {
            final names = ['Sophia', 'Liam', 'Olivia', 'Ethan'];
            final ages = ['21', '22', '20', '23'];
            final tags = ['Art', 'Music', 'Tech', 'Nature'];

            return Container(
              decoration: BoxDecoration(
                color: const Color(0xFF111619),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withAlpha(13)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: themeColor.withAlpha(26),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      child: Center(
                        child: Icon(LucideIcons.heart, color: themeColor.withAlpha(127), size: 36),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              names[index],
                              style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              ages[index],
                              style: TextStyle(color: Colors.white.withAlpha(127), fontSize: 12),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: themeColor.withAlpha(26),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            tags[index],
                            style: const TextStyle(color: themeColor, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

// ── Friends Tab Screen ───────────────────────────────────────────────────────

class _FriendsTab extends StatelessWidget {
  const _FriendsTab({required this.onOpenOrbit});

  final void Function(String, Color) onOpenOrbit;

  @override
  Widget build(BuildContext context) {
    const themeColor = Color(0xFFFF9F1C);
    return _TabScaffold(
      title: 'Friends',
      themeColor: themeColor,
      chatLabel: 'Friends',
      onOpenOrbitPressed: () => onOpenOrbit('Friends', themeColor),
      children: [
        const Text(
          'Active Hangouts',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 12),
        Column(
          children: List.generate(3, (index) {
            final titles = ['Board Games Night', 'Study Group - Calculus', 'Weekend Hiking'];
            final counts = ['3/5 active', '2/4 active', '5/8 active'];
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF111619),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withAlpha(13)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: themeColor.withAlpha(26),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(LucideIcons.users, color: themeColor),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titles[index],
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          counts[index],
                          style: TextStyle(color: Colors.white.withAlpha(127), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const Icon(LucideIcons.chevronRight, color: Color(0x66FFFFFF), size: 16),
                ],
              ),
            );
          }),
        ),
      ],
    );
  }
}

// ── My Profile Tab Screen ────────────────────────────────────────────────────

class _ProfileTab extends StatelessWidget {
  const _ProfileTab({required this.onOpenOrbit});

  final void Function(String, Color) onOpenOrbit;

  @override
  Widget build(BuildContext context) {
    const themeColor = Color(0xFF8B5CF6);
    final user = Supabase.instance.client.auth.currentUser;
    final config = AppConfig.current;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Custom Header
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'My Profile',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
              // Logout Action
              IconButton(
                icon: const Icon(LucideIcons.logOut, color: Colors.white),
                onPressed: () {
                  unawaited(Supabase.instance.client.auth.signOut());
                },
              ),
            ],
          ),
        ),

        // Scrollable content area
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 110),
            children: [
              // Profile Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E1B4B), Color(0xFF0F172A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: themeColor.withAlpha(76)),
                ),
                child: Column(
                  children: [
                    Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        CircleAvatar(
                          radius: 46,
                          backgroundColor: themeColor.withAlpha(51),
                          child: const Icon(LucideIcons.user, size: 48, color: Colors.white),
                        ),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(LucideIcons.check, size: 12, color: Colors.white),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (user?.email != null) ...[
                      Text(
                        user!.email!.split('@').first.toUpperCase(),
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user.email!,
                        style: TextStyle(color: Colors.white.withAlpha(127), fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Open Orbit quick launcher
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: themeColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () => onOpenOrbit('Personal Node', themeColor),
                  icon: const Icon(LucideIcons.globe, size: 18),
                  label: const Text(
                    'Open Personal Orbit',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Export code card if flavor variant
              if (config.isFlavorVariant) ...[
                const _ExportCodeCard(),
                const SizedBox(height: 20),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ── Professional Tab Screen ──────────────────────────────────────────────────

class _ProfessionalTab extends StatelessWidget {
  const _ProfessionalTab({required this.onOpenOrbit});

  final void Function(String, Color) onOpenOrbit;

  @override
  Widget build(BuildContext context) {
    const themeColor = Color(0xFF00F5D4);
    return _TabScaffold(
      title: 'Professional',
      themeColor: themeColor,
      chatLabel: 'Professional',
      onOpenOrbitPressed: () => onOpenOrbit('Professional', themeColor),
      children: [
        const Text(
          'Career & Projects',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 12),
        Column(
          children: List.generate(2, (index) {
            final companies = ['Nexus Labs', 'Tech Innovations'];
            final roles = ['Flutter Developer', 'UI/UX Intern'];
            final periods = ['Jan 2026 - Present', 'Jun 2025 - Dec 2025'];
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF111619),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withAlpha(13)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: themeColor.withAlpha(26),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(LucideIcons.briefcase, color: themeColor),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          roles[index],
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        Text(
                          companies[index],
                          style: TextStyle(color: Colors.white.withAlpha(178), fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          periods[index],
                          style: TextStyle(color: Colors.white.withAlpha(102), fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      ],
    );
  }
}

// ── Settings Tab Screen ──────────────────────────────────────────────────────

class _SettingsTab extends StatelessWidget {
  const _SettingsTab({required this.onOpenOrbit});

  final void Function(String, Color) onOpenOrbit;

  @override
  Widget build(BuildContext context) {
    const themeColor = Color(0xFF4EA8DE);
    return _TabScaffold(
      title: 'Settings',
      themeColor: themeColor,
      chatLabel: 'System',
      onOpenOrbitPressed: () => onOpenOrbit('Settings', themeColor),
      children: [
        const Text(
          'Preferences',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 12),
        Column(
          children: [
            _buildSettingTile(LucideIcons.bell, 'Notifications', 'On', themeColor),
            _buildSettingTile(LucideIcons.shieldAlert, 'Privacy & Safety', 'Secure', themeColor),
            _buildSettingTile(LucideIcons.palette, 'App Theme', 'Dark Mode', themeColor),
            _buildSettingTile(LucideIcons.helpCircle, 'Help & Feedback', '', themeColor),
          ],
        ),
      ],
    );
  }

  Widget _buildSettingTile(IconData icon, String title, String subtitle, Color themeColor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF111619),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withAlpha(13)),
      ),
      child: Row(
        children: [
          Icon(icon, color: themeColor, size: 20),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
            ),
          ),
          if (subtitle.isNotEmpty)
            Text(
              subtitle,
              style: TextStyle(color: Colors.white.withAlpha(102), fontSize: 13),
            ),
          const SizedBox(width: 8),
          const Icon(LucideIcons.chevronRight, color: Color(0x33FFFFFF), size: 16),
        ],
      ),
    );
  }
}

// ── Export Code Card ─────────────────────────────────────────────────────────

class _ExportCodeCard extends StatefulWidget {
  const _ExportCodeCard();

  @override
  State<_ExportCodeCard> createState() => _ExportCodeCardState();
}

class _ExportCodeCardState extends State<_ExportCodeCard> {
  static const Color _teal = Color(0xFF0D9488);
  static const int _ttlSeconds = 15 * 60; // 15 minutes

  bool _isLoading = false;
  String? _code;
  int _secondsRemaining = 0;
  Timer? _countdown;

  @override
  void dispose() {
    _countdown?.cancel();
    super.dispose();
  }

  String get _formattedTime {
    final m = (_secondsRemaining ~/ 60).toString().padLeft(2, '0');
    final s = (_secondsRemaining % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  bool get _hasActiveCode => _code != null && _secondsRemaining > 0;

  void _startCountdown() {
    _countdown?.cancel();
    _secondsRemaining = _ttlSeconds;
    _countdown = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _secondsRemaining--);
      if (_secondsRemaining <= 0) {
        t.cancel();
        setState(() => _code = null);
      }
    });
  }

  Future<void> _generateCode() async {
    setState(() => _isLoading = true);

    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) throw Exception('Session expired.');

      final appCheckToken = await FirebaseAppCheck.instance.getToken();
      final config = AppConfig.current;
      final dio = createDio();

      final response = await dio.post<Map<String, dynamic>>(
        '${config.backendUrl}/api/v1/profiles/export-code',
        options: Options(
          headers: {
            'Authorization': 'Bearer ${session.accessToken}',
            'X-Firebase-AppCheck': appCheckToken ?? '',
            'X-App-Variant': config.variantString,
          },
          validateStatus: (s) => s != null && s < 600,
        ),
      );

      if (response.statusCode == 200) {
        final code = response.data?['code'] as String?;
        if (code != null) {
          setState(() => _code = code);
          _startCountdown();
        }
      } else {
        final detail = response.data?['detail'] ?? 'Failed to generate code.';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFFD32F2F),
              content: Text(detail.toString(), style: const TextStyle(color: Colors.white)),
            ),
          );
        }
      }
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFD32F2F),
            content: Text(
              ErrorHandler.getFriendlyMessage(e),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _copyCode() {
    if (_code == null) return;
    unawaited(Clipboard.setData(ClipboardData(text: _code!)));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Color(0xFF111619),
        content: Text('Code copied!', style: TextStyle(color: Colors.white)),
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF111619),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x1F0D9488)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0x1A0D9488),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.upload_rounded, color: _teal, size: 18),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Export Profile Data',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Share with your Nexus main account',
                      style: TextStyle(fontSize: 12, color: Color(0x66FFFFFF)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (_hasActiveCode) ...[
            // Active code display
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0x0D0D9488),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0x330D9488)),
              ),
              child: Column(
                children: [
                  Text(
                    _code!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 10,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.timer_outlined, color: _teal, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        'Expires in $_formattedTime',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _teal,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ).animate().fade().scale(begin: const Offset(0.95, 0.95), duration: 300.ms),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _copyCode,
                    icon: const Icon(Icons.copy_rounded, size: 14),
                    label: const Text('Copy Code'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _teal,
                      side: const BorderSide(color: Color(0x330D9488)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      if (!_isLoading) {
                        unawaited(_generateCode());
                      }
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 14),
                    label: const Text('Refresh'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A2025),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            // No active code — generate prompt
            const Text(
              'Generate a one-time code to share your profile data with your main Nexus account. '
              'The code expires in 15 minutes.',
              style: TextStyle(
                fontSize: 13,
                color: Color(0x80FFFFFF),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(_teal),
                      ),
                    )
                  : ElevatedButton.icon(
                      onPressed: () {
                        unawaited(_generateCode());
                      },
                      icon: const Icon(Icons.generating_tokens_rounded, size: 16),
                      label: const Text('Generate Export Code'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _teal,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
            ),
          ],
        ],
      ),
    ).animate().fade(delay: 100.ms).slideY(begin: 0.05, end: 0, duration: 350.ms);
  }
}
