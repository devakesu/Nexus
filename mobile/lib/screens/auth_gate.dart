import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/screens/home/home_screen.dart';
import 'package:nexus/screens/login_screen.dart';
import 'package:nexus/screens/onboarding_screen.dart';
import 'package:nexus/screens/splash_screen.dart';
import 'package:nexus/services/notification_service.dart';
import 'package:nexus/utils/error_handler.dart';
import 'package:nexus/utils/network_utils.dart';
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

  /// Null until the server tells us which terms version this account is
  /// bound to. Deliberately has no fallback default - onboarding must not
  /// proceed against a guessed version if bootstrap never returned one.
  String? _termsVersion;

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
        if (data.event == AuthChangeEvent.signedOut) {
          unawaited(NotificationService.unregisterToken());
          unawaited(NotificationService.dispose());
        }
        if (mounted) {
          setState(() {});
          if (!_showSplash) {
            unawaited(_checkBootstrap());
          }
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        final errorStr = error.toString();
        if ((error is AuthException &&
                error.code == 'refresh_token_not_found') ||
            errorStr.contains('refresh_token_not_found') ||
            errorStr.contains('Invalid Refresh Token')) {
          ErrorHandler.handleError(
            error,
            stackTrace: stackTrace,
            level: ErrorLevel.info,
            customMessage:
                '[AuthGate] Refresh token invalid or not found. Force signing out.',
            showUi: false,
          );
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
      _authCheckCompleted = true;
      _maybeTransition();
      setState(() {});
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
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      _lastBootstrappedUserId = null;
      _hasProfile = false;
      return;
    }

    // If we already bootstrapped this user, do not repeat it
    if (_lastBootstrappedUserId == session.user.id) {
      return;
    }

    if (_isBootstrapping) {
      return;
    }

    // Set the guard synchronously, before the first `await` below - this
    // closes the race window where a second call (racing in via the
    // auth-state-change listener) could pass both checks above while this
    // call is still suspended on refreshSession() and start a concurrent
    // bootstrap.
    setState(() {
      _isBootstrapping = true;
    });

    var activeSession = session;
    if (activeSession.isExpired) {
      try {
        ErrorHandler.handleError(
          null,
          level: ErrorLevel.info,
          customMessage: '[AuthGate] Session expired. Refreshing token...',
          showUi: false,
        );
        final refreshResponse = await Supabase.instance.client.auth
            .refreshSession();
        final refreshed = refreshResponse.session;
        if (refreshed == null) {
          ErrorHandler.handleError(
            null,
            level: ErrorLevel.info,
            customMessage:
                '[AuthGate] Session refresh returned null session. Signing out.',
            showUi: false,
          );
          await Supabase.instance.client.auth.signOut();
          if (mounted) {
            setState(() {
              _isBootstrapping = false;
            });
          }
          return;
        }
        activeSession = refreshed;
      } on Object catch (e, stackTrace) {
        await Supabase.instance.client.auth.signOut();
        // Always report to Sentry, even if this widget is no longer
        // mounted - only the user-facing dialog depends on that.
        ErrorHandler.handleError(
          e,
          stackTrace: stackTrace,
          customMessage:
              'Session refresh failed: ${ErrorHandler.getFriendlyMessage(e)}',
          showUi: mounted,
        );
        if (mounted) {
          setState(() {
            _isBootstrapping = false;
            _lastBootstrappedUserId = null;
            _hasProfile = false;
          });
        }
        return;
      }
    }

    try {
      final config = AppConfig.current;
      final dio = createDio();

      final response = await dio.post<Map<String, dynamic>>(
        '${config.backendUrl}/api/v1/auth/bootstrap',
        options: Options(
          headers: {},
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
          unawaited(NotificationService.initialize());
        }
      } else {
        // Server rejected registration (e.g. 403 Forbidden - non-college email)
        final errorMsg =
            response.data?['detail'] ?? 'Server authentication failed.';
        throw Exception(errorMsg);
      }
    } on DioException catch (e, stackTrace) {
      // Network-level failures (no connectivity, timeout, DNS, 5xx) are
      // retry-able and not the user's fault - signing them out here would
      // force a full re-login just because Wi-Fi hiccupped during app
      // launch. An actual server rejection (e.g. non-college email) comes
      // back as a normal <500 response and is handled below via the
      // manually-thrown Exception instead, which does still sign out.
      if (mounted) {
        setState(() {
          _isBootstrapping = false;
        });
      }
      ErrorHandler.handleError(
        e,
        stackTrace: stackTrace,
        level: ErrorLevel.warning,
        customMessage:
            'Bootstrap connection error: ${ErrorHandler.getFriendlyMessage(e)}',
        showUi: mounted,
      );
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
          customMessage: 'Access denied: ${ErrorHandler.getFriendlyMessage(e)}',
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
            _animationCompleted = true;
            _maybeTransition();
            setState(() {});
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
      if (session != null && _lastBootstrappedUserId == session.user.id) {
        final termsVersion = _termsVersion;
        if (!_hasProfile && termsVersion != null) {
          currentWidget = OnboardingScreen(
            key: const ValueKey('onboarding'),
            termsVersion: termsVersion,
            onComplete: () {
              setState(() {
                _hasProfile = true;
              });
            },
          );
        } else if (!_hasProfile) {
          // Bootstrap succeeded but didn't return a terms version - fail
          // safe rather than onboard the user against a guessed version.
          currentWidget = const Scaffold(
            key: ValueKey('terms-version-missing'),
            backgroundColor: Color(0xFF0B0D13),
            body: Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
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
