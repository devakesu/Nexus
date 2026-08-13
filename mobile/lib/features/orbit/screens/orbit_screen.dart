import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/config/app_config.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/core/utils/discovery_hub_cache.dart';
import 'package:nexus/core/utils/error_handler.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:nexus/core/utils/secure_profile_cache.dart';
import 'package:nexus/core/widgets/nexus_toast.dart';
import 'package:nexus/features/home/widgets/profile_detail_sheet.dart';
import 'package:nexus/features/orbit/models/orbit_node.dart';
import 'package:nexus/features/orbit/widgets/constellation_loader.dart';
import 'package:nexus/features/orbit/widgets/orbit_filters_panel.dart';
import 'package:nexus/features/orbit/widgets/orbit_interactive.dart';
import 'package:nexus/features/orbit/widgets/orbit_painters.dart';
import 'package:nexus/features/orbit/widgets/orbit_ui_helpers.dart';
import 'package:nexus/features/profile/widgets/storage_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OrbitScreen extends StatefulWidget {
  const OrbitScreen({
    required this.tab,
    required this.themeColor,
    this.prefetchFuture,
    super.key,
  });

  final String tab;
  final Color themeColor;
  final Future<OrbitPrefetchResult?>? prefetchFuture;

  static Future<OrbitPrefetchResult?> prefetch(String tab) async {
    final dio = createDio();
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) return null;
      final config = AppConfig.current;
      var showBuckets = <String>[];
      var datingFor = <String>[];
      var partnerValues = <String>[];
      String? profilePicUrl;

      // Try reading filter defaults from DiscoveryHubCache first
      final cachedHub = await DiscoveryHubCache.read(tab.toLowerCase());
      final cachedProfile =
          cachedHub?['profileDetails'] as Map<String, dynamic>?;

      var data = cachedProfile;
      if (data == null) {
        final profileResp = await dio.get<Map<String, dynamic>>(
          '${config.backendUrl}/api/v1/profile/details',
        );
        if (profileResp.statusCode == 200 && profileResp.data != null) {
          data = profileResp.data;
        }
      }

      if (data != null) {
        final rawImages = data['ordered_images'];
        if (rawImages is List && rawImages.isNotEmpty) {
          profilePicUrl = rawImages[0]?.toString();
        }
        if (tab == 'Dating') {
          final rawBuckets = data['dating_target_buckets'];
          if (rawBuckets is List) {
            showBuckets = rawBuckets.map((e) => e.toString()).toList();
          }
          final rawDatingFor = data['dating_for'];
          if (rawDatingFor is List) {
            datingFor = rawDatingFor.map((e) => e.toString()).toList();
          }
          final rawPartnerValues = data['partner_values'];
          if (rawPartnerValues is List) {
            partnerValues = rawPartnerValues.map((e) => e.toString()).toList();
          }
        }
      }

      final defaultAgeMax = config.isMainVariant ? 80 : 27;
      final payload = <String, dynamic>{
        'tab': tab,
        'filters': <String, dynamic>{
          'min_age': 18,
          'max_age': defaultAgeMax,
          if (tab == 'Dating') ...{
            if (showBuckets.isNotEmpty) 'search_bucket_filter': showBuckets,
            if (datingFor.isNotEmpty) 'dating_for': datingFor,
            if (partnerValues.isNotEmpty) 'partner_values': partnerValues,
          },
        },
      };

      final discoverResp = await dio.post<Map<String, dynamic>>(
        '${config.backendUrl}/api/v1/discover',
        data: payload,
      );

      if (discoverResp.statusCode == 200 && discoverResp.data != null) {
        final rawNodes = discoverResp.data!['nodes'] as List<dynamic>? ?? [];
        final mappedNodes = rawNodes
            .map((e) => OrbitNode.fromJson(e as Map<String, dynamic>))
            .toList();
        return OrbitPrefetchResult(
          nodes: mappedNodes,
          sessionId: discoverResp.data!['session_id'] as String?,
          profilePicUrl: profilePicUrl,
          showBuckets: showBuckets,
          datingFor: datingFor,
          partnerValues: partnerValues,
        );
      }
    } on Exception catch (e) {
      debugPrint('[OrbitScreen] Prefetch error: $e');
    }
    return null;
  }

  @override
  State<OrbitScreen> createState() => _OrbitScreenState();
}

class _OrbitScreenState extends State<OrbitScreen>
    with TickerProviderStateMixin {
  final TransformationController _transformationController =
      TransformationController();
  late AnimationController _pulseController;
  final Dio _dio = createDio();

  String? _sessionId;
  List<OrbitNode> _nodes = [];
  String? _errorMessage;
  String? _currentUserProfilePic;
  bool _isFetchingViewport = false;

  // Viewport/Canvas Size
  final double _canvasSize = 3200;

  // Filters State - general (all tabs)
  late RangeValues _ageRange = RangeValues(
    18,
    AppConfig.current.isMainVariant ? 80 : 27,
  );
  final List<int> _selectedYears = [1, 2, 3, 4, 5];
  final List<String> _selectedDrinking = [];
  final List<String> _selectedSmoking = [];
  final List<String> _selectedLanguages = [];
  final List<String> _selectedSubInterests = [];

  // Filters State - dating tab only
  final List<String> _selectedChildrenPlans = [];
  final List<String> _selectedReligiousBeliefs = [];
  final List<String> _selectedDatingFor = [];
  final List<String> _selectedShowBuckets = [];
  final List<String> _selectedPartnerValues = [];
  final Set<String> _dealbreakerFields = {};

  // Filters State - professional tab only
  final List<String> _selectedLookingFor = [];
  final List<String> _selectedCausesSupported = [];
  final List<String> _selectedTechSkills = [];

  final Set<String> _savingFields = {};
  final Map<String, dynamic> _pendingSaves = {};
  final Set<String> _activeSaves = {};
  bool _isCentered = false;
  bool _isReloading = false;
  Timer? _fetchDebounceTimer;

  // Tracks the platform's reduced-motion preference so the starfield twinkle,
  // radar sweep, and node breathing loops can freeze on a static frame
  // instead of animating indefinitely. Null until the first
  // didChangeDependencies pass resolves it.
  bool? _reduceMotion;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    if (widget.prefetchFuture != null) {
      unawaited(_applyPrefetchData());
    } else {
      unawaited(_initData());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion == _reduceMotion) return;
    _reduceMotion = reduceMotion;
    if (reduceMotion) {
      _pulseController
        ..stop()
        ..value = 0.5;
    } else {
      unawaited(_pulseController.repeat(reverse: true));
    }
  }

  Future<void> _applyPrefetchData() async {
    final future = widget.prefetchFuture;
    if (future == null) return;
    setState(() => _isReloading = true);
    try {
      final result = await future;
      if (!mounted) return;
      if (result != null) {
        setState(() {
          _sessionId = result.sessionId;
          _nodes = result.nodes;
          if (result.profilePicUrl != null) {
            _currentUserProfilePic = result.profilePicUrl;
          }
          if (widget.tab == 'Dating') {
            if (result.showBuckets.isNotEmpty) {
              _selectedShowBuckets
                ..clear()
                ..addAll(result.showBuckets);
            }
            if (result.datingFor.isNotEmpty) {
              _selectedDatingFor
                ..clear()
                ..addAll(result.datingFor);
            }
            if (result.partnerValues.isNotEmpty) {
              _selectedPartnerValues
                ..clear()
                ..addAll(result.partnerValues);
            }
          }
        });
        _precacheNodeImages(result.nodes);
      } else {
        await _initData();
      }
    } on Exception catch (e) {
      debugPrint('[OrbitScreen] Prefetch apply error: $e');
      if (mounted) await _initData();
    } finally {
      if (mounted) setState(() => _isReloading = false);
    }
  }

  Future<void> _initData({OrbitPrefetchResult? prefetch}) async {
    if (widget.tab == 'Dating') {
      if (prefetch != null) {
        setState(() {
          _selectedShowBuckets
            ..clear()
            ..addAll(prefetch.showBuckets);
          _selectedDatingFor
            ..clear()
            ..addAll(prefetch.datingFor);
          _selectedPartnerValues
            ..clear()
            ..addAll(prefetch.partnerValues);
        });
      } else {
        await _loadDatingProfileStatus();
      }
    }
    await _fetchOrbitNodes(skipProfileFetch: prefetch != null, immediate: true);
  }

  Future<void> _loadDatingProfileStatus() async {
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        final data = await NetworkUtils.fetchProfileDetails(
          _dio,
          session.accessToken,
        );

        if (data != null && mounted) {
          setState(() {
            final rawBuckets = data['dating_target_buckets'];
            if (rawBuckets is List) {
              _selectedShowBuckets
                ..clear()
                ..addAll(rawBuckets.map((e) => e.toString()));
            }
            final rawDatingFor = data['dating_for'];
            if (rawDatingFor is List) {
              _selectedDatingFor
                ..clear()
                ..addAll(rawDatingFor.map((e) => e.toString()));
            }
            final rawPartnerValues = data['partner_values'];
            if (rawPartnerValues is List) {
              _selectedPartnerValues
                ..clear()
                ..addAll(rawPartnerValues.map((e) => e.toString()));
            }
          });
        }
      }
    } on Exception catch (e) {
      debugPrint('[OrbitScreen] Error loading profile status: $e');
    }
  }

  Future<bool> _saveDatingProfileDetails(Map<String, dynamic> payload) async {
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        final config = AppConfig.current;
        final response = await _dio.patch<Map<String, dynamic>>(
          '${config.backendUrl}/api/v1/profile/details',
          data: payload,
        );
        return response.statusCode == 200;
      }
    } on Exception catch (e) {
      debugPrint('[OrbitScreen] Error saving dating details: $e');
    }
    return false;
  }

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
            final listCopy = List<String>.from(currentValueToSave as List);
            _selectedShowBuckets
              ..clear()
              ..addAll(listCopy);
          } else if (field == 'dating_for') {
            final listCopy = List<String>.from(currentValueToSave as List);
            _selectedDatingFor
              ..clear()
              ..addAll(listCopy);
          } else if (field == 'partner_values') {
            final listCopy = List<String>.from(currentValueToSave as List);
            _selectedPartnerValues
              ..clear()
              ..addAll(listCopy);
          }
        }
      });
      setState(() {});
      unawaited(_fetchOrbitNodes());
    }
  }

  void _openTagSelectionPane({
    required String title,
    required List<String> options,
    required List<String> selected,
    required StateSetter setModalState,
  }) {
    final localCopy = List<String>.from(selected);
    var searchQuery = '';
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setPaneState) {
              final filtered = options
                  .where(
                    (opt) =>
                        opt.toLowerCase().contains(searchQuery.toLowerCase()),
                  )
                  .toList();

              return Theme(
                data: ThemeData(
                  useMaterial3: true,
                  colorScheme: ColorScheme.fromSeed(
                    seedColor: widget.themeColor,
                    brightness: Brightness.dark,
                    surface: AppColors.ink,
                  ),
                ),
                child: Container(
                  height: MediaQuery.of(context).size.height * 0.7,
                  decoration: BoxDecoration(
                    color: AppColors.ink,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(32),
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 12),
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: widget.themeColor,
                                foregroundColor: AppColors.foregroundFor(
                                  widget.themeColor,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: () {
                                selected
                                  ..clear()
                                  ..addAll(localCopy);
                                setModalState(() {});
                                setState(() {});
                                unawaited(_fetchOrbitNodes());
                                Navigator.pop(context);
                              },
                              child: const Text('Done'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: TextField(
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Search...',
                            hintStyle: const TextStyle(color: Colors.white38),
                            prefixIcon: const Icon(
                              LucideIcons.search,
                              size: 18,
                              color: Colors.white38,
                            ),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.05),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                          onChanged: (v) {
                            setPaneState(() {
                              searchQuery = v;
                            });
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: filtered.map((opt) {
                                final sel = localCopy.contains(opt);
                                return FilterChip(
                                  label: Text(
                                    opt,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: sel
                                          ? widget.themeColor
                                          : Colors.white60,
                                    ),
                                  ),
                                  selected: sel,
                                  selectedColor: widget.themeColor.withValues(
                                    alpha: 0.15,
                                  ),
                                  backgroundColor: Colors.white.withValues(
                                    alpha: 0.05,
                                  ),
                                  checkmarkColor: widget.themeColor,
                                  side: BorderSide(
                                    color: sel
                                        ? widget.themeColor
                                        : Colors.white.withValues(alpha: 0.2),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  onSelected: (v) {
                                    setPaneState(() {
                                      if (v) {
                                        if (title ==
                                            'Select Religious Beliefs') {
                                          if (opt == 'Atheist' ||
                                              opt == 'Agnostic') {
                                            localCopy.removeWhere(
                                              (item) =>
                                                  item != 'Atheist' &&
                                                  item != 'Agnostic',
                                            );
                                          } else if (opt == 'Not specified') {
                                            localCopy.clear();
                                          } else {
                                            localCopy
                                              ..remove('Atheist')
                                              ..remove('Agnostic')
                                              ..remove('Not specified');
                                          }
                                        }
                                        localCopy.add(opt);
                                      } else {
                                        localCopy.remove(opt);
                                      }
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _openPartnerValuesSelectionPane({
    required StateSetter setModalState,
    required List<String> predefinedValues,
  }) {
    var searchQuery = '';
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setPaneState) {
              final filtered = predefinedValues
                  .where(
                    (opt) =>
                        opt.toLowerCase().contains(searchQuery.toLowerCase()),
                  )
                  .toList();

              final showCustomOption =
                  searchQuery.trim().isNotEmpty &&
                  !predefinedValues.any(
                    (val) =>
                        val.toLowerCase() == searchQuery.trim().toLowerCase(),
                  ) &&
                  !_selectedPartnerValues.any(
                    (val) =>
                        val.toLowerCase() == searchQuery.trim().toLowerCase(),
                  );

              return Theme(
                data: ThemeData(
                  useMaterial3: true,
                  colorScheme: ColorScheme.fromSeed(
                    seedColor: widget.themeColor,
                    brightness: Brightness.dark,
                    surface: AppColors.ink,
                  ),
                ),
                child: Container(
                  height: MediaQuery.of(context).size.height * 0.75,
                  decoration: BoxDecoration(
                    color: AppColors.ink,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(32),
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 12),
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Select Partner Values',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: widget.themeColor,
                                foregroundColor: AppColors.foregroundFor(
                                  widget.themeColor,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: () {
                                Navigator.pop(context);
                              },
                              child: const Text('Done'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: TextField(
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                          maxLength: 30,
                          decoration: InputDecoration(
                            hintText: 'Search or add custom value...',
                            hintStyle: const TextStyle(color: Colors.white38),
                            prefixIcon: const Icon(
                              LucideIcons.search,
                              size: 18,
                              color: Colors.white38,
                            ),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.05),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            counterText: '',
                          ),
                          onChanged: (v) {
                            setPaneState(() {
                              searchQuery = v;
                            });
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                if (showCustomOption &&
                                    searchQuery.trim().length <= 30)
                                  ActionChip(
                                    avatar: Icon(
                                      LucideIcons.plus,
                                      size: 14,
                                      color: AppColors.foregroundFor(
                                        widget.themeColor,
                                      ),
                                    ),
                                    label: Text('Add "${searchQuery.trim()}"'),
                                    backgroundColor: widget.themeColor,
                                    labelStyle: TextStyle(
                                      color: AppColors.foregroundFor(
                                        widget.themeColor,
                                      ),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    onPressed: () async {
                                      final customVal = searchQuery.trim();
                                      setPaneState(() {
                                        _selectedPartnerValues.add(customVal);
                                        searchQuery = '';
                                      });
                                      setModalState(() {});
                                      await _saveDatingField(
                                        'partner_values',
                                        _selectedPartnerValues,
                                        setModalState,
                                      );
                                    },
                                  ),
                                ...filtered.map((opt) {
                                  final sel = _selectedPartnerValues.contains(
                                    opt,
                                  );
                                  return FilterChip(
                                    label: Text(
                                      opt,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: sel
                                            ? widget.themeColor
                                            : Colors.white60,
                                      ),
                                    ),
                                    selected: sel,
                                    selectedColor: widget.themeColor.withValues(
                                      alpha: 0.15,
                                    ),
                                    backgroundColor: Colors.white.withValues(
                                      alpha: 0.05,
                                    ),
                                    checkmarkColor: widget.themeColor,
                                    side: BorderSide(
                                      color: sel
                                          ? widget.themeColor
                                          : Colors.white.withValues(alpha: 0.2),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    onSelected: (v) async {
                                      if (_savingFields.contains(
                                        'partner_values',
                                      )) {
                                        return;
                                      }
                                      setPaneState(() {
                                        if (v) {
                                          _selectedPartnerValues.add(opt);
                                        } else {
                                          _selectedPartnerValues.remove(opt);
                                        }
                                      });
                                      setModalState(() {});
                                      await _saveDatingField(
                                        'partner_values',
                                        _selectedPartnerValues,
                                        setModalState,
                                      );
                                    },
                                  );
                                }),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _fetchDebounceTimer?.cancel();
    _pulseController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  @override
  void reassemble() {
    super.reassemble();
    _isCentered = false;
  }

  void _centerViewport(double screenWidth, double screenHeight) {
    if (!mounted || _isCentered) return;
    if (screenWidth == 0 || screenHeight == 0) return;
    final size = _canvasSize;
    final x = (screenWidth - size) / 2;
    final y = (screenHeight - size) / 2;
    debugPrint(
      'Center Viewport: screenWidth=$screenWidth, screenHeight=$screenHeight, x=$x, y=$y',
    );

    _transformationController.value = Matrix4.translationValues(x, y, 0);
    _isCentered = true;
  }

  Future<void> _fetchOrbitNodes({
    bool useExistingSession = false,
    bool skipProfileFetch = false,
    bool immediate = false,
  }) async {
    _fetchDebounceTimer?.cancel();

    if (!immediate) {
      final completer = Completer<void>();
      _fetchDebounceTimer = Timer(const Duration(milliseconds: 500), () async {
        if (!mounted) return;
        try {
          await _executeFetchOrbitNodes(
            useExistingSession: useExistingSession,
            skipProfileFetch: skipProfileFetch,
          );
          completer.complete();
        } catch (e) {
          completer.completeError(e);
        }
      });
      return completer.future;
    }

    return _executeFetchOrbitNodes(
      useExistingSession: useExistingSession,
      skipProfileFetch: skipProfileFetch,
    );
  }

  Future<void> _executeFetchOrbitNodes({
    bool useExistingSession = false,
    bool skipProfileFetch = false,
  }) async {
    if (!mounted) return;
    setState(() {
      _errorMessage = null;
      _isReloading = true;
    });

    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) {
        throw Exception('User is not authenticated.');
      }

      final config = AppConfig.current;
      final payload = {
        'tab': widget.tab,
        'filters': {
          'min_age': _ageRange.start.round(),
          'max_age': _ageRange.end.round(),
          if (config.isFlavorVariant && _selectedYears.isNotEmpty)
            'campus_years': _selectedYears,
          if (_selectedDrinking.isNotEmpty) 'drinking': _selectedDrinking,
          if (_selectedSmoking.isNotEmpty) 'smoking': _selectedSmoking,
          if (_selectedLanguages.isNotEmpty) 'languages': _selectedLanguages,
          if (_selectedSubInterests.isNotEmpty)
            'sub_interests': _selectedSubInterests
                .map((e) => e.contains(': ') ? e.split(': ').last : e)
                .toList(),
          if (widget.tab == 'Dating') ...{
            if (_selectedChildrenPlans.isNotEmpty)
              'children_plans': _selectedChildrenPlans,
            if (_selectedReligiousBeliefs.isNotEmpty)
              'religious_beliefs': _selectedReligiousBeliefs,
            if (_selectedDatingFor.isNotEmpty) 'dating_for': _selectedDatingFor,
            if (_selectedShowBuckets.isNotEmpty)
              'search_bucket_filter': _selectedShowBuckets,
            if (_selectedPartnerValues.isNotEmpty)
              'partner_values': _selectedPartnerValues,
            if (_dealbreakerFields.isNotEmpty)
              'dealbreaker_fields': _dealbreakerFields.toList(),
          },
          if (widget.tab == 'Professional') ...{
            if (_selectedLookingFor.isNotEmpty)
              'looking_for': _selectedLookingFor,
            if (_selectedCausesSupported.isNotEmpty)
              'causes_supported': _selectedCausesSupported,
            if (_selectedTechSkills.isNotEmpty)
              'tech_skills': _selectedTechSkills,
          },
        },
        if (useExistingSession && _sessionId != null) 'session_id': _sessionId,
      };

      final discoverFuture = _dio.post<Map<String, dynamic>>(
        '${config.backendUrl}/api/v1/discover',
        data: payload,
      );

      final profileFuture = skipProfileFetch
          ? Future<Response<Map<String, dynamic>>?>.value()
          : _dio.get<Map<String, dynamic>>(
              '${config.backendUrl}/api/v1/profile/details',
            );

      final results = await Future.wait([discoverFuture, profileFuture]);
      final discoverResponse = results[0]!;
      final profileResponse = results[1];

      String? profilePicUrl;
      if (profileResponse != null &&
          profileResponse.statusCode == 200 &&
          profileResponse.data != null) {
        final profileData = profileResponse.data!;
        final rawImages = profileData['ordered_images'];
        if (rawImages is List && rawImages.isNotEmpty) {
          profilePicUrl = rawImages[0]?.toString();
        }
      }

      if (discoverResponse.statusCode == 200 && discoverResponse.data != null) {
        final rawNodes =
            discoverResponse.data!['nodes'] as List<dynamic>? ?? [];
        final mappedNodes = rawNodes
            .map((e) => OrbitNode.fromJson(e as Map<String, dynamic>))
            .toList();
        if (kDebugMode) {
          debugPrint(
            '--- CLIENT ORBIT NODES RECEIVED (${rawNodes.length}) ---',
          );
          for (final node in mappedNodes) {
            debugPrint(
              'Node: ${node.name}, x: ${node.x}, y: ${node.y}, tier: ${node.orbitTier}, score: ${node.score}',
            );
          }
        }
        if (!mounted) return;
        setState(() {
          _sessionId = discoverResponse.data!['session_id'] as String?;
          _nodes = mappedNodes;
          if (profilePicUrl != null) {
            _currentUserProfilePic = profilePicUrl;
          }
        });
        _precacheNodeImages(mappedNodes);
      } else {
        throw Exception('Failed to fetch orbit constellation.');
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isReloading = false;
        });
      }
    }
  }

  Future<void> _fetchViewportNodes(double viewWidth, double viewHeight) async {
    if (_isFetchingViewport || _sessionId == null) return;
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return;

    final matrix = _transformationController.value;
    final scale = matrix.getMaxScaleOnAxis();
    if (scale <= 0) return;

    final translationX = matrix.entry(0, 3);
    final translationY = matrix.entry(1, 3);

    final visibleCanvasCenterX = (viewWidth / 2 - translationX) / scale;
    final visibleCanvasCenterY = (viewHeight / 2 - translationY) / scale;

    final center = _canvasSize / 2;
    final centerX = visibleCanvasCenterX - center;
    final centerY = visibleCanvasCenterY - center;

    final screenHalfWidth = viewWidth / 2;
    final screenHalfHeight = viewHeight / 2;
    final screenDiagonal = math.sqrt(
      screenHalfWidth * screenHalfWidth + screenHalfHeight * screenHalfHeight,
    );
    var radius = (screenDiagonal / scale) * 1.2;
    if (radius > 2000.0) {
      radius = 2000.0;
    }
    if (radius <= 0) {
      radius = 100.0;
    }

    if (!mounted) return;
    setState(() {
      _isFetchingViewport = true;
    });

    try {
      final config = AppConfig.current;
      final response = await _dio.post<Map<String, dynamic>>(
        '${config.backendUrl}/api/v1/discover/viewport',
        data: {
          'tab': widget.tab,
          'session_id': _sessionId,
          'center_x': centerX,
          'center_y': centerY,
          'radius': radius,
        },
      );

      if (response.statusCode == 200 && response.data != null && mounted) {
        final newNodes = response.data!['nodes'] as List<dynamic>? ?? [];
        final newlyMappedNodes = <OrbitNode>[];
        setState(() {
          final nodeMap = {for (final node in _nodes) node.id: node};
          for (final node in newNodes) {
            if (node is Map<String, dynamic>) {
              final mapped = OrbitNode.fromJson(node);
              if (mapped.id.isNotEmpty) {
                nodeMap[mapped.id] = mapped;
                newlyMappedNodes.add(mapped);
              }
            }
          }
          _nodes = nodeMap.values.toList();
        });
        _precacheNodeImages(newlyMappedNodes);
      }
    } on Exception catch (e) {
      debugPrint('[OrbitScreen] Error fetching viewport nodes: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isFetchingViewport = false;
        });
      }
    }
  }

  /// Best-effort, fire-and-forget: warms the image cache for candidates
  /// that just landed in [_nodes], so a subsequent pan/swipe to them
  /// doesn't show a shimmer placeholder. Never awaited by callers - this
  /// must not delay the setState that actually shows the new nodes.
  void _precacheNodeImages(List<OrbitNode> nodes) {
    if (!mounted) return;
    for (final node in nodes) {
      final provider = resolveStorageImageProvider(node.profilePic);
      if (provider == null) continue;
      unawaited(precacheImage(provider, context).catchError((_) {}));
    }
  }

  void _passNode(String candidateId) {
    // Fire backend first - before any mounted/setState guard so it always runs.
    unawaited(_recordPassAction(candidateId));

    if (!mounted) return;

    final angle = math.Random().nextDouble() * 2 * math.pi;
    const radius = 540.0;
    setState(() {
      final idx = _nodes.indexWhere((n) => n.id == candidateId);
      if (idx != -1) {
        _nodes[idx] = _nodes[idx].copyWith(
          x: radius * math.cos(angle),
          y: radius * math.sin(angle),
          orbitTier: 3,
          score: 0,
        );
      }
    });

    NexusToast.show(context, 'Moved to deep space.');
  }

  Future<void> _recordPassAction(String candidateId) async {
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) return;
      final config = AppConfig.current;
      await _dio.post<dynamic>(
        '${config.backendUrl}/api/v1/discover/action',
        data: {'target_id': candidateId, 'action': 'pass', 'tab': widget.tab},
      );
    } on Exception catch (_) {}
  }

  Future<void> _performAction(
    String candidateId,
    String actionType, {
    String? reason,
    String? reasonDetail,
  }) async {
    final index = _nodes.indexWhere((n) => n.id == candidateId);
    OrbitNode? deletedNode;
    if (index != -1) {
      deletedNode = _nodes[index];
    }

    // Remove immediately from local state so the node vanishes before the network round-trip.
    if (mounted) {
      setState(() => _nodes.removeWhere((n) => n.id == candidateId));
    }

    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) return;

      final config = AppConfig.current;
      final omitTab = actionType == 'block' || actionType == 'unblock';
      final payload = <String, dynamic>{
        'target_id': candidateId,
        'action': actionType,
        if (!omitTab) 'tab': widget.tab,
        'reason': reason,
        'reason_detail': reasonDetail,
      };

      final response = await _dio.post<Map<String, dynamic>>(
        '${config.backendUrl}/api/v1/discover/action',
        data: payload,
      );

      if (response.statusCode == 200) {
        if (mounted) {
          final (
            NexusToastType toastType,
            String message,
          ) = switch (actionType) {
            'like' => (NexusToastType.success, 'Locked into your orbit.'),
            'superlike' => (
              NexusToastType.success,
              'You just shot them a star ✦',
            ),
            'block' => (NexusToastType.info, 'User blocked.'),
            'report' => (
              NexusToastType.info,
              'Report submitted. Thanks for keeping the space safe.',
            ),
            _ => (NexusToastType.info, 'User hidden.'),
          };
          NexusToast.show(context, message, type: toastType);
        }
      } else {
        throw Exception('Server returned status code ${response.statusCode}');
      }
    } on Exception catch (e) {
      if (mounted) {
        if (deletedNode != null) {
          setState(() {
            if (index != -1 && index <= _nodes.length) {
              _nodes.insert(index, deletedNode!);
            } else {
              _nodes.add(deletedNode!);
            }
          });
        }
        final friendlyMsg = ErrorHandler.getFriendlyMessage(e);
        NexusToast.show(
          context,
          'Action failed: $friendlyMsg',
          type: NexusToastType.error,
        );
      }
    }
  }

  Future<void> _showNodeDetails(String candidateId) async {
    final theme = widget.themeColor;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return FutureBuilder<Map<String, dynamic>>(
          future: () async {
            late Map<String, dynamic> data;
            await Future.wait<dynamic>([
              _fetchNodeDetails(candidateId).then((d) => data = d),
              Future<void>.delayed(const Duration(milliseconds: 1500)),
            ]);
            return data;
          }(),
          builder: (context, snapshot) {
            // ── Loading ──────────────────────────────────────────────────────
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Container(
                width: double.infinity,
                height: MediaQuery.of(context).size.height * 0.7,
                decoration: const BoxDecoration(
                  color: Color(0xFF090D1A),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned(
                      top: 12,
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    ConstellationLoader(
                      themeColor: theme,
                      label: 'LOCKING ONTO SIGNAL',
                    ),
                  ],
                ),
              );
            }

            // ── Error ────────────────────────────────────────────────────────
            if (snapshot.hasError || !snapshot.hasData) {
              return Container(
                height: MediaQuery.of(context).size.height * 0.4,
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

            final data = snapshot.data!;
            final name = data['name']?.toString() ?? 'Anonymous';

            return DraggableScrollableSheet(
              initialChildSize: 0.92,
              minChildSize: 0.5,
              maxChildSize: 0.97,
              expand: false,
              builder: (sheetCtx, scrollController) {
                return ProfileDetailSheet(
                  data: data,
                  themeColor: theme,
                  scrollController: scrollController,
                  actionBar: _buildOrbitActionBar(sheetCtx, candidateId, theme),
                  onSpotifyConnectRefresh: () async {
                    setState(() {});
                  },
                  onHideTap: (ctx) async {
                    Navigator.pop(ctx);
                    await _performAction(candidateId, 'hide');
                  },
                  onBlockTap: (ctx) async {
                    final ok = await showProfileBlockDialog(ctx, name);
                    if ((ok ?? false) && ctx.mounted) {
                      Navigator.pop(ctx);
                      await _performAction(candidateId, 'block');
                    }
                  },
                  onReportTap: (ctx) => showProfileReportDialog(
                    ctx,
                    themeColor: widget.themeColor,
                    onConfirmed: (reason, detail) async {
                      Navigator.pop(ctx);
                      await _performAction(
                        candidateId,
                        'report',
                        reason: reason,
                        reasonDetail: detail,
                      );
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

  Widget _buildOrbitActionBar(
    BuildContext context,
    String candidateId,
    Color theme,
  ) {
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
              onPressed: () {
                Navigator.pop(context);
                _passNode(candidateId);
              },
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
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () async {
                  Navigator.pop(context);
                  await _performAction(candidateId, 'superlike');
                },
                icon: const Icon(LucideIcons.star, size: 14),
                label: const Text(
                  'Super',
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
                onPressed: () async {
                  Navigator.pop(context);
                  await _performAction(candidateId, 'like');
                },
                icon: const Icon(LucideIcons.heart, size: 14),
                label: const Text(
                  'Pull to Orbit',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<Map<String, dynamic>> _fetchSelfDetails() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) throw Exception('Not authenticated.');

    final cached = await SecureProfileCache.read();
    if (cached != null) {
      final orderedImages = cached['ordered_images'] as List? ?? [];
      final cachedFormatted = {
        ...cached,
        'profile_pic': orderedImages.isNotEmpty ? orderedImages[0] : '',
        'normal_pics': orderedImages.length > 1
            ? orderedImages.sublist(1)
            : <dynamic>[],
        'tab': widget.tab,
        'score': 0,
      };
      unawaited(
        _networkFetchSelfDetails()
            .then((fresh) {
              if (fresh != null) {
                unawaited(SecureProfileCache.write(fresh));
              }
            })
            .catchError((_) {}),
      );
      return cachedFormatted;
    }

    final fresh = await _networkFetchSelfDetails();
    if (fresh == null) throw Exception('Failed to load your profile.');
    unawaited(SecureProfileCache.write(fresh));
    final orderedImages = fresh['ordered_images'] as List? ?? [];
    return {
      ...fresh,
      'profile_pic': orderedImages.isNotEmpty ? orderedImages[0] : '',
      'normal_pics': orderedImages.length > 1
          ? orderedImages.sublist(1)
          : <dynamic>[],
      'tab': widget.tab,
      'score': 0,
    };
  }

  Future<Map<String, dynamic>?> _networkFetchSelfDetails() async {
    final config = AppConfig.current;
    final results = await Future.wait<dynamic>([
      _dio.get<Map<String, dynamic>>(
        '${config.backendUrl}/api/v1/profile/details',
      ),
      _dio.get<Map<String, dynamic>>(
        '${config.backendUrl}/api/v1/profile/privacy-settings',
      ),
    ]);

    final profileResp = results[0] as Response<Map<String, dynamic>>;
    final privacyResp = results[1] as Response<Map<String, dynamic>>;

    if (profileResp.statusCode != 200 || profileResp.data == null) {
      return null;
    }

    final d = Map<String, dynamic>.from(profileResp.data!);
    final hiddenFields =
        (privacyResp.statusCode == 200 && privacyResp.data != null)
        ? (privacyResp.data!['hidden_fields'] as List<dynamic>? ?? [])
              .map((e) => e.toString())
              .toSet()
        : <String>{};

    const listFields = {'pets', 'top_artists', 'causes_supported'};
    for (final field in hiddenFields) {
      d[field] = listFields.contains(field) ? <dynamic>[] : null;
    }
    return d;
  }

  Future<void> _showSelfDetails() async {
    final theme = widget.themeColor;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return FutureBuilder<Map<String, dynamic>>(
          future: _fetchSelfDetails(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Container(
                width: double.infinity,
                height: MediaQuery.of(context).size.height * 0.7,
                decoration: const BoxDecoration(
                  color: Color(0xFF090D1A),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned(
                      top: 12,
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    ConstellationLoader(
                      themeColor: theme,
                      label: 'PREVIEWING YOUR SIGNAL',
                    ),
                  ],
                ),
              );
            }

            if (snapshot.hasError || !snapshot.hasData) {
              return Container(
                height: MediaQuery.of(context).size.height * 0.4,
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
              builder: (sheetCtx, scrollController) {
                return ProfileDetailSheet(
                  data: snapshot.data!,
                  themeColor: theme,
                  scrollController: scrollController,
                  isSelf: true,
                  showScoreBadge: false,
                  showSafetyActions: false,
                  onSpotifyConnectRefresh: () async {
                    // Pop the current sheet then reopen with fresh data
                    // so the synced artists/playlists appear immediately.
                    if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                    await Future<void>.delayed(
                      const Duration(milliseconds: 300),
                    );
                    if (mounted) unawaited(_showSelfDetails());
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Future<Map<String, dynamic>> _fetchNodeDetails(String candidateId) async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      throw Exception('Not authenticated.');
    }

    // If there is no session yet, create one first.
    if (_sessionId == null) {
      await _fetchOrbitNodes(immediate: true);
    }
    if (_sessionId == null) {
      throw Exception('No discovery session available.');
    }

    final config = AppConfig.current;
    final headers = Options();

    var response = await _dio.post<Map<String, dynamic>>(
      '${config.backendUrl}/api/v1/discover/node-detail',
      data: {'session_id': _sessionId, 'candidate_id': candidateId},
      options: headers,
    );

    if (response.statusCode == 200 && response.data != null) {
      return response.data!;
    }

    // 404 means the session expired. Silently refresh orbit (creates a new
    // session) then retry once - the candidate is usually still in the pool.
    if (response.statusCode == 404) {
      await _fetchOrbitNodes(immediate: true);
      if (_sessionId != null) {
        response = await _dio.post<Map<String, dynamic>>(
          '${config.backendUrl}/api/v1/discover/node-detail',
          data: {'session_id': _sessionId, 'candidate_id': candidateId},
          options: headers,
        );
        if (response.statusCode == 200 && response.data != null) {
          return response.data!;
        }
      }
    }

    throw Exception('Error loading detail response.');
  }

  void _showFiltersPanel() {
    final theme = widget.themeColor;
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (context) {
          return Theme(
            data: ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                seedColor: theme,
                brightness: Brightness.dark,
                surface: AppColors.ink,
              ),
            ),
            child: DraggableScrollableSheet(
              initialChildSize: 0.65,
              minChildSize: 0.4,
              maxChildSize: 0.95,
              expand: false,
              builder: (context, scrollController) {
                return OrbitFiltersPanel(
                  noUsersFound: _nodes.isEmpty,
                  tab: widget.tab,
                  themeColor: widget.themeColor,
                  ageRange: _ageRange,
                  selectedDrinking: _selectedDrinking,
                  selectedSmoking: _selectedSmoking,
                  selectedLanguages: _selectedLanguages,
                  selectedSubInterests: _selectedSubInterests,
                  selectedYears: _selectedYears,
                  selectedChildrenPlans: _selectedChildrenPlans,
                  selectedReligiousBeliefs: _selectedReligiousBeliefs,
                  selectedShowBuckets: _selectedShowBuckets,
                  selectedDatingFor: _selectedDatingFor,
                  selectedPartnerValues: _selectedPartnerValues,
                  dealbreakerFields: _dealbreakerFields,
                  selectedLookingFor: _selectedLookingFor,
                  selectedTechSkills: _selectedTechSkills,
                  savingFields: _savingFields,
                  onAgeRangeChanged: (values) {
                    setState(() {
                      _ageRange = values;
                    });
                  },
                  onAgeRangeChangeEnd: (values) {
                    unawaited(_fetchOrbitNodes());
                  },
                  onSaveDatingField: (field, value, setModalState) async {
                    await _saveDatingField(field, value, setModalState);
                  },
                  onOpenTagSelectionPane:
                      (title, options, selected, setModalState) {
                        _openTagSelectionPane(
                          title: title,
                          options: options,
                          selected: selected,
                          setModalState: setModalState,
                        );
                      },
                  onOpenPartnerValuesSelectionPane:
                      (setModalState, predefinedValues) {
                        _openPartnerValuesSelectionPane(
                          setModalState: setModalState,
                          predefinedValues: predefinedValues,
                        );
                      },
                  isRefreshing: _isReloading,
                  onFetchOrbitNodes: () async {
                    await _fetchOrbitNodes(immediate: true);
                  },
                  scrollController: scrollController,
                );
              },
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020408),
      body: Stack(
        children: [
          // Static Infinite Space Background
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return CustomPaint(
                  painter: CelestialBackgroundPainter(
                    themeColor: widget.themeColor,
                    pulseValue: _pulseController.value,
                  ),
                );
              },
            ),
          ),

          // Pannable Celestial Space
          LayoutBuilder(
            builder: (context, constraints) {
              if (!_isCentered) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _centerViewport(constraints.maxWidth, constraints.maxHeight);
                });
              }
              return InteractiveViewer(
                transformationController: _transformationController,
                minScale: 0.2,
                maxScale: 2,
                constrained: false,
                boundaryMargin: const EdgeInsets.all(1000),
                onInteractionEnd: (details) {
                  unawaited(
                    _fetchViewportNodes(
                      constraints.maxWidth,
                      constraints.maxHeight,
                    ),
                  );
                },
                child: SizedBox(
                  width: _canvasSize,
                  height: _canvasSize,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Capture gestures on empty space
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          child: const SizedBox(),
                        ),
                      ),
                      // Panning Coordinate Grid & Radar Sweep
                      Positioned.fill(
                        child: AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, child) {
                            return CustomPaint(
                              painter: OrbitGridPainter(
                                themeColor: widget.themeColor,
                                sweepValue: _pulseController.value,
                              ),
                            );
                          },
                        ),
                      ),

                      // Inter-node Constellation Lines
                      Positioned.fill(
                        child: AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, child) {
                            return CustomPaint(
                              painter: ConstellationLinesPainter(
                                nodes: _nodes,
                                themeColor: widget.themeColor,
                                pulseValue: _pulseController.value,
                              ),
                            );
                          },
                        ),
                      ),

                      // Concentric Orbit Rings
                      _buildOrbitRing(
                        100,
                        'Core Gravity',
                        AppColors.tint(
                          widget.themeColor,
                          0.45,
                        ).withValues(alpha: 0.12),
                        isDashed: false,
                        index: 0,
                      ),
                      _buildOrbitRing(
                        200,
                        'Inner Constellation',
                        AppColors.tint(
                          widget.themeColor,
                          0.45,
                        ).withValues(alpha: 0.10),
                        isDashed: true,
                        index: 1,
                      ),
                      _buildOrbitRing(
                        300,
                        'Mid Horizon',
                        AppColors.tint(
                          widget.themeColor,
                          0.45,
                        ).withValues(alpha: 0.08),
                        isDashed: false,
                        index: 2,
                      ),
                      _buildOrbitRing(
                        420,
                        'Deep Space Horizon',
                        AppColors.tint(
                          widget.themeColor,
                          0.45,
                        ).withValues(alpha: 0.06),
                        isDashed: true,
                        index: 3,
                      ),

                      // Pulsing Center Node (Viewer)
                      Center(
                        child: Semantics(
                          button: true,
                          label: 'Your profile',
                          excludeSemantics: true,
                          onTap: _showSelfDetails,
                          child: InteractiveOrbitNode(
                            onTap: _showSelfDetails,
                            child: _buildSelfAvatar(),
                          ),
                        ),
                      ),
                      // Floating Nodes
                      ..._buildConstellationNodes(),
                    ],
                  ),
                ),
              );
            },
          ),

          // Edge vignette - signals the starfield continues past the
          // viewport (pan to explore) instead of reading as clipped/broken.
          // Uses 4 edge-aligned strips rather than a RadialGradient: a
          // circular radial gradient sizes its radius off the shortest side,
          // which on a tall phone viewport over-darkens the vertical
          // top/bottom while barely reaching the horizontal edges - exactly
          // where clipped node chips actually sit.
          const IgnorePointer(
            child: Stack(
              children: [
                OrbitEdgeFade(alignment: Alignment.topCenter),
                OrbitEdgeFade(alignment: Alignment.bottomCenter),
                OrbitEdgeFade(alignment: Alignment.centerLeft),
                OrbitEdgeFade(alignment: Alignment.centerRight),
              ],
            ),
          ),

          // Header Overlay
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 8,
                bottom: 8,
                left: 16,
                right: 16,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF020408),
                    Color(0xFF020408),
                    Colors.transparent,
                  ],
                  stops: [0.0, 0.82, 1.0],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OrbitHeaderIconButton(
                          icon: LucideIcons.arrowLeft,
                          glowColor: widget.themeColor,
                          semanticLabel: 'Back',
                          onPressed: () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            widget.tab == 'Professional'
                                ? 'Pro Constellation'
                                : '${widget.tab} Constellation',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OrbitHeaderIconButton(
                        icon: LucideIcons.slidersHorizontal,
                        glowColor: widget.themeColor,
                        semanticLabel: 'Filters',
                        onPressed: _showFiltersPanel,
                      ),
                      OrbitHeaderIconButton(
                        icon: LucideIcons.refreshCw,
                        glowColor: widget.themeColor,
                        semanticLabel: 'Refresh',
                        onPressed: () =>
                            unawaited(_fetchOrbitNodes(immediate: true)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          if (!_isReloading && _nodes.isEmpty && _errorMessage == null)
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: const EdgeInsets.fromLTRB(32, 0, 32, 140),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                decoration: BoxDecoration(
                  color: AppColors.ink.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: AppColors.tint(
                      widget.themeColor,
                      0.45,
                    ).withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      LucideIcons.users,
                      color: AppColors.tint(widget.themeColor, 0.55),
                      size: 40,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'No users found',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Try expanding your filters or removing criteria to see more people, or check back in a few days as new users join.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          if (_errorMessage != null)
            Center(
              child: Container(
                margin: const EdgeInsets.all(32),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.redAccent.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      LucideIcons.alertCircle,
                      color: Colors.redAccent,
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Error loading orbit space:\n$_errorMessage',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.themeColor,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () =>
                          unawaited(_fetchOrbitNodes(immediate: true)),
                      child: const Text('Try Again'),
                    ),
                  ],
                ),
              ),
            ),

          // Full blocking loader when reloading
          if (_isReloading)
            Positioned.fill(
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: ColoredBox(
                    color: const Color(0xFF020408).withValues(alpha: 0.6),
                    child: Center(
                      child: ConstellationLoader(themeColor: widget.themeColor),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSelfAvatar() {
    final avatar = Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: widget.themeColor.withValues(alpha: 0.15),
        border: Border.all(
          color: widget.themeColor,
          width: 2.5,
        ),
        boxShadow: [
          BoxShadow(
            color: widget.themeColor.withValues(alpha: 0.35),
            blurRadius: 40,
            spreadRadius: 8,
          ),
        ],
      ),
      child:
          _currentUserProfilePic != null && _currentUserProfilePic!.isNotEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(38),
              child: StorageImage(imagePath: _currentUserProfilePic!),
            )
          : Icon(
              LucideIcons.globe,
              color: widget.themeColor,
              size: 32,
            ),
    );

    if (_reduceMotion == true) return avatar;

    final breathingAvatar = avatar
        .animate(onPlay: (controller) => controller.repeat(reverse: true))
        .scale(
          begin: const Offset(0.98, 0.98),
          end: const Offset(1.02, 1.02),
          duration: 2.seconds,
          curve: Curves.easeInOut,
        );

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        // Rotating dashboard/gyro ring (Option B)
        SizedBox(
              width: 110,
              height: 110,
              child: CustomPaint(
                painter: DashedOrbitRingPainter(
                  color: AppColors.tint(
                    widget.themeColor,
                    0.45,
                  ).withValues(alpha: 0.45),
                ),
              ),
            )
            .animate(onPlay: (controller) => controller.repeat())
            .rotate(
              begin: 0,
              end: 1,
              duration: 12.seconds,
            ),

        // Radiating Pulsar Wave 1 (Option A)
        Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.tint(
                    widget.themeColor,
                    0.45,
                  ).withValues(alpha: 0.55),
                  width: 1.5,
                ),
              ),
            )
            .animate(onPlay: (controller) => controller.repeat())
            .scale(
              begin: const Offset(1, 1),
              end: const Offset(1.4, 1.4),
              duration: 2.seconds,
              curve: Curves.easeOut,
            )
            .fade(
              begin: 0.6,
              end: 0,
              duration: 2.seconds,
              curve: Curves.easeOut,
            ),

        // Radiating Pulsar Wave 2 - delayed (Option A)
        Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.tint(
                    widget.themeColor,
                    0.45,
                  ).withValues(alpha: 0.55),
                  width: 1.5,
                ),
              ),
            )
            .animate(onPlay: (controller) => controller.repeat())
            .scale(
              begin: const Offset(1, 1),
              end: const Offset(1.4, 1.4),
              delay: 1.seconds,
              duration: 2.seconds,
              curve: Curves.easeOut,
            )
            .fade(
              begin: 0.6,
              end: 0,
              delay: 1.seconds,
              duration: 2.seconds,
              curve: Curves.easeOut,
            ),

        breathingAvatar,
      ],
    );
  }

  Widget _buildOrbitRing(
    double radius,
    String label,
    Color ringColor, {
    required bool isDashed,
    required int index,
  }) {
    Widget ring = Center(
      child: Container(
        width: radius * 2,
        height: radius * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: ringColor,
          ),
        ),
      ),
    );

    if (isDashed) {
      ring = Center(
        child: SizedBox(
          width: radius * 2,
          height: radius * 2,
          child: CustomPaint(
            painter: DashedOrbitRingPainter(color: ringColor),
          ),
        ),
      );
    }

    if (_reduceMotion == true) return ring;

    final direction = index.isEven ? 1 : -1;
    final duration = (35 + index * 12).seconds;

    return ring
        .animate(onPlay: (controller) => controller.repeat())
        .rotate(
          begin: 0,
          end: direction * 2 * math.pi,
          duration: duration,
          curve: Curves.linear,
        );
  }

  /// Ring width/alpha/glow step per orbit tier (0 = best match, 3 = weakest)
  /// - the discrete, at-a-glance hierarchy signal. Raw `score` only nudges
  /// alpha slightly within a tier so same-tier nodes aren't pixel-identical.
  static ({double width, double alpha, double blur, double spread})
  _tierRingStyle(int tier) {
    switch (tier) {
      case 0:
        return (width: 3, alpha: 1, blur: 18.0, spread: 3);
      case 1:
        return (width: 2.5, alpha: 0.8, blur: 14.0, spread: 2);
      case 2:
        return (width: 2, alpha: 0.6, blur: 10.0, spread: 1);
      default:
        return (width: 1.5, alpha: 0.4, blur: 8.0, spread: 0);
    }
  }

  static String _initialsFor(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    final first = parts.first[0].toUpperCase();
    if (parts.length == 1) return first;
    return '$first${parts.last[0].toUpperCase()}';
  }

  double _getAvatarSize(int tier) {
    switch (tier) {
      case 0:
        return 56;
      case 1:
        return 50;
      case 2:
        return 44;
      default:
        return 38;
    }
  }

  double _getFontSize(int tier) {
    switch (tier) {
      case 0:
        return 12;
      case 1:
        return 10.5;
      case 2:
        return 9.5;
      default:
        return 8.5;
    }
  }

  double _getOpacity(int tier) {
    switch (tier) {
      case 0:
        return 1;
      case 1:
        return 0.9;
      case 2:
        return 0.7;
      default:
        return 0.5;
    }
  }

  /// Deterministic (hashed on `id`, not random) per-person gradient so the
  /// same photoless friend always renders the same placeholder across
  /// refreshes/rebuilds, instead of every photoless node looking identical.
  Widget _buildAvatarPlaceholder(OrbitNode node, double avatarSize) {
    final fraction = (node.id.hashCode.abs() % 100) / 100;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.tint(widget.themeColor, 0.15 + fraction * 0.25),
            AppColors.tint(widget.themeColor, 0.45 + fraction * 0.25),
          ],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        _initialsFor(node.name),
        style: TextStyle(
          color: Colors.white,
          fontSize: avatarSize * 0.32,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildNodeAvatar(OrbitNode node) {
    final avatarSize = _getAvatarSize(node.orbitTier);
    final tierStyle = _tierRingStyle(node.orbitTier);
    final scoreNudge = ((node.score % 20) - 10) / 10 * 0.04;
    final ringAlpha = (tierStyle.alpha + scoreNudge).clamp(0.3, 1.0);
    final profilePic = node.profilePic;

    Widget avatar = Container(
      width: avatarSize,
      height: avatarSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: AppColors.tint(
            widget.themeColor,
            0.4,
          ).withValues(alpha: ringAlpha),
          width: tierStyle.width,
        ),
        boxShadow: [
          BoxShadow(
            color: widget.themeColor.withValues(alpha: 0.15 * tierStyle.alpha),
            blurRadius: tierStyle.blur,
            spreadRadius: tierStyle.spread,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(avatarSize / 2),
        child: profilePic != null && profilePic.isNotEmpty
            ? StorageImage(imagePath: profilePic)
            : _buildAvatarPlaceholder(node, avatarSize),
      ),
    );

    if (_reduceMotion != true) {
      avatar = avatar
          .animate(onPlay: (controller) => controller.repeat(reverse: true))
          .scale(
            begin: const Offset(0.96, 0.96),
            end: const Offset(1.04, 1.04),
            duration: (1.2 + node.orbitTier * 0.3).seconds,
            curve: Curves.easeInOut,
          );
    }

    if (!node.isNew) return avatar;

    // "New" presence dot - reuses the nav bar's solid-dot badge shape
    // (custom_bottom_nav_bar.dart) rather than inventing a new pattern.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          top: -2,
          right: -2,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.themeColor,
              border: Border.all(
                color: const Color(0xFF020408),
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  static const TextStyle _nodeNameStyle = TextStyle(
    color: Colors.white,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
  );

  /// Truncates [name] to fit [maxTextWidth] without cutting a word in half.
  ///
  /// Flutter's own `TextOverflow.ellipsis` truncates by character, which can
  /// land mid-word ("Claude Us…"). This instead finds the word that the
  /// naive cutoff falls inside and keeps it whole ("Claude User"), dropping
  /// anything after it, rather than stopping short at the word before.
  static String _truncateNameAtWordBoundary(
    String name,
    double maxTextWidth,
  ) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return trimmed;

    double measure(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: _nodeNameStyle),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout();
      return painter.width;
    }

    if (measure(trimmed) <= maxTextWidth) return trimmed;

    final words = trimmed.split(RegExp(r'\s+'));
    var result = '';
    for (final word in words) {
      result = result.isEmpty ? word : '$result $word';
      if (measure(result) > maxTextWidth) break;
    }
    return result;
  }

  List<Widget> _buildConstellationNodes() {
    final center = _canvasSize / 2;
    return _nodes.map((node) {
      final x = node.x;
      final y = node.y;
      final id = node.id;
      final name = _truncateNameAtWordBoundary(node.name, 92);

      final avatarSize = _getAvatarSize(node.orbitTier);
      final fontSize = _getFontSize(node.orbitTier);
      final opacity = _getOpacity(node.orbitTier);

      return Positioned(
        left: center + x,
        top: center + y - (avatarSize / 2),
        child: FractionalTranslation(
          translation: const Offset(-0.5, 0),
          child:
              Opacity(
                    opacity: opacity,
                    child: InteractiveOrbitNode(
                      onTap: () => _showNodeDetails(id),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Avatar with tier/score-driven ring and glow
                          _buildNodeAvatar(node),
                          const SizedBox(height: 4),
                          // Name label with soft drop shadow (no background box)
                          Container(
                            constraints: const BoxConstraints(maxWidth: 92),
                            child: Text(
                              name,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              textAlign: TextAlign.center,
                              style: _nodeNameStyle.copyWith(
                                fontSize: fontSize,
                                shadows: [
                                  Shadow(
                                    color: const Color(
                                      0xFF020408,
                                    ).withValues(alpha: 0.85),
                                    offset: const Offset(0, 1.5),
                                    blurRadius: 3.5,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .animate()
                  .fadeIn(duration: 400.ms, curve: Curves.easeOut)
                  .scale(
                    begin: const Offset(0.85, 0.85),
                    duration: 400.ms,
                    curve: Curves.easeOut,
                  ),
        ),
      );
    }).toList();
  }
}
