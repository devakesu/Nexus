import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/theme/app_colors.dart';
import 'package:nexus/utils/error_handler.dart';
import 'package:nexus/utils/network_utils.dart';
import 'package:nexus/utils/special_category_consent_cache.dart';
import 'package:nexus/widgets/aesthetic_loaders.dart';
import 'package:nexus/widgets/nexus_toast.dart';

/// Submits special-category consent inline (without navigating away) -
/// re-affirms general consent too, since POST /api/v1/auth/accept-terms
/// requires it (the caller only ever reaches this prompt after already
/// clearing TermsConsentPage's mandatory gate, so this is a safe
/// re-affirmation, not a new ask). Omits safety_data_accepted so that
/// category is left untouched. Mirrors grantSafetyDataConsent exactly.
Future<bool> grantSpecialCategoryConsent(BuildContext context) async {
  try {
    await createDio().post<Map<String, dynamic>>(
      '${AppConfig.current.backendUrl}/api/v1/auth/accept-terms',
      data: {
        'terms_version': SpecialCategoryConsentCache.currentTermsVersion,
        'general_accepted': true,
        'special_category_accepted': true,
      },
      options: Options(
        headers: {'X-App-Variant': AppConfig.current.variantString},
      ),
    );
    SpecialCategoryConsentCache.isGranted = true;
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
      customMessage: 'Failed to enable special-category data.',
      showUi: false,
    );
    return false;
  }
}

/// Inline GDPR consent prompt shown in a bottom sheet before letting a user
/// set display_sexuality/religious_beliefs to a real disclosed value for the
/// first time, or before unlocking these fields in Privacy Settings.
/// onGranted fires only after a successful consent submission.
///
/// Under GDPR Article 9, sexual orientation and religious belief are
/// special-category data requiring explicit, separate consent. The card
/// mirrors the language and structure of _ConsentTile in
/// terms_consent_screen.dart so users see consistent framing.
class SpecialCategoryConsentPromptCard extends StatefulWidget {
  const SpecialCategoryConsentPromptCard({
    required this.onGranted,
    super.key,
  });

  final VoidCallback onGranted;

  @override
  State<SpecialCategoryConsentPromptCard> createState() =>
      _SpecialCategoryConsentPromptCardState();
}

class _SpecialCategoryConsentPromptCardState
    extends State<SpecialCategoryConsentPromptCard> {
  bool _isSubmitting = false;

  Future<void> _handleAccept() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    final granted = await grantSpecialCategoryConsent(context);
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
        // sheet scrim; the teal tint is kept via the border.
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primaryTeal.withValues(alpha: 0.35),
        ),
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
                LucideIcons.shieldCheck,
                color: AppColors.primaryTeal,
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

          // ── GDPR disclosure ─────────────────────────────────────────────
          Text(
            'Sexual orientation and religious belief are '
            'special-category data under GDPR (Article 9). Nexus '
            'needs your explicit consent to store and use them. '
            'This is entirely optional - Nexus works fully without '
            'it, and you can withdraw consent at any time from '
            'Privacy Settings.',
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
                    color: AppColors.primaryTeal,
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
              onTap: () => context.push<void>('/legal'),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Read our Terms & Privacy Policy',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryTeal,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(
                    LucideIcons.arrowUpRight,
                    size: 12,
                    color: AppColors.primaryTeal,
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
