import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/theme/app_colors.dart';

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

class NexusOverlayToast {
  NexusOverlayToast._();

  static OverlayEntry? _activeEntry;
  static Timer? _dismissTimer;

  static void show({
    required GlobalKey<NavigatorState> navigatorKey,
    required String title,
    required String message,
    required Color accentColor,
    required IconData icon,
    VoidCallback? onTap,
    String? profilePic,
    Widget Function(String path)? storageImageBuilder,
    Duration duration = const Duration(seconds: 4),
  }) {
    final state = navigatorKey.currentState;
    if (state == null) return;

    _dismissTimer?.cancel();
    _activeEntry?.remove();
    _activeEntry = null;

    final overlayState = state.overlay;
    if (overlayState == null) return;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => Positioned(
        top: MediaQuery.of(ctx).padding.top + 12,
        left: 16,
        right: 16,
        child: SafeArea(
          top: false,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: () {
                entry.remove();
                _dismissTimer?.cancel();
                _activeEntry = null;
                onTap?.call();
              },
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF161B26).withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: accentColor.withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.15),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    if (profilePic != null &&
                        profilePic.isNotEmpty &&
                        storageImageBuilder != null)
                      ClipOval(
                        child: SizedBox(
                          width: 38,
                          height: 38,
                          child: storageImageBuilder(profilePic),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, color: accentColor, size: 22),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (title.isNotEmpty)
                            Text(
                              title,
                              style: TextStyle(
                                color: accentColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          if (message.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              message,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                height: 1.3,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        entry.remove();
                        _dismissTimer?.cancel();
                        _activeEntry = null;
                      },
                      child: const Icon(
                        Icons.close,
                        color: Colors.white60,
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    _activeEntry = entry;
    Future.delayed(Duration.zero, () {
      overlayState.insert(entry);
    });

    _dismissTimer = Timer(duration, () {
      entry.remove();
      if (_activeEntry == entry) {
        _activeEntry = null;
      }
    });
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
    final bottom = MediaQuery.of(context).viewPadding.bottom + 80;

    final (Color accent, IconData icon) = switch (widget.type) {
      NexusToastType.success => (
        AppColors.success,
        LucideIcons.circleCheck,
      ),
      NexusToastType.error => (AppColors.error, LucideIcons.circleX),
      NexusToastType.warning => (
        AppColors.warning,
        LucideIcons.triangleAlert,
      ),
      NexusToastType.info => (AppColors.info, LucideIcons.info),
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
