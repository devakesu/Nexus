import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../widgets/universe_section.dart';
import '../widgets/place_autocomplete_field.dart';
import '../widgets/glass_text_field.dart';
import '../widgets/tag_chips_editor.dart';

class SocialCoordinatesSection extends StatelessWidget {
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
            initialValue: hometown,
            hintText: 'Set your hometown',
            prefixIcon: LucideIcons.home,
            onChanged: onHometownChanged,
            onFieldSubmitted: onHometownSubmitted,
          ),
          const SizedBox(height: 12),

          PlaceAutocompleteField(
            label: 'Current Place',
            initialValue: currentPlace,
            hintText: 'Set your current place',
            prefixIcon: LucideIcons.navigation,
            onChanged: onCurrentPlaceChanged,
            onFieldSubmitted: onCurrentPlaceSubmitted,
          ),
          const SizedBox(height: 16),

          // Languages tag editor
          TagChipsEditor(
            label: 'Languages',
            currentValues: languages,
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
            onChanged: onLanguagesChanged,
            hintText: 'Select languages...',
            allowCustom: false,
          ),
          const SizedBox(height: 12),

          GlassTextField(
            label: 'Institute Name',
            initialValue: campusName,
            hintText: 'Enter your institute name & location',
            prefixIcon: LucideIcons.mapPin,
            onChanged: onCampusNameChanged,
            onFieldSubmitted: onCampusNameSubmitted,
          ),
          const SizedBox(height: 12),

          GlassTextField(
            label: 'Major',
            initialValue: major,
            hintText: 'Enter your major',
            prefixIcon: LucideIcons.graduationCap,
            onChanged: onMajorChanged,
            onFieldSubmitted: onMajorSubmitted,
          ),
          const SizedBox(height: 12),

          // Studying checkbox
          Row(
            children: [
              Theme(
                data: ThemeData(
                  unselectedWidgetColor: const Color(0x66FFFFFF),
                ),
                child: Checkbox(
                  value: isStudying,
                  activeColor: const Color(0xFF7C3AED),
                  checkColor: Colors.white,
                  onChanged: (val) {
                    onIsStudyingChanged(val ?? false);
                  },
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Are you currently studying in this institute?',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontFamily: 'Outfit',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (isStudying) ...[
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
                    final isSelected = year == yearOption;
                    final label = '${yearOption == 1 ? "1st" : yearOption == 2 ? "2nd" : yearOption == 3 ? "3rd" : "${yearOption}th"} Year';
                    return GestureDetector(
                      onTap: () {
                        onYearChanged(yearOption);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF7C3AED).withValues(alpha: 0.15)
                              : Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFFFF7597).withValues(alpha: 0.8)
                                : Colors.white.withValues(alpha: 0.1),
                            width: isSelected ? 1.5 : 1,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFFFF7597).withValues(alpha: 0.1),
                                    blurRadius: 4,
                                    spreadRadius: 0.5,
                                  )
                                ]
                              : [],
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.white60,
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            fontFamily: 'Outfit',
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
