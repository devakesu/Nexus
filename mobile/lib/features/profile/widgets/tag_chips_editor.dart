import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/core/widgets/aesthetic_loaders.dart';
import 'package:nexus/features/profile/utils/emoji_helper.dart';

class TagChipsEditor extends StatelessWidget {
  const TagChipsEditor({
    required this.label,
    required this.currentValues,
    required this.presets,
    required this.icon,
    required this.iconColor,
    required this.onChanged,
    required this.hintText,
    this.allowCustom = true,
    this.onTapEdit,
    this.showEdit = true,
    this.isSaving = false,
    this.exclusiveOptions = const [],
    this.visibilityBadge,
    super.key,
  });

  final String label;
  final List<String> currentValues;
  final List<String> presets;
  final IconData icon;
  final Color iconColor;
  final ValueChanged<List<String>> onChanged;
  final String hintText;
  final bool allowCustom;
  final VoidCallback? onTapEdit;
  final bool showEdit;
  final bool isSaving;
  final Widget? visibilityBadge;

  /// Options that are mutually exclusive with everything else.
  /// Selecting one clears all other selections; selecting a non-exclusive
  /// option removes any currently selected exclusive ones.
  final List<String> exclusiveOptions;

  void _openMultiSelectSheet(BuildContext context) {
    final localSelected = List<String>.from(currentValues);
    final localPresets = List<String>.from(presets);

    // Combine presets and any custom selected values that are not in presets
    for (final val in localSelected) {
      if (!localPresets.contains(val)) {
        localPresets.add(val);
      }
    }

    final textController = TextEditingController();
    final searchController = TextEditingController();

    unawaited(
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        barrierColor: Colors.black.withValues(alpha: 0.8),
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setModalState) {
              final showSearch = localPresets.length > 10;
              final filteredPresets = showSearch
                  ? localPresets.where((option) {
                      return option.toLowerCase().contains(
                        searchController.text.toLowerCase(),
                      );
                    }).toList()
                  : localPresets;

              return Container(
                padding: EdgeInsets.only(
                  top: 12,
                  left: 20,
                  right: 20,
                  bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(28),
                    topRight: Radius.circular(28),
                  ),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.08),
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 38,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 18),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Select $label',
                            style: const TextStyle(
                              color: AppColors.ink,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text(
                              'Done',
                              style: TextStyle(
                                color: AppColors.pulsarPink,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (showSearch) ...[
                        Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.black.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                LucideIcons.search,
                                color: Colors.black38,
                                size: 16,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: searchController,
                                  style: const TextStyle(
                                    color: AppColors.ink,
                                    fontSize: 13,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'Search presets...',
                                    hintStyle: TextStyle(
                                      color: Colors.black.withValues(
                                        alpha: 0.25,
                                      ),
                                      fontSize: 13,
                                    ),
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                  onChanged: (val) {
                                    setModalState(() {});
                                  },
                                ),
                              ),
                              if (searchController.text.isNotEmpty)
                                Semantics(
                                  button: true,
                                  label: 'Clear search',
                                  excludeSemantics: true,
                                  onTap: () {
                                    searchController.clear();
                                    setModalState(() {});
                                  },
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      searchController.clear();
                                      setModalState(() {});
                                    },
                                    child: const SizedBox(
                                      width: 44,
                                      height: 44,
                                      child: Center(
                                        child: Icon(
                                          LucideIcons.xCircle,
                                          color: Colors.black38,
                                          size: 16,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight:
                              MediaQuery.of(context).size.height *
                              (MediaQuery.of(context).viewInsets.bottom > 0
                                  ? 0.22
                                  : 0.4),
                        ),
                        child: ShaderMask(
                          shaderCallback: (bounds) {
                            return const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.white, Colors.transparent],
                              stops: [0.90, 1.0],
                            ).createShader(bounds);
                          },
                          blendMode: BlendMode.dstIn,
                          child: ListView.separated(
                            shrinkWrap: true,
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.only(bottom: 20),
                            itemCount: filteredPresets.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final option = filteredPresets[index];
                              final isSelected = localSelected.contains(option);
                              final tagIcon = getTagIcon(
                                option,
                                iconSize: 14,
                                iconColor: isSelected
                                    ? AppColors.pulsarPink
                                    : Colors.black38,
                              );

                              void handleTap() {
                                setModalState(() {
                                  if (isSelected) {
                                    localSelected.remove(option);
                                  } else if (exclusiveOptions.contains(
                                    option,
                                  )) {
                                    localSelected
                                      ..clear()
                                      ..add(option);
                                  } else {
                                    localSelected
                                      ..removeWhere(
                                        exclusiveOptions.contains,
                                      )
                                      ..add(option);
                                  }
                                });
                                onChanged(localSelected);
                                if (!isSelected &&
                                    exclusiveOptions.contains(option)) {
                                  Navigator.pop(context);
                                }
                              }

                              return Semantics(
                                selected: isSelected,
                                button: true,
                                label: option,
                                excludeSemantics: true,
                                onTap: handleTap,
                                child: GestureDetector(
                                  onTap: handleTap,
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? AppColors.pulsarPink.withValues(
                                              alpha: 0.08,
                                            )
                                          : const Color(0xFFF9FAFB),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isSelected
                                            ? AppColors.pulsarPink.withValues(
                                                alpha: 0.45,
                                              )
                                            : Colors.black.withValues(
                                                alpha: 0.05,
                                              ),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        if (isSelected) ...[
                                          Container(
                                            width: 3,
                                            height: 14,
                                            decoration: BoxDecoration(
                                              color: AppColors.pulsarPink,
                                              borderRadius:
                                                  BorderRadius.circular(
                                                    1.5,
                                                  ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                        ],
                                        if (tagIcon != null) ...[
                                          tagIcon,
                                          const SizedBox(width: 12),
                                        ] else ...[
                                          Icon(
                                            LucideIcons.sparkles,
                                            size: 14,
                                            color: isSelected
                                                ? AppColors.pulsarPink
                                                : Colors.black38,
                                          ),
                                          const SizedBox(width: 12),
                                        ],
                                        Expanded(
                                          child: Text(
                                            option,
                                            style: TextStyle(
                                              color: isSelected
                                                  ? AppColors.ink
                                                  : const Color(0xFF475569),
                                              fontSize: 14,
                                              fontWeight: isSelected
                                                  ? FontWeight.bold
                                                  : FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                        if (isSelected)
                                          const Icon(
                                            LucideIcons.checkCircle,
                                            color: AppColors.pulsarPink,
                                            size: 16,
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      if (allowCustom) ...[
                        const SizedBox(height: 16),
                        Container(
                          height: 46,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.black.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: textController,
                                  style: const TextStyle(
                                    color: AppColors.ink,
                                    fontSize: 13,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: hintText,
                                    hintStyle: TextStyle(
                                      color: Colors.black.withValues(
                                        alpha: 0.25,
                                      ),
                                      fontSize: 13,
                                    ),
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                  onSubmitted: (val) {
                                    final trimmed = val.trim();
                                    if (trimmed.isNotEmpty &&
                                        !localPresets.contains(trimmed)) {
                                      setModalState(() {
                                        localPresets.add(trimmed);
                                        localSelected.add(trimmed);
                                      });
                                      onChanged(localSelected);
                                      textController.clear();
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Semantics(
                                button: true,
                                label: 'Add tag',
                                excludeSemantics: true,
                                onTap: () {
                                  final trimmed = textController.text.trim();
                                  if (trimmed.isNotEmpty &&
                                      !localPresets.contains(trimmed)) {
                                    setModalState(() {
                                      localPresets.add(trimmed);
                                      localSelected.add(trimmed);
                                    });
                                    onChanged(localSelected);
                                    textController.clear();
                                  }
                                },
                                child: GestureDetector(
                                  onTap: () {
                                    final trimmed = textController.text.trim();
                                    if (trimmed.isNotEmpty &&
                                        !localPresets.contains(trimmed)) {
                                      setModalState(() {
                                        localPresets.add(trimmed);
                                        localSelected.add(trimmed);
                                      });
                                      onChanged(localSelected);
                                      textController.clear();
                                    }
                                  },
                                  child: const Icon(
                                    LucideIcons.plusCircle,
                                    color: AppColors.pulsarPink,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ).then((_) {
        FocusManager.instance.primaryFocus?.unfocus();
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    const pulsarPink = AppColors.pulsarPink;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor, size: 18),
                const SizedBox(width: 8),
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    color: Colors.black.withValues(alpha: 0.6),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                if (visibilityBadge != null) ...[
                  const SizedBox(width: 6),
                  visibilityBadge!,
                ],
                if (isSaving) ...[
                  const SizedBox(width: 8),
                  const NexusOrbitLoader(size: 20),
                ],
              ],
            ),
            if (showEdit)
              TextButton.icon(
                onPressed: () {
                  if (onTapEdit != null) {
                    onTapEdit!();
                  } else {
                    _openMultiSelectSheet(context);
                  }
                },
                icon: const Icon(LucideIcons.plus, size: 12, color: pulsarPink),
                label: const Text(
                  'Edit',
                  style: TextStyle(
                    color: pulsarPink,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (currentValues.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 26),
            child: Text(
              'No $label added yet',
              style: TextStyle(
                color: Colors.black.withValues(alpha: 0.4),
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(left: 26),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: () {
                var displayValues = currentValues;
                if (label.toLowerCase() == 'interests') {
                  final grouped = <String, List<String>>{};
                  for (final val in currentValues) {
                    final parts = val.split(': ');
                    if (parts.length == 2) {
                      grouped.putIfAbsent(parts[0], () => []).add(parts[1]);
                    } else {
                      grouped.putIfAbsent(val, () => []);
                    }
                  }
                  final merged = <String>[];
                  grouped.forEach((parent, subs) {
                    if (subs.isEmpty) {
                      merged.add(parent);
                    } else {
                      merged.add('$parent: ${subs.join(", ")}');
                    }
                  });
                  displayValues = merged;
                }

                Widget? resolveTagIcon(String tag) {
                  var icon = getTagIcon(tag, iconSize: 13);
                  if (icon == null && tag.contains(': ')) {
                    final parent = tag.split(': ')[0];
                    icon = getTagIcon(parent, iconSize: 13);
                    if (icon == null) {
                      final parts = tag.split(': ');
                      if (parts.length == 2) {
                        final subs = parts[1].split(', ');
                        if (subs.isNotEmpty) {
                          icon = getTagIcon(subs[0], iconSize: 13);
                        }
                      }
                    }
                  }
                  return icon;
                }

                return displayValues.map((val) {
                  final tagIcon = resolveTagIcon(val);
                  return Container(
                    padding: const EdgeInsets.only(
                      left: 10,
                      right: 6,
                      top: 6,
                      bottom: 6,
                    ),
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: iconColor.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (tagIcon != null) ...[
                          tagIcon,
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: Text(
                            val,
                            style: const TextStyle(
                              color: AppColors.ink,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                            softWrap: true,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Semantics(
                          button: true,
                          label: 'Remove $val',
                          excludeSemantics: true,
                          onTap: () {
                            final List<String> newValues;
                            if (label.toLowerCase() == 'interests' &&
                                val.contains(': ')) {
                              final parent = val.split(': ')[0];
                              newValues = currentValues
                                  .where((v) => !v.startsWith('$parent: '))
                                  .toList();
                            } else {
                              newValues = currentValues
                                  .where((v) => v != val)
                                  .toList();
                            }
                            onChanged(newValues);
                          },
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              final List<String> newValues;
                              if (label.toLowerCase() == 'interests' &&
                                  val.contains(': ')) {
                                final parent = val.split(': ')[0];
                                newValues = currentValues
                                    .where((v) => !v.startsWith('$parent: '))
                                    .toList();
                              } else {
                                newValues = currentValues
                                    .where((v) => v != val)
                                    .toList();
                              }
                              onChanged(newValues);
                            },
                            child: Icon(
                              LucideIcons.x,
                              size: 11,
                              color: iconColor.withValues(alpha: 0.65),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList();
              }(),
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }
}
