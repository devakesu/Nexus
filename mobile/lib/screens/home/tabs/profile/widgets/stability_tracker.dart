import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class StabilityTracker extends StatelessWidget {
  const StabilityTracker({
    required this.stabilityPercentage,
    required this.imagePaths,
    required this.name,
    required this.age,
    required this.bio,
    required this.searchBuckets,
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
    required this.childrenPlans,
    required this.religiousBeliefs,
    required this.partnerValues,
    required this.pets,
    required this.subInterests,
    required this.causesSupported,
    required this.topArtists,
    required this.pulseController,
    super.key,
  });

  final int stabilityPercentage;
  final List<String?> imagePaths;
  final String name;
  final int age;
  final String bio;
  final List<String> searchBuckets;
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
  final String childrenPlans;
  final String religiousBeliefs;
  final String partnerValues;
  final List<String> pets;
  final Map<String, List<String>> subInterests;
  final List<String> causesSupported;
  final List<String> topArtists;
  final AnimationController pulseController;

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
              color: const Color(0xFF161B26).withValues(alpha: 0.95),
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
                    Icon(LucideIcons.activity, color: Color(0xFFFF7597)),
                    SizedBox(width: 12),
                    Text(
                      'Cosmic Stability Report',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Outfit',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Your stability is at $stabilityPercentage% alignment.',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Complete your signals to increase your matching resonance inside the campus cluster. Each filled parameter refines your cosmic coordinates:',
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 1. The Core Signal
                        _buildStabilityCategoryHeader('The Core Signal'),
                        _buildStabilityCriteriaRow(
                          icon: LucideIcons.image,
                          label: 'Profile Picture',
                          complete: imagePaths[0] != null && imagePaths[0]!.isNotEmpty,
                        ),
                        _buildStabilityCriteriaRow(
                          icon: LucideIcons.user,
                          label: 'Display Name',
                          complete: name.isNotEmpty,
                        ),
                        _buildStabilityCriteriaRow(
                          icon: LucideIcons.calendar,
                          label: 'Age',
                          complete: age >= 18,
                        ),
                        _buildStabilityCriteriaRow(
                          icon: LucideIcons.fileText,
                          label: 'Cosmic Signature (Bio)',
                          complete: bio.isNotEmpty,
                        ),
                        _buildStabilityCriteriaRow(
                          icon: LucideIcons.users,
                          label: 'Demographic Buckets',
                          complete: searchBuckets.isNotEmpty,
                        ),
                        _buildStabilityCriteriaRow(
                          icon: LucideIcons.userCheck,
                          label: 'Gender',
                          complete: displayGender.isNotEmpty && displayGender != 'Prefer not to say',
                        ),
                        _buildStabilityCriteriaRow(
                          icon: LucideIcons.heart,
                          label: 'Sexuality',
                          complete: displaySexuality.isNotEmpty && displaySexuality != 'Prefer not to say',
                        ),
                        _buildStabilityCriteriaRow(
                          icon: LucideIcons.smile,
                          label: 'Pronouns',
                          complete: pronouns.isNotEmpty && pronouns != 'Prefer not to say',
                        ),
                        _buildStabilityCriteriaRow(
                          icon: LucideIcons.image,
                          label: 'Gallery Slot 1',
                          complete: imagePaths[1] != null && imagePaths[1]!.isNotEmpty,
                        ),
                        _buildStabilityCriteriaRow(
                          icon: LucideIcons.image,
                          label: 'Gallery Slot 2',
                          complete: imagePaths[2] != null && imagePaths[2]!.isNotEmpty,
                        ),
                        _buildStabilityCriteriaRow(
                          icon: LucideIcons.image,
                          label: 'Gallery Slot 3',
                          complete: imagePaths[3] != null && imagePaths[3]!.isNotEmpty,
                        ),
                        _buildStabilityCriteriaRow(
                          icon: LucideIcons.image,
                          label: 'Gallery Slot 4',
                          complete: imagePaths[4] != null && imagePaths[4]!.isNotEmpty,
                        ),
                        const SizedBox(height: 12),

                        // 2. Social Coordinates
                        _buildStabilityCategoryHeader('Social Coordinates'),
                        _buildStabilityCriteriaRow(
                          icon: LucideIcons.home,
                          label: 'Hometown',
                          complete: hometown.isNotEmpty,
                        ),
                        _buildStabilityCriteriaRow(
                          icon: LucideIcons.navigation,
                          label: 'Current Place',
                          complete: currentPlace.isNotEmpty,
                        ),
                        _buildStabilityCriteriaRow(
                          icon: LucideIcons.languages,
                          label: 'Languages',
                          complete: languages.isNotEmpty,
                        ),
                        _buildStabilityCriteriaRow(
                          icon: LucideIcons.mapPin,
                          label: 'Institute Name',
                          complete: campusName.isNotEmpty,
                        ),
                        _buildStabilityCriteriaRow(
                          icon: LucideIcons.graduationCap,
                          label: 'Major',
                          complete: major.isNotEmpty,
                        ),
                        _buildStabilityCriteriaRow(
                          icon: LucideIcons.calendarCheck,
                          label: 'Campus Year',
                          complete: !isStudying || (year >= 1 && year <= 5),
                        ),
                        const SizedBox(height: 12),

                        // 3. Lifestyle & Resonance
                        _buildStabilityCategoryHeader('Lifestyle & Resonance'),
                        _buildStabilityCriteriaRow(
                          icon: LucideIcons.activity,
                          label: 'Lifestyle Description',
                          complete: lifestyle.isNotEmpty,
                        ),
                        _buildStabilityCriteriaRow(
                          icon: LucideIcons.glassWater,
                          label: 'Drinking',
                          complete: drinking.isNotEmpty && drinking != 'Not specified',
                        ),
                        _buildStabilityCriteriaRow(
                          icon: LucideIcons.cigarette,
                          label: 'Smoking',
                          complete: smoking.isNotEmpty && smoking != 'Not specified',
                        ),
                        _buildStabilityCriteriaRow(
                          icon: LucideIcons.baby,
                          label: 'Children Plans',
                          complete: childrenPlans.isNotEmpty && childrenPlans != 'Not specified',
                        ),
                        _buildStabilityCriteriaRow(
                          icon: LucideIcons.sparkles,
                          label: 'Religious Beliefs',
                          complete: religiousBeliefs.isNotEmpty && religiousBeliefs != 'Not specified',
                        ),
                        _buildStabilityCriteriaRow(
                          icon: LucideIcons.users,
                          label: 'Partner Values',
                          complete: partnerValues.isNotEmpty,
                        ),
                        _buildStabilityCriteriaRow(
                          icon: LucideIcons.pawPrint,
                          label: 'Pets',
                          complete: pets.isNotEmpty,
                        ),
                        const SizedBox(height: 12),

                        // 4. Affinity & Interests
                        _buildStabilityCategoryHeader('Affinity & Interests'),
                        _buildStabilityCriteriaRow(
                          icon: LucideIcons.sparkles,
                          label: 'Interests',
                          complete: subInterests.isNotEmpty,
                        ),
                        _buildStabilityCriteriaRow(
                          icon: LucideIcons.heart,
                          label: 'Causes Supported',
                          complete: causesSupported.isNotEmpty,
                        ),
                        _buildStabilityCriteriaRow(
                          icon: LucideIcons.music,
                          label: 'Top Artists',
                          complete: topArtists.isNotEmpty,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7C3AED),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Acknowledge',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
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
    const pulsarPink = Color(0xFFFF7597);
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
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: complete ? const Color(0xFFFF7597) : Colors.white38,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: complete ? Colors.white70 : Colors.white38,
                fontSize: 13,
                decoration: complete ? null : TextDecoration.lineThrough,
              ),
            ),
          ),
          Icon(
            complete ? LucideIcons.checkCircle : LucideIcons.helpCircle,
            size: 16,
            color: complete ? const Color(0xFF10B981) : Colors.white24,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const pulsarPink = Color(0xFFFF7597);
    const deepPurple = Color(0xFF7C3AED);
    final stabilityFraction = stabilityPercentage / 100;

    return GestureDetector(
      onTap: () => _showStabilityDetails(context),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF161B26).withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
          ),
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
                      'System Stability',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
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
            Container(
              height: 12,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.05),
                ),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final progressWidth = constraints.maxWidth * stabilityFraction;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 400),
                        width: progressWidth,
                        height: double.infinity,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [deepPurple, pulsarPink],
                          ),
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: [
                            BoxShadow(
                              color: pulsarPink.withValues(alpha: 0.3),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        left: progressWidth - 6,
                        top: -1,
                        child: AnimatedBuilder(
                          animation: pulseController,
                          builder: (context, child) {
                            return Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: pulsarPink.withValues(
                                      alpha: (0.6 * pulseController.value) + 0.4,
                                    ),
                                    blurRadius: 6 + 4 * pulseController.value,
                                    spreadRadius: 1 + 2 * pulseController.value,
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: pulsarPink,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
