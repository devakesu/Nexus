import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/screens/home/tabs/profile/widgets/futuristic_background_painter.dart';
import 'package:nexus/services/meetup_safety_session.dart';
import 'package:nexus/services/safety_contacts.dart';
import 'package:nexus/widgets/scale_pressable.dart';

/// Full-screen, animated Meetup Safety check-in alert. Pushed by
/// [MeetupSafetySession] whenever a check-in comes due — whether the app was
/// already open, the user tapped the check-in notification, or (on Android)
/// the notification's full-screen intent launched the app directly over the
/// lock screen.
///
/// No back-dismiss: the only ways off this screen are "I'm Safe" (resolves
/// the check-in) or "Turn off Meetup Safety" (ends the session).
class CheckInAlertScreen extends StatefulWidget {
  const CheckInAlertScreen({super.key});

  @override
  State<CheckInAlertScreen> createState() => _CheckInAlertScreenState();
}

class _CheckInAlertScreenState extends State<CheckInAlertScreen> {
  static const _accent = Color(0xFF0284C7);
  static const _teal = Color(0xFF0D9488);
  static const _red = Color(0xFFEF4444);

  bool _sosActive = false;
  int _sosCountdown = 5;
  Timer? _sosTimer;
  List<SafetyContact> _contacts = [];

  @override
  void initState() {
    super.initState();
    unawaited(_loadContacts());
  }

  @override
  void dispose() {
    _sosTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    final contacts = await loadSafetyContacts();
    if (mounted) setState(() => _contacts = contacts);
  }

  Future<void> _imSafe() async {
    await MeetupSafetySession.instance.checkInSafely();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _turnOffMeetupSafety() async {
    await MeetupSafetySession.instance.end();
    if (mounted) Navigator.of(context).pop();
  }

  void _startSos() {
    setState(() {
      _sosActive = true;
      _sosCountdown = 5;
    });
    _sosTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_sosCountdown > 1) {
        setState(() => _sosCountdown--);
      } else {
        _sosTimer?.cancel();
        unawaited(_triggerSosAlert());
      }
    });
  }

  void _cancelSos() {
    _sosTimer?.cancel();
    setState(() => _sosActive = false);
  }

  Future<void> _triggerSosAlert() async {
    setState(() => _sosActive = false);
    await showMockSosAlertDialog(context, contacts: _contacts);
  }

  @override
  Widget build(BuildContext context) {
    final session = MeetupSafetySession.instance;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0B0F1A),
        body: Stack(
          children: [
            const Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: FuturisticBackgroundPainter(accentColor: _accent),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                child: Column(
                  children: [
                    _buildHeader(session.checkInLabel),
                    const Spacer(),
                    _buildImSafeButton(),
                    const SizedBox(height: 28),
                    _buildSosButton(),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: _buildSecondaryTile(
                            icon: LucideIcons.phoneCall,
                            label: 'Call 112',
                            onTap: () => launchSafetyTel(context, 'tel:112'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildSecondaryTile(
                            icon: LucideIcons.users,
                            label: 'Inform Contacts',
                            onTap: () =>
                                showMockInformContactsToast(context, _contacts),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _turnOffMeetupSafety,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white38,
                      ),
                      child: Text(
                        'Turn off Meetup Safety',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_sosActive) _buildSosOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(String label) {
    return Column(
      children: [
        const Icon(LucideIcons.shieldAlert, color: _accent, size: 40)
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .scale(
              begin: const Offset(0.9, 0.9),
              end: const Offset(1.12, 1.12),
              duration: 1200.ms,
              curve: Curves.easeInOut,
            ),
        const SizedBox(height: 16),
        Text(
          'TIME TO CHECK IN',
          style: GoogleFonts.manrope(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 20,
            letterSpacing: 1.5,
          ),
        ),
        if (label.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: Colors.white60,
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ],
      ],
    ).animate().fadeIn(duration: 350.ms);
  }

  Widget _buildImSafeButton() {
    return ScalePressable(
          onTap: _imSafe,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: _teal,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: _teal.withValues(alpha: 0.4),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    LucideIcons.checkCheck,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    "I'm Safe",
                    style: GoogleFonts.manrope(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        )
        .animate()
        .fadeIn(delay: 150.ms, duration: 350.ms)
        .slideY(begin: 0.08, end: 0);
  }

  Widget _buildSosButton() {
    return SizedBox(
      width: 150,
      height: 150,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ..._buildRadarRings(),
          ScalePressable(
                onTap: _startSos,
                child: Container(
                  width: 104,
                  height: 104,
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
                          size: 26,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'SOS',
                          style: GoogleFonts.manrope(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .scale(
                begin: const Offset(0.97, 0.97),
                end: const Offset(1.03, 1.03),
                duration: 1300.ms,
                curve: Curves.easeInOut,
              ),
        ],
      ),
    ).animate().fadeIn(delay: 250.ms, duration: 350.ms);
  }

  List<Widget> _buildRadarRings() {
    return List.generate(3, (i) {
      return Container(
            width: 104,
            height: 104,
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
            end: const Offset(1.4, 1.4),
            duration: 2000.ms,
            curve: Curves.easeOut,
          )
          .fadeOut(duration: 2000.ms, curve: Curves.easeOut);
    });
  }

  Widget _buildSecondaryTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ScalePressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white70, size: 20),
            const SizedBox(height: 6),
            Text(
              label,
              style: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 300.ms, duration: 350.ms);
  }

  Widget _buildSosOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.9),
      width: double.infinity,
      height: double.infinity,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: _red, width: 4),
                    color: _red.withValues(alpha: 0.1),
                  ),
                  child: Center(
                    child: Text(
                      '$_sosCountdown',
                      style: GoogleFonts.manrope(
                        fontSize: 72,
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
            const SizedBox(height: 28),
            Text(
              'ACTIVATING SOS ALERT',
              style: GoogleFonts.manrope(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 40),
            ScalePressable(
              onTap: _cancelSos,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 36,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text(
                  'CANCEL SOS',
                  style: GoogleFonts.manrope(
                    fontSize: 14,
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
}
