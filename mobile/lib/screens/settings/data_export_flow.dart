import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/screens/settings/email_otp_reauth_dialog.dart';
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
  try {
    await createDio().post<Map<String, dynamic>>(
      '${AppConfig.current.backendUrl}/api/v1/account/export/otp/request',
      options: Options(
        headers: {'X-App-Variant': AppConfig.current.variantString},
      ),
    );
    if (!context.mounted) return;
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
