import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/screens/chats/open_chat.dart';
import 'package:nexus/screens/home/tabs/professional/widgets/professional_activation_overlay.dart';
import 'package:nexus/screens/home/tabs/professional/widgets/professional_lists_overlays.dart';
import 'package:nexus/screens/home/tabs/professional/widgets/professional_settings_overlay.dart';
import 'package:nexus/screens/home/widgets/match_screen.dart';
import 'package:nexus/screens/home/widgets/profile_detail_sheet.dart';
import 'package:nexus/screens/home/widgets/settings_loading_skeleton.dart';
import 'package:nexus/screens/home/widgets/tab_scaffold.dart';
import 'package:nexus/utils/error_handler.dart';
import 'package:nexus/utils/network_utils.dart';
import 'package:nexus/utils/orbit_refresh_notifier.dart';
import 'package:nexus/widgets/aesthetic_loaders.dart';
import 'package:nexus/widgets/nexus_toast.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfessionalTab extends StatefulWidget {
  const ProfessionalTab({
    required this.onOpenOrbit,
    this.onNavigateToTab,
    super.key,
  });

  final void Function(String, Color) onOpenOrbit;
  final void Function(int)? onNavigateToTab;

  @override
  State<ProfessionalTab> createState() => _ProfessionalTabState();
}

class _ProfessionalTabState extends State<ProfessionalTab>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  StreamSubscription<bool>? _orbitSub;

  bool _isLoading = true;
  bool _isOrbitActive = false;

  List<String> _professionalTargetBuckets = [];
  List<String> _lookingFor = [];
  List<String> _techSkills = [];
  String _company = '';
  List<String> _roleType = [];
  final Set<String> _savingFields = {};

  List<dynamic> _missingFields = [];

  List<Map<String, dynamic>> _handshakeItems = [];
  int _unseenCount = 0;

  List<Map<String, dynamic>> _connections = [];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    unawaited(_pulseController.repeat(reverse: true));
    unawaited(_loadProfessionalProfileStatus());
    unawaited(_fetchHandshakes());
    unawaited(_fetchConnections());
    _orbitSub = OrbitRefreshNotifier.stream.listen((_) {
      unawaited(_loadProfessionalProfileStatusSilent());
    });
  }

  @override
  void dispose() {
    unawaited(_orbitSub?.cancel());
    _pulseController.dispose();
    super.dispose();
  }

  void _parseProfileData(Map<String, dynamic> data) {
    _isOrbitActive = data['is_professional_active'] == true;

    final rawBuckets = data['professional_target_buckets'];
    _professionalTargetBuckets = rawBuckets is List
        ? rawBuckets.map((e) => e.toString()).toList()
        : [];
    final rawLookingFor = data['looking_for'];
    _lookingFor = rawLookingFor is List
        ? rawLookingFor.map((e) => e.toString()).toList()
        : [];
    final rawTechSkills = data['tech_skills'];
    _techSkills = rawTechSkills is List
        ? rawTechSkills.map((e) => e.toString()).toList()
        : [];
    _company = data['role_at']?.toString() ?? '';
    final rawRoleType = data['role_type'];
    _roleType = rawRoleType is List
        ? rawRoleType.map((e) => e.toString()).toList()
        : [];
  }

  Future<void> _fetchProfile({bool showLoading = false}) async {
    if (showLoading) {
      setState(() => _isLoading = true);
    }
    try {
      final supabaseClient = Supabase.instance.client;
      final session = supabaseClient.auth.currentSession;
      if (session != null) {
        final config = AppConfig.current;
        final dio = createDio();

        final response = await dio.get<Map<String, dynamic>>(
          '${config.backendUrl}/api/v1/profile/details',
          options: Options(
            headers: {'Authorization': 'Bearer ${session.accessToken}'},
          ),
        );

        if (response.statusCode == 200 && response.data != null && mounted) {
          final data = response.data!;
          setState(() {
            _parseProfileData(data);
            if (showLoading) {
              _isLoading = false;
            }
          });
          return;
        }
      }
    } on Exception catch (e, st) {
      ErrorHandler.handleError(
        e,
        stackTrace: st,
        level: ErrorLevel.warning,
        customMessage: showLoading
            ? '[ProfessionalTab] Error fetching professional status'
            : '[ProfessionalTab] Error fetching professional status silently',
        showUi: false,
      );
    }

    if (showLoading && mounted) {
      setState(() {
        if (_professionalTargetBuckets.isEmpty) {
          _professionalTargetBuckets = ['M', 'F', 'NB'];
        }
        _isOrbitActive = false;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadProfessionalProfileStatus() async {
    await _fetchProfile(showLoading: true);
  }

  Future<void> _loadProfessionalProfileStatusSilent() async {
    await _fetchProfile();
  }

  Future<bool> _saveProfessionalProfileDetails(
    Map<String, dynamic> payload,
  ) async {
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        final config = AppConfig.current;
        final dio = createDio();
        final response = await dio.patch<Map<String, dynamic>>(
          '${config.backendUrl}/api/v1/profile/details',
          data: payload,
          options: Options(
            headers: {'Authorization': 'Bearer ${session.accessToken}'},
          ),
        );
        return response.statusCode == 200;
      }
    } on Exception catch (e, st) {
      ErrorHandler.handleError(
        e,
        stackTrace: st,
        level: ErrorLevel.warning,
        customMessage: '[ProfessionalTab] Error saving professional details',
        showUi: false,
      );
    }
    return false;
  }

  Future<void> _saveProfessionalField(
    String field,
    dynamic value,
    StateSetter setModalState,
  ) async {
    setModalState(() => _savingFields.add(field));
    final success = await _saveProfessionalProfileDetails({field: value});
    if (mounted) {
      setModalState(() {
        _savingFields.remove(field);
        if (success) {
          if (field == 'professional_target_buckets') {
            _professionalTargetBuckets = List<String>.from(value as List);
          } else if (field == 'looking_for') {
            _lookingFor = List<String>.from(value as List);
          } else if (field == 'tech_skills') {
            _techSkills = List<String>.from(value as List);
          } else if (field == 'role_at') {
            _company = value as String;
          } else if (field == 'role_type') {
            _roleType = List<String>.from(value as List);
          }
        }
      });
      await _loadProfessionalProfileStatus();
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
          data: {'is_professional_active': active},
          options: Options(
            headers: {'Authorization': 'Bearer ${session.accessToken}'},
          ),
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
                    ProfessionalActivationOverlay(
                      onFinished: () => Navigator.pop(context),
                    ),
                transitionsBuilder:
                    (context, animation, secondaryAnimation, child) =>
                        FadeTransition(opacity: animation, child: child),
              ),
            );
          } else {
            NexusToast.show(context, 'Professional Orbit Deactivated.');
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
            unawaited(_showProfessionalSettingsOverlay(isActivating: true));
            await Future<void>.delayed(const Duration(milliseconds: 380));
            if (!mounted) return;
            NexusToast.show(
              context,
              'Complete your Professional settings to activate your orbit.',
              type: NexusToastType.error,
            );
            return;
          }
        }
        NexusToast.show(
          context,
          'Professional Profile is incomplete.',
          type: NexusToastType.error,
        );
      }
    } on Exception catch (e, st) {
      ErrorHandler.handleError(
        e,
        stackTrace: st,
        level: ErrorLevel.warning,
        customMessage: '[ProfessionalTab] Orbit activation failed',
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
                'Please complete your core profile before setting up Professional features:',
                style: TextStyle(color: Color(0xFF475569), fontSize: 14),
              ),
              const SizedBox(height: 16),
              ..._missingFields
                  .where(
                    (f) => !const {
                      'professional_target_buckets',
                      'looking_for',
                      'tech_skills',
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
                backgroundColor: const Color(0xFF00F5D4),
                foregroundColor: Colors.black87,
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
    ));
  }

  Future<void> _showProfessionalSettingsOverlay({bool isActivating = false}) async {
    if (!mounted) return;
    final loadingNotifier = ValueNotifier<bool>(true);
    unawaited(
      _loadProfessionalProfileStatusSilent().then((_) {
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
            return const SettingsLoadingSkeleton(themeColor: Color(0xFF00C4AB));
          }
          return ProfessionalSettingsOverlay(
            professionalTargetBuckets: _professionalTargetBuckets,
            lookingFor: _lookingFor,
            techSkills: _techSkills,
            company: _company,
            roleType: _roleType,
            savingFields: _savingFields,
            onSaveProfessionalField: (field, value, setStateCallback) async {
              await _saveProfessionalField(field, value, setStateCallback);
            },
            onLoadProfessionalProfileStatusSilent: () async {
              await _loadProfessionalProfileStatusSilent();
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

  Future<void> _fetchHandshakes() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return;
    try {
      final config = AppConfig.current;
      final dio = createDio();
      final response = await dio.get<Map<String, dynamic>>(
        '${config.backendUrl}/api/v1/likes',
        queryParameters: {'tab': 'Professional'},
        options: Options(
          headers: {'Authorization': 'Bearer ${session.accessToken}'},
        ),
      );
      if (response.statusCode == 200 && response.data != null && mounted) {
        final data = response.data!;
        final likes = data['likes'];
        final unseen = data['unseen_count'];
        setState(() {
          _handshakeItems = likes is List
              ? List<Map<String, dynamic>>.from(
                  likes.cast<Map<String, dynamic>>(),
                )
              : [];
          _unseenCount = (unseen as num?)?.toInt() ?? 0;
        });
      }
    } on Exception catch (e, st) {
      ErrorHandler.handleError(
        e,
        stackTrace: st,
        level: ErrorLevel.warning,
        customMessage: '[ProfessionalTab] Error fetching handshakes',
        showUi: false,
      );
    }
  }

  Future<void> _fetchConnections() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return;
    try {
      final config = AppConfig.current;
      final dio = createDio();
      final response = await dio.get<Map<String, dynamic>>(
        '${config.backendUrl}/api/v1/matches',
        queryParameters: {'tab': 'Professional'},
        options: Options(
          headers: {'Authorization': 'Bearer ${session.accessToken}'},
        ),
      );
      if (response.statusCode == 200 && response.data != null && mounted) {
        final raw = response.data!['matches'];
        final list = raw is List
            ? raw.cast<Map<String, dynamic>>()
            : <Map<String, dynamic>>[];
        final newIds = _connections
            .where((m) => m['is_new'] == true)
            .map((m) => m['matched_user_id'] as String?)
            .whereType<String>()
            .toSet();
        setState(() {
          _connections = list.map((m) {
            final uid = m['matched_user_id'] as String?;
            return (uid != null && newIds.contains(uid))
                ? {...m, 'is_new': true}
                : m;
          }).toList();
        });
      }
    } on Exception catch (e, st) {
      ErrorHandler.handleError(
        e,
        stackTrace: st,
        level: ErrorLevel.warning,
        customMessage: '[ProfessionalTab] Error fetching connections',
        showUi: false,
      );
    }
  }

  Future<bool> _recordConnectionAction(
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
        'tab': 'Professional',
      };
      if (reason != null) body['reason'] = reason;
      if (reasonDetail != null) body['reason_detail'] = reasonDetail;
      final response = await dio.post<void>(
        '${config.backendUrl}/api/v1/matches/action',
        data: body,
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      return response.statusCode == 200;
    } on Exception catch (e, st) {
      ErrorHandler.handleError(
        e,
        stackTrace: st,
        level: ErrorLevel.warning,
        customMessage: '[ProfessionalTab] Error recording connection action',
        showUi: false,
      );
      return false;
    }
  }

  Future<void> _markAllHandshakesSeen() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return;
    try {
      final config = AppConfig.current;
      final dio = createDio();
      await dio.post<void>(
        '${config.backendUrl}/api/v1/likes/mark-seen',
        data: {'mark_all': true},
        options: Options(
          headers: {'Authorization': 'Bearer ${session.accessToken}'},
        ),
      );
    } on Exception catch (e, st) {
      ErrorHandler.handleError(
        e,
        stackTrace: st,
        level: ErrorLevel.warning,
        customMessage: '[ProfessionalTab] Error marking handshakes seen',
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
      data: {'target_id': actorId, 'tab': 'Professional'},
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
    if (response.statusCode == 200 && response.data != null) {
      return response.data!;
    }
    throw Exception('Failed to load peer profile');
  }

  Future<Map<String, dynamic>?> _recordHandshakeAction(
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
        'tab': 'Professional',
      };
      if (reason != null) body['reason'] = reason;
      if (reasonDetail != null) body['reason_detail'] = reasonDetail;
      final response = await dio.post<Map<String, dynamic>>(
        '${config.backendUrl}/api/v1/likes/action',
        data: body,
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      if (response.statusCode == 200) return response.data;
      return null;
    } on Exception catch (e, st) {
      ErrorHandler.handleError(
        e,
        stackTrace: st,
        level: ErrorLevel.warning,
        customMessage: '[ProfessionalTab] Error recording handshake action',
        showUi: false,
      );
      return null;
    }
  }

  Widget _buildConnectBackActionBar(
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
          ? await _recordHandshakeAction(actorId, action, session.accessToken)
          : null;
      onActioned(actorId);
      if (result?['matched'] == true) {
        final matchId = result?['match_id'] as String?;
        if (mounted) {
          setState(() {
            _connections.insert(0, {
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
        unawaited(_fetchConnections());

        final goToConnections = await rootNav.push<bool?>(
          MaterialPageRoute<bool?>(
            fullscreenDialog: true,
            builder: (_) => MatchScreen(
              matchedName: name,
              matchedProfilePic: matchedProfilePic,
              titleText: 'Connected! 🤝',
              subtitleText:
                  'You and $name are now connected.\nTime to build something great together!',
              themeColor: theme,
              badgeIcon: LucideIcons.handshake,
            ),
          ),
        );
        if (goToConnections == true && mounted) {
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
                  colors: [Color(0xFFF59E0B), Color(0xFFEF4444)],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
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
                  'Super Connect',
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
                icon: const Icon(LucideIcons.handshake, size: 14),
                label: const Text(
                  'Connect Back',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showHandshakeProfile({
    required BuildContext ctx,
    required String actorId,
    required String name,
    required void Function(String actorId) onActioned,
  }) async {
    const themeColor = Color(0xFF00C4AB);
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return;

    final handshakeEntry = _handshakeItems.firstWhere(
      (i) => i['actor_id'] == actorId,
      orElse: () => <String, dynamic>{},
    );
    final matchedProfilePic = handshakeEntry['profile_pic'] as String?;

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
                  actionBar: _buildConnectBackActionBar(
                    dsCtx,
                    actorId,
                    name,
                    themeColor,
                    matchedProfilePic,
                    onActioned,
                  ),
                  onHideTap: (c) async {
                    Navigator.pop(c);
                    await _recordHandshakeAction(
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
                      await _recordHandshakeAction(
                        actorId,
                        'block',
                        session.accessToken,
                      );
                      onActioned(actorId);
                    }
                  },
                  onReportTap: (c) => showProfileReportDialog(
                    c,
                    onConfirmed: (reason, detail) async {
                      Navigator.pop(c);
                      await _recordHandshakeAction(
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

  Future<void> _showHandshakesOverlay() async {
    setState(() => _unseenCount = 0);
    unawaited(_markAllHandshakesSeen());
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return HandshakesOverlay(
          handshakes: _handshakeItems,
          onFetchHandshakes: () async {
            await _fetchHandshakes();
          },
          onShowHandshakeProfile: _showHandshakeProfile,
        );
      },
    );
  }

  void _showConnectionsOverlay() {
    unawaited(showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return ConnectionsOverlay(
          connections: _connections,
          onFetchConnections: () async {
            await _fetchConnections();
          },
          onRecordConnectionAction: _recordConnectionAction,
        );
      },
    ));
  }

  @override
  Widget build(BuildContext context) {
    const themeColor = Color(0xFF00F5D4);
    final activeHandshakesCount = _unseenCount;

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: NexusOrbitLoader(size: 64, lightMode: true)),
      );
    }

    return TabScaffold(
      title: 'Professional',
      themeColor: themeColor,
      chatLabel: 'Professional',
      isOrbitActive: _isOrbitActive,
      orbitDescription:
          'Start broadcasting your professional signals & begin connecting with people in your orbit.',
      onOpenOrbitPressed: () => _toggleOrbitState(true),
      onDeactivateOrbitPressed: () => _toggleOrbitState(false),
      onSettingsPressed: _showProfessionalSettingsOverlay,
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
                            Color(0xFF00F5D4),
                            Color(0xFF0EA5E9),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00F5D4).withAlpha(76),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: InkWell(
                        onTap: () {
                          widget.onOpenOrbit(
                            'Professional',
                            const Color(0xFF00F5D4),
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
                                      'Open your Pro Orbit',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Discover talent and opportunities near you',
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
                                onTap: _showHandshakesOverlay,
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
                                          LucideIcons.handshake,
                                          color: themeColor,
                                          size: 28,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      const Text(
                                        'Handshakes',
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
                                          '$activeHandshakesCount NEW',
                                          style: const TextStyle(
                                            color: Colors.black87,
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
                              onTap: _showConnectionsOverlay,
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
                                        LucideIcons.network,
                                        color: Colors.white,
                                        size: 28,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    const Text(
                                      'Connections',
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
                                        '${_connections.length} ACTIVE',
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
                          'Activate Professional Orbit to discover talent, send handshakes, and grow your network.',
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
                          onPressed: _showProfessionalSettingsOverlay,
                          icon: const Icon(LucideIcons.settings, size: 16),
                          label: const Text(
                            'Professional Settings',
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
