import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nexus/features/chats/providers/presence_provider.dart';

/// "Active now" / "Active 2h ago" text, or nothing at all if the peer has
/// Active Status off, isn't matched with the viewer, or has never been
/// active - all three cases are indistinguishable by design (see
/// `presence_provider.dart`).
class PresenceBadge extends ConsumerWidget {
  const PresenceBadge({
    required this.peerUserId,
    this.style,
    this.fallback,
    this.poll = true,
    super.key,
  });

  final String peerUserId;
  final TextStyle? style;

  /// Shown instead of nothing when there's no presence to display.
  final Widget? fallback;

  /// Whether to start a 30s polling stream for this user's presence (true, default)
  /// or read from the non-polling batch presence map (false, used in chat lists).
  final bool poll;

  String? _describe(PresenceInfo info) {
    if (info.isOnline == true) return 'Active now';
    final lastActive = info.lastActiveAt;
    if (lastActive == null) return null;
    final diff = DateTime.now().difference(lastActive);
    if (diff.inMinutes < 1) return 'Active just now';
    if (diff.inMinutes < 60) return 'Active ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Active ${diff.inHours}h ago';
    if (diff.inDays < 7) return 'Active ${diff.inDays}d ago';
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PresenceInfo? info;
    if (poll) {
      info = ref.watch(peerPresenceProvider(peerUserId)).value;
    } else {
      info = ref.watch(batchPresenceProvider)[peerUserId];
    }

    final text = info != null ? _describe(info) : null;
    if (text == null) return fallback ?? const SizedBox.shrink();

    return Text(
      text,
      overflow: TextOverflow.ellipsis,
      style:
          style ??
          GoogleFonts.inter(
            fontSize: 11.5,
            color: Colors.white.withValues(alpha: 0.8),
          ),
    );
  }
}
