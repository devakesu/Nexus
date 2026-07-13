import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/theme/app_colors.dart';
import 'package:nexus/utils/error_handler.dart';
import 'package:nexus/utils/network_utils.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Dialog that lets a main Nexus user enter a 6-char export code generated
/// by their Nexus-MEC (flavor) account and import profile data from it.
///
/// Only shown in the main nexus variant onboarding screen.
class ImportCodeDialog extends StatefulWidget {
  const ImportCodeDialog({
    required this.onImportSuccess,
    super.key,
  });

  final VoidCallback onImportSuccess;

  @override
  State<ImportCodeDialog> createState() => _ImportCodeDialogState();
}

class _ImportCodeDialogState extends State<ImportCodeDialog> {
  final _codeController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  bool _success = false;

  static const Color _teal = AppColors.pulsarPink;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submitCode() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.length != 6 || !RegExp(r'^[A-Z0-9]+$').hasMatch(code)) {
      setState(() => _errorMessage = 'Please enter a valid 6-character code.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) {
        throw Exception('Session expired. Please sign in again.');
      }

      final config = AppConfig.current;
      final dio = createDio();

      final response = await dio.post<Map<String, dynamic>>(
        '${config.backendUrl}/api/v1/profiles/import',
        data: {'sync_code': code},
        options: Options(
          headers: {
            'X-App-Variant': config.variantString,
          },
          validateStatus: (status) => status != null && status < 600,
        ),
      );

      if (response.statusCode == 200) {
        setState(() => _success = true);
        await Future<void>.delayed(
          const Duration(seconds: 1, milliseconds: 200),
        );
        if (mounted) {
          Navigator.of(context).pop();
          widget.onImportSuccess();
        }
      } else {
        final detail =
            response.data?['detail'] ??
            'Import failed. Check the code and try again.';
        setState(() => _errorMessage = detail.toString());
      }
    } on Object catch (e) {
      setState(() => _errorMessage = ErrorHandler.getFriendlyMessage(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF161B26),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0x1AFF7597),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.download_rounded,
                    color: _teal,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Import Profile Data',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'From your Nexus MEC account',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0x66FFFFFF),
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Icon(
                    Icons.close_rounded,
                    color: Color(0x66FFFFFF),
                    size: 20,
                  ),
                ),
              ],
            ).animate().fade(),
            const SizedBox(height: 20),

            // Info callout
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0x0DFF7597),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x1AFF7597)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, color: _teal, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Generate a 6-character code in your Nexus MEC app '
                      '(Home → Export Code). The code is valid for 15 minutes '
                      'and can only be used once.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0x99FFFFFF),
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ).animate().fade(delay: 80.ms),
            const SizedBox(height: 20),

            // Code input
            const Text(
              'EXPORT CODE',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: Color(0x99FFFFFF),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _codeController,
              enabled: !_isLoading && !_success,
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 6,
              ),
              decoration: InputDecoration(
                counterText: '',
                hintText: '• • • • • •',
                hintStyle: const TextStyle(
                  color: Color(0x33FFFFFF),
                  fontSize: 22,
                  letterSpacing: 6,
                ),
                filled: true,
                fillColor: const Color(0xFF0B0D13),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0x1FFF7597)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _teal, width: 1.5),
                ),
                errorText: _errorMessage,
                errorStyle: const TextStyle(color: Color(0xFFEF5350)),
                errorMaxLines: 3,
              ),
              onChanged: (_) => setState(() => _errorMessage = null),
            ).animate().fade(delay: 120.ms),
            const SizedBox(height: 20),

            // Action button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(_teal),
                      ),
                    )
                  : _success
                  ? Container(
                      decoration: BoxDecoration(
                        color: const Color(0x26FF7597),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.check_circle_rounded,
                            color: _teal,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Import Successful!',
                            style: TextStyle(
                              color: _teal,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _submitCode,
                        borderRadius: BorderRadius.circular(14),
                        child: Ink(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: const LinearGradient(
                              colors: [AppColors.pulsarPink, Color(0xFFE04B76)],
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x26FF7597),
                                blurRadius: 12,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Text(
                              'Import Now',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
            ).animate().fade(delay: 160.ms),
          ],
        ),
      ),
    );
  }
}
