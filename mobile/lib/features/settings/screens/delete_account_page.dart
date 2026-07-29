import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/config/app_config.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/core/utils/error_handler.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:nexus/core/widgets/aesthetic_loaders.dart';
import 'package:nexus/core/widgets/nexus_toast.dart';
import 'package:nexus/features/security_signal/services/signal/signal_key_service.dart';
import 'package:nexus/features/settings/screens/data_export_flow.dart';
import 'package:nexus/features/settings/widgets/email_otp_reauth_dialog.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Full-page destructive flow for self-serve account deletion - the first
/// non-AlertDialog destructive flow in the app, since the DPDP-style
/// disclosure content here doesn't fit a dialog. Uses AppColors.error as
/// the sole accent throughout (never the Safety Duo or modeSettings) per
/// DESIGN.md's One Signal Rule - this is a danger surface, not a safety one.
class DeleteAccountPage extends StatefulWidget {
  const DeleteAccountPage({super.key});

  @override
  State<DeleteAccountPage> createState() => _DeleteAccountPageState();
}

class _DeleteAccountPageState extends State<DeleteAccountPage> {
  final _confirmController = TextEditingController();
  bool _isSendingCode = false;
  bool _isDeleting = false;

  int _gracePeriodDays = 14;
  int _blocklistCooldownDays = 30;
  int _longTailPurgeDays = 1095;
  int _safetyEvidenceActiveRetentionDays = 365;
  int _safetyDataLegalHoldDays = 180;

  @override
  void initState() {
    super.initState();
    _confirmController.addListener(_updateConfirmState);
    unawaited(_loadSettings());
  }

  Future<void> _loadSettings() async {
    try {
      final response = await createDio().get<Map<String, dynamic>>(
        '${AppConfig.current.backendUrl}/api/v1/account/deletion/settings',
      );
      final data = response.data;
      if (data != null && mounted) {
        setState(() {
          _gracePeriodDays = data['grace_period_days'] as int? ?? 14;
          _blocklistCooldownDays =
              data['blocklist_cooldown_days'] as int? ?? 30;
          _longTailPurgeDays = data['long_tail_purge_days'] as int? ?? 1095;
          _safetyEvidenceActiveRetentionDays =
              data['safety_evidence_active_retention_days'] as int? ?? 365;
          _safetyDataLegalHoldDays =
              data['safety_data_legal_hold_days'] as int? ?? 180;
        });
      }
    } on Object catch (e, stackTrace) {
      // Gracefully fallback to defaults if request fails
      ErrorHandler.handleError(
        e,
        stackTrace: stackTrace,
        level: ErrorLevel.warning,
        showUi: false,
        customMessage: 'Failed to load account deletion settings',
      );
    }
  }

  String _formatLongTailPurge(int days) {
    if (days % 365 == 0) {
      final years = days ~/ 365;
      return '$years year${years == 1 ? '' : 's'}';
    }
    return '$days days';
  }

  @override
  void dispose() {
    _confirmController
      ..removeListener(_updateConfirmState)
      ..dispose();
    super.dispose();
  }

  void _updateConfirmState() {
    if (mounted) setState(() {});
  }

  bool get _isConfirmed =>
      _confirmController.text.trim().toUpperCase() == 'DELETE';

  Future<void> _beginDeletion() async {
    if (!_isConfirmed || _isSendingCode || _isDeleting) return;

    setState(() => _isSendingCode = true);
    try {
      await createDio().post<Map<String, dynamic>>(
        '${AppConfig.current.backendUrl}/api/v1/account/deletion/otp/request',
        options: Options(
          headers: {'X-App-Variant': AppConfig.current.variantString},
        ),
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => EmailOtpReauthDialog(
          verifyUrl:
              '${AppConfig.current.backendUrl}/api/v1/account/deletion/otp/verify',
          resendUrl:
              '${AppConfig.current.backendUrl}/api/v1/account/deletion/otp/request',
          infoText:
              'This confirms the deletion request came from you, not just '
              'from this device.',
          onVerificationSuccess: _submitDeletionRequest,
        ),
      );
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
          customMessage: 'Failed to send account deletion verification code.',
          showUi: false,
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingCode = false);
    }
  }

  /// Called by EmailOtpReauthDialog once it has verified the emailed code
  /// against the backend. Submits the actual deletion request, then tears
  /// down local state the same way sign-out does (see settings_tab.dart's
  /// _confirmSignOut) plus clears the cached_network_image disk cache -
  /// never done anywhere today, including on normal sign-out, but worth
  /// fixing here so a stale cached photo can't persist across accounts on
  /// a shared device.
  Future<void> _submitDeletionRequest() async {
    setState(() => _isDeleting = true);
    try {
      await createDio().post<Map<String, dynamic>>(
        '${AppConfig.current.backendUrl}/api/v1/account/deletion/request',
        data: {'confirmation_text': 'DELETE'},
        options: Options(
          headers: {'X-App-Variant': AppConfig.current.variantString},
        ),
      );

      await SignalKeyService.instance.wipeLocalData();
      await DefaultCacheManager().emptyCache();
      await Supabase.instance.client.auth.signOut();
      if (mounted) {
        context.go('/');
      }
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
          customMessage: 'Failed to submit account deletion request.',
          showUi: false,
        );
      }
      rethrow;
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: _buildAppBar(),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: [
            _buildHero(),
            const SizedBox(height: 20),
            const _InfoSection(
              icon: LucideIcons.zapOff,
              title: 'Immediate Actions',
              items: [
                'You will be signed out of your account on all devices.',
                'Your profile will no longer be visible to others on Orbit.',
                'All active matches and conversations will be closed. Other users will see that you are no longer available.',
                'You will cease to receive notifications or updates.',
              ],
            ),
            const SizedBox(height: 14),
            _InfoSection(
              icon: LucideIcons.undo2,
              title: 'Within $_gracePeriodDays Days (Restoration window)',
              iconColor: AppColors.success,
              items: const [
                'Logging back in at any time before the period ends allows you to cancel the deletion request.',
                'Your profile details, active matches, and conversation history will be fully restored.',
              ],
            ),
            const SizedBox(height: 14),
            _InfoSection(
              icon: LucideIcons.trash2,
              title: 'After $_gracePeriodDays Days (Permanent deletion)',
              items: [
                'Your name, photos, and profile details are irreversibly anonymized.',
                if (_blocklistCooldownDays > 0)
                  'If your account was suspended or flagged for safety issues, a secure one-way hash of your phone number is retained for **$_blocklistCooldownDays days** to prevent registration. Otherwise, your phone number is removed and can be used to sign up again.',
                '**This action cannot be undone.**',
              ],
            ),
            const SizedBox(height: 14),
            _InfoSection(
              icon: LucideIcons.scale,
              title: 'Data Retention & Compliance',
              items: [
                'Historical reports and moderation logs are retained anonymously to maintain platform safety and trust.',
                'Meetup Safety alerts are retained for **$_safetyDataLegalHoldDays days** and Digital Witness recordings are retained for **$_safetyEvidenceActiveRetentionDays days**, to support potential safety investigations.',
                'Financial records and compliance history required by law will be retained.',
                '**All retained data is permanently purged after ${_formatLongTailPurge(_longTailPurgeDays)}. No personal information is stored indefinitely.**',
              ],
            ),
            const SizedBox(height: 24),
            _buildExportPrompt(context),
            const SizedBox(height: 24),
            _buildConfirmField(),
            const SizedBox(height: 20),
            _buildDeleteButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildExportPrompt(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F6FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                LucideIcons.fileSpreadsheet,
                color: Color(0xFF2563EB),
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Backup Your Account Data',
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1E3A8A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Before you delete your account, we recommend exporting a copy of your personal data. Once the grace window expires, this data cannot be recovered.',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: const Color(0xFF1E40AF),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => unawaited(startDataExport(context)),
                borderRadius: BorderRadius.circular(12),
                child: Ink(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: const Color(0xFF2563EB),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: Text(
                        'Export My Data',
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

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.error, Color(0xFFB91C1C)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0x33EF4444),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(LucideIcons.chevronLeft, color: Colors.white),
            tooltip: 'Back',
            onPressed: _isDeleting
                ? null
                : () => Navigator.of(context).maybePop(),
          ),
          title: Text(
            'Delete Account',
            style: GoogleFonts.manrope(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          centerTitle: true,
        ),
      ),
    );
  }

  Widget _buildHero() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: AppColors.error.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              LucideIcons.triangleAlert,
              color: AppColors.error,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your account will be deactivated immediately',
                  style: GoogleFonts.manrope(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'You have a $_gracePeriodDays-day grace period to restore your account. '
                  'Beyond this window, the deletion is permanent and cannot be reversed. '
                  'Please review the timeline below.',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppColors.inkMuted,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "TYPE 'DELETE' TO CONFIRM",
          style: GoogleFonts.manrope(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
            color: AppColors.inkMuted,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _confirmController,
          enabled: !_isSendingCode && !_isDeleting,
          textCapitalization: TextCapitalization.characters,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
          decoration: InputDecoration(
            hintText: 'DELETE',
            hintStyle: GoogleFonts.jetBrainsMono(
              color: AppColors.inkFaint,
              fontSize: 16,
            ),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.borderNeutral),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.error, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDeleteButton() {
    final busy = _isSendingCode || _isDeleting;
    return SizedBox(
      width: double.infinity,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _isConfirmed && !busy ? _beginDeletion : null,
            borderRadius: BorderRadius.circular(14),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: _isConfirmed && !busy
                    ? AppColors.error
                    : AppColors.inkFaint.withValues(alpha: 0.2),
              ),
              child: Center(
                child: busy
                    ? const NexusOrbitLoader(size: 22)
                    : Text(
                        'Delete My Account',
                        style: GoogleFonts.manrope(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: _isConfirmed
                              ? Colors.white
                              : AppColors.inkFaint,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  const _InfoSection({
    required this.icon,
    required this.title,
    required this.items,
    this.iconColor = AppColors.error,
  });

  final IconData icon;
  final String title;
  final List<String> items;
  final Color iconColor;

  Widget _buildRichText(String text, TextStyle baseStyle) {
    final parts = text.split('**');
    if (parts.length <= 1) {
      return Text(text, style: baseStyle);
    }
    final spans = <InlineSpan>[];
    for (var i = 0; i < parts.length; i++) {
      final isBold = i.isOdd;
      spans.add(
        TextSpan(
          text: parts[i],
          style: isBold
              ? baseStyle.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.ink,
                )
              : baseStyle,
        ),
      );
    }
    return Text.rich(
      TextSpan(children: spans),
      style: baseStyle,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderNeutral),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000), // 3% opacity black for ambient depth
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...items.map(
            (text) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.inkFaint,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildRichText(
                      text,
                      GoogleFonts.inter(
                        fontSize: 13,
                        color: AppColors.inkMuted,
                        height: 1.5,
                      ),
                    ),
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
