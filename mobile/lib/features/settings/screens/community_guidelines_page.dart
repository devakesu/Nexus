import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/core/utils/secure_preferences.dart';
import 'package:nexus/core/widgets/nexus_toast.dart';
import 'package:nexus/core/widgets/scale_pressable.dart';

// ---------------------------------------------------------------------------
// Main Page
// ---------------------------------------------------------------------------

class CommunityGuidelinesPage extends StatefulWidget {
  const CommunityGuidelinesPage({super.key});

  @override
  State<CommunityGuidelinesPage> createState() =>
      _CommunityGuidelinesPageState();
}

class _CommunityGuidelinesPageState extends State<CommunityGuidelinesPage> {
  // 0: Orbits, 1: Profile, 2: Interactions, 3: Chat, 4: Safety & Privacy,
  // 5: Reporting, 6: Enforcement
  int _selectedTab = 0;
  bool _pledgeSigned = false;

  @override
  void initState() {
    super.initState();
    _loadPledgeState();
  }

  void _loadPledgeState() {
    unawaited(
      SecurePreferences.getInstance().then((prefs) async {
        final val = await prefs.getBool('pledge_signed');
        if (mounted) {
          setState(() {
            _pledgeSigned = val ?? false;
          });
        }
      }),
    );
  }

  Future<void> _savePledgeState(bool value) async {
    final prefs = await SecurePreferences.getInstance();
    await prefs.setBool('pledge_signed', value: value);
  }

  static const List<_TabMeta> _tabs = [
    _TabMeta(
      'Orbits',
      LucideIcons.orbit,
      AppColors.pulsarPink,
      'Dating, Friends & Professional rules',
    ),
    _TabMeta(
      'Profile',
      LucideIcons.user,
      AppColors.primaryTeal,
      'Photos, bio, identity & preferences',
    ),
    _TabMeta(
      'Interactions',
      LucideIcons.zap,
      AppColors.modeDating,
      'Liking, icebreakers & matches',
    ),
    _TabMeta(
      'Chat',
      LucideIcons.messageCircle,
      AppColors.modeFriends,
      'Messaging, scams & media rules',
    ),
    _TabMeta(
      'Safety',
      LucideIcons.shieldCheck,
      AppColors.safetyBlue,
      'Meetup safety, SOS & privacy',
    ),
    _TabMeta(
      'Reporting',
      LucideIcons.flag,
      AppColors.warning,
      'How to flag rule violations',
    ),
    _TabMeta(
      'Enforcement',
      LucideIcons.gavel,
      AppColors.error,
      'Warnings, bans & appeals',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: _buildAppBar(),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 60),
        children: [
          _buildHeroHeader(),
          const SizedBox(height: 16),
          _buildQuickSummaryBanner(),
          const SizedBox(height: 20),
          _buildSectionGrid(),
          const SizedBox(height: 20),
          _buildActiveTabContent(),
          const SizedBox(height: 24),
          _buildSafetyPledgeCard(),
          _buildFooterNote(),
        ],
      ),
    );
  }

  // ── App Bar ────────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.modeSettings, AppColors.primaryTeal],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0x220284C7),
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
            'Community Guidelines',
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

  // ── Hero Header ────────────────────────────────────────────────────────────

  Widget _buildHeroHeader() {
    return Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Colors.white, Color(0xFFEFF6FF)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFBFDBFE)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 12,
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
                      'Our Galaxy, Our Rules',
                      style: GoogleFonts.manrope(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Nexus is built on authenticity, respect, and genuine human connection. These guidelines protect every person in our constellation - from how you build your profile to how you treat others in chat.',
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        color: const Color(0xFF475569),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildLastUpdatedChip(),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 68,
                height: 68,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    ..._buildBreathingRings(),
                    Container(
                          padding: const EdgeInsets.all(12),
                          decoration: const BoxDecoration(
                            color: Color(0xFFDBEAFE),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            LucideIcons.bookOpen,
                            color: AppColors.safetyBlue,
                            size: 26,
                          ),
                        )
                        .animate(onPlay: (c) => c.repeat(reverse: true))
                        .scale(
                          begin: const Offset(0.92, 0.92),
                          end: const Offset(1.08, 1.08),
                          duration: 2200.ms,
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

  Widget _buildLastUpdatedChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFDBEAFE),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            LucideIcons.calendarDays,
            size: 10,
            color: AppColors.safetyBlue,
          ),
          const SizedBox(width: 5),
          Text(
            'Updated July 2026',
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.safetyBlue,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildBreathingRings() {
    return List.generate(2, (i) {
      return Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.safetyBlue.withValues(alpha: 0.2),
                width: 1.5,
              ),
            ),
          )
          .animate(onPlay: (c) => c.repeat(), delay: (i * 1000).ms)
          .scale(
            begin: const Offset(0.6, 0.6),
            end: const Offset(1.3, 1.3),
            duration: 2500.ms,
            curve: Curves.easeOut,
          )
          .fadeOut(duration: 2500.ms, curve: Curves.easeOut);
    });
  }

  // ── Quick Summary Banner ───────────────────────────────────────────────────

  Widget _buildQuickSummaryBanner() {
    final points = [
      (LucideIcons.checkCircle2, 'Be authentic, be yourself', true),
      (LucideIcons.checkCircle2, "Respect every person's boundaries", true),
      (LucideIcons.checkCircle2, 'Stay safe - use our safety tools', true),
      (LucideIcons.xCircle, 'No harassment, scams, or fakery', false),
    ];

    return Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFBBF7D0)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF10B981).withValues(alpha: 0.06),
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
                  const Icon(
                    LucideIcons.listChecks,
                    size: 14,
                    color: Color(0xFF059669),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'TL;DR - The Essentials',
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF065F46),
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 14,
                runSpacing: 6,
                children: points.map((p) {
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        p.$1,
                        size: 13,
                        color: p.$3 ? const Color(0xFF10B981) : AppColors.error,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        p.$2,
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: p.$3
                              ? const Color(0xFF065F46)
                              : const Color(0xFF991B1B),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ],
          ),
        )
        .animate()
        .fadeIn(delay: 100.ms, duration: 350.ms)
        .slideY(begin: 0.05, end: 0, duration: 350.ms);
  }

  // ── Tab Scroll Row ─────────────────────────────────────────────────────────

  // ── Section Grid (2-column) ─────────────────────────────────────────────────
  // All 7 sections are visible at once - no horizontal scrolling, no discovery
  // friction. Odd-count handled by making the last card span full width.

  Widget _buildSectionGrid() {
    return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'BROWSE SECTIONS',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF94A3B8),
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              // Rows of 2 - last row is a single full-width card if count is odd
              for (int row = 0; row < (_tabs.length / 2).ceil(); row++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _buildSectionGridRow(row),
                ),
            ],
          ),
        )
        .animate()
        .fadeIn(delay: 120.ms, duration: 380.ms)
        .slideY(
          begin: 0.04,
          end: 0,
          duration: 380.ms,
          curve: Curves.easeOut,
        );
  }

  Widget _buildSectionGridRow(int row) {
    final a = row * 2;
    final b = row * 2 + 1;
    final isLastOddRow = b >= _tabs.length;

    if (isLastOddRow) {
      // Full-width single card
      return _buildSectionCard(_tabs[a], a, fullWidth: true);
    }

    return Row(
      children: [
        Expanded(child: _buildSectionCard(_tabs[a], a)),
        const SizedBox(width: 10),
        Expanded(child: _buildSectionCard(_tabs[b], b)),
      ],
    );
  }

  Widget _buildSectionCard(
    _TabMeta tab,
    int index, {
    bool fullWidth = false,
  }) {
    final active = _selectedTab == index;
    return ScalePressable(
      onTap: () => setState(() => _selectedTab = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        // Fixed height for consistency; full-width card is shorter
        padding: EdgeInsets.symmetric(
          horizontal: 14,
          vertical: fullWidth ? 12 : 14,
        ),
        decoration: BoxDecoration(
          color: active ? tab.color.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active
                ? tab.color.withValues(alpha: 0.45)
                : const Color(0xFFE2E8F0),
            width: active ? 1.5 : 1,
          ),
          boxShadow: [
            if (active)
              BoxShadow(
                color: tab.color.withValues(alpha: 0.18),
                blurRadius: 12,
                offset: const Offset(0, 4),
              )
            else
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.025),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: fullWidth
            ? _buildSectionCardFullWidth(tab, active)
            : _buildSectionCardPortrait(tab, active),
      ),
    );
  }

  /// Portrait layout for 2-column cards: icon on top, label + subtitle below.
  Widget _buildSectionCardPortrait(_TabMeta tab, bool active) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,

      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: tab.color.withValues(alpha: active ? 0.16 : 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(tab.icon, size: 15, color: tab.color),
            ),
            if (active)
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: tab.color,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tab.label,
              style: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: active
                    ? Color.lerp(tab.color, AppColors.ink, 0.35)
                    : AppColors.ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              tab.subtitle,
              style: GoogleFonts.inter(
                fontSize: 9.5,
                color: active
                    ? Color.lerp(tab.color, AppColors.ink, 0.65)
                    : AppColors.inkFaint,
                height: 1.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ],
    );
  }

  /// Landscape layout for the full-width last card: icon left, text right.
  Widget _buildSectionCardFullWidth(_TabMeta tab, bool active) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: tab.color.withValues(alpha: active ? 0.16 : 0.10),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(tab.icon, size: 16, color: tab.color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                tab.label,
                style: GoogleFonts.manrope(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: active
                      ? Color.lerp(tab.color, AppColors.ink, 0.35)
                      : AppColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                tab.subtitle,
                style: GoogleFonts.inter(
                  fontSize: 10.5,
                  color: active
                      ? Color.lerp(tab.color, AppColors.ink, 0.65)
                      : AppColors.inkFaint,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        Icon(
          LucideIcons.chevronRight,
          size: 14,
          color: active ? tab.color : const Color(0xFFCBD5E1),
        ),
      ],
    );
  }

  // ── Tab Content Dispatcher ─────────────────────────────────────────────────

  Widget _buildActiveTabContent() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: KeyedSubtree(
        key: ValueKey(_selectedTab),
        child: switch (_selectedTab) {
          0 => _buildOrbitsTab(),
          1 => _buildProfileTab(),
          2 => _buildInteractionsTab(),
          3 => _buildChatTab(),
          4 => _buildSafetyPrivacyTab(),
          5 => _buildReportingTab(),
          6 => _buildEnforcementTab(),
          _ => const SizedBox.shrink(),
        },
      ),
    );
  }

  // ── Tab 0: Orbits ──────────────────────────────────────────────────────────

  Widget _buildOrbitsTab() {
    return _tabPadding(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('What are Orbits?'),
          _prose(
            "Orbits are Nexus's three distinct relationship modes - Dating, Friends, and Professional. Each orbit has its own signal color, its own social contract, and its own rules. You choose which orbits you broadcast in, and others only see you in orbits you've enabled. Cross-orbit conduct violations are treated with extra severity.",
          ),
          const SizedBox(height: 16),
          _AccordionSection(
            title: 'Dating Orbit - Romantic Connections',
            icon: LucideIcons.heart,
            accentColor: AppColors.modeDating,
            children: [
              _bullet(
                'Consent is non-negotiable. Every interaction must be welcomed - romantic interest only flows where it is explicitly or clearly invited.',
              ),
              _bullet(
                "Be honest about who you are and what you're looking for. Misrepresenting your intentions to get a match is a violation.",
              ),
              _bullet(
                'Zero tolerance for harassment: unsolicited explicit images, persistent contact after being told to stop, intimidation, or stalking all result in a permanent ban.',
              ),
              _bullet(
                'Age integrity: Nexus is strictly 18+. Misrepresenting your age to match with adults, or attempting to contact minors, results in immediate permanent removal and referral to law enforcement.',
              ),
              _bullet(
                "Respect a match's silence. If someone stops replying, that is a clear signal. Do not continue messaging, create new accounts to reach them, or escalate in any way.",
              ),
              _bullet(
                'Before meeting offline, configure a Safety Check-in from Settings → Safety Center. Always meet first in a busy public place.',
              ),
            ],
          ),
          _AccordionSection(
            title: 'Friends Orbit - Platonic Connections',
            icon: LucideIcons.users,
            accentColor: AppColors.modeFriends,
            children: [
              _bullet(
                'This space is explicitly platonic. Do not use it to make romantic advances - doing so after a match has expressed wanting a friendship is a conduct violation.',
              ),
              _bullet(
                'Welcome diverse interests, music tastes, majors, and backgrounds with an open mind. The Friends Orbit is where genuine variety meets.',
              ),
              _bullet(
                'Activity partners, study groups, interest clubs, and campus communities are all welcome. Keep conversations relevant to building a real connection.',
              ),
              _bullet(
                'No commercial activity: do not use the Friends Orbit to sell event tickets, promote businesses, share referral links, or recruit for third-party platforms.',
              ),
              _bullet(
                'Respect boundaries around time, attention, and personal topics - just as you would with any new friend.',
              ),
            ],
          ),
          _AccordionSection(
            title: 'Professional Orbit - Mentorship & Networking',
            icon: LucideIcons.briefcase,
            accentColor: AppColors.modeProfessional,
            children: [
              _bullet(
                'Strict no-romance rule: the Professional Orbit is for career, academic, and mentorship connections only. Any romantic or sexual advance here results in immediate account suspension.',
              ),
              _bullet(
                'Present your true credentials, skills, role, and goals. Inflating or fabricating academic or professional details undermines every connection made here.',
              ),
              _bullet(
                'Maintain professional messaging etiquette. Support peers seeking advice, referrals, collaboration opportunities, or mentorship with genuine help.',
              ),
              _bullet(
                'No MLM, pyramid scheme, or unsolicited job/service solicitation. Networking is about mutual value - not one-sided pitches.',
              ),
              _bullet(
                'Confidential information shared in a mentoring relationship must stay confidential. Do not screenshot or share private professional conversations.',
              ),
            ],
          ),
          _AccordionSection(
            title: 'Cross-Orbit Rules',
            icon: LucideIcons.arrowLeftRight,
            accentColor: AppColors.primaryTeal,
            children: [
              _bullet(
                'You may enable multiple orbits simultaneously, but users you connect with in one orbit cannot be contacted through a different orbit without their explicit knowledge and consent.',
              ),
              _bullet(
                'Switching orbit intent mid-conversation - e.g., starting in Friends and pivoting to romantic messaging - is considered deceptive and violates these guidelines.',
              ),
              _bullet(
                'Your orbit selection is visible to potential matches. Misusing an orbit to access users who have only enabled a different orbit is a ban-level offense.',
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Tab 1: Profile ─────────────────────────────────────────────────────────

  Widget _buildProfileTab() {
    return _tabPadding(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Your Profile Is Your Identity'),
          _prose(
            'Your Nexus profile is how the constellation sees you. It must represent your real, current self. Authenticity here protects every match you make - and every person who considers connecting with you.',
          ),
          const SizedBox(height: 16),
          _AccordionSection(
            title: 'Photos & Media',
            icon: LucideIcons.image,
            accentColor: AppColors.pulsarPink,
            children: [
              _bullet(
                'All photos must be recent, clear, and genuinely of you. No filters that fundamentally change your appearance, no primary photo older than 3 years.',
              ),
              _bullet(
                'No explicit nudity, graphic sexual imagery, or graphic violence in profile photos or any media shared via the platform.',
              ),
              _bullet(
                "No photos of minors as your profile photo, or photos that could be mistaken for a child's profile.",
              ),
              _bullet(
                'Avoid including personal identifiers you want to keep private in photos (e.g., ID cards, visible home address in background) - protect yourself.',
              ),
              _bullet(
                'AI-generated or heavily digitally altered photos that misrepresent your appearance are prohibited.',
              ),
              _bullet(
                'Group photos used as a primary photo must clearly indicate which person in the photo is you.',
              ),
            ],
          ),
          _AccordionSection(
            title: 'Bio & Personal Information',
            icon: LucideIcons.fileText,
            accentColor: AppColors.primaryTeal,
            children: [
              _bullet(
                'Your bio must reflect your actual personality, interests, and intentions. Do not copy-paste generic descriptions or use it to advertise external services.',
              ),
              _bullet(
                'Do not include hate speech, slurs, threats, or content that demeans any group of people in your bio.',
              ),
              _bullet(
                'No contact info (phone numbers, social handles, etc.) in your bio for the purpose of moving conversations off-platform before a match is formed - this is a common scam vector.',
              ),
              _bullet(
                'Spiritual beliefs, political views, and sensitive topics may appear in your bio, but must not be used to demean or discriminate against others.',
              ),
              _bullet(
                'Hometown, current place, and other location fields are optional and may be hidden at any time via Privacy Settings.',
              ),
            ],
          ),
          _AccordionSection(
            title: 'Identity & Verification',
            icon: LucideIcons.badgeCheck,
            accentColor: AppColors.modeProfessional,
            children: [
              _bullet(
                'Catfishing - impersonating another real person, a celebrity, or a fictional character - is a zero-tolerance offense and results in permanent removal.',
              ),
              _bullet(
                'Do not create multiple accounts to evade a ban, generate artificial matches, or contact users who have blocked you.',
              ),
              _bullet(
                'For the Nexus MEC campus flavor, your account must be associated with a valid campus email. Using a personal email to circumvent campus gating is a policy violation.',
              ),
              _bullet(
                'Gender identity, sexuality, and pronouns must be your own genuine identity. Misrepresenting these to access certain discovery filters is a violation.',
              ),
            ],
          ),
          _AccordionSection(
            title: 'Spotify & Music Taste',
            icon: LucideIcons.music2,
            accentColor: const Color(0xFF1DB954),
            children: [
              _bullet(
                'Your Spotify integration must reflect your genuine listening history. Do not use automation tools, fake streams, or third-party manipulation to inflate music compatibility scores.',
              ),
              _bullet(
                'Music taste is a genuine connection signal on Nexus - gaming it to appear more compatible with specific users is a form of deception.',
              ),
              _bullet(
                'Spotify data is used only for compatibility display. It is never sold or shared with third parties outside of what is described in our Privacy Policy.',
              ),
              _bullet(
                "Respect that others may have very different musical tastes. Zero tolerance for mocking or insulting someone's music preferences.",
              ),
            ],
          ),
          _AccordionSection(
            title: 'Preferences & Discovery Filters',
            icon: LucideIcons.sliders,
            accentColor: AppColors.modeSettings,
            children: [
              _bullet(
                'Discovery preferences (age range, distance, gender) are tools to help you find compatible people - not to exclude or dehumanize groups of people.',
              ),
              _bullet(
                'Your preferences are personal and private. You are not required to explain your filters to anyone.',
              ),
              _bullet(
                'Nexus does not permit using preference filters to signal discriminatory intent (e.g., anti-group statements in bio paired with exclusionary filters).',
              ),
              _bullet(
                'Special-category data (religious beliefs, sexuality, health-related fields) is processed under enhanced consent and may be hidden from your profile at any time via Privacy Settings.',
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Tab 2: Interactions ────────────────────────────────────────────────────

  Widget _buildInteractionsTab() {
    return _tabPadding(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('How We Interact'),
          _prose(
            "Every tap, like, and icebreaker is a signal you're sending to another human being. Nexus's interaction model is built around discovery without the swipe-deck mechanic - genuine connections over gamified numbers.",
          ),
          const SizedBox(height: 16),
          _AccordionSection(
            title: 'Liking & Passing',
            icon: LucideIcons.heartHandshake,
            accentColor: AppColors.modeDating,
            children: [
              _bullet(
                'Likes are an expression of genuine interest - not a numbers game. Mass-liking every profile to maximize matches degrades the experience for everyone.',
              ),
              _bullet(
                'Passing on someone is not disrespectful. It is a normal and healthy part of discovering who you connect with.',
              ),
              _bullet(
                'After passing on someone, do not attempt to contact them through external means or other accounts. A pass is a clear signal.',
              ),
              _bullet(
                'Automated like/pass bots or any third-party tool that interacts with the Orbit screen on your behalf is strictly prohibited and results in permanent account termination.',
              ),
            ],
          ),
          _AccordionSection(
            title: 'Stardust Messages (Icebreakers)',
            icon: LucideIcons.sparkles,
            accentColor: AppColors.pulsarPink,
            children: [
              _bullet(
                'Stardust messages are your first signal to a potential connection. Make them warm, contextual, and genuine - reference something real from their profile.',
              ),
              _bullet(
                'Copy-pasted, generic, or spam messages sent to many people at once diminish the platform for everyone and may result in messaging restrictions.',
              ),
              _bullet(
                "Never send explicit, sexual, or threatening content as an opening message - even if you think it's a joke.",
              ),
              _bullet(
                'Icebreakers must not include external contact information, payment links, commercial solicitations, or off-platform redirects.',
              ),
            ],
          ),
          _AccordionSection(
            title: 'Matches & Connections',
            icon: LucideIcons.link2,
            accentColor: AppColors.primaryTeal,
            children: [
              _bullet(
                'A match means both parties expressed interest - it is an invitation to start a conversation, not a guarantee of anything further.',
              ),
              _bullet(
                'If a match unmatches you, do not attempt to re-contact them, find them elsewhere online, or pressure them in any way.',
              ),
              _bullet(
                'Matches on Nexus are intended for personal connection, not for recruiting, surveying, or commercial engagement.',
              ),
              _bullet(
                'Screenshots of private profile content or conversations shared publicly without consent violate these guidelines and may constitute a violation of applicable privacy law.',
              ),
            ],
          ),
          _AccordionSection(
            title: 'Orbit Discovery (The Explore Screen)',
            icon: LucideIcons.telescope,
            accentColor: AppColors.modeProfessional,
            children: [
              _bullet(
                'The Orbit screen is a broadcast space - profiles displayed are shared with you in good faith. Treat every card as a real person deserving of respect.',
              ),
              _bullet(
                'Do not use the Orbit screen for reconnaissance (e.g., checking if a specific known person has a Nexus account to monitor their activity).',
              ),
              _bullet(
                'Location data used for discovery proximity is approximate and protected. Do not attempt to infer exact addresses from profile proximity data.',
              ),
              _bullet(
                'Reporting tools are accessible directly from any profile card. Use them if you see something concerning - report before engaging.',
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Tab 3: Chat ────────────────────────────────────────────────────────────

  Widget _buildChatTab() {
    return _tabPadding(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Chat Standards'),
          _prose(
            'The chat layer is where real connections are built. These rules ensure every conversation is a safe, respectful, and genuine exchange - regardless of which orbit the match was formed in.',
          ),
          const SizedBox(height: 16),
          _AccordionSection(
            title: 'Respectful Communication',
            icon: LucideIcons.messageCircleHeart,
            accentColor: AppColors.modeFriends,
            children: [
              _bullet(
                'Treat every message the way you would a face-to-face conversation. Text lacks nuance - lead with kindness and clarity.',
              ),
              _bullet(
                'Do not send unsolicited explicit content of any kind - no nude images, sexual videos, or graphic descriptions - unless both parties have clearly and explicitly consented.',
              ),
              _bullet(
                'Hate speech, slurs, dehumanizing language, or content targeting someone based on race, ethnicity, religion, gender, sexuality, disability, or other protected characteristic is a zero-tolerance offense.',
              ),
              _bullet(
                'Threats of physical harm, doxxing threats, or threats to leak personal information are criminal acts and will be reported to law enforcement.',
              ),
              _bullet(
                'Persistent messaging after being told to stop - even politely - constitutes harassment. A chat reply is not owed to you.',
              ),
            ],
          ),
          _AccordionSection(
            title: 'Scams & Financial Manipulation',
            icon: LucideIcons.alertTriangle,
            accentColor: AppColors.warning,
            children: [
              _bullet(
                'Never ask a match for money, gift cards, cryptocurrency, bank transfers, or any financial assistance - ever. Romance scams are a serious crime.',
              ),
              _bullet(
                "Do not share investment 'opportunities,' trading platforms, or crypto wallets in chat. These are among the most common scam vectors on dating platforms globally.",
              ),
              _bullet(
                'If a match asks you for money or directs you to an external financial platform, report them immediately using the in-chat report button and cease all contact.',
              ),
              _bullet(
                'Nexus will never ask you for payment through chat. Any message claiming to be from Nexus support and requesting payment is a scam - report it.',
              ),
              _bullet(
                'Phishing links - URLs that look like legitimate sites but steal your credentials - must never be sent or clicked. Report immediately if received.',
              ),
            ],
          ),
          _AccordionSection(
            title: 'Sharing Media in Chat',
            icon: LucideIcons.imagePlay,
            accentColor: AppColors.modeSettings,
            children: [
              _bullet(
                'Photos, GIFs, and other media shared in chat must comply with the same standards as profile photos: no explicit nudity, graphic violence, or content involving minors.',
              ),
              _bullet(
                "Do not share photos or videos of a third party in a conversation without that person's knowledge and consent.",
              ),
              _bullet(
                'Media used to intimidate, blackmail, or humiliate another person is a criminal act - immediate permanent removal and law-enforcement referral will follow.',
              ),
              _bullet(
                'Do not share copyrighted content (music, films, articles) in a way that constitutes infringement.',
              ),
            ],
          ),
          _AccordionSection(
            title: 'Off-Platform Contact',
            icon: LucideIcons.externalLink,
            accentColor: AppColors.primaryTeal,
            children: [
              _bullet(
                'You may choose to exchange contact details - that is your decision. However, Nexus recommends keeping early conversations in-app where safety tools are available.',
              ),
              _bullet(
                "Do not pressure a match to move to another platform before they're ready. Urgent pressure to go off-platform is one of the most common scam and harassment tactics.",
              ),
              _bullet(
                "Once conversation moves off-platform, Nexus's reporting tools no longer apply - but your original report of on-platform conduct remains actionable.",
              ),
              _bullet(
                'Nexus is not responsible for interactions that occur exclusively on external platforms after a match has moved conversation there.',
              ),
            ],
          ),
          _AccordionSection(
            title: 'Date & Meetup Planning Chat',
            icon: LucideIcons.calendarHeart,
            accentColor: AppColors.modeDating,
            children: [
              _bullet(
                "When planning to meet in person, use the in-chat 'Set up a safety check-in' shortcut to configure a Meetup Safety session without leaving the conversation.",
              ),
              _bullet(
                'Sharing a meeting location in chat is natural - but avoid sharing your exact home address, workplace, or other sensitive location until significant trust has been established.',
              ),
              _bullet(
                "If a match is pressuring you to meet faster than you're comfortable with, or insisting on a private location for a first meeting, that is a red flag. Trust your instincts and use our Safety Center.",
              ),
              _bullet(
                'Always confirm a meetup plan before departing. A last-minute change to a remote or private location is a serious red flag that should prompt you to cancel and report.',
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Tab 4: Safety & Privacy ────────────────────────────────────────────────

  Widget _buildSafetyPrivacyTab() {
    return _tabPadding(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Safety & Privacy'),
          _prose(
            "Safety is a first-class feature of Nexus - not a settings footnote. We've built dedicated tools to protect you before, during, and after a meetup. Privacy controls give you granular ownership of your personal data.",
          ),
          const SizedBox(height: 16),
          _buildSafetyToolsCard(),
          const SizedBox(height: 12),
          _AccordionSection(
            title: 'Meetup Safety & Check-ins',
            icon: LucideIcons.mapPinCheck,
            accentColor: AppColors.safetyBlue,
            children: [
              _bullet(
                "Always meet for the first time in a busy, public location - a campus café, a public park, a busy restaurant. Never someone's home, private vehicle, or isolated area.",
              ),
              _bullet(
                "Arrange your own transportation. Do not accept a ride from a match on a first meeting, and do not get into a car with someone you've only just met.",
              ),
              _bullet(
                "Set a Date Check-in before you leave: Settings → Safety Center → Meetup Safety. Configure a timer and trusted contact - if you don't check in, your contact is alerted automatically.",
              ),
              _bullet(
                "Tell a trusted friend or family member where you're going, who you're meeting, and when you expect to return - every time, especially early on.",
              ),
              _bullet(
                'Trust your gut. If something feels wrong before, during, or after a meetup - leave. Your safety matters more than being polite.',
              ),
              _bullet(
                'If you feel unsafe during a meetup, activate SOS from the app. It alerts your trusted contacts with your last known location.',
              ),
            ],
          ),
          _AccordionSection(
            title: 'Emergency SOS & Digital Witness',
            icon: LucideIcons.shieldAlert,
            accentColor: AppColors.safetyBlue,
            children: [
              _bullet(
                'SOS can be triggered from the Safety Center at any time. It immediately notifies your configured trusted contacts with your last known location.',
              ),
              _bullet(
                'Digital Witness, when activated via SOS, records encrypted audio and video footage as a local safety record, stored securely on your device.',
              ),
              _bullet(
                'Digital Witness footage is your private evidence - Nexus does not have access to it. You own it and may share it with authorities if needed.',
              ),
              _bullet(
                'Do not misuse SOS or Digital Witness as a prank, to surveil a match without their knowledge in a non-emergency context, or for any purpose other than genuine personal safety.',
              ),
              _bullet(
                'Crisis Helplines are available from Safety Center - local and national support lines are listed by region for mental health, domestic abuse, and sexual violence support.',
              ),
            ],
          ),
          _AccordionSection(
            title: 'Blocking & Hidden Users',
            icon: LucideIcons.userX,
            accentColor: AppColors.error,
            children: [
              _bullet(
                'You can block any user at any time from their profile or from within a chat. Blocked users cannot see your profile, contact you, or appear in your discovery feed.',
              ),
              _bullet(
                'Blocked users are not notified that they have been blocked.',
              ),
              _bullet(
                'Hidden Users is a separate feature: you can hide a profile from your Orbit discovery feed without fully blocking that person.',
              ),
              _bullet(
                'Blocking or hiding a user does not automatically submit a report. If the person violated guidelines, please also use the Report function so the Trust & Safety team can review.',
              ),
              _bullet(
                "If someone you've blocked creates a new account to contact you, report the new account immediately - ban evasion is treated with extra severity.",
              ),
            ],
          ),
          _AccordionSection(
            title: 'Privacy Controls',
            icon: LucideIcons.lock,
            accentColor: AppColors.primaryTeal,
            children: [
              _bullet(
                'Privacy Settings let you hide specific profile fields - gender, sexuality, pronouns, hometown, current location, religious beliefs, and more - from public view at any time.',
              ),
              _bullet(
                'Special-category data (sexual orientation, religious beliefs, health-related information) is processed under enhanced consent. You must opt in to display these fields and can withdraw consent at any time.',
              ),
              _bullet(
                'Location data used for proximity-based discovery is approximate and never stored as a precise GPS coordinate tied to your profile in the discovery feed.',
              ),
              _bullet(
                "Your profile is only visible in orbits you've enabled. If you disable Dating, you will not appear in any Dating discovery feeds.",
              ),
              _bullet(
                'Data Export: request a full export of your personal data from Settings → Privacy. Nexus will provide it in a machine-readable format within 30 days.',
              ),
              _bullet(
                'Account Deletion: permanently removes your profile, matches, and chat history. Some anonymized data may be retained for safety and legal compliance as described in our Privacy Policy.',
              ),
            ],
          ),
          _AccordionSection(
            title: 'Red Flag Awareness',
            icon: LucideIcons.flag,
            accentColor: AppColors.warning,
            children: [
              _bullet(
                "Profile inconsistencies: photos that don't match the written description, reluctance to video call before meeting, a very new account with only one photo.",
              ),
              _bullet(
                'Love bombing: excessive flattery, declarations of deep feeling very early in conversation, moving unusually fast emotionally.',
              ),
              _bullet(
                "Financial requests: any request for money, gift cards, or 'temporary' financial help - no matter how convincing the story is.",
              ),
              _bullet(
                'Off-platform pressure: urgent requests to move to WhatsApp, Telegram, or other apps very early - often used to escape moderation.',
              ),
              _bullet(
                'Location avoidance: refusing to suggest a public meetup location, or consistently choosing isolated venues.',
              ),
              _bullet(
                'Emergency stories: last-minute dramatic crises used to explain why they need money or cannot meet under the originally agreed terms.',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSafetyToolsCard() {
    final tools = [
      (LucideIcons.mapPin, 'Date Check-in', 'Timer + trusted contact alert'),
      (LucideIcons.siren, 'SOS Alert', 'One-tap emergency notification'),
      (LucideIcons.video, 'Digital Witness', 'Encrypted safety recording'),
      (LucideIcons.phone, 'Crisis Lines', 'Helplines by region'),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0284C7), Color(0xFF0D9488)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0284C7).withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                LucideIcons.shieldCheck,
                size: 16,
                color: Colors.white,
              ),
              const SizedBox(width: 8),
              Text(
                'Your Safety Tools',
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 2.6,
            children: tools.map((t) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(t.$1, size: 14, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            t.$2,
                            style: GoogleFonts.manrope(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            t.$3,
                            style: GoogleFonts.inter(
                              fontSize: 9,
                              color: Colors.white.withValues(alpha: 0.75),
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── Tab 5: Reporting ───────────────────────────────────────────────────────

  Widget _buildReportingTab() {
    return _tabPadding(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Reporting & Trust & Safety'),
          _prose(
            'Our community relies on everyone playing a part. If you see something that violates these guidelines, please report it. Every report is reviewed by a human member of our Trust & Safety team.',
          ),
          const SizedBox(height: 16),
          _AccordionSection(
            title: 'What to Report',
            icon: LucideIcons.flag,
            accentColor: AppColors.warning,
            children: [
              _bullet(
                'Fake or impersonation profiles - catfishing, stolen photos, false identity.',
              ),
              _bullet('Harassment, threats, or abusive messages in chat.'),
              _bullet('Unsolicited explicit or graphic content.'),
              _bullet(
                'Scam attempts - money requests, investment schemes, phishing links.',
              ),
              _bullet('Inappropriate content in profile photos or bio.'),
              _bullet(
                'Underage users - if you believe someone may be under 18, report immediately.',
              ),
              _bullet(
                'Cross-orbit conduct violations - e.g., romantic advances in the Professional Orbit.',
              ),
              _bullet('Illegal content or promotion of illegal activity.'),
              _bullet('Spam accounts or commercial solicitation.'),
            ],
          ),
          _AccordionSection(
            title: 'How to Report',
            icon: LucideIcons.clipboardList,
            accentColor: AppColors.primaryTeal,
            children: [
              _bullet(
                'From any profile card in the Orbit screen: tap the ⋮ menu → Report.',
              ),
              _bullet(
                'From a chat conversation: tap the ⋮ menu in the top-right corner → Report.',
              ),
              _bullet(
                "From a match's full profile view: scroll to the bottom → Report this person.",
              ),
              _bullet(
                'For urgent safety matters, use SOS in the Safety Center - this also alerts your trusted contacts immediately.',
              ),
              _bullet(
                'For complex situations: Settings → Feedback lets you submit a detailed report with additional context or attachments.',
              ),
              _bullet(
                'All reports are anonymous. The reported user will never be told who reported them.',
              ),
            ],
          ),
          _AccordionSection(
            title: 'What Happens After You Report',
            icon: LucideIcons.searchCheck,
            accentColor: AppColors.modeSettings,
            children: [
              _bullet(
                'Every report enters our Trust & Safety queue and is reviewed by a human team member within 24-72 hours for standard reports, and within hours for urgent safety flags.',
              ),
              _bullet(
                'We may ask follow-up questions via the Feedback ticket system - please check your tickets under Settings → Feedback.',
              ),
              _bullet(
                'If a violation is confirmed, enforcement action is taken based on severity (see the Enforcement tab).',
              ),
              _bullet(
                'You will receive a notification when your report has been reviewed and actioned - we believe in closing the loop.',
              ),
              _bullet(
                'If you believe a review decision was incorrect, you may appeal via Settings → Feedback, referencing your original ticket number.',
              ),
              _bullet(
                'Nexus does not tolerate retaliation against users who submit good-faith reports. If targeted after reporting someone, file a separate report immediately.',
              ),
            ],
          ),
          _AccordionSection(
            title: 'False & Malicious Reports',
            icon: LucideIcons.xOctagon,
            accentColor: AppColors.error,
            children: [
              _bullet(
                'Submitting reports you know to be false - to harass, silence, or harm another user - is itself a violation of these guidelines.',
              ),
              _bullet(
                'Coordinated false-reporting campaigns (multiple accounts reporting one user without genuine grounds) will result in all participating accounts being actioned.',
              ),
              _bullet(
                'The Trust & Safety team reviews context carefully. A report is an input, not an automatic action - false reports do not automatically harm the reported user.',
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Tab 6: Enforcement ─────────────────────────────────────────────────────

  Widget _buildEnforcementTab() {
    return _tabPadding(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('How We Enforce These Guidelines'),
          _prose(
            'We believe in proportionate, consistent, and transparent enforcement. Our goal is to keep the community safe - not to punish - but repeat or severe violations are met with decisive action.',
          ),
          const SizedBox(height: 16),
          _buildEnforcementLadderCard(),
          const SizedBox(height: 12),
          _AccordionSection(
            title: 'Warning',
            icon: LucideIcons.alertCircle,
            accentColor: AppColors.warning,
            children: [
              _bullet(
                'Issued for first-time or minor violations - e.g., a slightly misleading bio, a mildly inappropriate but non-threatening message, or minor spam.',
              ),
              _bullet(
                'Warnings are logged against your account. Accumulating warnings escalates your enforcement tier.',
              ),
              _bullet(
                'You will receive an in-app notification explaining what was flagged and which rule was violated.',
              ),
            ],
          ),
          _AccordionSection(
            title: 'Feature Restrictions',
            icon: LucideIcons.lockKeyhole,
            accentColor: AppColors.modeSettings,
            children: [
              _bullet(
                'For moderate violations, specific features may be restricted - e.g., sending messages, sending icebreakers, or appearing in certain orbit discovery feeds.',
              ),
              _bullet(
                'Feature restrictions are time-bound and expire unless further violations occur during the restriction period.',
              ),
              _bullet(
                'Restrictions are applied to give you time to review guidelines and correct behavior without losing your connections entirely.',
              ),
            ],
          ),
          _AccordionSection(
            title: 'Temporary Suspension',
            icon: LucideIcons.pauseCircle,
            accentColor: AppColors.error,
            children: [
              _bullet(
                'Issued for serious violations - harassment campaigns, sharing explicit content without consent, scam attempts, or significant identity misrepresentation.',
              ),
              _bullet(
                'Suspension periods range from 24 hours to 30 days depending on severity and account history.',
              ),
              _bullet(
                'During suspension you cannot access your account. Your matches and conversations are preserved if the suspension is temporary.',
              ),
              _bullet(
                'You will be notified of the reason, duration, and appeals process when a suspension is applied.',
              ),
            ],
          ),
          _AccordionSection(
            title: 'Permanent Ban',
            icon: LucideIcons.ban,
            accentColor: AppColors.error,
            children: [
              _bullet(
                'Reserved for zero-tolerance violations and repeat offenders who demonstrate unwillingness to comply with community standards.',
              ),
              _bullet(
                'Zero-tolerance offenses triggering immediate permanent bans include: sexual content involving minors (CSAM), credible threats of violence, confirmed catfishing of real individuals, confirmed financial fraud, and ban evasion.',
              ),
              _bullet(
                'A permanent ban removes your profile, matches, and messages. Device identifiers are flagged to prevent re-registration.',
              ),
              _bullet(
                'Permanent bans for criminal matters include referral to law enforcement.',
              ),
            ],
          ),
          _AccordionSection(
            title: 'Appeals',
            icon: LucideIcons.messageSquarePlus,
            accentColor: AppColors.primaryTeal,
            children: [
              _bullet(
                'Every enforcement action except immediate permanent bans for zero-tolerance offenses may be appealed within 14 days of the action date.',
              ),
              _bullet(
                'To appeal: Settings → Feedback → New Ticket, referencing your enforcement notification.',
              ),
              _bullet(
                'Appeals are reviewed by a different team member than the original reviewer. We take appeals seriously and review them thoroughly.',
              ),
              _bullet(
                'Appeals do not automatically suspend an enforcement action while being reviewed, unless the case is escalated internally.',
              ),
              _bullet(
                "Nexus's platform decisions on appeals are final - legal remedies remain available per our Terms of Service.",
              ),
            ],
          ),
          _AccordionSection(
            title: 'Law Enforcement Cooperation',
            icon: LucideIcons.scale,
            accentColor: const Color(0xFF475569),
            children: [
              _bullet(
                'Nexus cooperates fully with law enforcement investigations involving criminal activity on the platform, in accordance with applicable law.',
              ),
              _bullet(
                'Where legally required, we will preserve records, disclose account information, and provide evidence to appropriate authorities.',
              ),
              _bullet(
                'We proactively refer cases involving CSAM, credible threats to life, and financial fraud to relevant authorities without waiting for a report.',
              ),
              _bullet(
                "If you believe a crime has been committed, please also contact local law enforcement directly - Nexus's report system supplements but does not replace emergency services.",
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEnforcementLadderCard() {
    const steps = [
      (AppColors.warning, 'Warning', 'Minor / first-time'),
      (AppColors.modeSettings, 'Feature Limit', 'Moderate violation'),
      (Color(0xFFEF4444), 'Suspension', 'Serious violation'),
      (Color(0xFF7F1D1D), 'Permanent Ban', 'Zero-tolerance'),
    ];

    const icons = [
      LucideIcons.alertCircle,
      LucideIcons.lockKeyhole,
      LucideIcons.pauseCircle,
      LucideIcons.ban,
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Enforcement Ladder',
            style: GoogleFonts.manrope(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: List.generate(steps.length * 2 - 1, (i) {
              if (i.isOdd) {
                return const Expanded(
                  child: SizedBox(
                    height: 2,
                    child: ColoredBox(color: Color(0xFFE2E8F0)),
                  ),
                );
              }
              final idx = i ~/ 2;
              final step = steps[idx];
              return Column(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: step.$1.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                      border: Border.all(color: step.$1.withValues(alpha: 0.4)),
                    ),
                    child: Icon(icons[idx], size: 16, color: step.$1),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: 70,
                    child: Text(
                      step.$2,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.manrope(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: step.$1,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 70,
                    child: Text(
                      step.$3,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 8.5,
                        color: const Color(0xFF94A3B8),
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  // ── Safety Pledge Card ─────────────────────────────────────────────────────

  Widget _buildSafetyPledgeCard() {
    return Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _pledgeSigned ? const Color(0xFFF0FDF4) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _pledgeSigned
                  ? const Color(0xFFBBF7D0)
                  : const Color(0xFFE2E8F0),
              width: _pledgeSigned ? 1.5 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: _pledgeSigned
                    ? const Color(0xFF10B981).withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.02),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _pledgeSigned
                          ? const Color(0xFF10B981).withValues(alpha: 0.15)
                          : AppColors.pulsarPink.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _pledgeSigned
                          ? LucideIcons.badgeCheck
                          : LucideIcons.heartHandshake,
                      color: _pledgeSigned
                          ? const Color(0xFF10B981)
                          : AppColors.pulsarPink,
                      size: 28,
                    ),
                  )
                  .animate(target: _pledgeSigned ? 1 : 0)
                  .scale(
                    begin: const Offset(1, 1),
                    end: const Offset(1.15, 1.15),
                    duration: 200.ms,
                    curve: Curves.easeOutBack,
                  ),
              const SizedBox(height: 14),
              Text(
                _pledgeSigned ? 'Thank You, Star!' : 'Take the Safety Pledge',
                style: GoogleFonts.manrope(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _pledgeSigned
                    ? "You've committed to keeping our constellation safe, authentic, and respectful. Every pledge makes Nexus better for everyone in the galaxy."
                    : 'I commit to treating every person in this constellation with authenticity, respect, and care - in orbit, in chat, and in real life.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  color: AppColors.inkMuted,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 18),
              ScalePressable(
                onTap: () async {
                  setState(() => _pledgeSigned = !_pledgeSigned);
                  await _savePledgeState(_pledgeSigned);
                  if (_pledgeSigned && mounted) {
                    NexusToast.show(
                      context,
                      'Pledge Signed! Thank you for keeping Nexus safe. 🌌',
                    );
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: double.infinity,
                  height: 50,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: _pledgeSigned
                        ? const LinearGradient(
                            colors: [Color(0xFF10B981), Color(0xFF059669)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : const LinearGradient(
                            colors: [AppColors.pulsarPink, Color(0xFFE04B76)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                    boxShadow: [
                      BoxShadow(
                        color:
                            (_pledgeSigned
                                    ? const Color(0xFF10B981)
                                    : AppColors.pulsarPink)
                                .withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _pledgeSigned ? LucideIcons.check : LucideIcons.star,
                        size: 16,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _pledgeSigned
                            ? 'PLEDGE SIGNED'
                            : 'I PLEDGE TO KEEP NEXUS SAFE',
                        style: GoogleFonts.manrope(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        )
        .animate()
        .fadeIn(delay: 200.ms, duration: 400.ms)
        .slideY(begin: 0.05, end: 0, duration: 400.ms);
  }

  // ── Footer ─────────────────────────────────────────────────────────────────

  Widget _buildFooterNote() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 12),
      child: Column(
        children: [
          const Icon(LucideIcons.sparkles, color: Color(0xFFCBD5E1), size: 20)
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .scale(
                begin: const Offset(0.95, 0.95),
                end: const Offset(1.05, 1.05),
                duration: 2000.ms,
                curve: Curves.easeInOut,
              ),
          const SizedBox(height: 10),
          Text(
            'Nexus Trust & Safety Standards',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'These guidelines are enforced consistently and evolve with our community. Violations can result in immediate loss of account access. For questions, visit Settings → Help Center.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: AppColors.inkMuted,
              height: 1.45,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 300.ms, duration: 400.ms);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _tabPadding(Widget child) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: child,
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF94A3B8),
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _prose(String text) {
    return Text(
      text,
      style: GoogleFonts.inter(
        fontSize: 12.5,
        color: const Color(0xFF475569),
        height: 1.55,
      ),
    );
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Icon(Icons.circle, size: 4, color: AppColors.primaryTeal),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                color: const Color(0xFF475569),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Data models
// ---------------------------------------------------------------------------

class _TabMeta {
  const _TabMeta(this.label, this.icon, this.color, this.subtitle);

  final String label;
  final IconData icon;
  final Color color;
  final String subtitle;
}

// ---------------------------------------------------------------------------
// Accordion Section
// ---------------------------------------------------------------------------

class _AccordionSection extends StatefulWidget {
  const _AccordionSection({
    required this.title,
    required this.icon,
    required this.accentColor,
    required this.children,
  });

  final String title;
  final IconData icon;
  final Color accentColor;
  final List<Widget> children;

  @override
  State<_AccordionSection> createState() => _AccordionSectionState();
}

class _AccordionSectionState extends State<_AccordionSection> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isExpanded
              ? widget.accentColor.withValues(alpha: 0.3)
              : const Color(0xFFE2E8F0),
          width: _isExpanded ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: _isExpanded
                ? widget.accentColor.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => setState(() => _isExpanded = !_isExpanded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: widget.accentColor.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          widget.icon,
                          color: widget.accentColor,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.title,
                          style: GoogleFonts.manrope(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      AnimatedRotation(
                        turns: _isExpanded ? 0.25 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          LucideIcons.chevronRight,
                          size: 15,
                          color: _isExpanded
                              ? widget.accentColor
                              : const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Divider(
                      height: 1,
                      color: widget.accentColor.withValues(alpha: 0.15),
                    ),
                    const SizedBox(height: 10),
                    ...widget.children,
                  ],
                ),
              ),
              crossFadeState: _isExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 220),
            ),
          ],
        ),
      ),
    );
  }
}
