import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/screens/settings/delete_account_otp_dialog.dart';
import 'package:nexus/services/signal/signal_key_service.dart';
import 'package:nexus/theme/app_colors.dart';
import 'package:nexus/utils/error_handler.dart';
import 'package:nexus/utils/network_utils.dart';
import 'package:nexus/widgets/nexus_toast.dart';
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

  @override
  void initState() {
    super.initState();
    _confirmController.addListener(_updateConfirmState);
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
        builder: (_) => DeleteAccountOtpDialog(
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

  /// Called by DeleteAccountOtpDialog once it has verified the emailed code
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
              title: 'Immediately',
              items: [
                "You're signed out on every device.",
                'Your profile stops appearing in Orbit for everyone.',
                "Your active matches and conversations are closed - the other person sees you're no longer available.",
                "You'll stop receiving notifications.",
              ],
            ),
            const SizedBox(height: 14),
            const _InfoSection(
              icon: LucideIcons.undo2,
              title: 'Within 14 days, you can undo this',
              iconColor: AppColors.success,
              items: [
                'Log back in any time before then and a Reactivate screen lets you cancel the deletion.',
                'Your profile, matches, and conversations all come back exactly as they were.',
              ],
            ),
            const SizedBox(height: 14),
            const _InfoSection(
              icon: LucideIcons.trash2,
              title: 'After 14 days',
              items: [
                'Your name, photos, and profile details are permanently erased.',
                'Your phone number is removed and can be used to sign up again.',
                "This step can't be undone.",
              ],
            ),
            const SizedBox(height: 14),
            const _InfoSection(
              icon: LucideIcons.scale,
              title: 'What we keep, and why',
              items: [
                'Reports or moderation history involving your account, for trust & safety - kept without your name attached.',
                'Meetup Safety / SOS records, for a limited time, in case they are needed for a safety investigation.',
                'Records required by law, such as billing or legal compliance history.',
                'Everything above is deleted for good on a fixed schedule - nothing is retained indefinitely.',
              ],
            ),
            const SizedBox(height: 24),
            _buildConfirmField(),
            const SizedBox(height: 20),
            _buildDeleteButton(),
          ],
        ),
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
                  'This deactivates your account right away',
                  style: GoogleFonts.manrope(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'You have a 14-day window to change your mind. After '
                  "that, it's permanent. Read exactly what happens below.",
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
          'TYPE DELETE TO CONFIRM',
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
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
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

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderNeutral),
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
                    child: Text(
                      text,
                      style: GoogleFonts.inter(
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
