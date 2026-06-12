import 'package:flutter/material.dart';
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
    const deepPurple = Color(0xFF7C3AED);

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
                        color: deepPurple,
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
                                if ((isProcessingAI || isSaving) && hasPendingUpload)
                                  const Positioned.fill(
                                    child: ColoredBox(
                                      color: Colors.black54,
                                      child: Center(
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(pulsarPink),
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
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: pulsarPink,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      LucideIcons.user,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Hey, $name.',
            style: const TextStyle(
              fontFamily: 'Outfit',
              fontSize: 24,
              fontWeight: FontWeight.w300,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Currently floating in the Nebula.',
            style: TextStyle(
              fontFamily: 'Outfit',
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.4),
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
