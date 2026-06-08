import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:nexus/utils/error_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Dialog to verify the phone number using OTP.
/// Only proceeds if the OTP is verified successfully.
class OtpVerificationDialog extends StatefulWidget {
  const OtpVerificationDialog({
    required this.phone,
    required this.onVerificationSuccess,
    super.key,
  });

  final String phone;
  final FutureOr<void> Function() onVerificationSuccess;

  @override
  State<OtpVerificationDialog> createState() => _OtpVerificationDialogState();
}

class _OtpVerificationDialogState extends State<OtpVerificationDialog> {
  final _otpController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  bool _success = false;

  Timer? _countdownTimer;
  int _resendCountdown = 60;

  static const _teal = Color(0xFF0D9488);

  @override
  void initState() {
    super.initState();
    _startCountdown();
    _otpController.addListener(_updateOtpState);
  }

  void _updateOtpState() {
    if (mounted) setState(() {});
  }

  bool get _isOtpValid {
    final code = _otpController.text.trim();
    return code.length == 8 && RegExp(r'^\d{8}$').hasMatch(code);
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

  @override
  void dispose() {
    _otpController..removeListener(_updateOtpState)..dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _resendOtp() async {
    if (_resendCountdown > 0 || _isLoading || _success) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(phone: widget.phone),
      );
      if (mounted) {
        _startCountdown();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF00ADB5),
            content: Text(
              'OTP resent successfully!',
              style: TextStyle(color: Colors.white),
            ),
          ),
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
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitOtp() async {
    final code = _otpController.text.trim();
    if (code.length != 8 || !RegExp(r'^\d{8}$').hasMatch(code)) {
      setState(() => _errorMessage = 'Please enter a valid 8-digit OTP code.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await Supabase.instance.client.auth.verifyOTP(
        phone: widget.phone,
        token: code,
        type: OtpType.phoneChange,
      );

      if (mounted) {
        setState(() => _success = true);
        final successResult = widget.onVerificationSuccess();
        await Future.wait<dynamic>([
          Future<void>.delayed(const Duration(seconds: 1, milliseconds: 200)),
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
      backgroundColor: const Color(0xFF111619),
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
                    color: const Color(0x1A0D9488),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.phone_android_rounded, color: _teal, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Verify Phone Number',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Sent to ${widget.phone}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0x66FFFFFF),
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Icon(Icons.close_rounded, color: Color(0x66FFFFFF), size: 20),
                ),
              ],
            ).animate().fade(),
            const SizedBox(height: 20),

            // Info callout
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0x0D0D9488),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x1A0D9488)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, color: _teal, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Please enter the verification code sent to your phone number via SMS to complete onboarding setup.',
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
              'ENTER OTP CODE',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: Color(0x99FFFFFF),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _otpController,
              enabled: !_isLoading && !_success,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(8),
              ],
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 6,
              ),
              decoration: InputDecoration(
                counterText: '',
                hintText: '• • • • • • • •',
                hintStyle: const TextStyle(
                  color: Color(0x33FFFFFF),
                  fontSize: 22,
                  letterSpacing: 6,
                ),
                filled: true,
                fillColor: const Color(0xFF090D0F),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0x1F0D9488)),
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
            const SizedBox(height: 12),

            // Resend Option
            Center(
              child: _resendCountdown > 0
                  ? Text(
                      'Resend code in $_resendCountdown s',
                      style: const TextStyle(color: Color(0x66FFFFFF), fontSize: 13),
                    )
                  : GestureDetector(
                      onTap: _resendOtp,
                      child: const Text(
                        'Resend OTP',
                        style: TextStyle(
                          color: _teal,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
            ).animate().fade(delay: 140.ms),
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
                            color: const Color(0x260D9488),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle_rounded, color: _teal, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Verification Successful!',
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
                            onTap: _isOtpValid ? _submitOtp : null,
                            borderRadius: BorderRadius.circular(14),
                            child: Ink(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                gradient: !_isOtpValid
                                    ? null
                                    : const LinearGradient(
                                        colors: [Color(0xFF0D9488), Color(0xFF0F766E)],
                                      ),
                                color: !_isOtpValid ? Colors.white.withValues(alpha: 0.08) : null,
                                boxShadow: !_isOtpValid
                                    ? null
                                    : const [
                                        BoxShadow(
                                          color: Color(0x260D9488),
                                          blurRadius: 12,
                                          spreadRadius: 1,
                                        ),
                                      ],
                              ),
                              child: Center(
                                child: Text(
                                  'Verify',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: !_isOtpValid ? Colors.white.withValues(alpha: 0.3) : Colors.white,
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
