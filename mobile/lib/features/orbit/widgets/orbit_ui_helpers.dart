import 'package:flutter/material.dart';

// ── One edge of the viewport-edge vignette (see "Edge vignette" above) ──────

class OrbitEdgeFade extends StatelessWidget {
  const OrbitEdgeFade({required this.alignment, super.key});

  /// Which physical edge this strip fades toward.
  final Alignment alignment;

  static const _fadeColor = Color(0xFF020408);
  static const _span = 110.0;

  @override
  Widget build(BuildContext context) {
    final gradient = LinearGradient(
      begin: alignment,
      end: -alignment,
      colors: [_fadeColor.withValues(alpha: 0.85), Colors.transparent],
    );
    final strip = DecoratedBox(decoration: BoxDecoration(gradient: gradient));

    if (alignment == Alignment.topCenter) {
      return Positioned(top: 0, left: 0, right: 0, height: _span, child: strip);
    }
    if (alignment == Alignment.bottomCenter) {
      return Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        height: _span,
        child: strip,
      );
    }
    if (alignment == Alignment.centerLeft) {
      return Positioned(top: 0, bottom: 0, left: 0, width: _span, child: strip);
    }
    return Positioned(top: 0, bottom: 0, right: 0, width: _span, child: strip);
  }
}

// ── Header icon button with a Signal Glow press state (Ambient-Plus-One:
// zero glow at rest, one glow on press) instead of the default Material
// ripple, matching the rest of the app's hand-built tactile chrome ────────────

class OrbitHeaderIconButton extends StatefulWidget {
  const OrbitHeaderIconButton({
    required this.icon,
    required this.onPressed,
    required this.glowColor,
    required this.semanticLabel,
    super.key,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final Color glowColor;
  final String semanticLabel;

  @override
  State<OrbitHeaderIconButton> createState() => _OrbitHeaderIconButtonState();
}

class _OrbitHeaderIconButtonState extends State<OrbitHeaderIconButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: _pressed
                ? [
                    BoxShadow(
                      color: widget.glowColor.withValues(alpha: 0.25),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ]
                : const [],
          ),
          child: Icon(widget.icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}
