import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/utils/network_utils.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MyHomePage extends StatelessWidget {
  const MyHomePage({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final config = AppConfig.current;

    return Scaffold(
      backgroundColor: const Color(0xFF090D0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111619),
        surfaceTintColor: Colors.transparent,
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (user?.email != null) ...[
              Text(
                'Signed in as',
                style: const TextStyle(
                  color: Color(0x66FFFFFF),
                  fontSize: 12,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                user!.email!,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 28),
            ],

            // ── Export Code card — only for flavor variants (MEC etc.) ─────
            if (config.isFlavorVariant) ...[
              const _ExportCodeCard(),
              const SizedBox(height: 20),
            ],

            // Sign-out button
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A2025),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: Color(0x1AFFFFFF)),
                ),
              ),
              onPressed: () async {
                await Supabase.instance.client.auth.signOut();
              },
              child: const Text(
                'Sign Out',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Export Code Card ─────────────────────────────────────────────────────────

class _ExportCodeCard extends StatefulWidget {
  const _ExportCodeCard();

  @override
  State<_ExportCodeCard> createState() => _ExportCodeCardState();
}

class _ExportCodeCardState extends State<_ExportCodeCard> {
  static const _teal = Color(0xFF0D9488);
  static const _ttlSeconds = 15 * 60; // 15 minutes

  bool _isLoading = false;
  String? _code;
  int _secondsRemaining = 0;
  Timer? _countdown;

  @override
  void dispose() {
    _countdown?.cancel();
    super.dispose();
  }

  String get _formattedTime {
    final m = (_secondsRemaining ~/ 60).toString().padLeft(2, '0');
    final s = (_secondsRemaining % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  bool get _hasActiveCode => _code != null && _secondsRemaining > 0;

  void _startCountdown() {
    _countdown?.cancel();
    _secondsRemaining = _ttlSeconds;
    _countdown = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _secondsRemaining--);
      if (_secondsRemaining <= 0) {
        t.cancel();
        setState(() => _code = null);
      }
    });
  }

  Future<void> _generateCode() async {
    setState(() => _isLoading = true);

    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) throw Exception('Session expired.');

      final appCheckToken = await FirebaseAppCheck.instance.getToken();
      final config = AppConfig.current;
      final dio = createDio();

      final response = await dio.post<Map<String, dynamic>>(
        '${config.backendUrl}/api/v1/profiles/export-code',
        options: Options(
          headers: {
            'Authorization': 'Bearer ${session.accessToken}',
            'X-Firebase-AppCheck': appCheckToken ?? '',
            'X-App-Variant': config.variantString,
          },
          validateStatus: (s) => s != null && s < 600,
        ),
      );

      if (response.statusCode == 200) {
        final code = response.data?['code'] as String?;
        if (code != null) {
          setState(() => _code = code);
          _startCountdown();
        }
      } else {
        final detail = response.data?['detail'] ?? 'Failed to generate code.';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFFD32F2F),
              content: Text(detail.toString(), style: const TextStyle(color: Colors.white)),
            ),
          );
        }
      }
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFD32F2F),
            content: Text(
              e.toString().replaceAll('Exception:', '').trim(),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _copyCode() {
    if (_code == null) return;
    Clipboard.setData(ClipboardData(text: _code!));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Color(0xFF111619),
        content: Text('Code copied!', style: TextStyle(color: Colors.white)),
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF111619),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x1F0D9488)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0x1A0D9488),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.upload_rounded, color: _teal, size: 18),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Export Profile Data',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Share with your Nexus main account',
                      style: TextStyle(fontSize: 12, color: Color(0x66FFFFFF)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (_hasActiveCode) ...[
            // Active code display
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0x0D0D9488),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0x330D9488)),
              ),
              child: Column(
                children: [
                  Text(
                    _code!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 10,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.timer_outlined, color: _teal, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        'Expires in $_formattedTime',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _teal,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ).animate().fade().scale(begin: const Offset(0.95, 0.95), duration: 300.ms),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _copyCode,
                    icon: const Icon(Icons.copy_rounded, size: 14),
                    label: const Text('Copy Code'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _teal,
                      side: const BorderSide(color: Color(0x330D9488)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _generateCode,
                    icon: const Icon(Icons.refresh_rounded, size: 14),
                    label: const Text('Refresh'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A2025),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            // No active code — generate prompt
            const Text(
              'Generate a one-time code to share your profile data with your main Nexus account. '
              'The code expires in 15 minutes.',
              style: TextStyle(
                fontSize: 13,
                color: Color(0x80FFFFFF),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(_teal),
                      ),
                    )
                  : ElevatedButton.icon(
                      onPressed: _generateCode,
                      icon: const Icon(Icons.generating_tokens_rounded, size: 16),
                      label: const Text('Generate Export Code'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _teal,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
            ),
          ],
        ],
      ),
    ).animate().fade(delay: 100.ms).slideY(begin: 0.05, end: 0, duration: 350.ms);
  }
}
