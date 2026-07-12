import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/theme/app_colors.dart';
import 'package:nexus/utils/error_handler.dart';
import 'package:nexus/widgets/aesthetic_loaders.dart';
import 'package:nexus/widgets/nexus_toast.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum _PasswordSheetStep { entry, reauth }

/// Shows the Change Password bottom sheet.
Future<void> showChangePasswordSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    builder: (sheetContext) {
      return const ChangePasswordSheet();
    },
  );
}

class ChangePasswordSheet extends StatefulWidget {
  const ChangePasswordSheet({super.key});

  @override
  State<ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<ChangePasswordSheet> {
  _PasswordSheetStep _step = _PasswordSheetStep.entry;
  bool _isLoading = false;

  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _otpController = TextEditingController();

  bool _obscureCurrent = true;
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
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _otpController.dispose();
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

  bool get _canSubmitEntry {
    final current = _currentPasswordController.text;
    final newPass = _newPasswordController.text;
    final confirm = _confirmPasswordController.text;
    return _isPasswordValid &&
        newPass == confirm &&
        (current.isEmpty || newPass != current);
  }

  Future<void> _handleForgotPassword() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || user.email == null) {
      NexusToast.show(
        context,
        'No logged-in user email found.',
        type: NexusToastType.error,
      );
      return;
    }

    final email = user.email!;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text(
          'Reset Password?',
          style: GoogleFonts.manrope(fontWeight: FontWeight.w800),
        ),
        content: Text(
          'We will send a password reset link to $email.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Send Email'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      final isMec = AppConfig.current.appVariant == AppVariant.nexusMec;
      final String redirectUrl;
      if (kDebugMode) {
        final scheme = isMec ? 'devakesu-nexus-mec' : 'devakesu-nexus';
        redirectUrl = '$scheme://home';
      } else {
        final appHost = isMec ? 'nexus-mec.devakesu.com' : 'nexus.devakesu.com';
        redirectUrl = 'https://$appHost/app';
      }

      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        redirectTo: redirectUrl,
      );

      if (mounted) {
        NexusToast.show(
          context,
          'Password reset email sent!',
          type: NexusToastType.success,
        );
        Navigator.pop(context);
      }
    } on Object catch (e, stackTrace) {
      ErrorHandler.handleError(
        e,
        stackTrace: stackTrace,
        customMessage: 'Failed to send reset email: $e',
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSubmitEntry() async {
    if (!_canSubmitEntry) return;

    setState(() => _isLoading = true);

    final currentPass = _currentPasswordController.text;
    final newPass = _newPasswordController.text;

    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributesWithCurrentPassword(
          password: newPass,
          currentPassword: currentPass,
        ),
      );

      if (mounted) {
        NexusToast.show(
          context,
          'Password updated successfully!',
          type: NexusToastType.success,
        );
        Navigator.pop(context);
      }
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      // Check if reauthentication is required
      if (msg.contains('reauthenticate') ||
          msg.contains('nonce') ||
          e.code == 'reauthentication_needed') {
        try {
          await Supabase.instance.client.auth.reauthenticate();
          setState(() {
            _step = _PasswordSheetStep.reauth;
          });
          if (mounted) {
            NexusToast.show(
              context,
              'Security verification code sent to email/phone.',
            );
          }
        } on Object catch (reauthErr, reauthStack) {
          ErrorHandler.handleError(
            reauthErr,
            stackTrace: reauthStack,
            customMessage: 'Failed to trigger reauthentication: $reauthErr',
          );
        }
      } else {
        var errorMsg = e.message;
        if (e.code == 'current_password_mismatch' ||
            msg.contains('mismatch') ||
            msg.contains('incorrect') ||
            msg.contains('invalid') ||
            (currentPass.isNotEmpty && msg.contains('current password'))) {
          errorMsg = 'The current password you entered is incorrect.';
        }
        if (mounted) {
          NexusToast.show(
            context,
            errorMsg,
            type: NexusToastType.error,
          );
        }
      }
    } on Object catch (e, stackTrace) {
      ErrorHandler.handleError(
        e,
        stackTrace: stackTrace,
        customMessage: 'Failed to update password: $e',
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSubmitReauth() async {
    final otpCode = _otpController.text.trim();
    if (otpCode.isEmpty) return;

    setState(() => _isLoading = true);

    final currentPass = _currentPasswordController.text;
    final newPass = _newPasswordController.text;

    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributesWithCurrentPassword(
          password: newPass,
          currentPassword: currentPass,
          nonce: otpCode,
        ),
      );

      if (mounted) {
        NexusToast.show(
          context,
          'Password updated successfully!',
          type: NexusToastType.success,
        );
        Navigator.pop(context);
      }
    } on AuthException catch (e) {
      var errorMsg = e.message;
      final msg = e.message.toLowerCase();
      if (e.code == 'current_password_mismatch' ||
          msg.contains('mismatch') ||
          msg.contains('incorrect') ||
          msg.contains('invalid') ||
          (currentPass.isNotEmpty && msg.contains('current password'))) {
        errorMsg = 'The current password you entered is incorrect.';
      }
      if (mounted) {
        NexusToast.show(
          context,
          errorMsg,
          type: NexusToastType.error,
        );
      }
    } on Object catch (e, stackTrace) {
      ErrorHandler.handleError(
        e,
        stackTrace: stackTrace,
        customMessage: 'Reauthentication failed: $e',
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: 12,
        left: 20,
        right: 20,
        bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  const Icon(
                    LucideIcons.keyRound,
                    color: AppColors.modeSettings,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _step == _PasswordSheetStep.entry
                        ? 'Change Password'
                        : 'Security Verification',
                    style: GoogleFonts.manrope(
                      color: AppColors.ink,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (_isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: NexusOrbitLoader(
                      size: 60,
                      lightMode: true,
                    ),
                  ),
                )
              else ...[
                if (_step == _PasswordSheetStep.entry)
                  ..._buildEntryForm()
                else
                  ..._buildReauthForm(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildEntryForm() {
    final hasConfirmError = _confirmPasswordController.text.isNotEmpty &&
        _newPasswordController.text != _confirmPasswordController.text;

    return [
      _PasswordInput(
        label: 'CURRENT PASSWORD',
        hintText: 'Enter your current password',
        controller: _currentPasswordController,
        obscureText: _obscureCurrent,
        onToggleObscure: () => setState(() => _obscureCurrent = !_obscureCurrent),
        onChanged: (_) => setState(() {}),
      ),
      const Padding(
        padding: EdgeInsets.only(top: 4, left: 4),
        child: Text(
          "Leave blank if you registered via Google/OTP and haven't set a password yet.",
          style: TextStyle(
            color: AppColors.inkMuted,
            fontSize: 11,
          ),
        ),
      ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: _isLoading ? null : _handleForgotPassword,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text(
            'Forgot old password?',
            style: TextStyle(
              color: AppColors.modeSettings,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      _PasswordInput(
        label: 'NEW PASSWORD',
        hintText: 'Enter a strong password',
        controller: _newPasswordController,
        obscureText: _obscureNew,
        onToggleObscure: () => setState(() => _obscureNew = !_obscureNew),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 4),
      _buildValidationChecklist(),
      const SizedBox(height: 12),
      _PasswordInput(
        label: 'CONFIRM NEW PASSWORD',
        hintText: 'Re-enter your new password',
        controller: _confirmPasswordController,
        obscureText: _obscureConfirm,
        onToggleObscure: () => setState(() => _obscureConfirm = !_obscureConfirm),
        onChanged: (_) => setState(() {}),
      ),
      if (hasConfirmError) ...[
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            'Passwords do not match.',
            style: TextStyle(color: AppColors.error, fontSize: 12),
          ),
        ),
      ],
      const SizedBox(height: 12),
      ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.ink,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.borderNeutral,
          disabledForegroundColor: AppColors.inkMuted,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
          elevation: 0,
        ),
        onPressed: _isLoading || !_canSubmitEntry ? null : _handleSubmitEntry,
        child: _isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Text(
                'Change Password',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
      ),
    ];
  }

  List<Widget> _buildReauthForm() {
    return [
      const Text(
        'For security, we sent a 6-digit verification code to your email/phone. Please enter it to complete the password change.',
        style: TextStyle(color: AppColors.inkMuted, fontSize: 13, height: 1.4),
      ),
      const SizedBox(height: 20),
      _CustomTextField(
        label: 'VERIFICATION CODE',
        hintText: 'Enter 6-digit code',
        controller: _otpController,
        keyboardType: TextInputType.number,
        prefixIcon: LucideIcons.shieldAlert,
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 20),
      ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.ink,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.borderNeutral,
          disabledForegroundColor: AppColors.inkMuted,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
          elevation: 0,
        ),
        onPressed: _isLoading || _otpController.text.trim().isEmpty
            ? null
            : _handleSubmitReauth,
        child: _isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Text(
                'Verify & Change Password',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: _isLoading
            ? null
            : () => setState(() {
                  _step = _PasswordSheetStep.entry;
                  _otpController.clear();
                }),
        child: const Text(
          'Go Back',
          style: TextStyle(color: AppColors.inkMuted),
        ),
      ),
    ];
  }

  Widget _buildValidationChecklist() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          _ChecklistItem(label: 'At least 8 characters', checked: _hasMinLength),
          const SizedBox(height: 6),
          _ChecklistItem(label: 'At least 1 uppercase letter', checked: _hasUppercase),
          const SizedBox(height: 6),
          _ChecklistItem(label: 'At least 1 lowercase letter', checked: _hasLowercase),
          const SizedBox(height: 6),
          _ChecklistItem(label: 'At least 1 numeric digit', checked: _hasDigit),
          const SizedBox(height: 6),
          _ChecklistItem(label: r'At least 1 special character (@$!%*?&)', checked: _hasSpecialChar),
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
            color: Colors.black.withValues(alpha: 0.5),
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 6),
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
                      Colors.black.withValues(alpha: 0.08),
                      Colors.black.withValues(alpha: 0.08),
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
              color: _isFocused ? Colors.white : const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.lock,
                    color: _isFocused ? AppColors.pulsarPink : Colors.black38,
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
                        color: Color(0xFF0F172A),
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        hintText: widget.hintText,
                        hintStyle: TextStyle(
                          color: Colors.black.withValues(alpha: 0.3),
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
                      color: Colors.black38,
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

class _CustomTextField extends StatefulWidget {
  const _CustomTextField({
    required this.label,
    required this.hintText,
    required this.controller,
    required this.prefixIcon,
    required this.onChanged,
    this.keyboardType,
  });

  final String label;
  final String hintText;
  final TextEditingController controller;
  final IconData prefixIcon;
  final ValueChanged<String> onChanged;
  final TextInputType? keyboardType;

  @override
  State<_CustomTextField> createState() => _CustomTextFieldState();
}

class _CustomTextFieldState extends State<_CustomTextField> {
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
            color: Colors.black.withValues(alpha: 0.5),
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 6),
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
                      Colors.black.withValues(alpha: 0.08),
                      Colors.black.withValues(alpha: 0.08),
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
              color: _isFocused ? Colors.white : const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(
                children: [
                  Icon(
                    widget.prefixIcon,
                    color: _isFocused ? AppColors.pulsarPink : Colors.black38,
                    size: 16,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: widget.controller,
                      focusNode: _focusNode,
                      keyboardType: widget.keyboardType,
                      onChanged: widget.onChanged,
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        hintText: widget.hintText,
                        hintStyle: TextStyle(
                          color: Colors.black.withValues(alpha: 0.3),
                          fontSize: 14,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
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
          color: checked ? AppColors.success : Colors.black26,
          size: 14,
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: checked ? AppColors.ink : AppColors.inkMuted,
            fontSize: 11.5,
            fontWeight: checked ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}

class UserAttributesWithCurrentPassword extends UserAttributes {
  UserAttributesWithCurrentPassword({
    super.email,
    super.phone,
    super.password,
    super.nonce,
    super.data,
    this.currentPassword,
  });

  final String? currentPassword;

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    if (currentPassword != null && currentPassword!.isNotEmpty) {
      json['current_password'] = currentPassword;
    }
    return json;
  }
}
