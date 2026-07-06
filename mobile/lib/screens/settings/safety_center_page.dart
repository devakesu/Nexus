import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/screens/settings/blocked_users_page.dart';
import 'package:nexus/screens/settings/hidden_users_page.dart';
import 'package:nexus/screens/settings/privacy_settings_page.dart';
import 'package:nexus/widgets/aesthetic_loaders.dart';
import 'package:nexus/widgets/nexus_toast.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

// Reusable scale pressable for satisfying physical click haptics
class ScalePressable extends StatefulWidget {
  const ScalePressable({
    required this.child,
    required this.onTap,
    this.enabled = true,
    super.key,
  });

  final Widget child;
  final VoidCallback onTap;
  final bool enabled;

  @override
  State<ScalePressable> createState() => _ScalePressableState();
}

class _ScalePressableState extends State<ScalePressable> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return InkWell(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      child: AnimatedScale(
        scale: _isPressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

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

class _ChecklistItem {
  _ChecklistItem({
    required this.label,
    required this.done,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final bool done;
  final IconData icon;
  final VoidCallback onTap;
}

class _SafetyScoreRingPainter extends CustomPainter {
  _SafetyScoreRingPainter({required this.progress});

  final double progress;

  static const _track = Color(0xFFE2E8F0);
  static const _teal = Color(0xFF0D9488);
  static const _accent = Color(0xFF0284C7);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;
    final trackPaint = Paint()
      ..color = _track
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);

    if (progress <= 0) return;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final progressPaint = Paint()
      ..shader = SweepGradient(
        colors: const [_accent, _teal, _accent],
        startAngle: -math.pi / 2,
        endAngle: -math.pi / 2 + math.pi * 2 * progress,
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _SafetyScoreRingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

typedef _RedFlagData = ({IconData icon, String title, String desc});

class _RedFlagCarousel extends StatefulWidget {
  const _RedFlagCarousel({required this.flags});

  final List<_RedFlagData> flags;

  @override
  State<_RedFlagCarousel> createState() => _RedFlagCarouselState();
}

class _RedFlagCarouselState extends State<_RedFlagCarousel> {
  late final PageController _controller = PageController(
    viewportFraction: 0.62,
  );
  double _page = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onPageChange);
  }

  void _onPageChange() {
    if (mounted) {
      final newPage = _controller.page ?? 0;
      if (newPage != _page) {
        setState(() => _page = newPage);
      }
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onPageChange)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 168,
          child: PageView.builder(
            controller: _controller,
            padEnds: false,
            itemCount: widget.flags.length,
            itemBuilder: (context, index) {
              final distance = (index - _page).abs().clamp(0.0, 1.0);
              final scale = 1 - (distance * 0.08);
              final flag = widget.flags[index];
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Transform.scale(
                  scale: scale,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF9F9),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFFEE2E2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(9),
                          decoration: const BoxDecoration(
                            color: Color(0xFFFEE2E2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            flag.icon,
                            color: const Color(0xFFEF4444),
                            size: 18,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          flag.title,
                          style: GoogleFonts.manrope(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Expanded(
                          child: Text(
                            flag.desc,
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              color: const Color(0xFF64748B),
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.only(right: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.flags.length, (i) {
              final active = (_page.round() == i);
              return AnimatedContainer(
                duration: 250.ms,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: active ? 16 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: active
                      ? const Color(0xFFEF4444)
                      : const Color(0xFFFECACA),
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

class SafetyCenterPage extends StatefulWidget {
  const SafetyCenterPage({
    this.initialCheckInLabel,
    this.initialCheckInDuration,
    super.key,
  });

  /// Pre-fills the Date Check-In form and scrolls to it on open - used by
  /// a chat event card's "Set up a safety check-in" shortcut so the user
  /// doesn't have to retype a plan they already made in chat.
  final String? initialCheckInLabel;
  final Duration? initialCheckInDuration;

  @override
  State<SafetyCenterPage> createState() => _SafetyCenterPageState();
}

class _SafetyCenterPageState extends State<SafetyCenterPage> {
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

  // Quiz state variables
  int _quizIndex = 0; // 0: Start, 1: Q1, 2: Q2, 3: Q3, 4: Result
  int _score = 0;
  int _selectedAnswerIndex = -1;
  bool _answered = false;

  // Safety Score checklist state (persisted across sessions)
  bool _quizCompletedOnce = false;
  bool _guidelinesReviewed = false;
  bool _privacySettingsReviewed = false;

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

  // Section anchors for scroll-to-section navigation from the safety score card
  final GlobalKey _contactsKey = GlobalKey();
  final GlobalKey _checkInKey = GlobalKey();
  final GlobalKey _quizKey = GlobalKey();
  final GlobalKey _guidelinesKey = GlobalKey();

  // One controller per guideline accordion so a "Next" button can collapse
  // the current tile and expand the next one in sequence.
  final List<ExpansibleController> _accordionControllers = List.generate(
    4,
    (_) => ExpansibleController(),
  );

  double get _safetyScore {
    var completed = 0;
    if (_contacts.isNotEmpty) completed++;
    if (_quizCompletedOnce) completed++;
    if (_guidelinesReviewed) completed++;
    if (_privacySettingsReviewed) completed++;
    return completed / 4;
  }

  final List<Map<String, dynamic>> _quizQuestions = [
    {
      'question':
          'A match asks you to send them money for an emergency before you meet. What is the safest course of action?',
      'options': [
        'Send a small amount if they offer proof.',
        'Refuse the request and immediately report their profile.',
        'Offer to buy them a gift card instead.',
      ],
      'correct': 1,
      'explanation':
          'Never send money, share financial details, or invest in opportunities suggested by someone you met online. Genuine users will not ask you for money.',
    },
    {
      'question':
          'When planning a first meeting, which location is the safest choice?',
      'options': [
        'A quiet, private spot where you can chat without distractions.',
        'Their home or hotel room, as it is cozy and personal.',
        'A busy public space like a coffee shop, café, or restaurant.',
      ],
      'correct': 2,
      'explanation':
          'Always meet in public for the first few times. Do not go back to their home or private spaces until you know them well.',
    },
    {
      'question':
          'Your match offers to pick you up at your house for your first date. How should you respond?',
      'options': [
        'Decline and arrange your own transportation to and from the venue.',
        'Accept the ride, but text their license plate to a friend.',
        'Accept the ride to keep things convenient.',
      ],
      'correct': 0,
      'explanation':
          'Always stay in control of your transportation. Drive yourself, take public transit, or use a rideshare service so you can leave whenever you feel uncomfortable.',
    },
  ];

  @override
  void initState() {
    super.initState();
    unawaited(_loadContacts());
    unawaited(_loadChecklistFlags());

    final initialLabel = widget.initialCheckInLabel;
    if (initialLabel != null) {
      _checkInLabelController.text = initialLabel;
    }
    if (widget.initialCheckInDuration != null) {
      _checkInSelectedDuration = widget.initialCheckInDuration!;
    }
    if (initialLabel != null || widget.initialCheckInDuration != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollToKey(_checkInKey),
      );
    }
  }

  @override
  void dispose() {
    _sosTimer?.cancel();
    _checkInTimer?.cancel();
    _checkInLabelController.dispose();
    super.dispose();
  }

  // --- Safety Score checklist persistence ---
  Future<void> _loadChecklistFlags() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _quizCompletedOnce = prefs.getBool('safety_quiz_completed') ?? false;
      _guidelinesReviewed =
          prefs.getBool('safety_guidelines_reviewed') ?? false;
      _privacySettingsReviewed =
          prefs.getBool('safety_privacy_reviewed') ?? false;
    });
  }

  Future<void> _markQuizCompleted() async {
    if (_quizCompletedOnce) return;
    setState(() => _quizCompletedOnce = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('safety_quiz_completed', true);
  }

  Future<void> _markGuidelinesReviewed() async {
    if (_guidelinesReviewed) return;
    setState(() => _guidelinesReviewed = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('safety_guidelines_reviewed', true);
  }

  Future<void> _markPrivacySettingsReviewed() async {
    if (_privacySettingsReviewed) return;
    setState(() => _privacySettingsReviewed = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('safety_privacy_reviewed', true);
  }

  void _scrollToKey(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx != null) {
      unawaited(
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
          alignment: 0.08,
        ),
      );
    } else {
      // The section may not have been laid out yet on this frame; retry
      // once its RenderObject exists.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final retryCtx = key.currentContext;
        if (retryCtx != null) {
          unawaited(
            Scrollable.ensureVisible(
              retryCtx,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOut,
              alignment: 0.08,
            ),
          );
        }
      });
    }
  }

  void _openPrivacySettings() {
    unawaited(
      Navigator.of(context)
          .push(
            MaterialPageRoute<void>(
              builder: (_) => const PrivacySettingsPage(),
            ),
          )
          .then((_) => _markPrivacySettingsReviewed()),
    );
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
      setState(() {
        _contacts = loaded;
        _loadingContacts = false;
      });
    } on Exception catch (_) {
      setState(() => _loadingContacts = false);
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

  void _showAddContactDialog() {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    unawaited(
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Add Trusted Contact',
            style: GoogleFonts.manrope(fontWeight: FontWeight.w800),
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: 'Full Name',
                    labelStyle: GoogleFonts.inter(fontSize: 14),
                    prefixIcon: const Icon(LucideIcons.user, size: 18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Phone Number',
                    labelStyle: GoogleFonts.inter(fontSize: 14),
                    prefixIcon: const Icon(LucideIcons.phone, size: 18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a phone number';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                'Cancel',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF64748B),
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  _addContact(
                    nameController.text.trim(),
                    phoneController.text.trim(),
                  );
                  Navigator.of(ctx).pop();
                }
              },
              child: Text(
                'Save',
                style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
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

  // --- Quiz Answers Selection ---
  void _submitAnswer(int answerIndex, int correctIndex) {
    if (_answered) return;
    setState(() {
      _selectedAnswerIndex = answerIndex;
      _answered = true;
      if (answerIndex == correctIndex) {
        _score++;
      }
    });
  }

  void _nextQuizStep() {
    setState(() {
      _quizIndex++;
      _selectedAnswerIndex = -1;
      _answered = false;
    });
    if (_quizIndex > _quizQuestions.length) {
      unawaited(_markQuizCompleted());
    }
  }

  void _resetQuiz() {
    setState(() {
      _quizIndex = 0;
      _score = 0;
      _selectedAnswerIndex = -1;
      _answered = false;
    });
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
            // Large cache extent so every section is laid out up front —
            // otherwise the Sliver viewport only builds content near the
            // current scroll position and GlobalKey-based "scroll to
            // section" taps on far-below-the-fold items silently no-op.
            scrollCacheExtent: const ScrollCacheExtent.pixels(20000),
            children: [
              _buildSafetyHeroBanner(),
              _buildSafetyScoreSection(),
              _buildSosToolkitSection(),
              KeyedSubtree(key: _checkInKey, child: _buildDateCheckInSection()),
              KeyedSubtree(
                key: _contactsKey,
                child: _buildEmergencyContactsSection(),
              ),
              _buildHelplinesSection(),
              KeyedSubtree(
                key: _guidelinesKey,
                child: _buildSafetyEducationSection(),
              ),
              _buildVerifiedProtectedSection(),
              KeyedSubtree(
                key: _quizKey,
                child: _buildInteractiveQuizSection(),
              ),
              _buildShortcutsSection(),
              _buildFooterNote(),
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
            'Safety Center',
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

  // --- Calming Hero Banner ---
  Widget _buildSafetyHeroBanner() {
    return Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Colors.white, Color(0xFFECFDF5)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFD1FAE5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your Safety Matters',
                      style: GoogleFonts.manrope(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Access resources, configure emergency triggers, and learn guidelines to protect yourself online and offline.',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: const Color(0xFF475569),
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 76,
                height: 76,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    ..._buildBreathingRings(),
                    Container(
                          padding: const EdgeInsets.all(12),
                          decoration: const BoxDecoration(
                            color: Color(0xFFCCFBF1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            LucideIcons.shieldCheck,
                            color: _teal,
                            size: 32,
                          ),
                        )
                        .animate(onPlay: (c) => c.repeat(reverse: true))
                        .scale(
                          begin: const Offset(0.92, 0.92),
                          end: const Offset(1.08, 1.08),
                          duration: 2500.ms,
                          curve: Curves.easeInOut,
                        ),
                  ],
                ),
              ),
            ],
          ),
        )
        .animate()
        .fadeIn(duration: 350.ms, curve: Curves.easeOut)
        .slideY(begin: 0.05, end: 0, duration: 350.ms);
  }

  // Calming "breathing" halo rings that softly expand and fade behind the
  // hero shield icon, giving the whole header a slow, reassuring pulse.
  List<Widget> _buildBreathingRings() {
    return List.generate(2, (i) {
      return Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: _teal.withValues(alpha: 0.35),
                width: 1.5,
              ),
            ),
          )
          .animate(
            onPlay: (c) => c.repeat(),
            delay: (i * 900).ms,
          )
          .scale(
            begin: const Offset(0.55, 0.55),
            end: const Offset(1.35, 1.35),
            duration: 2600.ms,
            curve: Curves.easeOut,
          )
          .fadeOut(duration: 2600.ms, curve: Curves.easeOut);
    });
  }

  // --- Safety Score Section ---
  Widget _buildSafetyScoreSection() {
    final score = _safetyScore;
    final percent = (score * 100).round();
    final checklist = <_ChecklistItem>[
      _ChecklistItem(
        label: 'Add a trusted contact',
        done: _contacts.isNotEmpty,
        icon: LucideIcons.users,
        onTap: () => _scrollToKey(_contactsKey),
      ),
      _ChecklistItem(
        label: 'Review privacy settings',
        done: _privacySettingsReviewed,
        icon: LucideIcons.shield,
        onTap: _openPrivacySettings,
      ),
      _ChecklistItem(
        label: 'Take the safety quiz',
        done: _quizCompletedOnce,
        icon: LucideIcons.sparkle,
        onTap: () => _scrollToKey(_quizKey),
      ),
      _ChecklistItem(
        label: 'Review safety guidelines',
        done: _guidelinesReviewed,
        icon: LucideIcons.bookOpen,
        onTap: () => _scrollToKey(_guidelinesKey),
      ),
    ];

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
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: score),
                    duration: 800.ms,
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) {
                      return CustomPaint(
                        size: const Size(64, 64),
                        painter: _SafetyScoreRingPainter(progress: value),
                        child: SizedBox(
                          width: 64,
                          height: 64,
                          child: Center(
                            child: Text(
                              '$percent%',
                              style: GoogleFonts.manrope(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your Safety Setup',
                          style: GoogleFonts.manrope(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          percent == 100
                              ? "You've completed every safety step. Nicely done."
                              : 'Complete these quick steps to feel even safer on Nexus.',
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            color: const Color(0xFF64748B),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              ...checklist.map((item) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ScalePressable(
                    onTap: item.onTap,
                    child: Row(
                      children: [
                        AnimatedContainer(
                          duration: 300.ms,
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: item.done
                                ? _teal.withValues(alpha: 0.12)
                                : const Color(0xFFF1F5F9),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            item.done ? LucideIcons.checkCheck : item.icon,
                            size: 14,
                            color: item.done ? _teal : const Color(0xFF94A3B8),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            item.label,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: item.done
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF334155),
                              decoration: item.done
                                  ? TextDecoration.lineThrough
                                  : null,
                              decorationColor: const Color(0xFF94A3B8),
                            ),
                          ),
                        ),
                        const Icon(
                          LucideIcons.chevronRight,
                          size: 14,
                          color: Color(0xFFCBD5E1),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        )
        .animate()
        .fadeIn(delay: 30.ms, duration: 350.ms)
        .slideY(begin: 0.05, end: 0, duration: 350.ms);
  }

  // --- Meetup Safety Alert Section ---
  // Explains the persistent alert panel that stays available for the
  // duration of an active Date Check-In (i.e. an in-person meetup).
  Widget _buildSosToolkitSection() {
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
                              .fadeOut(duration: 700.ms, curve: Curves.easeInOut),
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
                    : 'Start a Date Check-In before you head out. While a check-in is active, a persistent alert panel stays on your device for the whole meetup — with SOS, Call 112, and Inform Trusted Contacts always one tap away.',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: const Color(0xFF64748B),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 20),
              if (_checkInActive)
                _buildMeetupAlertActions()
              else
                ScalePressable(
                  onTap: () => _scrollToKey(_checkInKey),
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
                            LucideIcons.mapPin,
                            size: 15,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Start a Date Check-In',
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
          ),
        )
        .animate()
        .fadeIn(delay: 50.ms, duration: 350.ms)
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

  // --- Date Check-In Section ---
  Widget _buildDateCheckInSection() {
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
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F9FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      LucideIcons.mapPin,
                      color: _accent,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'DATE CHECK-IN',
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF475569),
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                "Heading out to meet someone? Set a timer before you go. If you don't check in as safe, we'll simulate an alert to your trusted contact.",
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: const Color(0xFF64748B),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 16),
              AnimatedSwitcher(
                duration: 300.ms,
                child: _checkInActive
                    ? _buildCheckInActiveCard()
                    : _buildCheckInForm(),
              ),
            ],
          ),
        )
        .animate()
        .fadeIn(delay: 60.ms, duration: 350.ms)
        .slideY(begin: 0.05, end: 0, duration: 350.ms);
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
        if (_contacts.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'ALERT CONTACT',
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
            children: List.generate(_contacts.length, (i) {
              final selected = (_checkInContactIndex ?? 0) == i;
              return ScalePressable(
                onTap: () => setState(() => _checkInContactIndex = i),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? _teal.withValues(alpha: 0.1)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected ? _teal : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Text(
                    _contacts[i].name,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: selected ? _teal : const Color(0xFF475569),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
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
                        painter: _SafetyScoreRingPainter(progress: value),
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
                      onTap: _showAddContactDialog,
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

  // --- Verified & Protected Section ---
  Widget _buildVerifiedProtectedSection() {
    final items = [
      (
        icon: LucideIcons.badgeCheck,
        title: 'Photo Verification',
        desc:
            'The blue check confirms a profile’s photos were matched to a live selfie.',
      ),
      (
        icon: LucideIcons.scanFace,
        title: 'Duplicate & Deepfake Scans',
        desc:
            'Automated scans flag stolen, AI-generated, or duplicated profile photos.',
      ),
      (
        icon: LucideIcons.userRoundCheck,
        title: 'Identity Assurance',
        desc: 'Age and identity checks help keep the community authentic.',
      ),
      (
        icon: LucideIcons.bot,
        title: 'AI Photo & Message Moderation',
        desc:
            'Automated systems scan for explicit content, spam, and scam patterns in real time.',
      ),
      (
        icon: LucideIcons.headphones,
        title: '24/7 Human Trust & Safety Team',
        desc:
            'Reports are reviewed around the clock by real people, every day of the year.',
      ),
      (
        icon: LucideIcons.lockKeyhole,
        title: 'Encrypted Sessions & Data',
        desc:
            'Your login session and personal data are encrypted at rest and in transit.',
      ),
      (
        icon: LucideIcons.ban,
        title: 'Instant Block, Report & Hide',
        desc:
            'One tap removes someone from your matches, requests, and search results — permanently.',
      ),
    ];

    return Container(
          margin: const EdgeInsets.fromLTRB(20, 10, 20, 10),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF0F172A),
                const Color(0xFF0F172A).withValues(alpha: 0.92),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      LucideIcons.badgeCheck,
                      color: Color(0xFF5EEAD4),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'VERIFIED & PROTECTED',
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.white70,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Everything working quietly in the background — from identity checks to 24/7 moderation — to keep Nexus genuine and safe.',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: Colors.white60,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 16),
              ...List.generate(items.length, (i) {
                final item = items[i];
                return Padding(
                      padding: EdgeInsets.only(
                        bottom: i == items.length - 1 ? 0 : 16,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            item.icon,
                            color: const Color(0xFF5EEAD4),
                            size: 18,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  item.desc,
                                  style: GoogleFonts.inter(
                                    fontSize: 11.5,
                                    color: Colors.white60,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )
                    .animate()
                    .fadeIn(delay: (120 + i * 60).ms, duration: 300.ms)
                    .slideX(begin: 0.03, end: 0);
              }),
            ],
          ),
        )
        .animate()
        .fadeIn(delay: 120.ms, duration: 350.ms)
        .slideY(begin: 0.05, end: 0, duration: 350.ms);
  }

  // --- Crisis Helplines Section ---
  Widget _buildHelplinesSection() {
    final helplines = [
      {
        'title': 'Women Helpline (Domestic Abuse)',
        'desc':
            'Toll-free, 24/7 government helpline for women facing abuse or violence.',
        'actionText': 'Call 181',
        'url': 'tel:181',
        'icon': LucideIcons.phone,
      },
      {
        'title': 'AASRA Suicide Prevention Helpline',
        'desc':
            '24/7 confidential support for anyone in emotional distress or crisis.',
        'actionText': 'Call +91 98204 66726',
        'url': 'tel:+919820466726',
        'icon': LucideIcons.phone,
      },
      {
        'title': 'iCall Psychosocial Helpline',
        'desc':
            'Free telephone and email counselling from trained mental health professionals.',
        'actionText': 'Call +91 91529 87821',
        'url': 'tel:+919152987821',
        'icon': LucideIcons.messageSquare,
      },
    ];

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
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      LucideIcons.phoneCall,
                      color: Color(0xFFEA580C),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'CRISIS HELPLINES',
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF475569),
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                "If you are in immediate physical danger, dial 112 (India's national emergency number) or contact your local police. For support services, reach out to these hotlines:",
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: const Color(0xFF64748B),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 16),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: helplines.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final h = helplines[index];
                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFF1F5F9)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          h['title']! as String,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          h['desc']! as String,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: const Color(0xFF64748B),
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ScalePressable(
                          onTap: () => _launchUrlHelper(h['url']! as String),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 14,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  h['icon']! as IconData,
                                  size: 14,
                                  color: _accent,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  h['actionText']! as String,
                                  style: GoogleFonts.manrope(
                                    fontSize: 12,
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
                  );
                },
              ),
            ],
          ),
        )
        .animate()
        .fadeIn(delay: 150.ms, duration: 350.ms)
        .slideY(begin: 0.05, end: 0, duration: 350.ms);
  }

  // --- Interactive Safety Quiz Section ---
  Widget _buildInteractiveQuizSection() {
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
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _quizIndex == 0
                ? _buildQuizStart()
                : _quizIndex <= _quizQuestions.length
                ? _buildQuizQuestion()
                : _buildQuizResult(),
          ),
        )
        .animate()
        .fadeIn(delay: 200.ms, duration: 350.ms)
        .slideY(begin: 0.05, end: 0, duration: 350.ms);
  }

  Widget _buildQuizStart() {
    return Column(
      key: const ValueKey('start'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                LucideIcons.sparkles,
                color: Colors.indigo,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'SAFETY CHALLENGE',
              style: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF475569),
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Test your safety knowledge with a short quiz and learn how to handle online interactions securely.',
          style: GoogleFonts.inter(
            fontSize: 13,
            color: const Color(0xFF64748B),
            height: 1.45,
          ),
        ),
        const SizedBox(height: 16),
        ScalePressable(
          onTap: () => setState(() => _quizIndex = 1),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                'Start Quiz',
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuizQuestion() {
    final questionData = _quizQuestions[_quizIndex - 1];
    final questionText = questionData['question']! as String;
    final options = questionData['options']! as List<String>;
    final correctIndex = questionData['correct']! as int;
    final explanation = questionData['explanation']! as String;

    return Column(
      key: ValueKey('q_$_quizIndex'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'QUESTION $_quizIndex OF ${_quizQuestions.length}',
              style: GoogleFonts.manrope(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: _accent,
                letterSpacing: 1,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Score: $_score',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF475569),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          questionText,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF0F172A),
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16),
        Column(
          children: List.generate(options.length, (optIdx) {
            final isSelected = _selectedAnswerIndex == optIdx;
            final isCorrect = optIdx == correctIndex;
            final showResults = _answered;

            var tileBgColor = const Color(0xFFF8FAFC);
            var borderColor = const Color(0xFFE2E8F0);
            Widget? trailing;

            if (showResults) {
              if (isCorrect) {
                tileBgColor = const Color(0xFFECFDF5);
                borderColor = _teal;
                trailing = const Icon(
                  LucideIcons.check,
                  color: _teal,
                  size: 16,
                );
              } else if (isSelected) {
                tileBgColor = const Color(0xFFFEF2F2);
                borderColor = _red;
                trailing = const Icon(
                  LucideIcons.alertCircle,
                  color: _red,
                  size: 16,
                );
              }
            } else {
              if (isSelected) {
                borderColor = _accent;
                tileBgColor = _accent.withValues(alpha: 0.05);
              }
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ScalePressable(
                enabled: !showResults,
                onTap: () => _submitAnswer(optIdx, correctIndex),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: tileBgColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: borderColor,
                      width: isSelected || (showResults && isCorrect) ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          options[optIdx],
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: isSelected || (showResults && isCorrect)
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: isSelected || (showResults && isCorrect)
                                ? const Color(0xFF0F172A)
                                : const Color(0xFF475569),
                          ),
                        ),
                      ),
                      if (trailing != null) ...[
                        const SizedBox(width: 8),
                        trailing,
                      ],
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
        if (_answered) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedAnswerIndex == correctIndex
                      ? 'CORRECT'
                      : 'INCORRECT',
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: _selectedAnswerIndex == correctIndex ? _teal : _red,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  explanation,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: const Color(0xFF64748B),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 250.ms),
          const SizedBox(height: 16),
          ScalePressable(
            onTap: _nextQuizStep,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  _quizIndex < _quizQuestions.length
                      ? 'Next Question'
                      : 'View Results',
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildQuizResult() {
    var rank = 'Dating Beginner';
    var message = 'Take time to read the guidelines below to stay safe!';
    var rankColor = _red;

    if (_score == 3) {
      rank = 'Safety Champion';
      message = 'Outstanding! You have a perfect safety instinct.';
      rankColor = _teal;
    } else if (_score == 2) {
      rank = 'Safety Savvy';
      message = 'Great job! You know the core concepts well.';
      rankColor = _accent;
    }

    return Column(
      key: const ValueKey('result'),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: rankColor.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(LucideIcons.shieldCheck, color: rankColor, size: 40),
        ),
        const SizedBox(height: 12),
        Text(
          'QUIZ COMPLETED',
          style: GoogleFonts.manrope(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: const Color(0xFF64748B),
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$_score / ${_quizQuestions.length} Correct',
          style: GoogleFonts.manrope(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: rankColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            rank.toUpperCase(),
            style: GoogleFonts.manrope(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: rankColor,
              letterSpacing: 1,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 13,
            color: const Color(0xFF475569),
            height: 1.4,
          ),
        ),
        const SizedBox(height: 20),
        ScalePressable(
          onTap: _resetQuiz,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Center(
              child: Text(
                'Retake Quiz',
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // --- Safety Education Section (Accordion) ---
  Widget _buildSafetyEducationSection() {
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
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(LucideIcons.bookOpen, color: _teal, size: 18),
              ),
              const SizedBox(width: 12),
              Text(
                'SAFETY GUIDELINES & EDUCATION',
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF475569),
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Equip yourself with guidelines built in partnership with trust and safety experts.',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: const Color(0xFF64748B),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          _buildEducationAccordion(
            controller: _accordionControllers[0],
            title: '1. Meeting Up Safely (Offline Safety)',
            icon: LucideIcons.mapPin,
            items: [
              'Meet in well-lit, public places. Never meet at a private residence for the first time.',
              'Tell a trusted friend or family member where you are going, who you are meeting, and share your live location.',
              'Arrange your own transportation. Avoid getting picked up by your date or letting them know exactly where you live initially.',
              'Stay in control of your drink and personal items at all times. Do not leave your drink unattended.',
            ],
            nextLabel: 'Next: Chatting Safely',
            onNext: () {
              _accordionControllers[0].collapse();
              _accordionControllers[1].expand();
            },
          ),
          const SizedBox(height: 10),
          _buildEducationAccordion(
            controller: _accordionControllers[1],
            title: '2. Chatting Safely (Online Safety)',
            icon: LucideIcons.messageSquare,
            items: [
              'Keep personal details private. Do not share your address, social security number, or workplace details early on.',
              'Watch out for suspicious profiles. Profiles with no linked accounts, only one photo, or very vague details may be catfishers.',
              'Stay on the platform. Avoid switching to WhatsApp, Telegram, or personal text messaging too quickly.',
              'Verify before meeting. Ask for a video call to ensure the person matches their profile photos.',
            ],
            nextLabel: 'Next: Financial & Scams Protection',
            onNext: () {
              _accordionControllers[1].collapse();
              _accordionControllers[2].expand();
            },
          ),
          const SizedBox(height: 10),
          _buildEducationAccordion(
            controller: _accordionControllers[2],
            title: '3. Financial & Scams Protection',
            icon: LucideIcons.alertCircle,
            items: [
              'Never send money or share financial information. Under no circumstances should you wire money or purchase gift cards for someone met online.',
              'Report cryptocurrency or investment pitches. Anyone inviting you to participate in crypto trading or stocks is likely a scammer.',
              'Watch for sob stories. Scammers often claim they need funds for an emergency, travel, or medical treatment.',
            ],
            nextLabel: 'Next: Reporting & What Happens Next',
            onNext: () {
              _accordionControllers[2].collapse();
              _accordionControllers[3].expand();
            },
          ),
          const SizedBox(height: 10),
          _buildEducationAccordion(
            controller: _accordionControllers[3],
            title: '4. Reporting & What Happens Next',
            icon: LucideIcons.ban,
            items: [
              'You can report any concern. Block or report anyone who acts aggressively, asks for money, or behaves inappropriately.',
              'Reporting is confidential. The user will not be notified that they were reported by you.',
              'Our team reviews reports 24/7. Accounts violating community standards are permanently banned to keep Nexus safe.',
            ],
            nextLabel: 'Done',
            onNext: () => _accordionControllers[3].collapse(),
          ),
          const SizedBox(height: 20),
          _buildRedFlagsContent(),
        ],
      ),
    ).animate().fadeIn(delay: 250.ms, duration: 350.ms).slideY(begin: 0.05, end: 0, duration: 350.ms);
  }

  Widget _buildEducationAccordion({
    required ExpansibleController controller,
    required String title,
    required IconData icon,
    required List<String> items,
    required String nextLabel,
    required VoidCallback onNext,
  }) {
    return Theme(
      data: Theme.of(context).copyWith(
        dividerColor: Colors.transparent,
        hoverColor: Colors.transparent,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
      ),
      child: ExpansionTile(
        controller: controller,
        collapsedBackgroundColor: const Color(0xFFF8FAFC),
        backgroundColor: const Color(0xFFF8FAFC),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        onExpansionChanged: (expanded) {
          if (expanded) unawaited(_markGuidelinesReviewed());
        },
        leading: Icon(icon, color: _teal, size: 18),
        title: Text(
          title,
          style: GoogleFonts.inter(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF0F172A),
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          ...items.map((text) {
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Icon(Icons.circle, size: 4, color: _teal),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      text,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        color: const Color(0xFF475569),
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 14),
          ScalePressable(
            onTap: onNext,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  nextLabel,
                  style: GoogleFonts.manrope(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Spot the Red Flags (nested inside Safety Guidelines & Education) ---
  Widget _buildRedFlagsContent() {
    final flags = [
      (
        icon: LucideIcons.zap,
        title: 'Love Bombing',
        desc:
            'Overwhelming affection, pet names, or talk of a future together within days of matching.',
      ),
      (
        icon: LucideIcons.videoOff,
        title: 'Avoids Video Calls',
        desc:
            'Always has an excuse to skip a video chat or phone call before meeting.',
      ),
      (
        icon: LucideIcons.handCoins,
        title: 'Asks for Money',
        desc:
            'Requests cash, gift cards, crypto, or your banking details — for any reason.',
      ),
      (
        icon: LucideIcons.messageCircleOff,
        title: 'Rushes Off the App',
        desc:
            'Pushes hard to move to texting or another app before you feel ready.',
      ),
      (
        icon: LucideIcons.fileWarning,
        title: 'Inconsistent Story',
        desc:
            'Details about their job, age, or life keep changing or don’t add up.',
      ),
      (
        icon: LucideIcons.mapPinOff,
        title: 'Avoids Public Meetups',
        desc: 'Insists on meeting at a private home instead of a public place.',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                LucideIcons.triangleAlert,
                color: _red,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'SPOT THE RED FLAGS',
              style: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF475569),
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Swipe through common warning signs of scams and catfishing.',
          style: GoogleFonts.inter(
            fontSize: 13,
            color: const Color(0xFF64748B),
            height: 1.45,
          ),
        ),
        const SizedBox(height: 16),
        _RedFlagCarousel(flags: flags),
      ],
    );
  }

  // --- Shortcuts & Direct Links ---
  Widget _buildShortcutsSection() {
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
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F9FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      LucideIcons.shield,
                      color: _accent,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'QUICK SHORTCUTS',
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF475569),
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildShortcutTile(
                label: 'Privacy Settings',
                desc: 'Toggle public profile field visibility.',
                icon: LucideIcons.shield,
                onTap: _openPrivacySettings,
              ),
              const Divider(height: 20, color: Color(0xFFE2E8F0)),
              _buildShortcutTile(
                label: 'Blocked Users',
                desc: 'View and manage users you have blocked.',
                icon: LucideIcons.ban,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const BlockedUsersPage(),
                  ),
                ),
              ),
              const Divider(height: 20, color: Color(0xFFE2E8F0)),
              _buildShortcutTile(
                label: 'Hidden Users',
                desc: 'Manage users you have hidden from discovery.',
                icon: LucideIcons.eyeOff,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const HiddenUsersPage(),
                  ),
                ),
              ),
            ],
          ),
        )
        .animate()
        .fadeIn(delay: 300.ms, duration: 350.ms)
        .slideY(begin: 0.05, end: 0, duration: 350.ms);
  }

  Widget _buildShortcutTile({
    required String label,
    required String desc,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return ScalePressable(
      onTap: onTap,
      child: ColoredBox(
        color: Colors.transparent, // Ensures entire row remains tap target
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, color: _accent, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              LucideIcons.chevronRight,
              color: Color(0xFFCBD5E1),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  // --- Reassuring Footer ---
  Widget _buildFooterNote() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 12),
      child: Column(
        children: [
          const Icon(
                LucideIcons.heartHandshake,
                color: Color(0xFFCBD5E1),
                size: 22,
              )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .scale(
                begin: const Offset(0.95, 0.95),
                end: const Offset(1.05, 1.05),
                duration: 2200.ms,
                curve: Curves.easeInOut,
              ),
          const SizedBox(height: 10),
          Text(
            "You're never alone here — help is always one tap away.",
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Built with our Trust & Safety team.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: const Color(0xFFCBD5E1),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 380.ms, duration: 400.ms);
  }
}
