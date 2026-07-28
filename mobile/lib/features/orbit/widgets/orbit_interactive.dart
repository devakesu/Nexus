import 'package:flutter/material.dart';
import 'package:nexus/core/widgets/scale_pressable.dart';

class InteractiveOrbitNode extends StatelessWidget {
  const InteractiveOrbitNode({
    required this.child,
    required this.onTap,
    super.key,
  });

  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ScalePressable(
      onTap: onTap,
      child: child,
    );
  }
}
