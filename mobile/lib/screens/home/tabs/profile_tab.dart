import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/features/profile/providers/client_ai_image_provider.dart';
import 'package:nexus/screens/home/widgets/export_code_card.dart';
import 'package:nexus/utils/network_utils.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Modular Imports
import 'profile/utils/emoji_helper.dart';
import 'profile/widgets/cosmic_selection_overlay.dart';
import 'profile/widgets/profile_header.dart';
import 'profile/widgets/stability_tracker.dart';
import 'profile/widgets/storage_image.dart';
import 'profile/sections/bio_section.dart';
import 'profile/sections/core_signal_section.dart';
import 'profile/sections/social_coordinates_section.dart';
import 'profile/sections/lifestyle_resonance_section.dart';
import 'profile/sections/affinity_interests_section.dart';

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
  String _name = 'Alex';
  int _age = 21;
  int _savedAge = 21;
  int _year = 3;
  String _pronouns = 'they/them';
  String _campusName = '';
  bool _isStudying = true;
  String _major = '';
  // ignore: unused_field
  String _vibeMode = 'deep';
  String _displayGender = 'Not specified';
  String _displaySexuality = 'Not specified';
  List<String> _searchBuckets = [];
  bool _isSavingDetails = false;
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
  // ignore: unused_field
  String _role = 'Not specified';
  // ignore: unused_field
  List<String> _targetBuckets = [];
  // ignore: unused_field
  List<String> _lookingFor = [];
  // ignore: unused_field
  List<String> _activities = [];
  List<String> _causesSupported = [];
  List<String> _topArtists = [];
  // ignore: unused_field
  List<String> _techSkills = [];
  List<String> _languages = [];
  // ignore: unused_field
  List<String> _vibeTags = [];
  List<String> _pets = [];
  // ignore: unused_field
  Map<String, int> _interests = {};
  Map<String, List<String>> _subInterests = {};
  List<String> get _flatSubInterests {
    final list = <String>[];
    _subInterests.forEach((parent, subs) {
      for (final sub in subs) {
        list.add('$parent: $sub');
      }
    });
    return list;
  }

  // Profile images slot paths: supports up to 5 images (1 primary profile pic + 4 gallery pics)
  final List<String?> _imagePaths = [null, null, null, null, null];

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
            if (data['campus_year'] != null) {
              _year = (data['campus_year'] as num).toInt();
              _isStudying = _year > 0;
            } else {
              _isStudying = false;
            }
            String cleanVal(dynamic val) {
              if (val == null) return '';
              final s = val.toString().trim();
              if (s.toLowerCase() == 'not specified') return '';
              return s;
            }

            _major = cleanVal(data['campus_branch']);
            _campusName = cleanVal(data['campus_name']);
            _displayGender =
                data['display_gender']?.toString() ?? 'Not specified';
            _displaySexuality =
                data['display_sexuality']?.toString() ?? 'Not specified';
            _pronouns = data['pronouns']?.toString() ?? 'they/them';
            _bio = data['bio']?.toString() ?? '';
            _hometown = cleanVal(data['hometown']);
            _currentPlace = cleanVal(data['current_place']);
            _partnerValues = data['partner_values']?.toString() ?? '';
            _childrenPlans =
                data['children_plans']?.toString() ?? 'Not specified';
            _religiousBeliefs =
                data['religious_beliefs']?.toString() ?? 'Not specified';
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

            final rawInterests = data['interests'];
            if (rawInterests is Map) {
              _interests = Map<String, int>.from(
                rawInterests.map(
                  (k, v) => MapEntry(k.toString(), (v as num).toInt()),
                ),
              );
            } else {
              _interests = {};
            }

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

            final rawImages = data['ordered_images'];
            if (rawImages is List) {
              final List<String> loadedImages = List<String>.generate(5, (i) {
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

            final rawVibe = data['ai_vibe_tags'];
            if (rawVibe is List) {
              _vibeTags = rawVibe.map((e) => e.toString()).toList();
            } else {
              _vibeTags = [];
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
    String? pronouns,
    String? bio,
    List<String>? searchBuckets,
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
        if (displaySexuality != null)
          payload['display_sexuality'] = displaySexuality;
        if (pronouns != null) payload['pronouns'] = pronouns;
        if (bio != null) payload['bio'] = bio;
        if (searchBuckets != null) payload['search_buckets'] = searchBuckets;
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
        if (religiousBeliefs != null)
          payload['religious_beliefs'] = religiousBeliefs;
        if (lifestyle != null) payload['lifestyle'] = lifestyle;
        if (drinking != null) payload['drinking'] = drinking;
        if (smoking != null) payload['smoking'] = smoking;
        if (role != null) payload['role'] = role;
        if (targetBuckets != null) payload['target_buckets'] = targetBuckets;
        if (lookingFor != null) payload['looking_for'] = lookingFor;
        if (activities != null) payload['activities'] = activities;
        if (causesSupported != null)
          payload['causes_supported'] = causesSupported;
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
              if (age != null) _savedAge = age;
              if (name != null) _name = name;
              if (displayGender != null) _displayGender = displayGender;
              if (displaySexuality != null)
                _displaySexuality = displaySexuality;
              if (pronouns != null) _pronouns = pronouns;
              if (bio != null) _bio = bio;
              if (searchBuckets != null) _searchBuckets = searchBuckets;
              if (campusBranch != null) _major = campusBranch;
              if (campusYear != null) {
                _year = campusYear;
              } else if (clearCampusYear) {
                _year = 0;
              }
              if (campusName != null) _campusName = campusName;
              if (hometown != null) _hometown = hometown;
              if (currentPlace != null) _currentPlace = currentPlace;
              if (partnerValues != null) _partnerValues = partnerValues;
              if (childrenPlans != null) _childrenPlans = childrenPlans;
              if (religiousBeliefs != null)
                _religiousBeliefs = religiousBeliefs;
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
              if (interests != null) _interests = interests;
              if (subInterests != null) _subInterests = subInterests;
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
    } finally {
      if (mounted) {
        setState(() => _isSavingDetails = false);
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
    if (_searchBuckets.isNotEmpty) filled++;
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
          final Set<String> uniqueTags = {};
          for (final tags in providerState.slotSpecificVibeTags.values) {
            uniqueTags.addAll(tags);
          }
          setState(() {
            for (int i = 0; i < _imagePaths.length; i++) {
              if (i < providerState.remotePaths.length && providerState.remotePaths[i].isNotEmpty) {
                _imagePaths[i] = providerState.remotePaths[i];
              } else {
                _imagePaths[i] = null;
              }
            }
            _vibeTags = uniqueTags.toList();
          });
        }
      } catch (e) {
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
        final Set<String> uniqueTags = {};
        for (final tags in providerState.slotSpecificVibeTags.values) {
          uniqueTags.addAll(tags);
        }
        setState(() {
          for (int i = 0; i < _imagePaths.length; i++) {
            if (i < providerState.remotePaths.length && providerState.remotePaths[i].isNotEmpty) {
              _imagePaths[i] = providerState.remotePaths[i];
            } else {
              _imagePaths[i] = null;
            }
          }
          _vibeTags = uniqueTags.toList();
        });
      }
    } catch (e) {
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
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (context) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF161B26).withValues(alpha: 0.98),
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
                    Icon(
                      slotIndex == 0 ? LucideIcons.user : LucideIcons.image,
                      color: const Color(0xFFFF7597),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      slotIndex == 0 ? 'Profile Avatar' : 'Gallery - Slot $slotIndex',
                      style: const TextStyle(
                        color: Colors.white,
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
                  style: const TextStyle(
                    color: Colors.white54,
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
                      leading: const Icon(
                        LucideIcons.refreshCw,
                        color: Colors.white70,
                      ),
                      title: const Text(
                        'Replace Image',
                        style: TextStyle(color: Colors.white),
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
                  const Text(
                    'Upload an image from your device gallery to represent you in this slot.',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7C3AED),
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
    unawaited(
      showModalBottomSheet<String>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (context) {
          final searchController = TextEditingController();
          return StatefulBuilder(
            builder: (context, setModalState) {
              final filteredOptions = options.where((option) {
                return option.toLowerCase().contains(
                  searchController.text.toLowerCase(),
                );
              }).toList();

              return Container(
                padding: EdgeInsets.only(
                  top: 24,
                  left: 24,
                  right: 24,
                  bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF161B26).withValues(alpha: 0.95),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(30),
                    topRight: Radius.circular(30),
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Outfit',
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              LucideIcons.search,
                              color: Colors.white38,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: searchController,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Search...',
                                  hintStyle: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.25),
                                    fontSize: 12,
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
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          physics: const ClampingScrollPhysics(),
                          itemCount: filteredOptions.length,
                          itemBuilder: (context, index) {
                            final option = filteredOptions[index];
                            final isSelected = option == currentValue;
                            return Material(
                              color: Colors.transparent,
                              child: ListTile(
                                onTap: () {
                                  Navigator.pop(context, option);
                                },
                                title: Row(
                                  children: [
                                    if (getEmojiForTag(option).isNotEmpty) ...[
                                      Text(
                                        getEmojiForTag(option),
                                        style: const TextStyle(fontSize: 16),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    Expanded(
                                      child: Text(
                                        option,
                                        style: TextStyle(
                                          color: isSelected
                                              ? const Color(0xFFFF7597)
                                              : Colors.white,
                                          fontFamily: 'Outfit',
                                          fontWeight: isSelected
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: isSelected
                                    ? const Icon(
                                        LucideIcons.check,
                                        color: Color(0xFFFF7597),
                                      )
                                    : null,
                              ),
                            );
                          },
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
      child: Column(
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
                // 🪐 1. Pulsing & Rotating Profile Header
                ProfileHeader(
                  avatarPath: _imagePaths[0],
                  name: _name,
                  rotationController: rotationController,
                  pulseController: pulseController,
                  isProcessingAI: providerState.isProcessingAI,
                  isSaving: providerState.isSaving,
                  hasPendingUpload: providerState.pendingUploads.containsKey(0),
                  onAvatarTap: () => _showImageSlotPicker(0),
                ),
                const SizedBox(height: 20),

                // Stability Tracker Card
                StabilityTracker(
                  stabilityPercentage: _calculateStability(),
                  imagePaths: _imagePaths,
                  name: _name,
                  age: _age,
                  bio: _bio,
                  searchBuckets: _searchBuckets,
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
                ),
                const SizedBox(height: 24),

                // 🌌 2. Modular Custom Universe Cards
                // Card Layer A: The Core Signal
                CoreSignalSection(
                  name: _name,
                  age: _age,
                  savedAge: _savedAge,
                  searchBuckets: _searchBuckets,
                  displayGender: _displayGender,
                  displaySexuality: _displaySexuality,
                  pronouns: _pronouns,
                  imagePaths: _imagePaths,
                  isProcessingAI: providerState.isProcessingAI,
                  isSaving: providerState.isSaving,
                  pendingUploads: providerState.pendingUploads,
                  onNameChanged: (val) => setState(() => _name = val),
                  onNameSubmitted: (val) => unawaited(_saveProfileChanges(name: val)),
                  onAgeChanged: (val) => setState(() => _age = val),
                  onAgeConfirmed: (val) => unawaited(_saveProfileChanges(age: val)),
                  onBucketChanged: (val) {
                    setState(() => _searchBuckets = val);
                    unawaited(_saveProfileChanges(searchBuckets: val));
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

                // Card Layer B: Cosmic Signature (Bio)
                BioSection(
                  bio: _bio,
                  onBioChanged: (val) => setState(() => _bio = val),
                  onBioSubmitted: (val) => unawaited(_saveProfileChanges(bio: val)),
                ),

                // Card Layer C: Social Coordinates
                SocialCoordinatesSection(
                  hometown: _hometown,
                  currentPlace: _currentPlace,
                  languages: _languages,
                  campusName: _campusName,
                  major: _major,
                  isStudying: _isStudying,
                  year: _year,
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

                // Card Layer D: Lifestyle & Resonance
                LifestyleResonanceSection(
                  lifestyle: _lifestyle,
                  drinking: _drinking,
                  smoking: _smoking,
                  childrenPlans: _childrenPlans,
                  religiousBeliefs: _religiousBeliefs,
                  partnerValues: _partnerValues,
                  pets: _pets,
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

                // Card Layer E: Affinity & Interests
                AffinityInterestsSection(
                  flatSubInterests: _flatSubInterests,
                  causesSupported: _causesSupported,
                  topArtists: _topArtists,
                  onInterestsSaved: (val) {
                    final Map<String, List<String>> newSubInterests = {};
                    for (final item in val) {
                      final parts = item.split(': ');
                      if (parts.length == 2) {
                        newSubInterests.putIfAbsent(parts[0], () => []).add(parts[1]);
                      }
                    }
                    final Map<String, int> newInterests = {};
                    newSubInterests.forEach((parent, subs) {
                      int weight = 1;
                      if (subs.length == 2) weight = 2;
                      if (subs.length >= 3) weight = 3;
                      newInterests[parent] = weight;
                    });
                    setState(() {
                      _subInterests = newSubInterests;
                      _interests = newInterests;
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
    );
  }
}
