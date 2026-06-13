import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CustomBottomNavBar extends StatelessWidget {
  const CustomBottomNavBar({
    required this.currentIndex,
    required this.onTabSelected,
    super.key,
  });

  final int currentIndex;
  final ValueChanged<int> onTabSelected;

  Color _getSelectedColor(int index) {
    switch (index) {
      case 0:
        return const Color(0xFFFF4F81); // Dating
      case 1:
        return const Color(0xFFFF9F1C); // Friends
      case 2:
        return const Color(0xFF0891B2); // Profile
      case 3:
        return const Color(0xFF00F5D4); // Professional
      case 4:
        return const Color(0xFF4EA8DE); // Settings
      default:
        return const Color(0xFF0891B2);
    }
  }

  Color _getUnselectedColor(bool isDark) {
    return isDark ? const Color(0x9994A3B8) : const Color(0xFF64748B);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      height: 72,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B26) : Colors.white,
        borderRadius: BorderRadius.circular(36),
        border: Border.all(
          color: isDark ? Colors.white.withAlpha(20) : Colors.black.withAlpha(15),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withAlpha(50) : Colors.black.withAlpha(15),
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
            _buildNavItem(context, 0, Icons.favorite_rounded, 'dating', isDark),
            _buildNavItem(context, 1, Icons.all_inclusive_rounded, 'friends', isDark),
            _buildCenterNavItem(context, isDark),
            _buildNavItem(context, 3, Icons.work_rounded, 'work', isDark),
            _buildNavItem(context, 4, Icons.blur_circular_rounded, 'settings', isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(BuildContext context, int index, IconData icon, String label, bool isDark) {
    final isSelected = currentIndex == index;
    final selectedColor = _getSelectedColor(index);
    final unselectedColor = _getUnselectedColor(isDark);

    return GestureDetector(
      onTap: () {
        unawaited(HapticFeedback.lightImpact());
        onTabSelected(index);
      },
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? selectedColor.withAlpha(38)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: TweenAnimationBuilder<Color?>(
              duration: const Duration(milliseconds: 250),
              tween: ColorTween(
                begin: unselectedColor,
                end: isSelected ? selectedColor : unselectedColor,
              ),
              builder: (context, color, child) {
                return Icon(
                  icon,
                  color: color,
                  size: 22,
                );
              },
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label.toLowerCase(),
            style: TextStyle(
              fontSize: 9,
              letterSpacing: 1.2,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w400,
              color: isSelected
                  ? selectedColor
                  : unselectedColor.withAlpha(120),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCenterNavItem(BuildContext context, bool isDark) {
    final isSelected = currentIndex == 2;
    final selectedColor = _getSelectedColor(2); // Pulsar Pink
    final unselectedColor = _getUnselectedColor(isDark);

    return GestureDetector(
      onTap: () {
        unawaited(HapticFeedback.lightImpact());
        onTabSelected(2);
      },
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
                begin: unselectedColor,
                end: isSelected ? selectedColor : unselectedColor,
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
            style: TextStyle(
              fontSize: 9,
              letterSpacing: 1.2,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w400,
              color: isSelected
                  ? selectedColor
                  : unselectedColor.withAlpha(120),
            ),
          ),
        ],
      ),
    );
  }
}
