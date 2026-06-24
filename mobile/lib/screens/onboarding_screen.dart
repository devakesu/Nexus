import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/screens/legal_terms_page.dart';
import 'package:nexus/screens/onboarding/import_code_dialog.dart';
import 'package:nexus/screens/onboarding/mec_onboarding_fields.dart';
import 'package:nexus/screens/onboarding/nexus_onboarding_fields.dart';
import 'package:nexus/screens/onboarding/otp_verification_dialog.dart';
import 'package:nexus/utils/error_handler.dart';
import 'package:nexus/utils/network_utils.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    required this.termsVersion,
    required this.onComplete,
    super.key,
  });

  final String termsVersion;
  final VoidCallback onComplete;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  int _selectedAge = 18;
  bool _isLoading = false;

  // ── MEC-specific state ─────────────────────────────────────────────────────
  String _mecBranch = 'CSBS';
  int _mecYear = 1;

  // ── Nexus-specific variant state ───────────────────────────────────────────
  String _lifestyle = 'Chill';

  // ── Terms state ────────────────────────────────────────────────────────────
  bool _acceptedTerms = false;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_updateCanSubmit);
    _phoneController.addListener(_updateCanSubmit);

    final user = Supabase.instance.client.auth.currentUser;
    if (user?.phone != null && user!.phone!.isNotEmpty) {
      _phoneController.text = user.phone!;
    }

    final googleName = _getGoogleName();
    if (googleName != 'User') {
      _nameController.text = googleName;
    }
  }

  void _updateCanSubmit() {
    if (mounted) {
      setState(() {});
    }
  }

  // ---------------------------------------------------------------------------

  AppConfig get _config => AppConfig.current;

  /// Derives name from Google OAuth metadata for MEC (read-only).
  String _getGoogleName() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null && user.userMetadata != null) {
      for (final key in ['name', 'full_name', 'given_name', 'display_name']) {
        final val = user.userMetadata![key];
        if (val is String && val.trim().isNotEmpty) {
          return val.trim();
        }
      }
      final email = user.email;
      if (email != null && email.contains('@')) {
        final prefix = email.split('@')[0];
        final parts = prefix
            .replaceAll('.', ' ')
            .replaceAll('_', ' ')
            .replaceAll('-', ' ')
            .split(' ')
            .map(
              (p) =>
                  p.isNotEmpty ? '${p[0].toUpperCase()}${p.substring(1)}' : '',
            )
            .where((p) => p.isNotEmpty)
            .toList();
        if (parts.isNotEmpty) {
          return parts.join(' ');
        }
      }
    }
    return 'User';
  }

  @override
  void dispose() {
    _nameController.removeListener(_updateCanSubmit);
    _phoneController.removeListener(_updateCanSubmit);
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submitOnboarding() async {
    if (!_formKey.currentState!.validate()) return;

    // MEC: branch must be selected
    if (_config.isFlavorVariant && _mecBranch.isEmpty) {
      _showError('Please select your branch.');
      return;
    }

    final user = Supabase.instance.client.auth.currentUser;
    final hasVerifiedPhone =
        user?.phone != null &&
        user!.phone!.isNotEmpty &&
        user.phoneConfirmedAt != null;
    final phone = hasVerifiedPhone ? user.phone! : _phoneController.text.trim();
    final isPhoneVerified =
        hasVerifiedPhone ||
        (user?.phone == phone && user?.phoneConfirmedAt != null);

    if (!isPhoneVerified) {
      setState(() => _isLoading = true);
      try {
        await Supabase.instance.client.auth.updateUser(
          UserAttributes(phone: phone),
        );
        if (mounted) setState(() => _isLoading = false);

        if (!mounted) return;
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => OtpVerificationDialog(
            phone: phone,
            onVerificationSuccess: _executeCompleteOnboarding,
          ),
        );
      } on Object catch (e, stackTrace) {
        if (mounted) {
          ErrorHandler.handleError(
            e,
            stackTrace: stackTrace,
            customMessage:
                'Failed to update phone number: ${ErrorHandler.getFriendlyMessage(e)}',
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    } else {
      await _executeCompleteOnboarding();
    }
  }

  Future<void> _executeCompleteOnboarding() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) {
        throw Exception('Session expired. Please sign in again.');
      }

      final dio = createDio();

      final Map<String, dynamic> payload;
      final user = Supabase.instance.client.auth.currentUser;
      final phone = _phoneController.text.trim().isNotEmpty
          ? _phoneController.text.trim()
          : (user?.phone ?? '');

      if (_config.isFlavorVariant) {
        // MEC payload: campus_branch + campus_year + campus_name + age + phone
        payload = {
          'app_variant': _config.variantString,
          'campus_branch': _mecBranch,
          'campus_year': _mecYear,
          'campus_name': 'Model Engineering College',
          'age': _selectedAge,
          'phone': phone,
          'accepted_terms_version': widget.termsVersion,
        };
      } else {
        // Nexus main payload: name + age + lifestyle + phone
        payload = {
          'app_variant': _config.variantString,
          'name': _nameController.text.trim(),
          'age': _selectedAge,
          'lifestyle': _lifestyle,
          'phone': phone,
          'accepted_terms_version': widget.termsVersion,
        };
      }

      final response = await dio.post<Map<String, dynamic>>(
        '${_config.backendUrl}/api/v1/auth/complete-onboarding',
        data: payload,
        options: Options(
          headers: {
            'Authorization': 'Bearer ${session.accessToken}',
            'X-App-Variant': _config.variantString,
          },
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        widget.onComplete();
      } else {
        final errorMsg =
            response.data?['detail'] ?? 'Failed to complete onboarding.';
        throw Exception(errorMsg);
      }
    } on Object catch (e, stackTrace) {
      if (mounted) {
        ErrorHandler.handleError(
          e,
          stackTrace: stackTrace,
          customMessage: ErrorHandler.getFriendlyMessage(e),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFFD32F2F),
        content: Text(message, style: const TextStyle(color: Colors.white)),
      ),
    );
  }

  void _openImportDialog() {
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ImportCodeDialog(
        termsVersion: widget.termsVersion,
        onImportSuccess: widget.onComplete,
      ),
    ));
  }

  bool get _canSubmit {
    final isMec = _config.isFlavorVariant;
    final user = Supabase.instance.client.auth.currentUser;
    final hasVerifiedPhone =
        user?.phone != null &&
        user!.phone!.isNotEmpty &&
        user.phoneConfirmedAt != null;
    final hasPhone =
        hasVerifiedPhone || _phoneController.text.trim().isNotEmpty;
    if (isMec) {
      return _acceptedTerms && hasPhone;
    } else {
      return _nameController.text.trim().isNotEmpty &&
          _acceptedTerms &&
          hasPhone;
    }
  }

  Widget _buildTermsCheckbox() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF090D0F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _acceptedTerms
              ? const Color(0xFF0D9488)
              : const Color(0x1AFFFFFF),
        ),
      ),
      child: Row(
        children: [
          // Left column: checkbox only
          Theme(
            data: ThemeData(
              unselectedWidgetColor: const Color(0x66FFFFFF),
            ),
            child: Checkbox(
              value: _acceptedTerms,
              activeColor: const Color(0xFF0D9488),
              checkColor: Colors.white,
              onChanged: (val) {
                setState(() {
                  _acceptedTerms = val ?? false;
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          // Right column: terms acceptance text
          Expanded(
            child: GestureDetector(
              onTap: () {
                unawaited(Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => const LegalTermsPage(),
                  ),
                ));
              },
              child: RichText(
                text: const TextSpan(
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0x99FFFFFF),
                    height: 1.4,
                  ),
                  children: [
                    TextSpan(text: 'I agree to the '),
                    TextSpan(
                      text: 'Terms of Service',
                      style: TextStyle(
                        color: Color(0xFF0D9488),
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                    TextSpan(text: ' and '),
                    TextSpan(
                      text: 'Privacy Policy',
                      style: TextStyle(
                        color: Color(0xFF0D9488),
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                    TextSpan(text: '.'),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Build helpers ─────────────────────────────────────────────────────────

  static const _teal = Color(0xFFFF7597);
  static const _cardBg = Color(0xFF161B26);
  static const _pageBg = Color(0xFF0B0D13);
  static const _labelStyle = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.5,
    color: Color(0x99FFFFFF),
  );

  Widget _buildCard(Widget child) {
    return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0x1F0D9488)),
          ),
          child: child,
        )
        .animate()
        .fade(delay: 200.ms)
        .slideY(begin: 0.08, end: 0, duration: 420.ms);
  }

  Widget _buildAgeSlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('AGE', style: _labelStyle),
            Text(
              '$_selectedAge years old',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _teal,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: _teal,
            inactiveTrackColor: const Color(0x1AFFFFFF),
            thumbColor: Colors.white,
            overlayColor: const Color(0x260D9488),
            valueIndicatorColor: _teal,
            valueIndicatorTextStyle: const TextStyle(color: Colors.white),
          ),
          child: Slider(
            value: _selectedAge.toDouble(),
            min: 18,
            max: 27,
            divisions: 9,
            label: '$_selectedAge',
            onChanged: (v) => setState(() => _selectedAge = v.round()),
          ),
        ),
      ],
    );
  }

  // ── Nexus (main) card ─────────────────────────────────────────────────────

  Widget _buildNexusCard() {
    final user = Supabase.instance.client.auth.currentUser;
    final hasVerifiedPhone =
        user?.phone != null &&
        user!.phone!.isNotEmpty &&
        user.phoneConfirmedAt != null;
    return _buildCard(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('YOUR NAME', style: _labelStyle),
          const SizedBox(height: 8),
          TextFormField(
            controller: _nameController,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            decoration: InputDecoration(
              hintText: 'Enter your name',
              hintStyle: const TextStyle(color: Color(0x66FFFFFF)),
              filled: true,
              fillColor: _pageBg,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0x1F0D9488)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _teal),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFD32F2F)),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFD32F2F)),
              ),
            ),
            validator: (value) {
              if (value == null) return 'Name is required.';
              final trimmed = value.trim();
              if (trimmed.length < 4) {
                return 'Name must be at least 4 characters.';
              }
              if (RegExp(r'[^a-zA-Z\s\.]').hasMatch(trimmed)) {
                return 'Name can only contain letters, spaces, and dots.';
              }
              if (trimmed.contains('..')) {
                return 'Name cannot contain consecutive dots.';
              }
              if (RegExp('[a-zA-Z]').allMatches(trimmed).length < 2) {
                return 'Name must contain actual letters.';
              }
              return null;
            },
          ),
          const SizedBox(height: 20),
          if (hasVerifiedPhone) ...[
            const Text('VERIFIED PHONE', style: _labelStyle),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF0D9488).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x1F0D9488)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified_rounded, color: _teal, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      user.phone!,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
          ] else ...[
            const Text('PHONE NUMBER', style: _labelStyle),
            const SizedBox(height: 8),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              decoration: InputDecoration(
                hintText: '+911234567890',
                hintStyle: const TextStyle(color: Color(0x66FFFFFF)),
                filled: true,
                fillColor: _pageBg,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0x1F0D9488)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _teal),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFD32F2F)),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFD32F2F)),
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Phone number is required.';
                }
                final trimmed = value.trim();
                final phoneRegex = RegExp(r'^\+?[1-9]\d{7,14}$');
                if (!phoneRegex.hasMatch(trimmed)) {
                  return 'Enter a valid phone number (e.g. +1234567890 or 1234567890).';
                }
                return null;
              },
            ),
          ],
          const SizedBox(height: 20),
          _buildAgeSlider(),
          const SizedBox(height: 24),
          const Divider(color: Color(0x1AFFFFFF)),
          const SizedBox(height: 20),
          NexusOnboardingFields(
            onChanged: ({required lifestyle}) {
              setState(() {
                _lifestyle = lifestyle;
              });
            },
          ),
        ],
      ),
    );
  }

  // ── MEC (flavor) card ─────────────────────────────────────────────────────

  Widget _buildMECCard() {
    final googleName = _getGoogleName();
    final user = Supabase.instance.client.auth.currentUser;
    final hasVerifiedPhone =
        user?.phone != null &&
        user!.phone!.isNotEmpty &&
        user.phoneConfirmedAt != null;
    return _buildCard(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Read-only name from Google
          const Text('VERIFIED NAME', style: _labelStyle),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF0D9488).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x1F0D9488)),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified_rounded, color: _teal, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    googleName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Derived from your Google account - cannot be changed.',
            style: TextStyle(fontSize: 11, color: Color(0x66FFFFFF)),
          ),
          const SizedBox(height: 20),
          if (hasVerifiedPhone) ...[
            const Text('VERIFIED PHONE', style: _labelStyle),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF0D9488).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x1F0D9488)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified_rounded, color: _teal, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      user.phone!,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            const Text('PHONE NUMBER', style: _labelStyle),
            const SizedBox(height: 8),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              decoration: InputDecoration(
                hintText: '+911234567890',
                hintStyle: const TextStyle(color: Color(0x66FFFFFF)),
                filled: true,
                fillColor: _pageBg,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0x1F0D9488)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _teal),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFD32F2F)),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFD32F2F)),
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Phone number is required.';
                }
                final trimmed = value.trim();
                final phoneRegex = RegExp(r'^\+?[1-9]\d{7,14}$');
                if (!phoneRegex.hasMatch(trimmed)) {
                  return 'Enter a valid phone number (e.g. +1234567890 or 1234567890).';
                }
                return null;
              },
            ),
          ],
          const SizedBox(height: 20),
          _buildAgeSlider(),
          const SizedBox(height: 24),
          const Divider(color: Color(0x1AFFFFFF)),
          const SizedBox(height: 20),
          MECOnboardingFields(
            onChanged: ({required branch, required year}) {
              setState(() {
                _mecBranch = branch;
                _mecYear = year;
              });
            },
          ),
        ],
      ),
    );
  }

  // ── Main build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isMec = _config.isFlavorVariant;

    return Scaffold(
      backgroundColor: _pageBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Header ─────────────────────────────────────────────
                  Text(
                    isMec ? 'Welcome MEC' : 'NEXUS',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 4,
                      color: _teal,
                    ),
                  ).animate().fade().scale(duration: 400.ms),
                  const SizedBox(height: 8),
                  Text(
                    isMec ? 'Your campus profile' : 'Tell us about yourself',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: Colors.white,
                    ),
                  ).animate().fade(delay: 100.ms),
                  const SizedBox(height: 24),

                  // ── Variant-specific form card ────────────────---------
                  if (isMec) _buildMECCard() else _buildNexusCard(),
                  const SizedBox(height: 20),

                  // ── Terms Acceptance Checkbox ──────────────────────────
                  _buildTermsCheckbox(),
                  const SizedBox(height: 24),

                  // ── Submit button ──────────────────────────────────────
                  if (_isLoading)
                    const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(_teal),
                      ),
                    )
                  else
                    _SubmitButton(
                      label: 'Complete Setup',
                      onTap: _canSubmit ? _submitOnboarding : null,
                    ).animate().fade(delay: 300.ms),

                  // ── Import prompt (main nexus only) ────────────────────
                  if (!isMec) ...[
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: _openImportDialog,
                      child: const Text(
                        'Have a Nexus MEC account? Import your data →',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0x80FFFFFF),
                          decoration: TextDecoration.underline,
                          decorationColor: Color(0x40FFFFFF),
                        ),
                      ),
                    ).animate().fade(delay: 380.ms),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Reusable submit button ──────────────────────────────────────────────────

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDisabled = onTap == null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: isDisabled
                ? null
                : const [
                    BoxShadow(
                      color: Color(0x260D9488),
                      blurRadius: 18,
                      spreadRadius: 2,
                    ),
                  ],
            gradient: isDisabled
                ? null
                : const LinearGradient(
                    colors: [Color(0xFF0D9488), Color(0xFF0F766E)],
                  ),
            color: isDisabled ? const Color(0x1AFFFFFF) : null,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: isDisabled ? const Color(0x4DFFFFFF) : Colors.white,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
