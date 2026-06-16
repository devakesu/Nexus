import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/config/filter_options.dart';
import 'package:nexus/screens/home/tabs/profile/utils/emoji_helper.dart';
import 'package:nexus/screens/home/tabs/profile/widgets/storage_image.dart';
import 'package:nexus/screens/home/widgets/interests_overlay.dart';
import 'package:nexus/utils/network_utils.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OrbitScreen extends StatefulWidget {
  const OrbitScreen({
    required this.tab,
    required this.themeColor,
    super.key,
  });

  final String tab;
  final Color themeColor;

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
    )..repeat(reverse: true);

    _initData();
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
              _selectedShowBuckets.clear();
              _selectedShowBuckets.addAll(rawBuckets.map((e) => e.toString()));
            }
            final rawDatingFor = data['dating_for'];
            if (rawDatingFor is List) {
              _selectedDatingFor.clear();
              _selectedDatingFor.addAll(rawDatingFor.map((e) => e.toString()));
            }
            final rawPartnerValues = data['partner_values']?.toString() ?? '';
            if (rawPartnerValues.isNotEmpty) {
              _selectedPartnerValues.clear();
              _selectedPartnerValues.addAll(
                rawPartnerValues
                    .split(',')
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty),
              );
            }
          });
        }
      }
    } catch (e) {
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
    } catch (e) {
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
            _selectedShowBuckets.clear();
            _selectedShowBuckets.addAll(List<String>.from(value as List));
          } else if (field == 'dating_for') {
            _selectedDatingFor.clear();
            _selectedDatingFor.addAll(List<String>.from(value as List));
          } else if (field == 'partner_values') {
            _selectedPartnerValues.clear();
            _selectedPartnerValues.addAll(
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
                                }).toList(),
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
        for (final node in nodesList) {
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
    final double scale = matrix.getMaxScaleOnAxis();
    if (scale <= 0) return;

    final double translationX = matrix.entry(0, 3);
    final double translationY = matrix.entry(1, 3);

    final double visibleCanvasCenterX = (viewWidth / 2 - translationX) / scale;
    final double visibleCanvasCenterY = (viewHeight / 2 - translationY) / scale;

    final double center = _canvasSize / 2;
    final double centerX = visibleCanvasCenterX - center;
    final double centerY = visibleCanvasCenterY - center;

    final double screenHalfWidth = viewWidth / 2;
    final double screenHalfHeight = viewHeight / 2;
    final double screenDiagonal = math.sqrt(
      screenHalfWidth * screenHalfWidth + screenHalfHeight * screenHalfHeight,
    );
    double radius = (screenDiagonal / scale) * 1.2;
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
          final Map<String, dynamic> nodeMap = {
            for (var node in _nodes) node['id'] as String: node
          };
          for (var node in newNodes) {
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

  Future<void> _performAction(String candidateId, String actionType) async {
    // Remove immediately from local state so the node vanishes before the network round-trip.
    if (mounted) {
      setState(() => _nodes.removeWhere((n) => (n as Map)['id'] == candidateId));
    }

    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) return;

      final config = AppConfig.current;
      final isGlobal = actionType == 'block' || actionType == 'report';
      final payload = <String, dynamic>{
        'target_id': candidateId,
        'action': actionType,
        if (!isGlobal) 'tab': widget.tab,
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

  Widget _safetyButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
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

            // ── Data extraction ──────────────────────────────────────────────
            final data = snapshot.data!;
            final profilePic = data['profile_pic']?.toString() ?? '';
            final normalPics = <String>[];
            if (data['normal_pics'] is List) {
              normalPics.addAll(List<String>.from(data['normal_pics'] as List));
            }

            final name = data['name']?.toString() ?? 'Anonymous';
            final age = data['age'];
            final score = ((data['score'] as num?) ?? 0).round();
            final tab = data['tab']?.toString() ?? widget.tab;

            final pronouns = data['pronouns']?.toString() ?? '';
            final displayGender = data['display_gender']?.toString() ?? '';
            final displaySexuality = data['display_sexuality']?.toString() ?? '';
            final hometown = data['hometown']?.toString() ?? '';
            final currentPlace = data['current_place']?.toString() ?? '';
            final bio = data['bio']?.toString() ?? '';

            final campusBranch = data['campus_branch']?.toString() ?? '';
            final campusYear = data['campus_year'];
            final campusName = data['campus_name']?.toString() ?? '';
            final role = data['role']?.toString() ?? '';

            final drinking = data['drinking']?.toString() ?? '';
            final smoking = data['smoking']?.toString() ?? '';
            final lifestyle = data['lifestyle']?.toString() ?? '';
            final religiousBeliefs = data['religious_beliefs']?.toString() ?? '';
            final partnerValues = data['partner_values']?.toString() ?? '';
            final childrenPlans = data['children_plans']?.toString() ?? '';

            final interests = data['interests'] is Map
                ? Map<String, dynamic>.from(data['interests'] as Map)
                : <String, dynamic>{};
            final subInterests = data['sub_interests'] is Map
                ? Map<String, dynamic>.from(data['sub_interests'] as Map)
                : <String, dynamic>{};
            final interestKeys = interests.keys.toList();
            final subInterestTags = subInterests.values
                .expand(
                  (v) => v is List ? v.cast<String>() : <String>[],
                )
                .toList();

            final aiVibeTags = data['ai_vibe_tags'] is List
                ? List<String>.from(data['ai_vibe_tags'] as List)
                : <String>[];
            final activities = data['activities'] is List
                ? List<String>.from(data['activities'] as List)
                : <String>[];
            final languages = data['languages'] is List
                ? List<String>.from(data['languages'] as List)
                : <String>[];
            final pets = data['pets'] is List
                ? List<String>.from(data['pets'] as List)
                : <String>[];
            final topArtists = data['top_artists'] is List
                ? List<String>.from(data['top_artists'] as List)
                : <String>[];
            final lookingFor = data['looking_for'] is List
                ? List<String>.from(data['looking_for'] as List)
                : <String>[];
            final techSkills = data['tech_skills'] is List
                ? List<String>.from(data['tech_skills'] as List)
                : <String>[];
            final causesSupported = data['causes_supported'] is List
                ? List<String>.from(data['causes_supported'] as List)
                : <String>[];
            final datingFor = data['dating_for'] is List
                ? List<String>.from(data['dating_for'] as List)
                : <String>[];

            String decodeLookingFor(String code) => FilterOptions.lookingForOptions
                .firstWhere(
                  (m) => m['code'] == code,
                  orElse: () => {'code': code, 'label': code},
                )['label']!;
            String decodeDatingFor(String code) => FilterOptions.datingForOptions
                .firstWhere(
                  (m) => m['code'] == code,
                  orElse: () => {'code': code, 'label': code},
                )['label']!;

            final lookingForLabels = lookingFor.map(decodeLookingFor).toList();
            final datingForLabels = datingFor.map(decodeDatingFor).toList();

            final showSexuality =
                (tab == 'Dating' || tab == 'Friends') && displaySexuality.isNotEmpty;

            // ── Local widget helpers ─────────────────────────────────────────

            Widget photoBlock(String path, {double height = 240}) {
              return Container(
                height: height,
                margin: const EdgeInsets.fromLTRB(18, 6, 18, 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      StorageImage(imagePath: path),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.15),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            Widget sectionLabel(String label, {String emoji = '', IconData? icon}) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
                child: Row(
                  children: [
                    if (emoji.isNotEmpty) ...[
                      Text(emoji, style: const TextStyle(fontSize: 13)),
                      const SizedBox(width: 7),
                    ] else if (icon != null) ...[
                      Icon(icon, color: theme, size: 13),
                      const SizedBox(width: 7),
                    ],
                    Text(
                      label.toUpperCase(),
                      style: TextStyle(
                        color: theme.withValues(alpha: 0.75),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.8,
                      ),
                    ),
                  ],
                ),
              );
            }

            Widget chipWrap(
              List<String> items, {
              Color? accent,
              Color? labelColor,
              bool useEmoji = false,
            }) {
              final c = accent ?? theme;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: items.map((item) {
                    final emoji = useEmoji ? getEmojiForTag(item) : '';
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: c.withValues(alpha: 0.09),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: c.withValues(alpha: 0.28)),
                      ),
                      child: Text(
                        emoji.isNotEmpty ? '$emoji $item' : item,
                        style: TextStyle(
                          color: labelColor ?? c.withValues(alpha: 0.9),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              );
            }

            Widget emojiInfoRow(String emoji, String text) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 11),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(emoji, style: const TextStyle(fontSize: 17)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        text,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            Widget locationPill(IconData icon, String label) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: Colors.white38, size: 13),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: const TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  ],
                ),
              );
            }

            final screenHeight = MediaQuery.of(context).size.height;

            // ── Sheet ────────────────────────────────────────────────────────
            return DraggableScrollableSheet(
              initialChildSize: 0.92,
              minChildSize: 0.5,
              maxChildSize: 0.97,
              expand: false,
              builder: (context, scrollController) {
                return Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFF090D1A),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                  ),
                  child: Column(
                    children: [
                      // ── Scrollable body ──────────────────────────────────
                      Expanded(
                        child: ListView(
                          controller: scrollController,
                          padding: EdgeInsets.zero,
                          children: [

                            // ═══════════════════════════════════════════════
                            // HERO PHOTO
                            // ═══════════════════════════════════════════════
                            SizedBox(
                              height: screenHeight * 0.44,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  // Photo / placeholder
                                  ClipRRect(
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(28),
                                    ),
                                    child: profilePic.isNotEmpty
                                        ? StorageImage(imagePath: profilePic)
                                        : Container(
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [
                                                  theme.withValues(alpha: 0.35),
                                                  const Color(0xFF090D1A),
                                                ],
                                                begin: Alignment.topCenter,
                                                end: Alignment.bottomCenter,
                                              ),
                                            ),
                                            child: const Center(
                                              child: Icon(
                                                LucideIcons.user,
                                                color: Colors.white12,
                                                size: 72,
                                              ),
                                            ),
                                          ),
                                  ),

                                  // Gradient overlay
                                  Positioned.fill(
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        borderRadius: const BorderRadius.vertical(
                                          top: Radius.circular(28),
                                        ),
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Colors.transparent,
                                            Colors.transparent,
                                            Colors.black.withValues(alpha: 0.5),
                                            const Color(0xFF090D1A),
                                          ],
                                          stops: const [0.0, 0.42, 0.72, 1.0],
                                        ),
                                      ),
                                    ),
                                  ),

                                  // Drag handle
                                  Positioned(
                                    top: 12,
                                    left: 0,
                                    right: 0,
                                    child: Center(
                                      child: Container(
                                        width: 40,
                                        height: 4,
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.3),
                                          borderRadius: BorderRadius.circular(2),
                                        ),
                                      ),
                                    ),
                                  ),

                                  // Score badge — top right
                                  Positioned(
                                    top: 14,
                                    right: 16,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 13,
                                        vertical: 7,
                                      ),
                                      decoration: BoxDecoration(
                                        color: theme.withValues(alpha: 0.88),
                                        borderRadius:
                                            BorderRadius.circular(20),
                                        boxShadow: [
                                          BoxShadow(
                                            color:
                                                theme.withValues(alpha: 0.45),
                                            blurRadius: 18,
                                            spreadRadius: 1,
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            LucideIcons.sparkles,
                                            color: Colors.white,
                                            size: 11,
                                          ),
                                          const SizedBox(width: 5),
                                          Text(
                                            '$score%',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),

                                  // Name + pronouns + identity pills
                                  Positioned(
                                    left: 20,
                                    right: 20,
                                    bottom: 18,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          age != null ? '$name, $age' : name,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 30,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.2,
                                            shadows: [
                                              Shadow(blurRadius: 10, color: Colors.black54),
                                            ],
                                          ),
                                        ),
                                        if (pronouns.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            pronouns,
                                            style: const TextStyle(
                                              color: Colors.white60,
                                              fontSize: 13,
                                              shadows: [Shadow(blurRadius: 8, color: Colors.black45)],
                                            ),
                                          ),
                                        ],
                                        if (displayGender.isNotEmpty || showSexuality) ...[
                                          const SizedBox(height: 8),
                                          Wrap(
                                            spacing: 6,
                                            runSpacing: 4,
                                            children: [
                                              if (displayGender.isNotEmpty)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 4,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white.withValues(alpha: 0.15),
                                                    borderRadius: BorderRadius.circular(16),
                                                    border: Border.all(
                                                      color: Colors.white.withValues(alpha: 0.3),
                                                    ),
                                                  ),
                                                  child: Text(
                                                    '${getEmojiForTag(displayGender)} $displayGender',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              if (showSexuality)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 4,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFEC4899).withValues(alpha: 0.2),
                                                    borderRadius: BorderRadius.circular(16),
                                                    border: Border.all(
                                                      color: const Color(0xFFEC4899).withValues(alpha: 0.4),
                                                    ),
                                                  ),
                                                  child: Text(
                                                    '${getEmojiForTag(displaySexuality)} $displaySexuality',
                                                    style: const TextStyle(
                                                      color: Color(0xFFFCCBE5),
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // ═══════════════════════════════════════════════
                            // LOCATION PILLS
                            // ═══════════════════════════════════════════════
                            // ═══════════════════════════════════════════════
                            // LOCATION PILLS
                            // ═══════════════════════════════════════════════
                            if (currentPlace.isNotEmpty || hometown.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    if (currentPlace.isNotEmpty)
                                      locationPill(LucideIcons.mapPin, currentPlace),
                                    if (hometown.isNotEmpty && hometown != currentPlace)
                                      locationPill(LucideIcons.home, 'From $hometown'),
                                  ],
                                ),
                              ),

                            // ═══════════════════════════════════════════════
                            // BIO
                            // ═══════════════════════════════════════════════
                            if (bio.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(18, 20, 18, 0),
                                child: Container(
                                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                                  decoration: BoxDecoration(
                                    color: theme.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: theme.withValues(alpha: 0.18),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '“',
                                        style: TextStyle(
                                          color: theme.withValues(alpha: 0.6),
                                          fontSize: 38,
                                          height: 0.85,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          bio,
                                          style: TextStyle(
                                            color: Colors.white.withValues(alpha: 0.75),
                                            fontSize: 14,
                                            height: 1.7,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                            // ═══════════════════════════════════════════════
                            // BACKGROUND — campus + role
                            // ═══════════════════════════════════════════════
                            if (campusBranch.isNotEmpty ||
                                campusYear != null ||
                                campusName.isNotEmpty ||
                                role.isNotEmpty) ...[
                              sectionLabel('Background', emoji: '🎓'),
                              if (campusBranch.isNotEmpty ||
                                  campusYear != null ||
                                  campusName.isNotEmpty)
                                emojiInfoRow(
                                  '🏛️',
                                  [
                                    if (campusBranch.isNotEmpty) campusBranch,
                                    if (campusYear != null) 'Year $campusYear',
                                    if (campusName.isNotEmpty) campusName,
                                  ].where((s) => s.isNotEmpty).join(' · '),
                                ),
                              if (role.isNotEmpty) emojiInfoRow('💼', role),
                            ],

                            // ═══════════════════════════════════════════════
                            // DATING FOR (Dating only) — before 1st photo
                            // ═══════════════════════════════════════════════
                            if (tab == 'Dating' && datingForLabels.isNotEmpty) ...[
                              sectionLabel('Here for', emoji: '💘'),
                              chipWrap(
                                datingForLabels,
                                accent: const Color(0xFFEC4899),
                                labelColor: const Color(0xFFFCCBE5),
                              ),
                            ],

                            // ═══════════════════════════════════════════════
                            // PHOTO BREAK 1 — after Background + Dating For
                            // ═══════════════════════════════════════════════
                            if ((tab == 'Dating' || tab == 'Friends') &&
                                normalPics.isNotEmpty) ...[
                              const SizedBox(height: 20),
                              photoBlock(normalPics[0], height: 280),
                            ],

                            // ═══════════════════════════════════════════════
                            // AI VIBE TAGS
                            // ═══════════════════════════════════════════════
                            if (aiVibeTags.isNotEmpty) ...[
                              sectionLabel('Vibe', icon: LucideIcons.sparkles),
                              chipWrap(aiVibeTags),
                            ],

                            // ═══════════════════════════════════════════════
                            // INTERESTS + SUB-INTERESTS
                            // ═══════════════════════════════════════════════
                            if (interestKeys.isNotEmpty) ...[
                              sectionLabel('Interests', emoji: '✨'),
                              chipWrap(interestKeys, useEmoji: true),
                            ],
                            if (subInterestTags.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                child: Wrap(
                                  spacing: 7,
                                  runSpacing: 7,
                                  children: subInterestTags.map((tag) {
                                    final emoji = getEmojiForTag(tag);
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 11,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.05),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: Colors.white.withValues(alpha: 0.09),
                                        ),
                                      ),
                                      child: Text(
                                        emoji.isNotEmpty ? '$emoji $tag' : tag,
                                        style: const TextStyle(
                                          color: Colors.white38,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ],

                            // ═══════════════════════════════════════════════
                            // PHOTO BREAK 2 — after Interests
                            // ═══════════════════════════════════════════════
                            if ((tab == 'Dating' || tab == 'Friends') &&
                                normalPics.length >= 2) ...[
                              const SizedBox(height: 20),
                              photoBlock(normalPics[1]),
                            ],

                            // ═══════════════════════════════════════════════
                            // CAUSES
                            // ═══════════════════════════════════════════════
                            if (causesSupported.isNotEmpty) ...[
                              sectionLabel('Cares about', emoji: '🌍'),
                              chipWrap(
                                causesSupported,
                                accent: const Color(0xFF34D399),
                                labelColor: const Color(0xFF6EE7B7),
                                useEmoji: true,
                              ),
                            ],

                            // ═══════════════════════════════════════════════
                            // LIFESTYLE (Dating / Friends)
                            // ═══════════════════════════════════════════════
                            if ((tab == 'Dating' || tab == 'Friends') &&
                                (drinking.isNotEmpty ||
                                    smoking.isNotEmpty ||
                                    lifestyle.isNotEmpty ||
                                    religiousBeliefs.isNotEmpty)) ...[
                              sectionLabel('Lifestyle', emoji: '🌱'),
                              if (drinking.isNotEmpty)
                                emojiInfoRow('🍺', 'Drinks $drinking'),
                              if (smoking.isNotEmpty)
                                emojiInfoRow('🚬', 'Smokes $smoking'),
                              if (lifestyle.isNotEmpty)
                                emojiInfoRow('💫', lifestyle),
                              if (religiousBeliefs.isNotEmpty)
                                emojiInfoRow('🙏', religiousBeliefs),
                            ],

                            // ═══════════════════════════════════════════════
                            // RELATIONSHIP — partner values + family plans (Dating)
                            // ═══════════════════════════════════════════════
                            if (tab == 'Dating' &&
                                (partnerValues.isNotEmpty || childrenPlans.isNotEmpty)) ...[
                              sectionLabel('Relationship', emoji: '❤️'),
                              if (partnerValues.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEC4899).withValues(alpha: 0.06),
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                        color: const Color(0xFFEC4899).withValues(alpha: 0.18),
                                      ),
                                    ),
                                    child: Text(
                                      partnerValues,
                                      style: const TextStyle(
                                        color: Colors.white60,
                                        fontSize: 14,
                                        height: 1.65,
                                      ),
                                    ),
                                  ),
                                ),
                              if (partnerValues.isNotEmpty && childrenPlans.isNotEmpty)
                                const SizedBox(height: 14),
                              if (childrenPlans.isNotEmpty)
                                emojiInfoRow('👶', childrenPlans),
                            ],

                            // ═══════════════════════════════════════════════
                            // PHOTO BREAK 3 — after Lifestyle / Relationship
                            // ═══════════════════════════════════════════════
                            if ((tab == 'Dating' || tab == 'Friends') &&
                                normalPics.length >= 3) ...[
                              const SizedBox(height: 20),
                              photoBlock(normalPics[2], height: 260),
                            ],

                            // ═══════════════════════════════════════════════
                            // LANGUAGES — just before Soundtrack
                            // ═══════════════════════════════════════════════
                            if (languages.isNotEmpty) ...[
                              sectionLabel('Speaks', emoji: '🗣️'),
                              chipWrap(
                                languages,
                                accent: Colors.white,
                                labelColor: Colors.white60,
                                useEmoji: true,
                              ),
                            ],

                            // ═══════════════════════════════════════════════
                            // PHOTO BREAK 4 — after Languages
                            // ═══════════════════════════════════════════════
                            if ((tab == 'Dating' || tab == 'Friends') &&
                                normalPics.length >= 4) ...[
                              const SizedBox(height: 20),
                              photoBlock(normalPics[3]),
                            ],

                            // ═══════════════════════════════════════════════
                            // SOUNDTRACK (Dating / Friends)
                            // ═══════════════════════════════════════════════
                            if ((tab == 'Dating' || tab == 'Friends') &&
                                topArtists.isNotEmpty) ...[
                              sectionLabel('Soundtrack', emoji: '🎵'),
                              chipWrap(
                                topArtists,
                                accent: const Color(0xFFA78BFA),
                                labelColor: const Color(0xFFC4B5FD),
                              ),
                            ],

                            // ═══════════════════════════════════════════════
                            // PETS (Dating / Friends)
                            // ═══════════════════════════════════════════════
                            if ((tab == 'Dating' || tab == 'Friends') &&
                                pets.isNotEmpty) ...[
                              sectionLabel('Pet parent', emoji: '🐾'),
                              chipWrap(
                                pets,
                                accent: const Color(0xFFFBBF24),
                                labelColor: const Color(0xFFFDE68A),
                                useEmoji: true,
                              ),
                            ],

                            // ═══════════════════════════════════════════════
                            // PROFESSIONAL: Activities + Open to + Tech stack
                            // ═══════════════════════════════════════════════
                            if (tab == 'Professional') ...[
                              if (activities.isNotEmpty) ...[
                                sectionLabel('Into', icon: LucideIcons.activity),
                                chipWrap(
                                  activities,
                                  accent: Colors.white,
                                  labelColor: Colors.white60,
                                ),
                              ],
                              if (lookingForLabels.isNotEmpty) ...[
                                sectionLabel('Open to', emoji: '🤝'),
                                chipWrap(lookingForLabels),
                              ],
                              if (techSkills.isNotEmpty) ...[
                                sectionLabel('Tech stack', emoji: '💻'),
                                chipWrap(
                                  techSkills,
                                  accent: Colors.cyanAccent,
                                  labelColor: Colors.cyanAccent,
                                ),
                              ],
                            ],

                            // ═══════════════════════════════════════════════
                            // REMAINING PHOTOS (5th+, Dating / Friends)
                            // ═══════════════════════════════════════════════
                            if (tab == 'Dating' || tab == 'Friends')
                              ...normalPics.skip(4).map(
                                    (pic) => Padding(
                                      padding: const EdgeInsets.only(top: 20),
                                      child: photoBlock(pic),
                                    ),
                                  ),

                            // ═══════════════════════════════════════════════
                            // SAFETY ACTIONS — Hide · Block · Report
                            // ═══════════════════════════════════════════════
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 36, 20, 0),
                              child: Column(
                                children: [
                                  Divider(
                                    color: Colors.white.withValues(alpha: 0.07),
                                    height: 1,
                                  ),
                                  const SizedBox(height: 18),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _safetyButton(
                                        context: context,
                                        icon: LucideIcons.eyeOff,
                                        label: 'Hide',
                                        color: Colors.white38,
                                        onTap: () async {
                                          Navigator.pop(context);
                                          await _performAction(candidateId, 'hide');
                                        },
                                      ),
                                      Container(
                                        width: 1,
                                        height: 28,
                                        margin: const EdgeInsets.symmetric(horizontal: 18),
                                        color: Colors.white.withValues(alpha: 0.08),
                                      ),
                                      _safetyButton(
                                        context: context,
                                        icon: LucideIcons.shieldOff,
                                        label: 'Block',
                                        color: Colors.orange,
                                        onTap: () async {
                                          final ok = await showDialog<bool>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              backgroundColor: const Color(0xFF0F172A),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(20),
                                              ),
                                              title: const Text(
                                                'Block user?',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              content: Text(
                                                "$name will no longer appear in your discovery, and you'll disappear from theirs.",
                                                style: const TextStyle(
                                                  color: Colors.white54,
                                                  height: 1.5,
                                                ),
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
                                                  style: TextButton.styleFrom(
                                                    foregroundColor: Colors.orange,
                                                  ),
                                                  child: const Text(
                                                    'Block',
                                                    style: TextStyle(fontWeight: FontWeight.bold),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                          if ((ok ?? false) && context.mounted) {
                                            Navigator.pop(context);
                                            await _performAction(candidateId, 'block');
                                          }
                                        },
                                      ),
                                      Container(
                                        width: 1,
                                        height: 28,
                                        margin: const EdgeInsets.symmetric(horizontal: 18),
                                        color: Colors.white.withValues(alpha: 0.08),
                                      ),
                                      _safetyButton(
                                        context: context,
                                        icon: LucideIcons.flag,
                                        label: 'Report',
                                        color: Colors.redAccent,
                                        onTap: () async {
                                          final ok = await showDialog<bool>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              backgroundColor: const Color(0xFF0F172A),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(20),
                                              ),
                                              title: const Text(
                                                'Report profile?',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              content: const Text(
                                                "We'll review this profile and take appropriate action. Thank you for keeping the community safe.",
                                                style: TextStyle(
                                                  color: Colors.white54,
                                                  height: 1.5,
                                                ),
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
                                                  style: TextButton.styleFrom(
                                                    foregroundColor: Colors.redAccent,
                                                  ),
                                                  child: const Text(
                                                    'Report',
                                                    style: TextStyle(fontWeight: FontWeight.bold),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                          if ((ok ?? false) && context.mounted) {
                                            Navigator.pop(context);
                                            await _performAction(candidateId, 'report');
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                ],
                              ),
                            ),

                            const SizedBox(height: 28),
                          ],
                        ),
                      ),

                      // ── Sticky action bar ──────────────────────────────────
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                        decoration: BoxDecoration(
                          color: const Color(0xFF090D1A),
                          border: Border(
                            top: BorderSide(
                              color: Colors.white.withValues(alpha: 0.06),
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            // Pass
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white54,
                                  side: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.14),
                                  ),
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
                            // Superlike
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
                            // Pull into Orbit
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
                                    'Pull into Orbit',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ),
                              ),
                            ),
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
    final ageMax = AppConfig.current.isMainVariant ? 80.0 : 27.0;
    final ageDivisions = AppConfig.current.isMainVariant ? 62 : 9;
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

    unawaited(
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setModalState) {
              // ── helpers ────────────────────────────────────────────────────

              Widget filterChips(
                List<String> options,
                List<String> selected,
              ) {
                return Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: options.map((opt) {
                    final sel = selected.contains(opt);
                    return FilterChip(
                      label: Text(
                        opt,
                        style: TextStyle(
                          fontSize: 12,
                          color: sel ? theme : Colors.white60,
                        ),
                      ),
                      selected: sel,
                      selectedColor: theme.withValues(alpha: 0.15),
                      backgroundColor: Colors.white.withValues(alpha: 0.05),
                      checkmarkColor: theme,
                      side: BorderSide(
                        color: sel
                            ? theme
                            : Colors.white.withValues(alpha: 0.2),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      onSelected: (v) {
                        setModalState(() {
                          if (v) {
                            if (options == FilterOptions.drinking ||
                                options == FilterOptions.smoking) {
                              if (opt == 'Never') {
                                selected.clear();
                              } else {
                                selected.remove('Never');
                              }
                            } else if (options == FilterOptions.childrenPlans) {
                              if (opt == 'Not specified') {
                                selected.clear();
                              } else {
                                selected.remove('Not specified');
                              }
                            } else if (options == FilterOptions.religiousBeliefs) {
                              if (opt == 'Atheist' || opt == 'Agnostic') {
                                selected.removeWhere(
                                  (item) =>
                                      item != 'Atheist' && item != 'Agnostic',
                                );
                              } else if (opt == 'Not specified') {
                                selected.clear();
                              } else {
                                selected.remove('Atheist');
                                selected.remove('Agnostic');
                                selected.remove('Not specified');
                              }
                            }
                            selected.add(opt);
                          } else {
                            selected.remove(opt);
                          }
                        });
                        setState(() {});
                        unawaited(_fetchOrbitNodes());
                      },
                    );
                  }).toList(),
                );
              }

              Widget codeChips(
                List<Map<String, String>> options,
                List<String> selected,
              ) {
                return Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: options.map((opt) {
                    final code = opt['code']!;
                    final label = opt['label']!;
                    final sel = selected.contains(code);
                    return FilterChip(
                      label: Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          color: sel ? theme : Colors.white60,
                        ),
                      ),
                      selected: sel,
                      selectedColor: theme.withValues(alpha: 0.15),
                      backgroundColor: Colors.white.withValues(alpha: 0.05),
                      checkmarkColor: theme,
                      side: BorderSide(
                        color: sel
                            ? theme
                            : Colors.white.withValues(alpha: 0.2),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      onSelected: (v) {
                        setModalState(
                          () => v ? selected.add(code) : selected.remove(code),
                        );
                        setState(() {});
                        unawaited(_fetchOrbitNodes());
                      },
                    );
                  }).toList(),
                );
              }

              Widget customSwitch({
                required bool value,
                required ValueChanged<bool> onChanged,
              }) {
                return GestureDetector(
                  onTap: () => onChanged(!value),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 42,
                    height: 22,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(11),
                      color: value ? theme : Colors.white.withValues(alpha: 0.08),
                      border: Border.all(
                        color: value ? theme : Colors.white.withValues(alpha: 0.15),
                        width: 1,
                      ),
                    ),
                    child: AnimatedAlign(
                      duration: const Duration(milliseconds: 200),
                      alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        width: 16,
                        height: 16,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: value ? Colors.black87 : Colors.white54,
                        ),
                      ),
                    ),
                  ),
                );
              }

              Widget customAddButton({required VoidCallback onTap}) {
                return InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: theme.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: theme.withValues(alpha: 0.2),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.plus, size: 12, color: theme),
                        const SizedBox(width: 4),
                        Text(
                          'Add',
                          style: TextStyle(
                            color: theme,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              Widget filterSection({
                required String label,
                Widget? action,
                required Widget child,
                String? subtitle,
              }) {
                return Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B).withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.05),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              label,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (action != null) action,
                        ],
                      ),
                      if (subtitle != null && subtitle.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      child,
                    ],
                  ),
                );
              }


              // ── sheet ──────────────────────────────────────────────────────
              // Wrap in a dark Theme so M3 chip/switch surface colors don't
              // inherit the app's light ColorScheme inside this bottom sheet.

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
                    return Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(32),
                        ),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                        children: [
                          // Drag handle
                          Center(
                            child: Container(
                              width: 40,
                              height: 4,
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),

                          // Header
                          const Text(
                            'Constellation Filters',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 24),

                          // ── General filters (all tabs) ──────────────────────
                          filterSection(
                            label: 'Age Range',
                            action: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: theme.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: theme.withValues(alpha: 0.2),
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                '${_ageRange.start.round()} – ${_ageRange.end.round()}',
                                style: TextStyle(
                                  color: theme,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: theme,
                                inactiveTrackColor: Colors.white.withValues(alpha: 0.08),
                                trackHeight: 3.0,
                                thumbColor: theme,
                                overlayColor: theme.withValues(alpha: 0.12),
                                valueIndicatorColor: theme,
                                valueIndicatorTextStyle: const TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                ),
                                rangeThumbShape: const RoundRangeSliderThumbShape(
                                  enabledThumbRadius: 6.0,
                                  elevation: 2.0,
                                ),
                                rangeTrackShape: const RoundedRectRangeSliderTrackShape(),
                              ),
                              child: RangeSlider(
                                values: _ageRange,
                                min: 18,
                                max: ageMax,
                                divisions: ageDivisions,
                                activeColor: theme,
                                inactiveColor: Colors.white12,
                                labels: RangeLabels(
                                  _ageRange.start.round().toString(),
                                  _ageRange.end.round().toString(),
                                ),
                                onChanged: (values) {
                                  setModalState(() => _ageRange = values);
                                  setState(() {});
                                },
                                onChangeEnd: (values) {
                                  unawaited(_fetchOrbitNodes());
                                },
                              ),
                            ),
                          ),

                          filterSection(
                            label: 'Drinking',
                            child: filterChips(
                              FilterOptions.drinking,
                              _selectedDrinking,
                            ),
                          ),

                          filterSection(
                            label: 'Smoking',
                            child: filterChips(
                              FilterOptions.smoking,
                              _selectedSmoking,
                            ),
                          ),

                          // Languages section (Custom design with separate selection pane)
                          filterSection(
                            label: 'Languages',
                            action: customAddButton(
                              onTap: () => _openTagSelectionPane(
                                title: 'Select Languages',
                                options: FilterOptions.languages,
                                selected: _selectedLanguages,
                                setModalState: setModalState,
                              ),
                            ),
                            child: _selectedLanguages.isEmpty
                                ? const Text(
                                    'No languages selected.',
                                    style: TextStyle(
                                      color: Colors.white38,
                                      fontSize: 12,
                                    ),
                                  )
                                : Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    children: _selectedLanguages.map((opt) {
                                      return Chip(
                                        label: Text(
                                          opt,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.white70,
                                          ),
                                        ),
                                        backgroundColor: Colors.white.withValues(alpha: 0.05),
                                        deleteIcon: Icon(
                                          LucideIcons.x,
                                          size: 14,
                                          color: theme,
                                        ),
                                        side: BorderSide(
                                          color: Colors.white.withValues(alpha: 0.15),
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        onDeleted: () {
                                          setModalState(() {
                                            _selectedLanguages.remove(opt);
                                          });
                                          setState(() {});
                                          unawaited(_fetchOrbitNodes());
                                        },
                                      );
                                    }).toList(),
                                  ),
                          ),

                          // Interests section (Custom design with separate selection pane)
                          filterSection(
                            label: 'Interests',
                            action: customAddButton(
                              onTap: () {
                                unawaited(
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute<void>(
                                      builder: (context) => InterestsOverlay(
                                        initialSelected: _selectedSubInterests,
                                        saveButtonText: 'Save Filter',
                                        themeColor: theme,
                                        onSave: (newInterests) {
                                          setModalState(() {
                                            _selectedSubInterests.clear();
                                            _selectedSubInterests.addAll(newInterests);
                                          });
                                          setState(() {});
                                          unawaited(_fetchOrbitNodes());
                                        },
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                            child: _selectedSubInterests.isEmpty
                                ? const Text(
                                    'No interests selected.',
                                    style: TextStyle(
                                      color: Colors.white38,
                                      fontSize: 12,
                                    ),
                                  )
                                : Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    children: _selectedSubInterests.map((opt) {
                                      return Chip(
                                        label: Text(
                                          opt,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.white70,
                                          ),
                                        ),
                                        backgroundColor: Colors.white.withValues(alpha: 0.05),
                                        deleteIcon: Icon(
                                          LucideIcons.x,
                                          size: 14,
                                          color: theme,
                                        ),
                                        side: BorderSide(
                                          color: Colors.white.withValues(alpha: 0.15),
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        onDeleted: () {
                                          setModalState(() {
                                            _selectedSubInterests.remove(opt);
                                          });
                                          setState(() {});
                                          unawaited(_fetchOrbitNodes());
                                        },
                                      );
                                    }).toList(),
                                  ),
                          ),

                          // Campus Year (flavor variant only)
                          if (AppConfig.current.isFlavorVariant)
                            filterSection(
                              label: 'Campus Year',
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: List.generate(5, (index) {
                                  final year = index + 1;
                                  final sel = _selectedYears.contains(year);
                                  return FilterChip(
                                    label: Text(
                                      'Yr $year',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: sel ? theme : Colors.white60,
                                      ),
                                    ),
                                    selected: sel,
                                    selectedColor: theme.withValues(
                                      alpha: 0.15,
                                    ),
                                    backgroundColor: Colors.white.withValues(
                                      alpha: 0.05,
                                    ),
                                    checkmarkColor: theme,
                                    side: BorderSide(
                                      color: sel
                                          ? theme
                                          : Colors.white.withValues(
                                              alpha: 0.2,
                                            ),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    onSelected: (v) {
                                      setModalState(
                                        () => v
                                            ? _selectedYears.add(year)
                                            : _selectedYears.remove(year),
                                      );
                                      setState(() {});
                                      unawaited(_fetchOrbitNodes());
                                    },
                                  );
                                }),
                              ),
                            ),

                          // ── Dating Preferences ──────────────────────────────
                          if (widget.tab == 'Dating') ...[
                            filterSection(
                              label: 'Children Plans',
                              child: filterChips(
                                FilterOptions.childrenPlans,
                                _selectedChildrenPlans,
                              ),
                            ),

                            filterSection(
                              label: 'Religious Beliefs',
                              child: filterChips(
                                FilterOptions.religiousBeliefs,
                                _selectedReligiousBeliefs,
                              ),
                            ),

                            const Padding(
                              padding: EdgeInsets.only(top: 16, bottom: 16, left: 4),
                              child: Text(
                                'YOUR DATING PREFERENCES',
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 2.0,
                                ),
                              ),
                            ),

                            // Show Who
                            filterSection(
                              label: 'Who are you interested in meeting?',
                              subtitle: 'Select the gender identities you would like to see in your Orbit.',
                              action: _savingFields.contains('dating_target_buckets')
                                  ? const SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.white60,
                                        ),
                                      ),
                                    )
                                  : null,
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  {'code': 'M', 'label': 'Men'},
                                  {'code': 'F', 'label': 'Women'},
                                  {'code': 'NB', 'label': 'Non-binary'},
                                  {'code': 'Open', 'label': 'Open to all'},
                                ].map((item) {
                                final code = item['code']!;
                                final isSelected = _selectedShowBuckets.contains(code);
                                return FilterChip(
                                  label: Text(item['label']!),
                                  selected: isSelected,
                                  selectedColor: theme.withValues(alpha: 0.15),
                                  backgroundColor: Colors.white.withValues(alpha: 0.05),
                                  checkmarkColor: theme,
                                  side: BorderSide(
                                    color: isSelected
                                        ? theme
                                        : Colors.white.withValues(alpha: 0.2),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  labelStyle: TextStyle(
                                    color: isSelected ? theme : Colors.white60,
                                    fontSize: 12,
                                  ),
                                  onSelected: (selected) async {
                                    if (_savingFields.contains('dating_target_buckets')) {
                                      return;
                                    }
                                    setModalState(() {
                                      if (selected) {
                                        _selectedShowBuckets.add(code);
                                      } else {
                                        _selectedShowBuckets.remove(code);
                                      }
                                    });
                                    await _saveDatingField(
                                      'dating_target_buckets',
                                      _selectedShowBuckets,
                                      setModalState,
                                    );
                                  },
                                );
                              }).toList(),
                            ),
                          ),

                            // Dating Intent
                            filterSection(
                              label: 'What are you looking for?',
                              subtitle: 'Select the relationship types you are open to.',
                              action: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_savingFields.contains('dating_for')) ...[
                                    const SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.white60,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Text(
                                    'Dealbreaker',
                                    style: TextStyle(
                                      color: _dealbreakerFields.contains('dating_for') ? theme : Colors.white38,
                                      fontSize: 11,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  customSwitch(
                                    value: _dealbreakerFields.contains('dating_for'),
                                    onChanged: (v) {
                                      setModalState(() {
                                        if (v) {
                                          _dealbreakerFields.add('dating_for');
                                        } else {
                                          _dealbreakerFields.remove('dating_for');
                                        }
                                      });
                                      setState(() {});
                                      unawaited(_fetchOrbitNodes());
                                    },
                                  ),
                                ],
                              ),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  {'code': 'short', 'label': 'Short-term'},
                                  {'code': 'long', 'label': 'Long-term'},
                                  {'code': 'casual', 'label': 'Casual Dating'},
                                  {'code': 'fling', 'label': 'Fling'},
                                  {'code': 'hookups', 'label': 'Hookups'},
                                  {'code': 'fwb', 'label': 'Friends with Benefits'},
                                  {'code': 'monogamous', 'label': 'Monogamous'},
                                  {'code': 'polyamorous', 'label': 'Polyamorous'},
                                  {'code': 'open_rel', 'label': 'Open Relationship'},
                                  {'code': 'marriage', 'label': 'Marriage / Life Partner'},
                                  {'code': 'platonic', 'label': 'Platonic Dating'},
                                  {'code': 'unsure', 'label': 'Figuring it out'},
                                ].map((item) {
                                  final code = item['code']!;
                                  final isSelected = _selectedDatingFor.contains(code);
                                  return FilterChip(
                                    label: Text(item['label']!),
                                    selected: isSelected,
                                    selectedColor: theme.withValues(alpha: 0.15),
                                    backgroundColor: Colors.white.withValues(alpha: 0.05),
                                    checkmarkColor: theme,
                                    side: BorderSide(
                                      color: isSelected
                                          ? theme
                                          : Colors.white.withValues(alpha: 0.2),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    labelStyle: TextStyle(
                                      color: isSelected ? theme : Colors.white60,
                                      fontSize: 12,
                                    ),
                                    onSelected: (selected) async {
                                      if (_savingFields.contains('dating_for')) {
                                        return;
                                      }
                                      setModalState(() {
                                        if (selected) {
                                          _selectedDatingFor.add(code);
                                        } else {
                                          _selectedDatingFor.remove(code);
                                        }
                                      });
                                      await _saveDatingField(
                                        'dating_for',
                                        _selectedDatingFor,
                                        setModalState,
                                      );
                                    },
                                  );
                                }).toList(),
                              ),
                            ),

                            // Partner Values
                            filterSection(
                              label: 'Partner Values',
                              subtitle: 'Choose the qualities and shared principles you value most.',
                              action: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_savingFields.contains('partner_values')) ...[
                                    const SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.white60,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Text(
                                    'Dealbreaker',
                                    style: TextStyle(
                                      color: _dealbreakerFields.contains('partner_values') ? theme : Colors.white38,
                                      fontSize: 11,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  customSwitch(
                                    value: _dealbreakerFields.contains('partner_values'),
                                    onChanged: (v) {
                                      setModalState(() {
                                        if (v) {
                                          _dealbreakerFields.add('partner_values');
                                        } else {
                                          _dealbreakerFields.remove('partner_values');
                                        }
                                      });
                                      setState(() {});
                                      unawaited(_fetchOrbitNodes());
                                    },
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (_selectedPartnerValues.isEmpty)
                                    const Text(
                                      'No partner values selected.',
                                      style: TextStyle(
                                        color: Colors.white38,
                                        fontSize: 12,
                                      ),
                                    )
                                  else
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 6,
                                      children: _selectedPartnerValues.map((val) {
                                        return Chip(
                                          label: Text(
                                            val,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.white70,
                                            ),
                                          ),
                                          backgroundColor: Colors.white.withValues(alpha: 0.05),
                                          deleteIcon: Icon(
                                            LucideIcons.x,
                                            size: 14,
                                            color: theme,
                                          ),
                                          side: BorderSide(
                                            color: Colors.white.withValues(alpha: 0.15),
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          onDeleted: () async {
                                            if (_savingFields.contains('partner_values')) {
                                              return;
                                            }
                                            setModalState(() {
                                              _selectedPartnerValues.remove(val);
                                            });
                                            await _saveDatingField(
                                              'partner_values',
                                              _selectedPartnerValues.join(', '),
                                              setModalState,
                                            );
                                          },
                                        );
                                      }).toList(),
                                    ),
                                  const SizedBox(height: 12),
                                  customAddButton(
                                    onTap: () => _openPartnerValuesSelectionPane(
                                      setModalState: setModalState,
                                      predefinedValues: predefinedValues,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          // ── Professional Preferences ────────────────────────
                          if (widget.tab == 'Professional') ...[
                            filterSection(
                              label: 'Looking For',
                              child: codeChips(
                                FilterOptions.lookingForOptions,
                                _selectedLookingFor,
                              ),
                            ),

                            filterSection(
                              label: 'Causes Supported',
                              child: filterChips(
                                FilterOptions.causesSupported,
                                _selectedCausesSupported,
                              ),
                            ),

                            filterSection(
                              label: 'Tech Skills',
                              child: filterChips(
                                FilterOptions.techSkills,
                                _selectedTechSkills,
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ), // DraggableScrollableSheet
              ); // Theme
            },
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
                        child:
                            Container(
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
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(
                              LucideIcons.arrowLeft,
                              color: Colors.white,
                            ),
                            onPressed: () => Navigator.pop(context),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${widget.tab} Constellation',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Row(
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

          if (_isReloading)
            Positioned.fill(
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: ColoredBox(
                    color: const Color(0xFF020408).withValues(alpha: 0.6),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 90,
                            height: 90,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: widget.themeColor.withValues(alpha: 0.25),
                                  blurRadius: 30,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                widget.themeColor,
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                          Text(
                            'Aligning Constellations...',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.95),
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 2.5,
                              shadows: [
                                Shadow(
                                  color: widget.themeColor.withValues(alpha: 0.4),
                                  blurRadius: 12,
                                ),
                              ],
                            ),
                          )
                              .animate(
                                onPlay: (controller) =>
                                    controller.repeat(reverse: true),
                              )
                              .fade(
                                begin: 0.5,
                                end: 1.0,
                                duration: 1200.ms,
                                curve: Curves.easeInOut,
                              ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
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

class CelestialBackgroundPainter extends CustomPainter {
  CelestialBackgroundPainter({
    required this.themeColor,
    required this.pulseValue,
  });

  final Color themeColor;
  final double pulseValue;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..isAntiAlias = true;

    // 1. Draw Starfield (Deterministic based on coordinates)
    for (var i = 0; i < 150; i++) {
      final x = (math.sin(i * 12345.67) * 0.5 + 0.5) * size.width;
      final y = (math.cos(i * 98765.43) * 0.5 + 0.5) * size.height;
      final starSize = (math.sin(i * 4567.89) * 0.5 + 0.5) * 1.8 + 0.4;

      // Twinkle animation
      final twinklePhase = math.sin(pulseValue * 2.0 * math.pi + i);
      final alpha = (twinklePhase * 0.4 + 0.6).clamp(0.1, 1.0);

      paint.color = Colors.white.withValues(alpha: alpha * 0.55);
      canvas.drawCircle(Offset(x, y), starSize, paint);

      // Occasional star flares for larger stars
      if (starSize > 1.8 && twinklePhase > 0.85) {
        paint.color = Colors.white.withValues(
          alpha: (twinklePhase - 0.85) * 2.0,
        );
        canvas.drawLine(Offset(x - 4, y), Offset(x + 4, y), paint);
        canvas.drawLine(Offset(x, y - 4), Offset(x, y + 4), paint);
      }
    }

    // 2. High-Tech Grid Coordinate Rings & Crosshairs
    final gridPaint = Paint()
      ..color = themeColor.withValues(alpha: 0.08)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Cardinal axis lines
    canvas.drawLine(
      Offset(0, center.dy),
      Offset(size.width, center.dy),
      gridPaint,
    );
    canvas.drawLine(
      Offset(center.dx, 0),
      Offset(center.dx, size.height),
      gridPaint,
    );

    // Diagonal coordinate sweeps
    final diagonalPaint = Paint()
      ..color = themeColor.withValues(alpha: 0.03)
      ..strokeWidth = 0.8;
    canvas.drawLine(
      const Offset(0, 0),
      Offset(size.width, size.height),
      diagonalPaint,
    );
    canvas.drawLine(
      Offset(size.width, 0),
      Offset(0, size.height),
      diagonalPaint,
    );

    // 3. Tick marks on cardinal lines
    for (var r = 100.0; r <= 600.0; r += 100.0) {
      canvas.drawCircle(
        Offset(center.dx + r, center.dy),
        2,
        paint..color = themeColor.withValues(alpha: 0.35),
      );
      canvas.drawCircle(Offset(center.dx - r, center.dy), 2, paint);
      canvas.drawCircle(Offset(center.dx, center.dy + r), 2, paint);
      canvas.drawCircle(Offset(center.dx, center.dy - r), 2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CelestialBackgroundPainter oldDelegate) {
    return oldDelegate.pulseValue != pulseValue ||
        oldDelegate.themeColor != themeColor;
  }
}

class ConstellationLinesPainter extends CustomPainter {
  ConstellationLinesPainter({
    required this.nodes,
    required this.themeColor,
  });

  final List<dynamic> nodes;
  final Color themeColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (nodes.isEmpty) return;
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = themeColor.withValues(alpha: 0.1)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Draw lines from center to nodes
    for (final node in nodes) {
      final x = (node['x'] as num?)?.toDouble() ?? 0.0;
      final y = (node['y'] as num?)?.toDouble() ?? 0.0;
      final nodePos = Offset(center.dx + x, center.dy + y);
      canvas.drawLine(center, nodePos, paint);
    }

    // Draw lines between nearby nodes (e.g. within 160 units of each other)
    const maxDistSq = 160.0 * 160.0;
    for (var i = 0; i < nodes.length; i++) {
      final x1 = (nodes[i]['x'] as num?)?.toDouble() ?? 0.0;
      final y1 = (nodes[i]['y'] as num?)?.toDouble() ?? 0.0;
      final p1 = Offset(center.dx + x1, center.dy + y1);

      for (var j = i + 1; j < nodes.length; j++) {
        final x2 = (nodes[j]['x'] as num?)?.toDouble() ?? 0.0;
        final y2 = (nodes[j]['y'] as num?)?.toDouble() ?? 0.0;
        final p2 = Offset(center.dx + x2, center.dy + y2);

        final dx = p1.dx - p2.dx;
        final dy = p1.dy - p2.dy;
        if (dx * dx + dy * dy <= maxDistSq) {
          canvas.drawLine(p1, p2, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant ConstellationLinesPainter oldDelegate) {
    return oldDelegate.nodes != nodes || oldDelegate.themeColor != themeColor;
  }
}

class OrbitGridPainter extends CustomPainter {
  OrbitGridPainter({
    required this.themeColor,
    required this.sweepValue,
  });

  final Color themeColor;
  final double sweepValue;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final gridPaint = Paint()
      ..color = themeColor.withValues(alpha: 0.08)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Cardinal axis lines
    canvas.drawLine(
      Offset(0, center.dy),
      Offset(size.width, center.dy),
      gridPaint,
    );
    canvas.drawLine(
      Offset(center.dx, 0),
      Offset(center.dx, size.height),
      gridPaint,
    );

    // Diagonal coordinate sweeps
    final diagonalPaint = Paint()
      ..color = themeColor.withValues(alpha: 0.03)
      ..strokeWidth = 0.8;
    canvas.drawLine(
      const Offset(0, 0),
      Offset(size.width, size.height),
      diagonalPaint,
    );
    canvas.drawLine(
      Offset(size.width, 0),
      Offset(0, size.height),
      diagonalPaint,
    );

    // Tick marks on cardinal lines
    final paint = Paint()..isAntiAlias = true;
    for (var r = 100.0; r <= 600.0; r += 100.0) {
      canvas.drawCircle(
        Offset(center.dx + r, center.dy),
        2,
        paint..color = themeColor.withValues(alpha: 0.35),
      );
      canvas.drawCircle(Offset(center.dx - r, center.dy), 2, paint);
      canvas.drawCircle(Offset(center.dx, center.dy + r), 2, paint);
      canvas.drawCircle(Offset(center.dx, center.dy - r), 2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant OrbitGridPainter oldDelegate) {
    return oldDelegate.themeColor != themeColor ||
        oldDelegate.sweepValue != sweepValue;
  }
}
