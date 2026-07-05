import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/providers/chat_conversation_provider.dart';
import 'package:nexus/screens/chats/widgets/location_picker_sheet.dart';
import 'package:nexus/widgets/nexus_toast.dart';

/// Bottom sheet for proposing a date/plan: title, date, time, optional
/// location and notes. Submits via [ChatConversationController.createEvent].
class EventPlannerSheet extends ConsumerStatefulWidget {
  const EventPlannerSheet({
    required this.conversationId,
    required this.peerUserId,
    required this.themeColor,
    super.key,
  });

  final String conversationId;
  final String peerUserId;
  final Color themeColor;

  @override
  ConsumerState<EventPlannerSheet> createState() => _EventPlannerSheetState();
}

class _EventPlannerSheetState extends ConsumerState<EventPlannerSheet> {
  final _titleController = TextEditingController();
  final _notesController = TextEditingController();
  DateTime? _date;
  TimeOfDay? _time;
  LocationPointer? _location;
  bool _submitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? TimeOfDay.now(),
    );
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _pickLocation() async {
    final result = await Navigator.of(context).push<LocationPointer>(
      MaterialPageRoute<LocationPointer>(
        fullscreenDialog: true,
        builder: (_) => LocationPickerSheet(themeColor: widget.themeColor),
      ),
    );
    if (result != null && mounted) setState(() => _location = result);
  }

  bool get _canSubmit =>
      _titleController.text.trim().isNotEmpty &&
      _date != null &&
      _time != null &&
      !_submitting;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    final date = _date!;
    final time = _time!;
    final eventTime = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    setState(() => _submitting = true);
    final provider = chatConversationControllerProvider(
      widget.conversationId,
      widget.peerUserId,
    );
    final notes = _notesController.text.trim();
    final ok = await ref
        .read(provider.notifier)
        .createEvent(
          eventTime: eventTime,
          title: _titleController.text.trim(),
          notes: notes.isEmpty ? null : notes,
          locationLat: _location?.lat,
          locationLng: _location?.lng,
          locationLabel: _location?.label,
        );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok) {
      Navigator.of(context).pop();
    } else {
      NexusToast.show(
        context,
        'Could not create the plan. Please try again.',
        type: NexusToastType.error,
      );
    }
  }

  String _formatDate(DateTime d) => '${d.month}/${d.day}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.calendarPlus, color: widget.themeColor),
                  const SizedBox(width: 8),
                  Text(
                    'Plan a date',
                    style: GoogleFonts.manrope(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  hintText: 'e.g. Coffee at Blue Bottle',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => unawaited(_pickDate()),
                      icon: const Icon(LucideIcons.calendar, size: 16),
                      label: Text(_date == null ? 'Date' : _formatDate(_date!)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => unawaited(_pickTime()),
                      icon: const Icon(LucideIcons.clock, size: 16),
                      label: Text(_time == null ? 'Time' : _time!.format(context)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => unawaited(_pickLocation()),
                icon: const Icon(LucideIcons.mapPin, size: 16),
                label: Text(
                  _location == null
                      ? 'Add location (optional)'
                      : (_location!.label ??
                            '${_location!.lat.toStringAsFixed(4)}, '
                                '${_location!.lng.toStringAsFixed(4)}'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notesController,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Notes (optional)'),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _canSubmit ? () => unawaited(_submit()) : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.themeColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Send plan',
                          style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
