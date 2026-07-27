import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/features/profile/utils/name_moderation.dart';
import 'package:nexus/features/profile/widgets/glass_text_field.dart';

enum _NameSheetStep { intro, confirm }

String? _validationMessage(String candidate) {
  if (candidate.isEmpty) return null;
  if (candidate.length < 4) {
    return 'Display name must be at least 4 characters.';
  }
  return validateDisplayNameClientSide(candidate).error;
}

/// Bottom sheet for changing display name, gated to twice per rolling
/// 365-day window (the value set at registration counts as the first
/// change) and run through a profanity/title/digit moderation check.
///
/// Mirrors showAgeChangeSheet's structure and light-themed chrome.
Future<void> showNameChangeSheet(
  BuildContext context, {
  required String currentName,
  required bool eligible,
  required int changesUsedInWindow,
  required DateTime? nextEligibleAt,
  required ValueChanged<String> onConfirmed,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    builder: (sheetContext) {
      var step = _NameSheetStep.intro;
      var pendingName = currentName;

      return StatefulBuilder(
        builder: (context, setModalState) {
          final validationError = _validationMessage(pendingName);
          final canContinue =
              pendingName != currentName &&
              pendingName.length >= 4 &&
              validationError == null;

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
              child: SingleChildScrollView(
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
                          'Name Change',
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
                    else if (step == _NameSheetStep.intro)
                      ..._buildIntroContent(
                        currentName: currentName,
                        changesUsedInWindow: changesUsedInWindow,
                        validationError: validationError,
                        onChanged: (val) =>
                            setModalState(() => pendingName = val.trim()),
                        onContinue: canContinue
                            ? () => setModalState(
                                () => step = _NameSheetStep.confirm,
                              )
                            : null,
                      )
                    else
                      ..._buildConfirmContent(
                        currentName: currentName,
                        pendingName: pendingName,
                        changesUsedInWindow: changesUsedInWindow,
                        onBack: () =>
                            setModalState(() => step = _NameSheetStep.intro),
                        onConfirm: () {
                          Navigator.pop(sheetContext);
                          onConfirmed(pendingName);
                        },
                      ),
                  ],
                ),
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
      'To protect against impersonation and abuse, your display name can '
      'only be changed twice within a rolling 365-day window - the value '
      'set at registration counts as the first change.',
      style: TextStyle(
        color: Colors.black.withValues(alpha: 0.6),
        fontSize: 13,
      ),
    ),
    const SizedBox(height: 10),
    Text(
      "You've used both name changes for this year. You can change your "
      'name again on $formattedDate.',
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
  required String currentName,
  required int changesUsedInWindow,
  required String? validationError,
  required ValueChanged<String> onChanged,
  required VoidCallback? onContinue,
}) {
  final remaining = 2 - changesUsedInWindow;
  return [
    Text(
      'Display name can be changed twice within a rolling 365-day window - '
      'the value set at registration counts as the first change. You '
      'have $remaining change${remaining == 1 ? '' : 's'} left. New names '
      "can't contain numbers, titles (e.g. \"Dr.\"), or offensive language.",
      style: TextStyle(
        color: Colors.black.withValues(alpha: 0.6),
        fontSize: 13,
      ),
    ),
    const SizedBox(height: 16),
    GlassTextField(
      label: 'Display Name',
      initialValue: currentName,
      hintText: 'Enter your cosmic display name',
      prefixIcon: LucideIcons.user,
      onChanged: onChanged,
    ),
    if (validationError != null)
      Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Text(
          validationError,
          style: const TextStyle(
            color: AppColors.error,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
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
  required String currentName,
  required String pendingName,
  required int changesUsedInWindow,
  required VoidCallback onBack,
  required VoidCallback onConfirm,
}) {
  final remainingAfter = 2 - changesUsedInWindow - 1;
  return [
    Text(
      "You're about to change your display name from \"$currentName\" to "
      '"$pendingName". This will use one of your two yearly name changes '
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
