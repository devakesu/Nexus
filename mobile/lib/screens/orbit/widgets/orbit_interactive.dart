import 'package:flutter/material.dart';

class InteractiveOrbitNode extends StatefulWidget {
  const InteractiveOrbitNode({
    required this.child,
    required this.onTap,
    super.key,
  });

  final Widget child;
  final VoidCallback onTap;

  @override
  State<InteractiveOrbitNode> createState() => _InteractiveOrbitNodeState();
}

class _InteractiveOrbitNodeState extends State<InteractiveOrbitNode> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _isPressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
