import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nexus/core/config/app_config.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/core/utils/encrypted_string.dart';
import 'package:nexus/core/utils/error_handler.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:nexus/core/widgets/aesthetic_loaders.dart';
import 'package:nexus/core/widgets/nexus_toast.dart';
import 'package:nexus/features/security_signal/services/security_service.dart';

/// Confirms it's really the account owner via an emailed OTP, before a
/// sensitive action (account deletion, data export) proceeds. Reused across
/// those two flows rather than duplicated - only the verify endpoint and
/// copy differ. Rides Supabase's native email OTP (AppConfig.otpLength
/// digits) - the same system login_screen.dart's email flow uses - not the
/// 6-digit SMS-based account_phone_otp system used elsewhere in Settings.
class EmailOtpReauthDialog extends StatefulWidget {
  const EmailOtpReauthDialog({
    required this.verifyUrl,
    required this.resendUrl,
    required this.onVerificationSuccess,
    this.title = "Confirm It's You",
    this.infoText =
        'This confirms the request came from you, not just from this device.',
    super.key,
  });

  final String verifyUrl;
  final String resendUrl;
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

  Timer? _countdownTimer;
  int _resendCountdown = 60;

  StreamSubscription<void>? _overlaySubscription;
  Timer? _securityCheckTimer;
  bool _isOverlayDetected = false;
  bool _isScreenRecordingActive = false;

  static const int _codeLength = AppConfig.otpLength;

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
      if (!mounted) return;
      final active = await SecurityService.isScreenRecordingOrMirroring();
      if (mounted && active != _isScreenRecordingActive) {
        setState(() {
          _isScreenRecordingActive = active;
        });
      }
    });
    _startCountdown();
    _otpController.addListener(_updateOtpState);
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    setState(() {
      _resendCountdown = 60;
    });
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

  void _updateOtpState() {
    if (mounted) setState(() {});
  }

  bool get _isCodeValid {
    final code = _otpController.text.trim();
    return code.length == _codeLength && RegExp(r'^\d+$').hasMatch(code);
  }

  @override
  void dispose() {
    unawaited(_overlaySubscription?.cancel());
    _securityCheckTimer?.cancel();
    unawaited(SecurityService.exitSensitiveScreen());
    _countdownTimer?.cancel();
    _otpController
      ..removeListener(_updateOtpState)
      ..dispose();
    super.dispose();
  }

  Future<void> _resendOtp() async {
    if (_resendCountdown > 0 || _isLoading || _success) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await createDio().post<Map<String, dynamic>>(
        widget.resendUrl,
        options: Options(
          headers: {'X-App-Variant': AppConfig.current.variantString},
        ),
      );
      if (mounted) {
        _startCountdown();
        NexusToast.show(
          context,
          'A new verification code has been sent.',
        );
      }
    } on Object catch (e, stackTrace) {
      if (mounted) {
        setState(() {
          _errorMessage = ErrorHandler.getFriendlyMessage(e);
        });
        ErrorHandler.handleError(
          e,
          stackTrace: stackTrace,
          customMessage: 'Failed to resend OTP.',
          showUi: false,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
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

    final encryptedCode = EncryptedString(_otpController.text.trim());

    try {
      await encryptedCode.use(
        (code) => createDio().post<Map<String, dynamic>>(
          widget.verifyUrl,
          data: {'code': code},
          options: Options(
            headers: {'X-App-Variant': AppConfig.current.variantString},
          ),
        ),
      );

      if (mounted) {
        setState(() => _success = true);
        await Future<void>.delayed(const Duration(milliseconds: 600));
        if (mounted) {
          Navigator.of(context).pop();
        }
        widget.onVerificationSuccess();
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
    if (_isScreenRecordingActive) {
      return Dialog(
        backgroundColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off, color: Colors.red, size: 64),
              const SizedBox(height: 16),
              Text(
                'Screen Recording Detected',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Verification cannot be completed while screen recording or mirroring is active.',
                style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[400]),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (_isOverlayDetected) {
      return Dialog(
        backgroundColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.security, color: Colors.amber, size: 64),
              const SizedBox(height: 16),
              Text(
                'Screen Overlay Detected',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Another application is drawing an overlay on top of this screen. Please close any overlay applications to continue.',
                style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[400]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _isOverlayDetected = false;
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Dismiss Warning',
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

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
            const SizedBox(height: 12),
            Center(
              child: _resendCountdown > 0
                  ? Text(
                      'Resend code in ${_resendCountdown}s',
                      style: GoogleFonts.inter(
                        color: AppColors.inkMuted,
                        fontSize: 13,
                      ),
                    )
                  : GestureDetector(
                      onTap: _resendOtp,
                      child: Text(
                        'Resend OTP',
                        style: GoogleFonts.inter(
                          color: AppColors.error,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
            ).animate().fade(delay: 140.ms),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 50),
                child: _isLoading
                    ? const Center(
                        child: NexusOrbitLoader(size: 28, lightMode: true),
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
