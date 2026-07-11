import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/providers/discovery_hub_provider.dart';
import 'package:nexus/screens/chats/open_chat.dart';
import 'package:nexus/screens/home/tabs/friends/widgets/friends_lists_overlays.dart';
import 'package:nexus/screens/home/tabs/friends/widgets/friends_settings_overlay.dart';
import 'package:nexus/screens/home/widgets/custom_bottom_nav_bar.dart';
import 'package:nexus/screens/home/widgets/match_screen.dart';
import 'package:nexus/screens/home/widgets/profile_detail_sheet.dart';
import 'package:nexus/screens/home/widgets/settings_loading_skeleton.dart';
import 'package:nexus/screens/home/widgets/tab_scaffold.dart';
import 'package:nexus/theme/app_colors.dart';
import 'package:nexus/utils/error_handler.dart';
import 'package:nexus/utils/network_utils.dart';
import 'package:nexus/utils/orbit_refresh_notifier.dart';
import 'package:nexus/widgets/aesthetic_loaders.dart';
import 'package:nexus/widgets/nexus_toast.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FriendsTab extends ConsumerStatefulWidget {
  const FriendsTab({
    required this.onOpenOrbit,
    this.onNavigateToTab,
    super.key,
  });

  final void Function(String, Color) onOpenOrbit;
  final void Function(int)? onNavigateToTab;

  @override
  ConsumerState<FriendsTab> createState() => _FriendsTabState();
}

class _FriendsTabState extends ConsumerState<FriendsTab>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  StreamSubscription<bool>? _orbitSub;
  ProviderSubscription<AsyncValue<DiscoveryHubState>>? _hubSub;

  bool _isLoading = true;
  bool _isOrbitActive = false;
  bool _hasError = false;
  String? _errorMsg;

  List<String> _friendsTargetBuckets = [];
  List<String> _flatInterests = [];
  List<String> _causesSupported = [];
  final Set<String> _savingFields = {};

  List<dynamic> _missingFields = [];

  List<Map<String, dynamic>> _waveItems = [];
  int _unseenCount = 0;

  List<Map<String, dynamic>> _friends = [];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    unawaited(_pulseController.repeat(reverse: true));
    // Renders instantly from DiscoveryHubController's cached snapshot (if
    // any) via this immediate callback, then again whenever it reconciles
    // with the network in the background or is explicitly refreshed after
    // a mutation - replacing this tab's own _loadFriendsProfileStatus/
    // _fetchWaves/_fetchFriends calls on every mount.
    _hubSub = ref.listenManual(
      discoveryHubControllerProvider('friends'),
      (previous, next) {
        next.when(
          data: (data) {
            if (!mounted) return;
            setState(() {
              _applyHubState(data);
              _isLoading = false;
            });
          },
          loading: () {},
          error: (error, stackTrace) {
            if (!mounted) return;
            setState(() {
              _hasError = true;
              _errorMsg = error.toString();
              _isLoading = false;
            });
          },
        );
      },
      fireImmediately: true,
    );
    _orbitSub = OrbitRefreshNotifier.stream.listen((_) {
      unawaited(_loadFriendsProfileStatusSilent());
    });
  }

  @override
  void dispose() {
    _hubSub?.close();
    unawaited(_orbitSub?.cancel());
    _pulseController.dispose();
    super.dispose();
  }

  /// Applies a DiscoveryHubController snapshot to this tab's local fields
  /// - shared field-parsing/business logic stays exactly as it was, just
  /// fed from the shared controller's data instead of this tab's own
  /// fetch. Callers are responsible for wrapping this in setState.
  void _applyHubState(DiscoveryHubState data) {
    if (data.profileError != null) {
      _hasError = true;
      _errorMsg = data.profileError;
      return;
    }
    _hasError = false;
    _errorMsg = null;
    if (data.profileDetails != null) {
      _parseProfileData(data.profileDetails!);
    }
    // Preserve is_new flags set by optimistic inserts this session (same
    // merge _fetchFriends already did before this migration).
    final newIds = _friends
        .where((m) => m['is_new'] == true)
        .map((m) => m['matched_user_id'] as String?)
        .whereType<String>()
        .toSet();
    _friends = data.matches.map((m) {
      final uid = m['matched_user_id'] as String?;
      return (uid != null && newIds.contains(uid)) ? {...m, 'is_new': true} : m;
    }).toList();
    _waveItems = data.likes;
    _unseenCount = data.unseenCount;
  }

  void _parseProfileData(Map<String, dynamic> data) {
    _isOrbitActive = data['is_friends_active'] == true;

    final rawBuckets = data['friends_target_buckets'];
    _friendsTargetBuckets = rawBuckets is List
        ? rawBuckets.map((e) => e.toString()).toList()
        : [];

    final rawCauses = data['causes_supported'];
    _causesSupported = rawCauses is List
        ? rawCauses.map((e) => e.toString()).toList()
        : [];

    final rawSubInterests = data['sub_interests'];
    if (rawSubInterests is Map) {
      final flat = <String>[];
      rawSubInterests.forEach((parent, subs) {
        if (subs is List) {
          for (final sub in subs) {
            flat.add('$parent: $sub');
          }
        }
      });
      _flatInterests = flat;
    } else {
      _flatInterests = [];
    }
  }

  Future<void> _loadFriendsProfileStatus() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _hasError = false;
        _errorMsg = null;
      });
    }
    await ref
        .read(discoveryHubControllerProvider('friends').notifier)
        .refresh();
  }

  Future<void> _loadFriendsProfileStatusSilent() async {
    await ref
        .read(discoveryHubControllerProvider('friends').notifier)
        .refresh();
  }

  Future<bool> _saveFriendsProfileDetails(Map<String, dynamic> payload) async {
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        final config = AppConfig.current;
        final dio = createDio();
        final response = await dio.patch<Map<String, dynamic>>(
          '${config.backendUrl}/api/v1/profile/details',
          data: payload,
        );
        return response.statusCode == 200;
      }
    } on Exception catch (e, st) {
      ErrorHandler.handleError(
        e,
        stackTrace: st,
        level: ErrorLevel.warning,
        customMessage: '[FriendsTab] Error saving friends details',
        showUi: false,
      );
    }
    return false;
  }

  Future<void> _saveFriendsField(
    String field,
    dynamic value,
    StateSetter setModalState,
  ) async {
    setModalState(() => _savingFields.add(field));
    final success = await _saveFriendsProfileDetails({field: value});
    if (mounted) {
      setModalState(() {
        _savingFields.remove(field);
        if (success) {
          if (field == 'friends_target_buckets') {
            _friendsTargetBuckets = List<String>.from(value as List);
          } else if (field == 'causes_supported') {
            _causesSupported = List<String>.from(value as List);
          } else if (field == 'sub_interests') {
            final map = value as Map<String, List<String>>;
            final flat = <String>[];
            map.forEach((parent, subs) {
              for (final sub in subs) {
                flat.add('$parent: $sub');
              }
            });
            _flatInterests = flat;
          }
        }
      });
      await _loadFriendsProfileStatus();
    }
  }

  Future<void> _toggleOrbitState(bool active) async {
    setState(() => _isLoading = true);
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        final config = AppConfig.current;
        final dio = createDio();
        final response = await dio.patch<Map<String, dynamic>>(
          '${config.backendUrl}/api/v1/profile/details',
          data: {'is_friends_active': active},
        );

        if (response.statusCode == 200 && mounted) {
          if (active) {
            OrbitRefreshNotifier.notifyActivated();
          } else {
            OrbitRefreshNotifier.notifyDeactivated();
          }
          setState(() => _isOrbitActive = active);
          if (active) {
            await Navigator.push<void>(
              context,
              PageRouteBuilder<void>(
                opaque: false,
                pageBuilder: (context, animation, secondaryAnimation) =>
                    FriendsActivationOverlay(
                      onFinished: () => Navigator.pop(context),
                    ),
                transitionsBuilder:
                    (context, animation, secondaryAnimation, child) =>
                        FadeTransition(opacity: animation, child: child),
              ),
            );
          } else {
            NexusToast.show(context, 'Friends Orbit Deactivated.');
          }
        }
      }
    } on DioException catch (dioErr) {
      if (dioErr.response?.statusCode == 400 && mounted) {
        final responseData = dioErr.response?.data;
        if (responseData is Map && responseData['detail'] != null) {
          final detail = responseData['detail'];
          if (detail is Map && detail['missing_fields'] is List) {
            setState(() {
              _missingFields = detail['missing_fields'] as List<dynamic>;
            });

            final profileFields = [
              'name',
              'age',
              'interests',
              'profile_pic',
              'normal_pics',
            ];
            final hasMissingProfileFields = _missingFields.any(
              (field) => profileFields.contains(field.toString()),
            );

            if (hasMissingProfileFields) {
              _showProfileIncompleteDialog();
              return;
            }
            unawaited(_showFriendsSettingsOverlay(isActivating: true));
            await Future<void>.delayed(const Duration(milliseconds: 380));
            if (!mounted) return;
            NexusToast.show(
              context,
              'Complete your Friends settings to activate your orbit.',
              type: NexusToastType.error,
            );
            return;
          }
        }
        NexusToast.show(
          context,
          'Friends Profile is incomplete.',
          type: NexusToastType.error,
        );
      }
    } on Exception catch (e, st) {
      ErrorHandler.handleError(
        e,
        stackTrace: st,
        level: ErrorLevel.warning,
        customMessage: '[FriendsTab] Orbit activation failed',
        showUi: false,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showProfileIncompleteDialog() {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: const Row(
              children: [
                Icon(LucideIcons.alertTriangle, color: Colors.amber, size: 24),
                SizedBox(width: 8),
                Text(
                  'Profile Incomplete',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Please complete your core profile before setting up Friends features:',
                  style: TextStyle(color: Color(0xFF475569), fontSize: 14),
                ),
                const SizedBox(height: 16),
                ..._missingFields
                    .where(
                      (f) => !const {
                        'friends_target_buckets',
                        'sub_interests',
                        'causes_supported',
                      }.contains(f.toString()),
                    )
                    .map((field) {
                      final fieldStr = field.toString();
                      String label;
                      if (fieldStr == 'name') {
                        label = 'Display Name is missing';
                      } else if (fieldStr == 'age') {
                        label = 'Age is missing';
                      } else if (fieldStr == 'interests') {
                        label = 'At least 3 interests required';
                      } else if (fieldStr == 'profile_pic') {
                        label = 'Profile avatar image is missing';
                      } else if (fieldStr == 'normal_pics') {
                        label = 'At least 2 images required in profile gallery';
                      } else {
                        label = fieldStr.replaceAll('_', ' ');
                        label = label[0].toUpperCase() + label.substring(1);
                      }

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 2),
                              child: Icon(
                                LucideIcons.xCircle,
                                color: Colors.redAccent,
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                label,
                                style: const TextStyle(
                                  color: Color(0xFF334155),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
              ],
            ),
            actions: [
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF64748B),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.modeFriends,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  widget.onNavigateToTab?.call(2);
                },
                child: const Text('Go to Profile Tab'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showFriendsSettingsOverlay({bool isActivating = false}) async {
    if (!mounted) return;
    final loadingNotifier = ValueNotifier<bool>(true);
    unawaited(
      _loadFriendsProfileStatusSilent().then((_) {
        if (mounted) loadingNotifier.value = false;
      }),
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ValueListenableBuilder<bool>(
        valueListenable: loadingNotifier,
        builder: (context, isLoading, _) {
          if (isLoading) {
            return const SettingsLoadingSkeleton(
              themeColor: AppColors.modeFriends,
            );
          }
          return FriendsSettingsOverlay(
            friendsTargetBuckets: _friendsTargetBuckets,
            flatInterests: _flatInterests,
            causesSupported: _causesSupported,
            savingFields: _savingFields,
            onSaveFriendsField: (field, value, setStateCallback) async {
              await _saveFriendsField(field, value, setStateCallback);
            },
            onLoadFriendsProfileStatusSilent: () async {
              await _loadFriendsProfileStatusSilent();
            },
            isActivating: isActivating,
            onToggleOrbitState: ({required active}) async {
              await _toggleOrbitState(active);
            },
          );
        },
      ),
    );
  }

  // These now refresh the shared DiscoveryHubController (which fetches
  // profile status + likes + matches together) rather than doing their own
  // standalone fetch - callers (WavesOverlay/FriendsListOverlay's pull-to-
  // refresh, the optimistic-match-insert follow-up fetch) keep the same
  // Future<void> Function() shape they already expect.
  Future<void> _fetchWaves() async {
    await ref
        .read(discoveryHubControllerProvider('friends').notifier)
        .refresh();
  }

  Future<void> _fetchFriends() async {
    await ref
        .read(discoveryHubControllerProvider('friends').notifier)
        .refresh();
  }

  Future<bool> _recordFriendAction(
    String targetId,
    String action,
    String accessToken, {
    String? reason,
    String? reasonDetail,
  }) async {
    try {
      final config = AppConfig.current;
      final dio = createDio();
      final body = <String, dynamic>{
        'target_id': targetId,
        'action': action,
        'tab': 'Friends',
      };
      if (reason != null) body['reason'] = reason;
      if (reasonDetail != null) body['reason_detail'] = reasonDetail;
      final response = await dio.post<void>(
        '${config.backendUrl}/api/v1/matches/action',
        data: body,
      );
      return response.statusCode == 200;
    } on Exception catch (e, st) {
      ErrorHandler.handleError(
        e,
        stackTrace: st,
        level: ErrorLevel.warning,
        customMessage: '[FriendsTab] Error recording friend action',
        showUi: false,
      );
      return false;
    }
  }

  Future<void> _markAllWavesSeen() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return;
    try {
      final config = AppConfig.current;
      final dio = createDio();
      await dio.post<void>(
        '${config.backendUrl}/api/v1/likes/mark-seen',
        data: {'mark_all': true},
      );
    } on Exception catch (e, st) {
      ErrorHandler.handleError(
        e,
        stackTrace: st,
        level: ErrorLevel.warning,
        customMessage: '[FriendsTab] Error marking waves seen',
        showUi: false,
      );
    }
  }

  Future<Map<String, dynamic>> _fetchPeerProfile(
    String actorId,
    String accessToken,
  ) async {
    final config = AppConfig.current;
    final dio = createDio();
    final response = await dio.post<Map<String, dynamic>>(
      '${config.backendUrl}/api/v1/profile/peer',
      data: {'target_id': actorId, 'tab': 'Friends'},
    );
    if (response.statusCode == 200 && response.data != null) {
      return response.data!;
    }
    throw Exception('Failed to load peer profile');
  }

  Future<Map<String, dynamic>?> _recordWaveAction(
    String targetId,
    String action,
    String accessToken, {
    String? reason,
    String? reasonDetail,
  }) async {
    try {
      final config = AppConfig.current;
      final dio = createDio();
      final body = <String, dynamic>{
        'target_id': targetId,
        'action': action,
        'tab': 'Friends',
      };
      if (reason != null) body['reason'] = reason;
      if (reasonDetail != null) body['reason_detail'] = reasonDetail;
      final response = await dio.post<Map<String, dynamic>>(
        '${config.backendUrl}/api/v1/likes/action',
        data: body,
      );
      if (response.statusCode == 200) return response.data;
      return null;
    } on Exception catch (e, st) {
      ErrorHandler.handleError(
        e,
        stackTrace: st,
        level: ErrorLevel.warning,
        customMessage: '[FriendsTab] Error recording wave action',
        showUi: false,
      );
      return null;
    }
  }

  Widget _buildWaveBackActionBar(
    BuildContext ctx,
    String actorId,
    String name,
    Color theme,
    String? matchedProfilePic,
    void Function(String) onActioned,
  ) {
    final session = Supabase.instance.client.auth.currentSession;

    Future<void> doAction(String action) async {
      final rootNav = Navigator.of(ctx, rootNavigator: true);
      Navigator.pop(ctx);
      final result = session != null
          ? await _recordWaveAction(actorId, action, session.accessToken)
          : null;
      onActioned(actorId);
      if (result?['matched'] == true) {
        final matchId = result?['match_id'] as String?;
        if (mounted) {
          setState(() {
            _friends.insert(0, {
              'match_id': matchId,
              'matched_user_id': actorId,
              'name': name,
              'age': null,
              'profile_pic': matchedProfilePic,
              'matched_at': DateTime.now().toIso8601String(),
              'is_new': true,
            });
          });
        }
        unawaited(_fetchFriends());

        final goToFriends = await rootNav.push<bool?>(
          MaterialPageRoute<bool?>(
            fullscreenDialog: true,
            builder: (_) => MatchScreen(
              matchedName: name,
              matchedProfilePic: matchedProfilePic,
              titleText: "You're now Friends! 👋",
              subtitleText:
                  'You and $name waved back at each other.\nTime to plan something fun!',
              themeColor: theme,
              badgeIcon: LucideIcons.users,
            ),
          ),
        );
        if (goToFriends == true && mounted) {
          Navigator.of(context).pop();
          await openOrCreateChat(
            context,
            matchId: matchId,
            matchedUserId: actorId,
            name: name,
            profilePic: matchedProfilePic,
          );
        }
      }
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      decoration: BoxDecoration(
        color: const Color(0xFF090D1A),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white54,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: () => doAction('pass'),
              icon: const Icon(LucideIcons.x, size: 14),
              label: const Text(
                'Pass',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.warning, AppColors.error],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.warning.withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () => doAction('superlike'),
                icon: const Icon(LucideIcons.star, size: 14),
                label: const Text(
                  'Super Wave',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme,
                    Color.lerp(theme, const Color(0xFF7C3AED), 0.42)!,
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: theme.withValues(alpha: 0.38),
                    blurRadius: 18,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () => doAction('like'),
                icon: const Icon(LucideIcons.hand, size: 14),
                label: const Text(
                  'Wave Back',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showWaveProfile({
    required BuildContext ctx,
    required String actorId,
    required String name,
    required void Function(String actorId) onActioned,
  }) async {
    const themeColor = AppColors.modeFriends;
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return;

    final waveEntry = _waveItems.firstWhere(
      (i) => i['actor_id'] == actorId,
      orElse: () => <String, dynamic>{},
    );
    final matchedProfilePic = waveEntry['profile_pic'] as String?;

    await showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return FutureBuilder<Map<String, dynamic>>(
          future: _fetchPeerProfile(actorId, session.accessToken),
          builder: (sheetCtx, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Container(
                height: MediaQuery.of(sheetCtx).size.height * 0.7,
                decoration: const BoxDecoration(
                  color: Color(0xFF090D1A),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: const Center(
                  child: NexusOrbitLoader(size: 56),
                ),
              );
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return Container(
                height: MediaQuery.of(sheetCtx).size.height * 0.4,
                decoration: const BoxDecoration(
                  color: Color(0xFF090D1A),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: const Center(
                  child: Text(
                    'Unable to load profile.',
                    style: TextStyle(color: Colors.white38),
                  ),
                ),
              );
            }
            return DraggableScrollableSheet(
              initialChildSize: 0.92,
              minChildSize: 0.5,
              maxChildSize: 0.97,
              expand: false,
              builder: (dsCtx, scrollController) {
                return ProfileDetailSheet(
                  data: snapshot.data!,
                  themeColor: themeColor,
                  scrollController: scrollController,
                  showScoreBadge: false,
                  actionBar: _buildWaveBackActionBar(
                    dsCtx,
                    actorId,
                    name,
                    themeColor,
                    matchedProfilePic,
                    onActioned,
                  ),
                  onHideTap: (c) async {
                    Navigator.pop(c);
                    await _recordWaveAction(
                      actorId,
                      'hide',
                      session.accessToken,
                    );
                    onActioned(actorId);
                  },
                  onBlockTap: (c) async {
                    final ok = await showProfileBlockDialog(c, name);
                    if ((ok ?? false) && c.mounted) {
                      Navigator.pop(c);
                      await _recordWaveAction(
                        actorId,
                        'block',
                        session.accessToken,
                      );
                      onActioned(actorId);
                    }
                  },
                  onReportTap: (c) => showProfileReportDialog(
                    c,
                    themeColor: themeColor,
                    onConfirmed: (reason, detail) async {
                      Navigator.pop(c);
                      await _recordWaveAction(
                        actorId,
                        'report',
                        session.accessToken,
                        reason: reason,
                        reasonDetail: detail,
                      );
                      onActioned(actorId);
                    },
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _showWavesOverlay() async {
    setState(() => _unseenCount = 0);
    unawaited(_markAllWavesSeen());

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return WavesOverlay(
          waves: _waveItems,
          onFetchWaves: _fetchWaves,
          onOpenWavesDetailsDialog: _showWaveProfile,
          onRecordWavesAction: _recordWaveAction,
        );
      },
    );
  }

  void _showFriendsListOverlay() {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetCtx) {
          return FriendsListOverlay(
            friends: _friends,
            onFetchFriends: _fetchFriends,
            onRecordFriendAction: _recordFriendAction,
            onRemoveFriend: (userId) {
              setState(() {
                _friends.removeWhere((m) => m['matched_user_id'] == userId);
              });
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const themeColor = AppColors.modeFriends;
    final activeWavesCount = _unseenCount;

    if (_hasError) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  LucideIcons.alertCircle,
                  color: themeColor,
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  'Error loading friends profile:\n${_errorMsg ?? "Unknown error"}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: themeColor,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    unawaited(_loadFriendsProfileStatus());
                  },
                  child: const Text('Try Again'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: NexusOrbitLoader(size: 64, lightMode: true)),
      );
    }

    return TabScaffold(
      title: 'Friends',
      themeColor: themeColor,
      chatLabel: 'Friends',
      isOrbitActive: _isOrbitActive,
      orbitDescription:
          'Start broadcasting your social signals & begin connecting with people near your orbit.',
      onOpenOrbitPressed: () => _toggleOrbitState(true),
      onDeactivateOrbitPressed: () => _toggleOrbitState(false),
      onSettingsPressed: _showFriendsSettingsOverlay,
      children: [
        Stack(
          children: [
            Opacity(
              opacity: _isOrbitActive ? 1.0 : 0.35,
              child: IgnorePointer(
                ignoring: !_isOrbitActive,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            AppColors.modeFriends,
                            Color(0xFFFF6B35),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.modeFriends.withAlpha(76),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: InkWell(
                        onTap: () {
                          widget.onOpenOrbit(
                            'Friends',
                            AppColors.modeFriends,
                          );
                        },
                        borderRadius: BorderRadius.circular(24),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withAlpha(51),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  LucideIcons.orbit,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 16),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Open your Friends Orbit',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Discover people who share your vibe',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                LucideIcons.chevronRight,
                                color: Colors.white,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: AnimatedBuilder(
                            animation: _pulseController,
                            builder: (context, child) {
                              return Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(24),
                                  boxShadow: [
                                    BoxShadow(
                                      color: themeColor.withAlpha(
                                        (_pulseController.value * 25 + 10)
                                            .toInt(),
                                      ),
                                      blurRadius: 16,
                                      spreadRadius: _pulseController.value * 2,
                                    ),
                                  ],
                                ),
                                child: child,
                              );
                            },
                            child: Material(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(24),
                              child: InkWell(
                                onTap: _showWavesOverlay,
                                borderRadius: BorderRadius.circular(24),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 24,
                                    horizontal: 16,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(
                                      color: themeColor.withAlpha(40),
                                      width: 1.5,
                                    ),
                                    gradient: LinearGradient(
                                      colors: [
                                        const Color(0xFF1E293B),
                                        themeColor.withAlpha(20),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: themeColor.withAlpha(30),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          LucideIcons.hand,
                                          color: themeColor,
                                          size: 28,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      const Text(
                                        'Waves',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: themeColor,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Text(
                                          '$activeWavesCount NEW',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Material(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(24),
                            child: InkWell(
                              onTap: _showFriendsListOverlay,
                              borderRadius: BorderRadius.circular(24),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 24,
                                  horizontal: 16,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: Colors.white.withAlpha(15),
                                    width: 1.5,
                                  ),
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF1E293B),
                                      Color(0xFF0F172A),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withAlpha(15),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        LucideIcons.users,
                                        color: Colors.white,
                                        size: 28,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    const Text(
                                      'Friends',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withAlpha(25),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '${_friends.length} ACTIVE',
                                        style: TextStyle(
                                          color: Colors.white.withAlpha(200),
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            if (!_isOrbitActive)
              Positioned.fill(
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 24,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: Colors.black.withAlpha(15)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: themeColor.withAlpha(25),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            LucideIcons.lock,
                            color: themeColor,
                            size: 28,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Orbit Inactive',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Activate Friends Orbit to start meeting people nearby, send waves, and build your circle.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: themeColor,
                            side: const BorderSide(
                              color: themeColor,
                              width: 1.5,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                          ),
                          onPressed: _showFriendsSettingsOverlay,
                          icon: const Icon(LucideIcons.settings, size: 16),
                          label: const Text(
                            'Friends Settings',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class FriendsActivationOverlay extends StatefulWidget {
  const FriendsActivationOverlay({required this.onFinished, super.key});

  final VoidCallback onFinished;

  @override
  State<FriendsActivationOverlay> createState() =>
      _FriendsActivationOverlayState();
}

class _FriendsActivationOverlayState extends State<FriendsActivationOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.8, curve: Curves.easeOutBack),
      ),
    );

    _fadeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 0, end: 1), weight: 15),
      TweenSequenceItem(tween: ConstantTween<double>(1), weight: 70),
      TweenSequenceItem(tween: Tween<double>(begin: 1, end: 0), weight: 15),
    ]).animate(_controller);

    _rotationAnimation = Tween<double>(begin: 0, end: 2 * 3.14159).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.9),
      ),
    );

    unawaited(_controller.forward().then((_) => widget.onFinished()));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const brandColor = AppColors.modeFriends;
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF0F172A),
                const Color(0xFF1A1200),
                const Color(0xFF7C3A00).withValues(alpha: 0.95),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedBuilder(
                animation: _rotationAnimation,
                builder: (context, child) {
                  return Transform.rotate(
                    angle: _rotationAnimation.value,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        _buildRing(260, 4, brandColor.withValues(alpha: 0.1)),
                        _buildRing(200, 3, brandColor.withValues(alpha: 0.2)),
                        _buildRing(140, 2, brandColor.withValues(alpha: 0.3)),
                      ],
                    ),
                  );
                },
              ),
              ScaleTransition(
                scale: _scaleAnimation,
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: brandColor,
                    boxShadow: [
                      BoxShadow(
                        color: brandColor.withValues(alpha: 0.5),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      LucideIcons.users,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: CustomBottomNavBar.clearance,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'FRIENDS ORBIT',
                      style: TextStyle(
                        color: brandColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Orbit Activated',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Broadcasting your social signals nearby...',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRing(double size, double strokeWidth, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: strokeWidth),
      ),
    );
  }
}
