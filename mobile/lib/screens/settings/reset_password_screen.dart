import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/theme/app_colors.dart';
import 'package:nexus/utils/error_handler.dart';
import 'package:nexus/widgets/aesthetic_loaders.dart';
import 'package:nexus/widgets/nexus_toast.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({required this.onComplete, super.key});

  final VoidCallback onComplete;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  bool _isLoading = false;

  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscureNew = true;
  bool _obscureConfirm = true;

  // Password validation states
  bool _hasMinLength = false;
  bool _hasUppercase = false;
  bool _hasLowercase = false;
  bool _hasDigit = false;
  bool _hasSpecialChar = false;

  @override
  void initState() {
    super.initState();
    _newPasswordController.addListener(_validatePassword);
  }

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _validatePassword() {
    final val = _newPasswordController.text;
    setState(() {
      _hasMinLength = val.length >= 8;
      _hasUppercase = val.contains(RegExp('[A-Z]'));
      _hasLowercase = val.contains(RegExp('[a-z]'));
      _hasDigit = val.contains(RegExp('[0-9]'));
      _hasSpecialChar = val.contains(RegExp(r'[@$!%*?&]'));
    });
  }

  bool get _isPasswordValid =>
      _hasMinLength &&
      _hasUppercase &&
      _hasLowercase &&
      _hasDigit &&
      _hasSpecialChar;

  bool get _canSubmit {
    final newPass = _newPasswordController.text;
    final confirm = _confirmPasswordController.text;
    return _isPasswordValid && newPass == confirm;
  }

  Future<void> _handleSubmit() async {
    if (!_canSubmit) return;

    setState(() => _isLoading = true);

    final newPass = _newPasswordController.text;

    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: newPass),
      );

      if (mounted) {
        NexusToast.show(
          context,
          'Password reset successful!',
          type: NexusToastType.success,
        );
        widget.onComplete();
      }
    } on AuthException catch (e) {
      if (mounted) {
        NexusToast.show(
          context,
          e.message,
          type: NexusToastType.error,
        );
      }
    } on Object catch (e, stackTrace) {
      ErrorHandler.handleError(
        e,
        stackTrace: stackTrace,
        customMessage: 'Failed to reset password: $e',
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasConfirmError = _confirmPasswordController.text.isNotEmpty &&
        _newPasswordController.text != _confirmPasswordController.text;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0D13),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Brand Icon
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      LucideIcons.shieldAlert,
                      color: AppColors.pulsarPink,
                      size: 32,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Heading
                Text(
                  'Reset Your Password',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.manrope(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Please create a strong new password to secure your account.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.manrope(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 32),
                // Form Card
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: _isLoading
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 40),
                            child: NexusOrbitLoader(size: 60),
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _PasswordInput(
                              label: 'NEW PASSWORD',
                              hintText: 'Enter a strong password',
                              controller: _newPasswordController,
                              obscureText: _obscureNew,
                              onToggleObscure: () =>
                                  setState(() => _obscureNew = !_obscureNew),
                              onChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: 8),
                            _buildValidationChecklist(),
                            const SizedBox(height: 16),
                            _PasswordInput(
                              label: 'CONFIRM NEW PASSWORD',
                              hintText: 'Re-enter your new password',
                              controller: _confirmPasswordController,
                              obscureText: _obscureConfirm,
                              onToggleObscure: () =>
                                  setState(() => _obscureConfirm = !_obscureConfirm),
                              onChanged: (_) => setState(() {}),
                            ),
                            if (hasConfirmError) ...[
                              const Padding(
                                padding: EdgeInsets.only(left: 4, top: 8),
                                child: Text(
                                  'Passwords do not match.',
                                  style: TextStyle(
                                    color: AppColors.error,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 24),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: const Color(0xFF0F172A),
                                disabledBackgroundColor:
                                    Colors.white.withValues(alpha: 0.1),
                                disabledForegroundColor:
                                    Colors.white.withValues(alpha: 0.3),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                elevation: 0,
                              ),
                              onPressed: _isLoading || !_canSubmit ? null : _handleSubmit,
                              child: const Text(
                                'Reset Password',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _isLoading ? null : widget.onComplete,
                  child: Text(
                    'Cancel and Go Back',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildValidationChecklist() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.04),
        ),
      ),
      child: Column(
        children: [
          _ChecklistItem(
            label: 'At least 8 characters',
            checked: _hasMinLength,
          ),
          const SizedBox(height: 6),
          _ChecklistItem(
            label: 'At least 1 uppercase letter',
            checked: _hasUppercase,
          ),
          const SizedBox(height: 6),
          _ChecklistItem(
            label: 'At least 1 lowercase letter',
            checked: _hasLowercase,
          ),
          const SizedBox(height: 6),
          _ChecklistItem(
            label: 'At least 1 numeric digit',
            checked: _hasDigit,
          ),
          const SizedBox(height: 6),
          _ChecklistItem(
            label: r'At least 1 special character (@$!%*?&)',
            checked: _hasSpecialChar,
          ),
        ],
      ),
    );
  }
}

class _PasswordInput extends StatefulWidget {
  const _PasswordInput({
    required this.label,
    required this.hintText,
    required this.controller,
    required this.obscureText,
    required this.onToggleObscure,
    required this.onChanged,
  });

  final String label;
  final String hintText;
  final TextEditingController controller;
  final bool obscureText;
  final VoidCallback onToggleObscure;
  final ValueChanged<String> onChanged;

  @override
  State<_PasswordInput> createState() => _PasswordInputState();
}

class _PasswordInputState extends State<_PasswordInput> {
  final _focusNode = FocusNode();
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() => _isFocused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: _isFocused
                ? const LinearGradient(
                    colors: [Color(0xFF00E5FF), AppColors.pulsarPink],
                  )
                : LinearGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.08),
                      Colors.white.withValues(alpha: 0.08),
                    ],
                  ),
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: AppColors.pulsarPink.withValues(alpha: 0.2),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ]
                : [],
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.all(1.2),
            decoration: BoxDecoration(
              color: _isFocused
                  ? const Color(0xFF141722)
                  : const Color(0xFF181B27),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.lock,
                    color: _isFocused ? AppColors.pulsarPink : Colors.white30,
                    size: 16,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: widget.controller,
                      focusNode: _focusNode,
                      obscureText: widget.obscureText,
                      onChanged: widget.onChanged,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        hintText: widget.hintText,
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.2),
                          fontSize: 14,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      widget.obscureText ? LucideIcons.eyeOff : LucideIcons.eye,
                      color: Colors.white30,
                      size: 16,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: widget.onToggleObscure,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ChecklistItem extends StatelessWidget {
  const _ChecklistItem({required this.label, required this.checked});

  final String label;
  final bool checked;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          checked ? LucideIcons.checkCircle2 : LucideIcons.circle,
          color: checked ? AppColors.success : Colors.white30,
          size: 14,
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: checked ? Colors.white : Colors.white.withValues(alpha: 0.4),
            fontSize: 11.5,
            fontWeight: checked ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}
