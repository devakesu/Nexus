import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/screens/home/tabs/profile/widgets/orbit_painter.dart';
import 'package:nexus/screens/home/tabs/profile/widgets/storage_image.dart';

class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    required this.avatarPath,
    required this.name,
    required this.rotationController,
    required this.pulseController,
    required this.isProcessingAI,
    required this.isSaving,
    required this.hasPendingUpload,
    required this.onAvatarTap,
    super.key,
  });

  final String? avatarPath;
  final String name;
  final AnimationController rotationController;
  final AnimationController pulseController;
  final bool isProcessingAI;
  final bool isSaving;
  final bool hasPendingUpload;
  final VoidCallback onAvatarTap;

  @override
  Widget build(BuildContext context) {
    const pulsarPink = Color(0xFFFF7597);
    const deepCyan = Color(0xFF00E5FF);

    return Center(
      child: Column(
        children: [
          const SizedBox(height: 10),
          GestureDetector(
            onTap: onAvatarTap,
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
                        Color(0xFF161B26),
                        Color(0xFF0F0F23),
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
                                  child: StorageImage(
                                    imagePath: avatarPath!,
                                    width: 100,
                                    height: 100,
                                  ),
                                ),
                                if ((isProcessingAI || isSaving) &&
                                    hasPendingUpload)
                                  const Positioned.fill(
                                    child: ColoredBox(
                                      color: Colors.black54,
                                      child: Center(
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                pulsarPink,
                                              ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          )
                        : const Icon(
                            LucideIcons.user,
                            color: Colors.white24,
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
                          Color(0xFFFF7597),
                          Color(0xFFFF4D7E),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF0B0D13),
                        width: 2.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF7597).withValues(alpha: 0.5),
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
          const SizedBox(height: 20),
          Text(
            'Hey, $name 👋',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.5,
              shadows: [
                Shadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  offset: const Offset(0, 2),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.08),
                  Colors.white.withValues(alpha: 0.03),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: deepCyan.withValues(alpha: 0.3),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: deepCyan.withValues(alpha: 0.08),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Pulsing high-tech status indicator dot
                AnimatedBuilder(
                  animation: pulseController,
                  builder: (context, child) {
                    return Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: deepCyan,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: deepCyan.withValues(
                              alpha: 0.4 + 0.6 * pulseController.value,
                            ),
                            blurRadius: 4 + 6 * pulseController.value,
                            spreadRadius: 1 + 2 * pulseController.value,
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(width: 10),
                Text(
                  'Floating in the Nebula 🧑‍🚀',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.95),
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
