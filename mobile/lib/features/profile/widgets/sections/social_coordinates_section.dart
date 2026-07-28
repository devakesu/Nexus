import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/config/filter_options.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/core/widgets/aesthetic_loaders.dart';
import 'package:nexus/core/widgets/nexus_toast.dart';
import 'package:nexus/features/profile/widgets/glass_text_field.dart';
import 'package:nexus/features/profile/widgets/place_autocomplete_field.dart';
import 'package:nexus/features/profile/widgets/tag_chips_editor.dart';
import 'package:nexus/features/profile/widgets/universe_section.dart';

class SocialCoordinatesSection extends StatefulWidget {
  const SocialCoordinatesSection({
    required this.hometown,
    required this.currentPlace,
    required this.languages,
    required this.campusName,
    required this.savedCampusName,
    required this.major,
    required this.isStudying,
    required this.year,
    required this.onHometownChanged,
    required this.onHometownSubmitted,
    required this.onCurrentPlaceChanged,
    required this.onCurrentPlaceSubmitted,
    required this.onLanguagesChanged,
    required this.onCampusNameChanged,
    required this.onCampusNameSubmitted,
    required this.onMajorChanged,
    required this.onMajorSubmitted,
    required this.onIsStudyingChanged,
    required this.onYearChanged,
    this.isSavingHometown = false,
    this.isSavingCurrentPlace = false,
    this.isSavingCampusName = false,
    this.isSavingMajor = false,
    this.isSavingLanguages = false,
    this.isSavingCampusYear = false,
    this.hometownFocusNode,
    this.currentPlaceFocusNode,
    this.campusNameFocusNode,
    this.majorFocusNode,
    this.campusNameKey,
    this.majorKey,
    this.hometownKey,
    this.currentPlaceKey,
    super.key,
  });

  final String hometown;
  final String currentPlace;
  final List<String> languages;
  final String campusName;
  final String savedCampusName;
  final String major;
  final bool isStudying;
  final int year;
  final bool isSavingHometown;
  final bool isSavingCurrentPlace;
  final bool isSavingCampusName;
  final bool isSavingMajor;
  final bool isSavingLanguages;
  final bool isSavingCampusYear;
  final FocusNode? hometownFocusNode;
  final FocusNode? currentPlaceFocusNode;
  final FocusNode? campusNameFocusNode;
  final FocusNode? majorFocusNode;
  final Key? campusNameKey;
  final Key? majorKey;
  final Key? hometownKey;
  final Key? currentPlaceKey;

  final ValueChanged<String> onHometownChanged;
  final ValueChanged<String> onHometownSubmitted;
  final ValueChanged<String> onCurrentPlaceChanged;
  final ValueChanged<String> onCurrentPlaceSubmitted;
  final ValueChanged<List<String>> onLanguagesChanged;
  final ValueChanged<String> onCampusNameChanged;
  final ValueChanged<String> onCampusNameSubmitted;
  final ValueChanged<String> onMajorChanged;
  final ValueChanged<String> onMajorSubmitted;
  final ValueChanged<bool> onIsStudyingChanged;
  final ValueChanged<int> onYearChanged;

  @override
  State<SocialCoordinatesSection> createState() =>
      _SocialCoordinatesSectionState();
}

class _SocialCoordinatesSectionState extends State<SocialCoordinatesSection> {
  bool _isExpanded = false;

  bool _isValidCampusName(String name) {
    return name.trim().replaceAll(RegExp('[^a-zA-Z]'), '').length >= 3;
  }

  @override
  void didUpdateWidget(covariant SocialCoordinatesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isStudying && oldWidget.isStudying) {
      _isExpanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return UniverseSection(
      icon: LucideIcons.globe,
      title: 'Social & Campus Info',
      description: 'Your campus and hometown background',
      cardColor: const Color(0xFFF0FDF4),
      borderColor: AppColors.success.withValues(alpha: 0.4),
      accentColor: AppColors.success,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PlaceAutocompleteField(
            key: widget.hometownKey,
            label: 'Hometown',
            initialValue: widget.hometown,
            hintText: 'Set your hometown',
            prefixIcon: LucideIcons.home,
            onChanged: widget.onHometownChanged,
            onFieldSubmitted: widget.onHometownSubmitted,
            isSaving: widget.isSavingHometown,
            focusNode: widget.hometownFocusNode,
          ),
          const SizedBox(height: 12),

          PlaceAutocompleteField(
            key: widget.currentPlaceKey,
            label: 'Current Place',
            initialValue: widget.currentPlace,
            hintText: 'Set your current place',
            prefixIcon: LucideIcons.navigation,
            onChanged: widget.onCurrentPlaceChanged,
            onFieldSubmitted: widget.onCurrentPlaceSubmitted,
            isSaving: widget.isSavingCurrentPlace,
            focusNode: widget.currentPlaceFocusNode,
          ),
          const SizedBox(height: 16),

          // Languages tag editor
          TagChipsEditor(
            label: 'Languages',
            currentValues: widget.languages,
            presets: FilterOptions.languages,
            icon: LucideIcons.languages,
            iconColor: const Color(0xFF4CAF50),
            onChanged: widget.onLanguagesChanged,
            hintText: 'Select languages...',
            allowCustom: false,
            isSaving: widget.isSavingLanguages,
          ),
          const SizedBox(height: 12),

          GlassTextField(
            key: widget.campusNameKey,
            label: 'INSTITUTE NAME',
            initialValue: widget.campusName,
            hintText: 'Add your college name',
            prefixIcon: LucideIcons.mapPin,
            onChanged: widget.onCampusNameChanged,
            onFieldSubmitted: widget.onCampusNameSubmitted,
            isSaving: widget.isSavingCampusName,
            focusNode: widget.campusNameFocusNode,
          ),
          const SizedBox(height: 12),

          GlassTextField(
            key: widget.majorKey,
            label: 'MAJOR',
            initialValue: widget.major,
            hintText: 'e.g. Computer Science',
            prefixIcon: LucideIcons.graduationCap,
            onChanged: widget.onMajorChanged,
            onFieldSubmitted: widget.onMajorSubmitted,
            isSaving: widget.isSavingMajor,
            focusNode: widget.majorFocusNode,
          ),
          const SizedBox(height: 12),

          // Campus Year / Student Status Section
          if (widget.savedCampusName.trim().isNotEmpty) ...[
            if (!widget.isStudying) ...[
              GestureDetector(
                onTap: () {
                  if (widget.savedCampusName.trim().isEmpty) {
                    NexusToast.show(
                      context,
                      'Please enter your college/institute name first to set campus year.',
                      type: NexusToastType.warning,
                    );
                    return;
                  }
                  if (!_isValidCampusName(widget.savedCampusName)) {
                    NexusToast.show(
                      context,
                      'Institute name must contain at least three letters.',
                      type: NexusToastType.error,
                    );
                    return;
                  }
                  setState(() {
                    _isExpanded = !_isExpanded;
                  });
                },
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.black.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        LucideIcons.graduationCap,
                        color: Colors.black45,
                        size: 18,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Currently Studying here?',
                          style: GoogleFonts.plusJakartaSans(
                            color: AppColors.ink,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Icon(
                        _isExpanded
                            ? LucideIcons.minusCircle
                            : LucideIcons.plusCircle,
                        color: AppColors.pulsarPink,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
              if (_isExpanded) ...[
                const SizedBox(height: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CAMPUS YEAR',
                      style: TextStyle(
                        color: Colors.black.withValues(alpha: 0.5),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(5, (index) {
                        final yearOption = index + 1;
                        final label =
                            '${yearOption == 1
                                ? "1st"
                                : yearOption == 2
                                ? "2nd"
                                : yearOption == 3
                                ? "3rd"
                                : "${yearOption}th"} Year';

                        return GestureDetector(
                          onTap: () {
                            if (widget.savedCampusName.trim().isEmpty) {
                              NexusToast.show(
                                context,
                                'Please enter your college/institute name first to set campus year.',
                                type: NexusToastType.warning,
                              );
                              return;
                            }
                            if (!_isValidCampusName(widget.savedCampusName)) {
                              NexusToast.show(
                                context,
                                'Institute name must contain at least three letters.',
                                type: NexusToastType.error,
                              );
                              return;
                            }
                            widget.onIsStudyingChanged(true);
                            widget.onYearChanged(yearOption);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              color: const Color(0xFFF3F4F6),
                              border: Border.all(
                                color: Colors.black.withValues(alpha: 0.08),
                              ),
                            ),
                            child: Text(
                              label,
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.black87,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ],
            ] else ...[
              // Studying Switch (Turn off only)
              GestureDetector(
                onTap: () {
                  widget.onIsStudyingChanged(false);
                },
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.black.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Current Student Status',
                              style: GoogleFonts.plusJakartaSans(
                                color: AppColors.ink,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Turn off to disable student status',
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.black45,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Flat Switch (On state)
                      Container(
                        width: 44,
                        height: 24,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: AppColors.primaryTeal,
                        ),
                        child: Stack(
                          children: [
                            Align(
                              alignment: Alignment.centerRight,
                              child: Container(
                                width: 18,
                                height: 18,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                  vertical: 3,
                                ),
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Campus Year Segmented Selector
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'CAMPUS YEAR',
                        style: TextStyle(
                          color: Colors.black.withValues(alpha: 0.5),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      if (widget.isSavingCampusYear) ...[
                        const SizedBox(width: 8),
                        const NexusOrbitLoader(size: 20),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List.generate(5, (index) {
                      final yearOption = index + 1;
                      final isSelected = widget.year == yearOption;
                      final label =
                          '${yearOption == 1
                              ? "1st"
                              : yearOption == 2
                              ? "2nd"
                              : yearOption == 3
                              ? "3rd"
                              : "${yearOption}th"} Year';
                      const primaryColor = AppColors.primaryTeal;

                      return GestureDetector(
                        onTap: () {
                          if (widget.savedCampusName.trim().isEmpty) {
                            NexusToast.show(
                              context,
                              'Please enter your college/institute name first to set campus year.',
                              type: NexusToastType.warning,
                            );
                            return;
                          }
                          if (!_isValidCampusName(widget.savedCampusName)) {
                            NexusToast.show(
                              context,
                              'Institute name must contain at least three letters.',
                              type: NexusToastType.error,
                            );
                            return;
                          }
                          widget.onYearChanged(yearOption);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            color: isSelected
                                ? primaryColor
                                : const Color(0xFFF3F4F6),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.transparent
                                  : Colors.black.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Text(
                            label,
                            style: GoogleFonts.plusJakartaSans(
                              color: isSelected ? Colors.white : Colors.black87,
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}
