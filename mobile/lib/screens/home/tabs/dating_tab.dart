import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/screens/home/widgets/tab_scaffold.dart';
import 'package:dio/dio.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/utils/network_utils.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LikeItem {
  final String name;
  final String age;
  final String type;
  final String tag;
  final Color color;
  bool hasActioned;

  LikeItem({
    required this.name,
    required this.age,
    required this.type,
    required this.tag,
    required this.color,
    this.hasActioned = false,
  });
}

class ChatItem {
  final String name;
  final String age;
  final String lastMsg;
  final String time;
  final bool unread;
  final Color color;

  ChatItem({
    required this.name,
    required this.age,
    required this.lastMsg,
    required this.time,
    required this.unread,
    required this.color,
  });
}

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
  int? _selectedSparkOption;

  // Mock data for Likes
  final List<LikeItem> _likes = [
    LikeItem(
      name: 'Sophia',
      age: '21',
      type: 'Liked your profile',
      tag: 'Art',
      color: Colors.pinkAccent,
    ),
    LikeItem(
      name: 'Olivia',
      age: '20',
      type: 'Waved at you',
      tag: 'Tech',
      color: Colors.cyan,
    ),
    LikeItem(
      name: 'Emma',
      age: '22',
      type: 'Liked your prompt',
      tag: 'Travel',
      color: Colors.purpleAccent,
    ),
    LikeItem(
      name: 'Ava',
      age: '23',
      type: 'Liked your music',
      tag: 'Music',
      color: Colors.orangeAccent,
    ),
  ];

  // Mock data for Chats
  final List<ChatItem> _chats = [
    ChatItem(
      name: 'Liam',
      age: '22',
      lastMsg: 'Hey! Are you going to the gig tonight?',
      time: '1m ago',
      unread: true,
      color: Colors.blueAccent,
    ),
    ChatItem(
      name: 'Ethan',
      age: '23',
      lastMsg: 'That track is amazing. Let\'s collaborate!',
      time: '2h ago',
      unread: false,
      color: Colors.greenAccent,
    ),
    ChatItem(
      name: 'Chloe',
      age: '21',
      lastMsg: 'Let\'s grab a coffee sometime this week.',
      time: '1d ago',
      unread: false,
      color: Colors.amberAccent,
    ),
    ChatItem(
      name: 'Noah',
      age: '24',
      lastMsg: 'Hey there! Nice profile.',
      time: '2d ago',
      unread: false,
      color: Colors.redAccent,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _loadDatingProfileStatus();
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
            _isOrbitActive = data['is_dating_complete'] == true;

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
    } catch (e) {
      debugPrint(
        '[DatingTab] Error fetching dating status, using fallback: $e',
      );
    }

    // Offline/Error fallback data to ensure loading screen always disappears
    if (mounted) {
      setState(() {
        _datingTargetBuckets = ['M', 'F'];
        _datingFor = ['short', 'long'];
        _partnerValues = 'Deep trust, open communication, and shared growth.';
        _isOrbitActive = false;
        _isLoading = false;
      });
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
    } catch (e) {
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

  // Toggle Orbit activation state (patching is_dating_complete)
  Future<void> _toggleOrbitState(bool active) async {
    setState(() => _isLoading = true);
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        final config = AppConfig.current;
        final dio = createDio();
        final response = await dio.patch<Map<String, dynamic>>(
          '${config.backendUrl}/api/v1/profile/details',
          data: {'is_dating_complete': active},
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
            } else {
              _showDatingSettingsOverlay(isActivating: true);
            }
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
    } catch (e) {
      debugPrint('[DatingTab] Orbit activation failed: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Show dialog when core profile is incomplete (Light themed, matching app design)
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
                'Please complete your core profile details first before setting up Dating features:',
                style: TextStyle(color: Color(0xFF475569), fontSize: 14),
              ),
              const SizedBox(height: 16),
              ..._missingFields
                  .where((f) => f.toString() != 'dating_target_buckets')
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
                if (widget.onNavigateToTab != null) {
                  widget.onNavigateToTab!(2); // Go to Profile Tab (index 2)
                }
              },
              child: const Text('Go to Profile Tab'),
            ),
          ],
        );
      },
    );
  }

  // Show slide-up Dating Settings overlay
  void _showDatingSettingsOverlay({bool isActivating = false}) {
    List<String> localBuckets = List<String>.from(_datingTargetBuckets);
    List<String> localDatingFor = List<String>.from(_datingFor);
    List<String> localPartnerValues = _partnerValues.isNotEmpty
        ? _partnerValues
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList()
        : [];
    String searchQuery = '';

    final List<String> predefinedValues = [
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

    showModalBottomSheet<void>(
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
                      color: Colors.black.withOpacity(0.1),
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
                            ).withOpacity(0.4),
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
                                  backgroundColor: Colors.black.withOpacity(
                                    0.04,
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
                                    side: BorderSide.none,
                                  ),
                                  onSelected: (selected) async {
                                    if (_savingFields.contains(
                                      'dating_target_buckets',
                                    ))
                                      return;
                                    setModalState(() {
                                      if (selected) {
                                        localBuckets.add(code);
                                      } else {
                                        localBuckets.remove(code);
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
                                  backgroundColor: Colors.black.withOpacity(
                                    0.04,
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
                                    side: BorderSide.none,
                                  ),
                                  onSelected: (selected) async {
                                    if (_savingFields.contains('dating_for'))
                                      return;
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
                                ).withOpacity(0.1),
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
                                  if (_savingFields.contains('partner_values'))
                                    return;
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
                            fillColor: Colors.black.withOpacity(0.04),
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
                                  if (_savingFields.contains('partner_values'))
                                    return;
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
                                backgroundColor: Colors.black.withOpacity(0.04),
                                labelStyle: const TextStyle(
                                  color: Color(0xFF0F172A),
                                  fontSize: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                side: BorderSide.none,
                                onPressed: () async {
                                  if (_savingFields.contains('partner_values'))
                                    return;
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

  void _showLikesOverlay() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final activeLikes = _likes.where((l) => !l.hasActioned).toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
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
                        Row(
                          children: [
                            const Icon(
                              LucideIcons.heart,
                              color: Color(0xFFFF4F81),
                              size: 24,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Likes & Waves',
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
                            '${activeLikes.length} New',
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
                    child: activeLikes.isEmpty
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
                                  'All caught up!',
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
                            itemCount: activeLikes.length,
                            itemBuilder: (context, index) {
                              final like = activeLikes[index];
                              return Container(
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
                                      child: Container(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              like.color.withAlpha(128),
                                              like.color.withAlpha(26),
                                            ],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          borderRadius:
                                              const BorderRadius.vertical(
                                                top: Radius.circular(20),
                                              ),
                                        ),
                                        child: Center(
                                          child: Icon(
                                            LucideIcons.user,
                                            color: Colors.white.withAlpha(180),
                                            size: 40,
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
                                          Text(
                                            '${like.name}, ${like.age}',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            like.type,
                                            style: TextStyle(
                                              color: Colors.white.withAlpha(
                                                140,
                                              ),
                                              fontSize: 11,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: SizedBox(
                                                  height: 32,
                                                  child: ElevatedButton(
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor:
                                                          const Color(
                                                            0xFFFF4F81,
                                                          ),
                                                      foregroundColor:
                                                          Colors.white,
                                                      padding: EdgeInsets.zero,
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              10,
                                                            ),
                                                      ),
                                                    ),
                                                    onPressed: () {
                                                      setModalState(() {
                                                        like.hasActioned = true;
                                                      });
                                                      setState(() {});
                                                      ScaffoldMessenger.of(
                                                        context,
                                                      ).showSnackBar(
                                                        SnackBar(
                                                          behavior:
                                                              SnackBarBehavior
                                                                  .floating,
                                                          backgroundColor:
                                                              const Color(
                                                                0xFFFF4F81,
                                                              ),
                                                          content: Text(
                                                            'Matched with ${like.name}! 🎉',
                                                          ),
                                                        ),
                                                      );
                                                    },
                                                    child: const Icon(
                                                      LucideIcons.heart,
                                                      size: 14,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Container(
                                                height: 32,
                                                width: 32,
                                                decoration: BoxDecoration(
                                                  color: Colors.white.withAlpha(
                                                    20,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                ),
                                                child: IconButton(
                                                  padding: EdgeInsets.zero,
                                                  icon: const Icon(
                                                    LucideIcons.hand,
                                                    size: 14,
                                                    color: Colors.amber,
                                                  ),
                                                  onPressed: () {
                                                    setModalState(() {
                                                      like.hasActioned = true;
                                                    });
                                                    setState(() {});
                                                    ScaffoldMessenger.of(
                                                      context,
                                                    ).showSnackBar(
                                                      SnackBar(
                                                        behavior:
                                                            SnackBarBehavior
                                                                .floating,
                                                        backgroundColor:
                                                            Colors.amber[800],
                                                        content: Text(
                                                          'Waved back at ${like.name}! 👋',
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
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

  void _showChatsOverlay() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.75,
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
                    Row(
                      children: [
                        const Icon(
                          LucideIcons.messageSquare,
                          color: Color(0xFFFF4F81),
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Chats & Matches',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const Icon(
                      LucideIcons.slidersHorizontal,
                      color: Colors.white70,
                      size: 20,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 8,
                  ),
                  itemCount: _chats.length,
                  separatorBuilder: (context, index) =>
                      Divider(color: Colors.white.withAlpha(15)),
                  itemBuilder: (context, index) {
                    final chat = _chats[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 26,
                        backgroundColor: chat.color.withAlpha(50),
                        child: Icon(
                          LucideIcons.user,
                          color: chat.color,
                          size: 24,
                        ),
                      ),
                      title: Row(
                        children: [
                          Text(
                            '${chat.name}, ${chat.age}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (chat.unread)
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFFFF4F81),
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      subtitle: Text(
                        chat.lastMsg,
                        style: TextStyle(
                          color: chat.unread
                              ? Colors.white
                              : Colors.white.withAlpha(140),
                          fontSize: 13,
                          fontWeight: chat.unread
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            chat.time,
                            style: TextStyle(
                              color: Colors.white.withAlpha(100),
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Icon(
                            LucideIcons.chevronRight,
                            color: Colors.white38,
                            size: 16,
                          ),
                        ],
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: const Color(0xFF1E293B),
                            content: Text(
                              'Opening chat with ${chat.name}... 💬',
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const themeColor = Color(0xFFFF4F81);
    final activeLikesCount = _likes.where((l) => !l.hasActioned).length;

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
      onSettingsPressed: () => _showDatingSettingsOverlay(isActivating: false),
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
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              behavior: SnackBarBehavior.floating,
                              backgroundColor: Color(0xFFFF4F81),
                              content: Text(
                                'Opening Dating Orbit scan view... 📡',
                              ),
                            ),
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
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
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
                                      'Enter 3D radar to scan nearby signals',
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
                                        'Likes & Waves',
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
                              onTap: _showChatsOverlay,
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
                                        LucideIcons.messageSquare,
                                        color: Colors.white,
                                        size: 28,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    const Text(
                                      'Chats & Matches',
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
                                        '${_chats.length} ACTIVE',
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
                    const SizedBox(height: 28),
                    const Text(
                      'Daily Spark',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.black.withAlpha(10)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(8),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withAlpha(38),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  LucideIcons.sparkles,
                                  color: Colors.amber,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Ideal first date activity?',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey[800],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (_selectedSparkOption == null) ...[
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                side: BorderSide(
                                  color: Colors.black.withAlpha(20),
                                ),
                              ),
                              onPressed: () =>
                                  setState(() => _selectedSparkOption = 0),
                              child: const Text(
                                '☕ Casual Coffee & Walk',
                                style: TextStyle(
                                  color: Color(0xFF0F172A),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                side: BorderSide(
                                  color: Colors.black.withAlpha(20),
                                ),
                              ),
                              onPressed: () =>
                                  setState(() => _selectedSparkOption = 1),
                              child: const Text(
                                '🍹 Skyline Rooftop Drinks',
                                style: TextStyle(
                                  color: Color(0xFF0F172A),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ] else ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF4F81).withAlpha(15),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '☕ Casual Coffee & Walk',
                                        style: TextStyle(
                                          fontWeight: _selectedSparkOption == 0
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                          color: _selectedSparkOption == 0
                                              ? const Color(0xFFFF4F81)
                                              : Colors.grey[700],
                                        ),
                                      ),
                                      const Text(
                                        '62%',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: const LinearProgressIndicator(
                                      value: 0.62,
                                      backgroundColor: Colors.white,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Color(0xFFFF4F81),
                                      ),
                                      minHeight: 6,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.black.withAlpha(10),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '🍹 Skyline Rooftop Drinks',
                                        style: TextStyle(
                                          fontWeight: _selectedSparkOption == 1
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                          color: _selectedSparkOption == 1
                                              ? const Color(0xFFFF4F81)
                                              : Colors.grey[700],
                                        ),
                                      ),
                                      const Text(
                                        '38%',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: const LinearProgressIndicator(
                                      value: 0.38,
                                      backgroundColor: Colors.white,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Color(0xFFFF4F81),
                                      ),
                                      minHeight: 6,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Center(
                              child: Text(
                                'Choice saved! Matches with same choice will glow in your Orbit.',
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 11,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
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
                      color: Colors.white.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: Colors.black.withAlpha(15)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
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
                          onPressed: () =>
                              _showDatingSettingsOverlay(isActivating: false),
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
        curve: const Interval(0.0, 0.8, curve: Curves.easeOutBack),
      ),
    );

    _fadeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 0.0, end: 1.0), weight: 15),
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 70),
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 0.0), weight: 15),
    ]).animate(_controller);

    _rotationAnimation = Tween<double>(begin: 0.0, end: 2 * 3.14159).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.9, curve: Curves.linear),
      ),
    );

    _controller.forward().then((_) {
      widget.onFinished();
    });
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
                const Color(0xFF581C87).withOpacity(0.95), // violet
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
                        _buildRadarRing(260, 4, brandPink.withOpacity(0.1)),
                        _buildRadarRing(200, 3, brandPink.withOpacity(0.2)),
                        _buildRadarRing(140, 2, brandPink.withOpacity(0.3)),
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
                        color: brandPink.withOpacity(0.5),
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
                        letterSpacing: 4.0,
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
                        color: Colors.white.withOpacity(0.7),
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
          style: BorderStyle.solid,
        ),
      ),
    );
  }
}
