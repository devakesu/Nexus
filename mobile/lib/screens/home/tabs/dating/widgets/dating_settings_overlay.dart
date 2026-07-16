import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/theme/app_colors.dart';
import 'package:nexus/widgets/aesthetic_loaders.dart';

class DatingSettingsOverlay extends StatefulWidget {
  const DatingSettingsOverlay({
    required this.datingTargetBuckets,
    required this.datingFor,
    required this.partnerValues,
    required this.savingFields,
    required this.onSaveDatingField,
    required this.onLoadDatingProfileStatusSilent,
    this.isActivating = false,
    this.onToggleOrbitState,
    super.key,
  });

  final List<String> datingTargetBuckets;
  final List<String> datingFor;
  final List<String> partnerValues;
  final Set<String> savingFields;
  final Future<void> Function(String field, dynamic value, StateSetter setState)
  onSaveDatingField;
  final Future<void> Function() onLoadDatingProfileStatusSilent;
  final bool isActivating;
  final Future<void> Function({required bool active})? onToggleOrbitState;

  @override
  State<DatingSettingsOverlay> createState() => _DatingSettingsOverlayState();
}

class _DatingSettingsOverlayState extends State<DatingSettingsOverlay> {
  late List<String> localBuckets;
  late List<String> localDatingFor;
  late List<String> localPartnerValues;
  String searchQuery = '';

  final List<String> predefinedValues = const [
    'Authenticity',
    'Empathy',
    'Ambition',
    'Humility',
    'Kindness',
    'Growth Mindset',
    'Loyalty',
    'Honesty',
    'Creativity',
    'Emotional Maturity',
    'Humor & Wit',
    'Respect',
    'Independence',
    'Curiosity',
    'Communication',
    'Adventure',
    'Financial Stability',
    'Compassion',
    'Family-oriented',
    'Generosity',
    'Open-mindedness',
    'Patience',
    'Self-awareness',
    'Trustworthiness',
    'Spirituality',
    'Optimism',
    'Mindfulness',
    'Intellectual Depth',
    'Fitness-minded',
    'Playfulness',
    'Sincerity',
    'Tolerance',
    'Forgiveness',
    'Resilience',
    'Responsibility',
    'Warmth',
  ];

  @override
  void initState() {
    super.initState();
    localBuckets = List<String>.from(widget.datingTargetBuckets);
    localDatingFor = List<String>.from(widget.datingFor);
    localPartnerValues = List<String>.from(widget.partnerValues);
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
    final filteredValues = predefinedValues
        .where(
          (val) => val.toLowerCase().contains(searchQuery.toLowerCase()),
        )
        .where((val) => !localPartnerValues.contains(val))
        .toList();

    final showCustomOption =
        searchQuery.trim().isNotEmpty &&
        !predefinedValues.any(
          (val) => val.toLowerCase() == searchQuery.trim().toLowerCase(),
        ) &&
        !localPartnerValues.any(
          (val) => val.toLowerCase() == searchQuery.trim().toLowerCase(),
        );

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
                      color: AppColors.modeDating,
                      size: 24,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Dating Settings',
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
                        color: AppColors.modeDating.withValues(alpha: 0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.modeDating,
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
          // Form Fields
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              children: [
                _buildSectionHeader(
                  'Discovery Preferences',
                  LucideIcons.compass,
                  AppColors.modeDating,
                ),

                // Target Buckets (Seeking Gender)
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Who are you interested in meeting?',
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (widget.savingFields.contains('dating_target_buckets'))
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: NexusOrbitLoader(size: 16, lightMode: true),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Select the gender identities you would like to see in your Orbit.',
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
                          selectedColor: AppColors.modeDating,
                          backgroundColor: Colors.black.withValues(
                            alpha: 0.04,
                          ),
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
                            await widget.onSaveDatingField(
                              'dating_target_buckets',
                              localBuckets,
                              setState,
                            );
                          },
                        );
                      }).toList(),
                ),
                const SizedBox(height: 32),

                // Dating For (Relationship Goals)
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'What are you looking for?',
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (widget.savingFields.contains('dating_for'))
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: NexusOrbitLoader(size: 16, lightMode: true),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Select the relationship types you are open to.',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children:
                      [
                        {'code': 'short', 'label': 'Short-term'},
                        {'code': 'long', 'label': 'Long-term'},
                        {'code': 'casual', 'label': 'Casual Dating'},
                        {'code': 'fling', 'label': 'Fling'},
                        {'code': 'hookups', 'label': 'Hookups'},
                        {
                          'code': 'fwb',
                          'label': 'Friends with Benefits',
                        },
                        {'code': 'monogamous', 'label': 'Monogamous'},
                        {'code': 'polyamorous', 'label': 'Polyamorous'},
                        {
                          'code': 'open_rel',
                          'label': 'Open Relationship',
                        },
                        {
                          'code': 'marriage',
                          'label': 'Marriage / Life Partner',
                        },
                        {
                          'code': 'platonic',
                          'label': 'Platonic Dating',
                        },
                        {'code': 'unsure', 'label': 'Figuring it out'},
                      ].map((item) {
                        final code = item['code']!;
                        final isSelected = localDatingFor.contains(
                          code,
                        );
                        return FilterChip(
                          label: Text(item['label']!),
                          selected: isSelected,
                          selectedColor: AppColors.modeDating,
                          backgroundColor: Colors.black.withValues(
                            alpha: 0.04,
                          ),
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
                              if (selected) {
                                localDatingFor.add(code);
                              } else {
                                localDatingFor.remove(code);
                              }
                            });
                            await widget.onSaveDatingField(
                              'dating_for',
                              localDatingFor,
                              setState,
                            );
                          },
                        );
                      }).toList(),
                ),
                const SizedBox(height: 32),

                // Partner Values Input Header
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'What core values are most important to you in a partner?',
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (widget.savingFields.contains('partner_values'))
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: NexusOrbitLoader(size: 16, lightMode: true),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Choose the qualities and shared principles you value most.',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16),

                // Selected Partner Values Chips
                if (localPartnerValues.isNotEmpty) ...[
                  const Text(
                    'Your Selected Values:',
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
                    children: localPartnerValues.map((val) {
                      return Chip(
                        label: Text(val),
                        backgroundColor: AppColors.modeDating.withValues(
                          alpha: 0.1,
                        ),
                        labelStyle: const TextStyle(
                          color: AppColors.modeDating,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        deleteIcon: const Icon(
                          LucideIcons.x,
                          size: 14,
                          color: AppColors.modeDating,
                        ),
                        side: BorderSide.none,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        onDeleted: () async {
                          setState(() {
                            localPartnerValues.remove(val);
                          });
                          await widget.onSaveDatingField(
                            'partner_values',
                            localPartnerValues,
                            setState,
                          );
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                ],

                // Search Bar
                TextField(
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search or add core values...',
                    prefixIcon: const Icon(
                      LucideIcons.search,
                      size: 18,
                      color: Colors.grey,
                    ),
                    filled: true,
                    fillColor: Colors.black.withValues(alpha: 0.04),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.all(16),
                  ),
                  onChanged: (val) {
                    setState(() {
                      searchQuery = val;
                    });
                  },
                ),
                const SizedBox(height: 16),

                // Predefined / Filtered Choices
                const Text(
                  'Tap to select values:',
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
                  children: [
                    if (showCustomOption)
                      ActionChip(
                        avatar: const Icon(
                          LucideIcons.plus,
                          size: 14,
                          color: Colors.white,
                        ),
                        label: Text('Add "${searchQuery.trim()}"'),
                        backgroundColor: AppColors.modeDating,
                        labelStyle: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        onPressed: () async {
                          setState(() {
                            localPartnerValues.add(searchQuery.trim());
                            searchQuery = '';
                          });
                          await widget.onSaveDatingField(
                            'partner_values',
                            localPartnerValues,
                            setState,
                          );
                        },
                      ),
                    ...filteredValues.map((val) {
                      return ActionChip(
                        label: Text(val),
                        backgroundColor: Colors.black.withValues(
                          alpha: 0.04,
                        ),
                        labelStyle: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: BorderSide.none,
                        onPressed: () async {
                          setState(() {
                            localPartnerValues.add(val);
                          });
                          await widget.onSaveDatingField(
                            'partner_values',
                            localPartnerValues,
                            setState,
                          );
                        },
                      );
                    }),
                  ],
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
