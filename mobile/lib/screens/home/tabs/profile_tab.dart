import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/screens/home/widgets/export_code_card.dart';
import 'package:nexus/utils/network_utils.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileTab extends StatefulWidget {
  const ProfileTab({required this.onOpenOrbit, super.key});

  final void Function(String, Color) onOpenOrbit;

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> with TickerProviderStateMixin {
  AnimationController? _pulseController;
  AnimationController? _rotationController;
  late PageController _pageController;
  final SupabaseClient _client = Supabase.instance.client;

  // Loading state
  bool _isLoading = true;

  // Core profile state loaded from DB/Onboarding
  String _name = 'Alex';
  int _age = 21;
  int _savedAge = 21;
  bool _ageChangedSinceInteract = false;
  int _year = 3;
  String _pronouns = 'they/them';
  String _location = 'Campus Nebula';
  String _major = 'Computer Science';
  String _vibeMode = 'deep';
  String _selectedAvatarEmoji = '🪐';
  String _displayGender = 'Not specified';
  String _displaySexuality = 'Not specified';
  List<String> _searchBuckets = [];
  bool _isSavingDetails = false;

  // Extended profile fields from DB migration
  String _hometown = 'Not specified';
  String _partnerValues = '';
  String _childrenPlans = 'Not specified';
  String _religiousBeliefs = 'Not specified';
  String _lifestyle = '';
  String _drinking = 'Not specified';
  String _smoking = 'Not specified';
  String _role = 'Not specified';
  List<String> _targetBuckets = [];
  List<String> _lookingFor = [];
  List<String> _activities = [];
  List<String> _causesSupported = [];
  List<String> _topArtists = [];
  List<String> _techSkills = [];
  List<String> _languages = [];
  List<String> _pets = [];
  final TextEditingController _artistInputController = TextEditingController();


  // Interests / Vibe Tags State
  final Map<String, List<String>> _tagsByCategory = {
    'fixations': ['cybernetics', 'deep-dive', 'analog synth', 'design systems', 'creative coding'],
    'soundscapes': ['ambient fog', 'witch house', 'hyperpop', 'lo-fi beats', 'shoegaze'],
    'trajectories': ['startup', 'research', 'nomad', 'open source', 'metaverse'],
  };
  final Set<String> _selectedTags = {'creative coding', 'ambient fog', 'open source'};

  // Prompts State
  final List<Map<String, String>> _prompts = [
    {
      'question': 'midnight thoughts that keep you awake...',
      'answer': 'what if gravity is just the universe trying to embrace us all at once?',
    },
    {
      'question': 'my current obsession is...',
      'answer': 'analog modular synthesizers and procedural graphic generation.',
    },
    {
      'question': 'the frequency I vibe with is...',
      'answer': 'a quiet rainy night in the computer science library basement.',
    },
  ];
  int _currentPromptIndex = 0;
  double _shuffleRotation = 0;

  // Simulated image assets slot states: each slot has a state (0 = empty, 1 = loading, 2 = loaded)
  final List<int> _slotStates = [2, 0, 0, 0];
  final List<LinearGradient> _slotGradients = [
    const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFFFF7597)]),
    const LinearGradient(colors: [Colors.transparent, Colors.transparent]),
    const LinearGradient(colors: [Colors.transparent, Colors.transparent]),
    const LinearGradient(colors: [Colors.transparent, Colors.transparent]),
  ];
  final List<IconData> _slotIcons = [
    LucideIcons.sparkles,
    LucideIcons.image,
    LucideIcons.image,
    LucideIcons.image,
  ];

  @override
  void initState() {
    super.initState();
    final pulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    _pulseController = pulse;
    unawaited(pulse.repeat(reverse: true));

    final rotation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );
    _rotationController = rotation;
    unawaited(rotation.repeat());

    _pageController = PageController();
    unawaited(_loadProfileData());
  }

  @override
  void dispose() {
    _pulseController?.dispose();
    _rotationController?.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadProfileData() async {
    setState(() => _isLoading = true);
    try {
      final session = _client.auth.currentSession;
      if (session != null) {
        final config = AppConfig.current;
        final dio = createDio();
        final response = await dio.get<Map<String, dynamic>>(
          '${config.backendUrl}/api/v1/profile/details',
          options: Options(
            headers: {
              'Authorization': 'Bearer ${session.accessToken}',
            },
          ),
        );

        if (response.statusCode == 200 && response.data != null && mounted) {
          final data = response.data!;
          setState(() {
            _name = data['name']?.toString() ?? _name;
            _age = (data['age'] as num?)?.toInt() ?? _age;
            _savedAge = _age;
            if (data['year'] != null) {
              _year = (data['year'] as num).toInt();
            }
            if (data['branch'] != null) {
              _location = data['branch'].toString();
            }
            _displayGender = data['display_gender']?.toString() ?? 'Not specified';
            _displaySexuality = data['display_sexuality']?.toString() ?? 'Not specified';
            _hometown = data['hometown']?.toString() ?? 'Not specified';
            _partnerValues = data['partner_values']?.toString() ?? '';
            _childrenPlans = data['children_plans']?.toString() ?? 'Not specified';
            _religiousBeliefs = data['religious_beliefs']?.toString() ?? 'Not specified';
            _lifestyle = data['lifestyle']?.toString() ?? '';
            _drinking = data['drinking']?.toString() ?? 'Not specified';
            _smoking = data['smoking']?.toString() ?? 'Not specified';
            _role = data['role']?.toString() ?? 'Not specified';
            
            final rawBuckets = data['search_buckets'];
            if (rawBuckets is List) {
              _searchBuckets = rawBuckets.map((e) => e.toString()).toList();
            } else {
              _searchBuckets = [];
            }

            final rawTarget = data['target_buckets'];
            if (rawTarget is List) {
              _targetBuckets = rawTarget.map((e) => e.toString()).toList();
            } else {
              _targetBuckets = [];
            }

            final rawLooking = data['looking_for'];
            if (rawLooking is List) {
              _lookingFor = rawLooking.map((e) => e.toString()).toList();
            } else {
              _lookingFor = [];
            }

            final rawActivities = data['activities'];
            if (rawActivities is List) {
              _activities = rawActivities.map((e) => e.toString()).toList();
            } else {
              _activities = [];
            }

            final rawCauses = data['causes_supported'];
            if (rawCauses is List) {
              _causesSupported = rawCauses.map((e) => e.toString()).toList();
            } else {
              _causesSupported = [];
            }

            final rawArtists = data['top_artists'];
            if (rawArtists is List) {
              _topArtists = rawArtists.map((e) => e.toString()).toList();
            } else {
              _topArtists = [];
            }

            final rawTech = data['tech_skills'];
            if (rawTech is List) {
              _techSkills = rawTech.map((e) => e.toString()).toList();
            } else {
              _techSkills = [];
            }

            final rawLanguages = data['languages'];
            if (rawLanguages is List) {
              _languages = rawLanguages.map((e) => e.toString()).toList();
            } else {
              _languages = [];
            }

            final rawPets = data['pets'];
            if (rawPets is List) {
              _pets = rawPets.map((e) => e.toString()).toList();
            } else {
              _pets = [];
            }
          });
        }
      }
    } on Object catch (e) {
      debugPrint('[ProfileTab] Error loading profile details: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveProfileChanges({
    String? name,
    int? age,
    String? displayGender,
    String? displaySexuality,
    List<String>? searchBuckets,
    String? branch,
    int? year,
    String? hometown,
    String? partnerValues,
    String? childrenPlans,
    String? religiousBeliefs,
    String? lifestyle,
    String? drinking,
    String? smoking,
    String? role,
    List<String>? targetBuckets,
    List<String>? lookingFor,
    List<String>? activities,
    List<String>? causesSupported,
    List<String>? topArtists,
    List<String>? techSkills,
    List<String>? languages,
    List<String>? pets,
  }) async {
    setState(() => _isSavingDetails = true);
    try {
      final session = _client.auth.currentSession;
      if (session != null) {
        final config = AppConfig.current;
        final dio = createDio();

        final payload = <String, dynamic>{};
        if (name != null) payload['name'] = name;
        if (age != null) payload['age'] = age;
        if (displayGender != null) payload['display_gender'] = displayGender;
        if (displaySexuality != null) payload['display_sexuality'] = displaySexuality;
        if (searchBuckets != null) payload['search_buckets'] = searchBuckets;
        if (branch != null) payload['branch'] = branch;
        if (year != null) payload['year'] = year;
        if (hometown != null) payload['hometown'] = hometown;
        if (partnerValues != null) payload['partner_values'] = partnerValues;
        if (childrenPlans != null) payload['children_plans'] = childrenPlans;
        if (religiousBeliefs != null) payload['religious_beliefs'] = religiousBeliefs;
        if (lifestyle != null) payload['lifestyle'] = lifestyle;
        if (drinking != null) payload['drinking'] = drinking;
        if (smoking != null) payload['smoking'] = smoking;
        if (role != null) payload['role'] = role;
        if (targetBuckets != null) payload['target_buckets'] = targetBuckets;
        if (lookingFor != null) payload['looking_for'] = lookingFor;
        if (activities != null) payload['activities'] = activities;
        if (causesSupported != null) payload['causes_supported'] = causesSupported;
        if (topArtists != null) payload['top_artists'] = topArtists;
        if (techSkills != null) payload['tech_skills'] = techSkills;
        if (languages != null) payload['languages'] = languages;
        if (pets != null) payload['pets'] = pets;

        // Perform the details secure endpoint update
        if (payload.isNotEmpty) {
          final response = await dio.post<Map<String, dynamic>>(
            '${config.backendUrl}/api/v1/profile/details',
            data: payload,
            options: Options(
              headers: {
                'Authorization': 'Bearer ${session.accessToken}',
              },
            ),
          );

          if (response.statusCode == 200 && mounted) {
            setState(() {
              if (age != null) _savedAge = age;
              if (name != null) _name = name;
              if (displayGender != null) _displayGender = displayGender;
              if (displaySexuality != null) _displaySexuality = displaySexuality;
              if (searchBuckets != null) _searchBuckets = searchBuckets;
              if (branch != null) _location = branch;
              if (year != null) _year = year;
              if (hometown != null) _hometown = hometown;
              if (partnerValues != null) _partnerValues = partnerValues;
              if (childrenPlans != null) _childrenPlans = childrenPlans;
              if (religiousBeliefs != null) _religiousBeliefs = religiousBeliefs;
              if (lifestyle != null) _lifestyle = lifestyle;
              if (drinking != null) _drinking = drinking;
              if (smoking != null) _smoking = smoking;
              if (role != null) _role = role;
              if (targetBuckets != null) _targetBuckets = targetBuckets;
              if (lookingFor != null) _lookingFor = lookingFor;
              if (activities != null) _activities = activities;
              if (causesSupported != null) _causesSupported = causesSupported;
              if (topArtists != null) _topArtists = topArtists;
              if (techSkills != null) _techSkills = techSkills;
              if (languages != null) _languages = languages;
              if (pets != null) _pets = pets;
            });
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF161B26),
              content: const Text(
                'Cosmic frequency synchronized.',
                style: TextStyle(color: Color(0xFFE2D9F3), fontSize: 13),
              ),
              duration: const Duration(seconds: 2),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(20),
            ),
          );
        }
      }
    } on Object catch (e) {
      debugPrint('[ProfileTab] Error saving profile details: $e');
    } finally {
      if (mounted) {
        setState(() => _isSavingDetails = false);
      }
    }
  }


  int _calculateStability() {
    var filled = 0;
    const total = 8;
    if (_name.isNotEmpty) filled++;
    if (_age >= 18) filled++;
    if (_year >= 1 && _year <= 5) filled++;
    if (_pronouns.isNotEmpty) filled++;
    if (_location.isNotEmpty) filled++;
    if (_major.isNotEmpty) filled++;
    if (_selectedTags.isNotEmpty) filled++;
    if (_prompts.any((p) => p['answer']!.isNotEmpty)) filled++;

    return ((filled / total) * 100).round();
  }

  void _showStabilityDetails() {
    unawaited(showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF161B26).withValues(alpha: 0.95),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(30),
              topRight: Radius.circular(30),
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(LucideIcons.activity, color: Color(0xFFFF7597)),
                  SizedBox(width: 12),
                  Text(
                    'Cosmic Stability Report',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Outfit',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Your stability is at ${_calculateStability()}% alignment.',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 12),
              const Text(
                'Complete your signals to increase your matching resonance inside the campus cluster. Each filled parameter refines your cosmic coordinates:',
                style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 16),
              _buildStabilityCriteriaRow(
                icon: LucideIcons.user,
                label: 'Name & Age',
                complete: _name.isNotEmpty && _age >= 18,
              ),
              _buildStabilityCriteriaRow(
                icon: LucideIcons.messageSquare,
                label: 'Pronouns',
                complete: _pronouns.isNotEmpty,
              ),
              _buildStabilityCriteriaRow(
                icon: LucideIcons.mapPin,
                label: 'Campus Location & Year',
                complete: _location.isNotEmpty,
              ),
              _buildStabilityCriteriaRow(
                icon: LucideIcons.graduationCap,
                label: 'Major',
                complete: _major.isNotEmpty,
              ),
              _buildStabilityCriteriaRow(
                icon: LucideIcons.compass,
                label: 'Vibe Orientation',
                complete: true,
              ),
              _buildStabilityCriteriaRow(
                icon: LucideIcons.tags,
                label: 'Interests / Vibe Tags (${_selectedTags.length} mapped)',
                complete: _selectedTags.isNotEmpty,
              ),
              _buildStabilityCriteriaRow(
                icon: LucideIcons.sparkles,
                label: 'Cosmic Echoes (Prompts)',
                complete: _prompts.any((p) => p['answer']!.isNotEmpty),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Acknowledge',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ));
  }

  Widget _buildStabilityCriteriaRow({
    required IconData icon,
    required String label,
    required bool complete,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: complete ? const Color(0xFFFF7597) : Colors.white38,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: complete ? Colors.white70 : Colors.white38,
                fontSize: 13,
                decoration: complete ? null : TextDecoration.lineThrough,
              ),
            ),
          ),
          Icon(
            complete ? LucideIcons.checkCircle : LucideIcons.helpCircle,
            size: 16,
            color: complete ? const Color(0xFF10B981) : Colors.white24,
          ),
        ],
      ),
    );
  }

  void _showAvatarPicker() {
    final emojis = ['🪐', '🚀', '👽', '👾', '🌠', '🌌', '🤖', '👩‍🚀', '🦄', '🎭', '🎧', '🔮'];
    unawaited(showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF161B26).withValues(alpha: 0.95),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(30),
              topRight: Radius.circular(30),
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(LucideIcons.user, color: Color(0xFFFF7597)),
                  SizedBox(width: 12),
                  Text(
                    'Select Profile Frequency Node',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Outfit',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Select a representative cosmic symbol to represent your avatar frequency across the cluster.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 180,
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: emojis.length,
                  itemBuilder: (context, index) {
                    final emoji = emojis[index];
                    final isSelected = emoji == _selectedAvatarEmoji;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedAvatarEmoji = emoji;
                        });
                        Navigator.pop(context);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF7C3AED).withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected ? const Color(0xFF7C3AED) : Colors.white.withValues(alpha: 0.1),
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 28),
                          ),
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
    ));
  }

  void _showImageSlotPicker(int slotIndex) {
    final themes = [
      const CosmicTheme(
        name: 'Nebula Glow',
        gradient: LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFFFF7597)]),
        icon: LucideIcons.sparkles,
      ),
      const CosmicTheme(
        name: 'Supernova',
        gradient: LinearGradient(colors: [Color(0xFFFF7597), Color(0xFFF59E0B)]),
        icon: LucideIcons.zap,
      ),
      const CosmicTheme(
        name: 'Deep Void',
        gradient: LinearGradient(colors: [Color(0xFF0F172A), Color(0xFF3B82F6)]),
        icon: LucideIcons.orbit,
      ),
      const CosmicTheme(
        name: 'Cosmic Dust',
        gradient: LinearGradient(colors: [Color(0xFF10B981), Color(0xFF06B6D4)]),
        icon: LucideIcons.leaf,
      ),
    ];

    unawaited(showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF161B26).withValues(alpha: 0.95),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(30),
              topRight: Radius.circular(30),
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(LucideIcons.image, color: Color(0xFFFF7597)),
                  const SizedBox(width: 12),
                  Text(
                    'Load Cosmic Badge - Slot ${slotIndex + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Outfit',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Sync a high-fidelity vibe badge into your visual slot. This represents your aesthetic frequency.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 20),
              Column(
                children: List.generate(themes.length, (idx) {
                  final theme = themes[idx];
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      setState(() {
                        _slotStates[slotIndex] = 1;
                      });
                      Timer(const Duration(milliseconds: 800), () {
                        if (mounted) {
                          setState(() {
                            _slotStates[slotIndex] = 2;
                            _slotGradients[slotIndex] = theme.gradient;
                            _slotIcons[slotIndex] = theme.icon;
                          });
                        }
                      });
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              gradient: theme.gradient,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(theme.icon, color: Colors.white, size: 20),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              theme.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                fontFamily: 'Outfit',
                              ),
                            ),
                          ),
                          const Icon(LucideIcons.chevronRight, color: Colors.white30, size: 18),
                        ],
                      ),
                    ),
                  );
                }),
              ),
              if (_slotStates[slotIndex] == 2) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(color: Colors.redAccent),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () {
                      setState(() {
                        _slotStates[slotIndex] = 0;
                        _slotGradients[slotIndex] = const LinearGradient(colors: [Colors.transparent, Colors.transparent]);
                        _slotIcons[slotIndex] = LucideIcons.image;
                      });
                      Navigator.pop(context);
                    },
                    icon: const Icon(LucideIcons.trash2, size: 16),
                    label: const Text('Clear Slot Badge'),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    ));
  }

  void _shufflePrompt() {
    setState(() {
      _shuffleRotation += 1;
      _currentPromptIndex = (_currentPromptIndex + 1) % _prompts.length;
    });
    unawaited(_pageController.animateToPage(
      _currentPromptIndex,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOutCubic,
    ));
  }

  String _capitalize(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }

  Widget _buildUniverseSection({
    required IconData icon,
    required String title,
    required String description,
    required Widget child,
  }) {
    const deepPurple = Color(0xFF7C3AED);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF161B26).withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: deepPurple.withValues(alpha: 0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: deepPurple.withValues(alpha: 0.05),
            blurRadius: 15,
            spreadRadius: 2,
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: const Color(0xFFFF7597),
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFFE2D9F3),
                        fontSize: 15,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Outfit',
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const pulsarPink = Color(0xFFFF7597);
    const deepPurple = Color(0xFF7C3AED);
    const mistLavender = Color(0xFFE2D9F3);
    final config = AppConfig.current;

    final pulseController = _pulseController;
    final rotationController = _rotationController;

    if (_isLoading || pulseController == null || rotationController == null) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(pulsarPink),
        ),
      );
    }

    final stabilityFraction = _calculateStability() / 100;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_isSavingDetails)
          const LinearProgressIndicator(
            backgroundColor: Colors.transparent,
            valueColor: AlwaysStoppedAnimation<Color>(pulsarPink),
            minHeight: 2,
          ),
        Expanded(
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 110),
            children: [
              // 🪐 1. Redesigned Glowing Profile Header
              Center(
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: _showAvatarPicker,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Rotating Dashed Orbit Ring
                          AnimatedBuilder(
                            animation: rotationController,
                            builder: (context, child) {
                              return CustomPaint(
                                size: const Size(136, 136),
                                painter: OrbitPainter(
                                  color: deepPurple,
                                  progress: rotationController.value,
                                ),
                              );
                            },
                          ),
                          // Inner Pulsing Glow
                          AnimatedBuilder(
                            animation: pulseController,
                            builder: (context, child) {
                              return Container(
                                width: 108,
                                height: 108,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: pulsarPink.withValues(alpha: 0.3 * pulseController.value),
                                      blurRadius: 15 + 10 * pulseController.value,
                                      spreadRadius: 1 + 3 * pulseController.value,
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          // Main Avatar Circle
                          Container(
                            width: 104,
                            height: 104,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [Color(0xFF161B26), Color(0xFF0F0F23)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              border: Border.all(
                                color: pulsarPink.withValues(alpha: 0.6),
                                width: 2,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                _selectedAvatarEmoji,
                                style: const TextStyle(fontSize: 44),
                              ),
                            ),
                          ),
                          // Edit Badge
                          Positioned(
                            right: 4,
                            bottom: 4,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: pulsarPink,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                LucideIcons.user,
                                size: 12,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Hey, $_name.',
                      style: const TextStyle(
                        fontFamily: 'Outfit',
                        fontSize: 24,
                        fontWeight: FontWeight.w300,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Currently floating in the Nebula.',
                      style: TextStyle(
                        fontFamily: 'Outfit',
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.4),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Redesigned Stability Tracker Card
                    GestureDetector(
                      onTap: _showStabilityDetails,
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 20),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161B26).withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      LucideIcons.activity,
                                      color: pulsarPink,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'System Stability',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.6),
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: pulsarPink.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${_calculateStability()}% Mapped',
                                    style: const TextStyle(
                                      color: pulsarPink,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Container(
                              height: 12,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                              ),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final progressWidth = constraints.maxWidth * stabilityFraction;
                                  return Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      AnimatedContainer(
                                        duration: const Duration(milliseconds: 400),
                                        width: progressWidth,
                                        height: double.infinity,
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            colors: [deepPurple, pulsarPink],
                                          ),
                                          borderRadius: BorderRadius.circular(6),
                                          boxShadow: [
                                            BoxShadow(
                                              color: pulsarPink.withValues(alpha: 0.3),
                                              blurRadius: 8,
                                              spreadRadius: 1,
                                            )
                                          ],
                                        ),
                                      ),
                                      Positioned(
                                        left: progressWidth - 6,
                                        top: -1,
                                        child: AnimatedBuilder(
                                          animation: pulseController,
                                          builder: (context, child) {
                                            return Container(
                                              width: 14,
                                              height: 14,
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                shape: BoxShape.circle,
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: pulsarPink.withValues(alpha: (0.6 * pulseController.value) + 0.4),
                                                    blurRadius: 6 + 4 * pulseController.value,
                                                    spreadRadius: 1 + 2 * pulseController.value,
                                                  )
                                                ],
                                              ),
                                              child: Center(
                                                child: Container(
                                                  width: 6,
                                                  height: 6,
                                                  decoration: const BoxDecoration(
                                                    color: pulsarPink,
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // 🌌 2. Custom Universe Cards (Always Expanded)
              // Card Layer A: The Core Signal
              _buildUniverseSection(
                icon: LucideIcons.user,
                title: 'The Core Signal',
                description: 'Essential dimensional settings',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Display Name (moved to 1st field)
                    GlassTextField(
                      label: 'Display Name',
                      initialValue: _name,
                      hintText: 'Enter your cosmic display name',
                      prefixIcon: LucideIcons.user,
                      onChanged: (val) {
                        setState(() => _name = val);
                      },
                      onFieldSubmitted: (val) {
                        unawaited(_saveProfileChanges(name: val));
                      },
                    ),

                    // Age slider (Neon theme)
                    NeonSlider(
                      value: _age.toDouble(),
                      min: 18,
                      max: 27,
                      divisions: 9,
                      label: 'Age',
                      onChanged: (val) {
                        setState(() {
                          _age = val.round();
                          _ageChangedSinceInteract = _age != _savedAge;
                        });
                      },
                    ),
                    if (_ageChangedSinceInteract) ...[
                      const SizedBox(height: 8),
                      Center(
                        child: AnimatedSize(
                          duration: const Duration(milliseconds: 200),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF7C3AED),
                                foregroundColor: Colors.white,
                                shadowColor: const Color(0xFFFF7597).withValues(alpha: 0.5),
                                elevation: 8,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: const BorderSide(color: Color(0xFFFF7597)),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              onPressed: () {
                                setState(() {
                                  _ageChangedSinceInteract = false;
                                });
                                unawaited(_saveProfileChanges(age: _age));
                              },
                              icon: const Icon(LucideIcons.checkCircle, size: 16),
                              label: Text(
                                'Confirm Age Update to $_age',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  letterSpacing: 0.5,
                                  fontFamily: 'Outfit',
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),

                    // display_gender & display_sexuality selector tiles
                    Row(
                      children: [
                        Expanded(
                          child: _buildSelectorTile(
                            label: 'GENDER',
                            value: _displayGender,
                            icon: LucideIcons.user,
                            onTap: () {
                              _openSelectionOverlay(
                                title: 'Gender',
                                options: const [
                                  'Man',
                                  'Woman',
                                  'Non-binary',
                                  'Genderqueer',
                                  'Genderfluid',
                                  'Agender',
                                  'Transgender Man',
                                  'Transgender Woman',
                                  'Bigender',
                                  'Two-Spirit',
                                  'Demiboy',
                                  'Demigirl',
                                  'Queer',
                                  'Questioning',
                                  'Prefer not to say'
                                ],
                                currentValue: _displayGender,
                                onSelected: (val) {
                                  unawaited(_saveProfileChanges(displayGender: val));
                                },
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildSelectorTile(
                            label: 'SEXUALITY',
                            value: _displaySexuality,
                            icon: LucideIcons.heart,
                            onTap: () {
                              _openSelectionOverlay(
                                title: 'Sexuality',
                                options: const [
                                  'Straight',
                                  'Gay',
                                  'Lesbian',
                                  'Bisexual',
                                  'Pansexual',
                                  'Asexual',
                                  'Demisexual',
                                  'Queer',
                                  'Questioning',
                                  'Prefer not to say'
                                ],
                                currentValue: _displaySexuality,
                                onSelected: (val) {
                                  unawaited(_saveProfileChanges(displaySexuality: val));
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // search_buckets multiple option choice
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SEARCH COHORTS',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Who is allowed to discover you in search',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.3),
                            fontSize: 10,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _buildBucketChip(label: 'Men', value: 'M'),
                            const SizedBox(width: 8),
                            _buildBucketChip(label: 'Women', value: 'F'),
                            const SizedBox(width: 8),
                            _buildBucketChip(label: 'Non-Binary', value: 'NB'),
                            const SizedBox(width: 8),
                            _buildBucketChip(label: 'Queer', value: 'Q'),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Pronoun chips selector
                    SegmentedChipSelector(
                      options: const ['they/them', 'she/her', 'he/him', 'custom'],
                      selectedValue: _pronouns,
                      onSelected: (val) {
                        setState(() => _pronouns = val);
                      },
                    ),
                    const SizedBox(height: 16),



                    // Interactive image slots with glowing style
                    Text(
                      'Image Assets & Badges',
                      style: TextStyle(
                        color: mistLavender.withValues(alpha: 0.6),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(4, (index) {
                        final state = _slotStates[index];
                        final gradient = _slotGradients[index];
                        final icon = _slotIcons[index];

                        return Expanded(
                          child: GestureDetector(
                            onTap: () => _showImageSlotPicker(index),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              height: 72,
                              margin: EdgeInsets.only(
                                left: index == 0 ? 0 : 4,
                                right: index == 3 ? 0 : 4,
                              ),
                              decoration: BoxDecoration(
                                gradient: state == 2 ? gradient : null,
                                color: state == 2 ? null : Colors.white.withValues(alpha: 0.03),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: state == 2 ? Colors.transparent : Colors.white.withValues(alpha: 0.12),
                                ),
                                boxShadow: state == 2
                                    ? [
                                        BoxShadow(
                                          color: gradient.colors.last.withValues(alpha: 0.3),
                                          blurRadius: 8,
                                          spreadRadius: 1,
                                        )
                                      ]
                                    : [],
                              ),
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(20),
                                        gradient: LinearGradient(
                                          colors: [
                                            Colors.white.withValues(alpha: 0.08),
                                            Colors.transparent,
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Center(
                                    child: state == 1
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor: AlwaysStoppedAnimation<Color>(pulsarPink),
                                            ),
                                          )
                                        : Icon(
                                            icon,
                                            color: state == 2 ? Colors.white : Colors.white24,
                                            size: 22,
                                          ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),

              // Card Layer B: Field Vectors
              _buildUniverseSection(
                icon: LucideIcons.compass,
                title: 'Field Vectors',
                description: 'Polymorphic match preferences',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GlassTextField(
                      label: 'Major',
                      initialValue: _major,
                      hintText: 'Fields of study being decoded...',
                      prefixIcon: LucideIcons.graduationCap,
                      onChanged: (val) {
                        setState(() => _major = val);
                      },
                    ),
                    const SizedBox(height: 12),

                    // Role Selector
                    _buildSelectorTile(
                      label: 'ROLE',
                      value: _role,
                      icon: LucideIcons.briefcase,
                      onTap: () {
                        _openSelectionOverlay(
                          title: 'Role',
                          options: const [
                            'Student',
                            'Alumni',
                            'Faculty',
                            'Staff',
                            'Researcher',
                            'Founder',
                            'Not specified'
                          ],
                          currentValue: _role,
                          onSelected: (val) {
                            unawaited(_saveProfileChanges(role: val));
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 16),

                    // Custom Radio Buttons for Vibe Orientation Mode
                    Text(
                      'Vibe Frequency Mode',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    NeonRadioButton<String>(
                      value: 'chill',
                      groupValue: _vibeMode,
                      label: 'Chill Frequency',
                      description: 'Lowkey ambient signals. Perfect for library basement study dates.',
                      onChanged: (val) => setState(() => _vibeMode = val),
                    ),
                    NeonRadioButton<String>(
                      value: 'deep',
                      groupValue: _vibeMode,
                      label: 'Deep Frequency',
                      description: 'Deep dives, analog synthesizers, hackathons, and creative coding.',
                      onChanged: (val) => setState(() => _vibeMode = val),
                    ),
                    NeonRadioButton<String>(
                      value: 'chaos',
                      groupValue: _vibeMode,
                      label: 'Chaos Frequency',
                      description: 'High energy, rave signals, hyperpop, and spontaneous quests.',
                      onChanged: (val) => setState(() => _vibeMode = val),
                    ),
                    NeonRadioButton<String>(
                      value: 'open',
                      groupValue: _vibeMode,
                      label: 'Open Frequency',
                      description: 'Unrestricted signal band. Harmonizes with all active users.',
                      onChanged: (val) => setState(() => _vibeMode = val),
                    ),
                    const SizedBox(height: 16),

                    // target_buckets multiple option choice
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TARGET COHORTS',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Who you want to see/match with in discovery',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.3),
                            fontSize: 10,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _buildTargetBucketChip(label: 'Men', value: 'M'),
                            const SizedBox(width: 8),
                            _buildTargetBucketChip(label: 'Women', value: 'F'),
                            const SizedBox(width: 8),
                            _buildTargetBucketChip(label: 'Non-Binary', value: 'NB'),
                            const SizedBox(width: 8),
                            _buildTargetBucketChip(label: 'Open', value: 'Open'),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // tech_skills tag editor
                    _buildTagChipsEditor(
                      label: 'Tech Skills',
                      currentValues: _techSkills,
                      presets: const ['Flutter', 'Python', 'Machine Learning', 'UI/UX Design', 'Cloud Architecture', 'Rust', 'TypeScript', 'Docker'],
                      onChanged: (val) {
                        setState(() => _techSkills = val);
                        unawaited(_saveProfileChanges(techSkills: val));
                      },
                      hintText: 'Add custom tech skill...',
                    ),

                    // Floating clusters of chips categorized
                    ..._tagsByCategory.entries.map((entry) {
                      final category = entry.key;
                      final tags = entry.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _capitalize(category),
                              style: TextStyle(
                                color: mistLavender.withValues(alpha: 0.4),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: tags.map((tag) {
                                final isSelected = _selectedTags.contains(tag);
                                return GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      if (isSelected) {
                                        _selectedTags.remove(tag);
                                      } else {
                                        _selectedTags.add(tag);
                                      }
                                    });
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? deepPurple.withValues(alpha: 0.2)
                                          : Colors.white.withValues(alpha: 0.03),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: isSelected
                                            ? deepPurple.withValues(alpha: 0.6)
                                            : Colors.white.withValues(alpha: 0.12),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          tag,
                                          style: TextStyle(
                                            color: isSelected ? Colors.white : Colors.white60,
                                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                            fontSize: 12,
                                            fontFamily: 'Outfit',
                                          ),
                                        ),
                                        if (isSelected) ...[
                                          const SizedBox(width: 4),
                                          const Icon(
                                            LucideIcons.checkCircle,
                                            color: pulsarPink,
                                            size: 12,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),

              // Card Layer C: Social Coordinates
              _buildUniverseSection(
                icon: LucideIcons.globe,
                title: 'Social Coordinates',
                description: 'Space-time cluster orientation',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GlassTextField(
                      label: 'Campus Location',
                      initialValue: _location,
                      hintText: 'Enter campus name...',
                      prefixIcon: LucideIcons.mapPin,
                      onChanged: (val) {
                        setState(() => _location = val);
                      },
                      onFieldSubmitted: (val) {
                        unawaited(_saveProfileChanges(branch: val));
                      },
                    ),
                    const SizedBox(height: 12),

                    // Campus Year Selector
                    _buildSelectorTile(
                      label: 'CAMPUS YEAR',
                      value: 'Year $_year',
                      icon: LucideIcons.calendar,
                      onTap: () {
                        _openSelectionOverlay(
                          title: 'Campus Year',
                          options: const ['1', '2', '3', '4', '5'],
                          currentValue: _year.toString(),
                          onSelected: (val) {
                            unawaited(_saveProfileChanges(year: int.parse(val)));
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 16),

                    GlassTextField(
                      label: 'Hometown',
                      initialValue: _hometown,
                      hintText: 'Where are you originally from?',
                      prefixIcon: LucideIcons.home,
                      onChanged: (val) {
                        setState(() => _hometown = val);
                      },
                      onFieldSubmitted: (val) {
                        unawaited(_saveProfileChanges(hometown: val));
                      },
                    ),
                    const SizedBox(height: 16),

                    // Languages tag editor
                    _buildTagChipsEditor(
                      label: 'Languages',
                      currentValues: _languages,
                      presets: const ['English', 'Spanish', 'Mandarin', 'French', 'German', 'Japanese', 'Hindi', 'Arabic'],
                      onChanged: (val) {
                        setState(() => _languages = val);
                        unawaited(_saveProfileChanges(languages: val));
                      },
                      hintText: 'Add custom language...',
                    ),
                  ],
                ),
              ),

              // Card Layer D: Lifestyle & Resonance
              _buildUniverseSection(
                icon: LucideIcons.heart,
                title: 'Lifestyle & Resonance',
                description: 'Daily frequency parameters',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GlassTextField(
                      label: 'Lifestyle Description',
                      initialValue: _lifestyle,
                      hintText: 'Describe your daily routine/vibe...',
                      prefixIcon: LucideIcons.activity,
                      onChanged: (val) {
                        setState(() => _lifestyle = val);
                      },
                      onFieldSubmitted: (val) {
                        unawaited(_saveProfileChanges(lifestyle: val));
                      },
                    ),
                    const SizedBox(height: 16),

                    // Drinking and Smoking
                    Row(
                      children: [
                        Expanded(
                          child: _buildSelectorTile(
                            label: 'DRINKING',
                            value: _drinking,
                            icon: LucideIcons.glassWater,
                            onTap: () {
                              _openSelectionOverlay(
                                title: 'Drinking',
                                options: const ['Never', 'Socially', 'Often', 'Not specified'],
                                currentValue: _drinking,
                                onSelected: (val) {
                                  unawaited(_saveProfileChanges(drinking: val));
                                },
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildSelectorTile(
                            label: 'SMOKING',
                            value: _smoking,
                            icon: LucideIcons.cigarette,
                            onTap: () {
                              _openSelectionOverlay(
                                title: 'Smoking',
                                options: const ['Never', 'Socially', 'Often', 'Not specified'],
                                currentValue: _smoking,
                                onSelected: (val) {
                                  unawaited(_saveProfileChanges(smoking: val));
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Children Plans and Religious Beliefs
                    Row(
                      children: [
                        Expanded(
                          child: _buildSelectorTile(
                            label: 'CHILDREN PLANS',
                            value: _childrenPlans,
                            icon: LucideIcons.baby,
                            onTap: () {
                              _openSelectionOverlay(
                                title: 'Children Plans',
                                options: const ['Want kids', "Don't want kids", 'Undecided', 'Not specified'],
                                currentValue: _childrenPlans,
                                onSelected: (val) {
                                  unawaited(_saveProfileChanges(childrenPlans: val));
                                },
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildSelectorTile(
                            label: 'RELIGIOUS BELIEFS',
                            value: _religiousBeliefs,
                            icon: LucideIcons.sparkles,
                            onTap: () {
                              _openSelectionOverlay(
                                title: 'Religious Beliefs',
                                options: const ['Atheist', 'Agnostic', 'Spiritual', 'Christian', 'Muslim', 'Jewish', 'Hindu', 'Buddhist', 'Other', 'Not specified'],
                                currentValue: _religiousBeliefs,
                                onSelected: (val) {
                                  unawaited(_saveProfileChanges(religiousBeliefs: val));
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    GlassTextField(
                      label: 'Partner Values',
                      initialValue: _partnerValues,
                      hintText: 'What qualities/values do you prioritize in a partner?',
                      prefixIcon: LucideIcons.users,
                      onChanged: (val) {
                        setState(() => _partnerValues = val);
                      },
                      onFieldSubmitted: (val) {
                        unawaited(_saveProfileChanges(partnerValues: val));
                      },
                    ),
                    const SizedBox(height: 16),

                    // Pets tag editor
                    _buildTagChipsEditor(
                      label: 'Pets',
                      currentValues: _pets,
                      presets: const ['Dog', 'Cat', 'Bird', 'Fish', 'Reptile', 'Rabbit', 'No Pets'],
                      onChanged: (val) {
                        setState(() => _pets = val);
                        unawaited(_saveProfileChanges(pets: val));
                      },
                      hintText: 'Add custom pet...',
                    ),
                  ],
                ),
              ),

              // Card Layer E: Affinity & Interests
              _buildUniverseSection(
                icon: LucideIcons.tags,
                title: 'Affinity & Interests',
                description: 'Interstellar alignments',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Looking For tag editor
                    _buildTagChipsEditor(
                      label: 'Looking For',
                      currentValues: _lookingFor,
                      presets: const ['Long-term connection', 'Short-term connection', 'Study partner', 'Networking', 'Casual dating', 'Deep conversations'],
                      onChanged: (val) {
                        setState(() => _lookingFor = val);
                        unawaited(_saveProfileChanges(lookingFor: val));
                      },
                      hintText: 'Add custom goal...',
                    ),

                    // Activities tag editor
                    _buildTagChipsEditor(
                      label: 'Activities',
                      currentValues: _activities,
                      presets: const ['Coding', 'Gaming', 'Reading', 'Music', 'Hiking', 'Cooking', 'Traveling', 'Art'],
                      onChanged: (val) {
                        setState(() => _activities = val);
                        unawaited(_saveProfileChanges(activities: val));
                      },
                      hintText: 'Add custom activity...',
                    ),

                    // Causes Supported tag editor
                    _buildTagChipsEditor(
                      label: 'Causes Supported',
                      currentValues: _causesSupported,
                      presets: const ['Climate Action', 'Tech Ethics', 'Mental Health', 'LGBTQ+ Rights', 'Education Access', 'Animal Protection'],
                      onChanged: (val) {
                        setState(() => _causesSupported = val);
                        unawaited(_saveProfileChanges(causesSupported: val));
                      },
                      hintText: 'Add custom cause...',
                    ),

                    // Top Artists List
                    Text(
                      'TOP ARTISTS',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_topArtists.isNotEmpty) ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _topArtists.map((artist) {
                          return Chip(
                            backgroundColor: const Color(0xFF7C3AED).withValues(alpha: 0.15),
                            side: const BorderSide(color: Color(0xFFFF7597), width: 0.8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            label: Text(artist, style: const TextStyle(color: Colors.white, fontSize: 11)),
                            deleteIcon: const Icon(LucideIcons.x, size: 12, color: Colors.white70),
                            onDeleted: () {
                              final updated = List<String>.from(_topArtists)..remove(artist);
                              setState(() => _topArtists = updated);
                              unawaited(_saveProfileChanges(topArtists: updated));
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.02),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                            ),
                            child: TextField(
                              controller: _artistInputController,
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                              decoration: InputDecoration(
                                hintText: 'Type artist name and press Enter...',
                                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 11),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                border: InputBorder.none,
                              ),
                              onSubmitted: (val) {
                                final trimmed = val.trim();
                                if (trimmed.isNotEmpty && !_topArtists.contains(trimmed)) {
                                  final updated = List<String>.from(_topArtists)..add(trimmed);
                                  setState(() {
                                    _topArtists = updated;
                                    _artistInputController.clear();
                                  });
                                  unawaited(_saveProfileChanges(topArtists: updated));
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Card Layer F: Cosmic Echoes
              _buildUniverseSection(
                icon: LucideIcons.sparkles,
                title: 'Cosmic Echoes',
                description: 'Semantic dimensional prompts',
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Echo Chamber Signal',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                        GestureDetector(
                          onTap: _shufflePrompt,
                          child: Row(
                            children: [
                              Text(
                                'Shuffle',
                                style: TextStyle(
                                  color: pulsarPink.withValues(alpha: 0.8),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 6),
                              AnimatedRotation(
                                turns: _shuffleRotation,
                                duration: const Duration(milliseconds: 500),
                                child: Icon(
                                  LucideIcons.sparkles,
                                  color: pulsarPink.withValues(alpha: 0.8),
                                  size: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 190,
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: _prompts.length,
                        onPageChanged: (index) {
                          setState(() {
                            _currentPromptIndex = index;
                          });
                        },
                        itemBuilder: (context, index) {
                          final prompt = _prompts[index];
                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.03),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      LucideIcons.messageSquare,
                                      color: pulsarPink,
                                      size: 14,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        prompt['question']!,
                                        style: const TextStyle(
                                          color: mistLavender,
                                          fontSize: 13,
                                          fontStyle: FontStyle.italic,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Expanded(
                                  child: TextFormField(
                                    initialValue: prompt['answer'],
                                    maxLines: 4,
                                    onChanged: (val) {
                                      setState(() {
                                        prompt['answer'] = val;
                                      });
                                    },
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                      height: 1.4,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: "no echoes recorded yet. map a thought when you're ready.",
                                      hintStyle: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.3),
                                        fontSize: 12,
                                      ),
                                      border: InputBorder.none,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Prompt page dots indicators
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(_prompts.length, (index) {
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: _currentPromptIndex == index ? 16 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: _currentPromptIndex == index
                                ? pulsarPink
                                : Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Export code card if flavor variant
              if (config.isFlavorVariant) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: ExportCodeCard(),
                ),
                const SizedBox(height: 20),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSelectorTile({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    const pulsarPink = Color(0xFFFF7597);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Row(
              children: [
                Icon(icon, color: Colors.white38, size: 16),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'Outfit',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(
                  LucideIcons.chevronRight,
                  color: pulsarPink,
                  size: 14,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _openSelectionOverlay({
    required String title,
    required List<String> options,
    required String currentValue,
    required ValueChanged<String> onSelected,
  }) {
    unawaited(showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: title,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) {
        return CosmicSelectionOverlay(
          title: title,
          options: options,
          currentValue: currentValue,
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return FadeTransition(
          opacity: anim1,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1).animate(
              CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
    ).then((selected) {
      if (selected != null && mounted) {
        onSelected(selected);
      }
    }));
  }

  Widget _buildBucketChip({required String label, required String value}) {
    final isSelected = _searchBuckets.contains(value);
    const pulsarPink = Color(0xFFFF7597);
    const deepPurple = Color(0xFF7C3AED);

    return Expanded(
      child: GestureDetector(
        onTap: () {
          final updatedBuckets = List<String>.from(_searchBuckets);
          if (isSelected) {
            updatedBuckets.remove(value);
          } else {
            updatedBuckets.add(value);
          }
          setState(() {
            _searchBuckets = updatedBuckets;
          });
          unawaited(_saveProfileChanges(searchBuckets: updatedBuckets));
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? deepPurple.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? pulsarPink.withValues(alpha: 0.8) : Colors.white.withValues(alpha: 0.1),
              width: isSelected ? 1.5 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: pulsarPink.withValues(alpha: 0.1),
                      blurRadius: 8,
                    )
                  ]
                : [],
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white60,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 11,
                fontFamily: 'Outfit',
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTargetBucketChip({required String label, required String value}) {
    final isSelected = _targetBuckets.contains(value);
    const pulsarPink = Color(0xFFFF7597);
    const deepPurple = Color(0xFF7C3AED);

    return Expanded(
      child: GestureDetector(
        onTap: () {
          final updatedBuckets = List<String>.from(_targetBuckets);
          if (isSelected) {
            updatedBuckets.remove(value);
          } else {
            updatedBuckets.add(value);
          }
          setState(() {
            _targetBuckets = updatedBuckets;
          });
          unawaited(_saveProfileChanges(targetBuckets: updatedBuckets));
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? deepPurple.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? pulsarPink.withValues(alpha: 0.8) : Colors.white.withValues(alpha: 0.1),
              width: isSelected ? 1.5 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: pulsarPink.withValues(alpha: 0.1),
                      blurRadius: 8,
                    )
                  ]
                : [],
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white60,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 11,
                fontFamily: 'Outfit',
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTagChipsEditor({
    required String label,
    required List<String> currentValues,
    required List<String> presets,
    required ValueChanged<List<String>> onChanged,
    required String hintText,
  }) {
    const pulsarPink = Color(0xFFFF7597);
    const deepPurple = Color(0xFF7C3AED);

    final allTags = (List<String>.from(presets)..addAll(currentValues)).toSet().toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: allTags.map((tag) {
            final isSelected = currentValues.contains(tag);
            return GestureDetector(
              onTap: () {
                final updated = List<String>.from(currentValues);
                if (isSelected) {
                  updated.remove(tag);
                } else {
                  updated.add(tag);
                }
                onChanged(updated);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected ? deepPurple.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected ? pulsarPink.withValues(alpha: 0.8) : Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tag,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white60,
                        fontSize: 11,
                        fontFamily: 'Outfit',
                      ),
                    ),
                    if (isSelected) ...[
                      const SizedBox(width: 4),
                      const Icon(LucideIcons.checkCircle, color: pulsarPink, size: 10),
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Container(
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.02),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: TextField(
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: hintText,
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 11),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: InputBorder.none,
                  ),
                  onSubmitted: (val) {
                    final trimmed = val.trim();
                    if (trimmed.isNotEmpty && !currentValues.contains(trimmed)) {
                      final updated = List<String>.from(currentValues)..add(trimmed);
                      onChanged(updated);
                    }
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class CosmicSelectionOverlay extends StatefulWidget {
  const CosmicSelectionOverlay({
    required this.title,
    required this.options,
    required this.currentValue,
    super.key,
  });

  final String title;
  final List<String> options;
  final String currentValue;

  @override
  State<CosmicSelectionOverlay> createState() => _CosmicSelectionOverlayState();
}

class _CosmicSelectionOverlayState extends State<CosmicSelectionOverlay> {
  String _searchQuery = '';
  late List<String> _filteredOptions;


  @override
  void initState() {
    super.initState();
    _filteredOptions = widget.options;
  }

  void _filterOptions(String query) {
    setState(() {
      _searchQuery = query;
      _filteredOptions = widget.options
          .where((opt) => opt.toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    const pulsarPink = Color(0xFFFF7597);
    const deepPurple = Color(0xFF7C3AED);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Outfit',
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Select your dimensional coordinates',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.x, color: Colors.white70),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // Search Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: GlassTextField(
                  label: 'Search Option',
                  initialValue: _searchQuery,
                  hintText: 'Type to filter options...',
                  prefixIcon: LucideIcons.search,
                  onChanged: _filterOptions,
                ),
              ),

              // Options List
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  physics: const BouncingScrollPhysics(),
                  itemCount: _filteredOptions.length,
                  itemBuilder: (context, index) {
                    final option = _filteredOptions[index];
                    final isSelected = option == widget.currentValue;

                    return GestureDetector(
                      onTap: () => Navigator.pop(context, option),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? deepPurple.withValues(alpha: 0.15)
                              : Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected
                                ? pulsarPink.withValues(alpha: 0.8)
                                : Colors.white.withValues(alpha: 0.08),
                            width: isSelected ? 1.5 : 1,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: pulsarPink.withValues(alpha: 0.15),
                                    blurRadius: 10,
                                    spreadRadius: 1,
                                  )
                                ]
                              : [],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              option,
                              style: TextStyle(
                                color: isSelected ? Colors.white : Colors.white70,
                                fontSize: 14,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                fontFamily: 'Outfit',
                              ),
                            ),
                            if (isSelected)
                              const Icon(
                                LucideIcons.check,
                                color: pulsarPink,
                                size: 18,
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
        ),
      ),
    );
  }
}


class OrbitPainter extends CustomPainter {
  OrbitPainter({required this.color, required this.progress});

  final Color color;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Draw background ring
    final paint = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(center, radius, paint);

    // Draw rotating dashed elements
    final dashedPaint = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final circumference = 2 * math.pi * radius;
    const double dashLength = 10;
    const double gapLength = 8;
    final sweepAngle = (dashLength / circumference) * 2 * math.pi;
    final gapAngle = (gapLength / circumference) * 2 * math.pi;

    final dashCount = (2 * math.pi / (sweepAngle + gapAngle)).floor();
    final rotationAngle = progress * 2 * math.pi;

    for (var i = 0; i < dashCount; i++) {
      final startAngle = rotationAngle + i * (sweepAngle + gapAngle);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        dashedPaint,
      );
    }

    // Draw 3 orbiting glowing nodes
    final nodePaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final shadowPaint = Paint()
      ..color = color.withValues(alpha: 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)
      ..style = PaintingStyle.fill;

    for (var i = 0; i < 3; i++) {
      final angle = rotationAngle + (i * 2 * math.pi / 3);
      final x = center.dx + radius * math.cos(angle);
      final y = center.dy + radius * math.sin(angle);
      final nodeOffset = Offset(x, y);

      // Shadow glow and main node
      canvas
        ..drawCircle(nodeOffset, 6, shadowPaint)
        ..drawCircle(nodeOffset, 3.5, nodePaint);
    }
  }

  @override
  bool shouldRepaint(covariant OrbitPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

class GlassTextField extends StatefulWidget {
  const GlassTextField({
    required this.label,
    required this.initialValue,
    required this.hintText,
    required this.prefixIcon,
    required this.onChanged,
    this.onFieldSubmitted,
    super.key,
  });

  final String label;
  final String initialValue;
  final String hintText;
  final IconData prefixIcon;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onFieldSubmitted;

  @override
  State<GlassTextField> createState() => _GlassTextFieldState();
}

class _GlassTextFieldState extends State<GlassTextField> {
  late TextEditingController _controller;
  final _focusNode = FocusNode();
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _focusNode.addListener(() {
      setState(() {
        _isFocused = _focusNode.hasFocus;
      });
      if (!_focusNode.hasFocus) {
        widget.onFieldSubmitted?.call(_controller.text);
      }
    });
  }

  @override
  void didUpdateWidget(covariant GlassTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != _controller.text && !_focusNode.hasFocus) {
      _controller.text = widget.initialValue;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const pulsarPink = Color(0xFFFF7597);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: _isFocused ? 0.08 : 0.03),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _isFocused
                    ? pulsarPink.withValues(alpha: 0.8)
                    : Colors.white.withValues(alpha: 0.12),
                width: _isFocused ? 1.5 : 1,
              ),
              boxShadow: _isFocused
                  ? [
                      BoxShadow(
                        color: pulsarPink.withValues(alpha: 0.15),
                        blurRadius: 10,
                        spreadRadius: 1,
                      )
                    ]
                  : [],
            ),
            child: TextFormField(
              controller: _controller,
              focusNode: _focusNode,
              onChanged: widget.onChanged,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'Outfit',
                fontSize: 14,
              ),
              decoration: InputDecoration(
                prefixIcon: Icon(
                  widget.prefixIcon,
                  color: _isFocused ? pulsarPink : Colors.white38,
                  size: 18,
                ),
                hintText: widget.hintText,
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontSize: 14,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class NeonSlider extends StatelessWidget {
  const NeonSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.label,
    required this.onChanged,
    this.onChangeEnd,
    super.key,
  });

  final double value;
  final double min;
  final double max;
  final int divisions;
  final String label;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    const pulsarPink = Color(0xFFFF7597);
    const deepPurple = Color(0xFF7C3AED);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: pulsarPink.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: pulsarPink.withValues(alpha: 0.3)),
              ),
              child: Text(
                '${value.round()}',
                style: const TextStyle(
                  color: pulsarPink,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Outfit',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: deepPurple,
            inactiveTrackColor: Colors.white.withValues(alpha: 0.08),
            trackHeight: 4,
            thumbColor: pulsarPink,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            overlayColor: pulsarPink.withValues(alpha: 0.2),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            activeTickMarkColor: pulsarPink.withValues(alpha: 0.8),
            inactiveTickMarkColor: Colors.white.withValues(alpha: 0.3),
            tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 2.5),
          ),
          child: Slider(
            min: min,
            max: max,
            divisions: divisions,
            value: value,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
      ],
    );
  }
}

class NeonRadioButton<T> extends StatelessWidget {
  const NeonRadioButton({
    required this.value,
    required this.groupValue,
    required this.label,
    required this.description,
    required this.onChanged,
    super.key,
  });

  final T value;
  final T groupValue;
  final String label;
  final String description;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final isSelected = value == groupValue;
    const pulsarPink = Color(0xFFFF7597);
    const deepPurple = Color(0xFF7C3AED);

    return GestureDetector(
      onTap: () => onChanged(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? deepPurple.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? deepPurple.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.1),
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: deepPurple.withValues(alpha: 0.1),
                    blurRadius: 8,
                    spreadRadius: 1,
                  )
                ]
              : [],
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? pulsarPink : Colors.white30,
                  width: isSelected ? 2 : 1.5,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: pulsarPink.withValues(alpha: 0.3),
                          blurRadius: 6,
                          spreadRadius: 1,
                        )
                      ]
                    : [],
              ),
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: isSelected ? 10 : 0,
                  height: isSelected ? 10 : 0,
                  decoration: const BoxDecoration(
                    color: pulsarPink,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 13,
                      fontFamily: 'Outfit',
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SegmentedChipSelector extends StatelessWidget {
  const SegmentedChipSelector({
    required this.options,
    required this.selectedValue,
    required this.onSelected,
    super.key,
  });

  final List<String> options;
  final String selectedValue;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    const pulsarPink = Color(0xFFFF7597);
    const deepPurple = Color(0xFF7C3AED);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pronouns',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((option) {
            final isSelected = option == selectedValue;
            return GestureDetector(
              onTap: () => onSelected(option),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  gradient: isSelected
                      ? const LinearGradient(
                          colors: [deepPurple, pulsarPink],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: isSelected ? null : Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? Colors.transparent : Colors.white.withValues(alpha: 0.12),
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: pulsarPink.withValues(alpha: 0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          )
                        ]
                      : [],
                ),
                child: Text(
                  option,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 12,
                    fontFamily: 'Outfit',
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class CosmicTheme {
  const CosmicTheme({
    required this.name,
    required this.gradient,
    required this.icon,
  });

  final String name;
  final LinearGradient gradient;
  final IconData icon;
}
