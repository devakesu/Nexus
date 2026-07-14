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
  bool _specialCategoryAccepted = false;
  late bool _safetyDataAccepted = widget.initialSafetyDataAccepted;
  bool _isSubmitting = false;

  static const Color _accent = AppColors.primaryTeal;

  bool get _canContinue => _generalAccepted;

  Future<void> _submit() async {
    if (!_canContinue || _isSubmitting) return;
    setState(() => _isSubmitting = true);
    try {
      await createDio().post<Map<String, dynamic>>(
        '${AppConfig.current.backendUrl}/api/v1/auth/accept-terms',
        data: {
          'terms_version': widget.currentTermsVersion,
          'general_accepted': _generalAccepted,
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
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.isVersionBump
                ? 'Our terms have changed'
                : 'Before you continue',
            style: GoogleFonts.manrope(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.isVersionBump
                ? "We've updated our Terms of Service and Privacy Policy. "
                      'Please review and accept to keep using Nexus.'
                : 'Review and accept the following to start using Nexus.',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: AppColors.inkMuted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),
          _ConsentTile(
            accent: _accent,
            required: true,
            value: _generalAccepted,
            onChanged: (v) => setState(() => _generalAccepted = v),
            title: 'Terms of Service & Privacy Policy',
            description: 'How Nexus works, and how we handle your data.',
            linkLabel: 'Read the Terms & Privacy Policy',
            onLinkTap: () => unawaited(context.push<void>('/legal/terms')),
          ),
          const SizedBox(height: 14),
          _ConsentTile(
            accent: _accent,
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
          ),
          const SizedBox(height: 14),
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
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _canContinue && !_isSubmitting ? _submit : null,
                  borderRadius: BorderRadius.circular(14),
                  child: Ink(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: _canContinue && !_isSubmitting
                          ? _accent
                          : AppColors.inkFaint.withValues(alpha: 0.2),
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
              ),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 4,
              children: [
                TextButton(
                  onPressed: _isSubmitting
                      ? null
                      : () => unawaited(startDataExport(context)),
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
                  style: GoogleFonts.manrope(color: AppColors.inkFaint),
                ),
                TextButton(
                  onPressed: _isSubmitting ? null : _declineAndDelete,
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
    this.linkLabel,
    this.onLinkTap,
  });

  final Color accent;
  final bool required;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String title;
  final String description;
  final String? linkLabel;
  final VoidCallback? onLinkTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: value
              ? accent.withValues(alpha: 0.4)
              : AppColors.borderNeutral,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: value,
            activeColor: accent,
            checkColor: Colors.white,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: (v) => onChanged(v ?? false),
          ),
          const SizedBox(width: 4),
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
                    if (!required)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.inkFaint.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(
                          'Optional',
                          style: GoogleFonts.manrope(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.inkMuted,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    color: AppColors.inkMuted,
                    height: 1.45,
                  ),
                ),
                if (linkLabel != null) ...[
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: onLinkTap,
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
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(LucideIcons.arrowUpRight, size: 12, color: accent),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
