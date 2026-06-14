import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/screens/home/tabs/profile/widgets/storage_image.dart';
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

  // Viewport/Canvas Size
  final double _canvasSize = 3200;

  // Filters State
  RangeValues _ageRange = const RangeValues(18, 27);
  final List<int> _selectedYears = [1, 2, 3, 4, 5];
  String? _selectedRole;

  bool _isCentered = false;

  @override
  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    // Start fetching nodes immediately during navigation transition
    unawaited(_fetchOrbitNodes());
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
    if (_isCentered) return;
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
          'campus_years': _selectedYears,
          if (_selectedRole != null && _selectedRole!.isNotEmpty)
            'role': _selectedRole,
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
        for (var node in nodesList) {
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
    }
  }

  Future<void> _performAction(String candidateId, String actionType) async {
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) return;

      final config = AppConfig.current;
      final payload = {
        'target_id': candidateId,
        'action': actionType,
        'tab': widget.tab,
      };

      final response = await _dio.post<Map<String, dynamic>>(
        '${config.backendUrl}/api/v1/discover/action',
        data: payload,
        options: Options(
          headers: {'Authorization': 'Bearer ${session.accessToken}'},
        ),
      );

      if (response.statusCode == 200) {
        // Refresh nodes to exclude the actioned candidate
        await _fetchOrbitNodes(useExistingSession: true);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              backgroundColor: actionType == 'like' || actionType == 'superlike'
                  ? const Color(0xFFFF4F81)
                  : const Color(0xFF1E293B),
              content: Row(
                children: [
                  Icon(
                    actionType == 'like' || actionType == 'superlike'
                        ? LucideIcons.heartHandshake
                        : LucideIcons.compass,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    actionType == 'like' || actionType == 'superlike'
                        ? 'Pulled candidate into your gravity!'
                        : 'Repelled candidate into deep space.',
                    style: const TextStyle(fontWeight: FontWeight.bold),
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
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return FutureBuilder<Map<String, dynamic>>(
          future: _fetchNodeDetails(candidateId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Container(
                height: MediaQuery.of(context).size.height * 0.7,
                decoration: const BoxDecoration(
                  color: Color(0xFF0D121F),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                ),
                child: const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Color(0xFFFF4F81),
                    ),
                  ),
                ),
              );
            }

            if (snapshot.hasError || !snapshot.hasData) {
              return Container(
                height: MediaQuery.of(context).size.height * 0.5,
                decoration: const BoxDecoration(
                  color: Color(0xFF0D121F),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                ),
                child: Center(
                  child: Text(
                    'Failed to load details: ${snapshot.error}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              );
            }

            final data = snapshot.data!;
            final images = <String>[];
            if (data['profile_pic'] != null &&
                data['profile_pic'].toString().isNotEmpty) {
              images.add(data['profile_pic'].toString());
            }
            if (data['normal_pics'] is List) {
              images.addAll(
                List<String>.from(data['normal_pics'] as List<dynamic>),
              );
            }

            final interests = (data['interests'] as Map? ?? {}).keys
                .cast<String>()
                .toList();
            final partnerValues = data['partner_values']?.toString() ?? '';
            final bio = data['bio']?.toString() ?? '';

            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              decoration: BoxDecoration(
                color: const Color(0xFF0D121F).withValues(alpha: 0.95),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(32),
                ),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(32),
                ),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Column(
                    children: [
                      const SizedBox(height: 12),
                      Container(
                        width: 40,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2.5),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          children: [
                            // Gallery Carousel
                            if (images.isNotEmpty)
                              SizedBox(
                                height: 260,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: images.length,
                                  itemBuilder: (context, index) {
                                    return Container(
                                      width: 200,
                                      margin: const EdgeInsets.only(right: 12),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(24),
                                        border: Border.all(
                                          color: Colors.white12,
                                        ),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(24),
                                        child: StorageImage(
                                          imagePath: images[index],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            const SizedBox(height: 24),

                            // Basic details
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${data['name'] ?? 'Anonymous'}, ${data['age'] ?? ''}',
                                        style: const TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${data['campus_branch'] ?? ''} • Year ${data['campus_year'] ?? ''}',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: Colors.white60,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFFFF4F81,
                                    ).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: const Color(
                                        0xFFFF4F81,
                                      ).withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Text(
                                    '${((data['score'] as num?) ?? 0).round()}% match',
                                    style: const TextStyle(
                                      color: Color(0xFFFF4F81),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // Bio
                            if (bio.isNotEmpty) ...[
                              const Text(
                                'Bio',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                bio,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 24),
                            ],

                            // Values
                            if (partnerValues.isNotEmpty) ...[
                              const Text(
                                'Relationship Values',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                partnerValues,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 24),
                            ],

                            // Interests
                            if (interests.isNotEmpty) ...[
                              const Text(
                                'Common Interests',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: interests.map((interest) {
                                  return Chip(
                                    label: Text(interest),
                                    backgroundColor: Colors.white.withValues(
                                      alpha: 0.05,
                                    ),
                                    labelStyle: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                    side: BorderSide(
                                      color: Colors.white.withValues(
                                        alpha: 0.1,
                                      ),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 24),
                            ],
                          ],
                        ),
                      ),

                      // Action bar
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(color: Colors.white24),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                onPressed: () async {
                                  Navigator.pop(context);
                                  await _performAction(candidateId, 'hide');
                                },
                                icon: const Icon(LucideIcons.sparkles),
                                label: const Text(
                                  'Repel Node',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFF4F81),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  elevation: 8,
                                  shadowColor: const Color(
                                    0xFFFF4F81,
                                  ).withValues(alpha: 0.4),
                                ),
                                onPressed: () async {
                                  Navigator.pop(context);
                                  await _performAction(candidateId, 'like');
                                },
                                icon: const Icon(LucideIcons.heart),
                                label: const Text(
                                  'Pull into Orbit',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
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
          },
        );
      },
    );
  }

  Future<Map<String, dynamic>> _fetchNodeDetails(String candidateId) async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null || _sessionId == null) {
      throw Exception('Missing session authorization tokens.');
    }

    final config = AppConfig.current;
    final payload = {
      'session_id': _sessionId,
      'candidate_id': candidateId,
    };

    final response = await _dio.post<Map<String, dynamic>>(
      '${config.backendUrl}/api/v1/discover/node-detail',
      data: payload,
      options: Options(
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
      ),
    );

    if (response.statusCode == 200 && response.data != null) {
      return response.data!;
    }
    throw Exception('Error loading detail response.');
  }

  void _showFiltersPanel() {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setModalState) {
              return Container(
                padding: const EdgeInsets.all(24),
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
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Constellation Filters',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            LucideIcons.check,
                            color: Color(0xFFFF4F81),
                          ),
                          onPressed: () {
                            Navigator.pop(context);
                            unawaited(_fetchOrbitNodes());
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Age Range',
                      style: TextStyle(color: Colors.white70),
                    ),
                    RangeSlider(
                      values: _ageRange,
                      min: 18,
                      max: 27,
                      divisions: 9,
                      activeColor: const Color(0xFFFF4F81),
                      inactiveColor: Colors.white12,
                      labels: RangeLabels(
                        _ageRange.start.round().toString(),
                        _ageRange.end.round().toString(),
                      ),
                      onChanged: (values) {
                        setModalState(() {
                          _ageRange = values;
                        });
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Campus Years',
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(5, (index) {
                        final year = index + 1;
                        final isSelected = _selectedYears.contains(year);
                        return FilterChip(
                          label: Text('Yr $year'),
                          selected: isSelected,
                          selectedColor: const Color(0xFFFF4F81),
                          backgroundColor: Colors.white.withValues(alpha: 0.05),
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : Colors.white60,
                            fontSize: 12,
                          ),
                          checkmarkColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          onSelected: (selected) {
                            setModalState(() {
                              if (selected) {
                                _selectedYears.add(year);
                              } else {
                                _selectedYears.remove(year);
                              }
                            });
                            setState(() {});
                          },
                        );
                      }),
                    ),
                  ],
                ),
              );
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
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _centerViewport(constraints.maxWidth, constraints.maxHeight);
              });
              return InteractiveViewer(
                transformationController: _transformationController,
                minScale: 0.2,
                maxScale: 2,
                constrained: false,
                boundaryMargin: const EdgeInsets.all(1000),
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
                        const Color(0xFF020408).withValues(alpha: 0.0),
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
      Offset(0, 0),
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
        2.0,
        paint..color = themeColor.withValues(alpha: 0.35),
      );
      canvas.drawCircle(Offset(center.dx - r, center.dy), 2.0, paint);
      canvas.drawCircle(Offset(center.dx, center.dy + r), 2.0, paint);
      canvas.drawCircle(Offset(center.dx, center.dy - r), 2.0, paint);
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
    for (var node in nodes) {
      final x = (node['x'] as num?)?.toDouble() ?? 0.0;
      final y = (node['y'] as num?)?.toDouble() ?? 0.0;
      final nodePos = Offset(center.dx + x, center.dy + y);
      canvas.drawLine(center, nodePos, paint);
    }

    // Draw lines between nearby nodes (e.g. within 160 units of each other)
    final double maxDistSq = 160.0 * 160.0;
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
      Offset(0, 0),
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
        2.0,
        paint..color = themeColor.withValues(alpha: 0.35),
      );
      canvas.drawCircle(Offset(center.dx - r, center.dy), 2.0, paint);
      canvas.drawCircle(Offset(center.dx, center.dy + r), 2.0, paint);
      canvas.drawCircle(Offset(center.dx, center.dy - r), 2.0, paint);
    }
  }

  @override
  bool shouldRepaint(covariant OrbitGridPainter oldDelegate) {
    return oldDelegate.themeColor != themeColor ||
        oldDelegate.sweepValue != sweepValue;
  }
}
