import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:nexus/config/app_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({required this.appName, super.key});

  final String appName;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;

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
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFD32F2F),
            content: Text(
              'Authentication failed: $e',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = AppConfig.current;

    return Scaffold(
      backgroundColor: const Color(0xFF090D0F),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              // App Logo with subtle tech-teal border/glow
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0x1F0D9488), width: 1.5),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x110D9488),
                      blurRadius: 30,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Image.asset(
                    config.logoAssetPath,
                    fit: BoxFit.cover,
                  ),
                ),
              )
                  .animate()
                  .fade(duration: 600.ms)
                  .scale(
                    begin: const Offset(0.8, 0.8),
                    end: const Offset(1, 1),
                    duration: 600.ms,
                    curve: Curves.easeOut,
                  ),
              const SizedBox(height: 24),
              // App Title
              Text(
                widget.appName,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                  color: Colors.white,
                ),
              ).animate().fade(delay: 200.ms, duration: 600.ms),
              const SizedBox(height: 8),
              const Text(
                'Access requires authentication.',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0x80FFFFFF),
                  letterSpacing: 0.5,
                ),
              ).animate().fade(delay: 300.ms, duration: 600.ms),
              const Spacer(),
              // Google Login Button (Sleek Glassmorphic style with Teal outline)
              if (_isLoading)
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Color(0xFF0D9488),
                  ),
                )
              else
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _signInWithGoogle,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      height: 56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0x2A0D9488),
                        ),
                        color: const Color(0xFF111619),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.asset(
                            'assets/google_logo.png',
                            height: 22,
                          ),
                          const SizedBox(width: 14),
                          const Text(
                            'Sign in with Google',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                      .animate(
                        onPlay: (controller) =>
                            controller.repeat(reverse: true),
                      )
                      .shimmer(
                        delay: 2000.ms,
                        duration: 1500.ms,
                        color: const Color(0x0A0D9488),
                      ),
                ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
}
