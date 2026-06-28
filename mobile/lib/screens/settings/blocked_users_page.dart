import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/screens/home/tabs/profile/widgets/storage_image.dart';
import 'package:nexus/utils/network_utils.dart';
import 'package:nexus/widgets/aesthetic_loaders.dart';
import 'package:nexus/widgets/nexus_toast.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BlockedUsersPage extends StatefulWidget {
  const BlockedUsersPage({super.key});

  @override
  State<BlockedUsersPage> createState() => _BlockedUsersPageState();
}

class _BlockedUsersPageState extends State<BlockedUsersPage> {
  static const _accentBlue = Color(0xFF0284C7);

  late final Dio _dio;
  final SupabaseClient _client = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  List<_BlockedUser> _users = [];
  // Track which user IDs are mid-unblock to show a spinner on their button.
  final Set<String> _unblocking = {};

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

      // 1. Fetch active block actions.
      final res = await _client
          .from('profile_discovery_actions')
          .select('id, target_id, created_at')
          .eq('actor_id', userId)
          .eq('action', 'block')
          .isFilter('revoked_at', null)
          .order('created_at', ascending: false);

      final rows = List<Map<String, dynamic>>.from(res as List);
      if (rows.isEmpty) {
        setState(() {
          _users = [];
          _loading = false;
        });
        return;
      }

      // 2. Resolve display info from backend.
      final targetIds = rows.map((r) => r['target_id'] as String).toList();
      final profiles = await _fetchProfiles(targetIds);

      final built = rows.map((row) {
        final info = profiles[row['target_id'] as String];
        return _BlockedUser(
          actionId: row['id'] as String,
          targetId: row['target_id'] as String,
          blockedAt: DateTime.parse(row['created_at'] as String).toLocal(),
          name: info?['name'] as String? ?? 'Unknown',
          age: (info?['age'] as num?)?.toInt(),
          campusName: info?['campus_name'] as String?,
          campusBranch: info?['campus_branch'] as String?,
          hometown: info?['hometown'] as String?,
          currentPlace: info?['current_place'] as String?,
          profilePic: info?['profile_pic'] as String?,
        );
      }).toList()
        ..sort((a, b) => b.blockedAt.compareTo(a.blockedAt));
      setState(() {
        _users = built;
        _loading = false;
      });
    } on Exception catch (_) {
      setState(() {
        _error = 'Failed to load blocked users. Tap to retry.';
        _loading = false;
      });
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
        options: Options(
          headers: {'Authorization': 'Bearer ${session.accessToken}'},
        ),
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

  Future<void> _unblock(_BlockedUser user) async {
    setState(() => _unblocking.add(user.targetId));
    try {
      final session = _client.auth.currentSession;
      if (session == null) return;
      await _dio.post<void>(
        '${AppConfig.current.backendUrl}/api/v1/discover/action',
        data: {'target_id': user.targetId, 'action': 'unblock'},
        options: Options(
          headers: {'Authorization': 'Bearer ${session.accessToken}'},
        ),
      );
      if (!mounted) return;
      setState(() => _users.removeWhere((u) => u.targetId == user.targetId));
      NexusToast.show(
        context,
        '${user.name} has been unblocked.',
        type: NexusToastType.success,
      );
    } on Exception catch (_) {
      if (!mounted) return;
      NexusToast.show(
        context,
        'Failed to unblock. Please try again.',
        type: NexusToastType.error,
      );
    } finally {
      if (mounted) setState(() => _unblocking.remove(user.targetId));
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
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0284C7), Color(0xFF3B82F6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0x330284C7),
              blurRadius: 12,
              offset: Offset(0, 4),
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
            'Blocked Users',
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
        icon: LucideIcons.ban,
        title: 'No blocked users',
        subtitle: 'Users you block will appear here.',
        accentColor: _accentBlue,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
      itemCount: _users.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _UserCard(
        user: _users[i],
        isUnblocking: _unblocking.contains(_users[i].targetId),
        onUnblock: (user) async {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => _ConfirmDialog(
              name: user.name,
              message: '${user.name} will be able to find and interact with you again.',
              confirmLabel: 'Unblock',
            ),
          );
          if (confirmed == true) await _unblock(user);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

class _BlockedUser {
  const _BlockedUser({
    required this.actionId,
    required this.targetId,
    required this.blockedAt,
    required this.name,
    this.age,
    this.campusName,
    this.campusBranch,
    this.hometown,
    this.currentPlace,
    this.profilePic,
  });

  final String actionId;
  final String targetId;
  final DateTime blockedAt;
  final String name;
  final int? age;
  final String? campusName;
  final String? campusBranch;
  final String? hometown;
  final String? currentPlace;
  final String? profilePic;
}

// ---------------------------------------------------------------------------
// User card
// ---------------------------------------------------------------------------

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.onUnblock,
    required this.isUnblocking,
  });

  final _BlockedUser user;
  final Future<void> Function(_BlockedUser) onUnblock;
  final bool isUnblocking;

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
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      const Icon(
                        LucideIcons.ban,
                        size: 11,
                        color: Color(0xFFCBD5E1),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Blocked ${_formatDate(user.blockedAt)}',
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
            // Unblock button
            SizedBox(
              width: 82,
              height: 34,
              child: isUnblocking
                  ? const Center(
                      child: NexusOrbitLoader(size: 28, lightMode: true),
                    )
                  : OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF0284C7),
                        side: const BorderSide(color: Color(0xFF0284C7)),
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () => onUnblock(user),
                      child: Text(
                        'Unblock',
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

  String? _secondaryLine(_BlockedUser u) {
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
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
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
        color: const Color(0xFF0284C7).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: GoogleFonts.manrope(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0284C7),
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
                foregroundColor: const Color(0xFF0284C7),
                side: const BorderSide(color: Color(0xFF0284C7)),
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
              child: Icon(icon, size: 28, color: accentColor.withValues(alpha: 0.5)),
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
