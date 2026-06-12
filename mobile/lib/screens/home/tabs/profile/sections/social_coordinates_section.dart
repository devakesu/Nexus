import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/screens/home/tabs/profile/widgets/glass_text_field.dart';
import 'package:nexus/screens/home/tabs/profile/widgets/place_autocomplete_field.dart';
import 'package:nexus/screens/home/tabs/profile/widgets/tag_chips_editor.dart';
import 'package:nexus/screens/home/tabs/profile/widgets/universe_section.dart';

class SocialCoordinatesSection extends StatefulWidget {
  const SocialCoordinatesSection({
    required this.hometown,
    required this.currentPlace,
    required this.languages,
    required this.campusName,
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
    super.key,
  });

  final String hometown;
  final String currentPlace;
  final List<String> languages;
  final String campusName;
  final String major;
  final bool isStudying;
  final int year;

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
  State<SocialCoordinatesSection> createState() => _SocialCoordinatesSectionState();
}

class _SocialCoordinatesSectionState extends State<SocialCoordinatesSection> {
  bool _isExpanded = false;

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
      title: 'Social Coordinates',
      description: 'Space-time cluster orientation',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PlaceAutocompleteField(
            label: 'Hometown',
            initialValue: widget.hometown,
            hintText: 'Set your hometown',
            prefixIcon: LucideIcons.home,
            onChanged: widget.onHometownChanged,
            onFieldSubmitted: widget.onHometownSubmitted,
          ),
          const SizedBox(height: 12),

          PlaceAutocompleteField(
            label: 'Current Place',
            initialValue: widget.currentPlace,
            hintText: 'Set your current place',
            prefixIcon: LucideIcons.navigation,
            onChanged: widget.onCurrentPlaceChanged,
            onFieldSubmitted: widget.onCurrentPlaceSubmitted,
          ),
          const SizedBox(height: 16),

          // Languages tag editor
          TagChipsEditor(
            label: 'Languages',
            currentValues: widget.languages,
            presets: const [
              'English',
              'Spanish',
              'Mandarin Chinese',
              'Hindi',
              'Arabic',
              'Portuguese',
              'Bengali',
              'Russian',
              'Japanese',
              'Punjabi',
              'German',
              'Javanese',
              'Wu Chinese',
              'Malay',
              'Telugu',
              'Vietnamese',
              'Korean',
              'French',
              'Marathi',
              'Tamil',
              'Cantonese',
              'Turkish',
              'Urdu',
              'Italian',
              'Thai',
              'Persian',
              'Polish',
              'Kannada',
              'Ukrainian',
              'Filipino',
              'Gujarati',
              'Romanian',
              'Greek',
              'Czech',
              'Swedish',
              'Dutch',
              'Hungarian',
              'Zulu',
              'Hebrew',
              'Finnish',
              'Norwegian',
              'Danish',
              'Swahili',
              'Malayalam',
              'Amharic',
              'Yoruba',
              'Oromo',
              'Igbo',
              'Burmese',
              'Azerbaijani',
              'Maithili',
              'Uzbek',
              'Sindhi',
              'Pashto',
              'Kurdish',
              'Sinhala',
              'Somali',
              'Tagalog',
              'Nepali',
              'Khmer',
              'Lao',
              'Assamese',
              'Malagasy',
              'Slovak',
              'Bulgarian',
              'Croatian',
              'Serbian',
              'Lithuanian',
              'Latvian',
              'Estonian',
              'Slovenian',
              'Irish',
              'Welsh',
              'Icelandic',
              'Catalan',
              'Basque',
              'Galician',
            ],
            icon: LucideIcons.languages,
            iconColor: const Color(0xFF4CAF50),
            onChanged: widget.onLanguagesChanged,
            hintText: 'Select languages...',
            allowCustom: false,
          ),
          const SizedBox(height: 12),

          GlassTextField(
            label: 'Institute Name',
            initialValue: widget.campusName,
            hintText: 'Enter your institute name & location',
            prefixIcon: LucideIcons.mapPin,
            onChanged: widget.onCampusNameChanged,
            onFieldSubmitted: widget.onCampusNameSubmitted,
          ),
          const SizedBox(height: 12),

          GlassTextField(
            label: 'Major',
            initialValue: widget.major,
            hintText: 'Enter your major',
            prefixIcon: LucideIcons.graduationCap,
            onChanged: widget.onMajorChanged,
            onFieldSubmitted: widget.onMajorSubmitted,
          ),
          const SizedBox(height: 12),

          // Campus Year / Student Status Section
          if (!widget.isStudying) ...[
            GestureDetector(
              onTap: () {
                setState(() {
                  _isExpanded = !_isExpanded;
                });
              },
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.02),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      LucideIcons.graduationCap,
                      color: Colors.white38,
                      size: 18,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Add Campus Year / Student Info',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          fontFamily: 'Outfit',
                        ),
                      ),
                    ),
                    Icon(
                      _isExpanded ? LucideIcons.minusCircle : LucideIcons.plusCircle,
                      color: const Color(0xFFFF7597),
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
                      color: Colors.white.withValues(alpha: 0.5),
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
                      final label = '${yearOption == 1 ? "1st" : yearOption == 2 ? "2nd" : yearOption == 3 ? "3rd" : "${yearOption}th"} Year';

                      return GestureDetector(
                        onTap: () {
                          widget.onIsStudyingChanged(true);
                          widget.onYearChanged(yearOption);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            color: const Color(0xFF141822),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Text(
                            label,
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              fontFamily: 'Outfit',
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.02),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Current Student Status',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Outfit',
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Turn off to disable student status',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 12,
                              fontFamily: 'Outfit',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Custom Neon Switch (On state)
                    Container(
                      width: 44,
                      height: 24,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: const Color(0xFFFF7597).withValues(alpha: 0.15),
                        border: Border.all(
                          color: const Color(0xFFFF7597).withValues(alpha: 0.45),
                          width: 1,
                        ),
                      ),
                      child: Stack(
                        children: [
                          Align(
                            alignment: Alignment.centerRight,
                            child: Container(
                              width: 18,
                              height: 18,
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFFF7597),
                                    Color(0xFF00E5FF),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFFF7597).withValues(alpha: 0.5),
                                    blurRadius: 6,
                                    spreadRadius: 1,
                                  ),
                                ],
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
                Text(
                  'CAMPUS YEAR',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
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
                    final isSelected = widget.year == yearOption;
                    final label = '${yearOption == 1 ? "1st" : yearOption == 2 ? "2nd" : yearOption == 3 ? "3rd" : "${yearOption}th"} Year';
                    const pulsarPink = Color(0xFFFF7597);
                    const deepPurple = Color(0xFF00E5FF);

                    return GestureDetector(
                      onTap: () {
                        widget.onYearChanged(yearOption);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: isSelected
                              ? const LinearGradient(
                                  colors: [deepPurple, pulsarPink],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                )
                              : null,
                          color: isSelected ? null : const Color(0xFF141822),
                          border: Border.all(
                            color: isSelected
                                ? Colors.white.withValues(alpha: 0.35)
                                : Colors.white.withValues(alpha: 0.08),
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: pulsarPink.withValues(alpha: 0.25),
                                    blurRadius: 10,
                                    spreadRadius: 1,
                                  )
                                ]
                              : [],
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.white60,
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            fontFamily: 'Outfit',
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
      ),
    );
  }
}
