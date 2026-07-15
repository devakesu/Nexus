import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/screens/settings/email_otp_reauth_dialog.dart';
import 'package:nexus/theme/app_colors.dart';
import 'package:nexus/utils/error_handler.dart';
import 'package:nexus/utils/network_utils.dart';
import 'package:nexus/widgets/aesthetic_loaders.dart';
import 'package:nexus/widgets/nexus_toast.dart';
import 'package:path_provider/path_provider.dart';
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
                    color: AppColors.modeSettings.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.security_rounded,
                    color: AppColors.modeSettings,
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
                    text:
                        'The exported file contains a comprehensive, machine-readable copy of your personal data:\n\n',
                  ),
                  TextSpan(
                    text: '✓  Included: ',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold,
                      color: AppColors.ink,
                    ),
                  ),
                  const TextSpan(
                    text:
                        'Profile details, account history, active devices, matches and discovery history, chat metadata, reports and moderation logs (with reporter identities removed), support tickets, safety sessions, and connected Spotify playlists.\n\n',
                  ),
                  TextSpan(
                    text: '✗  Excluded: ',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold,
                      color: AppColors.ink,
                    ),
                  ),
                  const TextSpan(
                    text:
                        'Chat message contents (end-to-end encrypted and never stored on our servers), safety recording decryption keys, and internal system logs or moderation notes.\n\n',
                  ),
                  const TextSpan(
                    text:
                        'For your privacy and security, store this file securely and ',
                  ),
                  TextSpan(
                    text: 'NEVER share it with anyone else.',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
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
                          color: AppColors.modeSettings,
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Center(
                            child: Text(
                              'Start Export',
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
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const PopScope(
        canPop: false,
        child: Center(
          child: NexusOrbitLoader(size: 96),
        ),
      ),
    ),
  );

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
        resendUrl:
            '${AppConfig.current.backendUrl}/api/v1/account/export/otp/request',
        infoText:
            'This confirms the data export request came from you, not '
            'just from this device.',
        onVerificationSuccess: () {
          unawaited(_fetchAndShareExport(context));
        },
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
  // Show compiling loading indicator after OTP is verified
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const NexusOrbitLoader(size: 96),
              const SizedBox(height: 24),
              Material(
                color: Colors.transparent,
                child: Text(
                  'Compiling your data export...\nThis may take a few minutes, please wait.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  var loaderDismissed = false;
  try {
    final response = await createDio().post<Map<String, dynamic>>(
      '${AppConfig.current.backendUrl}/api/v1/account/export',
      options: Options(
        headers: {'X-App-Variant': AppConfig.current.variantString},
      ),
    );
    final data = response.data;

    if (context.mounted) {
      Navigator.of(context).pop(); // Dismiss loading indicator
      loaderDismissed = true;
    }

    if (data == null) throw Exception('Export returned no data.');

    final jsonBytes = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(data),
    );
    final dateStamp = DateTime.now().toIso8601String().split('T').first;
    final fileName = 'nexus-data-export-$dateStamp.json';

    if (!context.mounted) return;

    final action = await showDialog<String>(
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
                      color: AppColors.modeSettings.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.download_done_rounded,
                      color: AppColors.modeSettings,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Export File Ready',
                      style: GoogleFonts.manrope(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Your personal data has been compiled successfully. Choose how you would like to receive the file.',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppColors.inkMuted,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => Navigator.of(dialogContext).pop('download'),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.canvas,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.borderNeutral),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.file_download_rounded,
                              color: AppColors.modeSettings,
                              size: 28,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Save to Device',
                              style: GoogleFonts.manrope(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: InkWell(
                      onTap: () => Navigator.of(dialogContext).pop('share'),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.canvas,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.borderNeutral),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.share_rounded,
                              color: AppColors.pulsarPink,
                              size: 28,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Share Directly',
                              style: GoogleFonts.manrope(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
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
            ],
          ),
        ),
      ),
    );

    if (action == 'share') {
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              jsonBytes,
              name: fileName,
              mimeType: 'application/json',
            ),
          ],
          subject: 'Your Nexus data export',
        ),
      );
    } else if (action == 'download') {
      final directory =
          await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
      await directory.create(recursive: true);
      final file = File('${directory.path}/$fileName');
      await file.writeAsBytes(jsonBytes);
      if (context.mounted) {
        NexusToast.show(
          context,
          'Saved to Downloads: ${directory.path}/$fileName',
        );
      }
    }
  } on Object catch (e, stackTrace) {
    if (context.mounted) {
      if (!loaderDismissed) {
        Navigator.of(context).pop(); // Dismiss loading indicator
      }
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
