import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/screens/home/tabs/profile/widgets/neon_slider.dart';
import 'package:nexus/theme/app_colors.dart';

// Main nexus allows 18-80; every other variant (MEC, campus-gated) stays
// 18-27 - matches NexusOnboardingRequest/MECOnboardingRequest server-side
// (app/models.py) and the DB's per-variant trigger
// (20260803000000_widen_profile_age_range.sql).
int get _maxAge => AppConfig.current.isMainVariant ? 80 : 27;

enum _AgeSheetStep { intro, confirm }

/// Bottom sheet for changing age, gated to twice per rolling 365-day
/// window (the value set at registration counts as the first change).
///
/// Mirrors the light-themed container already used for the Gender/
/// Sexuality/Pronouns pickers in this same Core Details section (white
/// background, rounded top corners, drag handle) rather than the dark
/// AlertDialog chrome used elsewhere (e.g. the profile report dialog).
Future<void> showAgeChangeSheet(
  BuildContext context, {
  required int currentAge,
  required bool eligible,
  required int changesUsedInWindow,
  required DateTime? nextEligibleAt,
  required ValueChanged<int> onConfirmed,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    builder: (sheetContext) {
      var step = _AgeSheetStep.intro;
      var pendingAge = currentAge;

      return StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            padding: EdgeInsets.only(
              top: 12,
              left: 20,
              right: 20,
              bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(28),
                topRight: Radius.circular(28),
              ),
              border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 18),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const Row(
                    children: [
                      Icon(
                        LucideIcons.shieldCheck,
                        color: Color(0xFF2D8CFF),
                        size: 20,
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Age Change',
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (!eligible)
                    ..._buildIneligibleContent(sheetContext, nextEligibleAt)
                  else if (step == _AgeSheetStep.intro)
                    ..._buildIntroContent(
                      currentAge: currentAge,
                      pendingAge: pendingAge,
                      changesUsedInWindow: changesUsedInWindow,
                      onAgeChanged: (val) =>
                          setModalState(() => pendingAge = val),
                      onContinue: pendingAge != currentAge
                          ? () => setModalState(
                              () => step = _AgeSheetStep.confirm,
                            )
                          : null,
                    )
                  else
                    ..._buildConfirmContent(
                      currentAge: currentAge,
                      pendingAge: pendingAge,
                      changesUsedInWindow: changesUsedInWindow,
                      onBack: () =>
                          setModalState(() => step = _AgeSheetStep.intro),
                      onConfirm: () {
                        Navigator.pop(sheetContext);
                        onConfirmed(pendingAge);
                      },
                    ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

List<Widget> _buildIneligibleContent(
  BuildContext context,
  DateTime? nextEligibleAt,
) {
  final formattedDate = nextEligibleAt != null
      ? DateFormat('MMMM d, y').format(nextEligibleAt)
      : 'a later date';
  return [
    Text(
      'To protect against impersonation and abuse, age can only be '
      'changed twice within a rolling 365-day window - the value set at '
      'registration counts as the first change.',
      style: TextStyle(
        color: Colors.black.withValues(alpha: 0.6),
        fontSize: 13,
      ),
    ),
    const SizedBox(height: 10),
    Text(
      "You've used both age changes for this year. You can change your "
      'age again on $formattedDate.',
      style: const TextStyle(
        color: Color(0xFF0F172A),
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    ),
    const SizedBox(height: 6),
    Text(
      'Need it sooner? File a ticket via Settings → Help, Feedback & '
      'Bug Report to request an exception from customer service.',
      style: TextStyle(
        color: Colors.black.withValues(alpha: 0.5),
        fontSize: 12,
      ),
    ),
    const SizedBox(height: 18),
    SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryTeal,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 13),
        ),
        onPressed: () {
          Navigator.pop(context);
          unawaited(context.push<void>('/settings/feedback'));
        },
        icon: const Icon(LucideIcons.messageSquare, size: 16),
        label: const Text(
          'Help, Feedback & Bug Report',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ),
    ),
  ];
}

List<Widget> _buildIntroContent({
  required int currentAge,
  required int pendingAge,
  required int changesUsedInWindow,
  required ValueChanged<int> onAgeChanged,
  required VoidCallback? onContinue,
}) {
  final remaining = 2 - changesUsedInWindow;
  return [
    Text(
      'Age can be changed twice within a rolling 365-day window - the '
      'value set at registration counts as the first change. You have '
      '$remaining change${remaining == 1 ? '' : 's'} left.',
      style: TextStyle(
        color: Colors.black.withValues(alpha: 0.6),
        fontSize: 13,
      ),
    ),
    const SizedBox(height: 16),
    NeonSlider(
      value: pendingAge.toDouble(),
      min: 18,
      max: _maxAge.toDouble(),
      divisions: _maxAge - 18,
      label: 'Age',
      onChanged: (val) => onAgeChanged(val.round()),
    ),
    const SizedBox(height: 8),
    SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryTeal,
          disabledBackgroundColor: Colors.black12,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 13),
        ),
        onPressed: onContinue,
        child: const Text(
          'Continue',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ),
    ),
  ];
}

List<Widget> _buildConfirmContent({
  required int currentAge,
  required int pendingAge,
  required int changesUsedInWindow,
  required VoidCallback onBack,
  required VoidCallback onConfirm,
}) {
  final remainingAfter = 2 - changesUsedInWindow - 1;
  return [
    Text(
      "You're about to change your age from $currentAge to $pendingAge. "
      'This will use one of your two yearly age changes '
      '(${remainingAfter == 0 ? "none" : remainingAfter} left after this) '
      '- make sure this is correct before confirming.',
      style: const TextStyle(
        color: Color(0xFF0F172A),
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    ),
    const SizedBox(height: 18),
    Row(
      children: [
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.black87,
              side: BorderSide(color: Colors.black.withValues(alpha: 0.15)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
            onPressed: onBack,
            child: const Text(
              'Back',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryTeal,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
            onPressed: onConfirm,
            icon: const Icon(LucideIcons.checkCircle, size: 16),
            label: const Text(
              'Confirm',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ),
      ],
    ),
  ];
}
