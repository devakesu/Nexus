import 'dart:async';
import 'package:dio/dio.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/material.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/screens/home_screen.dart';
import 'package:nexus/screens/login_screen.dart';
import 'package:nexus/screens/onboarding_screen.dart';
import 'package:nexus/screens/splash_screen.dart';
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
  String? _lastBootstrappedSessionId;
  bool _hasProfile = false;
  String _termsVersion = '1.0';

  @override
  void initState() {
    super.initState();
    // Allow splash screen to show for 2.3 seconds
    Timer(const Duration(milliseconds: 2300), () {
      if (mounted) {
        setState(() {
          _showSplash = false;
        });
        unawaited(_checkBootstrap());
      }
    });

    // Listen to Supabase auth state changes
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      data,
    ) {
      if (mounted) {
        setState(() {});
        if (!_showSplash) {
          unawaited(_checkBootstrap());
        }
      }
    });
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
      _lastBootstrappedSessionId = null;
      _hasProfile = false;
      return;
    }

    // If we already bootstrapped this session, do not repeat it
    if (_lastBootstrappedSessionId == session.accessToken) {
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
      final appCheckToken = await FirebaseAppCheck.instance.getLimitedUseToken();

      final response = await dio.post<Map<String, dynamic>>(
        '${config.backendUrl}/api/v1/auth/bootstrap',
        options: Options(
          headers: {
            'Authorization': 'Bearer ${session.accessToken}',
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

        setState(() {
          _hasProfile = profileResponse != null;
          _lastBootstrappedSessionId = session.accessToken;
          _isBootstrapping = false;
        });
      } else {
        // Server rejected registration (e.g. 403 Forbidden - non-college email)
        final errorMsg = response.data?['detail'] ?? 'Server authentication failed.';
        throw Exception(errorMsg);
      }
    } on Object catch (e) {
      // Sign out from Supabase as bootstrap failed
      await Supabase.instance.client.auth.signOut();
      if (mounted) {
        setState(() {
          _isBootstrapping = false;
          _lastBootstrappedSessionId = null;
          _hasProfile = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFD32F2F),
            duration: const Duration(seconds: 5),
            content: Text(
              'Access denied: ${e.toString().replaceAll('Exception:', '').trim()}',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showSplash) {
      return SplashScreen(appName: widget.appName);
    }

    final session = Supabase.instance.client.auth.currentSession;

    if (_isBootstrapping) {
      return const Scaffold(
        backgroundColor: Color(0xFF090D0F),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0D9488)),
              ),
              SizedBox(height: 24),
              Text(
                'Securing Connection...',
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
      );
    }

    if (session != null && _lastBootstrappedSessionId == session.accessToken) {
      if (!_hasProfile) {
        return OnboardingScreen(
          termsVersion: _termsVersion,
          onComplete: () {
            setState(() {
              _hasProfile = true;
            });
          },
        );
      }
      return MyHomePage(title: widget.appName);
    }

    return LoginScreen(appName: widget.appName);
  }
}
