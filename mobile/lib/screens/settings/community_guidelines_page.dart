import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/theme/app_colors.dart';
import 'package:nexus/widgets/nexus_toast.dart';
import 'package:nexus/widgets/scale_pressable.dart';

class CommunityGuidelinesPage extends StatefulWidget {
  const CommunityGuidelinesPage({super.key});

  @override
  State<CommunityGuidelinesPage> createState() =>
      _CommunityGuidelinesPageState();
}

class _CommunityGuidelinesPageState extends State<CommunityGuidelinesPage> {
  static const Color _gradientStart = AppColors.modeSettings; // #4EA8DE
  static const Color _gradientEnd = AppColors.primaryTeal; // #0891B2

  int _selectedTab = 0; // 0: Orbits, 1: Features, 2: Code of Conduct
  bool _pledgeSigned = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: _buildAppBar(),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 60),
        children: [
          _buildHeroHeader(),
          _buildTabSelector(),
          const SizedBox(height: 16),
          _buildActiveTabContent(),
          const SizedBox(height: 24),
          _buildSafetyPledgeCard(),
          _buildFooterNote(),
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
            colors: [_gradientStart, _gradientEnd],
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

  Widget _buildHeroHeader() {
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
                      'Respecting the Space',
                      style: GoogleFonts.manrope(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Welcome to Nexus. To keep our campus and general galaxy safe, friendly, and authentic, please follow our guidelines below.',
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
                width: 72,
                height: 72,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    ..._buildBreathingRings(),
                    Container(
                          padding: const EdgeInsets.all(12),
                          decoration: const BoxDecoration(
                            color: Color(0xFFD1FAE5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            LucideIcons.bookOpen,
                            color: AppColors.safetyTeal,
                            size: 30,
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

  List<Widget> _buildBreathingRings() {
    return List.generate(2, (i) {
      return Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.safetyTeal.withValues(alpha: 0.25),
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

  Widget _buildTabSelector() {
    final tabs = ['Orbits', 'Features', 'Code of Conduct'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        height: 48,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFE2E8F0),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: List.generate(tabs.length, (index) {
            final active = _selectedTab == index;
            return Expanded(
              child: ScalePressable(
                onTap: () => setState(() => _selectedTab = index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  decoration: BoxDecoration(
                    color: active ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: active
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    tabs[index],
                    style: GoogleFonts.manrope(
                      fontSize: 12.5,
                      fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                      color: active
                          ? const Color(0xFF0F172A)
                          : const Color(0xFF64748B),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    ).animate().fadeIn(delay: 100.ms, duration: 350.ms);
  }

  Widget _buildActiveTabContent() {
    switch (_selectedTab) {
      case 0:
        return _buildOrbitsTab();
      case 1:
        return _buildFeaturesTab();
      case 2:
        return _buildConductTab();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildOrbitsTab() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          _AccordionSection(
            title: 'Dating Orbit - Romantic Connections',
            icon: LucideIcons.heart,
            accentColor: AppColors.modeDating,
            children: [
              _buildBulletPoint(
                'Consent is Paramount: Always respect boundaries, physical comfort levels, and preferences. "No" means no, at any stage.',
              ),
              _buildBulletPoint(
                'Clear Intention: Be honest about who you are and what you seek. Authentic communication prevents misunderstandings.',
              ),
              _buildBulletPoint(
                'Zero Harassment: Intimidation, unsolicited explicit media, stalking, or inappropriate comments will lead to a permanent ban.',
              ),
              _buildBulletPoint(
                'Safety Alert Check-ins: Before meeting offline, set up a Safety Check-in with a trusted contact from the Settings menu.',
              ),
            ],
          ),
          _AccordionSection(
            title: 'Friends Orbit - Platonic Friendships',
            icon: LucideIcons.users,
            accentColor: AppColors.modeFriends,
            children: [
              _buildBulletPoint(
                'Strictly Platonic: This space is built for finding activity partners, study groups, and new friends. Do not make unwanted romantic advances.',
              ),
              _buildBulletPoint(
                'Respect Differences: Keep an open mind and appreciate various music tastes, courses, backgrounds, and lifestyles.',
              ),
              _buildBulletPoint(
                'No Commercial Spam: Sharing referral links, selling tickets, or promoting products is forbidden here. Keep friendships authentic.',
              ),
            ],
          ),
          _AccordionSection(
            title: 'Professional Orbit - Mentorship & Career',
            icon: LucideIcons.briefcase,
            accentColor: AppColors.modeProfessional,
            children: [
              _buildBulletPoint(
                'Strict No-Romance Rule: Under no circumstances should this orbit be used for dating advances. Inappropriate advances here result in immediate ban.',
              ),
              _buildBulletPoint(
                'Verified and Authentic: Present your true academic credentials, job details, skills, and goals. Misrepresentation degrades trust.',
              ),
              _buildBulletPoint(
                'Respect and Nurture: Maintain professional messaging etiquette. Support peers seeking advice, job referrals, or mentorship.',
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms);
  }

  Widget _buildFeaturesTab() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          _AccordionSection(
            title: 'Spotify Integration & Gravity Pull',
            icon: LucideIcons.music,
            accentColor: const Color(0xFF1DB954), // Spotify Green
            children: [
              _buildBulletPoint(
                'Authentic Representation: Let your actual music taste construct your orbit coordinates. Do not use automation tools to fake compatibility.',
              ),
              _buildBulletPoint(
                'Zero Judgment: Diverse tastes build a vibrant galaxy. Respect others regardless of what they listen to.',
              ),
            ],
          ),
          _AccordionSection(
            title: 'Stardust Messages (Icebreakers)',
            icon: LucideIcons.sparkles,
            accentColor: AppColors.pulsarPink,
            children: [
              _buildBulletPoint(
                'Warm & Contextual: Craft thoughtful opening messages. Personalized icebreakers are more pleasant and set a great tone.',
              ),
              _buildBulletPoint(
                'No Copypasta & Spam: Sending the same generic or commercial message to dozens of orbits diminishes the platform experience.',
              ),
              _buildBulletPoint(
                'Polite Delivery: First impressions matter. Maintain a respectful tone in your stardust messages.',
              ),
            ],
          ),
          _AccordionSection(
            title: 'Meetup Safety & Emergency SOS',
            icon: LucideIcons.shieldAlert,
            accentColor: AppColors.safetyBlue,
            children: [
              _buildBulletPoint(
                'Always Meet in Public: For the first few meetings, always choose busy public locations (cafes, campus courtyards).',
              ),
              _buildBulletPoint(
                'Transportation Control: Arrange your own rides. Do not let matches pick you up from your residence on a first meeting.',
              ),
              _buildBulletPoint(
                'Pre-arrange Check-ins: Configure your Trusted Contacts. Set a check-in timer so your location can be securely verified if you go unreachable.',
              ),
              _buildBulletPoint(
                'SOS & Digital Witness: If you ever feel unsafe, trigger the SOS. Silent SOS activates Digital Witness to log encrypted audio/video footage for safety records.',
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms);
  }

  Widget _buildConductTab() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Code of Conduct',
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 12),
                _buildDoDontHeader(),
                const SizedBox(height: 16),
                _buildDoRow(
                  'Be Authentic',
                  'Verify your profile and represent your actual personality and interests.',
                ),
                const Divider(height: 20, color: Color(0xFFF1F5F9)),
                _buildDoRow(
                  'Communicate Boundaries',
                  "Clearly state your preferences and respect other users' boundaries.",
                ),
                const Divider(height: 20, color: Color(0xFFF1F5F9)),
                _buildDoRow(
                  'Report Abuse',
                  'Immediately block/report harassment, scams, or catfishing via the settings tab.',
                ),
                const Divider(height: 20, color: Color(0xFFF1F5F9)),
                _buildDontRow(
                  'Spam or Sell',
                  'Do not advertise commercial services, events, or sell merchandise.',
                ),
                const Divider(height: 20, color: Color(0xFFF1F5F9)),
                _buildDontRow(
                  'Catfish or Fake',
                  'Impersonating campus students or using fake profile photos results in a permanent ban.',
                ),
                const Divider(height: 20, color: Color(0xFFF1F5F9)),
                _buildDontRow(
                  'Make Dating Moves in Professional',
                  'Keep networking professional. Zero tolerance for professional boundary violations.',
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms);
  }

  Widget _buildDoDontHeader() {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              'DO',
              style: GoogleFonts.manrope(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF065F46),
                letterSpacing: 1,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              "DON'T",
              style: GoogleFonts.manrope(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF991B1B),
                letterSpacing: 1,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDoRow(String title, String desc) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          LucideIcons.checkCircle2,
          color: AppColors.success,
          size: 16,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  color: const Color(0xFF64748B),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDontRow(String title, String desc) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(LucideIcons.xCircle, color: AppColors.error, size: 16),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  color: const Color(0xFF64748B),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBulletPoint(String text) {
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
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

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
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        padding: const EdgeInsets.all(10),
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
                          size: 24,
                        ),
                      )
                      .animate(target: _pledgeSigned ? 1 : 0)
                      .scale(
                        begin: const Offset(1, 1),
                        end: const Offset(1.15, 1.15),
                        duration: 200.ms,
                        curve: Curves.easeOutBack,
                      ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                _pledgeSigned ? 'Thank You!' : 'Take the Safety Pledge',
                style: GoogleFonts.manrope(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _pledgeSigned
                    ? 'You have committed to keeping our community safe and respectful. Together, we build a trusted galaxy.'
                    : 'Join our constellation of respectful users. Commit to treating fellow community members with safety, authenticity, and respect.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  color: const Color(0xFF64748B),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              ScalePressable(
                onTap: () {
                  setState(() => _pledgeSigned = !_pledgeSigned);
                  if (_pledgeSigned) {
                    NexusToast.show(
                      context,
                      'Pledge Signed! Thank you for keeping Nexus safe. 🌌',
                    );
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: double.infinity,
                  height: 46,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
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
                                .withValues(alpha: 0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _pledgeSigned
                        ? 'PLEDGE SIGNED ✓'
                        : 'I PLEDGE TO KEEP NEXUS SAFE',
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 0.8,
                    ),
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

  Widget _buildFooterNote() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 12),
      child: Column(
        children: [
          const Icon(
                LucideIcons.sparkles,
                color: Color(0xFFCBD5E1),
                size: 20,
              )
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
            'Violating these guidelines can result in immediate loss of account access. Play safe, be authentic, explore wisely.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: const Color(0xFF64748B),
              height: 1.4,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 300.ms, duration: 400.ms);
  }
}

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
      margin: const EdgeInsets.only(bottom: 12),
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
            color: Colors.black.withValues(alpha: 0.02),
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
                    vertical: 16,
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
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.title,
                          style: GoogleFonts.manrope(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      AnimatedRotation(
                        turns: _isExpanded ? 0.25 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(
                          LucideIcons.chevronRight,
                          size: 16,
                          color: Color(0xFF94A3B8),
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
                    const Divider(height: 1, color: Color(0xFFF1F5F9)),
                    const SizedBox(height: 12),
                    ...widget.children,
                  ],
                ),
              ),
              crossFadeState: _isExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
            ),
          ],
        ),
      ),
    );
  }
}
