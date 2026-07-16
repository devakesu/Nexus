import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/screens/settings/blocked_users_page.dart';
import 'package:nexus/screens/settings/crisis_helplines_page.dart';
import 'package:nexus/screens/settings/feedback_page.dart';
import 'package:nexus/screens/settings/hidden_users_page.dart';
import 'package:nexus/screens/settings/meetup_safety_page.dart';
import 'package:nexus/screens/settings/privacy_settings_page.dart';
import 'package:nexus/theme/app_colors.dart';
import 'package:nexus/utils/safety_consent_cache.dart';
import 'package:nexus/widgets/safety_consent_prompt.dart';
import 'package:nexus/widgets/safety_score_ring_painter.dart';
import 'package:nexus/widgets/scale_pressable.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

typedef _RedFlagData = ({IconData icon, String title, String desc});

class _RedFlagCarousel extends StatefulWidget {
  const _RedFlagCarousel({required this.flags, required this.onAllViewed});

  final List<_RedFlagData> flags;

  /// Fired once when the user has scrolled to (or past) the final card.
  final VoidCallback onAllViewed;

  @override
  State<_RedFlagCarousel> createState() => _RedFlagCarouselState();
}

class _RedFlagCarouselState extends State<_RedFlagCarousel> {
  late final PageController _controller = PageController(
    viewportFraction: 0.62,
  );
  double _page = 0;
  bool _allViewedFired = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onPageChange);
  }

  // With viewportFraction < 1 and padEnds: false, the PageController page
  // value never reaches flags.length - 1 because the last card fills the
  // right portion of the viewport before the scroll end. The effective
  // "active" dot is clamped so that once page rounds to flags.length - 2
  // (second-to-last card is the primary card, last is fully visible to its
  // right), we treat the last dot as active.
  int get _activeDot {
    final rounded = _page.round();
    final last = widget.flags.length - 1;
    return rounded >= last - 1 ? last : rounded;
  }

  void _onPageChange() {
    if (mounted) {
      final newPage = _controller.page ?? 0;
      if (newPage != _page) {
        setState(() => _page = newPage);
      }
      // Fire once when the last card is visible (activeDot == last index).
      if (!_allViewedFired && _activeDot >= widget.flags.length - 1) {
        _allViewedFired = true;
        widget.onAllViewed();
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
                            color: AppColors.error,
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
              final active = (_activeDot == i);
              return AnimatedContainer(
                duration: 250.ms,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: active ? 16 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: active ? AppColors.error : const Color(0xFFFECACA),
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
  const SafetyCenterPage({super.key});

  @override
  State<SafetyCenterPage> createState() => _SafetyCenterPageState();
}

class _SafetyCenterPageState extends State<SafetyCenterPage> {
  static const Color _accent = AppColors.safetyBlue;
  static const Color _teal = AppColors.safetyTeal;
  static const Color _red = AppColors.error;

  // Whether at least one trusted contact exists - read independently here
  // just to drive the safety score checklist ring; the Meetup Safety page
  // owns the actual contacts list. Only meaningful when consent is granted;
  // forced false otherwise so the item can't show "done" without consent.
  bool _hasTrustedContacts = false;

  // Quiz state variables
  int _quizIndex = 0; // 0: Start, 1: Q1, 2: Q2, 3: Q3, 4: Result
  int _score = 0;
  int _selectedAnswerIndex = -1;
  bool _answered = false;

  // Safety Score checklist state (persisted across sessions).
  // Each flag is stored under a versioned key so that content updates
  // (new quiz questions, revised guidelines) automatically reset the tick.
  // Bump the version constant whenever the corresponding section changes.
  static const _quizVersion = 'v1';
  static const _guidelinesVersion = 'v3';
  static const _privacyVersion = 'v1';
  bool _quizCompletedOnce = false;
  bool _guidelinesReviewed = false;
  bool _privacySettingsReviewed = false;

  // Section anchors for scroll-to-section navigation from the safety score
  // card. Indices into the body's item list (see _buildSection) - driving
  // ScrollablePositionedList.scrollTo instead of a GlobalKey/ensureVisible
  // lets the list jump to a section that hasn't been built yet without
  // disabling virtualization for the rest of the page.
  final ItemScrollController _itemScrollController = ItemScrollController();
  static const _guidelinesSectionIndex = 2;
  static const _quizSectionIndex = 4;

  // One controller per guideline accordion so a "Next" button can collapse
  // the current tile and expand the next one in sequence.
  final List<ExpansibleController> _accordionControllers = List.generate(
    4,
    (_) => ExpansibleController(),
  );
  // Tracks which accordion panels have been expanded at least once.
  // Guidelines are only marked reviewed when all 4 have been opened.
  final Set<int> _openedAccordions = {};
  // Whether the user has scrolled through all red-flag carousel cards.
  bool _redFlagsAllViewed = false;

  /// Called whenever the user makes progress through the guidelines content
  /// (opens an accordion or reaches the last red-flag card). Only marks the
  /// checklist item done once both conditions are fully satisfied.
  void _checkGuidelinesComplete() {
    if (_openedAccordions.length == 4 && _redFlagsAllViewed) {
      unawaited(_markGuidelinesReviewed());
    }
  }

  double get _safetyScore {
    var completed = 0;
    if (_hasTrustedContacts) completed++;
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
    unawaited(_loadHasTrustedContacts());
    unawaited(_loadChecklistFlags());
  }

  // --- Safety Score checklist persistence ---
  Future<void> _loadChecklistFlags() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      // Each flag is keyed by version so bumping the constant above
      // automatically invalidates old ticks when content changes.
      _quizCompletedOnce =
          prefs.getBool('safety_quiz_completed_$_quizVersion') ?? false;
      _guidelinesReviewed =
          prefs.getBool('safety_guidelines_reviewed_$_guidelinesVersion') ??
          false;
      _privacySettingsReviewed =
          prefs.getBool('safety_privacy_reviewed_$_privacyVersion') ?? false;
    });
  }

  Future<void> _markQuizCompleted() async {
    if (_quizCompletedOnce) return;
    setState(() => _quizCompletedOnce = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('safety_quiz_completed_$_quizVersion', true);
  }

  Future<void> _markGuidelinesReviewed() async {
    if (_guidelinesReviewed) return;
    setState(() => _guidelinesReviewed = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      'safety_guidelines_reviewed_$_guidelinesVersion',
      true,
    );
  }

  Future<void> _markPrivacySettingsReviewed() async {
    if (_privacySettingsReviewed) return;
    setState(() => _privacySettingsReviewed = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('safety_privacy_reviewed_$_privacyVersion', true);
  }

  void _scrollToSection(int index) {
    unawaited(
      _itemScrollController.scrollTo(
        index: index,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        alignment: 0.08,
      ),
    );
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

  // Lightweight read of just the contact count for the safety score ring;
  // MeetupSafetyPage owns the full contacts list and its persistence.
  // Only updates _hasTrustedContacts when consent has been granted -
  // without consent the trusted-contacts section is inaccessible anyway,
  // so showing the item as done would be misleading.
  Future<void> _loadHasTrustedContacts() async {
    if (!SafetyConsentCache.isGranted) {
      // No consent → can't have legitimately added contacts; leave false.
      return;
    }
    try {
      const secureStorage = FlutterSecureStorage(
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
        ),
      );
      final val = await secureStorage.read(key: 'safety_contacts');
      if (val != null) {
        final list = jsonDecode(val) as List<dynamic>;
        if (mounted) setState(() => _hasTrustedContacts = list.isNotEmpty);
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('safety_contacts');
      if (mounted) {
        setState(() => _hasTrustedContacts = list?.isNotEmpty ?? false);
      }
    } on Exception catch (_) {
      // Not critical for the checklist ring; leave as-is.
    }
  }

  void _openMeetupSafetyPage() {
    if (!SafetyConsentCache.isGranted) {
      unawaited(_promptSafetyConsentThenOpen());
      return;
    }
    unawaited(
      Navigator.of(context)
          .push(
            MaterialPageRoute<void>(
              builder: (_) => const MeetupSafetyPage(),
            ),
          )
          .then((_) => _loadHasTrustedContacts()),
    );
  }

  /// Shown instead of navigating straight to MeetupSafetyPage when safety
  /// consent hasn't been granted - the trusted-contacts/check-in/SOS/
  /// Digital Witness features all live behind that page, so gating the nav
  /// tap here (rather than every individual feature inside it) is the one
  /// enforcement point this surface needs.
  Future<void> _promptSafetyConsentThenOpen() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
        ),
        child: SafetyConsentPromptCard(
          onGranted: () {
            Navigator.of(sheetContext).pop();
            if (mounted) _openMeetupSafetyPage();
          },
        ),
      ),
    );
  }

  void _openCrisisHelplinesPage() {
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const CrisisHelplinesPage()),
      ),
    );
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

  // Item count and order must stay in sync with _guidelinesSectionIndex and
  // _quizSectionIndex above.
  static const _sectionCount = 7;

  Widget _buildSection(int index) {
    switch (index) {
      case 0:
        return _buildSafetyHeroBanner();
      case 1:
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildNavCard(
                  icon: LucideIcons.shieldAlert,
                  iconColor: _red,
                  iconBg: const Color(0xFFFEE2E2),
                  title: 'Meetup Safety Alert',
                  subtitle: 'Check-ins, SOS & trusted contacts.',
                  onTap: _openMeetupSafetyPage,
                  animateDelay: 50,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildNavCard(
                  icon: LucideIcons.phoneCall,
                  iconColor: const Color(0xFFEA580C),
                  iconBg: const Color(0xFFFFF7ED),
                  title: 'Crisis Helplines',
                  subtitle: 'Confidential support hotlines.',
                  onTap: _openCrisisHelplinesPage,
                  animateDelay: 80,
                ),
              ),
            ],
          ),
        );
      case 2:
        return _buildSafetyEducationSection();
      case 3:
        return _buildVerifiedProtectedSection();
      case 4:
        return _buildInteractiveQuizSection();
      case 5:
        return _buildShortcutsSection();
      case 6:
        return _buildFooterNote();
      default:
        throw StateError('Unknown Safety Center section index: $index');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: _buildAppBar(),
      // A plain virtualized ScrollablePositionedList - unlike ListView, its
      // ItemScrollController can jump straight to a section by index even
      // before that section has ever been built, so the checklist's
      // "scroll to quiz/guidelines" taps work without forcing the whole
      // page to lay out up front.
      body: ScrollablePositionedList.builder(
        padding: const EdgeInsets.only(bottom: 60),
        itemScrollController: _itemScrollController,
        itemCount: _sectionCount,
        itemBuilder: (context, index) => _buildSection(index),
      ),
    );
  }

  // Tappable summary card that opens a dedicated page - used so Meetup
  // Safety Alert and Crisis Helplines get room to breathe on their own
  // screen instead of crowding the Safety Center hub. Laid out vertically
  // (icon, title, subtitle) so a pair fits comfortably side by side.
  Widget _buildNavCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    double animateDelay = 0,
  }) {
    return ScalePressable(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
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
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: iconBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: iconColor, size: 20),
                    ),
                    const Icon(
                      LucideIcons.chevronRight,
                      size: 16,
                      color: Color(0xFFCBD5E1),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    color: const Color(0xFF64748B),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        )
        .animate()
        .fadeIn(delay: animateDelay.ms, duration: 350.ms)
        .slideY(begin: 0.05, end: 0, duration: 350.ms);
  }

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.safetyBlue, AppColors.safetyTeal],
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
    final score = _safetyScore;
    final percent = (score * 100).round();
    final checklist = <_ChecklistItem>[
      _ChecklistItem(
        label: 'Add a trusted contact',
        // Only mark done if consent is granted - without it the Meetup
        // Safety page is gated so contacts can't have been legitimately added.
        done: _hasTrustedContacts && SafetyConsentCache.isGranted,
        icon: LucideIcons.users,
        onTap: _openMeetupSafetyPage,
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
        onTap: () => _scrollToSection(_quizSectionIndex),
      ),
      _ChecklistItem(
        label: 'Review safety guidelines',
        done: _guidelinesReviewed,
        icon: LucideIcons.bookOpen,
        onTap: () => _scrollToSection(_guidelinesSectionIndex),
      ),
    ];

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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
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
              const SizedBox(height: 20),
              const Divider(color: Color(0xFFD1FAE5), height: 1),
              const SizedBox(height: 20),
              Row(
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: score),
                    duration: 800.ms,
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) {
                      return CustomPaint(
                        size: const Size(64, 64),
                        painter: SafetyScoreRingPainter(progress: value),
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
                                  ? const Color(0xFF475569)
                                  : const Color(0xFF334155),
                              decoration: item.done
                                  ? TextDecoration.lineThrough
                                  : null,
                              decorationColor: const Color(0xFF475569),
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

  // --- Verified & Protected Section ---
  Widget _buildVerifiedProtectedSection() {
    final items = [
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
            'One tap removes someone from your matches, requests, and search results - permanently.',
      ),
    ];

    return Container(
          margin: const EdgeInsets.fromLTRB(20, 10, 20, 10),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFEFF6FF), Color(0xFFECFDF5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFBAE6FD)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: _accent.withValues(alpha: 0.12),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: const Icon(
                      LucideIcons.badgeCheck,
                      color: _accent,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'VERIFIED & PROTECTED',
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
                'Everything working quietly in the background - from identity checks to 24/7 moderation - to keep Nexus genuine and safe.',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: const Color(0xFF64748B),
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
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(item.icon, color: _teal, size: 16),
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
                                    color: const Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  item.desc,
                                  style: GoogleFonts.inter(
                                    fontSize: 11.5,
                                    color: const Color(0xFF64748B),
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
            index: 0,
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
            index: 1,
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
            index: 2,
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
            index: 3,
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
    required int index,
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
          if (expanded) {
            _openedAccordions.add(index);
            // Delegate to the shared completion check - red flags also
            // need to have been fully scrolled before the tick fires.
            _checkGuidelinesComplete();
          }
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
            'Requests cash, gift cards, crypto, or your banking details - for any reason.',
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
        _RedFlagCarousel(
          flags: flags,
          onAllViewed: () {
            setState(() => _redFlagsAllViewed = true);
            _checkGuidelinesComplete();
          },
        ),
      ],
    );
  }

  // --- Shortcuts & Direct Links ---
  // Deliberately the one dark card on the page - every other section is a
  // light/white card, so this reads instantly as "different kind of
  // content" (a utility menu, not a safety topic) rather than blending in.
  Widget _buildShortcutsSection() {
    return Container(
          margin: const EdgeInsets.fromLTRB(20, 10, 20, 10),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1E1B4B), Color(0xFF0F172A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.indigo.withValues(alpha: 0.18),
                blurRadius: 20,
                offset: const Offset(0, 8),
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
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      LucideIcons.zap,
                      color: Color(0xFFC7D2FE),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'QUICK SHORTCUTS',
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.white70,
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
              const Divider(height: 20, color: Colors.white12),
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
              const Divider(height: 20, color: Colors.white12),
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
              const Divider(height: 20, color: Colors.white12),
              _buildShortcutTile(
                label: 'Help, Feedback & Bug Report',
                desc: 'Reach our team directly, any time.',
                icon: LucideIcons.messageSquare,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const FeedbackPage(),
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
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, color: const Color(0xFFC7D2FE), size: 18),
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
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.white60,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              LucideIcons.chevronRight,
              color: Colors.white38,
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
            "You're never alone here - help is always one tap away.",
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Built with our Trust & Safety team.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: const Color(0xFF475569),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 380.ms, duration: 400.ms);
  }
}
