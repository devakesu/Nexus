import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/screens/home/widgets/interests_overlay.dart';
import 'package:nexus/theme/app_colors.dart';
import 'package:nexus/widgets/aesthetic_loaders.dart';

class FriendsSettingsOverlay extends StatefulWidget {
  const FriendsSettingsOverlay({
    required this.friendsTargetBuckets,
    required this.flatInterests,
    required this.causesSupported,
    required this.savingFields,
    required this.onSaveFriendsField,
    required this.onLoadFriendsProfileStatusSilent,
    this.isActivating = false,
    this.onToggleOrbitState,
    super.key,
  });

  final List<String> friendsTargetBuckets;
  final List<String> flatInterests;
  final List<String> causesSupported;
  final Set<String> savingFields;
  final Future<void> Function(String field, dynamic value, StateSetter setState)
  onSaveFriendsField;
  final Future<void> Function() onLoadFriendsProfileStatusSilent;
  final bool isActivating;
  final Future<void> Function({required bool active})? onToggleOrbitState;

  @override
  State<FriendsSettingsOverlay> createState() => _FriendsSettingsOverlayState();
}

class _FriendsSettingsOverlayState extends State<FriendsSettingsOverlay> {
  late List<String> localBuckets;
  late List<String> localInterests;
  late List<String> localCauses;

  static const List<String> causesPresets = [
    'Climate Action',
    'Tech Ethics',
    'Mental Health',
    'LGBTQ+ Rights',
    'Education Access',
    'Animal Protection',
    'Disaster Relief',
    'Poverty Alleviation',
    'Gender Equality',
    'Scientific Research',
    'Mental Health Advocacy',
    'Human Rights',
    'Clean Water & Sanitation',
    'Renewable Energy',
    'Economic Development',
    'Arts & Culture Preservation',
  ];

  @override
  void initState() {
    super.initState();
    localBuckets = List<String>.from(widget.friendsTargetBuckets);
    localInterests = List<String>.from(widget.flatInterests);
    localCauses = List<String>.from(widget.causesSupported);
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: 1,
            color: Colors.black.withValues(alpha: 0.06),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(2.5),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(
                      LucideIcons.settings,
                      color: AppColors.modeFriends,
                      size: 24,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Friends Settings',
                      style: TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                // Signal Glow shadow via BoxDecoration, not Material's
                // elevation: prop - DESIGN.md's shadow vocabulary.
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.modeFriends.withValues(alpha: 0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.modeFriends,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () async {
                      Navigator.pop(context);
                      if (widget.isActivating &&
                          widget.onToggleOrbitState != null) {
                        await widget.onToggleOrbitState!(active: true);
                      }
                    },
                    child: Text(
                      widget.isActivating ? 'Turn On Orbit' : 'Done',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              children: [
                _buildSectionHeader(
                  'Discovery Preferences',
                  LucideIcons.compass,
                  AppColors.modeFriends,
                ),

                // Target Buckets
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Who are you open to meeting?',
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (widget.savingFields.contains('friends_target_buckets'))
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: NexusOrbitLoader(size: 16, lightMode: true),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Select who you would like to appear in your Friends Orbit.',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children:
                      [
                        {'code': 'M', 'label': 'Men'},
                        {'code': 'F', 'label': 'Women'},
                        {'code': 'NB', 'label': 'Non-binary'},
                        {'code': 'Open', 'label': 'Open to all'},
                      ].map((item) {
                        final code = item['code']!;
                        final isSelected = localBuckets.contains(code);
                        return FilterChip(
                          label: Text(item['label']!),
                          selected: isSelected,
                          selectedColor: AppColors.modeFriends,
                          backgroundColor: Colors.black.withValues(alpha: 0.04),
                          checkmarkColor: Colors.white,
                          labelStyle: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : const Color(0xFF0F172A),
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          onSelected: (selected) async {
                            setState(() {
                              if (code == 'Open') {
                                if (selected) {
                                  localBuckets
                                    ..clear()
                                    ..add('Open');
                                } else {
                                  localBuckets.remove('Open');
                                }
                              } else {
                                if (selected) {
                                  localBuckets
                                    ..remove('Open')
                                    ..add(code);
                                } else {
                                  localBuckets.remove(code);
                                }
                              }
                            });
                            await widget.onSaveFriendsField(
                              'friends_target_buckets',
                              localBuckets,
                              setState,
                            );
                          },
                        );
                      }).toList(),
                ),
                const SizedBox(height: 12),

                _buildSectionHeader(
                  'More About You',
                  LucideIcons.user,
                  AppColors.modeFriends,
                ),

                // Interests
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Your Interests',
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (widget.savingFields.contains('sub_interests'))
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: NexusOrbitLoader(size: 16, lightMode: true),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Add your interests to find friends who share your passions.',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                if (localInterests.isNotEmpty) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children:
                        localInterests.take(6).map((val) {
                          final label = val.contains(': ')
                              ? val.split(': ').last
                              : val;
                          return Chip(
                            label: Text(label),
                            backgroundColor: AppColors.modeFriends.withValues(
                              alpha: 0.1,
                            ),
                            labelStyle: const TextStyle(
                              color: AppColors.modeFriends,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                            side: BorderSide.none,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          );
                        }).toList()..addAll(
                          localInterests.length > 6
                              ? [
                                  Chip(
                                    label: Text(
                                      '+${localInterests.length - 6} more',
                                    ),
                                    backgroundColor: Colors.black.withValues(
                                      alpha: 0.05,
                                    ),
                                    labelStyle: const TextStyle(
                                      color: Color(0xFF64748B),
                                      fontSize: 12,
                                    ),
                                    side: BorderSide.none,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ]
                              : [],
                        ),
                  ),
                  const SizedBox(height: 12),
                ],
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.modeFriends,
                      side: const BorderSide(
                        color: AppColors.modeFriends,
                        width: 1.5,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(LucideIcons.sparkles, size: 16),
                    label: Text(
                      localInterests.isEmpty
                          ? 'Add Interests'
                          : 'Edit Interests (${localInterests.length})',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    onPressed: () {
                      unawaited(
                        Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => InterestsOverlay(
                              initialSelected: localInterests,
                              onSave: (selected) {
                                setState(() {
                                  localInterests = List<String>.from(selected);
                                });
                                final dict = <String, List<String>>{};
                                for (final item in selected) {
                                  final idx = item.indexOf(': ');
                                  if (idx > 0) {
                                    final parent = item.substring(0, idx);
                                    final sub = item.substring(idx + 2);
                                    dict.putIfAbsent(parent, () => []).add(sub);
                                  }
                                }
                                unawaited(
                                  widget.onSaveFriendsField(
                                    'sub_interests',
                                    dict,
                                    setState,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 32),

                // Causes Supported
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Causes You Support',
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (widget.savingFields.contains('causes_supported'))
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: NexusOrbitLoader(size: 16, lightMode: true),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Connect with friends who care about the same causes as you do.',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                if (localCauses.isNotEmpty) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: localCauses.map((val) {
                      return Chip(
                        label: Text(val),
                        backgroundColor: AppColors.modeFriends.withValues(
                          alpha: 0.1,
                        ),
                        labelStyle: const TextStyle(
                          color: AppColors.modeFriends,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        deleteIcon: const Icon(
                          LucideIcons.x,
                          size: 14,
                          color: AppColors.modeFriends,
                        ),
                        side: BorderSide.none,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        onDeleted: () async {
                          setState(() => localCauses.remove(val));
                          await widget.onSaveFriendsField(
                            'causes_supported',
                            localCauses,
                            setState,
                          );
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                ],
                const Text(
                  'Tap to add:',
                  style: TextStyle(
                    color: Color(0xFF475569),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: causesPresets
                      .where((preset) => !localCauses.contains(preset))
                      .map((val) {
                        return ActionChip(
                          label: Text(val),
                          backgroundColor: Colors.black.withValues(alpha: 0.04),
                          labelStyle: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: BorderSide.none,
                          onPressed: () async {
                            setState(() => localCauses.add(val));
                            await widget.onSaveFriendsField(
                              'causes_supported',
                              localCauses,
                              setState,
                            );
                          },
                        );
                      })
                      .toList(),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
