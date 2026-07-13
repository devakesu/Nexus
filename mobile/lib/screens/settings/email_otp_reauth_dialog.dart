import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/theme/app_colors.dart';
import 'package:nexus/utils/error_handler.dart';
import 'package:nexus/utils/network_utils.dart';

/// Confirms it's really the account owner via an emailed OTP, before a
/// sensitive action (account deletion, data export) proceeds. Reused across
/// those two flows rather than duplicated - only the verify endpoint and
/// copy differ. Rides Supabase's native email OTP (AppConfig.otpLength
/// digits) - the same system login_screen.dart's email flow uses - not the
/// 6-digit SMS-based account_phone_otp system used elsewhere in Settings.
class EmailOtpReauthDialog extends StatefulWidget {
  const EmailOtpReauthDialog({
    required this.verifyUrl,
    required this.onVerificationSuccess,
    this.title = "Confirm It's You",
    this.infoText =
        'This confirms the request came from you, not just from this device.',
    super.key,
  });

  final String verifyUrl;
  final FutureOr<void> Function() onVerificationSuccess;
  final String title;
  final String infoText;

  @override
  State<EmailOtpReauthDialog> createState() => _EmailOtpReauthDialogState();
}

class _EmailOtpReauthDialogState extends State<EmailOtpReauthDialog> {
  final _otpController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  bool _success = false;

  static const int _codeLength = AppConfig.otpLength;

  @override
  void initState() {
    super.initState();
    _otpController.addListener(_updateOtpState);
  }

  void _updateOtpState() {
    if (mounted) setState(() {});
  }

  bool get _isCodeValid {
    final code = _otpController.text.trim();
    return code.length == _codeLength && RegExp(r'^\d+$').hasMatch(code);
  }

  @override
  void dispose() {
    _otpController
      ..removeListener(_updateOtpState)
      ..dispose();
    super.dispose();
  }

  Future<void> _submitCode() async {
    if (!_isCodeValid) {
      setState(
        () => _errorMessage = 'Please enter the $_codeLength-digit code.',
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await createDio().post<Map<String, dynamic>>(
        widget.verifyUrl,
        data: {'code': _otpController.text.trim()},
        options: Options(
          headers: {'X-App-Variant': AppConfig.current.variantString},
        ),
      );

      if (mounted) {
        setState(() => _success = true);
        final successResult = widget.onVerificationSuccess();
        await Future.wait<dynamic>([
          Future<void>.delayed(const Duration(milliseconds: 600)),
          if (successResult is Future) successResult,
        ]);
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    } on Object catch (e, stackTrace) {
      if (mounted) {
        setState(() {
          _errorMessage = ErrorHandler.getFriendlyMessage(e);
        });
        ErrorHandler.handleError(
          e,
          stackTrace: stackTrace,
          customMessage: 'OTP verification failed.',
          showUi: false,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.mark_email_read_rounded,
                    color: AppColors.error,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: GoogleFonts.manrope(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                      Text(
                        'Enter the code we emailed you',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppColors.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Icon(
                    Icons.close_rounded,
                    color: AppColors.inkMuted,
                    size: 20,
                  ),
                ),
              ],
            ).animate().fade(),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.error.withValues(alpha: 0.15),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    color: AppColors.error,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.infoText,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppColors.inkMuted,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ).animate().fade(delay: 80.ms),
            const SizedBox(height: 20),
            Text(
              'ENTER CODE',
              style: GoogleFonts.manrope(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: AppColors.inkMuted,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _otpController,
              enabled: !_isLoading && !_success,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(_codeLength),
              ],
              style: GoogleFonts.jetBrainsMono(
                color: AppColors.ink,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: 4,
              ),
              decoration: InputDecoration(
                counterText: '',
                hintText: '•' * _codeLength,
                hintStyle: GoogleFonts.jetBrainsMono(
                  color: AppColors.inkFaint,
                  fontSize: 20,
                  letterSpacing: 4,
                ),
                filled: true,
                fillColor: AppColors.canvas,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.borderNeutral),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: AppColors.error,
                    width: 1.5,
                  ),
                ),
                errorText: _errorMessage,
                errorMaxLines: 3,
              ),
              onChanged: (_) => setState(() => _errorMessage = null),
            ).animate().fade(delay: 120.ms),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 50),
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.error,
                          ),
                        ),
                      )
                    : _success
                    ? Container(
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.check_circle_rounded,
                              color: AppColors.success,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Verified',
                              style: GoogleFonts.manrope(
                                color: AppColors.success,
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
                          onTap: _isCodeValid ? _submitCode : null,
                          borderRadius: BorderRadius.circular(14),
                          child: Ink(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              color: _isCodeValid
                                  ? AppColors.error
                                  : AppColors.inkFaint.withValues(alpha: 0.2),
                            ),
                            child: Center(
                              child: Text(
                                'Verify & Continue',
                                style: GoogleFonts.manrope(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: _isCodeValid
                                      ? Colors.white
                                      : AppColors.inkFaint,
                                ),
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
