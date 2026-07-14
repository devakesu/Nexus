import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/screens/settings/email_otp_reauth_dialog.dart';
import 'package:nexus/theme/app_colors.dart';
import 'package:nexus/utils/error_handler.dart';
import 'package:nexus/utils/network_utils.dart';
import 'package:nexus/widgets/nexus_toast.dart';
import 'package:share_plus/share_plus.dart';

/// Entry point for "Export My Data" (Settings' Account Actions section, and
/// TermsConsentPage's decline path) - OTP-reauth via the same
/// EmailOtpReauthDialog account deletion uses, then a synchronous export
/// fetch (app/api/export.py -> app/db/export.py) handed directly to the
/// native OS share/save sheet as an in-memory JSON file - no local file
/// write needed, XFile.fromData shares straight from bytes.
Future<void> startDataExport(BuildContext context) async {
  final proceed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.security_rounded,
                    color: Colors.orange,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Export Personal Data',
                    style: GoogleFonts.manrope(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text.rich(
              TextSpan(
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppColors.inkMuted,
                  height: 1.5,
                ),
                children: [
                  const TextSpan(
                    text: 'The exported file will contain a complete, readable copy of your personal data:\n\n'
                        '✓  Included: Profile details, account history, active devices, matches/discovery actions, chat metadata, reports/moderation history (reporter IDs removed), feedback tickets, safety sessions/contacts, and Spotify playlists.\n\n'
                        '✗  Excluded: Chat message contents (end-to-end encrypted, never stored on server), safety recording decryption keys, and internal moderation notes.\n\n'
                        'For your privacy and security, keep this file safe and ',
                  ),
                  TextSpan(
                    text: 'NEVER share it with anyone else.',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      color: AppColors.error,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.manrope(
                        fontWeight: FontWeight.w700,
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => Navigator.of(dialogContext).pop(true),
                      borderRadius: BorderRadius.circular(14),
                      child: Ink(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: const Color(0xFF3B82F6),
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Center(
                            child: Text(
                              'Send OTP Code',
                              style: GoogleFonts.manrope(
                                fontSize: 14,
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
          ],
        ),
      ),
    ),
  );

  if (proceed != true) return;
  if (!context.mounted) return;

  // Show loading indicator dialog to prevent the screen from locking without feedback
  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => const PopScope(
      canPop: false,
      child: Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFEF4444)),
        ),
      ),
    ),
  ));

  try {
    await createDio().post<Map<String, dynamic>>(
      '${AppConfig.current.backendUrl}/api/v1/account/export/otp/request',
      options: Options(
        headers: {'X-App-Variant': AppConfig.current.variantString},
      ),
    );
    if (!context.mounted) return;
    Navigator.of(context).pop(); // Dismiss loading indicator

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => EmailOtpReauthDialog(
        verifyUrl:
            '${AppConfig.current.backendUrl}/api/v1/account/export/otp/verify',
        infoText:
            'This confirms the data export request came from you, not '
            'just from this device.',
        onVerificationSuccess: () => _fetchAndShareExport(dialogContext),
      ),
    );
  } on Object catch (e, stackTrace) {
    if (context.mounted) {
      Navigator.of(context).pop(); // Dismiss loading indicator
      NexusToast.show(
        context,
        ErrorHandler.getFriendlyMessage(e),
        type: NexusToastType.error,
      );
      ErrorHandler.handleError(
        e,
        stackTrace: stackTrace,
        customMessage: 'Failed to send data export verification code.',
        showUi: false,
      );
    }
  }
}

Future<void> _fetchAndShareExport(BuildContext context) async {
  try {
    final response = await createDio().post<Map<String, dynamic>>(
      '${AppConfig.current.backendUrl}/api/v1/account/export',
      options: Options(
        headers: {'X-App-Variant': AppConfig.current.variantString},
      ),
    );
    final data = response.data;
    if (data == null) throw Exception('Export returned no data.');

    final jsonBytes = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(data),
    );
    final dateStamp = DateTime.now().toIso8601String().split('T').first;

    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            jsonBytes,
            name: 'nexus-data-export-$dateStamp.json',
            mimeType: 'application/json',
          ),
        ],
        subject: 'Your Nexus data export',
      ),
    );
  } on Object catch (e, stackTrace) {
    if (context.mounted) {
      NexusToast.show(
        context,
        ErrorHandler.getFriendlyMessage(e),
        type: NexusToastType.error,
      );
      ErrorHandler.handleError(
        e,
        stackTrace: stackTrace,
        customMessage: 'Failed to generate data export.',
        showUi: false,
      );
    }
  }
}
