import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/config/app_config.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/features/profile/utils/name_moderation.dart';

enum ProfileFieldSheetStep { intro, confirm }

/// Generic reusable 2-step modal sheet for profile changes (Name, Age, etc.)
Future<void> showProfileFieldEditSheet<T>({
  required BuildContext context,
  required String fieldTitle,
  required T currentValue,
  required bool eligible,
  required int changesUsedInWindow,
  required DateTime? nextEligibleAt,
  required Widget Function(
    BuildContext context,
    T pendingValue,
    void Function(T val) onChanged,
  )
  inputBuilder,
  required String Function(T pendingValue) confirmDescriptionBuilder,
  required FutureOr<void> Function(T confirmedValue) onConfirmed,
  bool Function(T pendingValue)? isValid,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    builder: (sheetContext) {
      var step = ProfileFieldSheetStep.intro;
      var pendingValue = currentValue;

      return StatefulBuilder(
        builder: (context, setModalState) {
          final canContinue =
              (pendingValue != currentValue) &&
              (isValid == null || isValid(pendingValue));

          return Container(
            padding: EdgeInsets.only(
              top: 12,
              left: 20,
              right: 20,
              bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        step == ProfileFieldSheetStep.intro
                            ? 'Change $fieldTitle'
                            : 'Confirm New $fieldTitle',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(LucideIcons.x, color: Colors.black54),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  if (!eligible) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.amber.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            LucideIcons.alertTriangle,
                            color: Colors.amber,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'You have used all $changesUsedInWindow allowed changes in this 365-day period.'
                              '${nextEligibleAt != null ? ' Next change available on ${DateFormat.yMMMd().format(nextEligibleAt)}.' : ''}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (step == ProfileFieldSheetStep.intro) ...[
                    inputBuilder(context, pendingValue, (val) {
                      setModalState(() => pendingValue = val);
                    }),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: (eligible && canContinue)
                            ? () => setModalState(
                                () => step = ProfileFieldSheetStep.confirm,
                              )
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryTeal,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Review Change',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ] else ...[
                    Text(
                      confirmDescriptionBuilder(pendingValue),
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => setModalState(
                              () => step = ProfileFieldSheetStep.intro,
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('Back'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              Navigator.of(context).pop();
                              await onConfirmed(pendingValue);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryTeal,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Confirm',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

/// Backward compatible helper for changing name
Future<void> showNameChangeSheet(
  BuildContext context, {
  required String currentName,
  required bool eligible,
  required int changesUsedInWindow,
  required DateTime? nextEligibleAt,
  required ValueChanged<String> onConfirmed,
}) async {
  await showProfileFieldEditSheet<String>(
    context: context,
    fieldTitle: 'Display Name',
    currentValue: currentName,
    eligible: eligible,
    changesUsedInWindow: changesUsedInWindow,
    nextEligibleAt: nextEligibleAt,
    isValid: (val) =>
        val.length >= 4 && validateDisplayNameClientSide(val).error == null,
    inputBuilder: (context, pending, onChanged) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Enter new display name',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            controller: TextEditingController(text: pending)
              ..selection = TextSelection.collapsed(offset: pending.length),
            onChanged: onChanged,
          ),
        ],
      );
    },
    confirmDescriptionBuilder: (val) =>
        'Are you sure you want to change your display name to "$val"?',
    onConfirmed: onConfirmed,
  );
}

/// Backward compatible helper for changing age
Future<void> showAgeChangeSheet(
  BuildContext context, {
  required int currentAge,
  required bool eligible,
  required int changesUsedInWindow,
  required DateTime? nextEligibleAt,
  required ValueChanged<int> onConfirmed,
}) async {
  final maxAge = AppConfig.current.isMainVariant ? 80 : 27;
  await showProfileFieldEditSheet<int>(
    context: context,
    fieldTitle: 'Age',
    currentValue: currentAge,
    eligible: eligible,
    changesUsedInWindow: changesUsedInWindow,
    nextEligibleAt: nextEligibleAt,
    isValid: (val) => val >= 18 && val <= maxAge,
    inputBuilder: (context, pending, onChanged) {
      return Column(
        children: [
          Text(
            '$pending years old',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          Slider(
            value: pending.toDouble(),
            min: 18,
            max: maxAge.toDouble(),
            divisions: maxAge - 18,
            activeColor: AppColors.primaryTeal,
            onChanged: (val) => onChanged(val.round()),
          ),
        ],
      );
    },
    confirmDescriptionBuilder: (val) =>
        'Are you sure you want to update your age to $val years old?',
    onConfirmed: onConfirmed,
  );
}
