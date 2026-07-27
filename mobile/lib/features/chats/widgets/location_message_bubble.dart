import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/features/chats/providers/chat_conversation_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// A casual, fully-encrypted "here's where I am" pin. No embedded
/// interactive map (that would need a Maps tile fetch per bubble) - just
/// an icon + label that opens the native/web Maps app on tap.
class LocationMessageBubble extends StatelessWidget {
  const LocationMessageBubble({
    required this.pointer,
    required this.isMine,
    super.key,
  });

  final LocationPointer pointer;
  final bool isMine;

  Future<void> _openInMaps() async {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${pointer.lat},${pointer.lng}',
    );
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final textColor = isMine ? Colors.white : const Color(0xFF0F172A);
    final subColor = isMine
        ? Colors.white.withValues(alpha: 0.85)
        : const Color(0xFF64748B);
    final tileColor = (isMine ? Colors.white : const Color(0xFF0F172A))
        .withValues(alpha: 0.12);

    return GestureDetector(
      onTap: () => unawaited(_openInMaps()),
      child: SizedBox(
        width: 200,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 100,
              width: double.infinity,
              decoration: BoxDecoration(
                color: tileColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Icon(LucideIcons.mapPin, size: 32, color: textColor),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(LucideIcons.externalLink, size: 12, color: subColor),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    pointer.label ?? 'Shared location',
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
