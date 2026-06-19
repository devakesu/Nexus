import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/screens/home/tabs/profile/widgets/storage_image.dart';
import 'package:nexus/screens/home/widgets/profile_detail_sheet.dart';
import 'package:nexus/screens/orbit/widgets/constellation_loader.dart';
import 'package:nexus/screens/orbit/widgets/orbit_filters_panel.dart';
import 'package:nexus/screens/orbit/widgets/orbit_painters.dart';
import 'package:nexus/utils/network_utils.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OrbitPrefetchResult {
  OrbitPrefetchResult({
    required this.nodes,
    required this.sessionId,
    required this.profilePicUrl,
    this.showBuckets = const [],
    this.datingFor = const [],
    this.partnerValues = const [],
  });

  final List<dynamic> nodes;
  final String? sessionId;
  final String? profilePicUrl;
  final List<String> showBuckets;
  final List<String> datingFor;
  final List<String> partnerValues;
}

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
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) return null;
      final config = AppConfig.current;
      final dio = createDio();
      final headers = {'Authorization': 'Bearer ${session.accessToken}'};

      var showBuckets = <String>[];
      var datingFor = <String>[];
      var partnerValues = <String>[];
      String? profilePicUrl;

      final profileResp = await dio.get<Map<String, dynamic>>(
        '${config.backendUrl}/api/v1/profile/details',
        options: Options(headers: headers),
      );

      if (profileResp.statusCode == 200 && profileResp.data != null) {
        final data = profileResp.data!;
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
          final rawPartnerValues = data['partner_values']?.toString() ?? '';
          if (rawPartnerValues.isNotEmpty) {
            partnerValues = rawPartnerValues
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList();
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
        options: Options(headers: headers),
      );

      if (discoverResp.statusCode == 200 && discoverResp.data != null) {
        return OrbitPrefetchResult(
          nodes: discoverResp.data!['nodes'] as List<dynamic>? ?? [],
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
  List<dynamic> _nodes = [];
  String? _errorMessage;
  String? _currentUserProfilePic;
  bool _isFetchingViewport = false;

  // Viewport/Canvas Size
  final double _canvasSize = 3200;

  // Filters State — general (all tabs)
  late RangeValues _ageRange = RangeValues(
    18,
    AppConfig.current.isMainVariant ? 80 : 27,
  );
  final List<int> _selectedYears = [1, 2, 3, 4, 5];
  final List<String> _selectedDrinking = [];
  final List<String> _selectedSmoking = [];
  final List<String> _selectedLanguages = [];
  final List<String> _selectedSubInterests = [];

  // Filters State — dating tab only
  final List<String> _selectedChildrenPlans = [];
  final List<String> _selectedReligiousBeliefs = [];
  final List<String> _selectedDatingFor = [];
  final List<String> _selectedShowBuckets = [];
  final List<String> _selectedPartnerValues = [];
  final Set<String> _dealbreakerFields = {};

  // Filters State — professional tab only
  final List<String> _selectedLookingFor = [];
  final List<String> _selectedCausesSupported = [];
  final List<String> _selectedTechSkills = [];

  final Set<String> _savingFields = {};
  bool _isCentered = false;
  bool _isReloading = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    unawaited(_pulseController.repeat(reverse: true));

    if (widget.prefetchFuture != null) {
      unawaited(_applyPrefetchData());
    } else {
      unawaited(_initData());
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

  Future<void> _initData() async {
    if (widget.tab == 'Dating') {
      await _loadDatingProfileStatus();
    }
    await _fetchOrbitNodes();
  }

  Future<void> _loadDatingProfileStatus() async {
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        final config = AppConfig.current;
        final response = await _dio.get<Map<String, dynamic>>(
          '${config.backendUrl}/api/v1/profile/details',
          options: Options(
            headers: {'Authorization': 'Bearer ${session.accessToken}'},
          ),
        );

        if (response.statusCode == 200 && response.data != null && mounted) {
          final data = response.data!;
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
            final rawPartnerValues = data['partner_values']?.toString() ?? '';
            if (rawPartnerValues.isNotEmpty) {
              _selectedPartnerValues
                ..clear()
                ..addAll(
                  rawPartnerValues
                      .split(',')
                      .map((e) => e.trim())
                      .where((e) => e.isNotEmpty),
                );
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
          options: Options(
            headers: {'Authorization': 'Bearer ${session.accessToken}'},
          ),
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
            _selectedShowBuckets
              ..clear()
              ..addAll(List<String>.from(value as List));
          } else if (field == 'dating_for') {
            _selectedDatingFor
              ..clear()
              ..addAll(List<String>.from(value as List));
          } else if (field == 'partner_values') {
            _selectedPartnerValues
              ..clear()
              ..addAll(
                (value as String)
                    .split(',')
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty),
              );
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
                    (opt) => opt.toLowerCase().contains(searchQuery.toLowerCase()),
                  )
                  .toList();

              return Theme(
                data: ThemeData(
                  useMaterial3: true,
                  colorScheme: ColorScheme.fromSeed(
                    seedColor: widget.themeColor,
                    brightness: Brightness.dark,
                    surface: const Color(0xFF0F172A),
                  ),
                ),
                child: Container(
                  height: MediaQuery.of(context).size.height * 0.7,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
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
                                  foregroundColor: Colors.black87,
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
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Search...',
                            hintStyle: const TextStyle(color: Colors.white38),
                            prefixIcon: const Icon(LucideIcons.search, size: 18, color: Colors.white38),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.05),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                                final sel = selected.contains(opt);
                                return FilterChip(
                                  label: Text(
                                    opt,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: sel ? widget.themeColor : Colors.white60,
                                    ),
                                  ),
                                  selected: sel,
                                  selectedColor: widget.themeColor.withValues(alpha: 0.15),
                                  backgroundColor: Colors.white.withValues(alpha: 0.05),
                                  checkmarkColor: widget.themeColor,
                                  side: BorderSide(
                                    color: sel ? widget.themeColor : Colors.white.withValues(alpha: 0.2),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  onSelected: (v) {
                                    setPaneState(() {
                                      if (v) {
                                        selected.add(opt);
                                      } else {
                                        selected.remove(opt);
                                      }
                                    });
                                    setModalState(() {});
                                    setState(() {});
                                    unawaited(_fetchOrbitNodes());
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
                    (opt) => opt.toLowerCase().contains(searchQuery.toLowerCase()),
                  )
                  .toList();

              final showCustomOption = searchQuery.trim().isNotEmpty &&
                  !predefinedValues.any((val) => val.toLowerCase() == searchQuery.trim().toLowerCase()) &&
                  !_selectedPartnerValues.any((val) => val.toLowerCase() == searchQuery.trim().toLowerCase());

              return Theme(
                data: ThemeData(
                  useMaterial3: true,
                  colorScheme: ColorScheme.fromSeed(
                    seedColor: widget.themeColor,
                    brightness: Brightness.dark,
                    surface: const Color(0xFF0F172A),
                  ),
                ),
                child: Container(
                  height: MediaQuery.of(context).size.height * 0.75,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
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
                                foregroundColor: Colors.black87,
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
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Search or add custom value...',
                            hintStyle: const TextStyle(color: Colors.white38),
                            prefixIcon: const Icon(LucideIcons.search, size: 18, color: Colors.white38),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.05),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                                if (showCustomOption)
                                  ActionChip(
                                    avatar: const Icon(
                                      LucideIcons.plus,
                                      size: 14,
                                      color: Colors.black87,
                                    ),
                                    label: Text('Add "${searchQuery.trim()}"'),
                                    backgroundColor: widget.themeColor,
                                    labelStyle: const TextStyle(
                                      color: Colors.black87,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    onPressed: () async {
                                      if (_savingFields.contains('partner_values')) {
                                        return;
                                      }
                                      final customVal = searchQuery.trim();
                                      setPaneState(() {
                                        _selectedPartnerValues.add(customVal);
                                        searchQuery = '';
                                      });
                                      setModalState(() {});
                                      await _saveDatingField(
                                        'partner_values',
                                        _selectedPartnerValues.join(', '),
                                        setModalState,
                                      );
                                    },
                                  ),
                                ...filtered.map((opt) {
                                  final sel = _selectedPartnerValues.contains(opt);
                                  return FilterChip(
                                    label: Text(
                                      opt,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: sel ? widget.themeColor : Colors.white60,
                                      ),
                                    ),
                                    selected: sel,
                                    selectedColor: widget.themeColor.withValues(alpha: 0.15),
                                    backgroundColor: Colors.white.withValues(alpha: 0.05),
                                    checkmarkColor: widget.themeColor,
                                    side: BorderSide(
                                      color: sel ? widget.themeColor : Colors.white.withValues(alpha: 0.2),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    onSelected: (v) async {
                                      if (_savingFields.contains('partner_values')) {
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
                                        _selectedPartnerValues.join(', '),
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

  Future<void> _fetchOrbitNodes({bool useExistingSession = false}) async {
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
        options: Options(
          headers: {'Authorization': 'Bearer ${session.accessToken}'},
        ),
      );

      final profileFuture = _dio.get<Map<String, dynamic>>(
        '${config.backendUrl}/api/v1/profile/details',
        options: Options(
          headers: {'Authorization': 'Bearer ${session.accessToken}'},
        ),
      );

      final results = await Future.wait([discoverFuture, profileFuture]);
      final discoverResponse = results[0];
      final profileResponse = results[1];

      String? profilePicUrl;
      if (profileResponse.statusCode == 200 && profileResponse.data != null) {
        final profileData = profileResponse.data!;
        final rawImages = profileData['ordered_images'];
        if (rawImages is List && rawImages.isNotEmpty) {
          profilePicUrl = rawImages[0]?.toString();
        }
      }

      if (discoverResponse.statusCode == 200 && discoverResponse.data != null) {
        final nodesList =
            discoverResponse.data!['nodes'] as List<dynamic>? ?? [];
        debugPrint('--- CLIENT ORBIT NODES RECEIVED (${nodesList.length}) ---');
        for (final node in nodesList.cast<Map<String, dynamic>>()) {
          debugPrint(
            'Node: ${node['name']}, x: ${node['x']}, y: ${node['y']}, tier: ${node['orbit_tier']}, score: ${node['score']}',
          );
        }
        setState(() {
          _sessionId = discoverResponse.data!['session_id'] as String?;
          _nodes = nodesList;
          if (profilePicUrl != null) {
            _currentUserProfilePic = profilePicUrl;
          }
        });
      } else {
        throw Exception('Failed to fetch orbit constellation.');
      }
    } on Exception catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
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

    setState(() {
      _isFetchingViewport = true;
    });

    try {
      final config = AppConfig.current;
      final response = await _dio.post<Map<String, dynamic>>(
        '${config.backendUrl}/api/v1/discover/viewport',
        data: {
          'session_id': _sessionId,
          'center_x': centerX,
          'center_y': centerY,
          'radius': radius,
        },
        options: Options(
          headers: {'Authorization': 'Bearer ${session.accessToken}'},
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final newNodes = response.data!['nodes'] as List<dynamic>? ?? [];
        setState(() {
          final nodeMap = {
            for (final node in _nodes.cast<Map<String, dynamic>>()) node['id'] as String: node
          };
          for (final node in newNodes) {
            if (node is Map<String, dynamic>) {
              nodeMap[node['id'] as String] = node;
            }
          }
          _nodes = nodeMap.values.toList();
        });
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

  void _passNode(String candidateId) {
    // Fire backend first — before any mounted/setState guard so it always runs.
    unawaited(_recordPassAction(candidateId));

    if (!mounted) return;

    final angle = math.Random().nextDouble() * 2 * math.pi;
    const radius = 540.0;
    setState(() {
      final idx = _nodes.indexWhere((n) => (n as Map)['id'] == candidateId);
      if (idx != -1) {
        final updated = Map<String, dynamic>.from(_nodes[idx] as Map);
        updated['x'] = radius * math.cos(angle);
        updated['y'] = radius * math.sin(angle);
        updated['orbit_tier'] = 3;
        updated['score'] = 0.0;
        _nodes[idx] = updated;
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Color(0xFF1E293B),
        content: Row(
          children: [
            Icon(LucideIcons.compass, color: Colors.white, size: 18),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Moved to deep space.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _recordPassAction(String candidateId) async {
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) return;
      final config = AppConfig.current;
      await _dio.post<dynamic>(
        '${config.backendUrl}/api/v1/discover/action',
        data: {'target_id': candidateId, 'action': 'pass', 'tab': widget.tab},
        options: Options(headers: {'Authorization': 'Bearer ${session.accessToken}'}),
      );
    } on Exception catch (_) {}
  }

  Future<void> _performAction(
    String candidateId,
    String actionType, {
    String? reason,
    String? reasonDetail,
  }) async {
    // Remove immediately from local state so the node vanishes before the network round-trip.
    if (mounted) {
      setState(() => _nodes.removeWhere((n) => (n as Map)['id'] == candidateId));
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
        'reason': ?reason,
        'reason_detail': ?reasonDetail,
      };

      final response = await _dio.post<Map<String, dynamic>>(
        '${config.backendUrl}/api/v1/discover/action',
        data: payload,
        options: Options(
          headers: {'Authorization': 'Bearer ${session.accessToken}'},
        ),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          final (Color bg, IconData icon, String message) = switch (actionType) {
            'like' || 'superlike' => (
                const Color(0xFFFF4F81),
                LucideIcons.heartHandshake,
                'Pulled into your gravity!',
              ),
            'block' => (
                const Color(0xFF1E293B),
                LucideIcons.shieldOff,
                'User blocked.',
              ),
            'report' => (
                const Color(0xFF1E293B),
                LucideIcons.flag,
                'Report submitted. Thanks for keeping the space safe.',
              ),
            _ => (
                const Color(0xFF1E293B),
                LucideIcons.eyeOff,
                'User hidden.',
              ),
          };
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              backgroundColor: bg,
              content: Row(
                children: [
                  Icon(icon, color: Colors.white, size: 18),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      message,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      }
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.redAccent,
            content: Text('Action failed: $e'),
          ),
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
          future: _fetchNodeDetails(candidateId),
          builder: (context, snapshot) {
            // ── Loading ──────────────────────────────────────────────────────
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Container(
                height: MediaQuery.of(context).size.height * 0.7,
                decoration: const BoxDecoration(
                  color: Color(0xFF090D1A),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 48),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(theme),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Tuning into signal...',
                      style: TextStyle(
                        color: theme.withValues(alpha: 0.55),
                        fontSize: 12,
                        letterSpacing: 1.2,
                      ),
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
                    onConfirmed: (reason, detail) async {
                      Navigator.pop(ctx);
                      await _performAction(candidateId, 'report',
                          reason: reason, reasonDetail: detail);
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
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
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

    final config = AppConfig.current;
    final response = await _dio.get<Map<String, dynamic>>(
      '${config.backendUrl}/api/v1/profile/details',
      options: Options(
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
      ),
    );

    if (response.statusCode == 200 && response.data != null) {
      final d = response.data!;
      final orderedImages = d['ordered_images'] as List? ?? [];
      return {
        ...d,
        'profile_pic': orderedImages.isNotEmpty ? orderedImages[0] : '',
        'normal_pics':
            orderedImages.length > 1 ? orderedImages.sublist(1) : <dynamic>[],
        'tab': widget.tab,
        'score': 0,
      };
    }

    throw Exception('Failed to load your profile.');
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
                height: MediaQuery.of(context).size.height * 0.7,
                decoration: const BoxDecoration(
                  color: Color(0xFF090D1A),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 48),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(theme),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Loading your profile...',
                      style: TextStyle(
                        color: theme.withValues(alpha: 0.55),
                        fontSize: 12,
                        letterSpacing: 1.2,
                      ),
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
                  showScoreBadge: false,
                  showSafetyActions: false,
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
      await _fetchOrbitNodes();
    }
    if (_sessionId == null) {
      throw Exception('No discovery session available.');
    }

    final config = AppConfig.current;
    final headers = Options(
      headers: {'Authorization': 'Bearer ${session.accessToken}'},
    );

    var response = await _dio.post<Map<String, dynamic>>(
      '${config.backendUrl}/api/v1/discover/node-detail',
      data: {'session_id': _sessionId, 'candidate_id': candidateId},
      options: headers,
    );

    if (response.statusCode == 200 && response.data != null) {
      return response.data!;
    }

    // 404 means the session expired. Silently refresh orbit (creates a new
    // session) then retry once — the candidate is usually still in the pool.
    if (response.statusCode == 404) {
      await _fetchOrbitNodes();
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
                surface: const Color(0xFF0F172A),
              ),
            ),
            child: DraggableScrollableSheet(
              initialChildSize: 0.65,
              minChildSize: 0.4,
              maxChildSize: 0.95,
              expand: false,
              builder: (context, scrollController) {
                return OrbitFiltersPanel(
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
                  onOpenTagSelectionPane: (title, options, selected, setModalState) {
                    _openTagSelectionPane(
                      title: title,
                      options: options,
                      selected: selected,
                      setModalState: setModalState,
                    );
                  },
                  onOpenPartnerValuesSelectionPane: (setModalState, predefinedValues) {
                    _openPartnerValuesSelectionPane(
                      setModalState: setModalState,
                      predefinedValues: predefinedValues,
                    );
                  },
                  isRefreshing: _isReloading,
                  onFetchOrbitNodes: () async {
                    await _fetchOrbitNodes();
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
                  unawaited(_fetchViewportNodes(constraints.maxWidth, constraints.maxHeight));
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
                        child: CustomPaint(
                          painter: ConstellationLinesPainter(
                            nodes: _nodes,
                            themeColor: widget.themeColor,
                          ),
                        ),
                      ),

                      // Concentric Orbit Rings
                      _buildOrbitRing(
                        100,
                        'Core Gravity',
                        widget.themeColor.withValues(alpha: 0.1),
                      ),
                      _buildOrbitRing(
                        200,
                        'Inner Constellation',
                        widget.themeColor.withValues(alpha: 0.08),
                      ),
                      _buildOrbitRing(
                        300,
                        'Mid Horizon',
                        widget.themeColor.withValues(alpha: 0.05),
                      ),
                      _buildOrbitRing(
                        420,
                        'Deep Space Horizon',
                        widget.themeColor.withValues(alpha: 0.03),
                      ),

                      // Pulsing Center Node (Viewer)
                      Center(
                        child: GestureDetector(
                          onTap: _showSelfDetails,
                          child: Container(
                                  width: 76,
                                  height: 76,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: widget.themeColor.withValues(
                                      alpha: 0.15,
                                    ),
                                    border: Border.all(
                                      color: widget.themeColor,
                                      width: 2.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: widget.themeColor.withValues(
                                          alpha: 0.35,
                                        ),
                                        blurRadius: 40,
                                        spreadRadius: 8,
                                      ),
                                    ],
                                  ),
                                  child:
                                      _currentUserProfilePic != null &&
                                          _currentUserProfilePic!.isNotEmpty
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            38,
                                          ),
                                          child: StorageImage(
                                            imagePath: _currentUserProfilePic!,
                                          ),
                                        )
                                      : Icon(
                                          LucideIcons.globe,
                                          color: widget.themeColor,
                                          size: 32,
                                        ),
                                )
                                .animate(
                                  onPlay: (controller) =>
                                      controller.repeat(reverse: true),
                                )
                                .scale(
                                  begin: const Offset(0.9, 0.9),
                                  end: const Offset(1.15, 1.15),
                                  duration: 2.seconds,
                                  curve: Curves.easeInOut,
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

          // Header Overlay
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  padding: const EdgeInsets.only(
                    top: 55,
                    bottom: 8,
                    left: 16,
                    right: 16,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFF020408).withValues(alpha: 0.92),
                        const Color(0xFF020408).withValues(alpha: 0.65),
                        const Color(0xFF020408).withValues(alpha: 0),
                      ],
                      stops: const [0.0, 0.7, 1.0],
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(
                                LucideIcons.arrowLeft,
                                color: Colors.white,
                              ),
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
                          IconButton(
                            icon: const Icon(
                              LucideIcons.slidersHorizontal,
                              color: Colors.white,
                            ),
                            onPressed: _showFiltersPanel,
                          ),
                          IconButton(
                            icon: const Icon(
                              LucideIcons.refreshCw,
                              color: Colors.white,
                            ),
                            onPressed: () => unawaited(_fetchOrbitNodes()),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
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
                      onPressed: () => unawaited(_fetchOrbitNodes()),
                      child: const Text('Try Again'),
                    ),
                  ],
                ),
              ),
            ),

          // Full blocking loader only on initial load (no nodes yet)
          if (_isReloading && _nodes.isEmpty)
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

          // Non-blocking shimmer strip for filter-triggered refreshes
          if (_isReloading && _nodes.isNotEmpty)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _OrbitRefreshStrip(themeColor: widget.themeColor),
            ),
        ],
      ),
    );
  }

  Widget _buildOrbitRing(double radius, String label, Color ringColor) {
    return Center(
      child: Container(
        width: radius * 2,
        height: radius * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: ringColor,
            width: 1.5,
          ),
        ),
      ),
    );
  }

  List<Widget> _buildConstellationNodes() {
    final center = _canvasSize / 2;
    return _nodes.cast<Map<String, dynamic>>().map((node) {
      final x = (node['x'] as num?)?.toDouble() ?? 0.0;
      final y = (node['y'] as num?)?.toDouble() ?? 0.0;
      final id = node['id']?.toString() ?? '';
      final name = node['name']?.toString() ?? 'Anonymous';
      final profilePic = node['profile_pic']?.toString();
      final score = (node['score'] as num?)?.toDouble() ?? 0.0;

      // Position node on the canvas grid
      final posX = center + x - 40;
      final posY = center + y - 48;

      return Positioned(
        left: posX,
        top: posY,
        child:
            GestureDetector(
                  onTap: () => _showNodeDetails(id),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Avatar with compatibility score border
                      Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: widget.themeColor.withValues(
                                  alpha: (score / 100).clamp(0.2, 1.0),
                                ),
                                width: 2.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: widget.themeColor.withValues(
                                    alpha: 0.15,
                                  ),
                                  blurRadius: 12,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(29),
                              child: profilePic != null && profilePic.isNotEmpty
                                  ? StorageImage(imagePath: profilePic)
                                  : const ColoredBox(
                                      color: Color(0xFF1E293B),
                                      child: Icon(
                                        LucideIcons.user,
                                        color: Colors.white54,
                                        size: 24,
                                      ),
                                    ),
                            ),
                          )
                          .animate(
                            onPlay: (controller) =>
                                controller.repeat(reverse: true),
                          )
                          .scale(
                            begin: const Offset(0.96, 0.96),
                            end: const Offset(1.04, 1.04),
                            duration: (1.5 + (score % 5) * 0.1).seconds,
                            curve: Curves.easeInOut,
                          ),
                      const SizedBox(height: 6),
                      // Name Card
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.06),
                          ),
                        ),
                        child: Text(
                          name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
                .animate()
                .fadeIn(duration: 400.ms)
                .scale(begin: const Offset(0.3, 0.3)),
      );
    }).toList();
  }
}

// ── Non-blocking shimmer strip shown during filter-triggered refreshes ─────────

class _OrbitRefreshStrip extends StatefulWidget {
  const _OrbitRefreshStrip({required this.themeColor});
  final Color themeColor;

  @override
  State<_OrbitRefreshStrip> createState() => _OrbitRefreshStripState();
}

class _OrbitRefreshStripState extends State<_OrbitRefreshStrip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    unawaited(_ctrl.repeat());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) {
        return Container(
          height: 2,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(_ctrl.value * 2 - 1, 0),
              end: Alignment(_ctrl.value * 2 + 0.4, 0),
              colors: [
                Colors.transparent,
                widget.themeColor.withValues(alpha: 0.85),
                widget.themeColor,
                widget.themeColor.withValues(alpha: 0.85),
                Colors.transparent,
              ],
            ),
          ),
        );
      },
    );
  }
}
