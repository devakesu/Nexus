import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

enum NexusToastType { success, error, info, warning }

class NexusToast {
  NexusToast._();

  static void show(
    BuildContext context,
    String message, {
    NexusToastType type = NexusToastType.info,
    Duration duration = const Duration(seconds: 3),
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _NexusToastEntry(
        message: message,
        type: type,
        duration: duration,
        onDone: () {
          if (entry.mounted) entry.remove();
        },
      ),
    );
    overlay.insert(entry);
  }
}

class _NexusToastEntry extends StatefulWidget {
  const _NexusToastEntry({
    required this.message,
    required this.type,
    required this.duration,
    required this.onDone,
  });

  final String message;
  final NexusToastType type;
  final Duration duration;
  final VoidCallback onDone;

  @override
  State<_NexusToastEntry> createState() => _NexusToastEntryState();
}

class _NexusToastEntryState extends State<_NexusToastEntry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 220),
    );
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.35),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    unawaited(
      _ctrl.forward().then((_) {
        Future.delayed(widget.duration, () async {
          if (mounted) {
            await _ctrl.reverse();
            widget.onDone();
          }
        });
      }),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Position above the floating bottom nav bar.
    // Nav bar: 72 height + 20 bottom margin = 92px above safe area bottom.
    final bottom = MediaQuery.of(context).viewPadding.bottom + 104;

    final (Color accent, IconData icon) = switch (widget.type) {
      NexusToastType.success => (
        const Color(0xFF10B981),
        LucideIcons.circleCheck,
      ),
      NexusToastType.error => (const Color(0xFFEF4444), LucideIcons.circleX),
      NexusToastType.warning => (
        const Color(0xFFF59E0B),
        LucideIcons.triangleAlert,
      ),
      NexusToastType.info => (const Color(0xFF60A5FA), LucideIcons.info),
    };

    return Positioned(
      bottom: bottom,
      left: 20,
      right: 20,
      child: FadeTransition(
        opacity: _opacity,
        child: SlideTransition(
          position: _slide,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1117),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: accent.withValues(alpha: 0.28)),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.12),
                    blurRadius: 24,
                    offset: const Offset(0, 6),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.55),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(icon, color: accent, size: 17),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
