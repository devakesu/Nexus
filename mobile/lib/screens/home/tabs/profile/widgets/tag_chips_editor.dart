import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../utils/emoji_helper.dart';

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
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setModalState) {
              final filteredPresets = localPresets.where((option) {
                return option.toLowerCase().contains(
                  searchController.text.toLowerCase(),
                );
              }).toList();

              return Container(
                padding: EdgeInsets.only(
                  top: 24,
                  left: 24,
                  right: 24,
                  bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF161B26).withValues(alpha: 0.98),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(30),
                    topRight: Radius.circular(30),
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Select $label',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Outfit',
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text(
                              'Done',
                              style: TextStyle(
                                color: Color(0xFFFF7597),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              LucideIcons.search,
                              color: Colors.white38,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: searchController,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Search...',
                                  hintStyle: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.25),
                                    fontSize: 12,
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
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          physics: const ClampingScrollPhysics(),
                          itemCount: filteredPresets.length,
                          itemBuilder: (context, index) {
                            final option = filteredPresets[index];
                            final isSelected = localSelected.contains(option);
                            return Material(
                              color: Colors.transparent,
                              child: ListTile(
                                onTap: () {
                                  setModalState(() {
                                    if (isSelected) {
                                      localSelected.remove(option);
                                    } else {
                                      localSelected.add(option);
                                    }
                                  });
                                  onChanged(localSelected);
                                },
                                title: Row(
                                  children: [
                                    if (getEmojiForTag(option).isNotEmpty) ...[
                                      Text(
                                        getEmojiForTag(option),
                                        style: const TextStyle(fontSize: 16),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    Expanded(
                                      child: Text(
                                        option,
                                        style: TextStyle(
                                          color: isSelected
                                              ? const Color(0xFFFF7597)
                                              : Colors.white,
                                          fontFamily: 'Outfit',
                                          fontWeight: isSelected
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: isSelected
                                    ? const Icon(
                                        LucideIcons.check,
                                        color: Color(0xFFFF7597),
                                      )
                                    : null,
                              ),
                            );
                          },
                        ),
                      ),
                      if (allowCustom) ...[
                        const SizedBox(height: 16),
                        Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: textController,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: hintText,
                                    hintStyle: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.25,
                                      ),
                                      fontSize: 12,
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
                              const SizedBox(width: 8),
                              GestureDetector(
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
                                  LucideIcons.plus,
                                  color: Color(0xFFFF7597),
                                  size: 18,
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
    const pulsarPink = Color(0xFFFF7597);
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
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
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
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                color: Colors.white.withValues(alpha: 0.3),
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
                  final Map<String, List<String>> grouped = {};
                  for (final val in currentValues) {
                    final parts = val.split(': ');
                    if (parts.length == 2) {
                      grouped.putIfAbsent(parts[0], () => []).add(parts[1]);
                    } else {
                      grouped.putIfAbsent(val, () => []);
                    }
                  }
                  final List<String> merged = [];
                  grouped.forEach((parent, subs) {
                    if (subs.isEmpty) {
                      merged.add(parent);
                    } else {
                      merged.add('$parent: ${subs.join(", ")}');
                    }
                  });
                  displayValues = merged;
                }

                String resolveEmoji(String tag) {
                  var emoji = getEmojiForTag(tag);
                  if (emoji.isEmpty && tag.contains(': ')) {
                    final parent = tag.split(': ')[0];
                    emoji = getEmojiForTag(parent);
                    if (emoji.isEmpty) {
                      final parts = tag.split(': ');
                      if (parts.length == 2) {
                        final subs = parts[1].split(', ');
                        if (subs.isNotEmpty) {
                          emoji = getEmojiForTag(subs[0]);
                        }
                      }
                    }
                  }
                  return emoji;
                }

                return displayValues.map((val) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (resolveEmoji(val).isNotEmpty) ...[
                          Text(
                            resolveEmoji(val),
                            style: const TextStyle(fontSize: 13),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: Text(
                            val,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                            softWrap: true,
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
