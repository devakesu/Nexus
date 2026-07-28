import 'dart:async';
// Trigger analyzer refresh
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nexus/core/theme/app_colors.dart';

class CustomBottomNavBar extends StatelessWidget {
  const CustomBottomNavBar({
    required this.currentIndex,
    required this.onTabSelected,
    this.showDatingBadge = false,
    this.showFriendsBadge = false,
    this.showProfessionalBadge = false,
    super.key,
  });

  final int currentIndex;
  final ValueChanged<int> onTabSelected;
  final bool showDatingBadge;
  final bool showFriendsBadge;
  final bool showProfessionalBadge;

  /// The nav's own height, in logical pixels.
  static const double navHeight = 72;

  /// The nav's bottom margin off the screen edge.
  static const double bottomMargin = 20;

  /// Total space scrollable or positioned content should reserve above the
  /// screen bottom so it isn't obscured by the floating nav: [navHeight] +
  /// [bottomMargin] + a comfortable breathing gap. Screens should reference
  /// this instead of a hardcoded bottom-padding literal - that's exactly how
  /// this drifted before (some screens reserved 110px, others 120px, with no
  /// shared source of truth).
  static const double clearance = navHeight + bottomMargin + 18;

  Color _getSelectedColor(int index) {
    switch (index) {
      case 0:
        return AppColors.modeDating; // Dating
      case 1:
        return AppColors.modeFriends; // Friends
      case 2:
        return AppColors.primaryTeal; // Profile
      case 3:
        return AppColors.modeProfessional; // Professional
      case 4:
        return AppColors.modeSettings; // Settings
      default:
        return AppColors.primaryTeal;
    }
  }

  static const Color _unselectedColor = AppColors.inkMuted;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      height: 72,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(36),
        border: Border.all(color: Colors.black.withAlpha(15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(15),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(
              context,
              0,
              Icons.favorite_rounded,
              'dating',
              showBadge: showDatingBadge,
            ),
            _buildNavItem(
              context,
              1,
              Icons.all_inclusive_rounded,
              'friends',
              showBadge: showFriendsBadge,
            ),
            _buildCenterNavItem(context),
            _buildNavItem(
              context,
              3,
              Icons.work_rounded,
              'work',
              showBadge: showProfessionalBadge,
            ),
            _buildNavItem(
              context,
              4,
              Icons.blur_circular_rounded,
              'settings',
            ),
          ],
        ),
      ),
    );
  }

  void _handleTabTap(int index) {
    unawaited(HapticFeedback.lightImpact());
    onTabSelected(index);
  }

  Widget _buildNavItem(
    BuildContext context,
    int index,
    IconData icon,
    String label, {
    bool showBadge = false,
  }) {
    final isSelected = currentIndex == index;
    final selectedColor = _getSelectedColor(index);

    return Semantics(
      button: true,
      selected: isSelected,
      label: '$label tab',
      excludeSemantics: true,
      onTap: () => _handleTabTap(index),
      child: GestureDetector(
        onTap: () => _handleTabTap(index),
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: isSelected
                    ? selectedColor.withAlpha(38)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: TweenAnimationBuilder<Color?>(
                duration: const Duration(milliseconds: 250),
                tween: ColorTween(
                  begin: _unselectedColor,
                  end: isSelected ? selectedColor : _unselectedColor,
                ),
                builder: (context, color, child) {
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                        icon,
                        color: color,
                        size: 22,
                      ),
                      if (showBadge)
                        Positioned(
                          top: -2,
                          right: -2,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: selectedColor,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label.toLowerCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9,
                letterSpacing: 1.2,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w400,
                color: isSelected
                    ? selectedColor
                    : _unselectedColor.withAlpha(120),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterNavItem(BuildContext context) {
    final isSelected = currentIndex == 2;
    final selectedColor = _getSelectedColor(2); // Pulsar Pink

    return Semantics(
      button: true,
      selected: isSelected,
      label: 'Profile tab',
      excludeSemantics: true,
      onTap: () => _handleTabTap(2),
      child: GestureDetector(
        onTap: () => _handleTabTap(2),
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected
                    ? selectedColor.withAlpha(51)
                    : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? selectedColor.withAlpha(102)
                      : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: TweenAnimationBuilder<Color?>(
                duration: const Duration(milliseconds: 250),
                tween: ColorTween(
                  begin: _unselectedColor,
                  end: isSelected ? selectedColor : _unselectedColor,
                ),
                builder: (context, color, child) {
                  return Icon(
                    Icons.fingerprint_rounded,
                    color: color,
                    size: 24,
                  );
                },
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'profile',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9,
                letterSpacing: 1.2,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w400,
                color: isSelected
                    ? selectedColor
                    : _unselectedColor.withAlpha(120),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
