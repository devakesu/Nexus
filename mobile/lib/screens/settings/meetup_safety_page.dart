import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/services/meetup_safety_session.dart';
import 'package:nexus/services/safety_alert_api.dart';
import 'package:nexus/services/safety_contacts.dart';
import 'package:nexus/widgets/aesthetic_loaders.dart';
import 'package:nexus/widgets/nexus_toast.dart';
import 'package:nexus/widgets/safety_score_ring_painter.dart';
import 'package:nexus/widgets/scale_pressable.dart';

class MeetupSafetyPage extends StatefulWidget {
  const MeetupSafetyPage({
    this.initialCheckInLabel,
    this.initialCheckInDuration,
    super.key,
  });

  /// Pre-fills the Date Check-In form on open - used by a chat event card's
  /// "Set up a safety check-in" shortcut so the user doesn't have to retype
  /// a plan they already made in chat.
  final String? initialCheckInLabel;
  final Duration? initialCheckInDuration;

  @override
  State<MeetupSafetyPage> createState() => _MeetupSafetyPageState();
}

class _MeetupSafetyPageState extends State<MeetupSafetyPage> {
  static const _accent = Color(0xFF0284C7);
  static const _teal = Color(0xFF0D9488);

  // Emergency Contacts state
  List<SafetyContact> _contacts = [];
  bool _loadingContacts = true;

  // Date Check-In form state (the active session itself lives in
  // MeetupSafetySession, shared with CheckInAlertScreen).
  final TextEditingController _checkInLabelController = TextEditingController();
  Duration _checkInSelectedDuration = const Duration(hours: 1);

  // Ticks once a second purely to refresh the countdown text while a
  // session is active — MeetupSafetySession owns the actual deadline.
  Timer? _tickTimer;

  MeetupSafetySession get _session => MeetupSafetySession.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_loadContacts());
    _session.addListener(_onSessionChanged);
    _syncTicker();

    final initialLabel = widget.initialCheckInLabel;
    if (initialLabel != null) {
      _checkInLabelController.text = initialLabel;
    }
    if (widget.initialCheckInDuration != null) {
      _checkInSelectedDuration = widget.initialCheckInDuration!;
    }
  }

  @override
  void dispose() {
    _session.removeListener(_onSessionChanged);
    _tickTimer?.cancel();
    _checkInLabelController.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    setState(_syncTicker);
  }

  void _syncTicker() {
    if (_session.isActive && _tickTimer == null) {
      _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!_session.isActive && _tickTimer != null) {
      _tickTimer?.cancel();
      _tickTimer = null;
    }
  }

  // --- Contacts Storage Logic ---
  Future<void> _loadContacts() async {
    try {
      final loaded = await loadSafetyContacts();
      if (!mounted) return;
      setState(() {
        _contacts = loaded;
        _loadingContacts = false;
      });
    } on Exception catch (_) {
      if (mounted) setState(() => _loadingContacts = false);
    }
  }

  String _digitsOnly(String phone) => phone.replaceAll(RegExp(r'[^\d]'), '');

  void _addContact(String name, String phone) {
    if (_contacts.length >= 3) {
      NexusToast.show(
        context,
        'You can add a maximum of 3 trusted contacts.',
        type: NexusToastType.error,
      );
      return;
    }
    final alreadyAdded = _contacts.any(
      (c) => _digitsOnly(c.phone) == _digitsOnly(phone),
    );
    if (alreadyAdded) {
      NexusToast.show(
        context,
        'That contact is already on your trusted list.',
        type: NexusToastType.error,
      );
      return;
    }
    setState(() {
      _contacts.add(SafetyContact(name: name, phone: phone));
    });
    unawaited(saveSafetyContacts(_contacts));
    // Best-effort server mirror so SOS/inform alerts can be sent without
    // the device online — failures here don't block the local save above.
    unawaited(SafetyAlertApi.syncContacts(_contacts));
    NexusToast.show(
      context,
      'Contact added successfully',
      type: NexusToastType.success,
    );
  }

  void _deleteContact(int index) {
    setState(() {
      _contacts.removeAt(index);
    });
    unawaited(saveSafetyContacts(_contacts));
    unawaited(SafetyAlertApi.syncContacts(_contacts));
    NexusToast.show(context, 'Contact removed');
  }

  // Trusted contacts are picked straight from the device address book via
  // the native contact picker (permissionless on iOS; on Android, reading
  // the phone number back out requires READ_CONTACTS).
  Future<void> _pickContactFromDevice() async {
    if (_contacts.length >= 3) {
      NexusToast.show(
        context,
        'You can add a maximum of 3 trusted contacts.',
        type: NexusToastType.error,
      );
      return;
    }
    try {
      if (Platform.isAndroid) {
        final status = await FlutterContacts.permissions.request(
          PermissionType.read,
        );
        final granted =
            status == PermissionStatus.granted ||
            status == PermissionStatus.limited;
        if (!granted) {
          if (mounted) {
            NexusToast.show(
              context,
              'Contacts permission is needed to add a trusted contact.',
              type: NexusToastType.error,
            );
          }
          return;
        }
      }
      final contact = await FlutterContacts.native.showPicker(
        properties: {ContactProperty.phone},
      );
      if (contact == null) return;
      final name = contact.displayName?.trim() ?? '';
      final phone = contact.phones.isNotEmpty
          ? contact.phones.first.number.trim()
          : '';
      if (name.isEmpty) {
        if (mounted) {
          NexusToast.show(
            context,
            'That contact has no name on file.',
            type: NexusToastType.error,
          );
        }
        return;
      }
      if (phone.isEmpty) {
        if (mounted) {
          NexusToast.show(
            context,
            'That contact has no phone number.',
            type: NexusToastType.error,
          );
        }
        return;
      }
      if (!_isValidPhoneNumber(phone)) {
        if (mounted) {
          NexusToast.show(
            context,
            "That contact's phone number doesn't look valid.",
            type: NexusToastType.error,
          );
        }
        return;
      }
      _addContact(name, phone);
    } on PlatformException catch (_) {
      if (mounted) {
        NexusToast.show(
          context,
          'Could not access contacts.',
          type: NexusToastType.error,
        );
      }
    }
  }

  // Accepts any internationally-formatted number (+ country code, 8-15
  // digits) or a bare 10-digit Indian mobile number (starting 6-9, with an
  // optional leading 0 or 91 trunk prefix) — covers both local contacts and
  // contacts synced with a foreign country code.
  bool _isValidPhoneNumber(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^\d+]'), '');
    if (cleaned.startsWith('+')) {
      return RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(cleaned);
    }
    final withoutTrunkPrefix = cleaned.replaceFirst(RegExp('^(0|91)'), '');
    return RegExp(r'^[6-9]\d{9}$').hasMatch(withoutTrunkPrefix);
  }

  // --- Date Check-In Logic ---
  Future<void> _startCheckIn() async {
    final label = _checkInLabelController.text.trim();
    await _session.start(
      interval: _checkInSelectedDuration,
      label: label.isEmpty ? '' : label,
    );
    if (mounted) {
      NexusToast.show(
        context,
        'Check-in scheduled. Stay safe out there!',
        type: NexusToastType.success,
      );
    }
  }

  Future<void> _extendCheckIn(Duration extra) async {
    await _session.extend(extra);
    if (mounted) {
      NexusToast.show(
        context,
        'Added ${extra.inMinutes} minutes to your check-in.',
      );
    }
  }

  Future<void> _endMeetupSafety() async {
    await _session.end();
    if (mounted) {
      NexusToast.show(context, 'Meetup Safety turned off.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: _buildAppBar(),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 60),
        children: [
          _buildMeetupSafetySection(),
          _buildEmergencyContactsSection(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0284C7), Color(0xFF0D9488)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0x330284C7),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(LucideIcons.chevronLeft, color: Colors.white),
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            'Meetup Safety',
            style: GoogleFonts.manrope(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          centerTitle: true,
        ),
      ),
    );
  }

  // --- Meetup Safety Alert Section ---
  Widget _buildMeetupSafetySection() {
    return Container(
          margin: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      LucideIcons.shieldAlert,
                      color: Color(0xFFEF4444),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'MEETUP SAFETY ALERT',
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF475569),
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _session.isActive
                    ? "Meetup Safety is active. You'll be asked to check in periodically until you turn it off."
                    : 'Heading out to meet someone? Start a check-in below before you go.',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: const Color(0xFF64748B),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 20),
              AnimatedSwitcher(
                duration: 300.ms,
                child: _session.isActive
                    ? _buildCheckInActiveCard()
                    : _buildCheckInForm(),
              ),
            ],
          ),
        )
        .animate()
        .fadeIn(duration: 350.ms, curve: Curves.easeOut)
        .slideY(begin: 0.05, end: 0, duration: 350.ms);
  }

  Widget _buildCheckInForm() {
    final durationOptions = <Duration>[
      const Duration(minutes: 15),
      const Duration(minutes: 30),
      const Duration(hours: 1),
      const Duration(hours: 2),
    ];

    return Column(
      key: const ValueKey('checkin_form'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PLAN (OPTIONAL)',
          style: GoogleFonts.manrope(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF475569),
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _checkInLabelController,
          decoration: InputDecoration(
            hintText: 'e.g. Coffee with Jordan at Bloom Cafe',
            hintStyle: GoogleFonts.inter(
              fontSize: 13,
              color: const Color(0xFF475569),
            ),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFF1F5F9)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFF1F5F9)),
            ),
          ),
          style: GoogleFonts.inter(fontSize: 13),
        ),
        const SizedBox(height: 16),
        Text(
          'CHECK IN EVERY',
          style: GoogleFonts.manrope(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF475569),
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        Column(
          children: [
            for (var row = 0; row < 2; row++) ...[
              if (row > 0) const SizedBox(height: 8),
              Row(
                children: [
                  for (var col = 0; col < 2; col++) ...[
                    if (col > 0) const SizedBox(width: 8),
                    Expanded(
                      child: _buildDurationOption(
                        durationOptions[row * 2 + col],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
        const SizedBox(height: 18),
        _buildNotificationExplainerCard(),
        const SizedBox(height: 18),
        if (_contacts.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  LucideIcons.triangleAlert,
                  color: Color(0xFFEA580C),
                  size: 16,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Add a trusted contact first so we know who to alert.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: const Color(0xFF9A3412),
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          ScalePressable(
            onTap: _startCheckIn,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      LucideIcons.navigation,
                      size: 15,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Start Check-In',
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDurationOption(Duration d) {
    final selected = d == _checkInSelectedDuration;
    final label = d.inMinutes < 60 ? '${d.inMinutes}m' : '${d.inHours}h';
    return ScalePressable(
      onTap: () => setState(() => _checkInSelectedDuration = d),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected ? _accent : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? _accent : const Color(0xFFE2E8F0),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : const Color(0xFF475569),
          ),
        ),
      ),
    );
  }

  // Explains the persistent notification this feature relies on, with a
  // mock preview of what it looks like — this is illustrative UI, not a
  // live OS notification.
  Widget _buildNotificationExplainerCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                LucideIcons.bellRing,
                size: 15,
                color: Color(0xFF475569),
              ),
              const SizedBox(width: 8),
              Text(
                "WHILE ACTIVE, YOU'LL SEE",
                style: GoogleFonts.manrope(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF475569),
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildMockNotificationPreview(),
          const SizedBox(height: 12),
          Text(
            'This stays on your lock screen with SOS, Call 112, and Inform '
            'Trusted Contacts always one tap away. Allow lock-screen '
            'notification content and the full-screen alert permission if '
            "your phone asks — otherwise you'll only see it after unlocking.",
            style: GoogleFonts.inter(
              fontSize: 11.5,
              color: const Color(0xFF64748B),
              height: 1.45,
            ),
          ),
          if (Platform.isIOS) ...[
            const SizedBox(height: 6),
            Text(
              'On iPhone, the check-in alert arrives as a Time-Sensitive '
              "notification — it breaks through Focus/silent mode, but you'll "
              'still need to tap it to open the alert screen.',
              style: GoogleFonts.inter(
                fontSize: 11.5,
                color: const Color(0xFF64748B),
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMockNotificationPreview() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: _accent,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Icon(
                  LucideIcons.shieldCheck,
                  size: 13,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'NEXUS · NOW',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF94A3B8),
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Meetup Safety active',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Next check-in in 28:41',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildMockNotificationAction('SOS'),
              const SizedBox(width: 8),
              _buildMockNotificationAction('CALL 112'),
              const SizedBox(width: 8),
              _buildMockNotificationAction('INFORM'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMockNotificationAction(String label) {
    return Expanded(
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF475569),
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }

  Widget _buildCheckInActiveCard() {
    final interval = _session.checkInInterval;
    final nextAt = _session.nextCheckInAt;
    final remaining = nextAt == null
        ? Duration.zero
        : nextAt.difference(DateTime.now());
    final total = interval.inSeconds == 0 ? 1 : interval.inSeconds;
    final remainingFraction = (remaining.inSeconds / total).clamp(0.0, 1.0);
    final h = remaining.inHours;
    final m = remaining.inMinutes.remainder(60).clamp(0, 59);
    final s = remaining.inSeconds.remainder(60).clamp(0, 59);
    final timeText = h > 0
        ? '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
        : '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';

    return Column(
      key: const ValueKey('checkin_active'),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                _accent.withValues(alpha: 0.06),
                _teal.withValues(alpha: 0.06),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 56,
                height: 56,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 1, end: remainingFraction),
                      duration: 900.ms,
                      builder: (context, value, child) => CustomPaint(
                        size: const Size(56, 56),
                        painter: SafetyScoreRingPainter(progress: value),
                      ),
                    ),
                    const Icon(LucideIcons.mapPin, color: _accent, size: 18),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _session.checkInLabel.isEmpty
                          ? 'Meetup Safety'
                          : _session.checkInLabel,
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF0F172A),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      timeText,
                      style: GoogleFonts.manrope(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      'until your next check-in',
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ScalePressable(
          onTap: _endMeetupSafety,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Center(
              child: Text(
                'End Meetup Safety',
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF475569),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        ScalePressable(
          onTap: () => _extendCheckIn(const Duration(minutes: 30)),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Center(
              child: Text(
                '+ Add 30 Minutes',
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF475569),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // --- Emergency Contacts Section ---
  Widget _buildEmergencyContactsSection() {
    return Container(
          margin: const EdgeInsets.fromLTRB(20, 10, 20, 10),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          LucideIcons.users,
                          color: _teal,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'TRUSTED CONTACTS',
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF475569),
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                  if (_contacts.length < 3)
                    ScalePressable(
                      onTap: _pickContactFromDevice,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: _accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              LucideIcons.plus,
                              size: 12,
                              color: _accent,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Add (${_contacts.length}/3)',
                              style: GoogleFonts.manrope(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: _accent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                "Add up to 3 trusted contacts who'll be texted your location if the SOS trigger fires.",
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: const Color(0xFF64748B),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 16),
              if (_loadingContacts)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: NexusOrbitLoader(size: 40, lightMode: true),
                  ),
                )
              else if (_contacts.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFF1F5F9)),
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        LucideIcons.userPlus,
                        color: Color(0xFF94A3B8),
                        size: 28,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No contacts added yet',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Add trusted friends or family members to get started.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: const Color(0xFF475569),
                        ),
                      ),
                    ],
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _contacts.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final c = _contacts[index];
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFF1F5F9)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _accent.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              LucideIcons.user,
                              color: _accent,
                              size: 16,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c.name,
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  c.phone,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              LucideIcons.trash2,
                              color: Color(0xFF94A3B8),
                              size: 18,
                            ),
                            tooltip: 'Remove ${c.name}',
                            onPressed: () => _deleteContact(index),
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        )
        .animate()
        .fadeIn(delay: 100.ms, duration: 350.ms)
        .slideY(begin: 0.05, end: 0, duration: 350.ms);
  }
}
