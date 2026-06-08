import 'dart:async';
import 'package:dio/dio.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/utils/error_handler.dart';
import 'package:nexus/utils/network_utils.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ExportCodeCard extends StatefulWidget {
  const ExportCodeCard({super.key});

  @override
  State<ExportCodeCard> createState() => _ExportCodeCardState();
}

class _ExportCodeCardState extends State<ExportCodeCard> {
  static const Color _teal = Color(0xFFFF7597);
  static const int _ttlSeconds = 15 * 60; // 15 minutes

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
              content: Text(
                detail.toString(),
                style: const TextStyle(color: Colors.white),
              ),
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
              ErrorHandler.getFriendlyMessage(e),
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
    unawaited(Clipboard.setData(ClipboardData(text: _code!)));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Color(0xFF161B26),
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
        color: const Color(0xFF161B26),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x1FFF7597)),
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
                  color: const Color(0x1AFF7597),
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
                color: const Color(0x0DFF7597),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x33FF7597)),
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
            ).animate().fade().scale(
              begin: const Offset(0.95, 0.95),
              duration: 300.ms,
            ),
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
                      side: const BorderSide(color: Color(0x33FF7597)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      if (!_isLoading) {
                        unawaited(_generateCode());
                      }
                    },
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
                      onPressed: () {
                        unawaited(_generateCode());
                      },
                      icon: const Icon(
                        Icons.generating_tokens_rounded,
                        size: 16,
                      ),
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
