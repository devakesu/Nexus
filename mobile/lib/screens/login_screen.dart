// Telemetry rendering and CustomPainter math benefit from direct double representation and nested cascades.
// ignore_for_file: cascade_invocations, prefer_int_literals
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/screens/login/widgets/login_painters.dart';
import 'package:nexus/services/security_service.dart';
import 'package:nexus/theme/app_colors.dart';
import 'package:nexus/utils/encrypted_string.dart';
import 'package:nexus/utils/error_handler.dart';
import 'package:nexus/utils/network_utils.dart';
import 'package:nexus/widgets/aesthetic_loaders.dart';
import 'package:nexus/widgets/nexus_toast.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  bool _isScreenRecordingOrMirroringActive = false;
  bool _isOverlayDetected = false;
  StreamSubscription<void>? _overlaySubscription;
  Timer? _securityCheckTimer;

  // Controllers/Values for Email login
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();

  /// True when the current `otp` view is verifying a phone-as-username
  /// lookup rather than a direct email sign-in. The OTP itself is always
  /// emailed either way (the Phone auth provider is disabled - phone is
  /// only ever a lookup key, see /api/v1/auth/login-by-phone), so the
  /// backend never tells the client which email it went to; this flag just
  /// decides which backend call `_verifyOtp`/resend should make.
  bool _isPhoneLookupFlow = false;
  bool _hidePhoneLogin = false;

  int _resendCountdown = 0;
  Timer? _countdownTimer;

  // Physics & Particle Field State
  late AnimationController _physicsController;
  final List<SpaceNode> _nodes = [];
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
    unawaited(SecurityService.enterSensitiveScreen());
    _overlaySubscription = SecurityService.onOverlayDetected.listen((_) {
      if (mounted) {
        setState(() {
          _isOverlayDetected = true;
        });
      }
    });
    _securityCheckTimer = Timer.periodic(const Duration(seconds: 1), (
      timer,
    ) async {
      final active = await SecurityService.isScreenRecordingOrMirroring();
      if (mounted && active != _isScreenRecordingOrMirroringActive) {
        setState(() {
          _isScreenRecordingOrMirroringActive = active;
        });
      }
    });

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
    return code.length == AppConfig.otpLength &&
        RegExp(r'^\d+$').hasMatch(code);
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
    unawaited(_overlaySubscription?.cancel());
    _securityCheckTimer?.cancel();
    unawaited(SecurityService.exitSensitiveScreen());
    _matrixTimer?.cancel();
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

      final encryptedAccessToken = EncryptedString(accessToken);
      final encryptedIdToken = EncryptedString(idToken);

      await encryptedAccessToken.use((accToken) async {
        await encryptedIdToken.use((idTok) async {
          await Supabase.instance.client.auth.signInWithIdToken(
            provider: OAuthProvider.google,
            idToken: idTok,
            accessToken: accToken,
          );
        });
      });
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
      NexusToast.show(
        context,
        'Please wait $_resendCountdown seconds before requesting another code.',
        type: NexusToastType.error,
      );
      return;
    }

    final email = _emailController.text.trim();

    if (email.isEmpty) {
      NexusToast.show(
        context,
        'Please enter your email address.',
        type: NexusToastType.error,
      );
      return;
    }

    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    if (!emailRegex.hasMatch(email)) {
      NexusToast.show(
        context,
        'Please enter a valid email address.',
        type: NexusToastType.error,
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final config = AppConfig.current;
      final redirectUrl = 'https://${config.appDomain}/login-callback';
      await Supabase.instance.client.auth.signInWithOtp(
        email: email,
        emailRedirectTo: redirectUrl,
      );
      if (mounted) {
        setState(() {
          _isPhoneLookupFlow = false;
          _currentView = LoginView.otp;
          _resendCountdown = 60;
          _startCountdown();
        });
        NexusToast.show(
          context,
          'OTP sent successfully!',
          type: NexusToastType.success,
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

  Future<void> _sendLoginByPhoneOtp() async {
    if (_resendCountdown > 0) {
      NexusToast.show(
        context,
        'Please wait $_resendCountdown seconds before requesting another code.',
        type: NexusToastType.error,
      );
      return;
    }

    final phone = _phoneController.text.trim();

    if (phone.isEmpty) {
      NexusToast.show(
        context,
        'Please enter your phone number.',
        type: NexusToastType.error,
      );
      return;
    }

    final phoneRegex = RegExp(r'^\+[1-9]\d{7,14}$');
    if (!phoneRegex.hasMatch(phone)) {
      NexusToast.show(
        context,
        'Please enter a valid phone number starting with + (e.g. +1234567890).',
        type: NexusToastType.error,
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final dio = createDio();
      final config = AppConfig.current;
      final response = await dio.post<Map<String, dynamic>>(
        '${config.backendUrl}/api/v1/auth/login-by-phone/request',
        data: {'phone': phone},
        options: Options(
          headers: {'X-App-Variant': config.variantString},
        ),
      );
      final exists = response.data?['exists'] as bool? ?? false;
      if (!exists) {
        if (mounted) {
          setState(() {
            _currentView = LoginView.options;
            _hidePhoneLogin = true;
          });
          await showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: const Color(0xFF161B26),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFF374151)),
              ),
              title: Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    color: AppColors.pulsarPink,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Registration Required',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              content: Text(
                'This phone number is not registered. Please sign in or register with Google or Email first.',
                style: GoogleFonts.inter(
                  color: const Color(0xFF9CA3AF),
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'OK',
                    style: GoogleFonts.inter(
                      color: AppColors.pulsarPink,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        return;
      }
      if (mounted) {
        setState(() {
          _isPhoneLookupFlow = true;
          _currentView = LoginView.otp;
          _resendCountdown = 60;
          _startCountdown();
        });
        NexusToast.show(
          context,
          'If that phone number is registered, a code was emailed to the '
          'account on file.',
          type: NexusToastType.success,
        );
      }
    } on Object catch (e, stackTrace) {
      ErrorHandler.handleError(
        e,
        stackTrace: stackTrace,
        customMessage: 'Failed to send code: $e',
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
    final target = _emailController.text.trim();
    final encryptedCode = EncryptedString(_otpController.text.trim());

    final isLengthValid = encryptedCode.use(
      (code) => code.length == AppConfig.otpLength,
    );
    final isFormatValid = encryptedCode.use(
      (code) => RegExp(r'^\d+$').hasMatch(code),
    );

    if (target.isEmpty || _otpController.text.trim().isEmpty) {
      NexusToast.show(
        context,
        'Please enter the OTP verification code.',
        type: NexusToastType.error,
      );
      return;
    }

    if (!isLengthValid || !isFormatValid) {
      NexusToast.show(
        context,
        'Please enter a valid ${AppConfig.otpLength}-digit OTP code (digits only).',
        type: NexusToastType.error,
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await encryptedCode.use(
        (code) => Supabase.instance.client.auth.verifyOTP(
          email: target,
          token: code,
          type: OtpType.email,
        ),
      );
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

  /// Verifies a phone-as-username login code. The backend resolves the
  /// phone to an account and checks the code against that account's email
  /// OTP itself (we never learn the email) - on success it hands back a
  /// real Supabase session, which this device adopts via setSession rather
  /// than ever knowing the account's email or performing its own OTP call.
  Future<void> _verifyLoginByPhoneOtp() async {
    final phone = _phoneController.text.trim();
    final encryptedCode = EncryptedString(_otpController.text.trim());

    final isCodeEmpty = encryptedCode.use((code) => code.isEmpty);

    if (phone.isEmpty || isCodeEmpty) {
      NexusToast.show(
        context,
        'Please enter the OTP verification code.',
        type: NexusToastType.error,
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final dio = createDio();
      final config = AppConfig.current;
      final response = await encryptedCode.use(
        (code) => dio.post<Map<String, dynamic>>(
          '${config.backendUrl}/api/v1/auth/login-by-phone/verify',
          data: {'phone': phone, 'code': code},
          options: Options(
            headers: {'X-App-Variant': config.variantString},
          ),
        ),
      );

      final refreshToken = response.data?['refresh_token'] as String?;
      if (refreshToken == null || refreshToken.isEmpty) {
        throw Exception('Malformed session response from server.');
      }
      await Supabase.instance.client.auth.setSession(refreshToken);
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
    if (_isScreenRecordingOrMirroringActive) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Container(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.videocam_off, color: Colors.red, size: 80),
                const SizedBox(height: 24),
                Text(
                  'Screen Recording / Mirroring Detected',
                  style: GoogleFonts.inter(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'To protect your sensitive financial and academic data, this application cannot run while screen recording or mirroring is active. Please turn off recording/mirroring to proceed.',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    color: Colors.grey[400],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_isOverlayDetected) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Container(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.security, color: Colors.amber, size: 80),
                const SizedBox(height: 24),
                Text(
                  'Screen Overlay Detected',
                  style: GoogleFonts.inter(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Another application is drawing an overlay on top of this screen. This is blocked to prevent credential theft. Please close any overlay applications to continue.',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    color: Colors.grey[400],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _isOverlayDetected = false;
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                  child: Text(
                    'I have closed it',
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

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
                              color: AppColors
                                  .pulsarPink, // Pulsar Teal / Oracle Aqua accent
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
            if (!_hidePhoneLogin) ...[
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
            ],
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
            const SizedBox(height: 8),
            Text(
              'Enter your email address below to receive a login link or code.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: const Color(0xFF6B7280),
                height: 1.4,
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
              label: 'Login with Email Link/Code',
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
              'Only registered users who have linked a phone number can use this. If you are new, please sign in with Google or Email first.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: const Color(0xFF6B7280),
                height: 1.4,
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
              onTap: _sendLoginByPhoneOtp,
              label: 'Get Link/Code',
            ),
            const SizedBox(height: 12),
            _buildBackButton(),
          ],
        );
      case LoginView.otp:
        final targetText = _isPhoneLookupFlow
            ? 'the email linked to ${_phoneController.text}'
            : _emailController.text;
        final instructionText = _isPhoneLookupFlow
            ? 'Either click the link or enter the ${AppConfig.otpLength}-digit code sent to $targetText'
            : 'Either click the link in the email sent to\n$targetText\nor enter the ${AppConfig.otpLength}-digit code below:';
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isPhoneLookupFlow ? 'Verify OTP' : 'Check Your Email',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              instructionText,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: const Color(0xFF6B7280),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _otpController,
              hintText: '${AppConfig.otpLength}-digit code',
              icon: Icons.lock_clock_outlined,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(AppConfig.otpLength),
              ],
            ),
            const SizedBox(height: 16),
            _buildActionButton(
              onTap: _isOtpValid
                  ? (_isPhoneLookupFlow ? _verifyLoginByPhoneOtp : _verifyOtp)
                  : null,
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
                    onPressed: _isPhoneLookupFlow
                        ? _sendLoginByPhoneOtp
                        : _sendEmailOtp,
                    child: Text(
                      'Resend',
                      style: GoogleFonts.inter(
                        color: AppColors.pulsarPink,
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
            color: AppColors.pulsarPink,
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
                      AppColors.pulsarPink,
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
                      color: AppColors.pulsarPink.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.inter(
              color: isDisabled
                  ? Colors.white.withValues(alpha: 0.3)
                  : Colors.white,
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
          _countdownTimer?.cancel();
          _resendCountdown =
              0; // Reset countdown when returning to login options
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
        color: AppColors.pulsarPink.withValues(alpha: 0.7),
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildMatrixRow(String label, String status, bool isActive) {
    final color = isActive
        ? AppColors.pulsarPink
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
