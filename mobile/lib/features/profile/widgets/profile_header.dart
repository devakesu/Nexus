import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/core/widgets/aesthetic_loaders.dart';
import 'package:nexus/features/profile/widgets/orbit_painter.dart';
import 'package:nexus/features/profile/widgets/storage_image.dart';

class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    required this.avatarPath,
    required this.name,
    required this.rotationController,
    required this.pulseController,
    required this.hasPendingUpload,
    required this.onAvatarTap,
    this.isRemoving = false,
    super.key,
  });

  final String? avatarPath;
  final String name;
  final AnimationController rotationController;
  final AnimationController pulseController;
  final bool hasPendingUpload;
  final bool isRemoving;
  final VoidCallback onAvatarTap;

  @override
  Widget build(BuildContext context) {
    const pulsarPink = AppColors.pulsarPink;
    const deepCyan = Color(0xFF00E5FF);

    return Center(
      child: Column(
        children: [
          const SizedBox(height: 10),
          Semantics(
            button: true,
            label: 'Change profile photo',
            excludeSemantics: true,
            onTap: isRemoving ? null : onAvatarTap,
            child: GestureDetector(
              onTap: isRemoving ? null : onAvatarTap,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Rotating Dashed Orbit Ring
                  AnimatedBuilder(
                    animation: rotationController,
                    builder: (context, child) {
                      return CustomPaint(
                        size: const Size(136, 136),
                        painter: OrbitPainter(
                          color: deepCyan,
                          progress: rotationController.value,
                        ),
                      );
                    },
                  ),
                  // Inner Pulsing Glow
                  AnimatedBuilder(
                    animation: pulseController,
                    builder: (context, child) {
                      return Container(
                        width: 108,
                        height: 108,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: pulsarPink.withValues(
                                alpha: 0.3 * pulseController.value,
                              ),
                              blurRadius: 15 + 10 * pulseController.value,
                              spreadRadius: 1 + 3 * pulseController.value,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  // Main Avatar Circle
                  Container(
                    width: 104,
                    height: 104,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [
                          Colors.white,
                          Color(0xFFF3F4F6),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(
                        color: pulsarPink.withValues(alpha: 0.6),
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: avatarPath != null
                          ? ClipOval(
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: Opacity(
                                      opacity: isRemoving ? 0.5 : 1.0,
                                      child: StorageImage(
                                        imagePath: avatarPath!,
                                        width: 100,
                                        height: 100,
                                      ),
                                    ),
                                  ),
                                  if (hasPendingUpload || isRemoving)
                                    const Positioned.fill(
                                      child: ColoredBox(
                                        color: Colors.black54,
                                        child: Center(
                                          child: NexusOrbitLoader(size: 40),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            )
                          : const Icon(
                              LucideIcons.user,
                              color: Colors.black38,
                              size: 44,
                            ),
                    ),
                  ),
                  // Edit Badge
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            AppColors.pulsarPink,
                            Color(0xFFFF4D7E),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white,
                          width: 2.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.pulsarPink.withValues(alpha: 0.5),
                            blurRadius: 10,
                            spreadRadius: 1,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        LucideIcons.camera,
                        size: 15,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Hey, $name 👋',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
              letterSpacing: -0.5,
              shadows: [],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white,
                  const Color(0xFFE2F9FC).withValues(alpha: 0.55),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: deepCyan.withValues(alpha: 0.22),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
                BoxShadow(
                  color: deepCyan.withValues(alpha: 0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Spinning & Pulsing Sparkles status indicator
                AnimatedBuilder(
                  animation: Listenable.merge([
                    pulseController,
                    rotationController,
                  ]),
                  builder: (context, child) {
                    return Transform.rotate(
                      angle: rotationController.value * 2 * 3.141592653589793,
                      child: Transform.scale(
                        scale: 0.85 + 0.3 * pulseController.value,
                        child: const Icon(
                          LucideIcons.sparkles,
                          color: deepCyan,
                          size: 14,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 8),
                Text(
                  'Floating in the Nebula 🪐',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink.withValues(alpha: 0.8),
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
