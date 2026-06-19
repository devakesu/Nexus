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
    )..repeat(reverse: true);
    unawaited(_loadProfessionalProfileStatus());
    unawaited(_fetchHandshakes());
    unawaited(_fetchConnections());
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadProfessionalProfileStatus() async {
    setState(() => _isLoading = true);
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

            _isLoading = false;
          });
          return;
        }
      }
    } on Exception catch (e) {
      debugPrint('[ProfessionalTab] Error fetching professional status: $e');
    }

    if (mounted) {
      setState(() {
        if (_professionalTargetBuckets.isEmpty) {
          _professionalTargetBuckets = ['M', 'F', 'NB'];
        }
        _isOrbitActive = false;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadProfessionalProfileStatusSilent() async {
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
            final rawRoleType2 = data['role_type'];
            _roleType = rawRoleType2 is List
                ? rawRoleType2.map((e) => e.toString()).toList()
                : [];
          });
        }
      }
    } on Exception catch (e) {
      debugPrint(
        '[ProfessionalTab] Error fetching professional status silently: $e',
      );
    }
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
    } on Exception catch (e) {
      debugPrint('[ProfessionalTab] Error saving professional details: $e');
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
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                behavior: SnackBarBehavior.floating,
                backgroundColor: Color(0xFF1E293B),
                content: Text('Professional Orbit Deactivated.'),
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
            _showFloatingToast(
              'Complete your Professional settings to activate your orbit.',
              const Color(0xFF00C4AB),
            );
            return;
          }
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.redAccent,
            content: Text('Professional Profile is incomplete.'),
          ),
        );
      }
    } on Exception catch (e) {
      debugPrint('[ProfessionalTab] Orbit activation failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showProfileIncompleteDialog() {
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
    );
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

  Future<void> _showProfessionalSettingsOverlay({
    bool isActivating = false,
  }) async {
    await _loadProfessionalProfileStatusSilent();
    final localBuckets = List<String>.from(_professionalTargetBuckets);
    final localLookingFor = List<String>.from(_lookingFor);
    final localTechSkills = List<String>.from(_techSkills);
    final localRoleType = List<String>.from(_roleType);
    var skillsSearchQuery = '';
    final companyController = TextEditingController(text: _company);
    Timer? companyDebounce;

    final predefinedRoleTypes = <String>[
      'Founder',
      'Co-founder',
      'Engineer',
      'Designer',
      'Product Manager',
      'Data Scientist',
      'Researcher',
      'Student',
      'Investor',
      'VC',
      'Consultant',
      'Manager',
      'Marketing',
      'Sales',
      'Operations',
      'Healthcare',
      'Educator',
      'Freelancer',
      'Other',
    ];

    final predefinedLookingFor = <String>[
      'Mentorship',
      'Collaboration',
      'Networking',
      'Co-founder',
      'Freelance Work',
      'Job Opportunities',
      'Internship',
      'Partnerships',
      'Investors',
      'Side Projects',
      'Open Source',
      'Research',
      'Advisory',
      'Clients',
      'Peer Learning',
    ];

    final predefinedTechSkills = <String>[
      'Flutter',
      'React',
      'Python',
      'Swift',
      'Kotlin',
      'TypeScript',
      'Node.js',
      'Go',
      'Rust',
      'Java',
      'C++',
      'Machine Learning',
      'Data Science',
      'DevOps',
      'Kubernetes',
      'AWS',
      'Firebase',
      'GraphQL',
      'PostgreSQL',
      'MongoDB',
      'Figma',
      'UI/UX Design',
      'Product Management',
      'Agile',
      'Blockchain',
      'AR/VR',
      'Cybersecurity',
      'Cloud Architecture',
      'Android',
      'iOS',
    ];

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filteredSkills = predefinedTechSkills
                .where(
                  (val) => val.toLowerCase().contains(
                    skillsSearchQuery.toLowerCase(),
                  ),
                )
                .where((val) => !localTechSkills.contains(val))
                .toList();

            final showCustomSkill =
                skillsSearchQuery.trim().isNotEmpty &&
                !predefinedTechSkills.any(
                  (val) =>
                      val.toLowerCase() ==
                      skillsSearchQuery.trim().toLowerCase(),
                ) &&
                !localTechSkills.any(
                  (val) =>
                      val.toLowerCase() ==
                      skillsSearchQuery.trim().toLowerCase(),
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
                              color: Color(0xFF00C4AB),
                              size: 24,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Professional Settings',
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
                            backgroundColor: const Color(0xFF00C4AB),
                            foregroundColor: Colors.white,
                            elevation: 4,
                            shadowColor: const Color(
                              0xFF00C4AB,
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
                            companyDebounce?.cancel();
                            final pendingCompany = companyController.text.trim();
                            if (pendingCompany != _company) {
                              unawaited(
                                _saveProfessionalField(
                                  'role_at',
                                  pendingCompany,
                                  setModalState,
                                ),
                              );
                            }
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
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      children: [
                        // Target Buckets
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Who are you open to connecting with?',
                                style: TextStyle(
                                  color: Color(0xFF0F172A),
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (_savingFields.contains(
                              'professional_target_buckets',
                            ))
                              const Padding(
                                padding: EdgeInsets.only(left: 8),
                                child: SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Color(0xFF00C4AB),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Select who you want to appear in your Professional Orbit.',
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
                                  selectedColor: const Color(0xFF00C4AB),
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
                                      'professional_target_buckets',
                                    )) {
                                      return;
                                    }
                                    setModalState(() {
                                      if (selected) {
                                        localBuckets.add(code);
                                      } else {
                                        localBuckets.remove(code);
                                      }
                                    });
                                    await _saveProfessionalField(
                                      'professional_target_buckets',
                                      localBuckets,
                                      setModalState,
                                    );
                                  },
                                );
                              }).toList(),
                        ),
                        const SizedBox(height: 32),

                        // Role Type
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'What best describes your role?',
                                style: TextStyle(
                                  color: Color(0xFF0F172A),
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (_savingFields.contains('role_type'))
                              const Padding(
                                padding: EdgeInsets.only(left: 8),
                                child: SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Color(0xFF00C4AB),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Select all that apply.',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: predefinedRoleTypes.map((item) {
                            final isSelected = localRoleType.contains(item);
                            return FilterChip(
                              label: Text(item),
                              selected: isSelected,
                              selectedColor: const Color(0xFF00C4AB),
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
                                if (_savingFields.contains('role_type')) {
                                  return;
                                }
                                setModalState(() {
                                  if (selected) {
                                    localRoleType.add(item);
                                  } else {
                                    localRoleType.remove(item);
                                  }
                                });
                                await _saveProfessionalField(
                                  'role_type',
                                  localRoleType,
                                  setModalState,
                                );
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 32),

                        // Company / Institute
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Company / Institute',
                                style: TextStyle(
                                  color: Color(0xFF0F172A),
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (_savingFields.contains('role_at'))
                              const Padding(
                                padding: EdgeInsets.only(left: 8),
                                child: SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Color(0xFF00C4AB),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Leave blank if not applicable — this is optional.',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: companyController,
                          style: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 14,
                          ),
                          decoration: InputDecoration(
                            hintText: 'e.g. Google, MIT, Acme Corp',
                            hintStyle: TextStyle(
                              color: Colors.black.withValues(alpha: 0.3),
                              fontSize: 13,
                            ),
                            prefixIcon: const Icon(
                              LucideIcons.briefcase,
                              size: 18,
                              color: Color(0xFF00C4AB),
                            ),
                            filled: true,
                            fillColor: Colors.black.withValues(alpha: 0.04),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                color: Color(0xFF00C4AB),
                                width: 1.5,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                          textInputAction: TextInputAction.done,
                          onChanged: (val) {
                            companyDebounce?.cancel();
                            companyDebounce = Timer(
                              const Duration(milliseconds: 800),
                              () {
                                if (val.trim() != _company) {
                                  unawaited(
                                    _saveProfessionalField(
                                      'role_at',
                                      val.trim(),
                                      setModalState,
                                    ),
                                  );
                                }
                              },
                            );
                          },
                          onSubmitted: (val) {
                            companyDebounce?.cancel();
                            if (val.trim() != _company) {
                              unawaited(
                                _saveProfessionalField(
                                  'role_at',
                                  val.trim(),
                                  setModalState,
                                ),
                              );
                            }
                          },
                        ),
                        const SizedBox(height: 32),

                        // Looking For
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'What are you looking for professionally?',
                                style: TextStyle(
                                  color: Color(0xFF0F172A),
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (_savingFields.contains('looking_for'))
                              const Padding(
                                padding: EdgeInsets.only(left: 8),
                                child: SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Color(0xFF00C4AB),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Select your professional goals and intentions.',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: predefinedLookingFor.map((item) {
                            final isSelected = localLookingFor.contains(item);
                            return FilterChip(
                              label: Text(item),
                              selected: isSelected,
                              selectedColor: const Color(0xFF00C4AB),
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
                                if (_savingFields.contains('looking_for')) {
                                  return;
                                }
                                setModalState(() {
                                  if (selected) {
                                    localLookingFor.add(item);
                                  } else {
                                    localLookingFor.remove(item);
                                  }
                                });
                                await _saveProfessionalField(
                                  'looking_for',
                                  localLookingFor,
                                  setModalState,
                                );
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 32),

                        // Tech Skills
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'What are your key skills?',
                                style: TextStyle(
                                  color: Color(0xFF0F172A),
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (_savingFields.contains('tech_skills'))
                              const Padding(
                                padding: EdgeInsets.only(left: 8),
                                child: SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Color(0xFF00C4AB),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Add your technical skills and areas of expertise.',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 16),

                        if (localTechSkills.isNotEmpty) ...[
                          const Text(
                            'Your Skills:',
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
                            children: localTechSkills.map((val) {
                              return Chip(
                                label: Text(val),
                                backgroundColor: const Color(
                                  0xFF00C4AB,
                                ).withValues(alpha: 0.1),
                                labelStyle: const TextStyle(
                                  color: Color(0xFF00C4AB),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                                deleteIcon: const Icon(
                                  LucideIcons.x,
                                  size: 14,
                                  color: Color(0xFF00C4AB),
                                ),
                                side: BorderSide.none,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                onDeleted: () async {
                                  if (_savingFields.contains('tech_skills')) {
                                    return;
                                  }
                                  setModalState(
                                    () => localTechSkills.remove(val),
                                  );
                                  await _saveProfessionalField(
                                    'tech_skills',
                                    localTechSkills,
                                    setModalState,
                                  );
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),
                        ],

                        TextField(
                          style: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 14,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Search or add skills...',
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
                            setModalState(() => skillsSearchQuery = val);
                          },
                        ),
                        const SizedBox(height: 16),

                        const Text(
                          'Tap to add skills:',
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
                            if (showCustomSkill)
                              ActionChip(
                                avatar: const Icon(
                                  LucideIcons.plus,
                                  size: 14,
                                  color: Colors.white,
                                ),
                                label: Text(
                                  'Add "${skillsSearchQuery.trim()}"',
                                ),
                                backgroundColor: const Color(0xFF00C4AB),
                                labelStyle: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                onPressed: () async {
                                  if (_savingFields.contains('tech_skills')) {
                                    return;
                                  }
                                  setModalState(() {
                                    localTechSkills.add(
                                      skillsSearchQuery.trim(),
                                    );
                                    skillsSearchQuery = '';
                                  });
                                  await _saveProfessionalField(
                                    'tech_skills',
                                    localTechSkills,
                                    setModalState,
                                  );
                                },
                              ),
                            ...filteredSkills.map((val) {
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
                                  if (_savingFields.contains('tech_skills')) {
                                    return;
                                  }
                                  setModalState(
                                    () => localTechSkills.add(val),
                                  );
                                  await _saveProfessionalField(
                                    'tech_skills',
                                    localTechSkills,
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
    companyDebounce?.cancel();
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 350)).then((_) {
        companyController.dispose();
      }),
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
    } on Exception catch (e) {
      debugPrint('[ProfessionalTab] Error fetching handshakes: $e');
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
    } on Exception catch (e) {
      debugPrint('[ProfessionalTab] Error fetching connections: $e');
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
    } on Exception catch (e) {
      debugPrint('[ProfessionalTab] Error recording connection action: $e');
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
    } on Exception catch (e) {
      debugPrint('[ProfessionalTab] Error marking handshakes seen: $e');
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
    } on Exception catch (e) {
      debugPrint('[ProfessionalTab] Error recording handshake action: $e');
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
        if (mounted) {
          setState(() {
            _connections.insert(0, {
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
        unawaited(_fetchConnections());

        final goToConnections = await rootNav.push<bool?>(
          MaterialPageRoute<bool?>(
            fullscreenDialog: true,
            builder: (_) => MatchScreen(
              matchedName: name,
              matchedProfilePic: matchedProfilePic,
              titleText: "Connected! 🤝",
              subtitleText:
                  'You and $name are now connected.\nTime to build something great together!',
              themeColor: theme,
              badgeIcon: LucideIcons.handshake,
            ),
          ),
        );
        if (goToConnections == true && mounted) {
          Navigator.of(context).pop();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _showConnectionsOverlay();
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
    const themeColor = Color(0xFF00C4AB);

    setState(() => _unseenCount = 0);
    unawaited(_markAllHandshakesSeen());

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
                              LucideIcons.handshake,
                              color: themeColor,
                              size: 24,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Handshakes',
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
                            '${_handshakeItems.length} handshakes',
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
                  const SizedBox(height: 24),
                  Expanded(
                    child: _handshakeItems.isEmpty
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
                                  'No handshakes yet',
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
                            itemCount: _handshakeItems.length,
                            itemBuilder: (ctx, index) {
                              final item = _handshakeItems[index];
                              final actorId = item['actor_id'] as String? ?? '';
                              final name = item['name'] as String? ?? 'Unknown';
                              final age = item['age'];
                              final profilePic =
                                  item['profile_pic'] as String? ?? '';
                              final isSuperConnect =
                                  item['action'] == 'superlike';

                              return GestureDetector(
                                onTap: () => _showHandshakeProfile(
                                  ctx: ctx,
                                  actorId: actorId,
                                  name: name,
                                  onActioned: (id) {
                                    setState(() {
                                      _handshakeItems.removeWhere(
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
                                                if (isSuperConnect)
                                                  const Icon(
                                                    LucideIcons.star,
                                                    color: Color(0xFFF59E0B),
                                                    size: 13,
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              isSuperConnect
                                                  ? 'Super Connected you ⭐'
                                                  : 'Handshaked you 🤝',
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

  void _showConnectionsOverlay() {
    const themeColor = Color(0xFF00C4AB);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setModalState) {
            final session = Supabase.instance.client.auth.currentSession;

            void removeConnection(String userId) {
              setState(
                () => _connections.removeWhere(
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
                              LucideIcons.network,
                              color: themeColor,
                              size: 24,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Connections',
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
                            '${_connections.length} connected',
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
                    child: _connections.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  LucideIcons.network,
                                  color: Colors.white.withAlpha(50),
                                  size: 48,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No connections yet',
                                  style: TextStyle(
                                    color: Colors.white.withAlpha(150),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Connect back from your handshakes inbox',
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
                            itemCount: _connections.length,
                            separatorBuilder: (_, __) =>
                                Divider(color: Colors.white.withAlpha(12)),
                            itemBuilder: (_, i) {
                              final connection = _connections[i];
                              final userId =
                                  connection['matched_user_id'] as String? ??
                                  '';
                              final name =
                                  connection['name'] as String? ?? 'Unknown';
                              final age = connection['age'];
                              final profilePic =
                                  connection['profile_pic'] as String?;
                              final isNew = connection['is_new'] == true;
                              final displayName = age != null
                                  ? '$name, $age'
                                  : name;

                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                child: Row(
                                  children: [
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
                                                child: Center(
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
                                    ),
                                    const SizedBox(width: 12),
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
                                                      BorderRadius.circular(
                                                        8,
                                                      ),
                                                ),
                                                child: const Text(
                                                  'New connection ✨',
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
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(
                                            LucideIcons.messageCircle,
                                            size: 20,
                                          ),
                                          color: Colors.white54,
                                          visualDensity: VisualDensity.compact,
                                          tooltip: 'Message',
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
                                        IconButton(
                                          icon: const Icon(
                                            LucideIcons.x,
                                            size: 20,
                                          ),
                                          color: Colors.white38,
                                          visualDensity: VisualDensity.compact,
                                          tooltip: 'Disconnect',
                                          onPressed: () async {
                                            final ok = await showDialog<bool>(
                                              context: sheetCtx,
                                              builder: (d) => AlertDialog(
                                                backgroundColor: const Color(
                                                  0xFF1E293B,
                                                ),
                                                title: Text(
                                                  'Disconnect from $name?',
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
                                                        Navigator.pop(
                                                          d,
                                                          false,
                                                        ),
                                                    child: Text(
                                                      'Cancel',
                                                      style: TextStyle(
                                                        color: Colors.white
                                                            .withAlpha(
                                                              160,
                                                            ),
                                                      ),
                                                    ),
                                                  ),
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                          d,
                                                          true,
                                                        ),
                                                    child: const Text(
                                                      'Disconnect',
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
                                              await _recordConnectionAction(
                                                userId,
                                                'unmatch',
                                                session.accessToken,
                                              );
                                              removeConnection(userId);
                                            }
                                          },
                                        ),
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
                                                await _recordConnectionAction(
                                                  userId,
                                                  'block',
                                                  session.accessToken,
                                                );
                                                removeConnection(userId);
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
                                                        await _recordConnectionAction(
                                                          userId,
                                                          'report',
                                                          session.accessToken,
                                                          reason: reason,
                                                          reasonDetail: detail,
                                                        );
                                                        removeConnection(
                                                          userId,
                                                        );
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
    );
  }

  @override
  Widget build(BuildContext context) {
    const themeColor = Color(0xFF00F5D4);
    final activeHandshakesCount = _unseenCount;

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: CircularProgressIndicator(color: themeColor)),
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
                                      'Open your Professional Orbit',
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

class ProfessionalActivationOverlay extends StatefulWidget {
  const ProfessionalActivationOverlay({required this.onFinished, super.key});

  final VoidCallback onFinished;

  @override
  State<ProfessionalActivationOverlay> createState() =>
      _ProfessionalActivationOverlayState();
}

class _ProfessionalActivationOverlayState
    extends State<ProfessionalActivationOverlay>
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

    _controller.forward().then((_) => widget.onFinished());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const brandColor = Color(0xFF00F5D4);
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
                const Color(0xFF001A17),
                const Color(0xFF003D36).withValues(alpha: 0.95),
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
                      LucideIcons.handshake,
                      color: Colors.black87,
                      size: 40,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 120,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'PROFESSIONAL ORBIT',
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
                      'Broadcasting your professional signals nearby...',
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
