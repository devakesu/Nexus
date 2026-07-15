import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/screens/settings/data_export_flow.dart';
import 'package:nexus/theme/app_colors.dart';
import 'package:nexus/utils/error_handler.dart';
import 'package:nexus/utils/network_utils.dart';
import 'package:nexus/widgets/aesthetic_loaders.dart';
import 'package:nexus/widgets/nexus_toast.dart';
import 'package:nexus/widgets/scale_pressable.dart';

/// Itemized consent screen - three separate checkboxes rather than one
/// bundled "I agree" tick, per the DPDP/GDPR compliance plan. Only general
/// consent is mandatory (declining routes to account deletion).
/// Special-category (sexual orientation / religious belief) and
/// safety-data consent are both optional: sexual orientation and religion
/// are themselves optional/skippable profile fields, so declining that
/// consent only gates entering a real value in those two fields
/// (profile_tab.dart prompts inline if the user tries); safety-data
/// consent only gates the Meetup Safety/SOS/Digital Witness surfaces.
/// Neither optional decline blocks general app access.
///
/// Reused in two contexts, both supplied by the caller (this widget itself
/// has no Scaffold/Dialog chrome so it fits either):
///   - First-time, right after onboarding: AuthGate renders it directly
///     (no route), isVersionBump=false.
///   - Version bump for an existing user: AuthGate renders it directly at
///     cold-start, or shows it inside a modal Dialog when detected
///     mid-session via the app-resumed lifecycle hook, isVersionBump=true.
class TermsConsentPage extends StatefulWidget {
  const TermsConsentPage({
    required this.currentTermsVersion,
    required this.isVersionBump,
    required this.onConsentRecorded,
    this.initialSafetyDataAccepted = false,
    super.key,
  });

  final String currentTermsVersion;
  final bool isVersionBump;
  final FutureOr<void> Function() onConsentRecorded;
  final bool initialSafetyDataAccepted;

  @override
  State<TermsConsentPage> createState() => _TermsConsentPageState();
}

class _TermsConsentPageState extends State<TermsConsentPage> {
  bool _generalAccepted = false;
  bool _guidelinesAccepted = false;
  bool _specialCategoryAccepted = false;
  late bool _safetyDataAccepted = widget.initialSafetyDataAccepted;
  bool _isSubmitting = false;

  bool get _canContinue => _generalAccepted && _guidelinesAccepted;

  Future<void> _submit() async {
    if (!_canContinue || _isSubmitting) return;
    setState(() => _isSubmitting = true);
    try {
      await createDio().post<Map<String, dynamic>>(
        '${AppConfig.current.backendUrl}/api/v1/auth/accept-terms',
        data: {
          'terms_version': widget.currentTermsVersion,
          'general_accepted': _generalAccepted,
          'community_guidelines_accepted': _guidelinesAccepted,
          'special_category_accepted': _specialCategoryAccepted,
          'safety_data_accepted': _safetyDataAccepted,
        },
        options: Options(
          headers: {'X-App-Variant': AppConfig.current.variantString},
        ),
      );
      await widget.onConsentRecorded();
    } on Object catch (e, stackTrace) {
      if (mounted) {
        NexusToast.show(
          context,
          ErrorHandler.getFriendlyMessage(e),
          type: NexusToastType.error,
        );
        ErrorHandler.handleError(
          e,
          stackTrace: stackTrace,
          customMessage: 'Failed to record consent.',
          showUi: false,
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _declineAndDelete() {
    unawaited(context.push<void>('/settings/delete-account'));
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Elegant Header Block
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.pulsarPink.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  LucideIcons.shieldCheck,
                  color: AppColors.pulsarPink,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'NEXUS',
                    style: GoogleFonts.orbitron(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      color: AppColors.pulsarPink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Terms & Policy v${widget.currentTermsVersion}',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.inkMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            widget.isVersionBump
                ? 'Our terms have changed'
                : 'Before you continue',
            style: GoogleFonts.manrope(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.isVersionBump
                ? "We've updated our Terms of Service, Privacy Policy, and Community Guidelines. Please review and accept to keep using Nexus."
                : 'Review and accept the following to start using Nexus.',
            style: GoogleFonts.inter(
              fontSize: 13.5,
              color: AppColors.inkMuted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),

          // Categories List
          _ConsentTile(
            accent: AppColors.pulsarPink,
            required: true,
            value: _generalAccepted,
            onChanged: (v) => setState(() => _generalAccepted = v),
            title: 'Terms of Service & Privacy Policy',
            description: 'How Nexus works, and how we handle your data.',
            icon: LucideIcons.fileText,
            linkLabel: 'Read Terms & Privacy Policy',
            onLinkTap: () => unawaited(context.push<void>('/legal/terms')),
          ),
          const SizedBox(height: 12),
          _ConsentTile(
            accent: AppColors.modeSettings,
            required: true,
            value: _guidelinesAccepted,
            onChanged: (v) => setState(() => _guidelinesAccepted = v),
            title: 'Community Guidelines',
            description:
                'Rules for respectful behaviour on Nexus — covering '
                'harassment, safety, prohibited content, and how we '
                'enforce them. Required to use the app.',
            icon: LucideIcons.bookOpen,
            linkLabel: 'Read Community Guidelines',
            onLinkTap: () =>
                unawaited(context.push<void>('/settings/community-guidelines')),
          ),
          const SizedBox(height: 12),
          _ConsentTile(
            accent: AppColors.primaryTeal,
            required: false,
            value: _specialCategoryAccepted,
            onChanged: (v) => setState(() => _specialCategoryAccepted = v),
            title: 'Sexual orientation & religious belief data',
            description:
                'Optional - these fields are always skippable in your '
                'profile. GDPR treats this as sensitive data, so we ask '
                'separately: if you leave this off, you can still use '
                "Nexus fully, you just won't be able to fill in sexual "
                'orientation or religious belief on your profile until you '
                'turn it on (any time, from Profile).',
            icon: LucideIcons.userRound,
          ),
          const SizedBox(height: 12),
          _ConsentTile(
            accent: AppColors.safetyBlue,
            required: false,
            value: _safetyDataAccepted,
            onChanged: (v) => setState(() => _safetyDataAccepted = v),
            title: 'Meetup Safety & SOS data',
            description:
                'Location and check-in data for Safety Center features (trusted '
                'contacts, check-ins, SOS, Digital Witness). Optional - you can '
                'use Nexus without it, and turn it on later from Safety Center.',
            icon: LucideIcons.shieldCheck,
          ),
          const SizedBox(height: 24),

          // Main Submit Button
          ScalePressable(
            enabled: _canContinue && !_isSubmitting,
            onTap: _submit,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              width: double.infinity,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: _canContinue && !_isSubmitting
                    ? const LinearGradient(
                        colors: [
                          AppColors.pulsarPink,
                          Color(0xFFE04B76),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: _canContinue && !_isSubmitting
                    ? null
                    : AppColors.inkFaint.withValues(alpha: 0.15),
                boxShadow: _canContinue && !_isSubmitting
                    ? [
                        BoxShadow(
                          color: AppColors.pulsarPink.withValues(alpha: 0.25),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: _isSubmitting
                    ? const NexusOrbitLoader(size: 22)
                    : Text(
                        'Continue',
                        style: GoogleFonts.manrope(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: _canContinue
                              ? Colors.white
                              : AppColors.inkFaint,
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Secondary Actions
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton(
                  onPressed: _isSubmitting
                      ? null
                      : () => unawaited(startDataExport(context)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Export My Data',
                    style: GoogleFonts.manrope(
                      color: AppColors.inkMuted,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
                Text(
                  '·',
                  style: GoogleFonts.manrope(
                    color: AppColors.inkFaint,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton(
                  onPressed: _isSubmitting ? null : _declineAndDelete,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Decline & Delete My Account',
                    style: GoogleFonts.manrope(
                      color: AppColors.error,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConsentTile extends StatelessWidget {
  const _ConsentTile({
    required this.accent,
    required this.required,
    required this.value,
    required this.onChanged,
    required this.title,
    required this.description,
    required this.icon,
    this.linkLabel,
    this.onLinkTap,
  });

  final Color accent;
  final bool required;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String title;
  final String description;
  final IconData icon;
  final String? linkLabel;
  final VoidCallback? onLinkTap;

  @override
  Widget build(BuildContext context) {
    final cardBg = value ? accent.withValues(alpha: 0.03) : Colors.white;

    return ScalePressable(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: value
                ? accent.withValues(alpha: 0.4)
                : AppColors.borderNeutral,
            width: value ? 1.5 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left column: checkbox on top, icon badge below
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _CustomCheckbox(
                  value: value,
                  accentColor: accent,
                ),
                const SizedBox(height: 16),
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Icon(
                      icon,
                      color: accent,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            // Details Column
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: GoogleFonts.manrope(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Required / Optional Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: required
                              ? AppColors.pulsarPink.withValues(alpha: 0.1)
                              : AppColors.inkFaint.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(
                          required ? 'Required' : 'Optional',
                          style: GoogleFonts.manrope(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: required
                                ? AppColors.pulsarPink
                                : AppColors.inkMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      color: AppColors.inkMuted,
                      height: 1.45,
                    ),
                  ),
                  if (linkLabel != null) ...[
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: onLinkTap,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              linkLabel!,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: accent,
                                decoration: TextDecoration.underline,
                                decorationColor: accent,
                              ),
                            ),
                            const SizedBox(width: 3),
                            Icon(
                              LucideIcons.arrowUpRight,
                              size: 12,
                              color: accent,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomCheckbox extends StatelessWidget {
  const _CustomCheckbox({
    required this.value,
    required this.accentColor,
  });

  final bool value;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: value ? accentColor : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: value ? accentColor : AppColors.borderNeutral,
          width: 2,
        ),
      ),
      child: AnimatedScale(
        scale: value ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutBack,
        child: const Icon(
          Icons.check_rounded,
          size: 15,
          color: Colors.white,
        ),
      ),
    );
  }
}
