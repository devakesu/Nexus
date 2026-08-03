import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/core/widgets/aesthetic_loaders.dart';

/// A compact, animated micro-toggle switch designed to fit next to field title labels
/// on the profile tab without taking up excess horizontal or vertical space.
class VisibilityToggleMini extends StatelessWidget {
  const VisibilityToggleMini({
    required this.value,
    required this.onChanged,
    this.isSaving = false,
    this.locked = false,
    this.onLockedTap,
    super.key,
  });

  /// True if the field is visible, false if hidden.
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool isSaving;
  final bool locked;
  final VoidCallback? onLockedTap;

  @override
  Widget build(BuildContext context) {
    if (isSaving) {
      return const SizedBox(
        width: 28,
        height: 16,
        child: Center(
          child: NexusOrbitLoader(
            size: 16,
            lightMode: true,
          ),
        ),
      );
    }

    if (locked) {
      return Semantics(
        button: true,
        label: 'Field locked, tap to request consent',
        child: GestureDetector(
          onTap: onLockedTap,
          behavior: HitTestBehavior.opaque,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Icon(
              LucideIcons.lock,
              size: 13,
              color: AppColors.inkFaint,
            ),
          ),
        ),
      );
    }

    return Semantics(
      button: true,
      toggled: value,
      label: value ? 'Field visible' : 'Field hidden',
      child: GestureDetector(
        onTap: () => onChanged(!value),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 28,
          height: 16,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: value
                ? AppColors.primaryTeal
                : Colors.black.withValues(alpha: 0.15),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 200),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 12,
              height: 12,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 1,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
