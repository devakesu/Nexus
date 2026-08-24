import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/core/widgets/aesthetic_loaders.dart';
import 'package:nexus/core/widgets/nexus_toast.dart';
import 'package:nexus/core/widgets/scale_pressable.dart';
import 'package:nexus/features/profile/widgets/futuristic_background_painter.dart';
import 'package:nexus/features/security_signal/services/digital_witness_recorder.dart';
import 'package:nexus/features/security_signal/services/meetup_safety_session.dart';
import 'package:nexus/features/security_signal/services/safety_alert_api.dart';
import 'package:nexus/features/security_signal/services/safety_contacts.dart';
import 'package:nexus/features/security_signal/services/safety_dialer.dart';
import 'package:nexus/features/security_signal/services/security_service.dart';

enum _SosPhase { idle, countdown, silentActive, loudActive }

/// Full-screen, animated Meetup Safety check-in alert. Pushed by
/// [MeetupSafetySession] whenever a check-in comes due - whether the app was
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
  static const Color _accent = AppColors.safetyBlue;
  static const Color _teal = AppColors.safetyTeal;
  static const Color _red = AppColors.error;

  _SosPhase _phase = _SosPhase.idle;
  bool _pendingSilent = false;
  int _sosCountdown = 5;
  Timer? _sosTimer;
  List<SafetyContact> _contacts = [];
  AudioPlayer? _alarmPlayer;
  String? _lastAlertId;
  bool _alertSent = false;

  @override
  void initState() {
    super.initState();
    unawaited(SecurityService.enterSensitiveScreen());
    unawaited(_loadContacts());
  }

  @override
  void dispose() {
    unawaited(SecurityService.exitSensitiveScreen());
    _sosTimer?.cancel();
    unawaited(_alarmPlayer?.dispose());
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
    await _stopSos();
    await MeetupSafetySession.instance.end();
    if (mounted) Navigator.of(context).pop();
  }

  // --- SOS: countdown, then split into Silent / Loud ---

  void _startSosCountdown({required bool silent}) {
    setState(() {
      _phase = _SosPhase.countdown;
      _pendingSilent = silent;
      _sosCountdown = 5;
    });
    _sosTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_sosCountdown > 1) {
        setState(() => _sosCountdown--);
      } else {
        _sosTimer?.cancel();
        unawaited(_activateSos());
      }
    });
  }

  void _cancelSosCountdown() {
    _sosTimer?.cancel();
    setState(() => _phase = _SosPhase.idle);
  }

  Future<Position?> _tryGetLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      return await Geolocator.getCurrentPosition();
    } on Exception {
      return null;
    }
  }

  Future<void> _activateSos() async {
    final silent = _pendingSilent;
    final session = MeetupSafetySession.instance;
    SafetyAlertResult? result;

    try {
      final position = await _tryGetLocation();
      result = await SafetyAlertApi.sendAlert(
        alertType: silent ? 'sos_silent' : 'sos_loud',
        sessionId: session.serverSessionId,
        sessionLabel: session.checkInLabel,
        latitude: position?.latitude,
        longitude: position?.longitude,
      );
      _lastAlertId = result?.alertId;
      _alertSent = (result != null);
    } on Object catch (_) {
      _lastAlertId = null;
      _alertSent = false;
      if (mounted) {
        NexusToast.show(
          context,
          'SOS alert failed to send over network, starting local safety protocols.',
          type: NexusToastType.error,
        );
      }
    }

    if (!mounted) return;

    if (result == null && _lastAlertId == null) {
      _alertSent = false;
      NexusToast.show(
        context,
        'SOS alert failed to send over network, starting local safety protocols.',
        type: NexusToastType.error,
      );
    }

    if (silent) {
      setState(() => _phase = _SosPhase.silentActive);
      await _attemptRecording();
    } else {
      setState(() => _phase = _SosPhase.loudActive);
      try {
        await _startAlarm();
      } on Object catch (_) {
        // Non-fatal, alarm failed to start
      }
    }
  }

  /// Attempts to start Digital Witness recording, offering an explicit
  /// "Retry Recording" action (rather than auto-retrying silently, since a
  /// denied camera/mic permission needs the user to act, not just another
  /// attempt) if it fails. Re-invoked directly from that retry button.
  Future<void> _attemptRecording() async {
    try {
      final started = await DigitalWitnessRecorder.instance.start(
        alertId: _lastAlertId,
      );
      if (!started && mounted) {
        // Camera/mic unavailable or denied - fall back to the mock confirmation
        // so the screen doesn't just sit there looking broken.
        await showSosFallbackDialog(
          context,
          contacts: _contacts,
          onRetryRecording: _attemptRecording,
        );
        if (mounted) setState(() => _phase = _SosPhase.idle);
      }
    } on Object catch (_) {
      if (mounted) {
        await showSosFallbackDialog(
          context,
          contacts: _contacts,
          onRetryRecording: _attemptRecording,
        );
        setState(() => _phase = _SosPhase.idle);
      }
    }
  }

  Future<void> _startAlarm() async {
    final player = AudioPlayer();
    _alarmPlayer = player;
    try {
      await player.setAsset('assets/sounds/emergency_alarm.wav');
      await player.setLoopMode(LoopMode.all);
      await player.setVolume(1);
      await player.play();
    } on Exception {
      // Non-fatal - the SMS alert already went out even if the alarm sound
      // fails to load/play.
    }
  }

  Future<void> _stopAlarm() async {
    final player = _alarmPlayer;
    _alarmPlayer = null;
    if (player != null) {
      await player.stop();
      await player.dispose();
    }
  }

  /// Stops everything (alarm and/or recording) without calling anyone.
  Future<void> _stopSos() async {
    await _stopAlarm();
    if (DigitalWitnessRecorder.instance.isRecording) {
      await DigitalWitnessRecorder.instance.stop();
    }
    if (mounted) setState(() => _phase = _SosPhase.idle);
  }

  /// Loud SOS's "Call 112": the alarm and a live call can't sensibly run at
  /// once, so this stops the alarm first, then places the call.
  Future<void> _callFromLoudAlarm() async {
    await _stopAlarm();
    if (mounted) setState(() => _phase = _SosPhase.idle);
    if (mounted) await callEmergencyNumber(context, '112');
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
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: _buildSosModeButton(
                            label: 'Silent SOS',
                            icon: LucideIcons.video,
                            filled: false,
                            onTap: () => _startSosCountdown(silent: true),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildSosModeButton(
                            label: 'Loud SOS',
                            icon: LucideIcons.siren,
                            filled: true,
                            onTap: () => _startSosCountdown(silent: false),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: _buildSecondaryTile(
                            icon: LucideIcons.phoneCall,
                            label: 'Call 112',
                            onTap: () => callEmergencyNumber(context, '112'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildSecondaryTile(
                            icon: LucideIcons.users,
                            label: 'Inform Contacts',
                            onTap: _informContacts,
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
            if (_phase == _SosPhase.countdown) _buildCountdownOverlay(),
            if (_phase == _SosPhase.silentActive)
              _buildSilentRecordingOverlay(),
            if (_phase == _SosPhase.loudActive) _buildLoudAlarmOverlay(),
          ],
        ),
      ),
    );
  }

  void _informContacts() {
    unawaited(
      SafetyAlertApi.sendAlert(
        alertType: 'inform',
        sessionId: MeetupSafetySession.instance.serverSessionId,
        sessionLabel: MeetupSafetySession.instance.checkInLabel,
      ),
    );
    showInformContactsToast(context, _contacts);
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

  Widget _buildSosModeButton({
    required String label,
    required IconData icon,
    required bool filled,
    required VoidCallback onTap,
  }) {
    return ScalePressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: filled ? _red : _red.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: filled ? _red : _red.withValues(alpha: 0.4),
            width: filled ? 0 : 1.5,
          ),
          boxShadow: filled
              ? [
                  BoxShadow(
                    color: _red.withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            Icon(icon, color: filled ? Colors.white : _red, size: 22),
            const SizedBox(height: 6),
            Text(
              label,
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: filled ? Colors.white : _red,
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 250.ms, duration: 350.ms);
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

  List<Widget> _buildRadarRings(Color color, double size) {
    return List.generate(3, (i) {
      return Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: color.withValues(alpha: 0.3),
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

  Widget _buildCountdownOverlay() {
    final silent = _pendingSilent;
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
              silent ? 'ACTIVATING SILENT SOS' : 'ACTIVATING LOUD SOS',
              style: GoogleFonts.manrope(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 40),
            ScalePressable(
              onTap: _cancelSosCountdown,
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

  // Silent SOS's "Digital Witness" viewfinder - an explicit, visible
  // recording, never covert. See DigitalWitnessRecorder's doc comment.
  Widget _buildSilentRecordingOverlay() {
    return Container(
      color: const Color(0xFF0B0F1A),
      width: double.infinity,
      height: double.infinity,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: _red,
                          shape: BoxShape.circle,
                        ),
                      )
                      .animate(onPlay: (c) => c.repeat(reverse: true))
                      .fadeOut(duration: 600.ms, curve: Curves.easeInOut),
                  const SizedBox(width: 8),
                  Text(
                    'RECORDING EVIDENCE',
                    style: GoogleFonts.manrope(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: AnimatedBuilder(
                    animation: DigitalWitnessRecorder.instance,
                    builder: (context, _) {
                      final controller =
                          DigitalWitnessRecorder.instance.controller;
                      if (controller == null ||
                          !controller.value.isInitialized) {
                        return const ColoredBox(
                          color: Color(0xFF141822),
                          child: Center(
                            child: NexusOrbitLoader(size: 60),
                          ),
                        );
                      }
                      return CameraPreview(controller);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _alertSent
                    ? 'Recording video and audio as evidence, in the open - this '
                          'is visible on your screen the whole time, never hidden. '
                          'Trusted contacts have been notified.'
                    : 'Recording video and audio as evidence. ALERT SENDING FAILED - '
                          'trusted contacts have not been notified. Please call 112 directly.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: _alertSent ? Colors.white60 : _red,
                  fontSize: 12.5,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 20),
              ScalePressable(
                onTap: _stopSos,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Center(
                    child: Text(
                      'Stop SOS',
                      style: GoogleFonts.manrope(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoudAlarmOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.92),
      width: double.infinity,
      height: double.infinity,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 180,
              height: 180,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  ..._buildRadarRings(_red, 130),
                  Container(
                        width: 130,
                        height: 130,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _red,
                          boxShadow: [
                            BoxShadow(
                              color: _red.withValues(alpha: 0.5),
                              blurRadius: 24,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: const Icon(
                          LucideIcons.siren,
                          color: Colors.white,
                          size: 48,
                        ),
                      )
                      .animate(onPlay: (c) => c.repeat(reverse: true))
                      .scale(
                        begin: const Offset(0.95, 0.95),
                        end: const Offset(1.08, 1.08),
                        duration: 600.ms,
                        curve: Curves.easeInOut,
                      ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'LOUD SOS ACTIVE',
              style: GoogleFonts.manrope(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                _alertSent
                    ? 'Alarm sounding at full volume. Trusted contacts have been notified.'
                    : 'Alarm sounding at full volume. ALERT SENDING FAILED - '
                          'trusted contacts have not been notified. Please call 112 directly.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: _alertSent ? Colors.white60 : _red,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 40),
            ScalePressable(
              onTap: _callFromLoudAlarm,
              child: Container(
                width: 240,
                padding: const EdgeInsets.symmetric(vertical: 15),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Center(
                  child: Text(
                    'STOP ALARM & CALL 112',
                    style: GoogleFonts.manrope(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                      color: _red,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            ScalePressable(
              onTap: _stopSos,
              child: Container(
                width: 240,
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white38),
                ),
                child: Center(
                  child: Text(
                    'STOP SOS',
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Colors.white70,
                      letterSpacing: 1,
                    ),
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
