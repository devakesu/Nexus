import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../widgets/universe_section.dart';
import '../widgets/glass_text_field.dart';
import '../widgets/neon_slider.dart';
import '../widgets/selector_tile.dart';
import '../widgets/storage_image.dart';

class CoreSignalSection extends StatefulWidget {
  const CoreSignalSection({
    required this.name,
    required this.age,
    required this.savedAge,
    required this.searchBuckets,
    required this.displayGender,
    required this.displaySexuality,
    required this.pronouns,
    required this.imagePaths,
    required this.isProcessingAI,
    required this.isSaving,
    required this.pendingUploads,
    required this.onNameChanged,
    required this.onNameSubmitted,
    required this.onAgeChanged,
    required this.onAgeConfirmed,
    required this.onBucketChanged,
    required this.onSelectGender,
    required this.onSelectSexuality,
    required this.onSelectPronouns,
    required this.onImageSlotTap,
    super.key,
  });

  final String name;
  final int age;
  final int savedAge;
  final List<String> searchBuckets;
  final String displayGender;
  final String displaySexuality;
  final String pronouns;
  final List<String?> imagePaths;
  final bool isProcessingAI;
  final bool isSaving;
  final Map<int, dynamic> pendingUploads;

  final ValueChanged<String> onNameChanged;
  final ValueChanged<String> onNameSubmitted;
  final ValueChanged<int> onAgeChanged;
  final ValueChanged<int> onAgeConfirmed;
  final ValueChanged<List<String>> onBucketChanged;
  final VoidCallback onSelectGender;
  final VoidCallback onSelectSexuality;
  final VoidCallback onSelectPronouns;
  final ValueChanged<int> onImageSlotTap;

  @override
  State<CoreSignalSection> createState() => _CoreSignalSectionState();
}

class _CoreSignalSectionState extends State<CoreSignalSection> {
  bool _ageChangedSinceInteract = false;

  @override
  void didUpdateWidget(covariant CoreSignalSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.age == widget.savedAge) {
      _ageChangedSinceInteract = false;
    }
  }

  Widget _buildBucketChip({required String label, required String value}) {
    final isSelected = widget.searchBuckets.contains(value);
    const pulsarPink = Color(0xFFFF7597);
    const deepPurple = Color(0xFF7C3AED);

    return Expanded(
      child: GestureDetector(
        onTap: () {
          widget.onBucketChanged([value]);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? deepPurple.withValues(alpha: 0.15)
                : Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? pulsarPink.withValues(alpha: 0.8)
                  : Colors.white.withValues(alpha: 0.1),
              width: isSelected ? 1.5 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: pulsarPink.withValues(alpha: 0.25),
                      blurRadius: 8,
                      spreadRadius: 1,
                    )
                  ]
                : [],
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontFamily: 'Outfit',
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const pulsarPink = Color(0xFFFF7597);
    const mistLavender = Color(0xFFE2D9F3);

    return UniverseSection(
      icon: LucideIcons.user,
      title: 'The Core Signal',
      description: 'Essential dimensional settings',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Display Name
          GlassTextField(
            label: 'Display Name',
            initialValue: widget.name,
            hintText: 'Enter your cosmic display name',
            prefixIcon: LucideIcons.user,
            onChanged: widget.onNameChanged,
            onFieldSubmitted: widget.onNameSubmitted,
          ),

          // Age slider
          NeonSlider(
            value: widget.age.toDouble(),
            min: 18,
            max: 27,
            divisions: 9,
            label: 'Age',
            onChanged: (val) {
              final newAge = val.round();
              widget.onAgeChanged(newAge);
              setState(() {
                _ageChangedSinceInteract = newAge != widget.savedAge;
              });
            },
          ),
          if (_ageChangedSinceInteract) ...[
            const SizedBox(height: 8),
            Center(
              child: AnimatedSize(
                duration: const Duration(milliseconds: 200),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7C3AED),
                      foregroundColor: Colors.white,
                      shadowColor: const Color(0xFFFF7597).withValues(alpha: 0.5),
                      elevation: 8,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Color(0xFFFF7597)),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () {
                      setState(() {
                        _ageChangedSinceInteract = false;
                      });
                      widget.onAgeConfirmed(widget.age);
                    },
                    icon: const Icon(LucideIcons.checkCircle, size: 16),
                    label: Text(
                      'Confirm Age Update to ${widget.age}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 0.5,
                        fontFamily: 'Outfit',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),

          // Demographic Buckets
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'DEMOGRAPHIC BUCKETS',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Which bucket do you primarily identify as?',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontSize: 10,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildBucketChip(label: 'Men', value: 'M'),
                  const SizedBox(width: 8),
                  _buildBucketChip(label: 'Women', value: 'F'),
                  const SizedBox(width: 8),
                  _buildBucketChip(label: 'Non-Binary', value: 'NB'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Selector tiles
          SelectorTile(
            label: 'GENDER',
            value: widget.displayGender,
            icon: LucideIcons.user,
            iconColor: const Color(0xFFE91E63),
            onTap: widget.onSelectGender,
          ),
          const SizedBox(height: 16),
          SelectorTile(
            label: 'SEXUALITY',
            value: widget.displaySexuality,
            icon: LucideIcons.heart,
            iconColor: const Color(0xFFFF2D55),
            onTap: widget.onSelectSexuality,
          ),
          const SizedBox(height: 16),
          SelectorTile(
            label: 'PRONOUNS',
            value: widget.pronouns,
            icon: LucideIcons.smile,
            iconColor: const Color(0xFF30B0C7),
            onTap: widget.onSelectPronouns,
          ),
          const SizedBox(height: 16),

          // Gallery slots
          Text(
            'Images',
            style: TextStyle(
              color: mistLavender.withValues(alpha: 0.6),
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(4, (index) {
              final slotIndex = index + 1;
              final imagePath = widget.imagePaths[slotIndex];

              return Expanded(
                child: GestureDetector(
                  onTap: () => widget.onImageSlotTap(slotIndex),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    height: 72,
                    margin: EdgeInsets.only(
                      left: index == 0 ? 0 : 4,
                      right: index == 3 ? 0 : 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: imagePath != null
                            ? const Color(0xFF7C3AED)
                            : Colors.white.withValues(alpha: 0.12),
                        width: imagePath != null ? 1.5 : 1,
                      ),
                      boxShadow: imagePath != null
                          ? [
                              BoxShadow(
                                color: const Color(0xFF7C3AED).withValues(alpha: 0.3),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ]
                          : [],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Stack(
                        children: [
                          if (imagePath != null) ...[
                            Positioned.fill(
                              child: StorageImage(imagePath: imagePath),
                            ),
                            if ((widget.isProcessingAI || widget.isSaving) &&
                                widget.pendingUploads.containsKey(slotIndex))
                              Positioned.fill(
                                child: Container(
                                  color: Colors.black54,
                                  child: const Center(
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(pulsarPink),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ] else
                            const Center(
                              child: Icon(
                                LucideIcons.plus,
                                color: Colors.white24,
                                size: 22,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
