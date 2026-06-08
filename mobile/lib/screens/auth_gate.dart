import 'dart:async';
import 'package:dio/dio.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/material.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/screens/home/home_screen.dart';
import 'package:nexus/screens/login_screen.dart';
import 'package:nexus/screens/onboarding_screen.dart';
import 'package:nexus/screens/splash_screen.dart';
import 'package:nexus/utils/error_handler.dart';
import 'package:nexus/widgets/aesthetic_loaders.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({required this.appName, super.key});

  final String appName;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<AuthState>? _authSubscription;
  bool _showSplash = true;
  bool _isBootstrapping = false;
  String? _lastBootstrappedUserId;
  bool _hasProfile = false;
  String _termsVersion = '1';

  bool _animationCompleted = false;
  bool _authCheckCompleted = false;

  @override
  void initState() {
    super.initState();

    // Start initial authentication check in parallel with splash animation
    unawaited(_performInitialAuthCheck());

    // Listen to Supabase auth state changes
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      (data) {
        if (mounted) {
          setState(() {});
          if (!_showSplash) {
            unawaited(_checkBootstrap());
          }
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        final errorStr = error.toString();
        if ((error is AuthException && error.code == 'refresh_token_not_found') ||
            errorStr.contains('refresh_token_not_found') ||
            errorStr.contains('Invalid Refresh Token')) {
          debugPrint('[AuthGate] Refresh token invalid or not found. Force signing out.');
          unawaited(Supabase.instance.client.auth.signOut());
        } else {
          ErrorHandler.handleError(
            error,
            stackTrace: stackTrace,
            level: ErrorLevel.warning,
            customMessage: 'Authentication stream error: $error',
          );
        }
      },
    );
  }

  Future<void> _performInitialAuthCheck() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      await _checkBootstrap();
    }
    if (mounted) {
      setState(() {
        _authCheckCompleted = true;
        _maybeTransition();
      });
    }
  }

  void _maybeTransition() {
    if (_animationCompleted && _authCheckCompleted) {
      _showSplash = false;
    }
  }

  @override
  void dispose() {
    if (_authSubscription != null) {
      unawaited(_authSubscription!.cancel());
    }
    super.dispose();
  }

  Future<void> _checkBootstrap() async {
    var session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      _lastBootstrappedUserId = null;
      _hasProfile = false;
      return;
    }

    if (session.isExpired) {
      try {
        debugPrint('[AuthGate] Session expired. Refreshing token...');
        final refreshResponse = await Supabase.instance.client.auth.refreshSession();
        session = refreshResponse.session;
        if (session == null) {
          debugPrint('[AuthGate] Session refresh returned null session. Signing out.');
          await Supabase.instance.client.auth.signOut();
          return;
        }
      } on Object catch (e, stackTrace) {
        debugPrint('[AuthGate] Failed to refresh session: $e');
        await Supabase.instance.client.auth.signOut();
        if (mounted) {
          setState(() {
            _isBootstrapping = false;
            _lastBootstrappedUserId = null;
            _hasProfile = false;
          });
          ErrorHandler.handleError(
            e,
            stackTrace: stackTrace,
            customMessage: 'Session refresh failed: ${ErrorHandler.getFriendlyMessage(e)}',
          );
        }
        return;
      }
    }
    final activeSession = session;

    // If we already bootstrapped this user, do not repeat it
    if (_lastBootstrappedUserId == activeSession.user.id) {
      return;
    }

    if (_isBootstrapping) {
      return;
    }

    setState(() {
      _isBootstrapping = true;
    });

    try {
      final config = AppConfig.current;
      final dio = Dio();

      // Retrieve limited use App Check token for sensitive bootstrap endpoint
      final appCheckToken = await FirebaseAppCheck.instance
          .getLimitedUseToken();

      final response = await dio.post<Map<String, dynamic>>(
        '${config.backendUrl}/api/v1/auth/bootstrap',
        options: Options(
          headers: {
            'Authorization': 'Bearer ${activeSession.accessToken}',
            'X-Firebase-AppCheck': appCheckToken,
          },
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = response.data;
        final acceptedTerms = data?['accepted_terms_version'] as String?;
        if (acceptedTerms != null) {
          _termsVersion = acceptedTerms;
        }

        // Query Supabase directly to check if a profiles row exists
        final profileResponse = await Supabase.instance.client
            .from('profiles')
            .select()
            .maybeSingle();

        if (mounted) {
          setState(() {
            _hasProfile = profileResponse != null;
            _lastBootstrappedUserId = activeSession.user.id;
            _isBootstrapping = false;
          });
        }
      } else {
        // Server rejected registration (e.g. 403 Forbidden - non-college email)
        final errorMsg =
            response.data?['detail'] ?? 'Server authentication failed.';
        throw Exception(errorMsg);
      }
    } on Object catch (e, stackTrace) {
      // Sign out from Supabase as bootstrap failed
      await Supabase.instance.client.auth.signOut();
      if (mounted) {
        setState(() {
          _isBootstrapping = false;
          _lastBootstrappedUserId = null;
          _hasProfile = false;
        });
        ErrorHandler.handleError(
          e,
          stackTrace: stackTrace,
          customMessage:
              'Access denied: ${ErrorHandler.getFriendlyMessage(e)}',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget currentWidget;

    if (_showSplash) {
      currentWidget = SplashScreen(
        key: const ValueKey('splash'),
        appName: widget.appName,
        onAnimationComplete: () {
          if (mounted) {
            setState(() {
              _animationCompleted = true;
              _maybeTransition();
            });
          }
        },
      );
    } else if (_isBootstrapping) {
      currentWidget = const Scaffold(
        key: ValueKey('bootstrapping'),
        backgroundColor: Color(0xFF0B0D13),
        body: Stack(
          children: [
            IdentityScanLoader(),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(height: 160),
                  Text(
                    'Verifying your Identity...',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    } else {
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null &&
          _lastBootstrappedUserId == session.user.id) {
        if (!_hasProfile) {
          currentWidget = OnboardingScreen(
            key: const ValueKey('onboarding'),
            termsVersion: _termsVersion,
            onComplete: () {
              setState(() {
                _hasProfile = true;
              });
            },
          );
        } else {
          currentWidget = MyHomePage(
            key: const ValueKey('home'),
            title: widget.appName,
          );
        }
      } else {
        currentWidget = LoginScreen(
          key: const ValueKey('login'),
          appName: widget.appName,
        );
      }
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 650),
      switchInCurve: Curves.easeInOut,
      switchOutCurve: Curves.easeInOut,
      child: currentWidget,
    );
  }
}
