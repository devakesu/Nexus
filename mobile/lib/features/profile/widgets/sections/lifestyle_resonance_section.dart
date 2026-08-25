import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/config/filter_options.dart';
import 'package:nexus/features/profile/widgets/glass_text_field.dart';
import 'package:nexus/features/profile/widgets/profile_visibility_badge.dart';
import 'package:nexus/features/profile/widgets/selector_tile.dart';
import 'package:nexus/features/profile/widgets/tag_chips_editor.dart';
import 'package:nexus/features/profile/widgets/universe_section.dart';

class LifestyleResonanceSection extends StatelessWidget {
  const LifestyleResonanceSection({
    required this.lifestyle,
    required this.drinking,
    required this.smoking,
    required this.religiousBeliefs,
    required this.pets,
    required this.onLifestyleChanged,
    required this.onLifestyleSubmitted,
    required this.onPetsChanged,
    required this.openBottomSelectionSheet,
    required this.onDrinkingSaved,
    required this.onSmokingSaved,
    required this.onReligiousBeliefsSaved,
    this.childrenPlans = '',
    this.onChildrenPlansSaved,
    this.onClearChildrenPlans,
    this.onClearDrinking,
    this.onClearSmoking,
    this.onClearReligiousBeliefs,
    this.isSavingLifestyle = false,
    this.isSavingDrinking = false,
    this.isSavingSmoking = false,
    this.isSavingReligiousBeliefs = false,
    this.isSavingPets = false,
    this.isSavingChildrenPlans = false,
    this.religiousBeliefsVisibilityToggle,
    this.petsVisibilityToggle,
    this.childrenPlansVisibilityToggle,
    super.key,
  });

  final String lifestyle;
  final String drinking;
  final String smoking;
  final String religiousBeliefs;
  final String childrenPlans;
  final List<String> pets;
  final bool isSavingLifestyle;
  final bool isSavingDrinking;
  final bool isSavingSmoking;
  final bool isSavingReligiousBeliefs;
  final bool isSavingPets;
  final bool isSavingChildrenPlans;
  final Widget? religiousBeliefsVisibilityToggle;
  final Widget? petsVisibilityToggle;
  final Widget? childrenPlansVisibilityToggle;

  final ValueChanged<String> onLifestyleChanged;
  final ValueChanged<String> onLifestyleSubmitted;
  final ValueChanged<List<String>> onPetsChanged;
  final ValueChanged<String>? onChildrenPlansSaved;

  final void Function({
    required String title,
    required List<String> options,
    required String currentValue,
    required ValueChanged<String> onSelected,
  })
  openBottomSelectionSheet;

  final ValueChanged<String> onDrinkingSaved;
  final ValueChanged<String> onSmokingSaved;
  final ValueChanged<String> onReligiousBeliefsSaved;
  final VoidCallback? onClearDrinking;
  final VoidCallback? onClearSmoking;
  final VoidCallback? onClearReligiousBeliefs;
  final VoidCallback? onClearChildrenPlans;

  @override
  Widget build(BuildContext context) {
    return UniverseSection(
      icon: LucideIcons.heart,
      title: 'Lifestyle & Preferences',
      description: 'Your daily habits, values and background',
      cardColor: const Color(0xFFFFF7ED),
      borderColor: const Color(0xFFFF9500).withValues(alpha: 0.4),
      accentColor: const Color(0xFFFF9500),
      visibilityBadge: ProfileVisibilityBadge.datingAndFriends(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GlassTextField(
            label: 'Lifestyle Description',
            initialValue: lifestyle,
            hintText: 'Describe your daily routine/vibe...',
            prefixIcon: LucideIcons.activity,
            maxLines: null,
            minLines: 4,
            keyboardType: TextInputType.multiline,
            onChanged: onLifestyleChanged,
            onFieldSubmitted: onLifestyleSubmitted,
            isSaving: isSavingLifestyle,
          ),
          const SizedBox(height: 16),

          // Drinking and Smoking
          Row(
            children: [
              Expanded(
                child: SelectorTile(
                  label: 'DRINKING',
                  value: drinking,
                  icon: LucideIcons.glassWater,
                  iconColor: const Color(0xFF34C759),
                  onTap: () {
                    openBottomSelectionSheet(
                      title: 'Drinking',
                      options: const [
                        'Never',
                        'Occasionally',
                        'Socially',
                        'Regularly',
                      ],
                      currentValue: drinking,
                      onSelected: onDrinkingSaved,
                    );
                  },
                  onClear: onClearDrinking,
                  isSaving: isSavingDrinking,
                  isFullWidth: false,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SelectorTile(
                  label: 'SMOKING',
                  value: smoking,
                  icon: LucideIcons.cigarette,
                  iconColor: const Color(0xFF8E8E93),
                  onTap: () {
                    openBottomSelectionSheet(
                      title: 'Smoking',
                      options: const [
                        'Never',
                        'Occasionally',
                        'Socially',
                        'Regularly',
                      ],
                      currentValue: smoking,
                      onSelected: onSmokingSaved,
                    );
                  },
                  onClear: onClearSmoking,
                  isSaving: isSavingSmoking,
                  isFullWidth: false,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Religious Beliefs
          SelectorTile(
            label: 'RELIGIOUS BELIEFS',
            value: religiousBeliefs,
            icon: LucideIcons.sparkles,
            iconColor: const Color(0xFF5856D6),
            onTap: () {
              openBottomSelectionSheet(
                title: 'Religious Beliefs',
                options: FilterOptions.religiousBeliefs,
                currentValue: religiousBeliefs,
                onSelected: onReligiousBeliefsSaved,
              );
            },
            onClear: onClearReligiousBeliefs,
            isSaving: isSavingReligiousBeliefs,
            visibilityToggle: religiousBeliefsVisibilityToggle,
          ),
          const SizedBox(height: 16),

          // Children Plans
          SelectorTile(
            label: 'CHILDREN PLANS',
            value: childrenPlans,
            icon: LucideIcons.baby,
            iconColor: const Color(0xFF007AFF),
            onTap: () {
              if (onChildrenPlansSaved != null) {
                openBottomSelectionSheet(
                  title: 'Children Plans',
                  options: FilterOptions.childrenPlans,
                  currentValue: childrenPlans,
                  onSelected: onChildrenPlansSaved!,
                );
              }
            },
            onClear: onClearChildrenPlans,
            isSaving: isSavingChildrenPlans,
            visibilityToggle: childrenPlansVisibilityToggle,
          ),
          const SizedBox(height: 16),

          // Pets tag editor
          TagChipsEditor(
            label: 'Pets',
            currentValues: pets,
            presets: FilterOptions.pets,
            icon: LucideIcons.pawPrint,
            iconColor: const Color(0xFFFF9800),
            onChanged: onPetsChanged,
            hintText: '',
            allowCustom: false,
            isSaving: isSavingPets,
            exclusiveOptions: const ['No Pets'],
            visibilityToggle: petsVisibilityToggle,
          ),
        ],
      ),
    );
  }
}
