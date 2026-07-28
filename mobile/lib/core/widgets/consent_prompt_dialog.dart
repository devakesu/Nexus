import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/config/app_config.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/core/utils/consent_cache_manager.dart';
import 'package:nexus/core/utils/error_handler.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:nexus/core/widgets/aesthetic_loaders.dart';
import 'package:nexus/core/widgets/nexus_toast.dart';

enum ConsentPromptType {
  safetyData,
  specialCategory,
}

Future<bool> grantSafetyDataConsent(BuildContext context) async {
  try {
    await createDio().post<Map<String, dynamic>>(
      '${AppConfig.current.backendUrl}/api/v1/auth/accept-terms',
      data: {
        'terms_version': ConsentCacheManager.currentTermsVersion,
        'general_accepted': true,
        'special_category_accepted': true,
        'safety_data_accepted': true,
      },
      options: Options(
        headers: {'X-App-Variant': AppConfig.current.variantString},
      ),
    );
    ConsentCacheManager.safetyConsentGranted = true;
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

Future<bool> grantSpecialCategoryConsent(BuildContext context) async {
  try {
    await createDio().post<Map<String, dynamic>>(
      '${AppConfig.current.backendUrl}/api/v1/auth/accept-terms',
      data: {
        'terms_version': ConsentCacheManager.currentTermsVersion,
        'general_accepted': true,
        'special_category_accepted': true,
      },
      options: Options(
        headers: {'X-App-Variant': AppConfig.current.variantString},
      ),
    );
    ConsentCacheManager.specialCategoryConsentGranted = true;
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
      customMessage: 'Failed to submit consent.',
      showUi: false,
    );
    return false;
  }
}

class GenericConsentPromptCard extends StatefulWidget {
  const GenericConsentPromptCard({
    required this.type,
    required this.onGranted,
    super.key,
  });

  final ConsentPromptType type;
  final VoidCallback onGranted;

  @override
  State<GenericConsentPromptCard> createState() =>
      _GenericConsentPromptCardState();
}

class _GenericConsentPromptCardState extends State<GenericConsentPromptCard> {
  bool _isSubmitting = false;

  bool get _isSafety => widget.type == ConsentPromptType.safetyData;

  Color get _accentColor =>
      _isSafety ? AppColors.safetyBlue : AppColors.modeDating;

  IconData get _icon =>
      _isSafety ? LucideIcons.shieldAlert : LucideIcons.heartHandshake;

  String get _description => _isSafety
      ? 'Meetup Safety & SOS features process the following data under your control:\n\n'
            '• Location & check-in data - to share your whereabouts with trusted contacts\n'
            '• Battery level - to determine SOS thresholds\n'
            '• Camera & microphone - only when you start a Digital Witness recording; never accessed passively\n\n'
            'Under GDPR, processing this data requires your explicit consent. '
            'This is entirely optional - Nexus works fully without it, and you can withdraw consent at any time from Privacy Settings.'
      : 'Displaying orientation and religious beliefs on your profile requires processing under special category protection.\n\n'
            'Under GDPR, this requires your explicit consent. This is entirely optional - Nexus works fully without it, '
            'and you can withdraw consent at any time from Privacy Settings.';

  Future<void> _handleAccept() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    final granted = _isSafety
        ? await grantSafetyDataConsent(context)
        : await grantSpecialCategoryConsent(context);
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    if (granted) widget.onGranted();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _accentColor.withValues(alpha: 0.35)),
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
          Row(
            children: [
              Icon(
                _icon,
                color: _accentColor,
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
          Text(
            _description,
            style: GoogleFonts.inter(
              fontSize: 12.5,
              color: AppColors.inkMuted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
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
                    color: _accentColor,
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
                      color: _accentColor,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    LucideIcons.arrowUpRight,
                    size: 12,
                    color: _accentColor,
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

class SafetyConsentPromptCard extends StatelessWidget {
  const SafetyConsentPromptCard({required this.onGranted, super.key});
  final VoidCallback onGranted;

  @override
  Widget build(BuildContext context) {
    return GenericConsentPromptCard(
      type: ConsentPromptType.safetyData,
      onGranted: onGranted,
    );
  }
}

class SpecialCategoryConsentPromptCard extends StatelessWidget {
  const SpecialCategoryConsentPromptCard({required this.onGranted, super.key});
  final VoidCallback onGranted;

  @override
  Widget build(BuildContext context) {
    return GenericConsentPromptCard(
      type: ConsentPromptType.specialCategory,
      onGranted: onGranted,
    );
  }
}
