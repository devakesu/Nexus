import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/config/app_config.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/core/widgets/scale_pressable.dart';
import 'package:nexus/features/chats/providers/chats_providers.dart';
import 'package:nexus/features/chats/widgets/chat_list_tab.dart';

/// Entry point reached from the header chat icon, the match-celebration
/// "Send a message" button, and the per-tab match list overlays. Shows
/// active conversations grouped into the app's 3 discovery modes.
class ChatsPage extends ConsumerStatefulWidget {
  const ChatsPage({super.key});

  @override
  ConsumerState<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends ConsumerState<ChatsPage>
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

  Color _getInterpolatedColor(double value) {
    final colors = [
      AppColors.modeDating,
      AppColors.modeFriends,
      AppColors.modeProfessional,
    ];
    if (value <= 0) return colors[0];
    if (value >= colors.length - 1) return colors[colors.length - 1];

    final index = value.floor();
    final localValue = value - index;
    return Color.lerp(colors[index], colors[index + 1], localValue) ??
        colors[index];
  }

  Color _getTabThemeColor(String tab) {
    switch (tab) {
      case 'Dating':
        return AppColors.modeDating;
      case 'Friends':
        return AppColors.modeFriends;
      case 'Professional':
        return AppColors.modeProfessional;
      default:
        return AppColors.primaryTeal;
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusBarHeight = MediaQuery.of(context).padding.top;
    final unreadCounts = {
      for (final t in _tabs)
        t:
            ref
                .watch(chatConversationsProvider(t))
                .value
                ?.fold<int>(0, (sum, c) => sum + c.unreadCount) ??
            0,
    };

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: Column(
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(16, statusBarHeight + 12, 16, 16),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              boxShadow: [
                BoxShadow(
                  color: Color(0x08000000), // black @ ~3% matching Ambient Card
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ScalePressable(
                      onTap: () => Navigator.of(context).maybePop(),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.canvas,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.borderNeutral,
                          ),
                        ),
                        child: const Icon(
                          LucideIcons.chevronLeft,
                          color: AppColors.ink,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      AppConfig.current.isFlavorVariant
                          ? 'Nexus MEC Chats'
                          : 'Nexus Chats',
                      style: GoogleFonts.manrope(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                AnimatedBuilder(
                  animation: _tabController.animation!,
                  builder: (context, _) {
                    final animValue =
                        _tabController.animation?.value ??
                        _tabController.index.toDouble();
                    final activeColor = _getInterpolatedColor(animValue);

                    return Container(
                      height: 46,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: AppColors.canvas,
                        borderRadius: BorderRadius.circular(23),
                        border: Border.all(
                          color: AppColors.borderNeutral,
                        ),
                      ),
                      child: TabBar(
                        controller: _tabController,
                        dividerColor: Colors.transparent,
                        indicatorSize: TabBarIndicatorSize.tab,
                        indicator: BoxDecoration(
                          color: activeColor,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: activeColor.withValues(alpha: 0.3),
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        labelColor: Colors.white,
                        unselectedLabelColor: AppColors.inkMuted,
                        labelStyle: GoogleFonts.manrope(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                        unselectedLabelStyle: GoogleFonts.manrope(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        tabs: _tabs.map(
                          (t) {
                            final unreadCount = unreadCounts[t] ?? 0;
                            final isSelected =
                                _tabController.index == _tabs.indexOf(t);

                            return Tab(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(t),
                                    if (unreadCount > 0) ...[
                                      const SizedBox(width: 5),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 1.5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? Colors.white
                                              : _getTabThemeColor(t),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          unreadCount > 99
                                              ? '99+'
                                              : '$unreadCount',
                                          style: TextStyle(
                                            color: isSelected
                                                ? _getTabThemeColor(t)
                                                : Colors.white,
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ).toList(),
                      ),
                    );
                  },
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
