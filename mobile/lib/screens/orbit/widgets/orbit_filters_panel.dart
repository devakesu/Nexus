import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/config/app_config.dart';
import 'package:nexus/config/filter_options.dart';
import 'package:nexus/screens/home/widgets/interests_overlay.dart';

class OrbitFiltersPanel extends StatefulWidget {
  const OrbitFiltersPanel({
    required this.tab,
    required this.themeColor,
    required this.ageRange,
    required this.selectedDrinking,
    required this.selectedSmoking,
    required this.selectedLanguages,
    required this.selectedSubInterests,
    required this.selectedYears,
    required this.selectedChildrenPlans,
    required this.selectedReligiousBeliefs,
    required this.selectedShowBuckets,
    required this.selectedDatingFor,
    required this.selectedPartnerValues,
    required this.dealbreakerFields,
    required this.selectedLookingFor,
    required this.selectedTechSkills,
    required this.savingFields,
    required this.onAgeRangeChanged,
    required this.onAgeRangeChangeEnd,
    required this.onSaveDatingField,
    required this.onOpenTagSelectionPane,
    required this.onOpenPartnerValuesSelectionPane,
    required this.isRefreshing,
    required this.onFetchOrbitNodes,
    required this.scrollController,
    super.key,
  });

  final String tab;
  final Color themeColor;
  final RangeValues ageRange;
  final List<String> selectedDrinking;
  final List<String> selectedSmoking;
  final List<String> selectedLanguages;
  final List<String> selectedSubInterests;
  final List<int> selectedYears;
  final List<String> selectedChildrenPlans;
  final List<String> selectedReligiousBeliefs;
  final List<String> selectedShowBuckets;
  final List<String> selectedDatingFor;
  final List<String> selectedPartnerValues;
  final Set<String> dealbreakerFields;
  final List<String> selectedLookingFor;
  final List<String> selectedTechSkills;
  final Set<String> savingFields;

  final ValueChanged<RangeValues> onAgeRangeChanged;
  final ValueChanged<RangeValues> onAgeRangeChangeEnd;
  final Future<void> Function(
    String field,
    dynamic value,
    StateSetter setModalState,
  )
  onSaveDatingField;
  final void Function(
    String title,
    List<String> options,
    List<String> selected,
    StateSetter setModalState,
  )
  onOpenTagSelectionPane;
  final void Function(StateSetter setModalState, List<String> predefinedValues)
  onOpenPartnerValuesSelectionPane;
  final bool isRefreshing;
  final Future<void> Function() onFetchOrbitNodes;
  final ScrollController scrollController;

  @override
  State<OrbitFiltersPanel> createState() => _OrbitFiltersPanelState();
}

class _OrbitFiltersPanelState extends State<OrbitFiltersPanel> {
  late RangeValues _ageRange;

  @override
  void initState() {
    super.initState();
    _ageRange = widget.ageRange;
  }

  @override
  void didUpdateWidget(covariant OrbitFiltersPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ageRange != widget.ageRange) {
      _ageRange = widget.ageRange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.themeColor;
    final ageMax = AppConfig.current.isMainVariant ? 80.0 : 27.0;
    final ageDivisions = AppConfig.current.isMainVariant ? 62 : 9;
    final predefinedValues = <String>[
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

    Widget filterChips(
      List<String> options,
      List<String> selected,
    ) {
      return Wrap(
        spacing: 8,
        runSpacing: 6,
        children: options.map((opt) {
          final sel = selected.contains(opt);
          return FilterChip(
            label: Text(
              opt,
              style: TextStyle(
                fontSize: 12,
                color: sel ? theme : Colors.white60,
              ),
            ),
            selected: sel,
            selectedColor: theme.withValues(alpha: 0.15),
            backgroundColor: Colors.white.withValues(alpha: 0.05),
            checkmarkColor: theme,
            side: BorderSide(
              color: sel ? theme : Colors.white.withValues(alpha: 0.2),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            onSelected: (v) {
              setState(() {
                if (v) {
                  if (options == FilterOptions.drinking ||
                      options == FilterOptions.smoking) {
                    if (opt == 'Never') {
                      selected.clear();
                    } else {
                      selected.remove('Never');
                    }
                  } else if (options == FilterOptions.childrenPlans) {
                    if (opt == 'Not specified') {
                      selected.clear();
                    } else {
                      selected.remove('Not specified');
                    }
                  } else if (options == FilterOptions.religiousBeliefs) {
                    if (opt == 'Atheist' || opt == 'Agnostic') {
                      selected.removeWhere(
                        (item) => item != 'Atheist' && item != 'Agnostic',
                      );
                    } else if (opt == 'Not specified') {
                      selected.clear();
                    } else {
                      selected
                        ..remove('Atheist')
                        ..remove('Agnostic')
                        ..remove('Not specified');
                    }
                  }
                  selected.add(opt);
                } else {
                  selected.remove(opt);
                }
              });
              unawaited(widget.onFetchOrbitNodes());
            },
          );
        }).toList(),
      );
    }

    Widget codeChips(
      List<Map<String, String>> options,
      List<String> selected,
    ) {
      return Wrap(
        spacing: 8,
        runSpacing: 6,
        children: options.map((opt) {
          final code = opt['code']!;
          final label = opt['label']!;
          final sel = selected.contains(code);
          return FilterChip(
            label: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: sel ? theme : Colors.white60,
              ),
            ),
            selected: sel,
            selectedColor: theme.withValues(alpha: 0.15),
            backgroundColor: Colors.white.withValues(alpha: 0.05),
            checkmarkColor: theme,
            side: BorderSide(
              color: sel ? theme : Colors.white.withValues(alpha: 0.2),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            onSelected: (v) {
              setState(() {
                if (v) {
                  selected.add(code);
                } else {
                  selected.remove(code);
                }
              });
              unawaited(widget.onFetchOrbitNodes());
            },
          );
        }).toList(),
      );
    }

    Widget customSwitch({
      required bool value,
      required ValueChanged<bool> onChanged,
    }) {
      return GestureDetector(
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 42,
          height: 22,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            color: value ? theme : Colors.white.withValues(alpha: 0.08),
            border: Border.all(
              color: value ? theme : Colors.white.withValues(alpha: 0.15),
            ),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 200),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 16,
              height: 16,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: value ? Colors.black87 : Colors.white54,
              ),
            ),
          ),
        ),
      );
    }

    Widget customAddButton({required VoidCallback onTap}) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: theme.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: theme.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.plus, size: 12, color: theme),
              const SizedBox(width: 4),
              Text(
                'Add',
                style: TextStyle(
                  color: theme,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget filterSection({
      required String label,
      required Widget child,
      Widget? action,
      String? subtitle,
    }) {
      return Container(
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B).withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.05),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                // Null-aware element syntax action?, causes compile errors in some SDK versions.
                // ignore: use_null_aware_elements
                if (action != null) action,
              ],
            ),
            if (subtitle != null && subtitle.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                ),
              ),
            ],
            const SizedBox(height: 12),
            child,
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(32),
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: ListView(
        controller: widget.scrollController,
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Row(
            children: [
              Icon(
                LucideIcons.sparkles,
                color: theme.withValues(alpha: 0.8),
                size: 18,
              ),
              const SizedBox(width: 10),
              const Text(
                'Constellation Filters',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: widget.isRefreshing
                    ? _SyncingBadge(
                        key: const ValueKey('syncing'),
                        themeColor: theme,
                      )
                    : const SizedBox.shrink(key: ValueKey('idle')),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Animated progress line under header
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            height: widget.isRefreshing ? 1.5 : 0,
            margin: const EdgeInsets.only(bottom: 18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  theme.withValues(alpha: 0.7),
                  theme,
                  theme.withValues(alpha: 0.7),
                  Colors.transparent,
                ],
              ),
              borderRadius: BorderRadius.circular(1),
            ),
          ),

          // ── Age Range ──────────────────────────────────────────────────────
          filterSection(
            label: 'Age Range',
            action: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: theme.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.withValues(alpha: 0.2),
                ),
              ),
              child: Text(
                '${_ageRange.start.round()} – ${_ageRange.end.round()}',
                style: TextStyle(
                  color: theme,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: theme,
                inactiveTrackColor: Colors.white.withValues(alpha: 0.08),
                trackHeight: 3,
                thumbColor: theme,
                overlayColor: theme.withValues(alpha: 0.12),
                valueIndicatorColor: theme,
                valueIndicatorTextStyle: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
                // No Material elevation shadow on the thumb — its solid
                // fill already reads clearly against the track/panel.
                rangeThumbShape: const RoundRangeSliderThumbShape(
                  enabledThumbRadius: 6,
                  elevation: 0,
                ),
                rangeTrackShape: const RoundedRectRangeSliderTrackShape(),
              ),
              child: RangeSlider(
                values: _ageRange,
                min: 18,
                max: ageMax,
                divisions: ageDivisions,
                activeColor: theme,
                inactiveColor: Colors.white12,
                labels: RangeLabels(
                  _ageRange.start.round().toString(),
                  _ageRange.end.round().toString(),
                ),
                onChanged: (values) {
                  setState(() {
                    _ageRange = values;
                  });
                  widget.onAgeRangeChanged(values);
                },
                onChangeEnd: (values) {
                  widget.onAgeRangeChangeEnd(values);
                },
              ),
            ),
          ),

          if (widget.tab != 'Professional') ...[
            filterSection(
              label: 'Drinking',
              child: filterChips(
                FilterOptions.drinking,
                widget.selectedDrinking,
              ),
            ),

            filterSection(
              label: 'Smoking',
              child: filterChips(
                FilterOptions.smoking,
                widget.selectedSmoking,
              ),
            ),
          ],

          // Languages
          filterSection(
            label: 'Languages',
            action: customAddButton(
              onTap: () => widget.onOpenTagSelectionPane(
                'Select Languages',
                FilterOptions.languages,
                widget.selectedLanguages,
                setState,
              ),
            ),
            child: widget.selectedLanguages.isEmpty
                ? const Text(
                    'No languages selected.',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 12,
                    ),
                  )
                : Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: widget.selectedLanguages.map((opt) {
                      return Chip(
                        label: Text(
                          opt,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                        ),
                        backgroundColor: Colors.white.withValues(alpha: 0.05),
                        deleteIcon: Icon(
                          LucideIcons.x,
                          size: 14,
                          color: theme,
                        ),
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.15),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        onDeleted: () {
                          setState(() {
                            widget.selectedLanguages.remove(opt);
                          });
                          unawaited(widget.onFetchOrbitNodes());
                        },
                      );
                    }).toList(),
                  ),
          ),

          // Interests
          filterSection(
            label: 'Interests',
            action: customAddButton(
              onTap: () {
                unawaited(
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (context) => InterestsOverlay(
                        initialSelected: widget.selectedSubInterests,
                        saveButtonText: 'Save Filter',
                        themeColor: theme,
                        onSave: (newInterests) {
                          setState(() {
                            widget.selectedSubInterests
                              ..clear()
                              ..addAll(newInterests);
                          });
                          unawaited(widget.onFetchOrbitNodes());
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
            child: widget.selectedSubInterests.isEmpty
                ? const Text(
                    'No interests selected.',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 12,
                    ),
                  )
                : Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: widget.selectedSubInterests.map((opt) {
                      return Chip(
                        label: Text(
                          opt,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                        ),
                        backgroundColor: Colors.white.withValues(alpha: 0.05),
                        deleteIcon: Icon(
                          LucideIcons.x,
                          size: 14,
                          color: theme,
                        ),
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.15),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        onDeleted: () {
                          setState(() {
                            widget.selectedSubInterests.remove(opt);
                          });
                          unawaited(widget.onFetchOrbitNodes());
                        },
                      );
                    }).toList(),
                  ),
          ),

          // Campus Year (flavor variant only)
          if (AppConfig.current.isFlavorVariant)
            filterSection(
              label: 'Campus Year',
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(5, (index) {
                  final year = index + 1;
                  final sel = widget.selectedYears.contains(year);
                  return FilterChip(
                    label: Text(
                      'Yr $year',
                      style: TextStyle(
                        fontSize: 12,
                        color: sel ? theme : Colors.white60,
                      ),
                    ),
                    selected: sel,
                    selectedColor: theme.withValues(alpha: 0.15),
                    backgroundColor: Colors.white.withValues(alpha: 0.05),
                    checkmarkColor: theme,
                    side: BorderSide(
                      color: sel ? theme : Colors.white.withValues(alpha: 0.2),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    onSelected: (v) {
                      setState(() {
                        if (v) {
                          widget.selectedYears.add(year);
                        } else {
                          widget.selectedYears.remove(year);
                        }
                      });
                      unawaited(widget.onFetchOrbitNodes());
                    },
                  );
                }),
              ),
            ),

          // ── Dating Preferences ──────────────────────────────
          if (widget.tab == 'Dating') ...[
            filterSection(
              label: 'Children Plans',
              child: filterChips(
                FilterOptions.childrenPlans,
                widget.selectedChildrenPlans,
              ),
            ),

            filterSection(
              label: 'Religious Beliefs',
              child: filterChips(
                FilterOptions.religiousBeliefs,
                widget.selectedReligiousBeliefs,
              ),
            ),

            const Padding(
              padding: EdgeInsets.only(top: 16, bottom: 16, left: 4),
              child: Text(
                'YOUR DATING PREFERENCES',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                ),
              ),
            ),

            // Show Who
            filterSection(
              label: 'Who are you interested in meeting?',
              subtitle:
                  'Select the gender identities you would like to see in your Orbit.',
              action: widget.savingFields.contains('dating_target_buckets')
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white60,
                        ),
                      ),
                    )
                  : null,
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children:
                    [
                      {'code': 'M', 'label': 'Men'},
                      {'code': 'F', 'label': 'Women'},
                      {'code': 'NB', 'label': 'Non-binary'},
                      {'code': 'Open', 'label': 'Open to all'},
                    ].map((item) {
                      final code = item['code']!;
                      final isSelected = widget.selectedShowBuckets.contains(
                        code,
                      );
                      return FilterChip(
                        label: Text(item['label']!),
                        selected: isSelected,
                        selectedColor: theme.withValues(alpha: 0.15),
                        backgroundColor: Colors.white.withValues(alpha: 0.05),
                        checkmarkColor: theme,
                        side: BorderSide(
                          color: isSelected
                              ? theme
                              : Colors.white.withValues(alpha: 0.2),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        labelStyle: TextStyle(
                          color: isSelected ? theme : Colors.white60,
                          fontSize: 12,
                        ),
                        onSelected: (selected) async {
                          if (widget.savingFields.contains(
                            'dating_target_buckets',
                          )) {
                            return;
                          }
                          setState(() {
                            if (selected) {
                              widget.selectedShowBuckets.add(code);
                            } else {
                              widget.selectedShowBuckets.remove(code);
                            }
                          });
                          await widget.onSaveDatingField(
                            'dating_target_buckets',
                            widget.selectedShowBuckets,
                            setState,
                          );
                        },
                      );
                    }).toList(),
              ),
            ),

            // Dating Intent
            filterSection(
              label: 'What are you looking for?',
              subtitle: 'Select the relationship types you are open to.',
              action: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.savingFields.contains('dating_for')) ...[
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white60,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    'Dealbreaker',
                    style: TextStyle(
                      color: widget.dealbreakerFields.contains('dating_for')
                          ? theme
                          : Colors.white38,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(width: 6),
                  customSwitch(
                    value: widget.dealbreakerFields.contains('dating_for'),
                    onChanged: (v) {
                      setState(() {
                        if (v) {
                          widget.dealbreakerFields.add('dating_for');
                        } else {
                          widget.dealbreakerFields.remove('dating_for');
                        }
                      });
                      unawaited(widget.onFetchOrbitNodes());
                    },
                  ),
                ],
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children:
                    [
                      {'code': 'short', 'label': 'Short-term'},
                      {'code': 'long', 'label': 'Long-term'},
                      {'code': 'casual', 'label': 'Casual Dating'},
                      {'code': 'fling', 'label': 'Fling'},
                      {'code': 'hookups', 'label': 'Hookups'},
                      {'code': 'fwb', 'label': 'Friends with Benefits'},
                      {'code': 'monogamous', 'label': 'Monogamous'},
                      {'code': 'polyamorous', 'label': 'Polyamorous'},
                      {'code': 'open_rel', 'label': 'Open Relationship'},
                      {'code': 'marriage', 'label': 'Marriage / Life Partner'},
                      {'code': 'platonic', 'label': 'Platonic Dating'},
                      {'code': 'unsure', 'label': 'Figuring it out'},
                    ].map((item) {
                      final code = item['code']!;
                      final isSelected = widget.selectedDatingFor.contains(
                        code,
                      );
                      return FilterChip(
                        label: Text(item['label']!),
                        selected: isSelected,
                        selectedColor: theme.withValues(alpha: 0.15),
                        backgroundColor: Colors.white.withValues(alpha: 0.05),
                        checkmarkColor: theme,
                        side: BorderSide(
                          color: isSelected
                              ? theme
                              : Colors.white.withValues(alpha: 0.2),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        labelStyle: TextStyle(
                          color: isSelected ? theme : Colors.white60,
                          fontSize: 12,
                        ),
                        onSelected: (selected) async {
                          if (widget.savingFields.contains('dating_for')) {
                            return;
                          }
                          setState(() {
                            if (selected) {
                              widget.selectedDatingFor.add(code);
                            } else {
                              widget.selectedDatingFor.remove(code);
                            }
                          });
                          await widget.onSaveDatingField(
                            'dating_for',
                            widget.selectedDatingFor,
                            setState,
                          );
                        },
                      );
                    }).toList(),
              ),
            ),

            // Partner Values
            filterSection(
              label: 'Partner Values',
              subtitle:
                  'Choose the qualities and shared principles you value most.',
              action: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.savingFields.contains('partner_values')) ...[
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white60,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    'Dealbreaker',
                    style: TextStyle(
                      color: widget.dealbreakerFields.contains('partner_values')
                          ? theme
                          : Colors.white38,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(width: 6),
                  customSwitch(
                    value: widget.dealbreakerFields.contains('partner_values'),
                    onChanged: (v) {
                      setState(() {
                        if (v) {
                          widget.dealbreakerFields.add('partner_values');
                        } else {
                          widget.dealbreakerFields.remove('partner_values');
                        }
                      });
                      unawaited(widget.onFetchOrbitNodes());
                    },
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.selectedPartnerValues.isEmpty)
                    const Text(
                      'No partner values selected.',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: widget.selectedPartnerValues.map((val) {
                        return Chip(
                          label: Text(
                            val,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          ),
                          backgroundColor: Colors.white.withValues(alpha: 0.05),
                          deleteIcon: Icon(
                            LucideIcons.x,
                            size: 14,
                            color: theme,
                          ),
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.15),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          onDeleted: () async {
                            if (widget.savingFields.contains(
                              'partner_values',
                            )) {
                              return;
                            }
                            setState(() {
                              widget.selectedPartnerValues.remove(val);
                            });
                            await widget.onSaveDatingField(
                              'partner_values',
                              widget.selectedPartnerValues.join(', '),
                              setState,
                            );
                          },
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 12),
                  customAddButton(
                    onTap: () => widget.onOpenPartnerValuesSelectionPane(
                      setState,
                      predefinedValues,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── Professional Preferences ────────────────────────
          if (widget.tab == 'Professional') ...[
            filterSection(
              label: 'Looking For',
              child: codeChips(
                FilterOptions.lookingForOptions,
                widget.selectedLookingFor,
              ),
            ),

            filterSection(
              label: 'Tech Skills',
              child: filterChips(
                FilterOptions.techSkills,
                widget.selectedTechSkills,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Pulsing "Syncing orbit…" badge shown in the panel header ──────────────────

class _SyncingBadge extends StatelessWidget {
  const _SyncingBadge({required this.themeColor, super.key});
  final Color themeColor;

  @override
  Widget build(BuildContext context) {
    return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: themeColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: themeColor.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 8,
                height: 8,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation<Color>(themeColor),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Syncing orbit',
                style: TextStyle(
                  color: themeColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .fade(begin: 0.6, end: 1, duration: 900.ms, curve: Curves.easeInOut);
  }
}
