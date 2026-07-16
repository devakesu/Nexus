import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/theme/app_colors.dart';
import 'package:nexus/utils/error_handler.dart';
import 'package:nexus/utils/network_utils.dart';
import 'package:nexus/utils/safety_consent_cache.dart';
import 'package:nexus/widgets/aesthetic_loaders.dart';
import 'package:nexus/widgets/nexus_toast.dart';

/// Submits safety-data consent inline (without navigating away) - re-affirms
/// the two mandatory categories too, since POST /api/v1/auth/accept-terms
/// always requires both to be true (the caller only ever reaches this
/// prompt after already clearing TermsConsentPage's mandatory gate, so this
/// is a safe re-affirmation, not a new ask). Updates SafetyConsentCache on
/// success so the calling widget can rebuild unlocked immediately.
Future<bool> grantSafetyDataConsent(BuildContext context) async {
  try {
    await createDio().post<Map<String, dynamic>>(
      '${AppConfig.current.backendUrl}/api/v1/auth/accept-terms',
      data: {
        'terms_version': SafetyConsentCache.currentTermsVersion,
        'general_accepted': true,
        'special_category_accepted': true,
        'safety_data_accepted': true,
      },
      options: Options(
        headers: {'X-App-Variant': AppConfig.current.variantString},
      ),
    );
    SafetyConsentCache.isGranted = true;
    return true;
  } on Object catch (e, stackTrace) {
    if (context.mounted) {
      NexusToast.show(
        context,
        ErrorHandler.getFriendlyMessage(e),
        type: NexusToastType.error,
      );
    }
    ErrorHandler.handleError(
      e,
      stackTrace: stackTrace,
      customMessage: 'Failed to enable safety features.',
      showUi: false,
    );
    return false;
  }
}

/// Inline consent prompt shown when a user tries to access a safety feature
/// (Safety Center sections, Meetup Safety event-planner) without having
/// consented to safety-data processing. onGranted fires only after a
/// successful consent submission, letting the caller unlock in place.
///
/// Location and check-in data are personal data under GDPR; processing
/// requires consent. The card mirrors the language and structure of
/// _ConsentTile in terms_consent_screen.dart for consistent framing.
class SafetyConsentPromptCard extends StatefulWidget {
  const SafetyConsentPromptCard({
    required this.onGranted,
    super.key,
  });

  final VoidCallback onGranted;

  @override
  State<SafetyConsentPromptCard> createState() =>
      _SafetyConsentPromptCardState();
}

class _SafetyConsentPromptCardState extends State<SafetyConsentPromptCard> {
  bool _isSubmitting = false;

  Future<void> _handleAccept() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    final granted = await grantSafetyDataConsent(context);
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    if (granted) widget.onGranted();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        // Solid surface so the card is legible over the transparent bottom-
        // sheet scrim; the safety-blue tint is kept via the border.
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.safetyBlue.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Row(
            children: [
              const Icon(
                LucideIcons.shieldAlert,
                color: AppColors.safetyBlue,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Consent required',
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
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

          const SizedBox(height: 10),

          // ── Legal disclosure ─────────────────────────────────────────────
          Text(
            'Meetup Safety & SOS features process the following data '
            'under your control:\n\n'
            '• Location & check-in data - to share your whereabouts with '
            'trusted contacts\n'
            '• Battery level - to determine SOS thresholds\n'
            '• Camera & microphone - only when you start a Digital Witness '
            'recording; never accessed passively\n\n'
            'Under GDPR, processing this data requires your explicit consent. '
            'This is entirely optional - Nexus works fully without it, and '
            'you can withdraw consent at any time from Privacy Settings.',
            style: GoogleFonts.inter(
              fontSize: 12.5,
              color: AppColors.inkMuted,
              height: 1.5,
            ),
          ),

          const SizedBox(height: 16),

          // ── Accept button ────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _handleAccept,
                borderRadius: BorderRadius.circular(10),
                child: Ink(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: AppColors.safetyBlue,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    child: Center(
                      child: _isSubmitting
                          ? const NexusOrbitLoader(size: 18)
                          : Text(
                              'I Accept',
                              style: GoogleFonts.manrope(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 10),

          // ── Privacy policy link ──────────────────────────────────────────
          Center(
            child: GestureDetector(
              onTap: () => context.push<void>('/legal/terms'),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Read our Terms & Privacy Policy',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.safetyBlue,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(
                    LucideIcons.arrowUpRight,
                    size: 12,
                    color: AppColors.safetyBlue,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
