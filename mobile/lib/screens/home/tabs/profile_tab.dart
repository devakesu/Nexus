import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/features/profile/providers/client_ai_image_provider.dart';
import 'package:nexus/screens/home/tabs/profile/sections/affinity_interests_section.dart';
import 'package:nexus/screens/home/tabs/profile/sections/bio_section.dart';
import 'package:nexus/screens/home/tabs/profile/sections/core_signal_section.dart';
import 'package:nexus/screens/home/tabs/profile/sections/lifestyle_resonance_section.dart';
import 'package:nexus/screens/home/tabs/profile/sections/social_coordinates_section.dart';
// Modular Imports
import 'package:nexus/screens/home/tabs/profile/utils/emoji_helper.dart';
import 'package:nexus/screens/home/tabs/profile/widgets/cosmic_selection_overlay.dart';
import 'package:nexus/screens/home/tabs/profile/widgets/profile_header.dart';
import 'package:nexus/screens/home/tabs/profile/widgets/stability_tracker.dart';
import 'package:nexus/screens/home/tabs/profile/widgets/storage_image.dart';
import 'package:nexus/screens/home/widgets/export_code_card.dart';
import 'package:nexus/utils/network_utils.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileTab extends ConsumerStatefulWidget {
  const ProfileTab({required this.onOpenOrbit, super.key});

  final void Function(String, Color) onOpenOrbit;

  @override
  ConsumerState<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends ConsumerState<ProfileTab> with TickerProviderStateMixin {
  AnimationController? _pulseController;
  AnimationController? _rotationController;
  late PageController _pageController;
  final SupabaseClient _client = Supabase.instance.client;

  // Loading state
  bool _isLoading = true;

  // Core profile state loaded from DB/Onboarding
  String _name = '';
  int _age = 0;
  int _year = 0;
  String _pronouns = '';
  String _campusName = '';
  bool _isStudying = true;
  String _major = '';
  String _displayGender = 'Not specified';
  String _displaySexuality = 'Not specified';
  String _searchBucket = 'NB';
  final Set<String> _savingFields = {};
  String _bio = '';

  // Extended profile fields from DB migration
  String _hometown = '';
  String _currentPlace = '';
  String _partnerValues = '';
  String _childrenPlans = 'Not specified';
  String _religiousBeliefs = 'Not specified';
  String _lifestyle = '';
  String _drinking = 'Not specified';
  String _smoking = 'Not specified';
  List<String> _causesSupported = [];
  List<String> _topArtists = [];
  List<String> _languages = [];
  List<String> _pets = [];
  Map<String, List<String>> _subInterests = {};

  // Saved profile fields (for reverting on failure)
  String _savedName = '';
  int _savedAge = 0;
  int _savedYear = 0;
  String _savedPronouns = '';
  String _savedCampusName = '';
  bool _savedIsStudying = true;
  String _savedMajor = '';
  String _savedDisplayGender = 'Not specified';
  String _savedDisplaySexuality = 'Not specified';
  String _savedSearchBucket = 'NB';
  String _savedBio = '';
  String _savedHometown = '';
  String _savedCurrentPlace = '';
  String _savedPartnerValues = '';
  String _savedChildrenPlans = 'Not specified';
  String _savedReligiousBeliefs = 'Not specified';
  String _savedLifestyle = '';
  String _savedDrinking = 'Not specified';
  String _savedSmoking = 'Not specified';
  List<String> _savedCausesSupported = [];
  List<String> _savedTopArtists = [];
  List<String> _savedLanguages = [];
  List<String> _savedPets = [];
  Map<String, List<String>> _savedSubInterests = {};

  // Profile images slot paths: supports up to 5 images (1 primary profile pic + 4 gallery pics)
  final List<String?> _imagePaths = [null, null, null, null, null];

  final GlobalKey _coreSignalKey = GlobalKey();
  final GlobalKey _bioKey = GlobalKey();
  final GlobalKey _socialCoordinatesKey = GlobalKey();
  final GlobalKey _lifestyleResonanceKey = GlobalKey();
  final GlobalKey _affinityInterestsKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();

  // Focus nodes for interactive completion triggers
  final FocusNode _nameFocusNode = FocusNode();
  final FocusNode _bioFocusNode = FocusNode();
  final FocusNode _hometownFocusNode = FocusNode();
  final FocusNode _currentPlaceFocusNode = FocusNode();
  final FocusNode _campusNameFocusNode = FocusNode();
  final FocusNode _majorFocusNode = FocusNode();

  // Animation controller for staggered entry transition
  AnimationController? _entryController;

  void _scrollToSection(GlobalKey key) {
    final context = key.currentContext;
    if (context != null) {
      unawaited(
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        ),
      );
    }
  }

  Widget _buildStaggeredEntrance({
    required Widget child,
    required int index,
  }) {
    if (_entryController == null) return child;
    final start = (index * 0.08).clamp(0.0, 1.0);
    final end = (start + 0.55).clamp(0.0, 1.0);

    final fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entryController!,
        curve: Interval(start, end, curve: Curves.easeOut),
      ),
    );

    final slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entryController!,
        curve: Interval(start, end, curve: Curves.easeOutCubic),
      ),
    );

    return FadeTransition(
      opacity: fadeAnimation,
      child: SlideTransition(
        position: slideAnimation,
        child: child,
      ),
    );
  }

  void _handleCriteriaTap(String label) {
    // 1. Core Details
    if (label == 'Profile Picture') {
      _showImageSlotPicker(0);
    } else if (label == 'Gallery Slot 1') {
      _showImageSlotPicker(1);
    } else if (label == 'Gallery Slot 2') {
      _showImageSlotPicker(2);
    } else if (label == 'Gallery Slot 3') {
      _showImageSlotPicker(3);
    } else if (label == 'Gallery Slot 4') {
      _showImageSlotPicker(4);
    } else if (label == 'Display Name') {
      _scrollToSection(_coreSignalKey);
      _nameFocusNode.requestFocus();
    } else if (label == 'Gender') {
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
          'Gender Non-Conforming',
          'Pangender',
          'Androgynous',
          'Neutrois',
          'Third Gender',
          'Intersex',
          'Bigender',
          'Two-Spirit',
          'Demiboy',
          'Demigirl',
          'Queer',
          'Questioning',
          'Prefer not to say',
        ],
        currentValue: _displayGender,
        onSelected: (val) => unawaited(_saveProfileChanges(displayGender: val)),
      );
    } else if (label == 'Sexuality') {
      _openSelectionOverlay(
        title: 'Sexuality',
        options: const [
          'Straight',
          'Gay',
          'Lesbian',
          'Bisexual',
          'Pansexual',
          'Asexual',
          'Aromantic',
          'Greysexual',
          'Polysexual',
          'Omnisexual',
          'Fluid',
          'Skoliosexual',
          'Demisexual',
          'Queer',
          'Questioning',
          'Prefer not to say',
        ],
        currentValue: _displaySexuality,
        onSelected: (val) => unawaited(_saveProfileChanges(displaySexuality: val)),
      );
    } else if (label == 'Pronouns') {
      _openBottomSelectionSheet(
        title: 'Pronouns',
        options: const [
          'he/him',
          'she/her',
          'they/them',
          'he/they',
          'she/they',
          'it/its',
          'any/all',
          'xe/xem',
          'fae/faer',
          'Prefer not to say',
        ],
        currentValue: _pronouns,
        onSelected: (val) {
          setState(() => _pronouns = val);
          unawaited(_saveProfileChanges(pronouns: val));
        },
      );
    } else if (['Age', 'Demographic Buckets'].contains(label)) {
      _scrollToSection(_coreSignalKey);
    } else if (label == 'Cosmic Signature (Bio)') {
      _scrollToSection(_bioKey);
      _bioFocusNode.requestFocus();
    }
    // 2. Social & Campus Info
    else if (label == 'Hometown') {
      _scrollToSection(_socialCoordinatesKey);
      _hometownFocusNode.requestFocus();
    } else if (label == 'Current Place') {
      _scrollToSection(_socialCoordinatesKey);
      _currentPlaceFocusNode.requestFocus();
    } else if (label == 'Institute Name') {
      _scrollToSection(_socialCoordinatesKey);
      _campusNameFocusNode.requestFocus();
    } else if (label == 'Major') {
      _scrollToSection(_socialCoordinatesKey);
      _majorFocusNode.requestFocus();
    } else if (['Languages', 'Campus Year'].contains(label)) {
      _scrollToSection(_socialCoordinatesKey);
    }
    // 3. Lifestyle & Preferences
    else if (label == 'Drinking') {
      _openBottomSelectionSheet(
        title: 'Drinking',
        options: const [
          'Never',
          'Occasionally',
          'Socially',
          'Regularly',
        ],
        currentValue: _drinking,
        onSelected: (val) => unawaited(_saveProfileChanges(drinking: val)),
      );
    } else if (label == 'Smoking') {
      _openBottomSelectionSheet(
        title: 'Smoking',
        options: const [
          'Never',
          'Occasionally',
          'Socially',
          'Regularly',
        ],
        currentValue: _smoking,
        onSelected: (val) => unawaited(_saveProfileChanges(smoking: val)),
      );
    } else if (label == 'Children Plans') {
      _openBottomSelectionSheet(
        title: 'Children Plans',
        options: const [
          'Want kids',
          "Don't want kids",
          'Undecided',
          'Not specified',
        ],
        currentValue: _childrenPlans,
        onSelected: (val) => unawaited(_saveProfileChanges(childrenPlans: val)),
      );
    } else if (label == 'Religious Beliefs') {
      _openBottomSelectionSheet(
        title: 'Religious Beliefs',
        options: const [
          'Atheist',
          'Agnostic',
          'Spiritual',
          'Christian',
          'Muslim',
          'Jewish',
          'Hindu',
          'Buddhist',
          'Sikh',
          'Jain',
          'Shinto',
          'Baháʼí',
          'Taoist',
          'Zoroastrian',
          'Pagan',
          'Wiccan',
          'Other',
          'Not specified',
        ],
        currentValue: _religiousBeliefs,
        onSelected: (val) => unawaited(_saveProfileChanges(religiousBeliefs: val)),
      );
    } else if (['Lifestyle Description', 'Partner Values', 'Pets'].contains(label)) {
      _scrollToSection(_lifestyleResonanceKey);
    }
    // 4. Interests & Hobbies
    else if (['Interests', 'Causes Supported', 'Top Artists'].contains(label)) {
      _scrollToSection(_affinityInterestsKey);
    }
  }

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

  List<String> get _flatSubInterests {
    final list = <String>[];
    _subInterests.forEach((parent, subs) {
      for (final sub in subs) {
        list.add('$parent: $sub');
      }
    });
    return list;
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
            _savedName = _name;

            _age = (data['age'] as num?)?.toInt() ?? _age;
            _savedAge = _age;

            if (data['campus_year'] != null) {
              _year = (data['campus_year'] as num).toInt();
              _isStudying = _year > 0;
            } else {
              _isStudying = false;
            }
            _savedYear = _year;
            _savedIsStudying = _isStudying;

            String cleanVal(dynamic val) {
              if (val == null) return '';
              final s = val.toString().trim();
              if (s.toLowerCase() == 'not specified') return '';
              return s;
            }

            _major = cleanVal(data['campus_branch']);
            _savedMajor = _major;

            _campusName = cleanVal(data['campus_name']);
            _savedCampusName = _campusName;

            _displayGender =
                data['display_gender']?.toString() ?? 'Not specified';
            _savedDisplayGender = _displayGender;

            _displaySexuality =
                data['display_sexuality']?.toString() ?? 'Not specified';
            _savedDisplaySexuality = _displaySexuality;

            _pronouns = data['pronouns']?.toString() ?? 'they/them';
            _savedPronouns = _pronouns;

            _bio = data['bio']?.toString() ?? '';
            _savedBio = _bio;

            _hometown = cleanVal(data['hometown']);
            _savedHometown = _hometown;

            _currentPlace = cleanVal(data['current_place']);
            _savedCurrentPlace = _currentPlace;

            _partnerValues = data['partner_values']?.toString() ?? '';
            _savedPartnerValues = _partnerValues;

            _childrenPlans =
                data['children_plans']?.toString() ?? 'Not specified';
            _savedChildrenPlans = _childrenPlans;

            _religiousBeliefs =
                data['religious_beliefs']?.toString() ?? 'Not specified';
            _savedReligiousBeliefs = _religiousBeliefs;

            _lifestyle = data['lifestyle']?.toString() ?? '';
            _savedLifestyle = _lifestyle;

            _drinking = data['drinking']?.toString() ?? 'Not specified';
            _savedDrinking = _drinking;

            _smoking = data['smoking']?.toString() ?? 'Not specified';
            _savedSmoking = _smoking;

            final rawBucket = data['search_bucket'];
            _searchBucket = rawBucket?.toString() ?? 'NB';
            _savedSearchBucket = _searchBucket;

            final rawCauses = data['causes_supported'];
            if (rawCauses is List) {
              _causesSupported = rawCauses.map((e) => e.toString()).toList();
            } else {
              _causesSupported = [];
            }
            _savedCausesSupported = List<String>.from(_causesSupported);

            final rawArtists = data['top_artists'];
            if (rawArtists is List) {
              _topArtists = rawArtists.map((e) => e.toString()).toList();
            } else {
              _topArtists = [];
            }
            _savedTopArtists = List<String>.from(_topArtists);

            final rawLanguages = data['languages'];
            if (rawLanguages is List) {
              _languages = rawLanguages.map((e) => e.toString()).toList();
            } else {
              _languages = [];
            }
            _savedLanguages = List<String>.from(_languages);

            final rawPets = data['pets'];
            if (rawPets is List) {
              _pets = rawPets.map((e) => e.toString()).toList();
            } else {
              _pets = [];
            }
            _savedPets = List<String>.from(_pets);

            final rawSubInterests = data['sub_interests'];
            if (rawSubInterests is Map) {
              _subInterests = Map<String, List<String>>.from(
                rawSubInterests.map((k, v) {
                  final list = v as List? ?? [];
                  return MapEntry(
                    k.toString(),
                    list.map((e) => e.toString()).toList(),
                  );
                }),
              );
            } else {
              _subInterests = {};
            }
            _savedSubInterests = Map<String, List<String>>.from(_subInterests);

            final rawImages = data['ordered_images'];
            if (rawImages is List) {
              final loadedImages = List<String>.generate(5, (i) {
                if (i < rawImages.length && rawImages[i] != null && rawImages[i].toString().isNotEmpty) {
                  _imagePaths[i] = rawImages[i].toString();
                  return rawImages[i].toString();
                } else {
                  _imagePaths[i] = null;
                  return '';
                }
              });
              ref.read(clientAIImageManagerProvider.notifier).setRemotePaths(loadedImages);
            }
          });
        }
      }
    } on Object catch (e) {
      debugPrint('[ProfileTab] Error loading profile details: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        if (_entryController != null) {
          unawaited(_entryController!.forward(from: 0));
        }
      }
    }
  }

  Future<void> _saveProfileChanges({
    String? name,
    int? age,
    String? displayGender,
    String? displaySexuality,
    String? pronouns,
    String? bio,
    String? searchBucket,
    String? campusBranch,
    int? campusYear,
    bool clearCampusYear = false,
    String? campusName,
    String? hometown,
    String? currentPlace,
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
    Map<String, int>? interests,
    Map<String, List<String>>? subInterests,
  }) async {
    final fields = <String>[];
    if (name != null) fields.add('name');
    if (age != null) fields.add('age');
    if (displayGender != null) fields.add('displayGender');
    if (displaySexuality != null) fields.add('displaySexuality');
    if (pronouns != null) fields.add('pronouns');
    if (bio != null) fields.add('bio');
    if (searchBucket != null) fields.add('searchBucket');
    if (campusBranch != null) fields.add('campusBranch');
    if (campusYear != null || clearCampusYear) fields.add('campusYear');
    if (campusName != null) fields.add('campusName');
    if (hometown != null) fields.add('hometown');
    if (currentPlace != null) fields.add('currentPlace');
    if (partnerValues != null) fields.add('partnerValues');
    if (childrenPlans != null) fields.add('childrenPlans');
    if (religiousBeliefs != null) fields.add('religiousBeliefs');
    if (lifestyle != null) fields.add('lifestyle');
    if (drinking != null) fields.add('drinking');
    if (smoking != null) fields.add('smoking');
    if (causesSupported != null) fields.add('causesSupported');
    if (topArtists != null) fields.add('topArtists');
    if (languages != null) fields.add('languages');
    if (pets != null) fields.add('pets');
    if (subInterests != null || interests != null) fields.add('interests');

    setState(() {
      _savingFields.addAll(fields);
    });

    try {
      final session = _client.auth.currentSession;
      if (session != null) {
        final config = AppConfig.current;
        final dio = createDio();

        final payload = <String, dynamic>{};
        if (name != null) payload['name'] = name;
        if (age != null) payload['age'] = age;
        if (displayGender != null) payload['display_gender'] = displayGender;
        if (displaySexuality != null) {
          payload['display_sexuality'] = displaySexuality;
        }
        if (pronouns != null) payload['pronouns'] = pronouns;
        if (bio != null) payload['bio'] = bio;
        if (searchBucket != null) payload['search_bucket'] = searchBucket;
        if (campusBranch != null) payload['campus_branch'] = campusBranch;
        if (campusYear != null) {
          payload['campus_year'] = campusYear;
        } else if (clearCampusYear) {
          payload['campus_year'] = null;
        }
        if (campusName != null) payload['campus_name'] = campusName;
        if (hometown != null) payload['hometown'] = hometown;
        if (currentPlace != null) payload['current_place'] = currentPlace;
        if (partnerValues != null) payload['partner_values'] = partnerValues;
        if (childrenPlans != null) payload['children_plans'] = childrenPlans;
        if (religiousBeliefs != null) {
          payload['religious_beliefs'] = religiousBeliefs;
        }
        if (lifestyle != null) payload['lifestyle'] = lifestyle;
        if (drinking != null) payload['drinking'] = drinking;
        if (smoking != null) payload['smoking'] = smoking;
        if (role != null) payload['role'] = role;
        if (targetBuckets != null) payload['target_buckets'] = targetBuckets;
        if (lookingFor != null) payload['looking_for'] = lookingFor;
        if (activities != null) payload['activities'] = activities;
        if (causesSupported != null) {
          payload['causes_supported'] = causesSupported;
        }
        if (topArtists != null) payload['top_artists'] = topArtists;
        if (techSkills != null) payload['tech_skills'] = techSkills;
        if (languages != null) payload['languages'] = languages;
        if (pets != null) payload['pets'] = pets;
        if (interests != null) payload['interests'] = interests;
        if (subInterests != null) payload['sub_interests'] = subInterests;

        // Perform the details secure endpoint update
        if (payload.isNotEmpty) {
          final response = await dio.patch<Map<String, dynamic>>(
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
              if (age != null) {
                _age = age;
                _savedAge = age;
              }
              if (name != null) {
                _name = name;
                _savedName = name;
              }
              if (displayGender != null) {
                _displayGender = displayGender;
                _savedDisplayGender = displayGender;
              }
              if (displaySexuality != null) {
                _displaySexuality = displaySexuality;
                _savedDisplaySexuality = displaySexuality;
              }
              if (pronouns != null) {
                _pronouns = pronouns;
                _savedPronouns = pronouns;
              }
              if (bio != null) {
                _bio = bio;
                _savedBio = bio;
              }
              if (searchBucket != null) {
                _searchBucket = searchBucket;
                _savedSearchBucket = searchBucket;
              }
              if (campusBranch != null) {
                _major = campusBranch;
                _savedMajor = campusBranch;
              }
              if (campusYear != null) {
                _year = campusYear;
                _savedYear = campusYear;
              } else if (clearCampusYear) {
                _year = 0;
                _savedYear = 0;
              }
              if (campusName != null) {
                _campusName = campusName;
                _savedCampusName = campusName;
              }
              if (hometown != null) {
                _hometown = hometown;
                _savedHometown = hometown;
              }
              if (currentPlace != null) {
                _currentPlace = currentPlace;
                _savedCurrentPlace = currentPlace;
              }
              if (partnerValues != null) {
                _partnerValues = partnerValues;
                _savedPartnerValues = partnerValues;
              }
              if (childrenPlans != null) {
                _childrenPlans = childrenPlans;
                _savedChildrenPlans = childrenPlans;
              }
              if (religiousBeliefs != null) {
                _religiousBeliefs = religiousBeliefs;
                _savedReligiousBeliefs = religiousBeliefs;
              }
              if (lifestyle != null) {
                _lifestyle = lifestyle;
                _savedLifestyle = lifestyle;
              }
              if (drinking != null) {
                _drinking = drinking;
                _savedDrinking = drinking;
              }
              if (smoking != null) {
                _smoking = smoking;
                _savedSmoking = smoking;
              }
              if (causesSupported != null) {
                _causesSupported = causesSupported;
                _savedCausesSupported = List<String>.from(causesSupported);
              }
              if (topArtists != null) {
                _topArtists = topArtists;
                _savedTopArtists = List<String>.from(topArtists);
              }
              if (languages != null) {
                _languages = languages;
                _savedLanguages = List<String>.from(languages);
              }
              if (pets != null) {
                _pets = pets;
                _savedPets = List<String>.from(pets);
              }
              if (subInterests != null) {
                _subInterests = subInterests;
                _savedSubInterests = Map<String, List<String>>.from(subInterests);
              }
            });
          } else {
            throw Exception('API responded with status code: ${response.statusCode}');
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(20),
            ),
          );
        }
      }
    } on Object catch (e) {
      debugPrint('[ProfileTab] Error saving profile details: $e');
      if (mounted) {
        setState(() {
          // Revert all modified fields back to their saved versions
          if (name != null) _name = _savedName;
          if (age != null) _age = _savedAge;
          if (displayGender != null) _displayGender = _savedDisplayGender;
          if (displaySexuality != null) _displaySexuality = _savedDisplaySexuality;
          if (pronouns != null) _pronouns = _savedPronouns;
          if (bio != null) _bio = _savedBio;
          if (searchBucket != null) _searchBucket = _savedSearchBucket;
          if (campusBranch != null) _major = _savedMajor;
          if (campusYear != null || clearCampusYear) {
            _year = _savedYear;
            _isStudying = _savedIsStudying;
          }
          if (campusName != null) _campusName = _savedCampusName;
          if (hometown != null) _hometown = _savedHometown;
          if (currentPlace != null) _currentPlace = _savedCurrentPlace;
          if (partnerValues != null) _partnerValues = _savedPartnerValues;
          if (childrenPlans != null) _childrenPlans = _savedChildrenPlans;
          if (religiousBeliefs != null) _religiousBeliefs = _savedReligiousBeliefs;
          if (lifestyle != null) _lifestyle = _savedLifestyle;
          if (drinking != null) _drinking = _savedDrinking;
          if (smoking != null) _smoking = _savedSmoking;
          if (causesSupported != null) _causesSupported = List<String>.from(_savedCausesSupported);
          if (topArtists != null) _topArtists = List<String>.from(_savedTopArtists);
          if (languages != null) _languages = List<String>.from(_savedLanguages);
          if (pets != null) _pets = List<String>.from(_savedPets);
          if (subInterests != null || interests != null) {
            _subInterests = Map<String, List<String>>.from(_savedSubInterests);
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFC0392B),
            content: Text(
              'Failed to synchronize cosmic frequency: $e',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
            duration: const Duration(seconds: 4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(20),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _savingFields.removeAll(fields);
        });
      }
    }
  }

  int _calculateStability() {
    var filled = 0;
    const total = 28;

    // 1. The Core Signal
    if (_imagePaths[0] != null && _imagePaths[0]!.isNotEmpty) filled++;
    if (_name.isNotEmpty) filled++;
    if (_age >= 18) filled++;
    if (_bio.isNotEmpty) filled++;
    if (_searchBucket.isNotEmpty) filled++;
    if (_displayGender.isNotEmpty && _displayGender != 'Prefer not to say') filled++;
    if (_displaySexuality.isNotEmpty && _displaySexuality != 'Prefer not to say') filled++;
    if (_pronouns.isNotEmpty && _pronouns != 'Prefer not to say') filled++;
    if (_imagePaths[1] != null && _imagePaths[1]!.isNotEmpty) filled++;
    if (_imagePaths[2] != null && _imagePaths[2]!.isNotEmpty) filled++;
    if (_imagePaths[3] != null && _imagePaths[3]!.isNotEmpty) filled++;
    if (_imagePaths[4] != null && _imagePaths[4]!.isNotEmpty) filled++;

    // 2. Social Coordinates
    if (_hometown.isNotEmpty) filled++;
    if (_currentPlace.isNotEmpty) filled++;
    if (_languages.isNotEmpty) filled++;
    if (_campusName.isNotEmpty) filled++;
    if (_major.isNotEmpty) filled++;
    if (!_isStudying || (_year >= 1 && _year <= 5)) filled++;

    // 3. Lifestyle & Resonance
    if (_lifestyle.isNotEmpty) filled++;
    if (_drinking.isNotEmpty && _drinking != 'Not specified') filled++;
    if (_smoking.isNotEmpty && _smoking != 'Not specified') filled++;
    if (_childrenPlans.isNotEmpty && _childrenPlans != 'Not specified') filled++;
    if (_religiousBeliefs.isNotEmpty && _religiousBeliefs != 'Not specified') filled++;
    if (_partnerValues.isNotEmpty) filled++;
    if (_pets.isNotEmpty) filled++;

    // 4. Affinity & Interests
    if (_subInterests.isNotEmpty) filled++;
    if (_causesSupported.isNotEmpty) filled++;
    if (_topArtists.isNotEmpty) filled++;

    return ((filled / total) * 100).round();
  }

  Future<void> _pickImage(int slotIndex) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      final file = File(pickedFile.path);
      if (!mounted) return;
      final oldPaths = List<String?>.from(_imagePaths);
      setState(() {
        _imagePaths[slotIndex] = pickedFile.path;
      });

      try {
        // 1. Run local client-side vision AI model & stage local file
        await ref.read(clientAIImageManagerProvider.notifier).stageImageSlot(slotIndex, file, userBranch: _major);

        if (!mounted) return;

        // 2. Commit transaction instantly to upload to storage & update DB
        final userId = _client.auth.currentUser?.id;
        if (userId != null) {
          final dio = createDio();
          await ref.read(clientAIImageManagerProvider.notifier).commitProfileChanges(dio, userId);

          if (!mounted) return;

          // 3. Sync local state with provider's updated state
          final providerState = ref.read(clientAIImageManagerProvider);
          setState(() {
            for (var i = 0; i < _imagePaths.length; i++) {
              if (i < providerState.remotePaths.length && providerState.remotePaths[i].isNotEmpty) {
                _imagePaths[i] = providerState.remotePaths[i];
              } else {
                _imagePaths[i] = null;
              }
            }
          });
        }
      } on Object catch (e) {
        if (!mounted) return;
        setState(() {
          _imagePaths[slotIndex] = oldPaths[slotIndex];
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFC0392B),
            content: Text(
              'Failed to sync media: ${e.toString().contains('Bucket not found') ? 'Storage bucket not configured' : e.toString()}',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        );
      }
    }
  }

  Future<void> _clearImage(int slotIndex) async {
    final oldPaths = List<String?>.from(_imagePaths);
    setState(() {
      _imagePaths[slotIndex] = null;
    });

    try {
      // 1. Update Riverpod state removing the slot
      ref.read(clientAIImageManagerProvider.notifier).clearImageSlot(slotIndex);

      // 2. Commit transaction instantly to remove from storage & update DB
      final userId = _client.auth.currentUser?.id;
      if (userId != null) {
        final dio = createDio();
        await ref.read(clientAIImageManagerProvider.notifier).commitProfileChanges(dio, userId);

        if (!mounted) return;

        // 3. Sync local state with provider
        final providerState = ref.read(clientAIImageManagerProvider);
        setState(() {
          for (var i = 0; i < _imagePaths.length; i++) {
            if (i < providerState.remotePaths.length && providerState.remotePaths[i].isNotEmpty) {
              _imagePaths[i] = providerState.remotePaths[i];
            } else {
              _imagePaths[i] = null;
            }
          }
        });
      }
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _imagePaths[slotIndex] = oldPaths[slotIndex];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFC0392B),
          content: Text(
            'Failed to clear media: ${e.toString().contains('Bucket not found') ? 'Storage bucket not configured' : e.toString()}',
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
      );
    }
  }

  void _showImageSlotPicker(int slotIndex) {
    final imagePath = _imagePaths[slotIndex];
    final isDark = Theme.of(context).brightness == Brightness.dark;
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (context) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF161B26).withValues(alpha: 0.98) : Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(30),
                topRight: Radius.circular(30),
              ),
              border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      slotIndex == 0 ? LucideIcons.user : LucideIcons.image,
                      color: const Color(0xFFFF7597),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      slotIndex == 0 ? 'Profile Avatar' : 'Gallery - Slot $slotIndex',
                      style: TextStyle(
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Outfit',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  slotIndex == 0
                      ? 'Select your cosmic profile avatar...'
                      : 'Choose your gallery showcase photo...',
                  style: TextStyle(
                    color: isDark ? Colors.white54 : Colors.black54,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                if (imagePath != null) ...[
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: StorageImage(
                        imagePath: imagePath,
                        width: 150,
                        height: 150,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Material(
                    color: Colors.transparent,
                    child: ListTile(
                      leading: Icon(
                        LucideIcons.refreshCw,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                      title: Text(
                        'Replace Image',
                        style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0F172A)),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        unawaited(_pickImage(slotIndex));
                      },
                    ),
                  ),
                  Material(
                    color: Colors.transparent,
                    child: ListTile(
                      leading: const Icon(
                        LucideIcons.trash2,
                        color: Colors.redAccent,
                      ),
                      title: const Text(
                        'Clear Image',
                        style: TextStyle(color: Colors.redAccent),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        unawaited(_clearImage(slotIndex));
                      },
                    ),
                  ),
                ] else ...[
                  Text(
                    'Upload an image from your device gallery to represent you in this slot.',
                    style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E5FF),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        unawaited(_pickImage(slotIndex));
                      },
                      icon: const Icon(LucideIcons.plus, color: Colors.white),
                      label: const Text(
                        'Add Image',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  void _openSelectionOverlay({
    required String title,
    required List<String> options,
    required String currentValue,
    required ValueChanged<String> onSelected,
  }) {
    unawaited(
      showGeneralDialog<String>(
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
        FocusManager.instance.primaryFocus?.unfocus();
        if (selected != null && mounted) {
          onSelected(selected);
        }
      }),
    );
  }

  void _openBottomSelectionSheet({
    required String title,
    required List<String> options,
    required String currentValue,
    required ValueChanged<String> onSelected,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    unawaited(
      showModalBottomSheet<String>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        barrierColor: Colors.black.withValues(alpha: isDark ? 0.8 : 0.4),
        builder: (context) {
          final searchController = TextEditingController();
          return StatefulBuilder(
            builder: (context, setModalState) {
              final showSearch = options.length > 10;
              final filteredOptions = showSearch
                  ? options.where((option) {
                      return option.toLowerCase().contains(
                            searchController.text.toLowerCase(),
                          );
                    }).toList()
                  : options;

              return Container(
                padding: EdgeInsets.only(
                  top: 12,
                  left: 20,
                  right: 20,
                  bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
                ),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF131722).withValues(alpha: 0.98) : Colors.white,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(28),
                    topRight: Radius.circular(28),
                  ),
                  border: Border.all(
                    color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.08),
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 38,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 18),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Outfit',
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            '${filteredOptions.length} options',
                            style: TextStyle(
                              color: isDark ? Colors.white.withValues(alpha: 0.35) : Colors.black.withValues(alpha: 0.45),
                              fontSize: 11,
                              fontFamily: 'Outfit',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (showSearch) ...[
                        Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white.withValues(alpha: 0.02) : Colors.black.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                LucideIcons.search,
                                color: isDark ? Colors.white38 : Colors.black45,
                                size: 16,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: searchController,
                                  style: TextStyle(
                                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                                    fontSize: 13,
                                    fontFamily: 'Outfit',
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'Search signals...',
                                    hintStyle: TextStyle(
                                      color: isDark ? Colors.white.withValues(alpha: 0.25) : Colors.black.withValues(alpha: 0.35),
                                      fontSize: 13,
                                    ),
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                  onChanged: (val) {
                                    setModalState(() {});
                                  },
                                ),
                              ),
                              if (searchController.text.isNotEmpty)
                                GestureDetector(
                                  onTap: () {
                                    searchController.clear();
                                    setModalState(() {});
                                  },
                                  child: Icon(
                                    LucideIcons.xCircle,
                                    color: isDark ? Colors.white38 : Colors.black45,
                                    size: 16,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.45,
                        ),
                        child: ShaderMask(
                          shaderCallback: (bounds) {
                            return const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.white, Colors.transparent],
                              stops: [0.90, 1.0],
                            ).createShader(bounds);
                          },
                          blendMode: BlendMode.dstIn,
                          child: ListView.separated(
                            shrinkWrap: true,
                            physics: const BouncingScrollPhysics(),
                            itemCount: filteredOptions.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final option = filteredOptions[index];
                              final isSelected = option == currentValue;
                              final emoji = getEmojiForTag(option);

                              return GestureDetector(
                                onTap: () {
                                  Navigator.pop(context, option);
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? const Color(0xFFFF7597).withValues(alpha: 0.08)
                                        : (isDark ? Colors.white.withValues(alpha: 0.01) : Colors.black.withValues(alpha: 0.02)),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isSelected
                                          ? const Color(0xFFFF7597).withValues(alpha: 0.45)
                                          : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.06)),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      if (isSelected) ...[
                                        Container(
                                          width: 3,
                                          height: 14,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFF7597),
                                            borderRadius: BorderRadius.circular(1.5),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                      ],
                                      if (emoji.isNotEmpty) ...[
                                        Text(
                                          emoji,
                                          style: const TextStyle(fontSize: 16),
                                        ),
                                        const SizedBox(width: 12),
                                      ] else ...[
                                        Icon(
                                          LucideIcons.sparkles,
                                          size: 14,
                                          color: isSelected
                                              ? const Color(0xFFFF7597)
                                              : (isDark ? Colors.white24 : Colors.black26),
                                        ),
                                        const SizedBox(width: 12),
                                      ],
                                      Expanded(
                                        child: Text(
                                          option,
                                          style: TextStyle(
                                            color: isSelected
                                                ? (isDark ? Colors.white : const Color(0xFFFF7597))
                                                : (isDark ? Colors.white70 : Colors.black87),
                                            fontFamily: 'Outfit',
                                            fontSize: 14,
                                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      if (isSelected)
                                        const Icon(
                                          LucideIcons.checkCircle,
                                          color: Color(0xFFFF7597),
                                          size: 16,
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ).then((selected) {
        FocusManager.instance.primaryFocus?.unfocus();
        if (selected != null && mounted) {
          onSelected(selected);
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    const pulsarPink = Color(0xFFFF7597);
    final config = AppConfig.current;
    final providerState = ref.watch(clientAIImageManagerProvider);

    final pulseController = _pulseController;
    final rotationController = _rotationController;

    if (_isLoading || pulseController == null || rotationController == null) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(pulsarPink),
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        final currentFocus = FocusScope.of(context);
        if (!currentFocus.hasPrimaryFocus &&
            currentFocus.focusedChild != null) {
          currentFocus.unfocus();
        }
      },
      child: Stack(
        children: [
          // Base background color
          Positioned.fill(
            child: Container(color: Theme.of(context).scaffoldBackgroundColor),
          ),
          // Futuristic Grid Pattern Overlay
          Positioned.fill(
            child: CustomPaint(
              painter: FuturisticBackgroundPainter(
                isDark: Theme.of(context).brightness == Brightness.dark,
              ),
            ),
          ),
          // Layered Ambient Glows
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(-0.8, -0.6),
                  radius: 1.2,
                  colors: [
                    Color(0x1B6366F1), // Soft Indigo/Purple glow
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0.9, 0.2),
                  radius: 1.5,
                  colors: [
                    Color(0x1300E5FF), // Soft Cyan glow
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(-0.5, 0.9),
                  radius: 1.2,
                  colors: [
                    Color(0x11FF7597), // Soft Pink glow
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Scrollable content
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ListView(
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(0, 12, 0, 110),
                  children: [
                    // 🪐 1. Pulsing & Rotating Profile Header
                    _buildStaggeredEntrance(
                      index: 0,
                      child: ProfileHeader(
                        avatarPath: _imagePaths[0],
                        name: _name,
                        rotationController: rotationController,
                        pulseController: pulseController,
                        isProcessingAI: providerState.isProcessingAI,
                        isSaving: providerState.isSaving,
                        hasPendingUpload: providerState.pendingUploads.containsKey(0),
                        onAvatarTap: () => _showImageSlotPicker(0),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Stability Tracker Card
                    _buildStaggeredEntrance(
                      index: 1,
                      child: StabilityTracker(
                        stabilityPercentage: _calculateStability(),
                        imagePaths: _imagePaths,
                        name: _name,
                        age: _age,
                        bio: _bio,
                        searchBucket: _searchBucket,
                        displayGender: _displayGender,
                        displaySexuality: _displaySexuality,
                        pronouns: _pronouns,
                        hometown: _hometown,
                        currentPlace: _currentPlace,
                        languages: _languages,
                        campusName: _campusName,
                        major: _major,
                        isStudying: _isStudying,
                        year: _year,
                        lifestyle: _lifestyle,
                        drinking: _drinking,
                        smoking: _smoking,
                        childrenPlans: _childrenPlans,
                        religiousBeliefs: _religiousBeliefs,
                        partnerValues: _partnerValues,
                        pets: _pets,
                        subInterests: _subInterests,
                        causesSupported: _causesSupported,
                        topArtists: _topArtists,
                        pulseController: pulseController,
                        onCriteriaTap: _handleCriteriaTap,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // 🌌 2. Modular Custom Universe Cards
                    // Card Layer A: The Core Signal
                    _buildStaggeredEntrance(
                      index: 2,
                      child: CoreSignalSection(
                        key: _coreSignalKey,
                        name: _name,
                        age: _age,
                        savedAge: _savedAge,
                        searchBucket: _searchBucket,
                        displayGender: _displayGender,
                        displaySexuality: _displaySexuality,
                        pronouns: _pronouns,
                        imagePaths: _imagePaths,
                        isProcessingAI: providerState.isProcessingAI,
                        isSaving: providerState.isSaving,
                        pendingUploads: providerState.pendingUploads,
                        isSavingName: _savingFields.contains('name'),
                        isSavingGender: _savingFields.contains('displayGender'),
                        isSavingSexuality: _savingFields.contains('displaySexuality'),
                        isSavingPronouns: _savingFields.contains('pronouns'),
                        isSavingAge: _savingFields.contains('age'),
                        isSavingBuckets: _savingFields.contains('searchBucket'),
                        nameFocusNode: _nameFocusNode,
                        onNameChanged: (val) => setState(() => _name = val),
                        onNameSubmitted: (val) => unawaited(_saveProfileChanges(name: val)),
                        onAgeChanged: (val) => setState(() => _age = val),
                        onAgeConfirmed: (val) => unawaited(_saveProfileChanges(age: val)),
                        onBucketChanged: (val) {
                          setState(() => _searchBucket = val);
                          unawaited(_saveProfileChanges(searchBucket: val));
                        },
                        onSelectGender: () {
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
                              'Gender Non-Conforming',
                              'Pangender',
                              'Androgynous',
                              'Neutrois',
                              'Third Gender',
                              'Intersex',
                              'Bigender',
                              'Two-Spirit',
                              'Demiboy',
                              'Demigirl',
                              'Queer',
                              'Questioning',
                              'Prefer not to say',
                            ],
                            currentValue: _displayGender,
                            onSelected: (val) => unawaited(_saveProfileChanges(displayGender: val)),
                          );
                        },
                        onSelectSexuality: () {
                          _openSelectionOverlay(
                            title: 'Sexuality',
                            options: const [
                              'Straight',
                              'Gay',
                              'Lesbian',
                              'Bisexual',
                              'Pansexual',
                              'Asexual',
                              'Aromantic',
                              'Greysexual',
                              'Polysexual',
                              'Omnisexual',
                              'Fluid',
                              'Skoliosexual',
                              'Demisexual',
                              'Queer',
                              'Questioning',
                              'Prefer not to say',
                            ],
                            currentValue: _displaySexuality,
                            onSelected: (val) => unawaited(_saveProfileChanges(displaySexuality: val)),
                          );
                        },
                        onSelectPronouns: () {
                          _openBottomSelectionSheet(
                            title: 'Pronouns',
                            options: const [
                              'he/him',
                              'she/her',
                              'they/them',
                              'he/they',
                              'she/they',
                              'it/its',
                              'any/all',
                              'xe/xem',
                              'fae/faer',
                              'Prefer not to say',
                            ],
                            currentValue: _pronouns,
                            onSelected: (val) {
                              setState(() => _pronouns = val);
                              unawaited(_saveProfileChanges(pronouns: val));
                            },
                          );
                        },
                        onImageSlotTap: _showImageSlotPicker,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Card Layer B: Cosmic Signature (Bio)
                    _buildStaggeredEntrance(
                      index: 3,
                      child: BioSection(
                        key: _bioKey,
                        bio: _bio,
                        isSaving: _savingFields.contains('bio'),
                        focusNode: _bioFocusNode,
                        onBioChanged: (val) => setState(() => _bio = val),
                        onBioSubmitted: (val) => unawaited(_saveProfileChanges(bio: val)),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Card Layer C: Social Coordinates
                    _buildStaggeredEntrance(
                      index: 4,
                      child: SocialCoordinatesSection(
                        key: _socialCoordinatesKey,
                        hometown: _hometown,
                        currentPlace: _currentPlace,
                        languages: _languages,
                        campusName: _campusName,
                        major: _major,
                        isStudying: _isStudying,
                        year: _year,
                        isSavingHometown: _savingFields.contains('hometown'),
                        isSavingCurrentPlace: _savingFields.contains('currentPlace'),
                        isSavingCampusName: _savingFields.contains('campusName'),
                        isSavingMajor: _savingFields.contains('campusBranch'),
                        isSavingLanguages: _savingFields.contains('languages'),
                        isSavingCampusYear: _savingFields.contains('campusYear'),
                        hometownFocusNode: _hometownFocusNode,
                        currentPlaceFocusNode: _currentPlaceFocusNode,
                        campusNameFocusNode: _campusNameFocusNode,
                        majorFocusNode: _majorFocusNode,
                        onHometownChanged: (val) => setState(() => _hometown = val),
                        onHometownSubmitted: (val) => unawaited(_saveProfileChanges(hometown: val)),
                        onCurrentPlaceChanged: (val) => setState(() => _currentPlace = val),
                        onCurrentPlaceSubmitted: (val) => unawaited(_saveProfileChanges(currentPlace: val)),
                        onLanguagesChanged: (val) {
                          setState(() => _languages = val);
                          unawaited(_saveProfileChanges(languages: val));
                        },
                        onCampusNameChanged: (val) => setState(() => _campusName = val),
                        onCampusNameSubmitted: (val) => unawaited(_saveProfileChanges(campusName: val)),
                        onMajorChanged: (val) => setState(() => _major = val),
                        onMajorSubmitted: (val) => unawaited(_saveProfileChanges(campusBranch: val)),
                        onIsStudyingChanged: (val) {
                          setState(() => _isStudying = val);
                          if (!val) {
                            unawaited(_saveProfileChanges(clearCampusYear: true));
                          }
                        },
                        onYearChanged: (val) {
                          setState(() => _year = val);
                          unawaited(_saveProfileChanges(campusYear: val));
                        },
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Card Layer D: Lifestyle & Resonance
                    _buildStaggeredEntrance(
                      index: 5,
                      child: LifestyleResonanceSection(
                        key: _lifestyleResonanceKey,
                        lifestyle: _lifestyle,
                        drinking: _drinking,
                        smoking: _smoking,
                        childrenPlans: _childrenPlans,
                        religiousBeliefs: _religiousBeliefs,
                        partnerValues: _partnerValues,
                        pets: _pets,
                        isSavingLifestyle: _savingFields.contains('lifestyle'),
                        isSavingPartnerValues: _savingFields.contains('partnerValues'),
                        isSavingDrinking: _savingFields.contains('drinking'),
                        isSavingSmoking: _savingFields.contains('smoking'),
                        isSavingChildrenPlans: _savingFields.contains('childrenPlans'),
                        isSavingReligiousBeliefs: _savingFields.contains('religiousBeliefs'),
                        isSavingPets: _savingFields.contains('pets'),
                        onLifestyleChanged: (val) => setState(() => _lifestyle = val),
                        onLifestyleSubmitted: (val) => unawaited(_saveProfileChanges(lifestyle: val)),
                        onPartnerValuesChanged: (val) => setState(() => _partnerValues = val),
                        onPartnerValuesSubmitted: (val) => unawaited(_saveProfileChanges(partnerValues: val)),
                        onPetsChanged: (val) {
                          setState(() => _pets = val);
                          unawaited(_saveProfileChanges(pets: val));
                        },
                        openBottomSelectionSheet: _openBottomSelectionSheet,
                        onDrinkingSaved: (val) => unawaited(_saveProfileChanges(drinking: val)),
                        onSmokingSaved: (val) => unawaited(_saveProfileChanges(smoking: val)),
                        onChildrenPlansSaved: (val) => unawaited(_saveProfileChanges(childrenPlans: val)),
                        onReligiousBeliefsSaved: (val) => unawaited(_saveProfileChanges(religiousBeliefs: val)),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Card Layer E: Affinity & Interests
                    _buildStaggeredEntrance(
                      index: 6,
                      child: AffinityInterestsSection(
                        key: _affinityInterestsKey,
                        flatSubInterests: _flatSubInterests,
                        causesSupported: _causesSupported,
                        topArtists: _topArtists,
                        isSavingInterests: _savingFields.contains('interests'),
                        isSavingCauses: _savingFields.contains('causesSupported'),
                        isSavingTopArtists: _savingFields.contains('topArtists'),
                        onInterestsSaved: (val) {
                          final newSubInterests = <String, List<String>>{};
                          for (final item in val) {
                            final parts = item.split(': ');
                            if (parts.length == 2) {
                              newSubInterests.putIfAbsent(parts[0], () => []).add(parts[1]);
                            }
                          }
                          final newInterests = <String, int>{};
                          newSubInterests.forEach((parent, subs) {
                            var weight = 1;
                            if (subs.length == 2) weight = 2;
                            if (subs.length >= 3) weight = 3;
                            newInterests[parent] = weight;
                          });
                          setState(() {
                            _subInterests = newSubInterests;
                          });
                          unawaited(
                            _saveProfileChanges(
                              interests: newInterests,
                              subInterests: newSubInterests,
                            ),
                          );
                        },
                        onCausesSupportedChanged: (val) {
                          setState(() => _causesSupported = val);
                          unawaited(_saveProfileChanges(causesSupported: val));
                        },
                        onTopArtistsChanged: (val) {
                          setState(() => _topArtists = val);
                          unawaited(_saveProfileChanges(topArtists: val));
                        },
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
          ),
        ],
      ),
    );
  }
}

class FuturisticBackgroundPainter extends CustomPainter {
  const FuturisticBackgroundPainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    // Colors based on theme brightness (higher contrast for light mode)
    final gridAlpha = isDark ? 0.04 : 0.08;
    final primaryOrbitColor = isDark ? const Color(0xFF00E5FF) : const Color(0xFF0891B2);
    final secondaryOrbitColor = isDark ? const Color(0xFFFF7597) : const Color(0xFFE91E63);
    final tertiaryOrbitColor = isDark ? const Color(0xFF6366F1) : const Color(0xFF4F46E5);

    final lineAlpha = isDark ? 0.08 : 0.16;
    final glowAlpha = isDark ? 0.06 : 0.12;
    final starAlpha = isDark ? 0.25 : 0.40;

    // 1. Grid/Matrix Coordinate Dots
    final dotPaint = Paint()
      ..color = isDark ? Colors.white.withValues(alpha: gridAlpha) : Colors.black.withValues(alpha: gridAlpha * 0.8)
      ..style = PaintingStyle.fill;

    const spacing = 45.0;
    for (var x = spacing / 2; x < size.width; x += spacing) {
      for (var y = spacing / 2; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.2, dotPaint);
      }
    }

    final center = Offset(size.width * 0.5, size.height * 0.12);

    // 2. Radial Telemetry Rays (Faint rays from center coordinate)
    final rayPaint = Paint()
      ..color = isDark ? Colors.white.withValues(alpha: isDark ? 0.015 : 0.035) : Colors.black.withValues(alpha: 0.02)
      ..strokeWidth = 0.8;
    const rayCount = 12;
    const double angleStep = (2 * 3.1415926535) / rayCount;
    for (var i = 0; i < rayCount; i++) {
      final double angle = i * angleStep;
      canvas.drawLine(
        center,
        Offset(
          center.dx + size.height * 0.8 * double.parse(center.dx.sign.toString()) * 0.5 + 300 * math.cos(angle),
          center.dy + size.height * 0.8 + 300 * math.sin(angle),
        ),
        rayPaint,
      );
    }

    // 3. Multi-colored Cosmic Orbits (Concentric dashed circles)
    final colors = [primaryOrbitColor, secondaryOrbitColor, tertiaryOrbitColor, primaryOrbitColor];
    final radii = [110.0, 230.0, 350.0, 480.0];

    for (var r = 0; r < radii.length; r++) {
      final radius = radii[r];
      final orbitPaint = Paint()
        ..color = colors[r].withValues(alpha: lineAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;

      // Draw dashed circle
      const dashCount = 80;
      final sweepAngle = (2 * 3.1415926535) / dashCount;
      for (var i = 0; i < dashCount; i++) {
        if (i % 2 == 0) {
          canvas.drawArc(
            Rect.fromCircle(center: center, radius: radius),
            i * sweepAngle,
            sweepAngle,
            false,
            orbitPaint,
          );
        }
      }
    }

    // 4. Constellations & Star Coordinate Nodes
    final pathPaint = Paint()
      ..color = secondaryOrbitColor.withValues(alpha: lineAlpha * 1.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final starPaint = Paint()
      ..color = primaryOrbitColor.withValues(alpha: starAlpha)
      ..style = PaintingStyle.fill;

    final starGlowPaint = Paint()
      ..color = primaryOrbitColor.withValues(alpha: glowAlpha)
      ..style = PaintingStyle.fill;

    final nodes = [
      Offset(size.width * 0.12, size.height * 0.25),
      Offset(size.width * 0.26, size.height * 0.40),
      Offset(size.width * 0.08, size.height * 0.58),
      Offset(size.width * 0.88, size.height * 0.28),
      Offset(size.width * 0.74, size.height * 0.45),
      Offset(size.width * 0.90, size.height * 0.62),
      Offset(size.width * 0.20, size.height * 0.78),
      Offset(size.width * 0.38, size.height * 0.88),
    ];

    // Connect constellations
    canvas
      ..drawLine(nodes[0], nodes[1], pathPaint)
      ..drawLine(nodes[1], nodes[2], pathPaint)
      ..drawLine(nodes[3], nodes[4], pathPaint)
      ..drawLine(nodes[4], nodes[5], pathPaint)
      ..drawLine(nodes[6], nodes[7], pathPaint);

    // Draw nodes
    for (final node in nodes) {
      canvas
        ..drawCircle(node, 8.0, starGlowPaint) // Outer glow ring
        ..drawCircle(node, 3.5, starPaint);     // Core coordinate star
    }

    // 5. Technical Corner Brackets (Corner design elements)
    final bracketPaint = Paint()
      ..color = tertiaryOrbitColor.withValues(alpha: lineAlpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    const bracketSize = 14.0;
    const margin = 12.0;

    // Top Left Bracket
    canvas
      ..drawLine(const Offset(margin, margin), const Offset(margin + bracketSize, margin), bracketPaint)
      ..drawLine(const Offset(margin, margin), const Offset(margin, margin + bracketSize), bracketPaint);

    // Top Right Bracket
    canvas
      ..drawLine(Offset(size.width - margin, margin), Offset(size.width - margin - bracketSize, margin), bracketPaint)
      ..drawLine(Offset(size.width - margin, margin), Offset(size.width - margin, margin + bracketSize), bracketPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    if (oldDelegate is FuturisticBackgroundPainter) {
      return oldDelegate.isDark != isDark;
    }
    return true;
  }
}
