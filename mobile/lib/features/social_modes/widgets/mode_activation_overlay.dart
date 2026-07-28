import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/features/home/widgets/custom_bottom_nav_bar.dart';

class ModeActivationOverlay extends StatefulWidget {
  const ModeActivationOverlay({
    required this.modeTitle,
    required this.subtitle,
    required this.icon,
    required this.brandColor,
    required this.onFinished,
    super.key,
  });

  final String modeTitle;
  final String subtitle;
  final IconData icon;
  final Color brandColor;
  final VoidCallback onFinished;

  @override
  State<ModeActivationOverlay> createState() => _ModeActivationOverlayState();
}

class _ModeActivationOverlayState extends State<ModeActivationOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.8, curve: Curves.easeOutBack),
      ),
    );

    _fadeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 0, end: 1), weight: 15),
      TweenSequenceItem(tween: ConstantTween<double>(1), weight: 70),
      TweenSequenceItem(tween: Tween<double>(begin: 1, end: 0), weight: 15),
    ]).animate(_controller);

    _rotationAnimation = Tween<double>(begin: 0, end: 2 * 3.14159).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.9),
      ),
    );

    unawaited(_controller.forward().then((_) => widget.onFinished()));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.ink,
                widget.brandColor.withValues(alpha: 0.15),
                widget.brandColor.withValues(alpha: 0.35),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedBuilder(
                animation: _rotationAnimation,
                builder: (context, child) {
                  return Transform.rotate(
                    angle: _rotationAnimation.value,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        _buildRing(
                          260,
                          4,
                          widget.brandColor.withValues(alpha: 0.1),
                        ),
                        _buildRing(
                          200,
                          3,
                          widget.brandColor.withValues(alpha: 0.2),
                        ),
                        _buildRing(
                          140,
                          2,
                          widget.brandColor.withValues(alpha: 0.3),
                        ),
                      ],
                    ),
                  );
                },
              ),
              ScaleTransition(
                scale: _scaleAnimation,
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.brandColor,
                    boxShadow: [
                      BoxShadow(
                        color: widget.brandColor.withValues(alpha: 0.5),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      widget.icon,
                      color: Colors.black87,
                      size: 40,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: CustomBottomNavBar.clearance,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.modeTitle.toUpperCase(),
                      style: TextStyle(
                        color: widget.brandColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Orbit Activated',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      widget.subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
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

  Widget _buildRing(double size, double strokeWidth, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: strokeWidth),
      ),
    );
  }
}

class FriendsActivationOverlay extends StatelessWidget {
  const FriendsActivationOverlay({required this.onFinished, super.key});
  final VoidCallback onFinished;

  @override
  Widget build(BuildContext context) {
    return ModeActivationOverlay(
      modeTitle: 'Friends Orbit',
      subtitle: 'Broadcasting your social signals nearby...',
      icon: LucideIcons.users,
      brandColor: AppColors.modeFriends,
      onFinished: onFinished,
    );
  }
}

class DatingActivationOverlay extends StatelessWidget {
  const DatingActivationOverlay({required this.onFinished, super.key});
  final VoidCallback onFinished;

  @override
  Widget build(BuildContext context) {
    return ModeActivationOverlay(
      modeTitle: 'Dating Orbit',
      subtitle: 'Broadcasting your dating signals nearby...',
      icon: LucideIcons.heart,
      brandColor: AppColors.modeDating,
      onFinished: onFinished,
    );
  }
}

class ProfessionalActivationOverlay extends StatelessWidget {
  const ProfessionalActivationOverlay({required this.onFinished, super.key});
  final VoidCallback onFinished;

  @override
  Widget build(BuildContext context) {
    return ModeActivationOverlay(
      modeTitle: 'Professional Orbit',
      subtitle: 'Broadcasting your professional signals nearby...',
      icon: LucideIcons.handshake,
      brandColor: AppColors.modeProfessional,
      onFinished: onFinished,
    );
  }
}
