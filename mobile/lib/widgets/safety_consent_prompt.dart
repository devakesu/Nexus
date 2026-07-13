import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/theme/app_colors.dart';
import 'package:nexus/utils/error_handler.dart';
import 'package:nexus/utils/network_utils.dart';
import 'package:nexus/utils/safety_consent_cache.dart';
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

/// Inline "locked" card shown in place of a safety feature (Safety Center
/// sections, the Meetup Safety event-planner toggle) when the user hasn't
/// consented to safety-data processing yet. onGranted fires only after a
/// successful consent submission, letting the caller unlock in place.
class SafetyConsentPromptCard extends StatefulWidget {
  const SafetyConsentPromptCard({
    required this.onGranted,
    this.message =
        'Turn on Meetup Safety & SOS data processing to use this feature.',
    super.key,
  });

  final VoidCallback onGranted;
  final String message;

  @override
  State<SafetyConsentPromptCard> createState() =>
      _SafetyConsentPromptCardState();
}

class _SafetyConsentPromptCardState extends State<SafetyConsentPromptCard> {
  bool _isSubmitting = false;

  Future<void> _handleTap() async {
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.safetyBlue.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.safetyBlue.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                  'Safety features are off',
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            widget.message,
            style: GoogleFonts.inter(
              fontSize: 12.5,
              color: AppColors.inkMuted,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 42),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _handleTap,
                  borderRadius: BorderRadius.circular(10),
                  child: Ink(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: AppColors.safetyBlue,
                    ),
                    child: Center(
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : Text(
                              'Enable Safety Features',
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
        ],
      ),
    );
  }
}
