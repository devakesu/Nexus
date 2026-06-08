// Telemetry rendering and CustomPainter math benefit from direct double representation and nested cascades.
// ignore_for_file: cascade_invocations, prefer_int_literals
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/utils/error_handler.dart';
import 'package:nexus/widgets/aesthetic_loaders.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SpaceNode {
  SpaceNode({
    required this.position,
    required this.velocity,
    required this.score,
    required this.label,
    required this.type,
    required this.targetRadius,
  });

  Offset position; // relative position from -1.2 to 1.2
  Offset velocity;
  final double score;
  final String label;
  final int? type; // 0 = DATING, 1 = FRIENDS, 2 = PRO
  final double? targetRadius; // target orbit shell radius
}

enum LoginView { options, email, phone, otp }

class LoginScreen extends StatefulWidget {
  const LoginScreen({required this.appName, super.key});

  final String appName;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  bool _isLoading = false;
  LoginView _currentView = LoginView.options;

  // Controllers/Values for Email and Phone login
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();

  bool _isPhoneOtp = true;
  int _resendCountdown = 0;
  Timer? _countdownTimer;

  // Physics & Particle Field State
  late AnimationController _physicsController;
  final List<SpaceNode> _nodes = [];
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  Offset _accelerometerOffset = Offset.zero;
  double _simulatedTime = 0.0;

  // Matrix Dimensional Drift States
  int _matrixIndex = 0; // 0 = DATING, 1 = FRIENDS, 2 = PRO
  Timer? _matrixTimer;

  // Touch micro-interaction state
  Offset? _normalizedTouchPosition; // relative touch position from -1.0 to 1.0

  @override
  void initState() {
    super.initState();
    _nodes.clear();

    // Initialize 6 desaturated nodes (2 of each category) spread out from the center at opposite angles
    final nodeConfigs = [
      {
        'type': 0,
        'radius': 0.55,
        'angle': 0.0,
        'score': 0.71,
        'label': 'Vector 0x4B',
      },
      {
        'type': 0,
        'radius': 0.55,
        'angle': math.pi,
        'score': 0.89,
        'label': 'Vector 0x8C',
      },
      {
        'type': 1,
        'radius': 0.75,
        'angle': math.pi / 3.0,
        'score': 0.65,
        'label': 'Vector 0x3F',
      },
      {
        'type': 1,
        'radius': 0.75,
        'angle': 4.0 * math.pi / 3.0,
        'score': 0.82,
        'label': 'Vector 0x9A',
      },
      {
        'type': 2,
        'radius': 0.95,
        'angle': 2.0 * math.pi / 3.0,
        'score': 0.94,
        'label': 'Vector 0xE7',
      },
      {
        'type': 2,
        'radius': 0.95,
        'angle': 5.0 * math.pi / 3.0,
        'score': 0.78,
        'label': 'Vector 0x5D',
      },
    ];

    for (final config in nodeConfigs) {
      final type = config['type']! as int;
      final radius = config['radius']! as double;
      final angle = config['angle']! as double;
      final score = config['score']! as double;
      final label = config['label']! as String;

      final x = radius * math.cos(angle);
      final y = radius * math.sin(angle);

      const speed = 0.007;
      final vx = speed * math.sin(angle);
      final vy = -speed * math.cos(angle);

      _nodes.add(
        SpaceNode(
          position: Offset(x, y),
          velocity: Offset(vx, vy),
          score: score,
          label: label,
          type: type,
          targetRadius: radius,
        ),
      );
    }

    // Setup 60fps Ticker/AnimationController for physics
    _physicsController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(_updatePhysics);

    unawaited(_physicsController.repeat());

    // Switch Matrix Drift configuration every 4.5 seconds
    _matrixTimer = Timer.periodic(const Duration(milliseconds: 4500), (timer) {
      if (mounted) {
        setState(() {
          _matrixIndex = (_matrixIndex + 1) % 3;
        });
      }
    });

    // Safely listen to accelerometer sensor events with strict channel error check
    unawaited(_initAccelerometer());
    _otpController.addListener(_updateOtpState);
  }

  void _updateOtpState() {
    if (mounted) setState(() {});
  }

  bool get _isOtpValid {
    final code = _otpController.text.trim();
    return code.length == 8 && RegExp(r'^\d{8}$').hasMatch(code);
  }

  Future<void> _initAccelerometer() async {
    // Disabled physical accelerometer subscription to prevent emulator/device gravity bias.
    // The physics simulation falls back to a uniform, beautiful simulated ambient orbit loop.
    _accelerometerOffset = Offset.zero;
  }

  void _updatePhysics() {
    if (!mounted) return;

    setState(() {
      _simulatedTime += 0.015;

      // Use simulated ambient gyroscopic drift rotation for perfect uniform orbit
      final activeTilt = Offset(
        math.sin(_simulatedTime) * 0.03,
        math.cos(_simulatedTime) * 0.03,
      );

      for (final node in _nodes) {
        // Apply velocity
        node.position += node.velocity;

        // Apply gyroscopic tilt translation
        node.velocity += activeTilt * 0.0015;

        // Physics variables mapping relative distance to center
        final toCenter = Offset.zero - node.position;
        final distToCenter = toCenter.distance;

        // Kinetic physics profiles based on the active matrix dimension
        if (_matrixIndex == 0 || _matrixIndex == 1) {
          // DATING & FRIENDS: Orbit shells mapping to individual node.targetRadius
          if (distToCenter > 0.01) {
            // Adjust targetRadius based on mode attraction factor
            final nodeRadius = node.targetRadius ?? 0.6;
            final targetR = _matrixIndex == 0 ? nodeRadius * 0.8 : nodeRadius;
            final diffRadius = distToCenter - targetR;
            // Pull/push node radially to balance it on its orbit shell
            final radialForce =
                (node.position / distToCenter) * (-diffRadius * 0.015);
            node.velocity += radialForce;

            // Continuous orbiting perpendicular force
            final orbitForce =
                Offset(-toCenter.dy, toCenter.dx) / distToCenter * 0.00035;
            node.velocity += orbitForce;
          }
        } else {
          // PRO: Rigid, structured grids aligned to matrix intersection points
          final gridTargetX = (node.position.dx * 2.5).roundToDouble() / 2.5;
          final gridTargetY = (node.position.dy * 2.5).roundToDouble() / 2.5;
          final gridTarget = Offset(gridTargetX, gridTargetY);
          node.velocity += (gridTarget - node.position) * 0.004;
        }

        // Keep a minimum distance from Center • (You) to prevent crowded overlapping
        const minCenterDistance = 0.38;
        if (distToCenter < minCenterDistance && distToCenter > 0.01) {
          final pushOut =
              (node.position / distToCenter) *
              0.0008 *
              (1.0 - distToCenter / minCenterDistance);
          node.velocity += pushOut;
        }

        // Kinetic Magnetic Finger Snapping
        final touch = _normalizedTouchPosition;
        if (touch != null) {
          final toTouch = touch - node.position;
          final distToTouch = toTouch.distance;
          if (distToTouch < 0.6 && distToTouch > 0.01) {
            // Violent acceleration pull toward finger
            final pullForce =
                toTouch / distToTouch * 0.0028 * (1.0 - distToTouch / 0.6);
            node.velocity += pullForce;
            // Add perpendicular vector for orbiting around the touch point
            final orbitVector =
                Offset(-toTouch.dy, toTouch.dx) / distToTouch * 0.0022;
            node.velocity += orbitVector;
          }
        }

        // Particle repulsion to prevent overlapping
        for (final other in _nodes) {
          if (identical(node, other)) continue;
          final diff = node.position - other.position;
          final dist = diff.distance;
          if (dist < 0.35 && dist > 0.01) {
            final repulsion = diff / dist * 0.0007 * (1.0 - dist / 0.35);
            node.velocity += repulsion;
          }
        }

        // Speed limit (damping)
        node.velocity *= 0.95;

        // Soft viewport bounds containment (relative boundary radius = 1.3)
        const boundaryRadius = 1.3;
        final currentDist = node.position.distance;
        if (currentDist > boundaryRadius) {
          node.position = node.position / currentDist * boundaryRadius;
          node.velocity = -node.velocity * 0.6; // bounce and dampen
        }
      }
    });
  }

  @override
  void dispose() {
    _matrixTimer?.cancel();
    unawaited(_accelerometerSubscription?.cancel());
    _physicsController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _otpController.removeListener(_updateOtpState);
    _otpController.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final config = AppConfig.current;
      final googleSignIn = GoogleSignIn(
        clientId: config.googleIosClientId,
        serverClientId: config.googleWebClientId,
      );

      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final googleAuth = await googleUser.authentication;
      final accessToken = googleAuth.accessToken;
      final idToken = googleAuth.idToken;

      if (accessToken == null || idToken == null) {
        throw Exception('Missing authentication tokens from Google.');
      }

      await Supabase.instance.client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );
    } on Object catch (e, stackTrace) {
      ErrorHandler.handleError(
        e,
        stackTrace: stackTrace,
        customMessage: 'Authentication failed: $e',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _sendEmailOtp() async {
    if (_resendCountdown > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFD32F2F),
          content: Text(
            'Please wait $_resendCountdown seconds before requesting another code.',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
      return;
    }

    final email = _emailController.text.trim();

    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFD32F2F),
          content: Text(
            'Please enter your email address.',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
      return;
    }

    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    if (!emailRegex.hasMatch(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFD32F2F),
          content: Text(
            'Please enter a valid email address.',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await Supabase.instance.client.auth.signInWithOtp(
        email: email,
      );
      if (mounted) {
        setState(() {
          _isPhoneOtp = false;
          _currentView = LoginView.otp;
          _resendCountdown = 60;
          _startCountdown();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFFFF7597),
            content: Text(
              'OTP sent successfully!',
              style: TextStyle(color: Colors.white),
            ),
          ),
        );
      }
    } on Object catch (e, stackTrace) {
      ErrorHandler.handleError(
        e,
        stackTrace: stackTrace,
        customMessage: 'Failed to send OTP: $e',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _sendOtp() async {
    if (_resendCountdown > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFD32F2F),
          content: Text(
            'Please wait $_resendCountdown seconds before requesting another code.',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
      return;
    }

    final phone = _phoneController.text.trim();

    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFD32F2F),
          content: Text(
            'Please enter your phone number.',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
      return;
    }

    final phoneRegex = RegExp(r'^\+[1-9]\d{7,14}$');
    if (!phoneRegex.hasMatch(phone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFD32F2F),
          content: Text(
            'Please enter a valid phone number starting with + (e.g. +1234567890).',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await Supabase.instance.client.auth.signInWithOtp(
        phone: phone,
      );
      if (mounted) {
        setState(() {
          _isPhoneOtp = true;
          _currentView = LoginView.otp;
          _resendCountdown = 60;
          _startCountdown();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFFFF7597),
            content: Text(
              'OTP sent successfully!',
              style: TextStyle(color: Colors.white),
            ),
          ),
        );
      }
    } on Object catch (e, stackTrace) {
      ErrorHandler.handleError(
        e,
        stackTrace: stackTrace,
        customMessage: 'Failed to send OTP: $e',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_resendCountdown > 0) {
            _resendCountdown--;
          } else {
            _countdownTimer?.cancel();
          }
        });
      }
    });
  }

  Future<void> _verifyOtp() async {
    final target = _isPhoneOtp
        ? _phoneController.text.trim()
        : _emailController.text.trim();
    final code = _otpController.text.trim();

    if (target.isEmpty || code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFD32F2F),
          content: Text(
            'Please enter the OTP verification code.',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
      return;
    }

    if (code.length != 8 || !RegExp(r'^\d{8}$').hasMatch(code)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFD32F2F),
          content: Text(
            'Please enter a valid 8-digit OTP code (digits only).',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      if (_isPhoneOtp) {
        await Supabase.instance.client.auth.verifyOTP(
          phone: target,
          token: code,
          type: OtpType.sms,
        );
      } else {
        await Supabase.instance.client.auth.verifyOTP(
          email: target,
          token: code,
          type: OtpType.email,
        );
      }
    } on Object catch (e, stackTrace) {
      ErrorHandler.handleError(
        e,
        stackTrace: stackTrace,
        customMessage: 'OTP verification failed: $e',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _handleTouchUpdate(Offset localPosition, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final relativeScale =
        size.width * 0.45; // alignment matching coordinate system scaling
    setState(() {
      _normalizedTouchPosition = Offset(
        (localPosition.dx - center.dx) / relativeScale,
        (localPosition.dy - center.dy) / relativeScale,
      );
    });
  }

  void _handleTouchEnd() {
    setState(() {
      _normalizedTouchPosition = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final isMec = widget.appName.toLowerCase().contains('mec');

    return Scaffold(
      backgroundColor: const Color(0xFF0B0D13), // Cosmic Obsidian
      body: SafeArea(
        top: false,
        bottom: false,
        child: GestureDetector(
          onPanStart: (details) =>
              _handleTouchUpdate(details.localPosition, size),
          onPanUpdate: (details) =>
              _handleTouchUpdate(details.localPosition, size),
          onPanEnd: (_) => _handleTouchEnd(),
          child: Stack(
            children: [
              // 1. Interactive Gravity Field Background Canvas
              Positioned.fill(
                child: CustomPaint(
                  painter: GravityFieldPainter(
                    nodes: _nodes,
                    touchPosition: _normalizedTouchPosition,
                    tiltOffset: _accelerometerOffset,
                    simulatedTime: _simulatedTime,
                    matrixIndex: _matrixIndex,
                  ),
                ),
              ),

              // 2. Tab Dimension Drift UI overlay (The Tri-Matrix Hint)
              Positioned(
                top: mediaQuery.padding.top + 180,
                left: 24,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B0D13).withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFF6B7280).withValues(alpha: 0.1),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '[ SYSTEM CONFIGURATION ]',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 8.5,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF6B7280),
                        ),
                      ),
                      const SizedBox(height: 6),
                      _buildMatrixRow(
                        '⚡ AXIS_A: DATING',
                        'RESOLVING HEARTS...',
                        _matrixIndex == 0,
                      ),
                      _buildMatrixRow(
                        '•  AXIS_B: FRIENDS',
                        'SYNCING SPARKLES...',
                        _matrixIndex == 1,
                      ),
                      _buildMatrixRow(
                        '•  AXIS_C: PROFESSIONAL',
                        'ALIGNING WORK VECTOR...',
                        _matrixIndex == 2,
                      ),
                    ],
                  ),
                ).animate().fade(delay: 300.ms, duration: 800.ms),
              ),

              // 3. High-fidelity minimal typography (Top Third)
              Positioned(
                top: mediaQuery.padding.top + 50,
                left: 24,
                right: 24,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          'N E X U S',
                          style: GoogleFonts.inter(
                            fontSize: 36,
                            fontWeight: FontWeight.w200,
                            letterSpacing: 8,
                            color: Colors.white,
                          ),
                        ),
                        if (isMec) ...[
                          const SizedBox(width: 12),
                          Text(
                            'M E C',
                            style: GoogleFonts.inter(
                              fontSize: 18,
                              fontWeight: FontWeight.w400,
                              letterSpacing: 4,
                              color: const Color(
                                0xFFFF7597,
                              ), // Pulsar Teal / Oracle Aqua accent
                            ),
                          ),
                        ],
                      ],
                    ).animate().fade(duration: 800.ms),
                    const SizedBox(height: 12),
                    Text(
                      'Ditch the swipe. Find your orbit.',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w300,
                        height: 1.4,
                        color: const Color(0xFF6B7280), // Muted Slate Grey
                      ),
                    ).animate().fade(delay: 200.ms, duration: 800.ms),
                  ],
                ),
              ),

              // 4. Pinned Glassmorphic OAuth Card (Bottom) with Optical Chromatic Border Dispersion (Perfected and Centered)
              Positioned(
                left: 16,
                right: 16,
                bottom: mediaQuery.padding.bottom + 24,
                child: CustomPaint(
                  painter: ChromaticBorderPainter(borderRadius: 24.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF161B26).withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_isLoading)
                              const Center(
                                child: Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8.0),
                                  child: NexusOrbitLoader(size: 60.0),
                                ),
                              )
                            else
                              _buildAuthContent(isMec),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAuthContent(bool isMec) {
    if (isMec) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildGoogleButton(),
          const SizedBox(height: 20),
          _buildFootnote('Please use your official campus account to login.'),
        ],
      );
    }

    switch (_currentView) {
      case LoginView.options:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildGoogleButton(),
            const SizedBox(height: 12),
            _buildGreyButton(
              onTap: () {
                setState(() {
                  _currentView = LoginView.email;
                });
              },
              icon: Icons.mail_outline_rounded,
              label: 'Sign in with Email',
            ),
            const SizedBox(height: 12),
            _buildGreyButton(
              onTap: () {
                setState(() {
                  _currentView = LoginView.phone;
                });
              },
              icon: Icons.phone_iphone_rounded,
              label: 'Sign in with Phone',
            ),
            const SizedBox(height: 20),
            _buildFootnote('Find your orbit. Connect seamlessly.'),
          ],
        );
      case LoginView.email:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Welcome!',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _emailController,
              hintText: 'Email address',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            _buildActionButton(
              onTap: _sendEmailOtp,
              label: 'Get OTP',
            ),
            const SizedBox(height: 12),
            _buildBackButton(),
          ],
        );
      case LoginView.phone:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Sign in with Phone',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Enter your phone number starting with +',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: const Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _phoneController,
              hintText: '+911234567890',
              icon: Icons.phone_iphone_rounded,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            _buildActionButton(
              onTap: _sendOtp,
              label: 'Get OTP',
            ),
            const SizedBox(height: 12),
            _buildBackButton(),
          ],
        );
      case LoginView.otp:
        final targetText = _isPhoneOtp
            ? _phoneController.text
            : _emailController.text;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Verify OTP',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Enter the 8-digit code sent to $targetText',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: const Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _otpController,
              hintText: '8-digit code',
              icon: Icons.lock_clock_outlined,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(8),
              ],
            ),
            const SizedBox(height: 16),
            _buildActionButton(
              onTap: _isOtpValid ? _verifyOtp : null,
              label: 'Verify & Login',
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _resendCountdown > 0
                      ? 'Resend code in ${_resendCountdown}s'
                      : 'Did not receive code?',
                  style: GoogleFonts.inter(
                    color: const Color(0xFF6B7280),
                    fontSize: 13,
                  ),
                ),
                if (_resendCountdown == 0) ...[
                  TextButton(
                    onPressed: _isPhoneOtp ? _sendOtp : _sendEmailOtp,
                    child: Text(
                      'Resend',
                      style: GoogleFonts.inter(
                        color: const Color(0xFFFF7597),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            _buildBackButton(),
          ],
        );
    }
  }

  Widget _buildGoogleButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _signInWithGoogle,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 56,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.white,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: Colors.transparent,
                ),
                padding: const EdgeInsets.all(6),
                child: Image.asset(
                  'assets/google_logo.png',
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Sign in with Google',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0B0D13),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate().fade(delay: 400.ms, duration: 600.ms);
  }

  Widget _buildGreyButton({
    required VoidCallback onTap,
    required IconData icon,
    required String label,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: const Color(0xFF1F2937).withValues(alpha: 0.6),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white70, size: 20),
              const SizedBox(width: 12),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        filled: true,
        fillColor: const Color(0xFF07080A).withValues(alpha: 0.8),
        hintText: hintText,
        hintStyle: GoogleFonts.inter(
          color: const Color(0xFF6B7280),
          fontSize: 14,
        ),
        prefixIcon: Icon(icon, color: const Color(0xFF6B7280), size: 18),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: Colors.white.withValues(alpha: 0.05),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: Color(0xFFFF7597),
            width: 1.5,
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required VoidCallback? onTap,
    required String label,
  }) {
    final isDisabled = onTap == null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: isDisabled
                ? null
                : const LinearGradient(
                    colors: [
                      Color(0xFFFF7597),
                      Color(0xFFE04B76),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
            color: isDisabled ? Colors.white.withValues(alpha: 0.08) : null,
            boxShadow: isDisabled
                ? null
                : [
                    BoxShadow(
                      color: const Color(0xFFFF7597).withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.inter(
              color: isDisabled ? Colors.white.withValues(alpha: 0.3) : Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackButton() {
    return TextButton(
      onPressed: () {
        setState(() {
          _currentView = LoginView.options;
        });
      },
      child: Text(
        'Back to Login Options',
        style: GoogleFonts.inter(
          color: const Color(0xFF6B7280),
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildFootnote(String text) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: GoogleFonts.jetBrainsMono(
        fontSize: 9,
        fontWeight: FontWeight.bold,
        color: const Color(0xFFFF7597).withValues(alpha: 0.7),
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildMatrixRow(String label, String status, bool isActive) {
    final color = isActive
        ? const Color(0xFFFF7597)
        : const Color(0xFF6B7280).withValues(alpha: 0.5);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.padRight(25),
            style: GoogleFonts.jetBrainsMono(
              fontSize: 8,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              color: color,
            ),
          ),
          Text(
            '// $status',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 8,
              color: color.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

// Custom Painter for Gravity Grid, ripples & Interactive Mode-specific Nodes
class GravityFieldPainter extends CustomPainter {
  GravityFieldPainter({
    required this.nodes,
    required this.touchPosition,
    required this.tiltOffset,
    required this.simulatedTime,
    required this.matrixIndex,
  });

  final List<SpaceNode> nodes;
  final Offset? touchPosition;
  final Offset tiltOffset;
  final double simulatedTime;
  final int matrixIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final coordinateScale =
        size.width *
        0.45; // scale factor mapping relative coordinates to pixels

    // Define colors
    const accentColor = Color(0xFFFF7597);
    const whiteColor = Color(0xFFFFFFFF);
    const greyColor = Color(0xFF6B7280);

    canvas.save();
    final activeTilt = Offset(
      math.sin(simulatedTime) * 0.03,
      math.cos(simulatedTime) * 0.03,
    );
    canvas.translate(activeTilt.dx * 12, activeTilt.dy * 12);

    // 1. Draw concentric grid rings (0.50, 0.75, 1.00)
    final gridPaint = Paint()
      ..color = greyColor.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    final ringRatios = [0.5, 0.75, 1.0];
    for (final ratio in ringRatios) {
      final radius = ratio * coordinateScale;
      canvas.drawCircle(center, radius, gridPaint);

      // Decimal labels along X-axis
      final textSpan = TextSpan(
        text: ratio.toStringAsFixed(2),
        style: GoogleFonts.jetBrainsMono(
          color: greyColor.withValues(alpha: 0.35),
          fontSize: 8,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(center.dx + radius + 4, center.dy - 10));
    }

    // 2. Draw Distorted Space Grid Lines
    final linePaint = Paint()
      ..color = accentColor.withValues(alpha: 0.05)
      ..strokeWidth = 0.5;

    const gridRowsCols = 16;
    final rowSpacing = size.height / gridRowsCols;
    final colSpacing = size.width / gridRowsCols;

    // Distort horizontal lines
    for (var r = 0; r <= gridRowsCols; r++) {
      final path = Path();
      final y = r * rowSpacing;

      for (var c = 0; c <= 40; c++) {
        final x = c * (size.width / 40);
        var point = Offset(x, y);

        // Apply grid distortion math from touch gravity well
        final touch = touchPosition;
        if (touch != null) {
          final touchPixel = Offset(
            center.dx + touch.dx * coordinateScale,
            center.dy + touch.dy * coordinateScale,
          );
          final toTouch = touchPixel - point;
          final dist = toTouch.distance;
          if (dist < 180 && dist > 1) {
            final warpForce = 45.0 * (1.0 - dist / 180);
            point += toTouch / dist * warpForce;
          }
        }

        if (c == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(path, linePaint);
    }

    // Distort vertical lines
    for (var col = 0; col <= gridRowsCols; col++) {
      final path = Path();
      final x = col * colSpacing;

      for (var r = 0; r <= 40; r++) {
        final y = r * (size.height / 40);
        var point = Offset(x, y);

        final touch = touchPosition;
        if (touch != null) {
          final touchPixel = Offset(
            center.dx + touch.dx * coordinateScale,
            center.dy + touch.dy * coordinateScale,
          );
          final toTouch = touchPixel - point;
          final dist = toTouch.distance;
          if (dist < 180 && dist > 1) {
            final warpForce = 45.0 * (1.0 - dist / 180);
            point += toTouch / dist * warpForce;
          }
        }

        if (r == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(path, linePaint);
    }

    // 3. Touch Snapping Bounds
    final touch = touchPosition;
    if (touch != null) {
      final touchPixel = Offset(
        center.dx + touch.dx * coordinateScale,
        center.dy + touch.dy * coordinateScale,
      );
      final pulseRadius =
          (DateTime.now().millisecondsSinceEpoch % 1000) / 1000.0 * 100.0;
      final touchRingPaint = Paint()
        ..color = accentColor.withValues(
          alpha: 0.25 * (1.0 - pulseRadius / 100.0),
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5;

      canvas.drawCircle(touchPixel, pulseRadius, touchRingPaint);
      canvas.drawCircle(
        touchPixel,
        40.0,
        touchRingPaint..color = accentColor.withValues(alpha: 0.1),
      );
    }

    // 4. Draw Center Pulsing Node • (You)
    final youPixel = center;
    final pulsePaint = Paint()
      ..color = whiteColor.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;

    // Pulsing circle glow
    canvas.drawCircle(youPixel, 18, pulsePaint);

    final innerPaint = Paint()
      ..color = whiteColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(youPixel, 4, innerPaint);

    final youLabelSpan = TextSpan(
      text: '• (You)',
      style: GoogleFonts.inter(
        color: whiteColor,
        fontSize: 10,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
      ),
    );
    final youLabelPainter = TextPainter(
      text: youLabelSpan,
      textDirection: TextDirection.ltr,
    )..layout();
    youLabelPainter.paint(canvas, Offset(youPixel.dx - 18, youPixel.dy - 20));

    // 5. Draw Floating Vector Nodes (Spaced out layout with mode-specific icons)
    for (final node in nodes) {
      final nodePixel = Offset(
        center.dx + node.position.dx * coordinateScale,
        center.dy + node.position.dy * coordinateScale,
      );

      // Node background connection path line
      final connPaint = Paint()
        ..color = accentColor.withValues(alpha: 0.1)
        ..strokeWidth = 0.5;
      canvas.drawLine(center, nodePixel, connPaint);

      // Dynamic Node Icon selection based on type (simultaneous orbit)
      IconData nodeIcon;
      Color iconColor;

      final nodeType = node.type ?? (nodes.indexOf(node) % 3);
      if (nodeType == 0) {
        nodeIcon = Icons.favorite;
        iconColor = const Color(0xFFFF5A5F); // Crimson Red for Hearts/Dating
      } else if (nodeType == 1) {
        nodeIcon = Icons.auto_awesome;
        iconColor = const Color(0xFFFFB03A); // Teal for Sparkles/Friends
      } else {
        nodeIcon = Icons.work;
        iconColor = const Color(0xFFFFFFFF); // White for briefcase/Pro
      }

      // Slightly larger icon fonts (20.0 size) for clear readability
      final iconSpan = TextSpan(
        text: String.fromCharCode(nodeIcon.codePoint),
        style: TextStyle(
          fontSize: 20,
          fontFamily: nodeIcon.fontFamily,
          package: nodeIcon.fontPackage,
          color: iconColor.withValues(alpha: 0.8),
          shadows: [
            Shadow(
              color: iconColor.withValues(alpha: 0.4),
              blurRadius: 8.0,
            ),
          ],
        ),
      );

      final iconPainter = TextPainter(
        text: iconSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      // Paint centered icon on nodePixel
      iconPainter.paint(
        canvas,
        nodePixel - Offset(iconPainter.width / 2, iconPainter.height / 2),
      );

      // Spaced-out Label and Compatibility score text to avoid overlaps
      final textSpan = TextSpan(
        text: 'o (${node.score.toStringAsFixed(2)})',
        style: GoogleFonts.jetBrainsMono(
          color: whiteColor.withValues(alpha: 0.55),
          fontSize: 9,
          letterSpacing: 0.5,
        ),
      );
      final nodePainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      // Dynamically position text on outer side relative to node vector path from center
      final textOffsetDir = node.position / node.position.distance;
      final textX =
          nodePixel.dx +
          (textOffsetDir.dx * 16) -
          (node.position.dx < 0 ? nodePainter.width - 4 : 0);
      final textY = nodePixel.dy + (textOffsetDir.dy * 12) - 6;

      nodePainter.paint(canvas, Offset(textX, textY));
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant GravityFieldPainter oldDelegate) {
    return true; // continuously repainting for 60fps physics tick updates
  }
}

// Optical Chromatic Border Dispersion (Real Lens Effect) CustomPainter
class ChromaticBorderPainter extends CustomPainter {
  ChromaticBorderPainter({required this.borderRadius});

  final double borderRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(borderRadius),
    );

    // Path 1 (Left offset): Hyper-muted Crimson Red (#FF5A5F, opacity 20%)
    final paintRed = Paint()
      ..color = const Color(0x33FF5A5F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.save();
    canvas.translate(-0.3, 0.0);
    canvas.drawRRect(rrect, paintRed);
    canvas.restore();

    // Path 2 (Right offset): Pure Oracle Aqua/Teal (#00ADB5, opacity 25%)
    final paintTeal = Paint()
      ..color = const Color(0x4000ADB5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.save();
    canvas.translate(0.3, 0.0);
    canvas.drawRRect(rrect, paintTeal);
    canvas.restore();

    // Path 3 (Absolute center): Mathematical White (#FFFFFF, opacity 60%)
    final paintWhite = Paint()
      ..color = const Color(0x99FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawRRect(rrect, paintWhite);
  }

  @override
  bool shouldRepaint(covariant ChromaticBorderPainter oldDelegate) => false;
}
