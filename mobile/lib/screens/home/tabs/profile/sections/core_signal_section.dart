import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/screens/home/tabs/profile/widgets/profile_visibility_badge.dart';
import 'package:nexus/screens/home/tabs/profile/widgets/selector_tile.dart';
import 'package:nexus/screens/home/tabs/profile/widgets/storage_image.dart';
import 'package:nexus/screens/home/tabs/profile/widgets/universe_section.dart';
import 'package:nexus/theme/app_colors.dart';
import 'package:nexus/widgets/aesthetic_loaders.dart';

class CoreSignalSection extends StatefulWidget {
  const CoreSignalSection({
    required this.name,
    required this.age,
    required this.searchBucket,
    required this.displayGender,
    required this.displaySexuality,
    required this.pronouns,
    required this.imagePaths,
    required this.pendingUploads,
    required this.onNameTileTap,
    required this.onAgeTileTap,
    required this.onBucketChanged,
    required this.onSelectGender,
    required this.onSelectSexuality,
    required this.onSelectPronouns,
    required this.onImageSlotTap,
    required this.onSwapImages,
    this.removingSlots = const {},
    this.onClearGender,
    this.onClearSexuality,
    this.onClearPronouns,
    this.isSavingName = false,
    this.isSavingGender = false,
    this.isSavingSexuality = false,
    this.isSavingPronouns = false,
    this.isSavingAge = false,
    this.isSavingBuckets = false,
    super.key,
  });

  final String name;
  final int age;
  final String searchBucket;
  final String displayGender;
  final String displaySexuality;
  final String pronouns;
  final List<String?> imagePaths;
  final Map<int, dynamic> pendingUploads;
  final Set<int> removingSlots;
  final bool isSavingName;
  final bool isSavingGender;
  final bool isSavingSexuality;
  final bool isSavingPronouns;
  final bool isSavingAge;
  final bool isSavingBuckets;

  final VoidCallback onNameTileTap;
  final VoidCallback onAgeTileTap;
  final ValueChanged<String> onBucketChanged;
  final VoidCallback onSelectGender;
  final VoidCallback onSelectSexuality;
  final VoidCallback onSelectPronouns;
  final ValueChanged<int> onImageSlotTap;
  final void Function(int, int) onSwapImages;
  final VoidCallback? onClearGender;
  final VoidCallback? onClearSexuality;
  final VoidCallback? onClearPronouns;

  @override
  State<CoreSignalSection> createState() => _CoreSignalSectionState();
}

class _CoreSignalSectionState extends State<CoreSignalSection> {
  /// A plain label -> value row (icon, uppercase label, value, chevron),
  /// deliberately un-boxed - unlike SelectorTile, tapping this doesn't pick
  /// a value directly, it opens a dedicated confirmation popup (age/name
  /// change sheets), so it shouldn't read as an editable field itself.
  Widget _buildInlineDetailRow({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
    bool isSaving = false,
    bool showDivider = true,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 15, color: const Color(0xFF2D8CFF)),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.black.withValues(alpha: 0.5),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    value,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (isSaving)
                  const SizedBox.square(
                    dimension: 14,
                    child: NexusOrbitLoader(size: 14, lightMode: true),
                  )
                else
                  Icon(
                    LucideIcons.chevronRight,
                    size: 14,
                    color: Colors.black.withValues(alpha: 0.3),
                  ),
              ],
            ),
          ),
          if (showDivider)
            Container(height: 0.5, color: Colors.black.withValues(alpha: 0.08)),
        ],
      ),
    );
  }

  Widget _buildBucketChip({
    required String label,
    required String value,
    required IconData icon,
  }) {
    final isSelected = widget.searchBucket == value;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          widget.onBucketChanged(value);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: isSelected
                ? AppColors.primaryTeal.withValues(alpha: 0.15)
                : Colors.black.withValues(alpha: 0.04),
            border: Border.all(
              color: isSelected
                  ? const Color(
                      0xFF00E5FF,
                    ).withValues(alpha: 0.7)
                  : Colors.black.withValues(alpha: 0.08),
              width: isSelected ? 1.5 : 1.0,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: const Color(
                        0xFF00E5FF,
                      ).withValues(alpha: 0.12),
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
                color: isSelected ? AppColors.primaryTeal : Colors.black38,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? AppColors.primaryTeal : Colors.black87,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
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
    return UniverseSection(
      icon: LucideIcons.user,
      title: 'Core Details',
      description: 'Essential profile details',
      cardColor: const Color(0xFFF0F9FF),
      borderColor: const Color(
        0xFF2D8CFF,
      ).withValues(alpha: 0.4),
      accentColor: const Color(0xFF2D8CFF),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Name & Age - plain inline rows, not boxed like the selector
          // tiles below: tapping opens a dedicated confirmation popup
          // (rate-limited + moderated), it isn't a direct-edit field.
          _buildInlineDetailRow(
            label: 'DISPLAY NAME',
            value: widget.name,
            icon: LucideIcons.user,
            onTap: widget.onNameTileTap,
            isSaving: widget.isSavingName,
          ),
          _buildInlineDetailRow(
            label: 'AGE',
            value: '${widget.age} yrs old',
            icon: LucideIcons.calendar,
            onTap: widget.onAgeTileTap,
            isSaving: widget.isSavingAge,
            showDivider: false,
          ),
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
                      color: Colors.black.withValues(alpha: 0.5),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  if (widget.isSavingBuckets) ...[
                    const SizedBox(width: 8),
                    const NexusOrbitLoader(size: 20, lightMode: true),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Which bucket do you primarily identify as?',
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.45),
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
            onClear: widget.onClearGender,
            isSaving: widget.isSavingGender,
          ),
          const SizedBox(height: 16),
          SelectorTile(
            label: 'SEXUALITY',
            value: widget.displaySexuality,
            icon: LucideIcons.heart,
            iconColor: const Color(0xFFFF2D55),
            onTap: widget.onSelectSexuality,
            onClear: widget.onClearSexuality,
            isSaving: widget.isSavingSexuality,
            visibilityBadge: ProfileVisibilityBadge.datingAndFriends(),
          ),
          const SizedBox(height: 16),
          SelectorTile(
            label: 'PRONOUNS',
            value: widget.pronouns,
            icon: LucideIcons.smile,
            iconColor: const Color(0xFF30B0C7),
            onTap: widget.onSelectPronouns,
            onClear: widget.onClearPronouns,
            isSaving: widget.isSavingPronouns,
          ),
          const SizedBox(height: 16),

          // Gallery slots
          Row(
            children: [
              Text(
                'Images',
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.5),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(width: 6),
              ProfileVisibilityBadge.datingAndFriends(),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(4, (index) {
              final slotIndex = index + 1;
              final imagePath = widget.imagePaths[slotIndex];

              final itemWidget = AnimatedContainer(
                duration: const Duration(milliseconds: 250),
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
                            color: const Color(
                              0xFF00E5FF,
                            ).withValues(alpha: 0.18),
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
                      color: const Color(0xFFE2E8F0),
                      child: Stack(
                        children: [
                          if (imagePath != null) ...[
                            Positioned.fill(
                              child: Opacity(
                                opacity: widget.removingSlots.contains(slotIndex) ? 0.5 : 1.0,
                                child: StorageImage(imagePath: imagePath),
                              ),
                            ),
                            if (widget.pendingUploads.containsKey(slotIndex) ||
                                widget.removingSlots.contains(slotIndex))
                              const Positioned.fill(
                                child: ColoredBox(
                                  color: Colors.black54,
                                  child: Center(
                                    child: NexusOrbitLoader(size: 20),
                                  ),
                                ),
                              ),
                          ] else
                            CustomPaint(
                              painter: _DashedBorderPainter(
                                color: Colors.black.withValues(alpha: 0.15),
                                radius: 18.5,
                              ),
                              child: Center(
                                child: Icon(
                                  LucideIcons.plus,
                                  color: Colors.black.withValues(alpha: 0.3),
                                  size: 20,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );

              return Expanded(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: DragTarget<int>(
                    onWillAcceptWithDetails: (details) =>
                        details.data != slotIndex &&
                        !widget.removingSlots.contains(slotIndex) &&
                        !widget.removingSlots.contains(details.data),
                    onAcceptWithDetails: (details) {
                      widget.onSwapImages(details.data, slotIndex);
                    },
                    builder: (context, candidateData, rejectedData) {
                      final isHovered = candidateData.isNotEmpty;
                      final isRemoving = widget.removingSlots.contains(slotIndex);
                      return LongPressDraggable<int>(
                        data: slotIndex,
                        maxSimultaneousDrags: isRemoving ? 0 : 1,
                        feedback: Material(
                          color: Colors.transparent,
                          child: Opacity(
                            opacity: 0.8,
                            child: SizedBox(
                              width: 72,
                              height: 72,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: imagePath != null
                                    ? StorageImage(imagePath: imagePath)
                                    : Container(
                                        color: const Color(0xFFE2E8F0),
                                      ),
                              ),
                            ),
                          ),
                        ),
                        childWhenDragging: Opacity(
                          opacity: 0.3,
                          child: itemWidget,
                        ),
                        child: GestureDetector(
                          onTap: isRemoving
                              ? null
                              : () => widget.onImageSlotTap(slotIndex),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              border: isHovered
                                  ? Border.all(
                                      color: const Color(0xFFFF2D55),
                                      width: 2,
                                    )
                                  : null,
                            ),
                            child: itemWidget,
                          ),
                        ),
                      );
                    },
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
