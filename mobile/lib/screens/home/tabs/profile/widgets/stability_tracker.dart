import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/theme/app_colors.dart';

class StabilityTracker extends StatelessWidget {
  const StabilityTracker({
    required this.stabilityPercentage,
    required this.imagePaths,
    required this.name,
    required this.age,
    required this.bio,
    required this.searchBucket,
    required this.displayGender,
    required this.displaySexuality,
    required this.pronouns,
    required this.hometown,
    required this.currentPlace,
    required this.languages,
    required this.campusName,
    required this.major,
    required this.isStudying,
    required this.year,
    required this.lifestyle,
    required this.drinking,
    required this.smoking,
    required this.religiousBeliefs,
    required this.pets,
    required this.subInterests,
    required this.causesSupported,
    required this.topArtists,
    required this.pulseController,
    required this.onCriteriaTap,
    super.key,
  });

  final int stabilityPercentage;
  final List<String?> imagePaths;
  final String name;
  final int age;
  final String bio;
  final String searchBucket;
  final String displayGender;
  final String displaySexuality;
  final String pronouns;
  final String hometown;
  final String currentPlace;
  final List<String> languages;
  final String campusName;
  final String major;
  final bool isStudying;
  final int year;
  final String lifestyle;
  final String drinking;
  final String smoking;
  final String religiousBeliefs;
  final List<String> pets;
  final Map<String, List<String>> subInterests;
  final List<String> causesSupported;
  final List<String> topArtists;
  final AnimationController pulseController;
  final void Function(String label) onCriteriaTap;

  void _showStabilityDetails(BuildContext context) {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (context) {
          return Container(
            padding: const EdgeInsets.all(24),
            height: MediaQuery.of(context).size.height * 0.85,
            decoration: BoxDecoration(
              color: const Color(0xFF161B26),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(30),
                topRight: Radius.circular(30),
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(LucideIcons.activity, color: AppColors.pulsarPink),
                    SizedBox(width: 12),
                    Text(
                      'Profile Completion Report',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Your profile is $stabilityPercentage% complete.',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Complete your profile details to improve matchmaking. Each filled parameter increases your search relevance:',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Builder(
                      builder: (context) {
                        final coreDetails = [
                          _CriteriaItem(
                            icon: LucideIcons.image,
                            label: 'Profile Picture',
                            complete:
                                imagePaths[0] != null &&
                                imagePaths[0]!.isNotEmpty,
                          ),
                          _CriteriaItem(
                            icon: LucideIcons.user,
                            label: 'Display Name',
                            complete: name.isNotEmpty,
                          ),
                          _CriteriaItem(
                            icon: LucideIcons.calendar,
                            label: 'Age',
                            complete: age >= 18,
                          ),
                          _CriteriaItem(
                            icon: LucideIcons.fileText,
                            label: 'Cosmic Signature (Bio)',
                            complete: bio.isNotEmpty,
                          ),
                          _CriteriaItem(
                            icon: LucideIcons.users,
                            label: 'Demographic Buckets',
                            complete: searchBucket.isNotEmpty,
                          ),
                          _CriteriaItem(
                            icon: LucideIcons.userCheck,
                            label: 'Gender',
                            complete:
                                displayGender.isNotEmpty &&
                                displayGender != 'Prefer not to say',
                          ),
                          _CriteriaItem(
                            icon: LucideIcons.heart,
                            label: 'Sexuality',
                            complete:
                                displaySexuality.isNotEmpty &&
                                displaySexuality != 'Prefer not to say',
                          ),
                          _CriteriaItem(
                            icon: LucideIcons.smile,
                            label: 'Pronouns',
                            complete:
                                pronouns.isNotEmpty &&
                                pronouns != 'Prefer not to say',
                          ),
                          _CriteriaItem(
                            icon: LucideIcons.image,
                            label: 'Gallery Slot 1',
                            complete:
                                imagePaths[1] != null &&
                                imagePaths[1]!.isNotEmpty,
                          ),
                          _CriteriaItem(
                            icon: LucideIcons.image,
                            label: 'Gallery Slot 2',
                            complete:
                                imagePaths[2] != null &&
                                imagePaths[2]!.isNotEmpty,
                          ),
                          _CriteriaItem(
                            icon: LucideIcons.image,
                            label: 'Gallery Slot 3',
                            complete:
                                imagePaths[3] != null &&
                                imagePaths[3]!.isNotEmpty,
                          ),
                          _CriteriaItem(
                            icon: LucideIcons.image,
                            label: 'Gallery Slot 4',
                            complete:
                                imagePaths[4] != null &&
                                imagePaths[4]!.isNotEmpty,
                          ),
                        ];

                        final socialCampus = [
                          _CriteriaItem(
                            icon: LucideIcons.home,
                            label: 'Hometown',
                            complete: hometown.isNotEmpty,
                          ),
                          _CriteriaItem(
                            icon: LucideIcons.navigation,
                            label: 'Current Place',
                            complete: currentPlace.isNotEmpty,
                          ),
                          _CriteriaItem(
                            icon: LucideIcons.languages,
                            label: 'Languages',
                            complete: languages.isNotEmpty,
                          ),
                          _CriteriaItem(
                            icon: LucideIcons.mapPin,
                            label: 'Institute Name',
                            complete: campusName.isNotEmpty,
                          ),
                          _CriteriaItem(
                            icon: LucideIcons.graduationCap,
                            label: 'Major',
                            complete: major.isNotEmpty,
                          ),
                          _CriteriaItem(
                            icon: LucideIcons.calendarCheck,
                            label: 'Campus Year',
                            complete: !isStudying || (year >= 1 && year <= 5),
                          ),
                        ];

                        final lifestylePref = [
                          _CriteriaItem(
                            icon: LucideIcons.activity,
                            label: 'Lifestyle Description',
                            complete: lifestyle.isNotEmpty,
                          ),
                          _CriteriaItem(
                            icon: LucideIcons.glassWater,
                            label: 'Drinking',
                            complete:
                                drinking.isNotEmpty &&
                                drinking != 'Not specified',
                          ),
                          _CriteriaItem(
                            icon: LucideIcons.cigarette,
                            label: 'Smoking',
                            complete:
                                smoking.isNotEmpty &&
                                smoking != 'Not specified',
                          ),
                          _CriteriaItem(
                            icon: LucideIcons.sparkles,
                            label: 'Religious Beliefs',
                            complete:
                                religiousBeliefs.isNotEmpty &&
                                religiousBeliefs != 'Not specified',
                          ),
                          _CriteriaItem(
                            icon: LucideIcons.pawPrint,
                            label: 'Pets',
                            complete: pets.isNotEmpty,
                          ),
                        ];

                        final interestsHobbies = [
                          _CriteriaItem(
                            icon: LucideIcons.sparkles,
                            label: 'Interests',
                            complete: subInterests.isNotEmpty,
                          ),
                          _CriteriaItem(
                            icon: LucideIcons.heart,
                            label: 'Causes Supported',
                            complete: causesSupported.isNotEmpty,
                          ),
                          _CriteriaItem(
                            icon: LucideIcons.music,
                            label: 'Top Artists',
                            complete: topArtists.isNotEmpty,
                          ),
                        ];

                        final incompleteCore = coreDetails
                            .where((item) => !item.complete)
                            .toList();
                        final incompleteSocial = socialCampus
                            .where((item) => !item.complete)
                            .toList();
                        final incompleteLifestyle = lifestylePref
                            .where((item) => !item.complete)
                            .toList();
                        final incompleteInterests = interestsHobbies
                            .where((item) => !item.complete)
                            .toList();

                        if (incompleteCore.isEmpty &&
                            incompleteSocial.isEmpty &&
                            incompleteLifestyle.isEmpty &&
                            incompleteInterests.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Column(
                                children: [
                                  Icon(
                                    LucideIcons.checkCircle,
                                    color: AppColors.success,
                                    size: 48,
                                  ),
                                  SizedBox(height: 16),
                                  Text(
                                    'All details synchronized!',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'Your profile stability is at maximum capacity.',
                                    style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (incompleteCore.isNotEmpty) ...[
                              _buildStabilityCategoryHeader('Core Details'),
                              ...incompleteCore.map(
                                (item) => _buildStabilityCriteriaRow(
                                  icon: item.icon,
                                  label: item.label,
                                  complete: item.complete,
                                  context: context,
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            if (incompleteSocial.isNotEmpty) ...[
                              _buildStabilityCategoryHeader(
                                'Social & Campus Info',
                              ),
                              ...incompleteSocial.map(
                                (item) => _buildStabilityCriteriaRow(
                                  icon: item.icon,
                                  label: item.label,
                                  complete: item.complete,
                                  context: context,
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            if (incompleteLifestyle.isNotEmpty) ...[
                              _buildStabilityCategoryHeader(
                                'Lifestyle & Preferences',
                              ),
                              ...incompleteLifestyle.map(
                                (item) => _buildStabilityCriteriaRow(
                                  icon: item.icon,
                                  label: item.label,
                                  complete: item.complete,
                                  context: context,
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            if (incompleteInterests.isNotEmpty) ...[
                              _buildStabilityCategoryHeader(
                                'Interests & Hobbies',
                              ),
                              ...incompleteInterests.map(
                                (item) => _buildStabilityCriteriaRow(
                                  icon: item.icon,
                                  label: item.label,
                                  complete: item.complete,
                                  context: context,
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Center(
                  child: SizedBox(
                    width: 220,
                    height: 46,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(23),
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFF00E5FF),
                            AppColors.pulsarPink,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.pulsarPink.withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(23),
                          ),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          'Acknowledge',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStabilityCategoryHeader(String title) {
    const pulsarPink = AppColors.pulsarPink;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: pulsarPink,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildStabilityCriteriaRow({
    required IconData icon,
    required String label,
    required bool complete,
    required BuildContext context,
  }) {
    const actionColor =
        AppColors.pulsarPink; // pulsarPink accent for call to action
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: GestureDetector(
        onTap: () {
          Navigator.pop(context);
          onCriteriaTap(label);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.04),
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: Colors.white54,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: actionColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: actionColor.withValues(alpha: 0.25),
                    width: 0.8,
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      LucideIcons.plus,
                      size: 10,
                      color: actionColor,
                    ),
                    SizedBox(width: 3),
                    Text(
                      'Add',
                      style: TextStyle(
                        color: actionColor,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
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
    const pulsarPink = AppColors.pulsarPink;
    final stabilityFraction = stabilityPercentage / 100;

    return GestureDetector(
      onTap: () => _showStabilityDetails(context),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.pulsarPink.withValues(alpha: 0.35),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 16,
              spreadRadius: 1,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      LucideIcons.activity,
                      color: pulsarPink,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Profile Completion',
                      style: TextStyle(
                        color: Colors.black.withValues(alpha: 0.6),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: pulsarPink.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$stabilityPercentage% Mapped',
                    style: const TextStyle(
                      color: pulsarPink,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AnimatedBuilder(
              animation: pulseController,
              builder: (context, child) {
                const totalSegments = 24;
                const activeColorStart = Color(0xFF00E5FF); // deepPurple
                const activeColorEnd = AppColors.pulsarPink; // pulsarPink

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(totalSegments, (index) {
                    final segmentThreshold = index / totalSegments;
                    final isActive = stabilityFraction > segmentThreshold;
                    final segmentRatio = index / (totalSegments - 1);

                    // Interpolate base color
                    final baseColor =
                        Color.lerp(
                          activeColorStart,
                          activeColorEnd,
                          segmentRatio,
                        ) ??
                        activeColorEnd;

                    // Calculate distance from scanner sweep
                    final sweepValue = pulseController.value;
                    final distanceFromSweep = (segmentRatio - sweepValue).abs();
                    final sweepHighlight = (1.0 - (distanceFromSweep / 0.2))
                        .clamp(0.0, 1.0);

                    Color displayColor;
                    List<BoxShadow>? boxShadows;

                    if (isActive) {
                      // Blend base color with bright white/pink for sweep highlight
                      displayColor = Color.lerp(
                        baseColor,
                        Colors.white,
                        sweepHighlight * 0.45,
                      )!;
                      boxShadows = [
                        BoxShadow(
                          color: baseColor.withValues(
                            alpha: 0.3 + (sweepHighlight * 0.3),
                          ),
                          blurRadius: 4 + (sweepHighlight * 6),
                          spreadRadius: 0.5 + (sweepHighlight * 1),
                        ),
                      ];
                    } else {
                      // Inactive segment gets a tiny hint of sweep light
                      displayColor = Colors.black.withValues(
                        alpha: 0.06 + (sweepHighlight * 0.08),
                      );
                      boxShadows = sweepHighlight > 0.5
                          ? [
                              BoxShadow(
                                color: Colors.white.withValues(
                                  alpha: 0.05 * sweepHighlight,
                                ),
                                blurRadius: 2,
                                spreadRadius: 0.1,
                              ),
                            ]
                          : null;
                    }

                    return Expanded(
                      child: Transform(
                        transform: Matrix4.skewX(-0.18),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin: const EdgeInsets.symmetric(horizontal: 1.5),
                          height: 10,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(1.5),
                            color: displayColor,
                            border: Border.all(
                              color: isActive
                                  ? displayColor.withValues(alpha: 0.4)
                                  : Colors.white.withValues(alpha: 0.02),
                              width: 0.5,
                            ),
                            boxShadow: boxShadows,
                          ),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
            const SizedBox(height: 10),
            Builder(
              builder: (context) {
                final percentage = stabilityPercentage;
                String statusText;
                Color statusColor;
                IconData statusIcon;

                if (percentage < 35) {
                  statusText = 'PROFILE INCOMPLETE';
                  statusColor = AppColors.error;
                  statusIcon = LucideIcons.alertTriangle;
                } else if (percentage < 75) {
                  statusText = 'SYNCHRONIZING';
                  statusColor = AppColors.warning;
                  statusIcon = LucideIcons.refreshCw;
                } else {
                  statusText = 'PROFILE COMPLETE';
                  statusColor = AppColors.success;
                  statusIcon = LucideIcons.checkCircle;
                }

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          statusIcon,
                          size: 10,
                          color: statusColor.withValues(alpha: 0.8),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          statusText,
                          style: TextStyle(
                            color: statusColor.withValues(alpha: 0.8),
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'STABILITY INDEX: $percentage/100',
                      style: TextStyle(
                        color: Colors.black.withValues(alpha: 0.45),
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CriteriaItem {
  const _CriteriaItem({
    required this.icon,
    required this.label,
    required this.complete,
  });

  final IconData icon;
  final String label;
  final bool complete;
}
