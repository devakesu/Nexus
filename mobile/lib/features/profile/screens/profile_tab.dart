import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/config/app_config.dart';
import 'package:nexus/core/config/filter_options.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/core/utils/app_refresh_notifier.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/core/utils/error_handler.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:nexus/core/utils/secure_profile_cache.dart';
import 'package:nexus/core/widgets/aesthetic_loaders.dart';
import 'package:nexus/core/widgets/consent_prompt_dialog.dart';
import 'package:nexus/core/widgets/nexus_toast.dart';
import 'package:nexus/features/home/widgets/custom_bottom_nav_bar.dart';
import 'package:nexus/features/home/widgets/export_code_card.dart';
import 'package:nexus/features/profile/providers/client_ai_image_provider.dart';
import 'package:nexus/features/profile/utils/emoji_helper.dart';
import 'package:nexus/features/profile/widgets/cosmic_selection_overlay.dart';
import 'package:nexus/features/profile/widgets/futuristic_background_painter.dart';
import 'package:nexus/features/profile/widgets/place_autocomplete_field.dart';
import 'package:nexus/features/profile/widgets/profile_field_edit_sheet.dart';
import 'package:nexus/features/profile/widgets/profile_header.dart';
import 'package:nexus/features/profile/widgets/sections/affinity_interests_section.dart';
import 'package:nexus/features/profile/widgets/sections/bio_section.dart';
import 'package:nexus/features/profile/widgets/sections/core_signal_section.dart';
import 'package:nexus/features/profile/widgets/sections/lifestyle_resonance_section.dart';
import 'package:nexus/features/profile/widgets/sections/social_coordinates_section.dart';
import 'package:nexus/features/profile/widgets/sections/spotify_artists_section.dart';
import 'package:nexus/features/profile/widgets/stability_tracker.dart';
import 'package:nexus/features/profile/widgets/storage_image.dart';
import 'package:nexus/features/spotify/providers/spotify_provider.dart';
import 'package:nexus/features/spotify/services/spotify_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class ProfileTab extends ConsumerStatefulWidget {
  const ProfileTab({
    required this.onOpenOrbit,
    this.targetSection,
    this.onClearTargetSection,
    super.key,
  });

  final void Function(String, Color) onOpenOrbit;
  final String? targetSection;
  final VoidCallback? onClearTargetSection;

  @override
  ConsumerState<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends ConsumerState<ProfileTab>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  AnimationController? _pulseController;
  AnimationController? _rotationController;
  late PageController _pageController;
  late final Dio _dio;
  late final SpotifyService _spotifyService;
  final SupabaseClient _client = Supabase.instance.client;
  StreamSubscription<void>? _profileRefreshSub;

  // Loading state
  bool _isLoading = true;
  // True while a background network reconciliation is in flight after
  // instantly rendering a cached snapshot - never blocks the page.
  bool _isRevalidating = false;

  // Core profile state loaded from DB/Onboarding
  String _name = '';
  int _age = 0;
  int _year = 0;

  // Age/name change-rate-limit eligibility, refreshed from the profile
  // details GET response - the backend is the single source of truth for
  // this date math (see app/api/user.py::get_profile_details).
  int _ageChangesUsedInWindow = 0;
  bool _ageChangeEligible = true;
  DateTime? _ageNextEligibleAt;
  int _nameChangesUsedInWindow = 0;
  bool _nameChangeEligible = true;
  DateTime? _nameNextEligibleAt;
  String _pronouns = '';
  String _campusName = '';
  bool _isStudying = true;
  String _major = '';
  String _displayGender = '';
  String _displaySexuality = '';
  String _searchBucket = 'NB';
  final Set<String> _savingFields = {};
  final Map<String, dynamic> _pendingProfilePayload = {};
  bool _isProfileSaving = false;

  String _mapPayloadKeyToField(String key) {
    switch (key) {
      case 'display_gender':
        return 'displayGender';
      case 'display_sexuality':
        return 'displaySexuality';
      case 'search_bucket':
        return 'searchBucket';
      case 'campus_branch':
        return 'campusBranch';
      case 'campus_year':
        return 'campusYear';
      case 'campus_name':
        return 'campusName';
      case 'current_place':
        return 'currentPlace';
      case 'religious_beliefs':
        return 'religiousBeliefs';
      case 'causes_supported':
        return 'causesSupported';
      case 'top_artists':
        return 'topArtists';
      case 'sub_interests':
      case 'interests':
        return 'interests';
      default:
        return key;
    }
  }

  String _bio = '';

  // Extended profile fields from DB migration
  String _hometown = '';
  String _currentPlace = '';

  String _religiousBeliefs = '';
  String _lifestyle = '';
  String _drinking = '';
  String _smoking = '';
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
  String _savedDisplayGender = '';
  String _savedDisplaySexuality = '';
  String _savedSearchBucket = 'NB';
  String _savedBio = '';
  String _savedHometown = '';
  String _savedCurrentPlace = '';

  String _savedReligiousBeliefs = '';
  String _savedLifestyle = '';
  String _savedDrinking = '';
  String _savedSmoking = '';
  List<String> _savedCausesSupported = [];
  List<String> _savedTopArtists = [];
  List<String> _savedLanguages = [];
  List<String> _savedPets = [];
  Map<String, List<String>> _savedSubInterests = {};

  // Profile images slot paths: supports up to 5 images (1 primary profile pic + 4 gallery pics)
  final List<String?> _imagePaths = [null, null, null, null, null];
  List<String?> _savedImagePaths = [null, null, null, null, null];
  final Set<int> _removingSlots = {};
  Timer? _saveImagesDebounceTimer;

  final GlobalKey _coreSignalKey = GlobalKey();
  final GlobalKey _bioKey = GlobalKey();
  final GlobalKey _socialCoordinatesKey = GlobalKey();
  final GlobalKey _campusNameKey = GlobalKey();
  final GlobalKey _majorKey = GlobalKey();
  final GlobalKey _lifestyleResonanceKey = GlobalKey();
  final GlobalKey _affinityInterestsKey = GlobalKey();
  final GlobalKey _spotifyArtistsKey = GlobalKey();
  final GlobalKey<PlaceAutocompleteFieldState> _hometownKey =
      GlobalKey<PlaceAutocompleteFieldState>();
  final GlobalKey<PlaceAutocompleteFieldState> _currentPlaceKey =
      GlobalKey<PlaceAutocompleteFieldState>();

  bool _isSpotifyConnecting = false;
  final ScrollController _scrollController = ScrollController();

  // Focus nodes for interactive completion triggers
  final FocusNode _bioFocusNode = FocusNode();
  final FocusNode _hometownFocusNode = FocusNode();
  final FocusNode _currentPlaceFocusNode = FocusNode();
  final FocusNode _campusNameFocusNode = FocusNode();
  final FocusNode _majorFocusNode = FocusNode();

  // Animation controller for staggered entry transition
  AnimationController? _entryController;

  void _scrollToSection(GlobalKey key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 100), () {
        final context = key.currentContext;
        if (context != null && context.mounted) {
          unawaited(
            Scrollable.ensureVisible(
              context,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOut,
              alignment: 0.3,
            ),
          );
        }
      });
    });
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

    final slideAnimation =
        Tween<Offset>(
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
    } else if (['Display Name', 'Age', 'Demographic Buckets'].contains(label)) {
      _scrollToSection(_coreSignalKey);
    } else if (label == 'Gender') {
      _openSelectionOverlay(
        title: 'Gender',
        options: FilterOptions.genderOptions,
        currentValue: _displayGender,
        onSelected: (val) => unawaited(_saveProfileChanges(displayGender: val)),
      );
    } else if (label == 'Sexuality') {
      _openSelectionOverlay(
        title: 'Sexuality',
        options: FilterOptions.sexualityOptions,
        currentValue: _displaySexuality,
        onSelected: (val) =>
            unawaited(_saveSpecialCategoryField(displaySexuality: val)),
      );
    } else if (label == 'Pronouns') {
      _openBottomSelectionSheet(
        title: 'Pronouns',
        options: FilterOptions.pronounOptions,
        currentValue: _pronouns,
        onSelected: (val) {
          setState(() => _pronouns = val);
          unawaited(_saveProfileChanges(pronouns: val));
        },
      );
    } else if (label == 'Cosmic Signature (Bio)') {
      _bioFocusNode.requestFocus();
      Future.delayed(const Duration(milliseconds: 300), () {
        _scrollToSection(_bioKey);
      });
    }
    // 2. Social & Campus Info
    else if (label == 'Hometown') {
      _scrollToSection(_socialCoordinatesKey);
      Future.delayed(const Duration(milliseconds: 350), () {
        _hometownKey.currentState?.openLocationPicker();
      });
    } else if (label == 'Current Place') {
      _scrollToSection(_socialCoordinatesKey);
      Future.delayed(const Duration(milliseconds: 350), () {
        _currentPlaceKey.currentState?.openLocationPicker();
      });
    } else if (label == 'Institute Name') {
      _campusNameFocusNode.requestFocus();
      Future.delayed(const Duration(milliseconds: 300), () {
        _scrollToSection(_campusNameKey);
      });
    } else if (label == 'Major') {
      _majorFocusNode.requestFocus();
      Future.delayed(const Duration(milliseconds: 300), () {
        _scrollToSection(_majorKey);
      });
    } else if (label == 'Languages') {
      _openMultiSelectSheet(
        title: 'Languages',
        currentValues: _languages,
        presets: FilterOptions.languages,
        onChanged: (val) {
          setState(() => _languages = val);
          unawaited(_saveProfileChanges(languages: val));
        },
        allowCustom: false,
      );
    } else if (label == 'Campus Year') {
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
    } else if (label == 'Religious Beliefs') {
      _openBottomSelectionSheet(
        title: 'Religious Beliefs',
        options: FilterOptions.religiousBeliefs,
        currentValue: _religiousBeliefs,
        onSelected: (val) =>
            unawaited(_saveSpecialCategoryField(religiousBeliefs: val)),
      );
    } else if (label == 'Pets') {
      _openMultiSelectSheet(
        title: 'Pets',
        currentValues: _pets,
        presets: FilterOptions.pets,
        onChanged: (val) {
          setState(() => _pets = val);
          unawaited(_saveProfileChanges(pets: val));
        },
      );
    } else if (label == 'Lifestyle Description') {
      _scrollToSection(_lifestyleResonanceKey);
    }
    // 4. Interests & Hobbies
    else if (['Interests', 'Causes Supported'].contains(label)) {
      _scrollToSection(_affinityInterestsKey);
    } else if (label == 'Top Artists') {
      _scrollToSection(_spotifyArtistsKey);
    }
  }

  void _scrollToTargetSection(String field) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      GlobalKey? key;
      FocusNode? focusNode;

      switch (field) {
        case 'name':
        case 'age':
        case 'profile_pic':
        case 'normal_pics':
          key = _coreSignalKey;
        case 'bio':
          key = _bioKey;
          focusNode = _bioFocusNode;
        case 'drinking':
        case 'smoking':
          key = _lifestyleResonanceKey;
        case 'interests':
        case 'sub_interests':
          key = _affinityInterestsKey;
        case 'hometown':
          key = _socialCoordinatesKey;
          focusNode = _hometownFocusNode;
        case 'current_place':
          key = _socialCoordinatesKey;
          focusNode = _currentPlaceFocusNode;
        case 'campus_name':
          key = _socialCoordinatesKey;
          focusNode = _campusNameFocusNode;
      }

      if (key != null) {
        _scrollToSection(key);
      }
      if (focusNode != null) {
        focusNode.requestFocus();
      }
      widget.onClearTargetSection?.call();
    });
  }

  @override
  void didUpdateWidget(covariant ProfileTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.targetSection != null &&
        widget.targetSection != oldWidget.targetSection) {
      _scrollToTargetSection(widget.targetSection!);
    }
  }

  @override
  void initState() {
    super.initState();
    _dio = createDio();
    _spotifyService = SpotifyService(_dio);
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

    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _pageController = PageController();
    _profileRefreshSub = ProfileRefreshNotifier.stream.listen((_) {
      if (mounted) {
        setState(() {
          if (!ConsentCacheManager.specialCategoryConsentGranted) {
            _displaySexuality = '';
            _savedDisplaySexuality = '';
            _religiousBeliefs = '';
            _savedReligiousBeliefs = '';
          }
        });
        unawaited(_loadProfileData(silent: true));
      }
    });
    WidgetsBinding.instance.addObserver(this);
    unawaited(_bootstrapProfileData());
    if (widget.targetSection != null) {
      _scrollToTargetSection(widget.targetSection!);
    }
  }

  /// Renders instantly from the last cached snapshot (if any) while
  /// reconciling with the network in the background, instead of blocking
  /// the whole page behind a spinner on every mount.
  Future<void> _bootstrapProfileData() async {
    final startTime = DateTime.now();
    final cached = await SecureProfileCache.read();
    if (cached != null && mounted) {
      setState(() {
        _applyProfileData(cached);
      });
    }
    await _loadProfileData(silent: cached != null, isBootstrap: true);

    // Only enforce minimum 1-second animation floor on cold launch (no cache)
    if (cached == null) {
      final elapsed = DateTime.now().difference(startTime);
      final remaining = const Duration(seconds: 1) - elapsed;
      if (remaining > Duration.zero) {
        await Future<void>.delayed(remaining);
      }
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
        _isRevalidating = false;
      });
      if (_entryController != null && !_entryController!.isCompleted) {
        unawaited(_entryController!.forward(from: 0));
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_profileRefreshSub?.cancel());
    _pulseController?.dispose();
    _rotationController?.dispose();
    _entryController?.dispose();
    _pageController.dispose();
    _scrollController.dispose();
    _bioFocusNode.dispose();
    _hometownFocusNode.dispose();
    _currentPlaceFocusNode.dispose();
    _campusNameFocusNode.dispose();
    _majorFocusNode.dispose();
    super.dispose();
  }

  bool _awaitingSpotifyReturn = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      if (_awaitingSpotifyReturn) {
        _awaitingSpotifyReturn = false;
        // Show overlay immediately, then wait for backend to finish its
        // OAuth callback before re-fetching.
        setState(() => _isSpotifyConnecting = true);
        unawaited(
          Future<void>.delayed(const Duration(seconds: 2)).then((_) async {
            if (!mounted) return;
            await _loadProfileData(silent: true);
            unawaited(ref.refresh(spotifyStatusProvider.future));
            if (mounted) setState(() => _isSpotifyConnecting = false);
          }),
        );
      } else {
        final pending = ref.read(clientAIImageManagerProvider).pendingUploads;
        if (pending.isNotEmpty || _removingSlots.isNotEmpty) {
          return;
        }
        unawaited(_loadProfileData(silent: true));
        unawaited(ref.refresh(spotifyStatusProvider.future));
      }
    }
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

  Future<void> _loadProfileData({
    bool silent = false,
    bool isBootstrap = false,
  }) async {
    setState(() {
      if (silent) {
        _isRevalidating = true;
      } else {
        _isLoading = true;
      }
    });
    try {
      final session = _client.auth.currentSession;
      if (session == null) {
        unawaited(_client.auth.signOut());
        return;
      }
      final config = AppConfig.current;
      final dio = _dio;
      final response = await dio.get<Map<String, dynamic>>(
        '${config.backendUrl}/api/v1/profile/details',
        options: Options(
          headers: {},
        ),
      );

      if (response.statusCode == 200 && response.data != null && mounted) {
        final data = response.data!;
        setState(() => _applyProfileData(data));
        unawaited(SecureProfileCache.write(data));
      }
    } on Object catch (e) {
      debugPrint('[ProfileTab] Error loading profile details: $e');
      if (mounted) {
        if (!silent) {
          final friendlyMsg = ErrorHandler.getFriendlyMessage(e);
          NexusToast.show(
            context,
            'Failed to load profile: $friendlyMsg',
            type: NexusToastType.error,
          );
        }

        // Handle session/auth failure specifically
        if (e is DioException) {
          final statusCode = e.response?.statusCode;
          if (statusCode == 401 || statusCode == 403) {
            // Unauthenticated/Session expired: logout/re-route to login
            unawaited(_client.auth.signOut());
          }
        }
      }
    } finally {
      if (mounted && !isBootstrap) {
        setState(() {
          _isLoading = false;
          _isRevalidating = false;
        });
        if (_entryController != null && !_entryController!.isCompleted) {
          unawaited(_entryController!.forward(from: 0));
        }
      }
    }
  }

  /// Populates all profile [State] fields from a `/api/v1/profile/details`
  /// JSON payload - shared by both the cache-read path (instant render) and
  /// the network-fetch path (initial load / background revalidation), so
  /// the ~25-field mapping logic only lives in one place. Callers are
  /// responsible for wrapping this in `setState`.
  void _applyProfileData(Map<String, dynamic> data) {
    _name = data['name']?.toString() ?? _name;
    _savedName = _name;

    _age = (data['age'] as num?)?.toInt() ?? _age;
    _savedAge = _age;

    _ageChangesUsedInWindow =
        (data['age_changes_used_in_window'] as num?)?.toInt() ?? 0;
    _ageChangeEligible = data['age_change_eligible'] as bool? ?? true;
    _ageNextEligibleAt = DateTime.tryParse(
      data['age_next_eligible_at']?.toString() ?? '',
    );
    _nameChangesUsedInWindow =
        (data['name_changes_used_in_window'] as num?)?.toInt() ?? 0;
    _nameChangeEligible = data['name_change_eligible'] as bool? ?? true;
    _nameNextEligibleAt = DateTime.tryParse(
      data['name_next_eligible_at']?.toString() ?? '',
    );

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

    String cleanSingle(dynamic val) {
      if (val == null) {
        return '';
      }
      final s = val.toString().trim();
      if (s.isEmpty ||
          s.toLowerCase() == 'not specified' ||
          s.toLowerCase() == 'prefer not to say') {
        return '';
      }
      return s;
    }

    _major = cleanVal(data['campus_branch']);
    _savedMajor = _major;

    _campusName = cleanVal(data['campus_name']);
    _savedCampusName = _campusName;

    _displayGender = cleanSingle(data['display_gender']);
    _savedDisplayGender = _displayGender;

    _displaySexuality = cleanSingle(data['display_sexuality']);
    _savedDisplaySexuality = _displaySexuality;

    _pronouns = cleanSingle(data['pronouns']);
    _savedPronouns = _pronouns;

    _bio = data['bio']?.toString() ?? '';
    _savedBio = _bio;

    _hometown = cleanVal(data['hometown']);
    _savedHometown = _hometown;

    _currentPlace = cleanVal(data['current_place']);
    _savedCurrentPlace = _currentPlace;

    _religiousBeliefs = cleanSingle(data['religious_beliefs']);
    _savedReligiousBeliefs = _religiousBeliefs;

    _lifestyle = data['lifestyle']?.toString() ?? '';
    _savedLifestyle = _lifestyle;

    _drinking = cleanSingle(data['drinking']);
    _savedDrinking = _drinking;

    _smoking = cleanSingle(data['smoking']);
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
      final pending = ref.read(clientAIImageManagerProvider).pendingUploads;
      final loadedImages = List<String>.generate(5, (i) {
        if (pending.containsKey(i) || _removingSlots.contains(i)) {
          return _imagePaths[i] ?? '';
        }
        if (i < rawImages.length &&
            rawImages[i] != null &&
            rawImages[i].toString().isNotEmpty) {
          _imagePaths[i] = rawImages[i].toString();
          return rawImages[i].toString();
        } else {
          _imagePaths[i] = null;
          return '';
        }
      });
      ref
          .read(clientAIImageManagerProvider.notifier)
          .setRemotePaths(loadedImages);
      _savedImagePaths = List<String?>.from(_imagePaths);
    }
    _memoizedStability = null;
  }

  /// Rebuilds the same JSON shape `/api/v1/profile/details` returns from
  /// the currently-committed (`_saved*`) state fields, so a successful save
  /// can write-through to the cache immediately instead of waiting on the
  /// next full reload to reflect the edit.
  Map<String, dynamic> _currentProfileSnapshot() {
    return {
      'name': _savedName,
      'age': _savedAge,
      'campus_year': _savedIsStudying ? _savedYear : null,
      'campus_branch': _savedMajor,
      'campus_name': _savedCampusName,
      'display_gender': _savedDisplayGender,
      'display_sexuality': _savedDisplaySexuality,
      'pronouns': _savedPronouns,
      'bio': _savedBio,
      'hometown': _savedHometown,
      'current_place': _savedCurrentPlace,
      'religious_beliefs': _savedReligiousBeliefs,
      'lifestyle': _savedLifestyle,
      'drinking': _savedDrinking,
      'smoking': _savedSmoking,
      'search_bucket': _savedSearchBucket,
      'causes_supported': _savedCausesSupported,
      'top_artists': _savedTopArtists,
      'languages': _savedLanguages,
      'pets': _savedPets,
      'sub_interests': _savedSubInterests,
      'ordered_images': _savedImagePaths,
    };
  }

  /// Gate for sexual-orientation/religious-belief fields specifically -
  /// both are optional/skippable, and setting either to a real disclosed
  /// value (not the "prefer not to say"/"not specified" opt-out, which
  /// never needs consent) requires special-category consent. Shows an
  /// inline bottom-sheet prompt if it hasn't been granted yet, and only
  /// proceeds with the save once it has (or already was). Backend also
  /// enforces this (update_profile_details -> assert_special_category_consent)
  /// so this is a UX nicety, not the only enforcement point.
  Future<void> _saveSpecialCategoryField({
    String? displaySexuality,
    String? religiousBeliefs,
  }) async {
    const sexualityOptOut = 'Prefer not to say';
    const religionOptOut = 'Prefer not to say';
    final needsConsent =
        (displaySexuality != null &&
            displaySexuality.isNotEmpty &&
            displaySexuality != sexualityOptOut) ||
        (religiousBeliefs != null &&
            religiousBeliefs.isNotEmpty &&
            religiousBeliefs != religionOptOut);

    if (needsConsent && !ConsentCacheManager.specialCategoryConsentGranted) {
      final granted = await _promptSpecialCategoryConsent();
      if (!granted) return;
    }

    unawaited(
      _saveProfileChanges(
        displaySexuality: displaySexuality,
        religiousBeliefs: religiousBeliefs,
      ),
    );
  }

  Future<bool> _promptSpecialCategoryConsent() async {
    var granted = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
        ),
        child: SpecialCategoryConsentPromptCard(
          onGranted: () {
            granted = true;
            Navigator.of(sheetContext).pop();
          },
        ),
      ),
    );
    return granted;
  }

  bool _areListsEqual(List<String>? a, List<String>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool _areMapsOfListsEqual(
    Map<String, List<String>>? a,
    Map<String, List<String>>? b,
  ) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      if (!_areListsEqual(a[key], b[key])) return false;
    }
    return true;
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
    var hasChanges = false;
    if (name != null && name != _savedName) hasChanges = true;
    if (age != null && age != _savedAge) hasChanges = true;
    if (displayGender != null && displayGender != _savedDisplayGender) {
      hasChanges = true;
    }
    if (displaySexuality != null &&
        displaySexuality != _savedDisplaySexuality) {
      hasChanges = true;
    }
    if (pronouns != null && pronouns != _savedPronouns) hasChanges = true;
    if (bio != null && bio != _savedBio) hasChanges = true;
    if (searchBucket != null && searchBucket != _savedSearchBucket) {
      hasChanges = true;
    }
    if (campusBranch != null && campusBranch != _savedMajor) hasChanges = true;
    if (campusYear != null && campusYear != _savedYear) hasChanges = true;
    if (clearCampusYear && _savedYear != 0) hasChanges = true;
    if (campusName != null && campusName != _savedCampusName) hasChanges = true;
    if (hometown != null && hometown != _savedHometown) hasChanges = true;
    if (currentPlace != null && currentPlace != _savedCurrentPlace) {
      hasChanges = true;
    }
    if (religiousBeliefs != null &&
        religiousBeliefs != _savedReligiousBeliefs) {
      hasChanges = true;
    }
    if (lifestyle != null && lifestyle != _savedLifestyle) hasChanges = true;
    if (drinking != null && drinking != _savedDrinking) hasChanges = true;
    if (smoking != null && smoking != _savedSmoking) hasChanges = true;
    if (causesSupported != null &&
        !_areListsEqual(causesSupported, _savedCausesSupported)) {
      hasChanges = true;
    }
    if (topArtists != null && !_areListsEqual(topArtists, _savedTopArtists)) {
      hasChanges = true;
    }
    if (languages != null && !_areListsEqual(languages, _savedLanguages)) {
      hasChanges = true;
    }
    if (pets != null && !_areListsEqual(pets, _savedPets)) hasChanges = true;
    if (subInterests != null &&
        !_areMapsOfListsEqual(subInterests, _savedSubInterests)) {
      hasChanges = true;
    }

    if (!hasChanges) {
      return;
    }

    if (bio != null && bio.trim().isNotEmpty) {
      final lettersCount = bio.replaceAll(RegExp('[^a-zA-Z]'), '').length;
      if (lettersCount < 3) {
        NexusToast.show(
          context,
          'Bio must contain at least three alphabetic characters.',
          type: NexusToastType.error,
        );
        return;
      }
    }

    final incomingPayload = <String, dynamic>{};
    if (name != null) incomingPayload['name'] = name;
    if (age != null) incomingPayload['age'] = age;
    if (displayGender != null) {
      incomingPayload['display_gender'] = displayGender.isEmpty
          ? 'Prefer not to say'
          : displayGender;
    }
    if (displaySexuality != null) {
      incomingPayload['display_sexuality'] = displaySexuality.isEmpty
          ? 'Prefer not to say'
          : displaySexuality;
    }
    if (pronouns != null) {
      incomingPayload['pronouns'] = pronouns.isEmpty
          ? 'Prefer not to say'
          : pronouns;
    }
    if (bio != null) incomingPayload['bio'] = bio;
    if (searchBucket != null) incomingPayload['search_bucket'] = searchBucket;
    if (campusBranch != null) incomingPayload['campus_branch'] = campusBranch;
    if (campusYear != null) {
      incomingPayload['campus_year'] = campusYear;
    } else if (clearCampusYear) {
      incomingPayload['campus_year'] = null;
    }
    if (campusName != null) incomingPayload['campus_name'] = campusName;
    if (hometown != null) incomingPayload['hometown'] = hometown;
    if (currentPlace != null) incomingPayload['current_place'] = currentPlace;
    if (currentPlace != null) incomingPayload['current_place'] = currentPlace;
    if (religiousBeliefs != null) {
      incomingPayload['religious_beliefs'] = religiousBeliefs.isEmpty
          ? 'Prefer not to say'
          : religiousBeliefs;
    }
    if (lifestyle != null) incomingPayload['lifestyle'] = lifestyle;
    if (drinking != null) {
      incomingPayload['drinking'] = drinking.isEmpty ? null : drinking;
    }
    if (smoking != null) {
      incomingPayload['smoking'] = smoking.isEmpty ? null : smoking;
    }
    if (role != null) incomingPayload['role_at'] = role;
    if (targetBuckets != null) {
      incomingPayload['target_buckets'] = targetBuckets;
    }
    if (lookingFor != null) incomingPayload['looking_for'] = lookingFor;
    if (activities != null) incomingPayload['activities'] = activities;
    if (causesSupported != null) {
      incomingPayload['causes_supported'] = causesSupported;
    }
    if (topArtists != null) incomingPayload['top_artists'] = topArtists;
    if (techSkills != null) incomingPayload['tech_skills'] = techSkills;
    if (languages != null) incomingPayload['languages'] = languages;
    if (pets != null) incomingPayload['pets'] = pets;
    if (interests != null) incomingPayload['interests'] = interests;
    if (subInterests != null) incomingPayload['sub_interests'] = subInterests;

    _pendingProfilePayload.addAll(incomingPayload);

    if (_isProfileSaving) {
      setState(() {
        for (final key in incomingPayload.keys) {
          _savingFields.add(_mapPayloadKeyToField(key));
        }
      });
      return;
    }

    _isProfileSaving = true;

    while (_pendingProfilePayload.isNotEmpty) {
      final currentPayload = Map<String, dynamic>.from(_pendingProfilePayload);
      _pendingProfilePayload.clear();

      final fields = currentPayload.keys.map(_mapPayloadKeyToField).toList();
      setState(() {
        _savingFields.addAll(fields);
      });

      try {
        final session = _client.auth.currentSession;
        if (session != null) {
          final config = AppConfig.current;
          final dio = _dio;

          final response = await dio.patch<Map<String, dynamic>>(
            '${config.backendUrl}/api/v1/profile/details',
            data: currentPayload,
          );

          if (response.statusCode == 200 && mounted) {
            setState(() {
              _memoizedStability = null;
              if (currentPayload.containsKey('name')) {
                _name = currentPayload['name'] as String;
                _savedName = _name;
              }
              if (currentPayload.containsKey('age')) {
                _age = currentPayload['age'] as int;
                _savedAge = _age;
              }
              if (currentPayload.containsKey('display_gender')) {
                final displayGender =
                    currentPayload['display_gender'] as String;
                _displayGender = displayGender == 'Prefer not to say'
                    ? ''
                    : displayGender;
                _savedDisplayGender = _displayGender;
              }
              if (currentPayload.containsKey('display_sexuality')) {
                final displaySexuality =
                    currentPayload['display_sexuality'] as String;
                _displaySexuality = displaySexuality == 'Prefer not to say'
                    ? ''
                    : displaySexuality;
                _savedDisplaySexuality = _displaySexuality;
              }
              if (currentPayload.containsKey('pronouns')) {
                final pronouns = currentPayload['pronouns'] as String;
                _pronouns = pronouns == 'Prefer not to say' ? '' : pronouns;
                _savedPronouns = pronouns;
              }
              if (currentPayload.containsKey('bio')) {
                _bio = currentPayload['bio'] as String;
                _savedBio = _bio;
              }
              if (currentPayload.containsKey('search_bucket')) {
                _searchBucket = currentPayload['search_bucket'] as String;
                _savedSearchBucket = _searchBucket;
              }
              if (currentPayload.containsKey('campus_branch')) {
                _major = currentPayload['campus_branch'] as String;
                _savedMajor = _major;
              }
              if (currentPayload.containsKey('campus_year')) {
                final val = currentPayload['campus_year'];
                if (val == null) {
                  _year = 0;
                  _savedYear = 0;
                } else {
                  _year = val as int;
                  _savedYear = _year;
                }
              }
              if (currentPayload.containsKey('campus_name')) {
                _campusName = currentPayload['campus_name'] as String;
                _savedCampusName = _campusName;
              }
              if (currentPayload.containsKey('hometown')) {
                _hometown = currentPayload['hometown'] as String;
                _savedHometown = _hometown;
              }
              if (currentPayload.containsKey('current_place')) {
                _currentPlace = currentPayload['current_place'] as String;
                _savedCurrentPlace = _currentPlace;
              }
              if (currentPayload.containsKey('religious_beliefs')) {
                final beliefs = currentPayload['religious_beliefs'] as String;
                _religiousBeliefs = beliefs == 'Prefer not to say'
                    ? ''
                    : beliefs;
                _savedReligiousBeliefs = _religiousBeliefs;
              }
              if (currentPayload.containsKey('lifestyle')) {
                _lifestyle = currentPayload['lifestyle'] as String;
                _savedLifestyle = _lifestyle;
              }
              if (currentPayload.containsKey('drinking')) {
                final d = currentPayload['drinking'];
                _drinking = d == null ? '' : d as String;
                _savedDrinking = _drinking;
              }
              if (currentPayload.containsKey('smoking')) {
                final s = currentPayload['smoking'];
                _smoking = s == null ? '' : s as String;
                _savedSmoking = _smoking;
              }
              if (currentPayload.containsKey('causes_supported')) {
                _causesSupported = List<String>.from(
                  currentPayload['causes_supported'] as List,
                );
                _savedCausesSupported = List<String>.from(_causesSupported);
              }
              if (currentPayload.containsKey('top_artists')) {
                _topArtists = List<String>.from(
                  currentPayload['top_artists'] as List,
                );
                _savedTopArtists = List<String>.from(_topArtists);
              }
              if (currentPayload.containsKey('languages')) {
                _languages = List<String>.from(
                  currentPayload['languages'] as List,
                );
                _savedLanguages = List<String>.from(_languages);
              }
              if (currentPayload.containsKey('pets')) {
                _pets = List<String>.from(currentPayload['pets'] as List);
                _savedPets = List<String>.from(_pets);
              }
              if (currentPayload.containsKey('sub_interests')) {
                _subInterests = Map<String, List<String>>.from(
                  currentPayload['sub_interests'] as Map,
                );
                _savedSubInterests = Map<String, List<String>>.from(
                  _subInterests,
                );
              }
            });
            unawaited(SecureProfileCache.write(_currentProfileSnapshot()));
            if (currentPayload.containsKey('age') ||
                currentPayload.containsKey('name')) {
              unawaited(_loadProfileData(silent: true));
            }

            if (mounted) {
              NexusToast.show(
                context,
                'Cosmic frequency synchronized.',
                type: NexusToastType.success,
                duration: const Duration(seconds: 2),
              );
            }
          } else {
            throw Exception(
              'API responded with status code: ${response.statusCode}',
            );
          }
        }
      } on Object catch (e) {
        debugPrint('[ProfileTab] Error saving profile details: $e');
        if (mounted) {
          setState(() {
            if (currentPayload.containsKey('name')) _name = _savedName;
            if (currentPayload.containsKey('age')) _age = _savedAge;
            if (currentPayload.containsKey('display_gender')) {
              _displayGender = _savedDisplayGender;
            }
            if (currentPayload.containsKey('display_sexuality')) {
              _displaySexuality = _savedDisplaySexuality;
            }
            if (currentPayload.containsKey('pronouns')) {
              _pronouns = _savedPronouns;
            }
            if (currentPayload.containsKey('bio')) _bio = _savedBio;
            if (currentPayload.containsKey('search_bucket')) {
              _searchBucket = _savedSearchBucket;
            }
            if (currentPayload.containsKey('campus_branch')) {
              _major = _savedMajor;
            }
            if (currentPayload.containsKey('campus_year')) {
              _year = _savedYear;
              _isStudying = _savedIsStudying;
            }
            if (currentPayload.containsKey('campus_name')) {
              _campusName = _savedCampusName;
            }
            if (currentPayload.containsKey('hometown')) {
              _hometown = _savedHometown;
            }
            if (currentPayload.containsKey('current_place')) {
              _currentPlace = _savedCurrentPlace;
            }
            if (currentPayload.containsKey('religious_beliefs')) {
              _religiousBeliefs = _savedReligiousBeliefs;
            }
            if (currentPayload.containsKey('lifestyle')) {
              _lifestyle = _savedLifestyle;
            }
            if (currentPayload.containsKey('drinking')) {
              _drinking = _savedDrinking;
            }
            if (currentPayload.containsKey('smoking')) _smoking = _savedSmoking;
            if (currentPayload.containsKey('causes_supported')) {
              _causesSupported = List<String>.from(_savedCausesSupported);
            }
            if (currentPayload.containsKey('top_artists')) {
              _topArtists = List<String>.from(_savedTopArtists);
            }
            if (currentPayload.containsKey('languages')) {
              _languages = List<String>.from(_savedLanguages);
            }
            if (currentPayload.containsKey('pets')) {
              _pets = List<String>.from(_savedPets);
            }
            if (currentPayload.containsKey('sub_interests') ||
                currentPayload.containsKey('interests')) {
              _subInterests = Map<String, List<String>>.from(
                _savedSubInterests,
              );
            }
          });

          final friendlyMsg = ErrorHandler.getFriendlyMessage(e);
          NexusToast.show(
            context,
            'Failed to synchronize cosmic frequency: $friendlyMsg',
            type: NexusToastType.error,
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
    _isProfileSaving = false;
  }

  int? _memoizedStability;

  int _calculateStability() {
    if (_memoizedStability != null) return _memoizedStability!;
    var filled = 0;
    const total = 27;

    // 1. The Core Signal
    if (_imagePaths[0] != null && _imagePaths[0]!.isNotEmpty) filled++;
    if (_name.isNotEmpty) filled++;
    if (_age >= 18) filled++;
    if (_bio.isNotEmpty) filled++;
    if (_searchBucket.isNotEmpty) filled++;
    if (_displayGender.isNotEmpty) filled++;
    if (_displaySexuality.isNotEmpty) filled++;
    if (_pronouns.isNotEmpty) filled++;
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
    if (_drinking.isNotEmpty) filled++;
    if (_smoking.isNotEmpty) filled++;
    if (_religiousBeliefs.isNotEmpty) filled++;
    if (_pets.isNotEmpty) filled++;

    // 4. Affinity & Interests
    if (_subInterests.isNotEmpty) filled++;
    if (_causesSupported.isNotEmpty) filled++;
    if (_topArtists.isNotEmpty) filled++;

    final result = ((filled / total) * 100).round();
    _memoizedStability = result;
    return result;
  }

  // Entrypoint: picks native Android SSO or browser fallback automatically.
  Future<void> _connectSpotify() async {
    if (Platform.isAndroid) {
      await _connectSpotifyNative();
    } else {
      await _connectSpotifyBrowser();
    }
  }

  // Native path: Spotify Android Auth Library → one-tap SSO if Spotify app is installed,
  // Chrome Custom Tabs otherwise. Token is sent to our backend which fetches top artists.
  Future<void> _connectSpotifyNative() async {
    final session = _client.auth.currentSession;
    if (session == null) return;

    setState(() => _isSpotifyConnecting = true);
    try {
      final code = await _spotifyService.requestNativeAuthCode();
      if (code == null || code.isEmpty || !mounted) return;

      final artists = await _spotifyService.exchangeNativeCode(code);
      if (!mounted) return;
      setState(() {
        _topArtists = artists;
        _savedTopArtists = List<String>.from(artists);
      });
      unawaited(ref.refresh(spotifyStatusProvider.future));
      NexusToast.show(
        context,
        'Synced ${artists.length} top artists. Your playlists are syncing '
        'in the background.',
        type: NexusToastType.success,
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      if (e.code == 'SPOTIFY_AUTH_CANCELLED') return;
      // Native Spotify app rejected the request - fall back to browser OAuth.
      if (e.message == 'AUTHENTICATION_SERVICE_UNAVAILABLE') {
        setState(() => _isSpotifyConnecting = false);
        await _connectSpotifyBrowser();
        return;
      }
      NexusToast.show(
        context,
        'Spotify auth failed: ${e.message ?? e.code}',
        type: NexusToastType.error,
      );
    } on Object catch (e) {
      if (!mounted) return;
      NexusToast.show(
        context,
        'Failed to connect Spotify: ${ErrorHandler.getFriendlyMessage(e)}',
        type: NexusToastType.error,
      );
    } finally {
      if (mounted) setState(() => _isSpotifyConnecting = false);
    }
  }

  // Browser fallback: server-side OAuth via backend /connect → /callback.
  // Used on non-Android platforms and as a fallback if native auth is unavailable.
  Future<void> _connectSpotifyBrowser() async {
    final session = _client.auth.currentSession;
    if (session == null) return;

    setState(() => _isSpotifyConnecting = true);
    try {
      final authUrl = await _spotifyService.fetchAuthUrl();
      if (mounted && authUrl != null) {
        _awaitingSpotifyReturn = true;
        await launchUrl(
          Uri.parse(authUrl),
          mode: LaunchMode.externalApplication,
        );
        // WidgetsBindingObserver.didChangeAppLifecycleState will fire when
        // the user returns from the browser and auto-reload profile data +
        // refresh spotifyStatusProvider - no manual dialog needed.
      }
    } on Object catch (e) {
      if (!mounted) return;
      NexusToast.show(
        context,
        'Failed to connect Spotify: ${ErrorHandler.getFriendlyMessage(e)}',
        type: NexusToastType.error,
      );
    } finally {
      if (mounted) setState(() => _isSpotifyConnecting = false);
    }
  }

  Future<void> _disconnectSpotify() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Disconnect Spotify?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This deletes your synced playlists and removes your top artists '
          'from your public profile. You can reconnect at any time. You may '
          'also want to revoke access from open.spotify.com/account/apps.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white38),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Disconnect',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await _spotifyService.disconnect();
      if (!mounted) return;
      setState(() {
        _topArtists = [];
        _savedTopArtists = [];
      });
      ref.invalidate(spotifyStatusProvider);
      NexusToast.show(
        context,
        'Spotify disconnected.',
        type: NexusToastType.success,
      );
    } on Object catch (e) {
      if (!mounted) return;
      NexusToast.show(
        context,
        'Failed to disconnect Spotify: ${ErrorHandler.getFriendlyMessage(e)}',
        type: NexusToastType.error,
      );
    }
  }

  void _debounceSaveImages() {
    _saveImagesDebounceTimer?.cancel();
    _saveImagesDebounceTimer = Timer(
      const Duration(milliseconds: 1500),
      () async {
        final userId = _client.auth.currentUser?.id;
        if (userId == null) return;
        try {
          final dio = _dio;
          await ref
              .read(clientAIImageManagerProvider.notifier)
              .commitProfileChanges(dio, userId);

          if (!mounted) return;

          // Save succeeded! Sync local state and update savedState
          final providerState = ref.read(clientAIImageManagerProvider);
          setState(() {
            for (var i = 0; i < _imagePaths.length; i++) {
              if (i < providerState.remotePaths.length &&
                  providerState.remotePaths[i].isNotEmpty) {
                _imagePaths[i] = providerState.remotePaths[i];
              } else {
                _imagePaths[i] = null;
              }
            }
            _savedImagePaths = List<String?>.from(_imagePaths);
            _removingSlots.clear();
          });
          unawaited(SecureProfileCache.write(_currentProfileSnapshot()));
        } on Object catch (e) {
          if (!mounted) return;
          // Restore from last known good state
          setState(() {
            _imagePaths
              ..clear()
              ..addAll(_savedImagePaths);
            _removingSlots.clear();
          });
          ref.read(clientAIImageManagerProvider.notifier).restoreBackup();

          final friendlyMsg = ErrorHandler.getFriendlyMessage(e);
          NexusToast.show(
            context,
            'Failed to save profile changes: $friendlyMsg',
            type: NexusToastType.error,
          );
        }
      },
    );
  }

  Future<void> _swapImages(int fromIndex, int toIndex) async {
    setState(() {
      final temp = _imagePaths[fromIndex];
      _imagePaths[fromIndex] = _imagePaths[toIndex];
      _imagePaths[toIndex] = temp;
    });

    try {
      ref
          .read(clientAIImageManagerProvider.notifier)
          .swapImageSlots(fromIndex, toIndex);
      _debounceSaveImages();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        final temp = _imagePaths[fromIndex];
        _imagePaths[fromIndex] = _imagePaths[toIndex];
        _imagePaths[toIndex] = temp;
      });
      final friendlyMsg = ErrorHandler.getFriendlyMessage(e);
      NexusToast.show(
        context,
        'Failed to swap images: $friendlyMsg',
        type: NexusToastType.error,
      );
    }
  }

  Future<void> _pickImage(int slotIndex) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return;

    // Enforce 1:1 square crop before any processing.
    final croppedFile = await _cropToSquare(pickedFile.path);
    if (croppedFile == null || !mounted) return;

    final file = File(croppedFile.path);
    final oldPaths = List<String?>.from(_imagePaths);
    setState(() {
      _imagePaths[slotIndex] = croppedFile.path;
    });

    try {
      // 1. Run local client-side vision AI model & stage cropped file
      await ref
          .read(clientAIImageManagerProvider.notifier)
          .stageImageSlot(slotIndex, file, userBranch: _major);

      if (!mounted) return;

      // 2. Trigger debounced save
      _debounceSaveImages();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _imagePaths[slotIndex] = oldPaths[slotIndex];
      });
      final friendlyMsg = ErrorHandler.getFriendlyMessage(e);
      NexusToast.show(
        context,
        e.toString().contains('Bucket not found')
            ? 'Failed to sync media: Storage bucket not configured'
            : 'Failed to sync media: $friendlyMsg',
        type: NexusToastType.error,
      );
    }
  }

  Future<CroppedFile?> _cropToSquare(String sourcePath) {
    return ImageCropper().cropImage(
      sourcePath: sourcePath,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop Photo',
          toolbarColor: const Color(0xFF0B0D13),
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: AppColors.pulsarPink,
          backgroundColor: const Color(0xFF0B0D13),
          dimmedLayerColor: Colors.black.withValues(alpha: 0.55),
          cropFrameColor: AppColors.pulsarPink,
          cropGridColor: Colors.white24,
          lockAspectRatio: true,
          hideBottomControls: false,
          showCropGrid: true,
        ),
        IOSUiSettings(
          title: 'Crop Photo',
          cancelButtonTitle: 'Cancel',
          doneButtonTitle: 'Done',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
          aspectRatioPickerButtonHidden: true,
        ),
      ],
    );
  }

  Future<void> _clearImage(int slotIndex) async {
    final oldPaths = List<String?>.from(_imagePaths);
    setState(() {
      _removingSlots.add(slotIndex);
    });

    try {
      // 1. Update Riverpod state removing the slot
      ref.read(clientAIImageManagerProvider.notifier).clearImageSlot(slotIndex);

      // 2. Trigger debounced save
      _debounceSaveImages();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _removingSlots.remove(slotIndex);
        _imagePaths
          ..clear()
          ..addAll(oldPaths);
      });
      final friendlyMsg = ErrorHandler.getFriendlyMessage(e);
      NexusToast.show(
        context,
        'Failed to clear image: $friendlyMsg',
        type: NexusToastType.error,
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
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(30),
                topRight: Radius.circular(30),
              ),
              border: Border.all(
                color: Colors.black.withValues(alpha: 0.08),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      slotIndex == 0 ? LucideIcons.user : LucideIcons.image,
                      color: AppColors.pulsarPink,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      slotIndex == 0
                          ? 'Profile Avatar'
                          : 'Gallery - Slot $slotIndex',
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
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
                    color: Colors.black54,
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
                        color: Colors.black87,
                      ),
                      title: const Text(
                        'Replace Image',
                        style: TextStyle(
                          color: AppColors.ink,
                        ),
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
                    style: TextStyle(
                      color: Colors.black54,
                      fontSize: 13,
                    ),
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
          final normalized = selected == 'Prefer not to say' ? '' : selected;
          onSelected(normalized);
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
        barrierColor: Colors.black.withValues(alpha: 0.4),
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
                  color: Colors.white,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(28),
                    topRight: Radius.circular(28),
                  ),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.08),
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
                            color: Colors.black.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: AppColors.ink,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            '${filteredOptions.length} options',
                            style: TextStyle(
                              color: Colors.black.withValues(alpha: 0.45),
                              fontSize: 11,
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
                            color: Colors.black.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.black.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                LucideIcons.search,
                                color: Colors.black45,
                                size: 16,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: searchController,
                                  style: const TextStyle(
                                    color: AppColors.ink,
                                    fontSize: 13,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'Search signals...',
                                    hintStyle: TextStyle(
                                      color: Colors.black.withValues(
                                        alpha: 0.35,
                                      ),
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
                                Semantics(
                                  button: true,
                                  label: 'Clear search',
                                  excludeSemantics: true,
                                  onTap: () {
                                    searchController.clear();
                                    setModalState(() {});
                                  },
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      searchController.clear();
                                      setModalState(() {});
                                    },
                                    child: const SizedBox(
                                      width: 44,
                                      height: 44,
                                      child: Center(
                                        child: Icon(
                                          LucideIcons.xCircle,
                                          color: Colors.black45,
                                          size: 16,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight:
                              MediaQuery.of(context).size.height *
                              (MediaQuery.of(context).viewInsets.bottom > 0
                                  ? 0.22
                                  : 0.45),
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
                            padding: const EdgeInsets.only(bottom: 20),
                            itemCount: filteredOptions.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final option = filteredOptions[index];
                              final isSelected = option == currentValue;
                              final tagIcon = getTagIcon(
                                option,
                                iconSize: 14,
                                iconColor: isSelected
                                    ? AppColors.pulsarPink
                                    : Colors.black26,
                              );

                              return GestureDetector(
                                onTap: () {
                                  Navigator.pop(
                                    context,
                                    isSelected ? null : option,
                                  );
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppColors.pulsarPink.withValues(
                                            alpha: 0.08,
                                          )
                                        : Colors.black.withValues(alpha: 0.02),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isSelected
                                          ? AppColors.pulsarPink.withValues(
                                              alpha: 0.45,
                                            )
                                          : Colors.black.withValues(
                                              alpha: 0.06,
                                            ),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      if (isSelected) ...[
                                        Container(
                                          width: 3,
                                          height: 14,
                                          decoration: BoxDecoration(
                                            color: AppColors.pulsarPink,
                                            borderRadius: BorderRadius.circular(
                                              1.5,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                      ],
                                      if (tagIcon != null) ...[
                                        tagIcon,
                                        const SizedBox(width: 12),
                                      ] else ...[
                                        Icon(
                                          LucideIcons.sparkles,
                                          size: 14,
                                          color: isSelected
                                              ? AppColors.pulsarPink
                                              : Colors.black26,
                                        ),
                                        const SizedBox(width: 12),
                                      ],
                                      Expanded(
                                        child: Text(
                                          option,
                                          style: TextStyle(
                                            color: isSelected
                                                ? AppColors.pulsarPink
                                                : Colors.black87,
                                            fontSize: 14,
                                            fontWeight: isSelected
                                                ? FontWeight.bold
                                                : FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      if (isSelected)
                                        const Icon(
                                          LucideIcons.checkCircle,
                                          color: AppColors.pulsarPink,
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
          final normalized =
              (selected == 'Prefer not to say' || selected == 'Not specified')
              ? ''
              : selected;
          onSelected(normalized);
        }
      }),
    );
  }

  void _openMultiSelectSheet({
    required String title,
    required List<String> currentValues,
    required List<String> presets,
    required ValueChanged<List<String>> onChanged,
    bool allowCustom = true,
  }) {
    final localSelected = List<String>.from(currentValues);
    final localPresets = List<String>.from(presets);

    for (final val in localSelected) {
      if (!localPresets.contains(val)) {
        localPresets.add(val);
      }
    }

    final textController = TextEditingController();
    final searchController = TextEditingController();

    unawaited(
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        barrierColor: Colors.black.withValues(alpha: 0.8),
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setModalState) {
              final showSearch = localPresets.length > 10;
              final filteredPresets = showSearch
                  ? localPresets.where((option) {
                      return option.toLowerCase().contains(
                        searchController.text.toLowerCase(),
                      );
                    }).toList()
                  : localPresets;

              return Container(
                padding: EdgeInsets.only(
                  top: 12,
                  left: 20,
                  right: 20,
                  bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(28),
                    topRight: Radius.circular(28),
                  ),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.08),
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
                            color: Colors.black.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: AppColors.ink,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text(
                              'Done',
                              style: TextStyle(
                                color: AppColors.pulsarPink,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (showSearch) ...[
                        TextField(
                          controller: searchController,
                          decoration: InputDecoration(
                            hintText: 'Search $title...',
                            prefixIcon: const Icon(
                              LucideIcons.search,
                              size: 16,
                              color: Colors.black38,
                            ),
                            filled: true,
                            fillColor: Colors.black.withValues(alpha: 0.03),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onChanged: (val) => setModalState(() {}),
                        ),
                        const SizedBox(height: 16),
                      ],
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight:
                              MediaQuery.of(context).size.height *
                              (MediaQuery.of(context).viewInsets.bottom > 0
                                  ? 0.22
                                  : 0.4),
                        ),
                        child: SingleChildScrollView(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: filteredPresets.map((option) {
                              final isSelected = localSelected.contains(option);
                              return FilterChip(
                                label: Text(option),
                                selected: isSelected,
                                onSelected: (selected) {
                                  setModalState(() {
                                    if (selected) {
                                      localSelected.add(option);
                                    } else {
                                      localSelected.remove(option);
                                    }
                                  });
                                  onChanged(localSelected);
                                },
                                selectedColor: AppColors.pulsarPink.withValues(
                                  alpha: 0.15,
                                ),
                                checkmarkColor: AppColors.pulsarPink,
                                labelStyle: TextStyle(
                                  color: isSelected
                                      ? AppColors.pulsarPink
                                      : const Color(0xFF334155),
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  fontSize: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  side: BorderSide(
                                    color: isSelected
                                        ? AppColors.pulsarPink.withValues(
                                            alpha: 0.5,
                                          )
                                        : Colors.black12,
                                  ),
                                ),
                                backgroundColor: Colors.transparent,
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                      if (allowCustom) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: textController,
                                  decoration: const InputDecoration(
                                    hintText: 'Add custom...',
                                    border: InputBorder.none,
                                    hintStyle: TextStyle(fontSize: 13),
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                  ),
                                  style: const TextStyle(fontSize: 13),
                                  onSubmitted: (val) {
                                    final trimmed = val.trim();
                                    if (trimmed.isNotEmpty &&
                                        !localPresets.contains(trimmed)) {
                                      setModalState(() {
                                        localPresets.add(trimmed);
                                        localSelected.add(trimmed);
                                      });
                                      onChanged(localSelected);
                                      textController.clear();
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Semantics(
                                button: true,
                                label: 'Add tag',
                                excludeSemantics: true,
                                onTap: () {
                                  final trimmed = textController.text.trim();
                                  if (trimmed.isNotEmpty &&
                                      !localPresets.contains(trimmed)) {
                                    setModalState(() {
                                      localPresets.add(trimmed);
                                      localSelected.add(trimmed);
                                    });
                                    onChanged(localSelected);
                                    textController.clear();
                                  }
                                },
                                child: GestureDetector(
                                  onTap: () {
                                    final trimmed = textController.text.trim();
                                    if (trimmed.isNotEmpty &&
                                        !localPresets.contains(trimmed)) {
                                      setModalState(() {
                                        localPresets.add(trimmed);
                                        localSelected.add(trimmed);
                                      });
                                      onChanged(localSelected);
                                      textController.clear();
                                    }
                                  },
                                  child: const Icon(
                                    LucideIcons.plusCircle,
                                    color: AppColors.pulsarPink,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ).then((_) {
        FocusManager.instance.primaryFocus?.unfocus();
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = AppConfig.current;
    // .select() instead of watching the whole 6-field provider state: this
    // build method only reads this field, so unrelated state changes
    // (remotePaths, isProcessingAI, isSaving, slotSpecificVibeTags,
    // pendingDeletions) no longer trigger a rebuild of this ~400-line
    // widget tree. A slot's spinner overlay is keyed off its presence in
    // this map alone, which is populated the instant an image is staged and
    // cleared only once the commit succeeds or fails - so it stays visible
    // for the entire staged-but-not-yet-committed window.
    final pendingUploads = ref.watch(
      clientAIImageManagerProvider.select((s) => s.pendingUploads),
    );

    final pulseController = _pulseController;
    final rotationController = _rotationController;

    if (_isLoading || pulseController == null || rotationController == null) {
      return ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: const Center(
          child: NexusOrbitLoader(lightMode: true),
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
          const Positioned.fill(
            child: CustomPaint(
              painter: FuturisticBackgroundPainter(),
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
                  scrollCacheExtent: const ScrollCacheExtent.pixels(9999),
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    0,
                    12,
                    0,
                    CustomBottomNavBar.clearance,
                  ),
                  children: [
                    // 🪐 1. Pulsing & Rotating Profile Header
                    _buildStaggeredEntrance(
                      index: 0,
                      child: ProfileHeader(
                        avatarPath: _imagePaths[0],
                        name: _name,
                        rotationController: rotationController,
                        pulseController: pulseController,
                        hasPendingUpload: pendingUploads.containsKey(0),
                        isRemoving: _removingSlots.contains(0),
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
                        religiousBeliefs: _religiousBeliefs,
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
                        searchBucket: _searchBucket,
                        displayGender: _displayGender,
                        displaySexuality: _displaySexuality,
                        pronouns: _pronouns,
                        imagePaths: _imagePaths,
                        pendingUploads: pendingUploads,
                        removingSlots: _removingSlots,
                        isSavingName: _savingFields.contains('name'),
                        isSavingGender: _savingFields.contains('displayGender'),
                        isSavingSexuality: _savingFields.contains(
                          'displaySexuality',
                        ),
                        isSavingPronouns: _savingFields.contains('pronouns'),
                        isSavingAge: _savingFields.contains('age'),
                        isSavingBuckets: _savingFields.contains('searchBucket'),
                        onNameTileTap: () => unawaited(
                          showNameChangeSheet(
                            context,
                            currentName: _name,
                            eligible: _nameChangeEligible,
                            changesUsedInWindow: _nameChangesUsedInWindow,
                            nextEligibleAt: _nameNextEligibleAt,
                            onConfirmed: (newName) =>
                                unawaited(_saveProfileChanges(name: newName)),
                          ),
                        ),
                        onAgeTileTap: () => unawaited(
                          showAgeChangeSheet(
                            context,
                            currentAge: _age,
                            eligible: _ageChangeEligible,
                            changesUsedInWindow: _ageChangesUsedInWindow,
                            nextEligibleAt: _ageNextEligibleAt,
                            onConfirmed: (newAge) =>
                                unawaited(_saveProfileChanges(age: newAge)),
                          ),
                        ),
                        onBucketChanged: (val) {
                          setState(() => _searchBucket = val);
                          unawaited(_saveProfileChanges(searchBucket: val));
                        },
                        onSelectGender: () {
                          _openSelectionOverlay(
                            title: 'Gender',
                            options: FilterOptions.genderOptions,
                            currentValue: _displayGender,
                            onSelected: (val) => unawaited(
                              _saveProfileChanges(displayGender: val),
                            ),
                          );
                        },
                        onClearGender: () =>
                            unawaited(_saveProfileChanges(displayGender: '')),
                        onSelectSexuality: () {
                          _openSelectionOverlay(
                            title: 'Sexuality',
                            options: FilterOptions.sexualityOptions,
                            currentValue: _displaySexuality,
                            onSelected: (val) => unawaited(
                              _saveSpecialCategoryField(displaySexuality: val),
                            ),
                          );
                        },
                        onClearSexuality: () => unawaited(
                          _saveProfileChanges(displaySexuality: ''),
                        ),
                        onSelectPronouns: () {
                          _openBottomSelectionSheet(
                            title: 'Pronouns',
                            options: FilterOptions.pronounOptions,
                            currentValue: _pronouns,
                            onSelected: (val) {
                              setState(() => _pronouns = val);
                              unawaited(_saveProfileChanges(pronouns: val));
                            },
                          );
                        },
                        onClearPronouns: () {
                          setState(() => _pronouns = '');
                          unawaited(_saveProfileChanges(pronouns: ''));
                        },
                        onImageSlotTap: _showImageSlotPicker,
                        onSwapImages: _swapImages,
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
                        onBioSubmitted: (val) =>
                            unawaited(_saveProfileChanges(bio: val)),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Card Layer C: Social Coordinates
                    _buildStaggeredEntrance(
                      index: 4,
                      child: SocialCoordinatesSection(
                        key: _socialCoordinatesKey,
                        campusNameKey: _campusNameKey,
                        majorKey: _majorKey,
                        hometownKey: _hometownKey,
                        currentPlaceKey: _currentPlaceKey,
                        hometown: _hometown,
                        currentPlace: _currentPlace,
                        languages: _languages,
                        campusName: _campusName,
                        savedCampusName: _savedCampusName,
                        major: _major,
                        isStudying: _isStudying,
                        year: _year,
                        isSavingHometown: _savingFields.contains('hometown'),
                        isSavingCurrentPlace: _savingFields.contains(
                          'currentPlace',
                        ),
                        isSavingCampusName: _savingFields.contains(
                          'campusName',
                        ),
                        isSavingMajor: _savingFields.contains('campusBranch'),
                        isSavingLanguages: _savingFields.contains('languages'),
                        isSavingCampusYear: _savingFields.contains(
                          'campusYear',
                        ),
                        hometownFocusNode: _hometownFocusNode,
                        currentPlaceFocusNode: _currentPlaceFocusNode,
                        campusNameFocusNode: _campusNameFocusNode,
                        majorFocusNode: _majorFocusNode,
                        onHometownChanged: (val) =>
                            setState(() => _hometown = val),
                        onHometownSubmitted: (val) =>
                            unawaited(_saveProfileChanges(hometown: val)),
                        onCurrentPlaceChanged: (val) =>
                            setState(() => _currentPlace = val),
                        onCurrentPlaceSubmitted: (val) =>
                            unawaited(_saveProfileChanges(currentPlace: val)),
                        onLanguagesChanged: (val) {
                          setState(() => _languages = val);
                          unawaited(_saveProfileChanges(languages: val));
                        },
                        onCampusNameChanged: (val) =>
                            setState(() => _campusName = val),
                        onCampusNameSubmitted: (val) {
                          final trimmed = val.trim();
                          if (trimmed.isEmpty) {
                            setState(() {
                              _campusName = '';
                              _isStudying = false;
                              _year = 0;
                            });
                            unawaited(
                              _saveProfileChanges(
                                campusName: '',
                                clearCampusYear: true,
                              ),
                            );
                          } else {
                            final lettersCount = trimmed
                                .replaceAll(RegExp('[^a-zA-Z]'), '')
                                .length;
                            if (lettersCount < 3) {
                              NexusToast.show(
                                context,
                                'Institute name must contain at least three letters.',
                                type: NexusToastType.error,
                              );
                              return;
                            }
                            unawaited(_saveProfileChanges(campusName: trimmed));
                          }
                        },
                        onMajorChanged: (val) => setState(() => _major = val),
                        onMajorSubmitted: (val) =>
                            unawaited(_saveProfileChanges(campusBranch: val)),
                        onIsStudyingChanged: (val) {
                          setState(() => _isStudying = val);
                          if (!val) {
                            unawaited(
                              _saveProfileChanges(clearCampusYear: true),
                            );
                          }
                        },
                        onYearChanged: (val) {
                          setState(() => _year = val);
                          unawaited(_saveProfileChanges(campusYear: val));
                        },
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Card Layer D: Affinity & Interests
                    _buildStaggeredEntrance(
                      index: 5,
                      child: AffinityInterestsSection(
                        key: _affinityInterestsKey,
                        flatSubInterests: _flatSubInterests,
                        causesSupported: _causesSupported,
                        isSavingInterests: _savingFields.contains('interests'),
                        isSavingCauses: _savingFields.contains(
                          'causesSupported',
                        ),
                        onInterestsSaved: (val) {
                          final newSubInterests = <String, List<String>>{};
                          for (final item in val) {
                            final parts = item.split(': ');
                            if (parts.length == 2) {
                              newSubInterests
                                  .putIfAbsent(parts[0], () => [])
                                  .add(parts[1]);
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
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Card Layer E: Music (Spotify top artists + playlists)
                    _buildStaggeredEntrance(
                      index: 6,
                      child: SpotifyMusicSection(
                        key: _spotifyArtistsKey,
                        topArtists: _topArtists,
                        isSaving: _savingFields.contains('topArtists'),
                        isConnecting: _isSpotifyConnecting,
                        onArtistRemoved: (artist) {
                          final updated = List<String>.from(_topArtists)
                            ..remove(artist);
                          setState(() => _topArtists = updated);
                          unawaited(
                            _saveProfileChanges(topArtists: updated),
                          );
                        },
                        onSpotifyConnect: _connectSpotify,
                        onSpotifyDisconnect: _disconnectSpotify,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Card Layer F: Lifestyle & Resonance
                    _buildStaggeredEntrance(
                      index: 7,
                      child: LifestyleResonanceSection(
                        key: _lifestyleResonanceKey,
                        lifestyle: _lifestyle,
                        drinking: _drinking,
                        smoking: _smoking,
                        religiousBeliefs: _religiousBeliefs,
                        pets: _pets,
                        isSavingLifestyle: _savingFields.contains('lifestyle'),
                        isSavingDrinking: _savingFields.contains('drinking'),
                        isSavingSmoking: _savingFields.contains('smoking'),
                        isSavingReligiousBeliefs: _savingFields.contains(
                          'religiousBeliefs',
                        ),
                        isSavingPets: _savingFields.contains('pets'),
                        onLifestyleChanged: (val) =>
                            setState(() => _lifestyle = val),
                        onLifestyleSubmitted: (val) =>
                            unawaited(_saveProfileChanges(lifestyle: val)),
                        onPetsChanged: (val) {
                          setState(() => _pets = val);
                          unawaited(_saveProfileChanges(pets: val));
                        },
                        openBottomSelectionSheet: _openBottomSelectionSheet,
                        onDrinkingSaved: (val) =>
                            unawaited(_saveProfileChanges(drinking: val)),
                        onClearDrinking: () =>
                            unawaited(_saveProfileChanges(drinking: '')),
                        onSmokingSaved: (val) =>
                            unawaited(_saveProfileChanges(smoking: val)),
                        onClearSmoking: () =>
                            unawaited(_saveProfileChanges(smoking: '')),
                        onReligiousBeliefsSaved: (val) => unawaited(
                          _saveSpecialCategoryField(religiousBeliefs: val),
                        ),
                        onClearReligiousBeliefs: () => unawaited(
                          _saveProfileChanges(religiousBeliefs: ''),
                        ),
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
          // Subtle, non-blocking signal that a cached snapshot is being
          // reconciled with the network - never covers page content.
          if (_isRevalidating)
            const Positioned(
              top: 8,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Center(
                  child: NexusOrbitLoader(size: 20, lightMode: true),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
