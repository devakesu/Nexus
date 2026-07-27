import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/config/app_config.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/core/utils/error_handler.dart';
import 'package:nexus/core/utils/network_utils.dart';
import 'package:nexus/core/widgets/aesthetic_loaders.dart';
import 'package:nexus/core/widgets/nexus_toast.dart';
import 'package:nexus/features/security_signal/services/signal/signal_key_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Shown by AuthGate instead of the normal app when the signed-in account
/// has a pending deletion (auth/bootstrap returned deletion_pending=true).
/// Lets the user undo it - see app/db/account_deletion.py::cancel_deletion,
/// which fully restores the profile, matches, and conversations, not just
/// the account row.
class ReactivateAccountPage extends StatefulWidget {
  const ReactivateAccountPage({
    required this.scheduledPurgeAt,
    required this.onReactivated,
    super.key,
  });

  final DateTime? scheduledPurgeAt;
  final FutureOr<void> Function() onReactivated;

  @override
  State<ReactivateAccountPage> createState() => _ReactivateAccountPageState();
}

class _ReactivateAccountPageState extends State<ReactivateAccountPage> {
  bool _isReactivating = false;
  bool _isSigningOut = false;

  int? get _daysRemaining {
    final purgeAt = widget.scheduledPurgeAt;
    if (purgeAt == null) return null;
    final remaining = purgeAt.difference(DateTime.now()).inHours / 24;
    return remaining.ceil().clamp(0, 1 << 30);
  }

  Future<void> _reactivate() async {
    setState(() => _isReactivating = true);
    try {
      await createDio().post<Map<String, dynamic>>(
        '${AppConfig.current.backendUrl}/api/v1/account/deletion/cancel',
        options: Options(
          headers: {'X-App-Variant': AppConfig.current.variantString},
        ),
      );
      await widget.onReactivated();
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
          customMessage: 'Failed to reactivate account.',
          showUi: false,
        );
      }
    } finally {
      if (mounted) setState(() => _isReactivating = false);
    }
  }

  Future<void> _signOut() async {
    setState(() => _isSigningOut = true);
    await SignalKeyService.instance.wipeLocalData();
    await Supabase.instance.client.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final daysRemaining = _daysRemaining;
    final busy = _isReactivating || _isSigningOut;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    LucideIcons.rotateCcw,
                    color: AppColors.warning,
                    size: 30,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Welcome back',
                  style: GoogleFonts.manrope(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  daysRemaining != null
                      ? 'Your account is scheduled for deletion in '
                            '$daysRemaining day${daysRemaining == 1 ? '' : 's'}. '
                            'Reactivate now to keep your profile, matches, '
                            'and conversations exactly as they were.'
                      : 'Your account is scheduled for deletion. Reactivate '
                            'now to keep your profile, matches, and '
                            'conversations exactly as they were.',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: AppColors.inkMuted,
                    height: 1.6,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 52),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: busy ? null : _reactivate,
                        borderRadius: BorderRadius.circular(14),
                        child: Ink(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            color: AppColors.success,
                          ),
                          child: Center(
                            child: _isReactivating
                                ? const NexusOrbitLoader(size: 22)
                                : Text(
                                    'Reactivate My Account',
                                    style: GoogleFonts.manrope(
                                      fontSize: 15,
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
                const SizedBox(height: 16),
                TextButton(
                  onPressed: busy ? null : _signOut,
                  child: _isSigningOut
                      ? const NexusOrbitLoader(size: 18, lightMode: true)
                      : Text(
                          'Not now, sign me out',
                          style: GoogleFonts.manrope(
                            color: AppColors.inkMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
