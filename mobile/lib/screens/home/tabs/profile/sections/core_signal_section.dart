import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/screens/home/tabs/profile/widgets/glass_text_field.dart';
import 'package:nexus/screens/home/tabs/profile/widgets/neon_slider.dart';
import 'package:nexus/screens/home/tabs/profile/widgets/selector_tile.dart';
import 'package:nexus/screens/home/tabs/profile/widgets/storage_image.dart';
import 'package:nexus/screens/home/tabs/profile/widgets/universe_section.dart';

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
    this.isSavingName = false,
    this.isSavingGender = false,
    this.isSavingSexuality = false,
    this.isSavingPronouns = false,
    this.isSavingAge = false,
    this.isSavingBuckets = false,
    this.nameFocusNode,
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
  final bool isSavingName;
  final bool isSavingGender;
  final bool isSavingSexuality;
  final bool isSavingPronouns;
  final bool isSavingAge;
  final bool isSavingBuckets;

  final ValueChanged<String> onNameChanged;
  final ValueChanged<String> onNameSubmitted;
  final ValueChanged<int> onAgeChanged;
  final ValueChanged<int> onAgeConfirmed;
  final ValueChanged<List<String>> onBucketChanged;
  final VoidCallback onSelectGender;
  final VoidCallback onSelectSexuality;
  final VoidCallback onSelectPronouns;
  final ValueChanged<int> onImageSlotTap;
  final FocusNode? nameFocusNode;

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

  Widget _buildBucketChip({
    required String label,
    required String value,
    required IconData icon,
  }) {
    final isSelected = widget.searchBuckets.contains(value);

    return Expanded(
      child: GestureDetector(
        onTap: () {
          widget.onBucketChanged([value]);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: isSelected
                ? const Color(0xFF0891B2).withValues(alpha: 0.25)
                : Colors.white.withValues(alpha: 0.02),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF00E5FF).withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.08),
              width: isSelected ? 1.5 : 1.0,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: const Color(0xFF00E5FF).withValues(alpha: 0.25),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 13,
                color: isSelected ? const Color(0xFF00E5FF) : Colors.white38,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  fontFamily: 'Outfit',
                ),
              ),
            ],
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
      title: 'Core Details',
      description: 'Essential profile details',
      cardColor: const Color(0xFF0D1424),
      borderColor: const Color(0xFF2D8CFF).withValues(alpha: 0.35),
      accentColor: const Color(0xFF2D8CFF),
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
            isSaving: widget.isSavingName,
            focusNode: widget.nameFocusNode,
          ),

          // Age slider
          NeonSlider(
            value: widget.age.toDouble(),
            min: 18,
            max: 27,
            divisions: 9,
            label: 'Age',
            isSaving: widget.isSavingAge,
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
                      backgroundColor: const Color(0xFF0891B2),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
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
              Row(
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
                  if (widget.isSavingBuckets) ...[
                    const SizedBox(width: 8),
                    const SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        valueColor: AlwaysStoppedAnimation<Color>(pulsarPink),
                      ),
                    ),
                  ],
                ],
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
                  _buildBucketChip(
                    label: 'Men',
                    value: 'M',
                    icon: LucideIcons.user,
                  ),
                  const SizedBox(width: 8),
                  _buildBucketChip(
                    label: 'Women',
                    value: 'F',
                    icon: LucideIcons.user,
                  ),
                  const SizedBox(width: 8),
                  _buildBucketChip(
                    label: 'Non-Binary',
                    value: 'NB',
                    icon: LucideIcons.sparkles,
                  ),
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
            isSaving: widget.isSavingGender,
          ),
          const SizedBox(height: 16),
          SelectorTile(
            label: 'SEXUALITY',
            value: widget.displaySexuality,
            icon: LucideIcons.heart,
            iconColor: const Color(0xFFFF2D55),
            onTap: widget.onSelectSexuality,
            isSaving: widget.isSavingSexuality,
          ),
          const SizedBox(height: 16),
          SelectorTile(
            label: 'PRONOUNS',
            value: widget.pronouns,
            icon: LucideIcons.smile,
            iconColor: const Color(0xFF30B0C7),
            onTap: widget.onSelectPronouns,
            isSaving: widget.isSavingPronouns,
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
                      borderRadius: BorderRadius.circular(20),
                      border: imagePath != null
                          ? Border.all(
                              color: const Color(0xFF00E5FF),
                              width: 1.5,
                            )
                          : null,
                      boxShadow: imagePath != null
                          ? [
                              BoxShadow(
                                color: const Color(0xFF00E5FF).withValues(alpha: 0.18),
                                blurRadius: 10,
                                spreadRadius: 0.5,
                              ),
                            ]
                          : null,
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(imagePath != null ? 1.5 : 0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18.5),
                        child: ColoredBox(
                          color: const Color(0xFF141822),
                          child: Stack(
                            children: [
                              if (imagePath != null) ...[
                                Positioned.fill(
                                  child: StorageImage(imagePath: imagePath),
                                ),
                                if ((widget.isProcessingAI ||
                                        widget.isSaving) &&
                                    widget.pendingUploads.containsKey(
                                      slotIndex,
                                    ))
                                  const Positioned.fill(
                                    child: ColoredBox(
                                      color: Colors.black54,
                                      child: Center(
                                        child: SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                  pulsarPink,
                                                ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ] else
                                CustomPaint(
                                  painter: _DashedBorderPainter(
                                    color: Colors.white.withValues(alpha: 0.18),
                                    radius: 18.5,
                                  ),
                                  child: const Center(
                                    child: Icon(
                                      LucideIcons.plus,
                                      color: Colors.white30,
                                      size: 20,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
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

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({
    required this.color,
    required this.radius,
  });

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0.6, 0.6, size.width - 1.2, size.height - 1.2),
          Radius.circular(radius),
        ),
      );

    final dashedPath = Path();
    const dashLength = 4;
    const gapLength = 3;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      var draw = true;
      while (distance < metric.length) {
        final length = draw ? dashLength : gapLength;
        if (draw) {
          dashedPath.addPath(
            metric.extractPath(
              distance,
              (distance + length).clamp(0.0, metric.length),
            ),
            Offset.zero,
          );
        }
        distance += length;
        draw = !draw;
      }
    }

    canvas.drawPath(dashedPath, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
