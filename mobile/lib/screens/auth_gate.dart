import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/screens/home/home_screen.dart';
import 'package:nexus/screens/login_screen.dart';
import 'package:nexus/screens/onboarding_screen.dart';
import 'package:nexus/screens/reactivate_account_page.dart';
import 'package:nexus/screens/splash_screen.dart';
import 'package:nexus/screens/terms_consent_screen.dart';
import 'package:nexus/services/notification_service.dart';
import 'package:nexus/services/signal/signal_key_service.dart';
import 'package:nexus/theme/app_colors.dart';
import 'package:nexus/utils/discovery_hub_cache.dart';
import 'package:nexus/utils/error_handler.dart';
import 'package:nexus/utils/network_utils.dart';
import 'package:nexus/utils/safety_consent_cache.dart';
import 'package:nexus/utils/secure_profile_cache.dart';
import 'package:nexus/utils/special_category_consent_cache.dart';
import 'package:nexus/widgets/aesthetic_loaders.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({required this.appName, super.key});

  final String appName;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  StreamSubscription<AuthState>? _authSubscription;
  bool _showSplash = true;
  bool _isBootstrapping = false;
  bool _isSilentBootstrapping = false;
  String? _lastBootstrappedUserId;
  bool _hasProfile = false;

  /// Verified-mobile state from the bootstrap response (public.users.mobile/
  /// mobile_verified_at), threaded into OnboardingScreen so it never reads
  /// Supabase Auth's user.phone (the Phone provider is disabled - phone
  /// verification is now backend-owned, see app/core/account_phone_otp.py).
  String? _verifiedMobile;
  DateTime? _mobileVerifiedAt;

  /// Set from the bootstrap response when this account has a pending
  /// self-serve deletion request - see app/db/account_deletion.py. When
  /// true, build() renders ReactivateAccountPage instead of the normal app,
  /// regardless of onboarding/profile state.
  bool _deletionPending = false;
  DateTime? _scheduledPurgeAt;

  /// Itemized consent state - see 20260802000000_terms_consent_expansion.sql
  /// and TermsConsentPage. current_terms_version is always populated by the
  /// backend (unlike the old accepted_terms_version, which is null for a
  /// brand-new user) - that's what makes it possible to gate on this at all
  /// without the previous dead-end fail-safe screen.
  String _currentTermsVersion = '1';
  bool _mandatoryConsentRequired = false;
  bool _hasEverAcceptedGeneralTerms = false;
  bool _safetyDataPreviouslyAccepted = false;

  /// True once this session has ever rendered MyHomePage. Once true, a
  /// later mandatory-consent-required detection (via the app-resumed
  /// lifecycle hook) is shown as a modal dialog over the current screen
  /// instead of a jarring full-page swap - see _handleResumed. Before this
  /// is true (cold start / just-finished-onboarding), build() shows the
  /// full-page TermsConsentPage branch instead.
  bool _hasReachedHome = false;

  bool _animationCompleted = false;
  bool _authCheckCompleted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Start initial authentication check in parallel with splash animation
    unawaited(_performInitialAuthCheck());

    // Listen to Supabase auth state changes
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      (data) {
        if (data.event == AuthChangeEvent.signedOut) {
          unawaited(NotificationService.unregisterToken());
          unawaited(NotificationService.dispose());
          // Central sign-out hook so no cached profile/discovery-hub
          // snapshot from this account can leak into a subsequent login on
          // the same device.
          unawaited(SecureProfileCache.clear());
          unawaited(DiscoveryHubCache.clearAll());
          SafetyConsentCache.clear();
          SpecialCategoryConsentCache.clear();
          _hasReachedHome = false;
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
            showUi: false,
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
    WidgetsBinding.instance.removeObserver(this);
    if (_authSubscription != null) {
      unawaited(_authSubscription!.cancel());
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_handleResumed());
    }
  }

  /// Re-bootstraps on every foreground resume, not just cold start/sign-in -
  /// the only real trigger point for catching a server-side terms-version
  /// bump while the app is already open (Supabase's own tokenRefreshed
  /// events for an already-bootstrapped session are a no-op in
  /// _checkBootstrap's short-circuit guard, so without this hook a version
  /// bump would only ever be noticed on the next full app relaunch). If the
  /// user was already settled on the home screen, show the result as a
  /// modal dialog instead of swapping the whole screen away.
  Future<void> _handleResumed() async {
    final wasSettled =
        _hasReachedHome && _hasProfile && !_deletionPending && !_mandatoryConsentRequired;
    _lastBootstrappedUserId = null;
    await _checkBootstrap(silent: wasSettled);
    if (!mounted || !wasSettled) return;
    if (_mandatoryConsentRequired && _hasProfile && !_deletionPending) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => Dialog(
          backgroundColor: AppColors.canvas,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 640),
            child: TermsConsentPage(
              currentTermsVersion: _currentTermsVersion,
              isVersionBump: true,
              initialSafetyDataAccepted: _safetyDataPreviouslyAccepted,
              onConsentRecorded: () async {
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                await _handleConsentRecorded();
              },
            ),
          ),
        ),
      );
    }
  }

  Future<void> _checkBootstrap({bool silent = false}) async {
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

    if (_isBootstrapping || _isSilentBootstrapping) {
      return;
    }

    // Set the guard synchronously, before the first `await` below - this
    // closes the race window where a second call (racing in via the
    // auth-state-change listener) could pass both checks above while this
    // call is still suspended on refreshSession() and start a concurrent
    // bootstrap.
    if (silent) {
      _isSilentBootstrapping = true;
    } else {
      setState(() {
        _isBootstrapping = true;
      });
    }

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
              _isSilentBootstrapping = false;
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
            _isSilentBootstrapping = false;
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

      final bootstrapFuture = dio.post<Map<String, dynamic>>(
        '${config.backendUrl}/api/v1/auth/bootstrap',
        options: Options(
          headers: {},
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      // Independent of bootstrap's outcome - bootstrap only upserts
      // `public.users`, it never creates/touches `profiles` (confirmed
      // against the backend), so there's no read-after-write race to
      // protect by sequencing this after bootstrap. Start it immediately.
      final profileFuture = Supabase.instance.client
          .from('profiles')
          .select()
          .maybeSingle();

      final response = await bootstrapFuture;
      final profileResponse = await profileFuture;

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = response.data;
        _verifiedMobile = data?['mobile'] as String?;
        final mobileVerifiedAtRaw = data?['mobile_verified_at'] as String?;
        _mobileVerifiedAt = mobileVerifiedAtRaw != null
            ? DateTime.tryParse(mobileVerifiedAtRaw)
            : null;
        _deletionPending = data?['deletion_pending'] as bool? ?? false;
        final scheduledPurgeAtRaw = data?['scheduled_purge_at'] as String?;
        _scheduledPurgeAt = scheduledPurgeAtRaw != null
            ? DateTime.tryParse(scheduledPurgeAtRaw)
            : null;
        _currentTermsVersion = data?['current_terms_version'] as String? ?? '1';
        _mandatoryConsentRequired =
            data?['mandatory_consent_required'] as bool? ?? false;
        _hasEverAcceptedGeneralTerms = data?['accepted_terms_version'] != null;
        _safetyDataPreviouslyAccepted =
            data?['safety_data_consent_version'] != null;
        SafetyConsentCache.isGranted =
            data?['safety_data_consent_granted'] as bool? ?? false;
        SafetyConsentCache.currentTermsVersion = _currentTermsVersion;
        SpecialCategoryConsentCache.isGranted =
            data?['special_category_consent_granted'] as bool? ?? false;
        SpecialCategoryConsentCache.currentTermsVersion = _currentTermsVersion;

        final hasProfile = profileResponse != null;
        if (hasProfile && !_deletionPending && !_mandatoryConsentRequired) {
          _hasReachedHome = true;
        }

        if (mounted) {
          setState(() {
            _hasProfile = hasProfile;
            _lastBootstrappedUserId = activeSession.user.id;
            _isBootstrapping = false;
            _isSilentBootstrapping = false;
          });
          unawaited(NotificationService.initialize());
          // Publish this device's Signal key bundle right after login so a
          // brand-new match never has to wait on either side opening a chat
          // screen first (see SignalKeyService.ensureBootstrappedInBackground
          // doc comment for the retry-safe fallback chain).
          if (hasProfile) {
            unawaited(SignalKeyService.instance.ensureBootstrappedInBackground());
          }
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
          _isSilentBootstrapping = false;
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
          _isSilentBootstrapping = false;
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

  /// Called by ReactivateAccountPage once /account/deletion/cancel has
  /// succeeded. Forces the next _checkBootstrap() call to actually re-fetch
  /// (rather than short-circuit on the already-bootstrapped-this-user
  /// guard) so deletion_pending flips to false and build() falls through to
  /// the normal onboarding/home routing.
  Future<void> _handleReactivated() async {
    _lastBootstrappedUserId = null;
    await _checkBootstrap();
  }

  /// Called by TermsConsentPage once /api/v1/auth/accept-terms has
  /// succeeded - same reset-and-refetch trick as _handleReactivated, so
  /// mandatory_consent_required flips to false and build() falls through
  /// past the consent branch.
  Future<void> _handleConsentRecorded() async {
    _lastBootstrappedUserId = null;
    await _checkBootstrap();
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
        if (_deletionPending) {
          currentWidget = ReactivateAccountPage(
            key: const ValueKey('reactivate-account'),
            scheduledPurgeAt: _scheduledPurgeAt,
            onReactivated: _handleReactivated,
          );
        } else if (!_hasProfile) {
          currentWidget = OnboardingScreen(
            key: const ValueKey('onboarding'),
            verifiedMobile: _verifiedMobile,
            mobileVerifiedAt: _mobileVerifiedAt,
            onComplete: () {
              setState(() {
                _hasProfile = true;
              });
              unawaited(SignalKeyService.instance.ensureBootstrappedInBackground());
            },
          );
        } else if (_mandatoryConsentRequired && !_hasReachedHome) {
          // Only shown full-page before this session has ever reached home
          // (first-time-post-onboarding, or a version bump caught at cold
          // start/sign-in) - a version bump caught later, while already on
          // the home screen, is shown as a modal instead (_handleResumed).
          currentWidget = Scaffold(
            key: const ValueKey('terms-consent'),
            backgroundColor: AppColors.canvas,
            body: SafeArea(
              child: TermsConsentPage(
                currentTermsVersion: _currentTermsVersion,
                isVersionBump: _hasEverAcceptedGeneralTerms,
                initialSafetyDataAccepted: _safetyDataPreviouslyAccepted,
                onConsentRecorded: _handleConsentRecorded,
              ),
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
