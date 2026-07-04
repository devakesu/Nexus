import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/screens/chats/chat_theme.dart';
import 'package:nexus/screens/chats/widgets/chat_list_tab.dart';

/// Entry point reached from the header chat icon, the match-celebration
/// "Send a message" button, and the per-tab match list overlays. Shows
/// active conversations grouped into the app's 3 discovery modes.
class ChatsPage extends StatefulWidget {
  const ChatsPage({super.key});

  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<ChatsPage>
    with SingleTickerProviderStateMixin {
  static const _tabs = ['Dating', 'Friends', 'Professional'];

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this)
      ..addListener(_handleTabChange);
  }

  void _handleTabChange() {
    // Only rebuild the header gradient once the settle lands on a new index,
    // not on every intermediate swipe frame.
    if (!_tabController.indexIsChanging) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_handleTabChange)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = chatTabTheme(_tabs[_tabController.index]);
    final statusBarHeight = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      body: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            padding: EdgeInsets.fromLTRB(4, statusBarHeight + 4, 16, 0),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [theme.primary, theme.secondary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
              boxShadow: [
                BoxShadow(
                  color: theme.primary.withValues(alpha: 0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        LucideIcons.chevronLeft,
                        color: Colors.white,
                      ),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    Text(
                      'Chats',
                      style: GoogleFonts.manrope(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                TabBar(
                  controller: _tabController,
                  indicatorColor: Colors.white,
                  indicatorWeight: 3,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white.withValues(alpha: 0.62),
                  labelStyle: GoogleFonts.manrope(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                  tabs: _tabs.map((t) => Tab(text: t)).toList(),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: _tabs.map((t) => ChatListTab(tab: t)).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
