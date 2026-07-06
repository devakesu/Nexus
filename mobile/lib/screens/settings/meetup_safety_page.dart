import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/widgets/aesthetic_loaders.dart';
import 'package:nexus/widgets/nexus_toast.dart';
import 'package:nexus/widgets/safety_score_ring_painter.dart';
import 'package:nexus/widgets/scale_pressable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class SafetyContact {
  SafetyContact({required this.name, required this.phone});

  factory SafetyContact.fromJson(Map<String, dynamic> json) {
    return SafetyContact(
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
    );
  }
  final String name;
  final String phone;

  Map<String, dynamic> toJson() => {'name': name, 'phone': phone};
}

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
  static const _red = Color(0xFFEF4444);

  // SOS state variables
  bool _sosActive = false;
  int _sosCountdown = 5;
  Timer? _sosTimer;

  // Emergency Contacts state
  List<SafetyContact> _contacts = [];
  bool _loadingContacts = true;

  // Date Check-In state
  bool _checkInActive = false;
  String _checkInLabel = '';
  Duration _checkInStartedDuration = const Duration(hours: 1);
  DateTime? _checkInEndsAt;
  Duration _checkInRemaining = Duration.zero;
  Timer? _checkInTimer;
  int? _checkInContactIndex;
  final TextEditingController _checkInLabelController = TextEditingController();
  Duration _checkInSelectedDuration = const Duration(hours: 1);

  @override
  void initState() {
    super.initState();
    unawaited(_loadContacts());

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
    _sosTimer?.cancel();
    _checkInTimer?.cancel();
    _checkInLabelController.dispose();
    super.dispose();
  }

  // --- SOS Logic ---
  void _startSos() {
    setState(() {
      _sosActive = true;
      _sosCountdown = 5;
    });
    _sosTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_sosCountdown > 1) {
        setState(() {
          _sosCountdown--;
        });
      } else {
        _sosTimer?.cancel();
        _triggerSosAlert();
      }
    });
  }

  void _cancelSos() {
    _sosTimer?.cancel();
    setState(() {
      _sosActive = false;
    });
    NexusToast.show(context, 'SOS Alert Cancelled');
  }

  void _triggerSosAlert() {
    setState(() {
      _sosActive = false;
    });
    // Create a string of contacts to mock notification
    final contactNames = _contacts.map((c) => c.name).join(', ');
    final message = _contacts.isEmpty
        ? 'Emergency SOS Activated! Mocking broadcast alert...'
        : 'Emergency SOS Activated! Mock alert and GPS location sent to: $contactNames';

    unawaited(
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          icon: const Icon(
            LucideIcons.shieldAlert,
            color: _red,
            size: 48,
          ).animate(onPlay: (c) => c.repeat()).shake(duration: 800.ms, hz: 4),
          title: Text(
            'Emergency Triggered',
            style: GoogleFonts.manrope(
              fontWeight: FontWeight.w800,
              color: _red,
            ),
          ),
          content: Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 14, height: 1.45),
          ),
          actions: [
            Center(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(
                  'Dismiss',
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Contacts Storage Logic ---
  Future<void> _loadContacts() async {
    try {
      const secureStorage = FlutterSecureStorage(
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
        ),
      );
      final val = await secureStorage.read(key: 'safety_contacts');
      var loaded = <SafetyContact>[];
      if (val != null) {
        final list = jsonDecode(val) as List<dynamic>;
        loaded = list
            .map((item) => SafetyContact.fromJson(item as Map<String, dynamic>))
            .toList();
      } else {
        // Fallback migration check from SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        final list = prefs.getStringList('safety_contacts');
        if (list != null && list.isNotEmpty) {
          loaded = list
              .map(
                (item) => SafetyContact.fromJson(
                  jsonDecode(item) as Map<String, dynamic>,
                ),
              )
              .toList();
          final encList = loaded.map((c) => c.toJson()).toList();
          await secureStorage.write(
            key: 'safety_contacts',
            value: jsonEncode(encList),
          );
          await prefs.remove('safety_contacts');
        }
      }
      if (!mounted) return;
      setState(() {
        _contacts = loaded;
        _loadingContacts = false;
      });
    } on Exception catch (_) {
      if (mounted) setState(() => _loadingContacts = false);
    }
  }

  Future<void> _saveContacts() async {
    try {
      const secureStorage = FlutterSecureStorage(
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
        ),
      );
      final encList = _contacts.map((c) => c.toJson()).toList();
      await secureStorage.write(
        key: 'safety_contacts',
        value: jsonEncode(encList),
      );
    } on Exception catch (_) {
      if (mounted) {
        NexusToast.show(
          context,
          'Failed to save contacts',
          type: NexusToastType.error,
        );
      }
    }
  }

  void _addContact(String name, String phone) {
    if (_contacts.length >= 3) {
      NexusToast.show(
        context,
        'You can add a maximum of 3 trusted contacts.',
        type: NexusToastType.error,
      );
      return;
    }
    setState(() {
      _contacts.add(SafetyContact(name: name, phone: phone));
    });
    unawaited(_saveContacts());
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
    unawaited(_saveContacts());
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
  void _startCheckIn() {
    final label = _checkInLabelController.text.trim();
    setState(() {
      _checkInActive = true;
      _checkInLabel = label.isEmpty ? 'Your date' : label;
      _checkInStartedDuration = _checkInSelectedDuration;
      _checkInEndsAt = DateTime.now().add(_checkInSelectedDuration);
      _checkInRemaining = _checkInSelectedDuration;
      _checkInContactIndex ??= _contacts.isNotEmpty ? 0 : null;
    });
    _checkInTimer?.cancel();
    _checkInTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final endsAt = _checkInEndsAt;
      if (endsAt == null) return;
      final remaining = endsAt.difference(DateTime.now());
      if (remaining.isNegative || remaining == Duration.zero) {
        timer.cancel();
        _onCheckInExpired();
      } else {
        setState(() => _checkInRemaining = remaining);
      }
    });
    NexusToast.show(
      context,
      'Check-in scheduled. Stay safe out there!',
      type: NexusToastType.success,
    );
  }

  void _checkInSafely() {
    _checkInTimer?.cancel();
    setState(() {
      _checkInActive = false;
      _checkInEndsAt = null;
    });
    NexusToast.show(
      context,
      "Glad you're safe! Check-in closed.",
      type: NexusToastType.success,
    );
  }

  void _extendCheckIn(Duration extra) {
    final endsAt = _checkInEndsAt;
    if (endsAt == null) return;
    setState(() {
      _checkInEndsAt = endsAt.add(extra);
      _checkInStartedDuration += extra;
      _checkInRemaining += extra;
    });
    NexusToast.show(
      context,
      'Added ${extra.inMinutes} minutes to your check-in.',
    );
  }

  void _onCheckInExpired() {
    setState(() {
      _checkInActive = false;
      _checkInEndsAt = null;
    });
    final contactName =
        (_checkInContactIndex != null &&
            _checkInContactIndex! < _contacts.length)
        ? _contacts[_checkInContactIndex!].name
        : 'your trusted contacts';
    unawaited(
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          icon: const Icon(
            LucideIcons.alarmClockCheck,
            color: _red,
            size: 48,
          ).animate(onPlay: (c) => c.repeat()).shake(duration: 800.ms, hz: 4),
          title: Text(
            'Check-In Missed',
            style: GoogleFonts.manrope(
              fontWeight: FontWeight.w800,
              color: _red,
            ),
          ),
          content: Text(
            "You didn't check in for \"$_checkInLabel\" in time. A mock safety alert with your last shared plan has been sent to $contactName.",
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 14, height: 1.45),
          ),
          actions: [
            Center(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(
                  'Dismiss',
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- External URL launcher helper ---
  Future<void> _launchUrlHelper(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        NexusToast.show(
          context,
          'Could not launch helpline dialer',
          type: NexusToastType.error,
        );
      }
    }
  }

  // Lighter-weight than the full SOS flow: no countdown, just a mock nudge
  // to trusted contacts letting them know to check in on you.
  void _informTrustedContacts() {
    if (_contacts.isEmpty) {
      NexusToast.show(
        context,
        'Add a trusted contact first so we know who to alert.',
        type: NexusToastType.error,
      );
      return;
    }
    final contactNames = _contacts.map((c) => c.name).join(', ');
    NexusToast.show(
      context,
      'Mock alert sent to $contactNames with your live check-in status.',
      type: NexusToastType.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.only(bottom: 60),
            children: [
              _buildMeetupSafetySection(),
              _buildEmergencyContactsSection(),
            ],
          ),
          if (_sosActive) _buildSosOverlay(),
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
  // Combines the Date Check-In controls with the persistent alert panel
  // explainer: start/manage a check-in here, and while one is active the
  // same card surfaces the SOS / Call 112 / Inform Trusted Contacts panel.
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
                      color: _red,
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
                  if (_checkInActive)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: _red,
                                  shape: BoxShape.circle,
                                ),
                              )
                              .animate(onPlay: (c) => c.repeat(reverse: true))
                              .fadeOut(
                                duration: 700.ms,
                                curve: Curves.easeInOut,
                              ),
                          const SizedBox(width: 6),
                          Text(
                            'LIVE',
                            style: GoogleFonts.manrope(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: _red,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _checkInActive
                    ? "Your meetup alert panel is active for the rest of this check-in. These stay one tap away — even if you're mid-conversation."
                    : "Heading out to meet someone? Start a check-in below before you go. While it's active, a persistent alert panel stays on your device for the whole meetup — with SOS, Call 112, and Inform Trusted Contacts always one tap away.",
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: const Color(0xFF64748B),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 20),
              AnimatedSwitcher(
                duration: 300.ms,
                child: _checkInActive
                    ? Column(
                        key: const ValueKey('meetup_active'),
                        children: [
                          _buildCheckInActiveCard(),
                          const SizedBox(height: 20),
                          _buildMeetupAlertActions(),
                        ],
                      )
                    : _buildCheckInForm(),
              ),
            ],
          ),
        )
        .animate()
        .fadeIn(duration: 350.ms, curve: Curves.easeOut)
        .slideY(begin: 0.05, end: 0, duration: 350.ms);
  }

  // The three quick actions surfaced in the persistent panel during an
  // active meetup: escalate to full SOS, ring the national emergency
  // number, or nudge trusted contacts without a full alert.
  Widget _buildMeetupAlertActions() {
    return Column(
      children: [
        Center(
          child: SizedBox(
            width: 190,
            height: 190,
            child: Stack(
              alignment: Alignment.center,
              children: [
                ..._buildRadarRings(),
                ScalePressable(
                      onTap: _startSos,
                      child: Container(
                        width: 130,
                        height: 130,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _red,
                          boxShadow: [
                            BoxShadow(
                              color: _red.withValues(alpha: 0.4),
                              blurRadius: 16,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                LucideIcons.shieldAlert,
                                color: Colors.white,
                                size: 36,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'ACTIVATE',
                                style: GoogleFonts.manrope(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                  letterSpacing: 1,
                                ),
                              ),
                              Text(
                                'SOS',
                                style: GoogleFonts.manrope(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                  letterSpacing: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                    .animate(
                      onPlay: (controller) => controller.repeat(reverse: true),
                    )
                    .scale(
                      begin: const Offset(0.96, 0.96),
                      end: const Offset(1.04, 1.04),
                      duration: 1500.ms,
                      curve: Curves.easeInOut,
                    ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _buildMeetupActionTile(
                icon: LucideIcons.phoneCall,
                label: 'Call 112',
                color: _accent,
                onTap: () => _launchUrlHelper('tel:112'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMeetupActionTile(
                icon: LucideIcons.users,
                label: 'Inform Contacts',
                color: _teal,
                onTap: _informTrustedContacts,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMeetupActionTile({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ScalePressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 6),
            Text(
              label,
              style: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Slow radar pings that ripple outward from the SOS button, signaling
  // "actively watching" without feeling alarming.
  List<Widget> _buildRadarRings() {
    return List.generate(3, (i) {
      return Container(
            width: 130,
            height: 130,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: _red.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
          )
          .animate(onPlay: (c) => c.repeat(), delay: (i * 700).ms)
          .scale(
            begin: const Offset(1, 1),
            end: const Offset(1.45, 1.45),
            duration: 2100.ms,
            curve: Curves.easeOut,
          )
          .fadeOut(duration: 2100.ms, curve: Curves.easeOut);
    });
  }

  // --- SOS Countdown Overlay ---
  Widget _buildSosOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      width: double.infinity,
      height: double.infinity,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: _red, width: 4),
                    color: _red.withValues(alpha: 0.1),
                  ),
                  child: Center(
                    child: Text(
                      '$_sosCountdown',
                      style: GoogleFonts.manrope(
                        fontSize: 80,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                )
                .animate(onPlay: (c) => c.repeat())
                .scale(
                  begin: const Offset(0.9, 0.9),
                  end: const Offset(1.1, 1.1),
                  duration: 500.ms,
                  curve: Curves.easeInOut,
                )
                .shake(duration: 500.ms, hz: 3),
            const SizedBox(height: 32),
            Text(
              'ACTIVATING SOS ALERT',
              style: GoogleFonts.manrope(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Text(
                'An emergency notification is about to be sent to your trusted contacts.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: const Color(0xFF94A3B8),
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(height: 48),
            ScalePressable(
              onTap: _cancelSos,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Text(
                  'CANCEL SOS',
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: _red,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckInForm() {
    final durationOptions = <Duration>[
      const Duration(minutes: 30),
      const Duration(hours: 1),
      const Duration(hours: 2),
      const Duration(hours: 3),
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
            color: const Color(0xFF94A3B8),
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
              color: const Color(0xFFCBD5E1),
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
          'CHECK IN AFTER',
          style: GoogleFonts.manrope(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF94A3B8),
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: durationOptions.map((d) {
            final selected = d == _checkInSelectedDuration;
            final label = d.inMinutes < 60
                ? '${d.inMinutes}m'
                : '${d.inHours}h';
            return ScalePressable(
              onTap: () => setState(() => _checkInSelectedDuration = d),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: selected ? _accent : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(20),
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
          }).toList(),
        ),
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

  Widget _buildCheckInActiveCard() {
    final total = _checkInStartedDuration.inSeconds == 0
        ? 1
        : _checkInStartedDuration.inSeconds;
    final remainingFraction = (_checkInRemaining.inSeconds / total).clamp(
      0.0,
      1.0,
    );
    final h = _checkInRemaining.inHours;
    final m = _checkInRemaining.inMinutes.remainder(60);
    final s = _checkInRemaining.inSeconds.remainder(60);
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
                      _checkInLabel,
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
                      'until we check on you',
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
          onTap: _checkInSafely,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(
              color: _teal,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    LucideIcons.checkCheck,
                    size: 16,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "I'm Safe — Check In Now",
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
        const SizedBox(height: 10),
        ScalePressable(
          onTap: () => _extendCheckIn(const Duration(minutes: 30)),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
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
                'Add up to 3 trusted contacts who should receive simulated location updates when the SOS trigger fires.',
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
                          color: const Color(0xFF94A3B8),
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
