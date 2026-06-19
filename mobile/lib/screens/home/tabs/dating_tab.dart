import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/screens/home/tabs/profile/widgets/storage_image.dart';
import 'package:nexus/screens/home/widgets/match_screen.dart';
import 'package:nexus/screens/home/widgets/profile_detail_sheet.dart';
import 'package:nexus/screens/home/widgets/tab_scaffold.dart';
import 'package:nexus/utils/network_utils.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DatingTab extends StatefulWidget {
  const DatingTab({
    required this.onOpenOrbit,
    this.onNavigateToTab,
    super.key,
  });

  final void Function(String, Color) onOpenOrbit;
  final void Function(int)? onNavigateToTab;

  @override
  State<DatingTab> createState() => _DatingTabState();
}

class _DatingTabState extends State<DatingTab>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  // State variables for Orbit activation & profile details
  bool _isLoading = true;
  bool _isOrbitActive = false;

  // Profile fields loaded from server (for settings form)
  List<String> _datingTargetBuckets = [];
  List<String> _datingFor = [];
  String _partnerValues = '';
  final Set<String> _savingFields = {};

  // Local state for checking off missing fields dialog
  List<dynamic> _missingFields = [];

  // Likes inbox — populated from GET /api/v1/likes
  List<Map<String, dynamic>> _likeItems = [];
  int _unseenCount = 0;

  // Matches — populated from GET /api/v1/matches
  List<Map<String, dynamic>> _matches = [];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    unawaited(_pulseController.repeat(reverse: true));
    unawaited(_loadDatingProfileStatus());
    unawaited(_fetchLikes());
    unawaited(_fetchMatches());
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  // Load current profile details from secure endpoint
  Future<void> _loadDatingProfileStatus() async {
    setState(() => _isLoading = true);
    try {
      final supabaseClient = Supabase.instance.client;
      final session = supabaseClient.auth.currentSession;
      if (session != null) {
        final config = AppConfig.current;
        final dio = createDio();
        // 3-second quick timeout to prevent hanging on slow/inactive local server
        dio.options.connectTimeout = const Duration(seconds: 3);
        dio.options.receiveTimeout = const Duration(seconds: 3);

        final response = await dio.get<Map<String, dynamic>>(
          '${config.backendUrl}/api/v1/profile/details',
          options: Options(
            headers: {'Authorization': 'Bearer ${session.accessToken}'},
          ),
        );

        if (response.statusCode == 200 && response.data != null && mounted) {
          final data = response.data!;
          setState(() {
            _isOrbitActive = data['is_dating_active'] == true;

            final rawBuckets = data['dating_target_buckets'];
            _datingTargetBuckets = rawBuckets is List
                ? rawBuckets.map((e) => e.toString()).toList()
                : [];
            final rawDatingFor = data['dating_for'];
            _datingFor = rawDatingFor is List
                ? rawDatingFor.map((e) => e.toString()).toList()
                : [];
            _partnerValues = data['partner_values']?.toString() ?? '';

            _isLoading = false;
          });
          return;
        }
      }
    } on Exception catch (e) {
      debugPrint(
        '[DatingTab] Error fetching dating status, using fallback: $e',
      );
    }

    if (mounted) {
      setState(() {
        if (_datingTargetBuckets.isEmpty) {
          _datingTargetBuckets = ['M', 'F'];
        }
        if (_datingFor.isEmpty) {
          _datingFor = ['short', 'long'];
        }
        if (_partnerValues.isEmpty) {
          _partnerValues = 'Deep trust, open communication, and shared growth.';
        }
        _isOrbitActive = false;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadDatingProfileStatusSilent() async {
    try {
      final supabaseClient = Supabase.instance.client;
      final session = supabaseClient.auth.currentSession;
      if (session != null) {
        final config = AppConfig.current;
        final dio = createDio();
        dio.options.connectTimeout = const Duration(seconds: 3);
        dio.options.receiveTimeout = const Duration(seconds: 3);

        final response = await dio.get<Map<String, dynamic>>(
          '${config.backendUrl}/api/v1/profile/details',
          options: Options(
            headers: {'Authorization': 'Bearer ${session.accessToken}'},
          ),
        );

        if (response.statusCode == 200 && response.data != null && mounted) {
          final data = response.data!;
          setState(() {
            _isOrbitActive = data['is_dating_active'] == true;

            final rawBuckets = data['dating_target_buckets'];
            _datingTargetBuckets = rawBuckets is List
                ? rawBuckets.map((e) => e.toString()).toList()
                : [];
            final rawDatingFor = data['dating_for'];
            _datingFor = rawDatingFor is List
                ? rawDatingFor.map((e) => e.toString()).toList()
                : [];
            _partnerValues = data['partner_values']?.toString() ?? '';
          });
        }
      }
    } on Exception catch (e) {
      debugPrint('[DatingTab] Error fetching dating status silently: $e');
    }
  }

  // Save profile updates to the details endpoint
  Future<bool> _saveDatingProfileDetails(Map<String, dynamic> payload) async {
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
    } on Exception catch (e) {
      debugPrint('[DatingTab] Error saving dating details: $e');
    }
    return false;
  }

  // Real-time save helper for individual settings fields
  Future<void> _saveDatingField(
    String field,
    dynamic value,
    StateSetter setModalState,
  ) async {
    setModalState(() {
      _savingFields.add(field);
    });
    final success = await _saveDatingProfileDetails({
      field: value,
    });
    if (mounted) {
      setModalState(() {
        _savingFields.remove(field);
        if (success) {
          if (field == 'dating_target_buckets') {
            _datingTargetBuckets = List<String>.from(value as List);
          } else if (field == 'dating_for') {
            _datingFor = List<String>.from(value as List);
          } else if (field == 'partner_values') {
            _partnerValues = value as String;
          }
        }
      });
      // Synchronize states
      await _loadDatingProfileStatus();
    }
  }

  // Toggle Orbit activation state (patching is_dating_active)
  Future<void> _toggleOrbitState(bool active) async {
    setState(() => _isLoading = true);
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        final config = AppConfig.current;
        final dio = createDio();
        final response = await dio.patch<Map<String, dynamic>>(
          '${config.backendUrl}/api/v1/profile/details',
          data: {'is_dating_active': active},
          options: Options(
            headers: {'Authorization': 'Bearer ${session.accessToken}'},
          ),
        );

        if (response.statusCode == 200 && mounted) {
          setState(() {
            _isOrbitActive = active;
          });
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
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                behavior: SnackBarBehavior.floating,
                backgroundColor: Color(0xFF1E293B),
                content: Text('Dating Orbit Deactivated.'),
              ),
            );
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

            // Separate profile fields from dating-only fields
            final profileFields = [
              'name',
              'age',
              'drinking',
              'smoking',
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
            unawaited(_showDatingSettingsOverlay(isActivating: true));
            await Future<void>.delayed(const Duration(milliseconds: 380));
            if (!mounted) return;
            _showFloatingToast(
              'Complete your Dating settings to activate your orbit.',
              const Color(0xFFFF4F81),
            );
            return;
          }
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.redAccent,
            content: Text('Dating Profile is incomplete.'),
          ),
        );
      }
    } on Exception catch (e) {
      debugPrint('[DatingTab] Orbit activation failed: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Show dialog when core profile is incomplete (Light themed, matching app design)
  void _showProfileIncompleteDialog() {
    unawaited(showDialog<void>(
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
                      label = 'At least 3 interests required';
                    } else if (fieldStr == 'profile_pic') {
                      label = 'Profile avatar image is missing';
                    } else if (fieldStr == 'normal_pics') {
                      label =
                          'At least 2 images required to be set in profile other than profile avatar';
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
                backgroundColor: const Color(0xFFFF4F81),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                Navigator.pop(context);
                widget.onNavigateToTab?.call(2); // Go to Profile Tab (index 2)
              },
              child: const Text('Go to Profile Tab'),
            ),
          ],
        );
      },
    ));
  }

  void _showFloatingToast(String message, Color color) {
    final overlay = Navigator.of(context).overlay;
    if (overlay == null) return;
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => Positioned(
        top: MediaQuery.of(ctx).padding.top + 12,
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.45),
                  blurRadius: 18,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.info, color: Colors.white, size: 17),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    unawaited(
      Future<void>.delayed(const Duration(seconds: 3)).then((_) {
        if (entry.mounted) entry.remove();
      }),
    );
  }

  // Show slide-up Dating Settings overlay
  Future<void> _showDatingSettingsOverlay({bool isActivating = false}) async {
    await _loadDatingProfileStatusSilent();
    final localBuckets = List<String>.from(_datingTargetBuckets);
    final localDatingFor = List<String>.from(_datingFor);
    final localPartnerValues = _partnerValues.isNotEmpty
        ? _partnerValues
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList()
        : <String>[];
    var searchQuery = '';

    final predefinedValues = <String>[
      'Authenticity',
      'Empathy',
      'Ambition',
      'Humility',
      'Kindness',
      'Growth Mindset',
      'Loyalty',
      'Honesty',
      'Creativity',
      'Emotional Maturity',
      'Humor & Wit',
      'Respect',
      'Independence',
      'Curiosity',
      'Communication',
      'Adventure',
      'Financial Stability',
      'Compassion',
      'Family-oriented',
      'Generosity',
      'Open-mindedness',
      'Patience',
      'Self-awareness',
      'Trustworthiness',
      'Spirituality',
      'Optimism',
      'Mindfulness',
      'Intellectual Depth',
      'Fitness-minded',
      'Playfulness',
      'Sincerity',
      'Tolerance',
      'Forgiveness',
      'Resilience',
      'Responsibility',
      'Warmth',
    ];

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filteredValues = predefinedValues
                .where(
                  (val) =>
                      val.toLowerCase().contains(searchQuery.toLowerCase()),
                )
                .where((val) => !localPartnerValues.contains(val))
                .toList();

            final showCustomOption =
                searchQuery.trim().isNotEmpty &&
                !predefinedValues.any(
                  (val) =>
                      val.toLowerCase() == searchQuery.trim().toLowerCase(),
                ) &&
                !localPartnerValues.any(
                  (val) =>
                      val.toLowerCase() == searchQuery.trim().toLowerCase(),
                );

            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              LucideIcons.settings,
                              color: Color(0xFFFF4F81),
                              size: 24,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Dating Settings',
                              style: TextStyle(
                                color: Color(0xFF0F172A),
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF4F81),
                            foregroundColor: Colors.white,
                            elevation: 4,
                            shadowColor: const Color(
                              0xFFFF4F81,
                            ).withValues(alpha: 0.4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () async {
                            Navigator.pop(context);
                            if (isActivating) {
                              await _toggleOrbitState(true);
                            }
                          },
                          child: Text(
                            isActivating ? 'Turn On Orbit' : 'Done',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Form Fields
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      children: [
                        // Target Buckets (Seeking Gender)
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Who are you interested in meeting?',
                                style: TextStyle(
                                  color: Color(0xFF0F172A),
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (_savingFields.contains('dating_target_buckets'))
                              const Padding(
                                padding: EdgeInsets.only(left: 8),
                                child: SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Color(0xFFFF4F81),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Select the gender identities you would like to see in your Orbit.',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          children:
                              [
                                {'code': 'M', 'label': 'Men'},
                                {'code': 'F', 'label': 'Women'},
                                {'code': 'NB', 'label': 'Non-binary'},
                                {'code': 'Open', 'label': 'Open to all'},
                              ].map((item) {
                                final code = item['code']!;
                                final isSelected = localBuckets.contains(code);
                                return FilterChip(
                                  label: Text(item['label']!),
                                  selected: isSelected,
                                  selectedColor: const Color(0xFFFF4F81),
                                  backgroundColor: Colors.black.withValues(
                                    alpha: 0.04,
                                  ),
                                  checkmarkColor: Colors.white,
                                  labelStyle: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : const Color(0xFF0F172A),
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  onSelected: (selected) async {
                                    if (_savingFields.contains(
                                      'dating_target_buckets',
                                    )) {
                                      return;
                                    }
                                    setModalState(() {
                                      if (code == 'Open') {
                                        if (selected) {
                                          localBuckets
                                            ..clear()
                                            ..add('Open');
                                        } else {
                                          localBuckets.remove('Open');
                                        }
                                      } else {
                                        if (selected) {
                                          localBuckets
                                            ..remove('Open')
                                            ..add(code);
                                        } else {
                                          localBuckets.remove(code);
                                        }
                                      }
                                    });
                                    await _saveDatingField(
                                      'dating_target_buckets',
                                      localBuckets,
                                      setModalState,
                                    );
                                  },
                                );
                              }).toList(),
                        ),
                        const SizedBox(height: 32),

                        // Dating For (Relationship Goals)
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'What are you looking for?',
                                style: TextStyle(
                                  color: Color(0xFF0F172A),
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (_savingFields.contains('dating_for'))
                              const Padding(
                                padding: EdgeInsets.only(left: 8),
                                child: SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Color(0xFFFF4F81),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Select the relationship types you are open to.',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children:
                              [
                                {'code': 'short', 'label': 'Short-term'},
                                {'code': 'long', 'label': 'Long-term'},
                                {'code': 'casual', 'label': 'Casual Dating'},
                                {'code': 'fling', 'label': 'Fling'},
                                {'code': 'hookups', 'label': 'Hookups'},
                                {
                                  'code': 'fwb',
                                  'label': 'Friends with Benefits',
                                },
                                {'code': 'monogamous', 'label': 'Monogamous'},
                                {'code': 'polyamorous', 'label': 'Polyamorous'},
                                {
                                  'code': 'open_rel',
                                  'label': 'Open Relationship',
                                },
                                {
                                  'code': 'marriage',
                                  'label': 'Marriage / Life Partner',
                                },
                                {
                                  'code': 'platonic',
                                  'label': 'Platonic Dating',
                                },
                                {'code': 'unsure', 'label': 'Figuring it out'},
                              ].map((item) {
                                final code = item['code']!;
                                final isSelected = localDatingFor.contains(
                                  code,
                                );
                                return FilterChip(
                                  label: Text(item['label']!),
                                  selected: isSelected,
                                  selectedColor: const Color(0xFFFF4F81),
                                  backgroundColor: Colors.black.withValues(
                                    alpha: 0.04,
                                  ),
                                  checkmarkColor: Colors.white,
                                  labelStyle: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : const Color(0xFF0F172A),
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  onSelected: (selected) async {
                                    if (_savingFields.contains('dating_for')) {
                                      return;
                                    }
                                    setModalState(() {
                                      if (selected) {
                                        localDatingFor.add(code);
                                      } else {
                                        localDatingFor.remove(code);
                                      }
                                    });
                                    await _saveDatingField(
                                      'dating_for',
                                      localDatingFor,
                                      setModalState,
                                    );
                                  },
                                );
                              }).toList(),
                        ),
                        const SizedBox(height: 32),

                        // Partner Values Input Header
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'What core values are most important to you in a partner?',
                                style: TextStyle(
                                  color: Color(0xFF0F172A),
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (_savingFields.contains('partner_values'))
                              const Padding(
                                padding: EdgeInsets.only(left: 8),
                                child: SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Color(0xFFFF4F81),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Choose the qualities and shared principles you value most.',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Selected Partner Values Chips
                        if (localPartnerValues.isNotEmpty) ...[
                          const Text(
                            'Your Selected Values:',
                            style: TextStyle(
                              color: Color(0xFF475569),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: localPartnerValues.map((val) {
                              return Chip(
                                label: Text(val),
                                backgroundColor: const Color(
                                  0xFFFF4F81,
                                ).withValues(alpha: 0.1),
                                labelStyle: const TextStyle(
                                  color: Color(0xFFFF4F81),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                                deleteIcon: const Icon(
                                  LucideIcons.x,
                                  size: 14,
                                  color: Color(0xFFFF4F81),
                                ),
                                side: BorderSide.none,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                onDeleted: () async {
                                  if (_savingFields.contains(
                                    'partner_values',
                                  )) {
                                    return;
                                  }
                                  setModalState(() {
                                    localPartnerValues.remove(val);
                                  });
                                  await _saveDatingField(
                                    'partner_values',
                                    localPartnerValues.join(', '),
                                    setModalState,
                                  );
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Search Bar
                        TextField(
                          style: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 14,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Search or add core values...',
                            prefixIcon: const Icon(
                              LucideIcons.search,
                              size: 18,
                              color: Colors.grey,
                            ),
                            filled: true,
                            fillColor: Colors.black.withValues(alpha: 0.04),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.all(16),
                          ),
                          onChanged: (val) {
                            setModalState(() {
                              searchQuery = val;
                            });
                          },
                        ),
                        const SizedBox(height: 16),

                        // Predefined / Filtered Choices
                        const Text(
                          'Tap to select values:',
                          style: TextStyle(
                            color: Color(0xFF475569),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            if (showCustomOption)
                              ActionChip(
                                avatar: const Icon(
                                  LucideIcons.plus,
                                  size: 14,
                                  color: Colors.white,
                                ),
                                label: Text('Add "${searchQuery.trim()}"'),
                                backgroundColor: const Color(0xFFFF4F81),
                                labelStyle: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                onPressed: () async {
                                  if (_savingFields.contains(
                                    'partner_values',
                                  )) {
                                    return;
                                  }
                                  setModalState(() {
                                    localPartnerValues.add(searchQuery.trim());
                                    searchQuery = '';
                                  });
                                  await _saveDatingField(
                                    'partner_values',
                                    localPartnerValues.join(', '),
                                    setModalState,
                                  );
                                },
                              ),
                            ...filteredValues.map((val) {
                              return ActionChip(
                                label: Text(val),
                                backgroundColor: Colors.black.withValues(
                                  alpha: 0.04,
                                ),
                                labelStyle: const TextStyle(
                                  color: Color(0xFF0F172A),
                                  fontSize: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                side: BorderSide.none,
                                onPressed: () async {
                                  if (_savingFields.contains(
                                    'partner_values',
                                  )) {
                                    return;
                                  }
                                  setModalState(() {
                                    localPartnerValues.add(val);
                                  });
                                  await _saveDatingField(
                                    'partner_values',
                                    localPartnerValues.join(', '),
                                    setModalState,
                                  );
                                },
                              );
                            }),
                          ],
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _fetchLikes() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return;
    try {
      final config = AppConfig.current;
      final dio = createDio();
      final response = await dio.get<Map<String, dynamic>>(
        '${config.backendUrl}/api/v1/likes',
        queryParameters: {'tab': 'Dating'},
        options: Options(
          headers: {'Authorization': 'Bearer ${session.accessToken}'},
        ),
      );
      if (response.statusCode == 200 && response.data != null && mounted) {
        final data = response.data!;
        final likes = data['likes'];
        final unseen = data['unseen_count'];
        setState(() {
          _likeItems = likes is List
              ? List<Map<String, dynamic>>.from(
                  likes.cast<Map<String, dynamic>>(),
                )
              : [];
          _unseenCount = (unseen as num?)?.toInt() ?? 0;
        });
      }
    } on Exception catch (e) {
      debugPrint('[DatingTab] Error fetching likes: $e');
    }
  }

  Future<void> _fetchMatches() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return;
    try {
      final config = AppConfig.current;
      final dio = createDio();
      final response = await dio.get<Map<String, dynamic>>(
        '${config.backendUrl}/api/v1/matches',
        options: Options(
          headers: {'Authorization': 'Bearer ${session.accessToken}'},
        ),
      );
      if (response.statusCode == 200 && response.data != null && mounted) {
        final raw = response.data!['matches'];
        final list = raw is List
            ? raw.cast<Map<String, dynamic>>()
            : <Map<String, dynamic>>[];
        // Preserve is_new flags set by optimistic inserts this session
        final newIds = _matches
            .where((m) => m['is_new'] == true)
            .map((m) => m['matched_user_id'] as String?)
            .whereType<String>()
            .toSet();
        setState(() {
          _matches = list.map((m) {
            final uid = m['matched_user_id'] as String?;
            return (uid != null && newIds.contains(uid))
                ? {...m, 'is_new': true}
                : m;
          }).toList();
        });
      }
    } on Exception catch (e) {
      debugPrint('[DatingTab] Error fetching matches: $e');
    }
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
      final dio = createDio();
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
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      return response.statusCode == 200;
    } on Exception catch (e) {
      debugPrint('[DatingTab] Error recording match action: $e');
      return false;
    }
  }

  Future<void> _markAllLikesSeen() async {
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
    } on Exception catch (e) {
      debugPrint('[DatingTab] Error marking likes seen: $e');
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
      data: {'target_id': actorId, 'tab': 'Dating'},
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
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
      final dio = createDio();
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
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      if (response.statusCode == 200) return response.data;
      return null;
    } on Exception catch (e) {
      debugPrint('[DatingTab] Error recording like action: $e');
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
        // Optimistic insert covers both "Send a message" and "Keep browsing" paths.
        if (mounted) {
          setState(() {
            _matches.insert(0, {
              'match_id': null,
              'matched_user_id': actorId,
              'name': name,
              'age': null,
              'profile_pic': matchedProfilePic,
              'matched_at': DateTime.now().toIso8601String(),
              'is_new': true,
            });
          });
        }
        // Refresh in background to get real match_id and full profile data.
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
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _showMatchesOverlay();
          });
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
                  'Super Back',
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

  Future<void> _showLikeProfile({
    required BuildContext ctx,
    required String actorId,
    required String name,
    required void Function(String actorId) onActioned,
  }) async {
    const themeColor = Color(0xFFFF4F81);
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return;

    final likeEntry = _likeItems.firstWhere(
      (i) => i['actor_id'] == actorId,
      orElse: () => <String, dynamic>{},
    );
    final matchedProfilePic = likeEntry['profile_pic'] as String?;

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
                  child: CircularProgressIndicator(color: themeColor),
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
  }

  Future<void> _showLikesOverlay() async {
    const themeColor = Color(0xFFFF4F81);

    setState(() => _unseenCount = 0);
    unawaited(_markAllLikesSeen());

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Container(
              height: MediaQuery.of(ctx).size.height * 0.75,
              decoration: const BoxDecoration(
                color: Color(0xFF0F172A),
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(50),
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              LucideIcons.heart,
                              color: Color(0xFFFF4F81),
                              size: 24,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Likes',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF4F81).withAlpha(38),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${_likeItems.length} likes',
                            style: const TextStyle(
                              color: Color(0xFFFF4F81),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: _likeItems.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  LucideIcons.sparkles,
                                  color: Colors.white.withAlpha(50),
                                  size: 48,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No likes yet',
                                  style: TextStyle(
                                    color: Colors.white.withAlpha(150),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  mainAxisSpacing: 16,
                                  crossAxisSpacing: 16,
                                  childAspectRatio: 0.82,
                                ),
                            itemCount: _likeItems.length,
                            itemBuilder: (ctx, index) {
                              final item = _likeItems[index];
                              final actorId = item['actor_id'] as String? ?? '';
                              final name = item['name'] as String? ?? 'Unknown';
                              final age = item['age'];
                              final profilePic =
                                  item['profile_pic'] as String? ?? '';
                              final isSuperlike = item['action'] == 'superlike';

                              return GestureDetector(
                                onTap: () => _showLikeProfile(
                                  ctx: ctx,
                                  actorId: actorId,
                                  name: name,
                                  onActioned: (id) {
                                    setState(() {
                                      _likeItems.removeWhere(
                                        (i) => i['actor_id'] == id,
                                      );
                                    });
                                    setModalState(() {});
                                  },
                                ),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1E293B),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: Colors.white.withAlpha(20),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(
                                        child: ClipRRect(
                                          borderRadius:
                                              const BorderRadius.vertical(
                                                top: Radius.circular(20),
                                              ),
                                          child: profilePic.isNotEmpty
                                              ? StorageImage(
                                                  imagePath: profilePic,
                                                )
                                              : ColoredBox(
                                                  color: themeColor.withAlpha(
                                                    40,
                                                  ),
                                                  child: const Center(
                                                    child: Icon(
                                                      LucideIcons.user,
                                                      color: Colors.white38,
                                                      size: 36,
                                                    ),
                                                  ),
                                                ),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    age != null
                                                        ? '$name, $age'
                                                        : name,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 14,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                if (isSuperlike)
                                                  const Icon(
                                                    LucideIcons.star,
                                                    color: Color(0xFFF59E0B),
                                                    size: 13,
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              isSuperlike
                                                  ? 'Superliked you ⭐'
                                                  : 'Liked you ❤️',
                                              style: TextStyle(
                                                color: Colors.white.withAlpha(
                                                  140,
                                                ),
                                                fontSize: 11,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
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
            );
          },
        );
      },
    );
  }

  void _showMatchesOverlay() {
    const themeColor = Color(0xFFFF4F81);

    unawaited(showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setModalState) {
            final session = Supabase.instance.client.auth.currentSession;

            void removeMatch(String userId) {
              setState(
                () => _matches.removeWhere(
                  (m) => m['matched_user_id'] == userId,
                ),
              );
              setModalState(() {});
            }

            return Container(
              height: MediaQuery.of(sheetCtx).size.height * 0.78,
              decoration: const BoxDecoration(
                color: Color(0xFF0F172A),
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(50),
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              LucideIcons.heartHandshake,
                              color: themeColor,
                              size: 24,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Matches',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: themeColor.withAlpha(38),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${_matches.length} matched',
                            style: const TextStyle(
                              color: themeColor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: _matches.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  LucideIcons.heartOff,
                                  color: Colors.white.withAlpha(50),
                                  size: 48,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No matches yet',
                                  style: TextStyle(
                                    color: Colors.white.withAlpha(150),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Like someone back from your inbox',
                                  style: TextStyle(
                                    color: Colors.white.withAlpha(80),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(24, 4, 12, 32),
                            itemCount: _matches.length,
                            separatorBuilder: (context, index) =>
                                Divider(color: Colors.white.withAlpha(12)),
                            itemBuilder: (_, i) {
                              final match = _matches[i];
                              final userId =
                                  match['matched_user_id'] as String? ?? '';
                              final name =
                                  match['name'] as String? ?? 'Unknown';
                              final age = match['age'];
                              final profilePic =
                                  match['profile_pic'] as String?;
                              final isNew = match['is_new'] == true;
                              final displayName = age != null
                                  ? '$name, $age'
                                  : name;

                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                child: Row(
                                  children: [
                                    // Avatar
                                    Container(
                                      width: 52,
                                      height: 52,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: themeColor.withAlpha(80),
                                          width: 2,
                                        ),
                                      ),
                                      child: ClipOval(
                                        child:
                                            profilePic != null &&
                                                profilePic.isNotEmpty
                                            ? StorageImage(
                                                imagePath: profilePic,
                                              )
                                            : ColoredBox(
                                                color: themeColor.withAlpha(30),
                                                child: Icon(
                                                  LucideIcons.user,
                                                  color: themeColor.withAlpha(
                                                    160,
                                                  ),
                                                  size: 26,
                                                ),
                                              ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    // Name + new badge
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            displayName,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (isNew)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 3,
                                              ),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 7,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: themeColor.withAlpha(
                                                    38,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: const Text(
                                                  'New match ✨',
                                                  style: TextStyle(
                                                    color: themeColor,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    // Action buttons
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Chat (stub)
                                        IconButton(
                                          icon: const Icon(
                                            LucideIcons.messageCircle,
                                            size: 20,
                                          ),
                                          color: Colors.white54,
                                          visualDensity: VisualDensity.compact,
                                          tooltip: 'Chat',
                                          onPressed: () {
                                            ScaffoldMessenger.of(
                                              sheetCtx,
                                            ).showSnackBar(
                                              const SnackBar(
                                                behavior:
                                                    SnackBarBehavior.floating,
                                                backgroundColor: Color(
                                                  0xFF1E293B,
                                                ),
                                                content: Text(
                                                  'Chat coming soon 💬',
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                        // Unmatch
                                        IconButton(
                                          icon: const Icon(
                                            LucideIcons.x,
                                            size: 20,
                                          ),
                                          color: Colors.white38,
                                          visualDensity: VisualDensity.compact,
                                          tooltip: 'Unmatch',
                                          onPressed: () async {
                                            final ok = await showDialog<bool>(
                                              context: sheetCtx,
                                              builder: (d) => AlertDialog(
                                                backgroundColor: const Color(
                                                  0xFF1E293B,
                                                ),
                                                title: Text(
                                                  'Unmatch from $name?',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 17,
                                                  ),
                                                ),
                                                content: Text(
                                                  "You won't see each other for some time.",
                                                  style: TextStyle(
                                                    color: Colors.white
                                                        .withAlpha(160),
                                                    fontSize: 14,
                                                  ),
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(d, false),
                                                    child: Text(
                                                      'Cancel',
                                                      style: TextStyle(
                                                        color: Colors.white
                                                            .withAlpha(160),
                                                      ),
                                                    ),
                                                  ),
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(d, true),
                                                    child: const Text(
                                                      'Unmatch',
                                                      style: TextStyle(
                                                        color: themeColor,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                            if ((ok ?? false) &&
                                                session != null) {
                                              await _recordMatchAction(
                                                userId,
                                                'unmatch',
                                                session.accessToken,
                                              );
                                              removeMatch(userId);
                                            }
                                          },
                                        ),
                                        // Block / Report
                                        PopupMenuButton<String>(
                                          icon: const Icon(
                                            LucideIcons.moreVertical,
                                            size: 20,
                                            color: Colors.white38,
                                          ),
                                          color: const Color(0xFF1E293B),
                                          padding: EdgeInsets.zero,
                                          onSelected: (value) async {
                                            if (value == 'block') {
                                              final ok =
                                                  await showProfileBlockDialog(
                                                    sheetCtx,
                                                    name,
                                                  );
                                              if ((ok ?? false) &&
                                                  session != null) {
                                                await _recordMatchAction(
                                                  userId,
                                                  'block',
                                                  session.accessToken,
                                                );
                                                removeMatch(userId);
                                              }
                                            } else if (value == 'report') {
                                              if (!sheetCtx.mounted) return;
                                              unawaited(
                                                showProfileReportDialog(
                                                  sheetCtx,
                                                  onConfirmed:
                                                      (reason, detail) async {
                                                        if (session == null) {
                                                          return;
                                                        }
                                                        await _recordMatchAction(
                                                          userId,
                                                          'report',
                                                          session.accessToken,
                                                          reason: reason,
                                                          reasonDetail: detail,
                                                        );
                                                        removeMatch(userId);
                                                      },
                                                ),
                                              );
                                            }
                                          },
                                          itemBuilder: (_) => [
                                            const PopupMenuItem(
                                              value: 'block',
                                              child: Text(
                                                'Block',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                            const PopupMenuItem(
                                              value: 'report',
                                              child: Text(
                                                'Report',
                                                style: TextStyle(
                                                  color: Colors.redAccent,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    ));
  }

  @override
  Widget build(BuildContext context) {
    const themeColor = Color(0xFFFF4F81);
    final activeLikesCount = _unseenCount;

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: CircularProgressIndicator(color: themeColor)),
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
                            Color(0xFFFF4F81),
                            Color(0xFF8B5CF6),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF4F81).withAlpha(76),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: InkWell(
                        onTap: () {
                          widget.onOpenOrbit('Dating', const Color(0xFFFF4F81));
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
                          'Activate Dating Orbit above to unlock matches, chats, and daily sparks.',
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

class DatingActivationOverlay extends StatefulWidget {
  const DatingActivationOverlay({required this.onFinished, super.key});

  final VoidCallback onFinished;

  @override
  State<DatingActivationOverlay> createState() =>
      _DatingActivationOverlayState();
}

class _DatingActivationOverlayState extends State<DatingActivationOverlay>
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

    unawaited(_controller.forward().then((_) {
      widget.onFinished();
    }));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const brandPink = Color(0xFFFF4F81);
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
                const Color(0xFF1E1B4B), // deep purple
                const Color(0xFF581C87).withValues(alpha: 0.95), // violet
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Concentric rotating rings
              AnimatedBuilder(
                animation: _rotationAnimation,
                builder: (context, child) {
                  return Transform.rotate(
                    angle: _rotationAnimation.value,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        _buildRadarRing(
                          260,
                          4,
                          brandPink.withValues(alpha: 0.1),
                        ),
                        _buildRadarRing(
                          200,
                          3,
                          brandPink.withValues(alpha: 0.2),
                        ),
                        _buildRadarRing(
                          140,
                          2,
                          brandPink.withValues(alpha: 0.3),
                        ),
                      ],
                    ),
                  );
                },
              ),
              // Main pulsing center
              ScaleTransition(
                scale: _scaleAnimation,
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: brandPink,
                    boxShadow: [
                      BoxShadow(
                        color: brandPink.withValues(alpha: 0.5),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      LucideIcons.heart,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                ),
              ),
              // Overlay text description
              Positioned(
                bottom: 120,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'DATING ORBIT',
                      style: TextStyle(
                        color: brandPink,
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
                      'Broadcasting matching signals near you...',
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

  Widget _buildRadarRing(double size, double strokeWidth, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: color,
          width: strokeWidth,
        ),
      ),
    );
  }
}
