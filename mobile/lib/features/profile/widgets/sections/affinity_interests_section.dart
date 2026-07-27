import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/config/filter_options.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/features/home/widgets/interests_overlay.dart';
import 'package:nexus/features/profile/widgets/tag_chips_editor.dart';
import 'package:nexus/features/profile/widgets/universe_section.dart';

class AffinityInterestsSection extends StatelessWidget {
  const AffinityInterestsSection({
    required this.flatSubInterests,
    required this.causesSupported,
    required this.onInterestsSaved,
    required this.onCausesSupportedChanged,
    this.isSavingInterests = false,
    this.isSavingCauses = false,
    super.key,
  });

  final List<String> flatSubInterests;
  final List<String> causesSupported;
  final bool isSavingInterests;
  final bool isSavingCauses;

  final ValueChanged<List<String>> onInterestsSaved;
  final ValueChanged<List<String>> onCausesSupportedChanged;

  @override
  Widget build(BuildContext context) {
    return UniverseSection(
      icon: LucideIcons.tags,
      title: 'Interests & Hobbies',
      description: 'Your hobbies and causes',
      cardColor: const Color(0xFFECFEFF),
      borderColor: const Color(0xFF00E5FF).withValues(alpha: 0.4),
      accentColor: const Color(0xFF00E5FF),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TagChipsEditor(
            label: 'Interests',
            currentValues: flatSubInterests,
            presets: const [],
            icon: LucideIcons.sparkles,
            iconColor: AppColors.pulsarPink,
            onChanged: onInterestsSaved,
            hintText: 'Select interests...',
            allowCustom: false,
            isSaving: isSavingInterests,
            onTapEdit: () {
              unawaited(
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (context) => InterestsOverlay(
                      initialSelected: flatSubInterests,
                      onSave: onInterestsSaved,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          TagChipsEditor(
            label: 'Causes Supported',
            currentValues: causesSupported,
            presets: FilterOptions.causesSupported,
            icon: LucideIcons.heart,
            iconColor: const Color(0xFF00BCD4),
            onChanged: onCausesSupportedChanged,
            hintText: 'Select causes...',
            allowCustom: false,
            isSaving: isSavingCauses,
          ),
        ],
      ),
    );
  }
}
