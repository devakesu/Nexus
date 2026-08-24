import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/core/widgets/nexus_toast.dart';
import 'package:nexus/features/chats/providers/chat_conversation_provider.dart';
import 'package:nexus/features/settings/screens/meetup_safety_page.dart';
import 'package:url_launcher/url_launcher.dart';

/// Renders a date/plan proposal: decrypted title/notes ([EventPayload]) +
/// plaintext time/location/status ([ChatEventInfo]) - see the doc comments
/// on those two classes for why they're split that way.
class EventCard extends ConsumerWidget {
  const EventCard({
    required this.payload,
    required this.eventInfo,
    required this.conversationId,
    required this.peerUserId,
    required this.themeColor,
    super.key,
  });

  final EventPayload payload;
  final ChatEventInfo eventInfo;
  final String conversationId;
  final String peerUserId;
  final Color themeColor;

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final suffix = local.hour >= 12 ? 'PM' : 'AM';
    return '${_months[local.month - 1]} ${local.day}, $hour:$minute $suffix';
  }

  Future<void> _openInMaps() async {
    final lat = eventInfo.locationLat;
    final lng = eventInfo.locationLng;
    if (lat == null || lng == null) return;
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    );
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _updateStatus(
    BuildContext context,
    WidgetRef ref,
    String status,
  ) async {
    final provider = chatConversationControllerProvider(
      conversationId,
      peerUserId,
    );
    final ok = await ref
        .read(provider.notifier)
        .updateEventStatus(eventInfo.eventId, status);
    if (!ok && context.mounted) {
      NexusToast.show(
        context,
        'Could not update the plan. Please try again.',
        type: NexusToastType.error,
      );
    }
  }

  void _openSafetyCheckIn(BuildContext context) {
    final untilEvent = eventInfo.eventTime.difference(DateTime.now());
    final clamped = untilEvent.isNegative
        ? null
        : (untilEvent > const Duration(hours: 3)
              ? const Duration(hours: 3)
              : untilEvent);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MeetupSafetyPage(
          initialCheckInLabel: payload.title,
          initialCheckInDuration: clamped,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (Color statusColor, String statusLabel) = switch (eventInfo.status) {
      'confirmed' => (AppColors.success, 'Confirmed'),
      'cancelled' => (const Color(0xFF94A3B8), 'Cancelled'),
      _ => (themeColor, 'Proposed'),
    };
    final hasLocation =
        eventInfo.locationLabel != null ||
        (eventInfo.locationLat != null && eventInfo.locationLng != null);
    final notes = payload.notes;

    return Container(
      width: 240,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(LucideIcons.calendarHeart, size: 16, color: themeColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Date Plan',
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.inkMuted,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  statusLabel,
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            payload.title,
            style: GoogleFonts.manrope(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(
                LucideIcons.clock,
                size: 13,
                color: AppColors.inkMuted,
              ),
              const SizedBox(width: 6),
              Text(
                _formatDateTime(eventInfo.eventTime),
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  color: const Color(0xFF475569),
                ),
              ),
            ],
          ),
          if (hasLocation) ...[
            const SizedBox(height: 4),
            GestureDetector(
              onTap: () => unawaited(_openInMaps()),
              child: Row(
                children: [
                  const Icon(
                    LucideIcons.mapPin,
                    size: 13,
                    color: AppColors.inkMuted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      eventInfo.locationLabel ?? 'Open in Maps',
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        color: themeColor,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (eventInfo.safetyEnabled) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(
                  LucideIcons.shieldCheck,
                  size: 13,
                  color: AppColors.safetyTeal,
                ),
                const SizedBox(width: 6),
                Text(
                  'Meetup Safety on',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.safetyTeal,
                  ),
                ),
              ],
            ),
          ],
          if (notes != null && notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              notes,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                color: const Color(0xFF475569),
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (eventInfo.status == 'proposed')
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        unawaited(_updateStatus(context, ref, 'cancelled')),
                    child: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () =>
                        unawaited(_updateStatus(context, ref, 'confirmed')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: themeColor,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Confirm'),
                  ),
                ),
              ],
            )
          else if (eventInfo.status == 'confirmed')
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () =>
                    unawaited(_updateStatus(context, ref, 'cancelled')),
                child: const Text('Cancel plan'),
              ),
            ),
          if (eventInfo.status != 'cancelled') ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () => _openSafetyCheckIn(context),
                icon: const Icon(LucideIcons.shieldCheck, size: 15),
                label: const Text('Set up a safety check-in'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
