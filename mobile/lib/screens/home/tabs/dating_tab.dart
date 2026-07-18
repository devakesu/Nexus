import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/providers/discovery_hub_provider.dart';
import 'package:nexus/screens/chats/open_chat.dart';
import 'package:nexus/screens/home/tabs/dating/widgets/dating_activation_overlay.dart';
import 'package:nexus/screens/home/tabs/dating/widgets/dating_lists_overlays.dart';
import 'package:nexus/screens/home/tabs/dating/widgets/dating_settings_overlay.dart';
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

class DatingTab extends ConsumerStatefulWidget {
  const DatingTab({
    required this.onOpenOrbit,
    this.onNavigateToTab,
    super.key,
  });

  final void Function(String, Color) onOpenOrbit;
  final void Function(int, [String?])? onNavigateToTab;

  @override
  ConsumerState<DatingTab> createState() => _DatingTabState();
}

class _DatingTabState extends ConsumerState<DatingTab>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late final Dio _dio;
  StreamSubscription<bool>? _orbitSub;
  ProviderSubscription<AsyncValue<DiscoveryHubState>>? _hubSub;

  // State variables for Orbit activation & profile details
  bool _isLoading = true;
  bool _isOrbitActive = false;
  bool _hasError = false;
  String? _errorMsg;

  // Profile fields loaded from server (for settings form)
  List<String> _datingTargetBuckets = [];
  List<String> _datingFor = [];
  List<String> _partnerValues = [];
  String _childrenPlans = '';
  final Set<String> _savingFields = {};
  final Map<String, dynamic> _pendingSaves = {};
  final Set<String> _activeSaves = {};

  // Local state for checking off missing fields dialog
  List<dynamic> _missingFields = [];

  // Likes inbox - populated from GET /api/v1/likes
  final List<Map<String, dynamic>> _likeItems = [];
  int _unseenCount = 0;

  // Matches - populated from GET /api/v1/matches
  List<Map<String, dynamic>> _matches = [];

  @override
  void initState() {
    super.initState();
    _dio = createDio();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    unawaited(_pulseController.repeat(reverse: true));
    // Renders instantly from DiscoveryHubController's cached snapshot (if
    // any) via this immediate callback, then again whenever it reconciles
    // with the network in the background or is explicitly refreshed after
    // a mutation - replacing this tab's own _loadDatingProfileStatus/
    // _fetchLikes/_fetchMatches calls on every mount.
    _hubSub = ref.listenManual(
      discoveryHubControllerProvider('dating'),
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
      unawaited(_loadDatingProfileStatusSilent());
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
  /// - shared field-parsing/business logic (_parseProfileData, save/toggle/
  /// record-action methods) stays exactly as it was, just fed from the
  /// shared controller's data instead of this tab's own fetch. Callers are
  /// responsible for wrapping this in setState.
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
    // merge _fetchMatches already did before this migration).
    final newIds = _matches
        .where((m) => m['is_new'] == true)
        .map((m) => m['matched_user_id'] as String?)
        .whereType<String>()
        .toSet();
    _matches = data.matches.map((m) {
      final uid = m['matched_user_id'] as String?;
      return (uid != null && newIds.contains(uid)) ? {...m, 'is_new': true} : m;
    }).toList();
    _likeItems
      ..clear()
      ..addAll(data.likes);
    _unseenCount = data.unseenCount;
  }

  // Load current profile details from secure endpoint
  void _parseProfileData(Map<String, dynamic> data) {
    _isOrbitActive = data['is_dating_active'] == true;

    final rawBuckets = data['dating_target_buckets'];
    _datingTargetBuckets = rawBuckets is List
        ? rawBuckets.map((e) => e.toString()).toList()
        : [];
    final rawDatingFor = data['dating_for'];
    _datingFor = rawDatingFor is List
        ? rawDatingFor.map((e) => e.toString()).toList()
        : [];
    final rawPartnerValues = data['partner_values'];
    _partnerValues = rawPartnerValues is List
        ? rawPartnerValues.map((e) => e.toString()).toList()
        : [];
    _childrenPlans = data['children_plans']?.toString() ?? '';
  }

  Future<void> _loadDatingProfileStatus() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _hasError = false;
        _errorMsg = null;
      });
    }
    await ref.read(discoveryHubControllerProvider('dating').notifier).refresh();
  }

  Future<void> _loadDatingProfileStatusSilent() async {
    await ref.read(discoveryHubControllerProvider('dating').notifier).refresh();
  }

  // Save profile updates to the details endpoint
  Future<bool> _saveDatingProfileDetails(Map<String, dynamic> payload) async {
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        final config = AppConfig.current;
        final dio = _dio;
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
        customMessage: '[DatingTab] Error saving dating details',
        showUi: false,
      );
    }
    return false;
  }

  // Real-time save helper for individual settings fields
  Future<void> _saveDatingField(
    String field,
    dynamic value,
    StateSetter setModalState,
  ) async {
    if (_activeSaves.contains(field)) {
      _pendingSaves[field] = value;
      setModalState(() {
        _savingFields.add(field);
      });
      return;
    }

    _activeSaves.add(field);
    setModalState(() {
      _savingFields.add(field);
    });

    dynamic currentValueToSave = value;
    var success = false;

    while (true) {
      success = await _saveDatingProfileDetails({
        field: currentValueToSave,
      });

      if (_pendingSaves.containsKey(field)) {
        currentValueToSave = _pendingSaves[field];
        _pendingSaves.remove(field);
      } else {
        break;
      }
    }

    _activeSaves.remove(field);
    if (mounted) {
      setModalState(() {
        _savingFields.remove(field);
        if (success) {
          if (field == 'dating_target_buckets') {
            _datingTargetBuckets = List<String>.from(currentValueToSave as List);
          } else if (field == 'dating_for') {
            _datingFor = List<String>.from(currentValueToSave as List);
          } else if (field == 'partner_values') {
            _partnerValues = List<String>.from(currentValueToSave as List);
          } else if (field == 'children_plans') {
            _childrenPlans = currentValueToSave as String;
          }
        }
      });
      // Synchronize states
      await _loadDatingProfileStatusSilent();
    }
  }

  // Toggle Orbit activation state (patching is_dating_active)
  Future<void> _toggleOrbitState(bool active) async {
    final oldActive = _isOrbitActive;
    setState(() {
      _isLoading = true;
      _isOrbitActive = active;
    });
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        final config = AppConfig.current;
        final dio = _dio;
        final response = await dio.patch<Map<String, dynamic>>(
          '${config.backendUrl}/api/v1/profile/details',
          data: {'is_dating_active': active},
        );

        if (response.statusCode == 200 && mounted) {
          if (active) {
            OrbitRefreshNotifier.notifyActivated();
          } else {
            OrbitRefreshNotifier.notifyDeactivated();
          }
          if (active) {
            await Navigator.push<void>(
              context,
              PageRouteBuilder<void>(
                opaque: false,
                pageBuilder: (context, animation, secondaryAnimation) =>
                    DatingActivationOverlay(
                      onFinished: () {
                        Navigator.pop(context);
                      },
                    ),
                transitionsBuilder:
                    (context, animation, secondaryAnimation, child) {
                      return FadeTransition(opacity: animation, child: child);
                    },
              ),
            );
          } else {
            NexusToast.show(context, 'Dating Orbit Deactivated.');
          }
        } else {
          throw Exception('Failed to toggle orbit state');
        }
      }
    } on DioException catch (dioErr) {
      if (mounted) {
        setState(() {
          _isOrbitActive = oldActive;
        });
      }
      if (dioErr.response?.statusCode == 400 && mounted) {
        final responseData = dioErr.response?.data;
        if (responseData is Map && responseData['detail'] != null) {
          final detail = responseData['detail'];
          if (detail is Map && detail['missing_fields'] is List) {
            setState(() {
              _missingFields = detail['missing_fields'] as List<dynamic>;
            });

            // Separate profile fields from dating-only fields
            final profileFields = [
              'name',
              'age',
              'drinking',
              'smoking',
              'interests',
              'profile_pic',
              'normal_pics',
              'bio',
            ];
            final hasMissingProfileFields = _missingFields.any(
              (field) => profileFields.contains(field.toString()),
            );

            if (hasMissingProfileFields) {
              _showProfileIncompleteDialog();
              return;
            }
            unawaited(_showDatingSettingsOverlay(isActivating: true));
            await Future<void>.delayed(const Duration(milliseconds: 380));
            if (!mounted) return;
            NexusToast.show(
              context,
              'Complete your Dating settings to activate your orbit.',
              type: NexusToastType.error,
            );
            return;
          }
        }
        NexusToast.show(
          context,
          'Dating Profile is incomplete.',
          type: NexusToastType.error,
        );
      }
    } on Exception catch (e, st) {
      if (mounted) {
        setState(() {
          _isOrbitActive = oldActive;
        });
      }
      ErrorHandler.handleError(
        e,
        stackTrace: st,
        level: ErrorLevel.warning,
        customMessage: '[DatingTab] Orbit activation failed',
        showUi: false,
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Show dialog when core profile is incomplete (Light themed, matching app design)
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
                  'Please complete your core profile details first before setting up Dating features:',
                  style: TextStyle(color: Color(0xFF475569), fontSize: 14),
                ),
                const SizedBox(height: 16),
                ..._missingFields
                    .where(
                      (f) => !const {
                        'dating_target_buckets',
                        'dating_for',
                        'partner_values',
                      }.contains(f.toString()),
                    )
                    .map((field) {
                      final fieldStr = field.toString();
                      String label;
                      if (fieldStr == 'name') {
                        label = 'Display Name is missing';
                      } else if (fieldStr == 'age') {
                        label = 'Age is missing';
                      } else if (fieldStr == 'drinking') {
                        label = 'Drinking preferences are missing';
                      } else if (fieldStr == 'smoking') {
                        label = 'Smoking preferences are missing';
                      } else if (fieldStr == 'interests') {
                        label = 'At least 2 interests required';
                      } else if (fieldStr == 'profile_pic') {
                        label = 'Profile avatar image is missing';
                      } else if (fieldStr == 'normal_pics') {
                        label =
                            'At least 1 image required to be set in profile other than profile avatar';
                      } else if (fieldStr == 'bio') {
                        label = 'Bio is missing';
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
                  backgroundColor: AppColors.modeDating,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  final firstMissing = _missingFields.firstWhere(
                    (f) => !const {
                      'dating_target_buckets',
                      'dating_for',
                      'partner_values',
                    }.contains(f.toString()),
                    orElse: () => null,
                  );
                  widget.onNavigateToTab?.call(
                    2,
                    firstMissing?.toString(),
                  ); // Go to Profile Tab (index 2)
                },
                child: const Text('Go to Profile Tab'),
              ),
            ],
          );
        },
      ),
    );
  }

  // Show slide-up Dating Settings overlay
  Future<void> _showDatingSettingsOverlay({bool isActivating = false}) async {
    if (!mounted) return;
    final loadingNotifier = ValueNotifier<bool>(true);
    unawaited(
      _loadDatingProfileStatusSilent().then((_) {
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
              themeColor: AppColors.modeDating,
            );
          }
          return DatingSettingsOverlay(
            datingTargetBuckets: _datingTargetBuckets,
            datingFor: _datingFor,
            partnerValues: _partnerValues,
            childrenPlans: _childrenPlans,
            savingFields: _savingFields,
            onSaveDatingField: (field, value, setStateCallback) async {
              await _saveDatingField(field, value, setStateCallback);
            },
            onLoadDatingProfileStatusSilent: () async {
              await _loadDatingProfileStatusSilent();
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
  // standalone fetch - callers (LikesOverlay/MatchesOverlay's pull-to-
  // refresh, the optimistic-match-insert follow-up fetch) keep the same
  // Future<void> Function() shape they already expect.
  Future<void> _fetchLikes() async {
    await ref.read(discoveryHubControllerProvider('dating').notifier).refresh();
  }

  Future<void> _fetchMatches() async {
    await ref.read(discoveryHubControllerProvider('dating').notifier).refresh();
  }

  Future<bool> _recordMatchAction(
    String targetId,
    String action,
    String accessToken, {
    String? reason,
    String? reasonDetail,
  }) async {
    try {
      final config = AppConfig.current;
      final dio = _dio;
      final body = <String, dynamic>{
        'target_id': targetId,
        'action': action,
        'tab': 'Dating',
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
        customMessage: '[DatingTab] Error recording match action',
        showUi: false,
      );
      return false;
    }
  }

  Future<void> _markLikeSeen(String actorId) async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return;
    try {
      final config = AppConfig.current;
      final dio = _dio;
      await dio.post<void>(
        '${config.backendUrl}/api/v1/likes/mark-seen',
        data: {
          'actor_ids': [actorId],
          'tab': 'Dating',
        },
      );
    } on Exception catch (e, st) {
      ErrorHandler.handleError(
        e,
        stackTrace: st,
        level: ErrorLevel.warning,
        customMessage: '[DatingTab] Error marking like seen',
        showUi: false,
      );
    }
  }

  Future<Map<String, dynamic>> _fetchPeerProfile(
    String actorId,
    String accessToken,
  ) async {
    final config = AppConfig.current;
    final dio = _dio;
    final response = await dio.post<Map<String, dynamic>>(
      '${config.backendUrl}/api/v1/profile/peer',
      data: {'target_id': actorId, 'tab': 'Dating'},
    );
    if (response.statusCode == 200 && response.data != null) {
      return response.data!;
    }
    throw Exception('Failed to load peer profile');
  }

  Future<Map<String, dynamic>?> _recordLikeAction(
    String targetId,
    String action,
    String accessToken, {
    String? reason,
    String? reasonDetail,
  }) async {
    try {
      final config = AppConfig.current;
      final dio = _dio;
      final body = <String, dynamic>{
        'target_id': targetId,
        'action': action,
        'tab': 'Dating',
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
        customMessage: '[DatingTab] Error recording like action',
        showUi: false,
      );
      return null;
    }
  }

  Widget _buildLikeBackActionBar(
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
          ? await _recordLikeAction(actorId, action, session.accessToken)
          : null;
      onActioned(actorId);
      if (result?['matched'] == true) {
        final matchId = result?['match_id'] as String?;
        // Optimistic insert covers both "Send a message" and "Keep browsing" paths.
        if (mounted) {
          setState(() {
            _matches.insert(0, {
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
        // Refresh in background to pick up full profile data.
        unawaited(_fetchMatches());

        final goToChat = await rootNav.push<bool?>(
          MaterialPageRoute<bool?>(
            fullscreenDialog: true,
            builder: (_) => MatchScreen(
              matchedName: name,
              matchedProfilePic: matchedProfilePic,
            ),
          ),
        );
        if (goToChat == true && mounted) {
          Navigator.of(context).pop(); // close likes overlay
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
                icon: const Icon(LucideIcons.heart, size: 14),
                label: const Text(
                  'Like Back',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onLikeProfileLoaded(String actorId, void Function() onProfileLoaded) {
    final index = _likeItems.indexWhere((i) => i['actor_id'] == actorId);
    if (index != -1) {
      final likeEntry = _likeItems[index];
      final isUnseen = likeEntry['seen_at'] == null;
      if (isUnseen) {
        setState(() {
          likeEntry['seen_at'] = DateTime.now().toIso8601String();
          _unseenCount = _unseenCount > 0 ? _unseenCount - 1 : 0;
          _likeItems
            ..removeAt(index)
            ..add(likeEntry);
        });
        onProfileLoaded();
        unawaited(
          _markLikeSeen(actorId).then((_) {
            unawaited(
              ref
                  .read(discoveryHubControllerProvider('dating').notifier)
                  .refresh(),
            );
          }),
        );
      }
    }
  }

  Future<void> _showLikeProfile({
    required BuildContext ctx,
    required String actorId,
    required String name,
    required void Function(String actorId) onActioned,
    required void Function() onProfileLoaded,
  }) async {
    const themeColor = AppColors.modeDating;
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return;

    final likeEntry = _likeItems.firstWhere(
      (i) => i['actor_id'] == actorId,
      orElse: () => <String, dynamic>{},
    );
    final matchedProfilePic = likeEntry['profile_pic'] as String?;

    final profileFuture = _fetchPeerProfile(actorId, session.accessToken);
    final currentProfileFuture = profileFuture;


    await showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheetState) {
            return FutureBuilder<Map<String, dynamic>>(
              future: currentProfileFuture,
              builder: (sheetCtx, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Container(
                    height: MediaQuery.of(sheetCtx).size.height * 0.7,
                    decoration: const BoxDecoration(
                      color: Color(0xFF090D1A),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                    ),
                    child: const Center(
                      child: NexusOrbitLoader(),
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

                // Mark seen and re-sort only on successful load
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    _onLikeProfileLoaded(actorId, onProfileLoaded);
                  }
                });

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

                      actionBar: _buildLikeBackActionBar(

                    dsCtx,
                    actorId,
                    name,
                    themeColor,
                    matchedProfilePic,
                    onActioned,
                  ),
                  onHideTap: (c) async {
                    Navigator.pop(c);
                    await _recordLikeAction(
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
                      await _recordLikeAction(
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
                      await _recordLikeAction(
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
  },
);
}

  Future<void> _showLikesOverlay() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return LikesOverlay(
          likes: _likeItems,
          onFetchLikes: () async {
            await _fetchLikes();
          },
          onOpenLikesDetailsDialog: _showLikeProfile,
          onRecordMatchAction: (id, act, tok) async {
            await _recordMatchAction(id, act, tok);
          },
        );
      },
    );
  }

  void _showMatchesOverlay() {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetCtx) {
          return MatchesOverlay(
            matches: _matches,
            onFetchMatches: () async {
              await _fetchMatches();
            },
            onRecordMatchAction: (id, act, tok, {reason, reasonDetail}) async {
              await _recordMatchAction(
                id,
                act,
                tok,
                reason: reason,
                reasonDetail: reasonDetail,
              );
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const themeColor = AppColors.modeDating;
    final activeLikesCount = _unseenCount;

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
                  'Error loading dating profile:\n${_errorMsg ?? "Unknown error"}',
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
                    setState(() {
                      _hasError = false;
                      _errorMsg = null;
                    });
                    unawaited(_loadDatingProfileStatus());
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
        body: Center(child: NexusOrbitLoader(size: 96, lightMode: true)),
      );
    }

    return TabScaffold(
      title: 'Dating',
      themeColor: themeColor,
      chatLabel: 'Dating',
      isOrbitActive: _isOrbitActive,
      orbitDescription:
          'Start broadcasting your matching signals & begin viewing active profiles near your orbit.',
      onOpenOrbitPressed: () => _toggleOrbitState(true),
      onDeactivateOrbitPressed: () => _toggleOrbitState(false),
      onSettingsPressed: _showDatingSettingsOverlay,
      children: [
        Stack(
          children: [
            // Dimmable & Unfocusable Main Content
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
                            AppColors.modeDating,
                            Color(0xFF8B5CF6),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.modeDating.withAlpha(76),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: InkWell(
                        onTap: () {
                          widget.onOpenOrbit('Dating', AppColors.modeDating);
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
                                      'Open your Dating Orbit',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Discover connections beyond the swipe',
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
                                onTap: _showLikesOverlay,
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
                                          LucideIcons.heart,
                                          color: themeColor,
                                          size: 28,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      const Text(
                                        'Likes',
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
                                          '$activeLikesCount NEW',
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
                              onTap: _showMatchesOverlay,
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
                                        LucideIcons.heartHandshake,
                                        color: Colors.white,
                                        size: 28,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    const Text(
                                      'Matches',
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
                                        '${_matches.length} ACTIVE',
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

            // Inactive Orbit Blur Overlay
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
                          'Activate Dating Orbit above to unlock matches, chats, and find authentic connections.',
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
                          onPressed: _showDatingSettingsOverlay,
                          icon: const Icon(LucideIcons.settings, size: 16),
                          label: const Text(
                            'Dating Settings',
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
