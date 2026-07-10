import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/screens/home/tabs/profile/widgets/storage_image.dart';
import 'package:nexus/theme/app_colors.dart';
import 'package:nexus/utils/network_utils.dart';
import 'package:nexus/widgets/aesthetic_loaders.dart';
import 'package:nexus/widgets/nexus_toast.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HiddenUsersPage extends StatefulWidget {
  const HiddenUsersPage({super.key});

  @override
  State<HiddenUsersPage> createState() => _HiddenUsersPageState();
}

class _HiddenUsersPageState extends State<HiddenUsersPage> {
  // Settings Signal — matches this page's parent Settings tab. Was
  // previously Safety Blue (#0284C7); Hidden Users isn't a safety surface.
  static const Color _accentBlue = AppColors.modeSettings;

  late final Dio _dio;
  final SupabaseClient _client = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  List<_HiddenUser> _users = [];
  final Set<String> _unhiding = {};

  @override
  void initState() {
    super.initState();
    _dio = createDio();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) throw Exception('Not signed in');

      // 1. Fetch all active hide actions - one row per tab per user.
      final res = await _client
          .from('profile_discovery_actions')
          .select('id, target_id, tab, created_at')
          .eq('actor_id', userId)
          .eq('action', 'hide')
          .isFilter('revoked_at', null)
          .order('created_at', ascending: false);

      final rows = List<Map<String, dynamic>>.from(res as List);
      if (rows.isEmpty) {
        if (mounted) {
          setState(() {
            _users = [];
            _loading = false;
          });
        }
        return;
      }

      // 2. Group rows by target_id.
      final grouped = <String, List<Map<String, dynamic>>>{};
      for (final row in rows) {
        final tid = row['target_id'] as String;
        grouped.putIfAbsent(tid, () => []).add(row);
      }

      // 3. Resolve display info from backend.
      final targetIds = grouped.keys.toList();
      final profiles = await _fetchProfiles(targetIds);

      final built = grouped.entries.map((entry) {
        final tid = entry.key;
        final info = profiles[tid];
        final entries = entry.value
            .map(
              (r) => _HideEntry(
                actionId: r['id'] as String,
                tab: r['tab'] as String? ?? '',
                hiddenAt: DateTime.parse(r['created_at'] as String).toLocal(),
              ),
            )
            .toList();
        return _HiddenUser(
          targetId: tid,
          entries: entries,
          name: info?['name'] as String? ?? 'Unknown',
          age: (info?['age'] as num?)?.toInt(),
          campusName: info?['campus_name'] as String?,
          campusBranch: info?['campus_branch'] as String?,
          hometown: info?['hometown'] as String?,
          currentPlace: info?['current_place'] as String?,
          profilePic: info?['profile_pic'] as String?,
        );
      }).toList()..sort((a, b) => b.latestHiddenAt.compareTo(a.latestHiddenAt));
      if (mounted) {
        setState(() {
          _users = built;
          _loading = false;
        });
      }
    } on Exception catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load hidden users. Tap to retry.';
          _loading = false;
        });
      }
    }
  }

  Future<Map<String, Map<String, dynamic>>> _fetchProfiles(
    List<String> targetIds,
  ) async {
    final session = _client.auth.currentSession;
    if (session == null) return {};
    try {
      final response = await _dio.post<List<dynamic>>(
        '${AppConfig.current.backendUrl}/api/v1/users/moderation-subjects',
        data: {'target_ids': targetIds},
      );
      final list = response.data ?? [];
      return {
        for (final item in list)
          (item as Map<String, dynamic>)['id'] as String: item,
      };
    } on Exception catch (_) {
      return {};
    }
  }

  Future<void> _unhide(_HiddenUser user) async {
    setState(() => _unhiding.add(user.targetId));
    try {
      final session = _client.auth.currentSession;
      if (session == null) return;

      // Fire an unhide for each tab the user is hidden on, in parallel.
      await Future.wait(
        user.entries.map(
          (entry) => _dio.post<void>(
            '${AppConfig.current.backendUrl}/api/v1/discover/action',
            data: {
              'target_id': user.targetId,
              'action': 'unhide',
              'tab': entry.tab,
            },
          ),
        ),
      );

      if (!mounted) return;
      setState(() => _users.removeWhere((u) => u.targetId == user.targetId));
      NexusToast.show(
        context,
        '${user.name} will appear in your feeds again.',
        type: NexusToastType.success,
      );
    } on Exception catch (_) {
      if (!mounted) return;
      NexusToast.show(
        context,
        'Failed to unhide. Please try again.',
        type: NexusToastType.error,
      );
    } finally {
      if (mounted) setState(() => _unhiding.remove(user.targetId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: _buildAppBar(),
      body: _buildBody(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.modeSettings,
              AppColors.tint(AppColors.modeSettings),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.modeSettings.withAlpha(0x33),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(LucideIcons.chevronLeft, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            'Hidden Users',
            style: GoogleFonts.manrope(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          centerTitle: true,
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const _LoadingView();
    if (_error != null) {
      return _ErrorView(message: _error!, onRetry: _load);
    }
    if (_users.isEmpty) {
      return const _EmptyView(
        icon: LucideIcons.eyeOff,
        title: 'No hidden users',
        subtitle: 'Users you hide from your feeds will appear here.',
        accentColor: _accentBlue,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
      itemCount: _users.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _UserCard(
        user: _users[i],
        isUnhiding: _unhiding.contains(_users[i].targetId),
        onUnhide: (user) async {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => _ConfirmDialog(
              name: user.name,
              message: '${user.name} will reappear in your discovery feeds.',
              confirmLabel: 'Unhide',
            ),
          );
          if (confirmed == true) await _unhide(user);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Data models
// ---------------------------------------------------------------------------

class _HideEntry {
  const _HideEntry({
    required this.actionId,
    required this.tab,
    required this.hiddenAt,
  });

  final String actionId;
  final String tab;
  final DateTime hiddenAt;
}

class _HiddenUser {
  const _HiddenUser({
    required this.targetId,
    required this.entries,
    required this.name,
    this.age,
    this.campusName,
    this.campusBranch,
    this.hometown,
    this.currentPlace,
    this.profilePic,
  });

  final String targetId;
  final List<_HideEntry> entries;
  final String name;
  final int? age;
  final String? campusName;
  final String? campusBranch;
  final String? hometown;
  final String? currentPlace;
  final String? profilePic;

  // The earliest hide date across all tabs.
  DateTime get firstHiddenAt =>
      entries.map((e) => e.hiddenAt).reduce((a, b) => a.isBefore(b) ? a : b);

  // The most recent hide date across all tabs - used for sort ordering.
  DateTime get latestHiddenAt =>
      entries.map((e) => e.hiddenAt).reduce((a, b) => a.isAfter(b) ? a : b);
}

// ---------------------------------------------------------------------------
// User card
// ---------------------------------------------------------------------------

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.onUnhide,
    required this.isUnhiding,
  });

  final _HiddenUser user;
  final Future<void> Function(_HiddenUser) onUnhide;
  final bool isUnhiding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar
            _Avatar(picPath: user.profilePic, name: user.name),
            const SizedBox(width: 14),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        user.name,
                        style: GoogleFonts.manrope(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      if (user.age != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          '${user.age}',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: const Color(0xFF64748B),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (_secondaryLine(user) != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      _secondaryLine(user)!,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  // Tab badges
                  Wrap(
                    spacing: 5,
                    runSpacing: 4,
                    children: user.entries
                        .map((e) => _TabBadge(tab: e.tab))
                        .toList(),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      const Icon(
                        LucideIcons.eyeOff,
                        size: 11,
                        color: Color(0xFFCBD5E1),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Hidden ${_formatDate(user.firstHiddenAt)}',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Unhide button
            SizedBox(
              width: 74,
              height: 34,
              child: isUnhiding
                  ? const Center(
                      child: NexusOrbitLoader(size: 28, lightMode: true),
                    )
                  : OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.modeSettings,
                        side: const BorderSide(color: AppColors.modeSettings),
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () => onUnhide(user),
                      child: Text(
                        'Unhide',
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String? _secondaryLine(_HiddenUser u) {
    if (AppConfig.current.appVariant == AppVariant.nexusMec) {
      final parts = [
        if (u.campusBranch != null) u.campusBranch!,
        if (u.campusName != null) u.campusName!,
      ];
      return parts.isEmpty ? null : parts.join(' · ');
    } else {
      final parts = [
        if (u.currentPlace != null) u.currentPlace!,
        if (u.hometown != null) u.hometown!,
      ];
      return parts.isEmpty ? null : parts.join(' · ');
    }
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}

class _TabBadge extends StatelessWidget {
  const _TabBadge({required this.tab});

  final String tab;

  // Matches each mode's Mode Signal color in custom_bottom_nav_bar.dart.
  static const Map<String, Color> _tabColors = {
    'Dating': AppColors.modeDating,
    'Friends': AppColors.modeFriends,
    'Professional': AppColors.modeProfessional,
  };

  @override
  Widget build(BuildContext context) {
    final color = _tabColors[tab] ?? const Color(0xFF64748B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        tab,
        style: GoogleFonts.manrope(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared sub-widgets
// ---------------------------------------------------------------------------

class _Avatar extends StatelessWidget {
  const _Avatar({required this.picPath, required this.name});

  final String? picPath;
  final String name;

  @override
  Widget build(BuildContext context) {
    if (picPath != null && picPath!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: StorageImage(
          imagePath: picPath!,
          width: 50,
          height: 50,
        ),
      );
    }
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: AppColors.modeSettings.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: GoogleFonts.manrope(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppColors.modeSettings,
          ),
        ),
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: NexusOrbitLoader(size: 64, lightMode: true),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.wifiOff, size: 40, color: Color(0xFFCBD5E1)),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: const Color(0xFF64748B),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.modeSettings,
                side: const BorderSide(color: AppColors.modeSettings),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                'Retry',
                style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({
    required this.name,
    required this.message,
    required this.confirmLabel,
  });

  final String name;
  final String message;
  final String confirmLabel;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Text(
        '$confirmLabel $name?',
        style: GoogleFonts.manrope(
          fontWeight: FontWeight.w800,
          fontSize: 17,
          color: const Color(0xFF0F172A),
        ),
      ),
      content: Text(
        message,
        style: GoogleFonts.inter(
          fontSize: 14,
          color: const Color(0xFF64748B),
          height: 1.5,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            'Cancel',
            style: GoogleFonts.manrope(
              color: const Color(0xFF64748B),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.modeSettings,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            confirmLabel,
            style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accentColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                icon,
                size: 28,
                color: accentColor.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: GoogleFonts.manrope(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
