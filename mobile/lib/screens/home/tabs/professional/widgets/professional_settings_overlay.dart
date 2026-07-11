import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/theme/app_colors.dart';
import 'package:nexus/widgets/aesthetic_loaders.dart';

class ProfessionalSettingsOverlay extends StatefulWidget {
  const ProfessionalSettingsOverlay({
    required this.professionalTargetBuckets,
    required this.lookingFor,
    required this.techSkills,
    required this.company,
    required this.roleType,
    required this.savingFields,
    required this.onSaveProfessionalField,
    required this.onLoadProfessionalProfileStatusSilent,
    this.isActivating = false,
    this.onToggleOrbitState,
    super.key,
  });

  final List<String> professionalTargetBuckets;
  final List<String> lookingFor;
  final List<String> techSkills;
  final String company;
  final List<String> roleType;
  final Set<String> savingFields;
  final Future<void> Function(String field, dynamic value, StateSetter setState)
  onSaveProfessionalField;
  final Future<void> Function() onLoadProfessionalProfileStatusSilent;
  final bool isActivating;
  final Future<void> Function({required bool active})? onToggleOrbitState;

  @override
  State<ProfessionalSettingsOverlay> createState() =>
      _ProfessionalSettingsOverlayState();
}

class _ProfessionalSettingsOverlayState
    extends State<ProfessionalSettingsOverlay> {
  late List<String> localBuckets;
  late List<String> localLookingFor;
  late List<String> localTechSkills;
  late List<String> localRoleType;
  late TextEditingController companyController;
  Timer? companyDebounce;

  String searchQuery = '';
  String skillsSearchQuery = '';

  static const List<String> predefinedRoleTypes = [
    'Engineer',
    'Designer',
    'Product Manager',
    'Founder / Co-founder',
    'Researcher / Scientist',
    'Investor / VC',
    'Student',
    'Educator / Professor',
    'Business / Sales / Marketing',
    'Creative / Writer / Artist',
    'Other',
  ];

  static const List<String> predefinedLookingFor = [
    'Co-founder matching',
    'Hiring talent',
    'Finding a job / projects',
    'Industry networking',
    'Mentorship (giving or getting)',
    'Advising / Consulting',
    'Investment opportunities',
    'Learning / Skill sharing',
  ];

  static const List<String> predefinedSkills = [
    'Flutter & Dart',
    'Python & Django/FastAPI',
    'JavaScript & React/Node.js',
    'AI / Machine Learning',
    'UI/UX Design',
    'Product Management',
    'Growth Marketing',
    'Financial Modeling',
    'Cloud Architecture (AWS/GCP)',
    'Cybersecurity',
    'Data Science & Analytics',
    'Solidity & Web3',
    'Rust Development',
    'Go Development',
    'Mobile Development (iOS/Android)',
    'DevOps & CI/CD',
    'Agile & Scrum',
    'Product Strategy',
  ];

  @override
  void initState() {
    super.initState();
    localBuckets = List<String>.from(widget.professionalTargetBuckets);
    localLookingFor = List<String>.from(widget.lookingFor);
    localTechSkills = List<String>.from(widget.techSkills);
    localRoleType = List<String>.from(widget.roleType);
    companyController = TextEditingController(text: widget.company);
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
  void dispose() {
    companyDebounce?.cancel();
    companyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredSkills = predefinedSkills
        .where(
          (val) => val.toLowerCase().contains(skillsSearchQuery.toLowerCase()),
        )
        .where((val) => !localTechSkills.contains(val))
        .toList();

    final showCustomSkill =
        skillsSearchQuery.trim().isNotEmpty &&
        !predefinedSkills.any(
          (val) => val.toLowerCase() == skillsSearchQuery.trim().toLowerCase(),
        ) &&
        !localTechSkills.any(
          (val) => val.toLowerCase() == skillsSearchQuery.trim().toLowerCase(),
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
                      color: AppColors.modeProfessional,
                      size: 24,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Professional Settings',
                      style: TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                // Signal Glow shadow via BoxDecoration, not Material's
                // elevation: prop — DESIGN.md's shadow vocabulary.
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.modeProfessional.withValues(
                          alpha: 0.4,
                        ),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.modeProfessional,
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
                      companyDebounce?.cancel();
                      final pendingCompany = companyController.text.trim();
                      if (pendingCompany != widget.company) {
                        unawaited(
                          widget.onSaveProfessionalField(
                            'role_at',
                            pendingCompany,
                            setState,
                          ),
                        );
                      }
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
                _buildSectionHeader('Discovery Preferences', LucideIcons.compass, AppColors.modeProfessional),

                // Target Buckets
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Who are you open to connecting with?',
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (widget.savingFields.contains(
                      'professional_target_buckets',
                    ))
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: NexusOrbitLoader(size: 16, lightMode: true),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Select who you want to appear in your Professional Orbit.',
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
                          selectedColor: AppColors.modeProfessional,
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
                            if (widget.savingFields.contains(
                              'professional_target_buckets',
                            )) {
                              return;
                            }
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
                            await widget.onSaveProfessionalField(
                              'professional_target_buckets',
                              localBuckets,
                              setState,
                            );
                          },
                        );
                      }).toList(),
                ),
                const SizedBox(height: 32),

                // Looking For
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'What are you looking for professionally?',
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (widget.savingFields.contains('looking_for'))
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: NexusOrbitLoader(size: 16, lightMode: true),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Select your professional goals and intentions.',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: predefinedLookingFor.map((item) {
                    final isSelected = localLookingFor.contains(item);
                    return FilterChip(
                      label: Text(item),
                      selected: isSelected,
                      selectedColor: AppColors.modeProfessional,
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
                        if (widget.savingFields.contains('looking_for')) {
                          return;
                        }
                        setState(() {
                          if (selected) {
                            localLookingFor.add(item);
                          } else {
                            localLookingFor.remove(item);
                          }
                        });
                        await widget.onSaveProfessionalField(
                          'looking_for',
                          localLookingFor,
                          setState,
                        );
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),

                _buildSectionHeader('More About You', LucideIcons.user, AppColors.modeProfessional),

                // Role Type
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'What best describes your role?',
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (widget.savingFields.contains('role_type'))
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: NexusOrbitLoader(size: 16, lightMode: true),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Select all that apply.',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: predefinedRoleTypes.map((item) {
                    final isSelected = localRoleType.contains(item);
                    return FilterChip(
                      label: Text(item),
                      selected: isSelected,
                      selectedColor: AppColors.modeProfessional,
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
                        if (widget.savingFields.contains('role_type')) {
                          return;
                        }
                        setState(() {
                          if (selected) {
                            localRoleType.add(item);
                          } else {
                            localRoleType.remove(item);
                          }
                        });
                        await widget.onSaveProfessionalField(
                          'role_type',
                          localRoleType,
                          setState,
                        );
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 32),

                // Company / Institute
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Company / Institute',
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (widget.savingFields.contains('role_at'))
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: NexusOrbitLoader(size: 16, lightMode: true),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Leave blank if not applicable - this is optional.',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: companyController,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    hintText: 'e.g. Google, MIT, Acme Corp',
                    hintStyle: TextStyle(
                      color: Colors.black.withValues(alpha: 0.3),
                      fontSize: 13,
                    ),
                    prefixIcon: const Icon(
                      LucideIcons.briefcase,
                      size: 18,
                      color: AppColors.modeProfessional,
                    ),
                    filled: true,
                    fillColor: Colors.black.withValues(alpha: 0.04),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: AppColors.modeProfessional,
                        width: 1.5,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                  textInputAction: TextInputAction.done,
                  onChanged: (val) {
                    companyDebounce?.cancel();
                    companyDebounce = Timer(
                      const Duration(milliseconds: 800),
                      () {
                        if (val.trim() != widget.company) {
                          unawaited(
                            widget.onSaveProfessionalField(
                              'role_at',
                              val.trim(),
                              setState,
                            ),
                          );
                        }
                      },
                    );
                  },
                  onSubmitted: (val) {
                    companyDebounce?.cancel();
                    if (val.trim() != widget.company) {
                      unawaited(
                        widget.onSaveProfessionalField(
                          'role_at',
                          val.trim(),
                          setState,
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(height: 32),

                // Tech Skills
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'What are your key skills?',
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (widget.savingFields.contains('tech_skills'))
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: NexusOrbitLoader(size: 16, lightMode: true),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Add your technical skills and areas of expertise.',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16),

                if (localTechSkills.isNotEmpty) ...[
                  const Text(
                    'Your Skills:',
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
                    children: localTechSkills.map((val) {
                      return Chip(
                        label: Text(val),
                        backgroundColor: AppColors.modeProfessional.withValues(
                          alpha: 0.1,
                        ),
                        labelStyle: const TextStyle(
                          color: AppColors.modeProfessional,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        deleteIcon: const Icon(
                          LucideIcons.x,
                          size: 14,
                          color: AppColors.modeProfessional,
                        ),
                        side: BorderSide.none,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        onDeleted: () async {
                          if (widget.savingFields.contains('tech_skills')) {
                            return;
                          }
                          setState(() => localTechSkills.remove(val));
                          await widget.onSaveProfessionalField(
                            'tech_skills',
                            localTechSkills,
                            setState,
                          );
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                ],

                TextField(
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search or add skills...',
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
                    setState(() => skillsSearchQuery = val);
                  },
                ),
                const SizedBox(height: 16),

                const Text(
                  'Tap to add skills:',
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
                    if (showCustomSkill)
                      ActionChip(
                        avatar: const Icon(
                          LucideIcons.plus,
                          size: 14,
                          color: Colors.white,
                        ),
                        label: Text('Add "${skillsSearchQuery.trim()}"'),
                        backgroundColor: AppColors.modeProfessional,
                        labelStyle: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        onPressed: () async {
                          if (widget.savingFields.contains('tech_skills')) {
                            return;
                          }
                          setState(() {
                            localTechSkills.add(skillsSearchQuery.trim());
                            skillsSearchQuery = '';
                          });
                          await widget.onSaveProfessionalField(
                            'tech_skills',
                            localTechSkills,
                            setState,
                          );
                        },
                      ),
                    ...filteredSkills.map((val) {
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
                          if (widget.savingFields.contains('tech_skills')) {
                            return;
                          }
                          setState(() => localTechSkills.add(val));
                          await widget.onSaveProfessionalField(
                            'tech_skills',
                            localTechSkills,
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
