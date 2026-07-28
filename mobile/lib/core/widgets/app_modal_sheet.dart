import 'package:flutter/material.dart';
import 'package:nexus/core/theme/app_colors.dart';

class AppModalSheet extends StatelessWidget {
  const AppModalSheet({
    required this.child,
    this.backgroundColor = AppColors.ink,
    this.borderRadius = 32.0,
    this.heightFactor = 0.75,
    this.showDragHandle = true,
    super.key,
  });

  final Widget child;
  final Color backgroundColor;
  final double borderRadius;
  final double heightFactor;
  final bool showDragHandle;

  static Future<T?> show<T>({
    required BuildContext context,
    required Widget child,
    Color backgroundColor = AppColors.ink,
    double borderRadius = 32.0,
    double heightFactor = 0.75,
    bool isScrollControlled = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AppModalSheet(
        backgroundColor: backgroundColor,
        borderRadius: borderRadius,
        heightFactor: heightFactor,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * heightFactor,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(borderRadius)),
      ),
      child: Column(
        children: [
          if (showDragHandle) ...[
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Expanded(child: child),
        ],
      ),
    );
  }
}
