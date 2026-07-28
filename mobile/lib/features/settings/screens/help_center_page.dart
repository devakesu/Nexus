import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/core/theme/app_colors.dart';
import 'package:nexus/core/widgets/scale_pressable.dart';
import 'package:url_launcher/url_launcher.dart';

const _kGithubIssuesUrl = 'https://github.com/devakesu/Nexus/issues';

typedef _Faq = ({String question, String answer});

class _HelpCategory {
  const _HelpCategory({
    required this.title,
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.faqs,
  });

  final String title;
  final IconData icon;
  final Color color;
  final Color bgColor;
  final List<_Faq> faqs;
}

typedef _RoadmapItem = ({IconData icon, String title, String desc});

const List<_HelpCategory> _kHelpCategories = [
  _HelpCategory(
    title: 'Getting Started',
    icon: LucideIcons.rocket,
    color: AppColors.safetyBlue,
    bgColor: Color(0xFFEFF6FF),
    faqs: [
      (
        question: 'What is Nexus?',
        answer:
            'Nexus brings three ways to connect into one app - Dating, Friends, and Professional - all built around a single profile. Switch tabs any time; who you meet changes, but your profile stays yours.',
      ),
      (
        question: 'How do I set up my profile?',
        answer:
            "During onboarding you'll pick your display name, age, and demographic bucket (for the main Nexus app) or your major/branch and study year (for Nexus MEC). You'll also verify your phone number with an OTP. After onboarding, you can fill in your bio, location, lifestyle details, interests, and linked Spotify artists from the Profile tab at any time.",
      ),
      (
        question:
            'Can Dating, Friends, and Professional all be active at once?',
        answer:
            'Yes. Each context has its own activation toggle, so you can be discoverable for Dating and Professional networking at the same time, or focus on just one - entirely up to you.',
      ),
      (
        question: "What's Nexus MEC?",
        answer:
            'Nexus MEC is our campus-community flavor. It verifies you with a campus Google Workspace email (only approved institutional domains can sign in) and lets you export your profile to the main Nexus app via a one-time code - built for closed university communities.',
      ),
      (
        question:
            'How do I move my profile from Nexus MEC to the main Nexus app?',
        answer:
            "From your Nexus MEC Profile tab, tap the Export Profile Data card to generate a 6-character code - it's valid for 15 minutes and works only once. Enter that code during onboarding in the main Nexus app to pull your profile across.",
      ),
      (
        question: 'What is a Demographic Bucket?',
        answer:
            "On the main Nexus app, you pick a demographic bucket during onboarding - it's your primary community identification (e.g. Men, Women, Non-Binary). This helps surface you to the right people without exposing personal details. You can update it later from your Profile tab.",
      ),
    ],
  ),
  _HelpCategory(
    title: 'Orbit & Discovery',
    icon: LucideIcons.orbit,
    color: Color(0xFF7C3AED),
    bgColor: Color(0xFFF5F3FF),
    faqs: [
      (
        question: 'What is Orbit?',
        answer:
            'Orbit is our discovery screen - instead of a flat swipe stack, potential matches appear as nodes arranged in concentric tiers around you, positioned by how closely you match. Open it from the Dating, Friends, or Professional tab.',
      ),
      (
        question: 'Why do the tiers matter?',
        answer:
            'Closer tiers generally mean a stronger match on shared interests, preferences, and activity - so you can prioritize who to check out first, without losing the rest of the field.',
      ),
      (
        question: 'Can I filter who shows up in my Orbit?',
        answer:
            'Yes - each Orbit has its own filters panel, so you can fine-tune preferences separately for Dating, Friends, and Professional.',
      ),
      (
        question: 'Why does my Orbit look empty?',
        answer:
            "Make sure the relevant Orbit is activated and matching isn't paused (Settings → Pause Matching), check your connection, and try pulling down to refresh - new profiles roll in continuously.",
      ),
      (
        question: "Why is my Orbit's age filter capped at a different number?",
        answer:
            "It depends on which Nexus app you're using - the main Nexus app lets you filter ages up to 80, while Nexus MEC (our campus flavor) caps it at 27 to match its university-community focus.",
      ),
      (
        question: 'How do I activate or deactivate an Orbit?',
        answer:
            "Each mode tab (Dating, Friends, Professional) has its own activation toggle at the top. You can also deactivate all three at once using Pause Matching in Settings. To resume after pausing, open any mode tab and activate its Orbit individually - there's no single 'resume all' button.",
      ),
    ],
  ),
  _HelpCategory(
    title: 'Messaging & Chat',
    icon: LucideIcons.messageSquareLock,
    color: AppColors.safetyTeal,
    bgColor: Color(0xFFECFDF5),
    faqs: [
      (
        question: 'Are my chats actually private?',
        answer:
            "Yes - every conversation on Nexus is end-to-end encrypted using the Signal Protocol, the same technology behind Signal's encrypted messaging. Only you and the other person can ever read what's sent.",
      ),
      (
        question: 'Can I send more than text?',
        answer:
            'You can share photos and voice notes, both encrypted the same way as your messages.',
      ),
      (
        question: 'What are chat events?',
        answer:
            'Chat events let you schedule a meetup right inside a conversation, with optional location sharing and reminders - handy for planning a first coffee or call.',
      ),
      (
        question: "Do people know when I've read their message?",
        answer:
            "Read receipts and presence indicators (online / last active) show when enabled - you're always in control of what's visible from your Privacy Settings.",
      ),
      (
        question: 'Why can I only message someone after matching?',
        answer:
            'You need a mutual match (both of you liking each other) to start a conversation. This keeps your inbox focused and prevents unwanted messages.',
      ),
    ],
  ),
  _HelpCategory(
    title: 'Profile & Photos',
    icon: LucideIcons.userRound,
    color: Color(0xFFE11D48),
    bgColor: Color(0xFFFFF1F2),
    faqs: [
      (
        question: 'How do I edit my profile?',
        answer:
            'Open the Profile tab to update your display name, age, bio, gender, sexuality, pronouns, location, lifestyle details (drinking, smoking, children plans, religious beliefs), interests, causes, pets, languages, and linked Spotify artists. Each section saves individually when you close or confirm it.',
      ),
      (
        question: "What's the AI photo tool?",
        answer:
            'Built into your Profile tab, it offers AI-assisted suggestions to help you pick and style your best profile photos.',
      ),
      (
        question: 'How many photos can I add?',
        answer:
            'You can upload up to 5 photos: 1 primary profile picture and 4 gallery slots. Your profile picture is the first thing other users see in Orbit.',
      ),
      (
        question: 'How does photo verification work?',
        answer:
            "It's on our roadmap, not live yet - the plan is a quick live selfie scan matched against your profile photos, earning you a blue verified badge plus ongoing duplicate and deepfake scans once it ships. We'll let you know the moment it's live.",
      ),
      (
        question: 'Can I hide specific profile fields from others?',
        answer:
            'Yes - Settings → Privacy Settings lets you individually toggle visibility for: Gender, Sexuality, Pronouns, Hometown, Current Place, Major/Branch, Religious Beliefs, Pets, Top Artists, and Causes Supported. You can also control whether others see your active status and read receipts.',
      ),
      (
        question: 'How often can I change my age?',
        answer:
            "Age can be changed twice within a rolling 365-day window - the value you set during onboarding counts as the first change. Once both are used, the change sheet shows the exact date you're next eligible. Need it sooner? File a ticket via Settings → Help, Feedback & Bug Report to request an exception.",
      ),
      (
        question: 'How often can I change my display name?',
        answer:
            "You get 2 name changes every rolling 365-day window, and the name set at registration counts as the first change. Once both are used, the sheet shows when you can change it again. Names can't contain numbers, titles (e.g. Dr.), or offensive language. Need it sooner? File a ticket via Settings → Help, Feedback & Bug Report.",
      ),
      (
        question: 'Why is my sexuality or religious beliefs field locked?',
        answer:
            'These are special-category (sensitive) fields. You need to grant explicit consent to store and display them. If the field appears locked or empty, look for the consent prompt when you tap it - granting consent unlocks the field for the current session.',
      ),
    ],
  ),
  _HelpCategory(
    title: 'Privacy & Safety',
    icon: LucideIcons.shieldCheck,
    color: AppColors.primaryTeal,
    bgColor: Color(0xFFECFEFF),
    faqs: [
      (
        question: 'How is my data protected?',
        answer:
            'Your session and sensitive profile fields are encrypted both at rest and in transit, with strong field-level encryption for particularly sensitive data (sexuality, religious beliefs). Messages are end-to-end encrypted and never stored on our servers.',
      ),
      (
        question: "What's in the Safety Center?",
        answer:
            'A full safety hub - a personal safety score checklist, red-flag awareness cards, an interactive safety quiz, meetup safety tools (trusted contacts and check-ins), crisis helpline resources, and links to Privacy Settings, Blocked/Hidden users, and reporting.',
      ),
      (
        question: 'What are the Community Guidelines?',
        answer:
            "Our Community Guidelines are live and browsable inside the app - Settings → Community Guidelines. They cover what's allowed, what isn't, and what happens when rules are broken.",
      ),
      (
        question: 'How do I block, hide, or report someone?',
        answer:
            'From any profile or chat, one tap blocks, hides, or reports them. Blocking removes them from your matches and Orbit permanently. Hiding removes them from your Orbit without affecting their visibility to others. You can manage blocked and hidden users from Settings → Blocked Users / Hidden Users.',
      ),
      (
        question: 'What happens after I report someone?',
        answer:
            "Our Trust & Safety team reviews every report, 24/7. It's completely confidential - the reported user is never told who reported them.",
      ),
      (
        question: 'Why does my report need more detail when I choose "Other"?',
        answer:
            'When "Other" is selected, the details field needs a valid reason (min. 5 letters) before Report & Block unlocks - just enough for our Trust & Safety team to have something to go on. You can add up to 200 characters if you want to explain further.',
      ),
      (
        question: 'Where do I find Safety Check-in and SOS/Emergency tools?',
        answer:
            'They live in their own section below - Safety Check-In & Emergency Alerts - covering meetup check-ins, trusted contacts, and exactly what SOS does. You can also open the same tools from Safety Center → Meetup Safety Alert.',
      ),
    ],
  ),
  _HelpCategory(
    title: 'Safety Check-In & Emergency Alerts',
    icon: LucideIcons.shieldAlert,
    color: Color(0xFFDC2626),
    bgColor: Color(0xFFFEF2F2),
    faqs: [
      (
        question: 'What is a Safety Check-in, and when should I use it?',
        answer:
            "A Safety Check-in - called Meetup Safety Alert in the Safety Center - keeps you accountable during a date or meetup. Pick a check-in interval (15 / 30 / 60 / 120 minutes) and an optional label, like Coffee with Jordan at Bloom Cafe, so your trusted contacts have context if anything's ever sent to them. You'll need at least one trusted contact on file before you can start one.",
      ),
      (
        question:
            'How many trusted contacts can I add, and do they get notified right away?',
        answer:
            "You can add up to 3, typed in manually or picked from your address book - and adding someone doesn't notify them. They only hear from Nexus the moment a real alert actually fires, and that message includes a link where they can verify their own phone number to view your session's live status, last known location, and any evidence clips - no Nexus account needed on their end.",
      ),
      (
        question: 'What happens if I miss a check-in?',
        answer:
            "If you don't check in within about 5 minutes of your scheduled time, Nexus texts your trusted contacts that you're unreachable - including your last known battery level, connection type, and the meetup label if you set one - plus a link they can tap to cancel the alert themselves, no account needed. This repeats up to 3 times, spaced by your check-in interval, until you check in or a contact cancels it.",
      ),
      (
        question:
            "What does SOS actually do, and what's the difference between Silent and Loud?",
        answer:
            "Both give you a 5-second window to cancel, then grab your location if it's available and text every trusted contact an emergency alert with a map link, the meetup label if any, and a nudge to consider contacting local authorities. Loud SOS plays a full-volume alarm with a one-tap Stop Alarm & Call 112 button; Silent SOS instead starts Digital Witness, a visible on-screen recording, with no sound at all. Either way, Nexus only texts your own trusted contacts - it doesn't call the police or alert a Nexus safety team for you, so Call 112 is always a separate, manual tap.",
      ),
      (
        question: 'What is Digital Witness, and is that recording private?',
        answer:
            "Digital Witness is Silent SOS's camera-and-mic recording - always visible on your screen while it runs, by design, so it's never a secret recording. Segments are encrypted and access-controlled, but unlike your end-to-end encrypted chats, the decryption key isn't held solely on your device, so treat it as protected rather than as airtight-private as a message only you and your match can read. If your camera or mic isn't available, Silent SOS still sends the alert text - you'll just be missing the footage.",
      ),
      (
        question:
            'Does a Safety Check-in or SOS track my location the whole time?',
        answer:
            "No - Nexus doesn't run continuous background location tracking. The only moment it captures your location is if you trigger SOS, and even then it's best-effort: if location access isn't available at that moment, the alert still goes out to your trusted contacts, just without a map link.",
      ),
      (
        question: 'Will the check-in alert always wake up my phone?',
        answer:
            "We do our best, but it isn't a guaranteed alarm, especially on iOS. On iPhone the reminder is a Time-Sensitive notification that can break through Focus and silent mode, but you'll still need to tap it open; on Android, make sure to grant the lock-screen and full-screen-alert permissions the app asks for, or you may only see it after you've already unlocked your phone.",
      ),
      (
        question: 'How long does Nexus keep my check-in and SOS data?',
        answer:
            "Safety Check-in, SOS, and Digital Witness data isn't tied to the normal account-deletion timeline - even after your account is deleted, we keep it a little longer in case it's ever needed for a safety investigation, then remove it permanently.",
      ),
    ],
  ),
  _HelpCategory(
    title: 'Account & Data',
    icon: LucideIcons.userCog,
    color: Color(0xFF475569),
    bgColor: Color(0xFFF1F5F9),
    faqs: [
      (
        question: 'How do I sign out?',
        answer:
            'Settings → Account Actions (at the bottom of Settings) → Sign Out. This also securely clears your local encryption keys from the device.',
      ),
      (
        question: 'Can I delete my account?',
        answer:
            "Settings → Account Actions → Delete Account. You'll be asked to type DELETE and verify via an email OTP before the request is submitted. You're signed out immediately and hidden from Orbit, but you have a grace period (shown on the deletion screen) to log back in and cancel. After that, your account is permanently anonymized.",
      ),
      (
        question: 'How do I export my data?',
        answer:
            "Settings → Account Actions → Export My Data. After an email OTP verification, your data is packaged as a JSON file and handed to your device's native share/save sheet. The export includes your profile details, match history, chat metadata, safety sessions, and support tickets - but not message contents (end-to-end encrypted and never stored on our servers).",
      ),
      (
        question: 'How do I manage push notifications?',
        answer:
            "Settings → Notifications → Push Notifications. If permissions are denied, a dialog will guide you to your device's notification settings for Nexus.",
      ),
      (
        question: 'How do I manage email notifications?',
        answer:
            'Settings → Notifications → Email Notifications. You can independently toggle: New Matches & Likes, New Messages, Weekly Activity Digest, Product News & Updates, and Promotions & Offers.',
      ),
      (
        question: 'How do I pause my visibility without deleting anything?',
        answer:
            "Settings → Privacy & Safety → Pause Matching deactivates all three Orbits at once, making you invisible to discovery. You can still chat with people you've already matched with. To resume, activate individual Orbits from their respective tabs - there is no single 'resume all' shortcut.",
      ),
      (
        question: 'How do I manage blocked or hidden users?',
        answer:
            "Settings → Privacy & Safety → Blocked Users shows everyone you've blocked, with the option to unblock. Settings → Privacy & Safety → Hidden Users shows everyone you've hidden from your Orbit.",
      ),
    ],
  ),
  _HelpCategory(
    title: 'Troubleshooting',
    icon: LucideIcons.wrench,
    color: Color(0xFFD97706),
    bgColor: Color(0xFFFFFBEB),
    faqs: [
      (
        question: "Orbit won't load any profiles.",
        answer:
            'Check your connection, confirm at least one Orbit is activated and matching is not paused (Settings → Pause Matching), and try pulling down to refresh. If the problem persists, force-close and reopen the app.',
      ),
      (
        question: "I'm not getting notifications.",
        answer:
            'Settings → Notifications → Push Notifications to check your permission status. If it shows Disabled, tap it to open a dialog guiding you to your device settings. Also check that Do Not Disturb / Focus Mode is not blocking the app.',
      ),
      (
        question: "A photo isn't uploading.",
        answer:
            'Usually a connection hiccup or an oversized image - try again on Wi-Fi, or crop/resize the image first. Make sure the app has camera and photo library permissions in your device settings. Still stuck? Contact support below.',
      ),
      (
        question: 'The app is slow or keeps closing.',
        answer:
            "Force close and reopen the app, and make sure you're on the latest version from the App Store or Play Store - most stability issues are fixed in updates.",
      ),
      (
        question: 'I see a "Session expired" or login error.',
        answer:
            'Your session token has expired or been revoked. Sign out from Settings → Account Actions → Sign Out, then sign back in. If you see this repeatedly, check your internet connection.',
      ),
      (
        question: "My profile changes aren't saving.",
        answer:
            'Each profile section saves automatically when you close it or tap the confirm button. If a save fails, a toast message will appear. Make sure you have a stable connection and try again. If a field like sexuality or religious beliefs appears locked, you may need to grant special-category consent first.',
      ),
      (
        question: 'The export code for Nexus MEC is not working.',
        answer:
            "Export codes are valid for 15 minutes and can only be used once. If yours expired, open your Nexus MEC Profile tab and tap Generate Export Code again to get a new one. Make sure you're entering it in the main Nexus app during onboarding, not in Nexus MEC itself.",
      ),
      (
        question: "I can't change my age or display name.",
        answer:
            "Both are limited to 2 changes per rolling 365-day window, and the values set at registration count as the first change. If you've used both, the change sheet shows the exact date you're next eligible. For urgent corrections, file a ticket via Settings → Help, Feedback & Bug Report.",
      ),
    ],
  ),
];

const List<_RoadmapItem> _kRoadmapItems = [
  (
    icon: LucideIcons.sparkles,
    title: 'Nexus+',
    desc:
        'Premium features including Gravity Pull (music-based orbit alignment), Stardust Messages (icebreaker shooting stars), Dark Nebula (invisible browsing), Retrograde (undo last action), Chroma Orbit (custom profile aesthetics), and a Verified Badge.',
  ),
  (
    icon: LucideIcons.link,
    title: 'Linked Accounts',
    desc: 'Connect Instagram and other platforms to enrich your profile.',
  ),
  (
    icon: LucideIcons.badgeCheck,
    title: 'Photo Verification',
    desc:
        "A live selfie scan and blue verified badge to confirm it's really you.",
  ),
];

class HelpCenterPage extends StatefulWidget {
  const HelpCenterPage({super.key});

  @override
  State<HelpCenterPage> createState() => _HelpCenterPageState();
}

class _HelpCenterPageState extends State<HelpCenterPage> {
  static const _gradientStart = Color(0xFF4F46E5);
  static const _gradientEnd = Color(0xFF7C3AED);

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  String _query = '';

  final GlobalKey _contactKey = GlobalKey();
  late final List<GlobalKey> _categoryKeys = List.generate(
    _kHelpCategories.length,
    (_) => GlobalKey(),
  );

  late final List<({_HelpCategory category, _Faq faq})> _allFaqsFlat = [
    for (final category in _kHelpCategories)
      for (final faq in category.faqs) (category: category, faq: faq),
  ];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  List<({_HelpCategory category, _Faq faq})> get _filteredFaqs {
    if (_query.isEmpty) return const [];
    return _allFaqsFlat.where((entry) {
      return entry.faq.question.toLowerCase().contains(_query) ||
          entry.faq.answer.toLowerCase().contains(_query) ||
          entry.category.title.toLowerCase().contains(_query);
    }).toList();
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

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final searching = _query.isNotEmpty;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: _buildAppBar(),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 60),
        scrollCacheExtent: const ScrollCacheExtent.pixels(20000),
        children: [
          _buildSearchHero(),
          if (searching)
            _buildSearchResults()
          else ...[
            _buildQuickActions(),
            _buildTopicChips(),
            for (var i = 0; i < _kHelpCategories.length; i++)
              KeyedSubtree(
                key: _categoryKeys[i],
                child: _buildCategorySection(_kHelpCategories[i], i),
              ),
            _buildRoadmapSection(),
            KeyedSubtree(key: _contactKey, child: _buildContactSection()),
          ],
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
              color: Color(0x334F46E5),
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
            'Help Center',
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

  // --- Hero: greeting + breathing icon + search bar ---
  Widget _buildSearchHero() {
    return Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Colors.white, Color(0xFFF5F3FF)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE0E7FF)),
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
                          'Hi there 👋',
                          style: GoogleFonts.manrope(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'How can we help you today? Search below or browse a topic.',
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
                    width: 68,
                    height: 68,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        ..._buildBreathingRings(),
                        Container(
                              padding: const EdgeInsets.all(12),
                              decoration: const BoxDecoration(
                                color: Color(0xFFEDE9FE),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                LucideIcons.lifeBuoy,
                                color: _gradientEnd,
                                size: 28,
                              ),
                            )
                            .animate(onPlay: (c) => c.repeat(reverse: true))
                            .rotate(
                              begin: -0.02,
                              end: 0.02,
                              duration: 2600.ms,
                              curve: Curves.easeInOut,
                            )
                            .scale(
                              begin: const Offset(0.94, 0.94),
                              end: const Offset(1.06, 1.06),
                              duration: 2600.ms,
                              curve: Curves.easeInOut,
                            ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _buildSearchField(),
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
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: _gradientEnd.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
          )
          .animate(onPlay: (c) => c.repeat(), delay: (i * 900).ms)
          .scale(
            begin: const Offset(0.55, 0.55),
            end: const Offset(1.35, 1.35),
            duration: 2600.ms,
            curve: Curves.easeOut,
          )
          .fadeOut(duration: 2600.ms, curve: Curves.easeOut);
    });
  }

  Widget _buildSearchField() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _searchFocus.hasFocus
              ? _gradientEnd.withValues(alpha: 0.5)
              : const Color(0xFFE2E8F0),
          width: _searchFocus.hasFocus ? 1.5 : 1,
        ),
      ),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocus,
        onTapOutside: (_) => _searchFocus.unfocus(),
        onChanged: (_) => setState(() {}),
        style: GoogleFonts.inter(fontSize: 14, color: AppColors.ink),
        decoration: InputDecoration(
          hintText: 'Search FAQs, features, settings…',
          // Placeholder text still needs 4.5:1, not the muted-gray default.
          hintStyle: GoogleFonts.inter(
            fontSize: 13.5,
            color: AppColors.inkMuted,
          ),
          prefixIcon: const Icon(
            LucideIcons.search,
            size: 18,
            color: Color(0xFF94A3B8),
          ),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(
                    LucideIcons.x,
                    size: 16,
                    color: Color(0xFF94A3B8),
                  ),
                  onPressed: _searchController.clear,
                ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  // --- Search results ---
  Widget _buildSearchResults() {
    final results = _filteredFaqs;
    if (results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(32, 40, 32, 20),
        child: Column(
          children: [
            const Icon(
              LucideIcons.searchX,
              size: 36,
              color: Color(0xFFCBD5E1),
            ),
            const SizedBox(height: 12),
            Text(
              'No results for "${_searchController.text.trim()}"',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Try a different word, or contact support below.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                color: AppColors.inkMuted,
              ),
            ),
          ],
        ),
      ).animate().fadeIn(duration: 250.ms);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10, left: 2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${results.length} result${results.length == 1 ? '' : 's'}',
                style: GoogleFonts.manrope(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.inkMuted,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ),
          ...List.generate(results.length, (i) {
            final entry = results[i];
            return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              entry.category.icon,
                              size: 13,
                              color: entry.category.color,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              entry.category.title.toUpperCase(),
                              style: GoogleFonts.manrope(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: entry.category.color,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          entry.faq.question,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          entry.faq.answer,
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            color: AppColors.inkMuted,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .animate()
                .fadeIn(delay: (i * 40).ms, duration: 250.ms)
                .slideY(begin: 0.03, end: 0, duration: 250.ms);
          }),
        ],
      ),
    );
  }

  // --- Quick actions ---
  Widget _buildQuickActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildActionCard(
                  icon: LucideIcons.headphones,
                  iconColor: AppColors.safetyTeal,
                  iconBg: const Color(0xFFECFDF5),
                  title: 'Contact Support',
                  subtitle: "We're here to help.",
                  onTap: () => context.push<void>('/settings/feedback'),
                  animateDelay: 40,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionCard(
                  icon: LucideIcons.bug,
                  iconColor: const Color(0xFFD97706),
                  iconBg: const Color(0xFFFFFBEB),
                  title: 'Report an Issue',
                  subtitle: 'File a bug on GitHub.',
                  onTap: () => _launch(_kGithubIssuesUrl),
                  animateDelay: 70,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildActionCard(
                  icon: LucideIcons.shieldCheck,
                  iconColor: AppColors.safetyBlue,
                  iconBg: const Color(0xFFEFF6FF),
                  title: 'Safety Center',
                  subtitle: 'Safety tools & guidelines.',
                  onTap: () => context.push<void>('/settings/safety-center'),
                  animateDelay: 100,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionCard(
                  icon: LucideIcons.bookOpen,
                  iconColor: const Color(0xFF7C3AED),
                  iconBg: const Color(0xFFF5F3FF),
                  title: 'Community Guidelines',
                  subtitle: 'Our community standards.',
                  onTap: () =>
                      context.push<void>('/settings/community-guidelines'),
                  animateDelay: 130,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard({
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
                SizedBox(
                  height: 36,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 30,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        color: AppColors.inkMuted,
                        height: 1.35,
                      ),
                    ),
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

  // --- Browse by topic chips ---
  Widget _buildTopicChips() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 0, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'BROWSE BY TOPIC',
            style: GoogleFonts.manrope(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.inkMuted,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(right: 20),
              itemCount: _kHelpCategories.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final category = _kHelpCategories[i];
                return ScalePressable(
                  onTap: () => _scrollToKey(_categoryKeys[i]),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: category.bgColor,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: category.color.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(category.icon, size: 14, color: category.color),
                        const SizedBox(width: 7),
                        Text(
                          category.title,
                          style: GoogleFonts.manrope(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: category.color,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 160.ms, duration: 350.ms);
  }

  // --- FAQ category section (accordion) ---
  Widget _buildCategorySection(_HelpCategory category, int index) {
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
                      color: category.bgColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(category.icon, color: category.color, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      category.title.toUpperCase(),
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF475569),
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  Text(
                    '${category.faqs.length} articles',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppColors.inkMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ...List.generate(category.faqs.length, (i) {
                final faq = category.faqs[i];
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: i == category.faqs.length - 1 ? 0 : 10,
                  ),
                  child: _buildFaqAccordion(category: category, faq: faq),
                );
              }),
            ],
          ),
        )
        .animate()
        .fadeIn(delay: (180 + index * 40).ms, duration: 350.ms)
        .slideY(begin: 0.05, end: 0, duration: 350.ms);
  }

  Widget _buildFaqAccordion({
    required _HelpCategory category,
    required _Faq faq,
  }) {
    return Theme(
      data: Theme.of(context).copyWith(
        dividerColor: Colors.transparent,
        hoverColor: Colors.transparent,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
      ),
      child: ExpansionTile(
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
        iconColor: category.color,
        collapsedIconColor: const Color(0xFF94A3B8),
        title: Text(
          faq.question,
          style: GoogleFonts.inter(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              faq.answer,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                color: AppColors.inkMuted,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Roadmap / "What's coming" ---
  Widget _buildRoadmapSection() {
    return Container(
          margin: const EdgeInsets.fromLTRB(20, 10, 20, 10),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1E1B4B), AppColors.ink],
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
                          LucideIcons.sparkles,
                          color: Color(0xFFC7D2FE),
                          size: 18,
                        ),
                      )
                      .animate(onPlay: (c) => c.repeat(reverse: true))
                      .scale(
                        begin: const Offset(0.9, 0.9),
                        end: const Offset(1.1, 1.1),
                        duration: 1800.ms,
                        curve: Curves.easeInOut,
                      ),
                  const SizedBox(width: 12),
                  Text(
                    "WHAT'S COMING TO NEXUS",
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.white70,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                "A few things we're actively building - this is a living list, not a promise of dates.",
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  color: Colors.white54,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              ...List.generate(_kRoadmapItems.length, (i) {
                final item = _kRoadmapItems[i];
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: i == _kRoadmapItems.length - 1 ? 0 : 16,
                  ),
                  child: _buildRoadmapRow(item),
                );
              }),
            ],
          ),
        )
        .animate()
        .fadeIn(delay: 220.ms, duration: 350.ms)
        .slideY(begin: 0.05, end: 0, duration: 350.ms);
  }

  Widget _buildRoadmapRow(_RoadmapItem item) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(item.icon, color: const Color(0xFFC7D2FE), size: 18),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                item.desc,
                style: GoogleFonts.inter(fontSize: 11.5, color: Colors.white54),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white24),
              ),
              child: Text(
                'PLANNED',
                style: GoogleFonts.manrope(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFFC7D2FE),
                  letterSpacing: 0.6,
                ),
              ),
            )
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .fadeIn(duration: 1200.ms, begin: 0.55)
            .then()
            .fadeOut(duration: 1200.ms, begin: 1),
      ],
    );
  }

  // --- Contact / still need help ---
  Widget _buildContactSection() {
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
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      LucideIcons.headphones,
                      color: AppColors.safetyTeal,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'STILL NEED HELP?',
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
                "Couldn't find your answer above? Reach out and we'll take it from there.",
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppColors.inkMuted,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 16),
              _buildContactRow(
                icon: LucideIcons.messageSquare,
                label: 'Help, Feedback & Bug Report',
                desc: 'Send quick feedback straight to the team.',
                onTap: () => context.push<void>('/settings/feedback'),
              ),
              const Divider(height: 24, color: Color(0xFFE2E8F0)),
              _buildContactRow(
                icon: LucideIcons.externalLink,
                label: 'Report an Issue on GitHub',
                desc: 'File a bug or feature request in our public repo.',
                onTap: () => _launch(_kGithubIssuesUrl),
              ),
            ],
          ),
        )
        .animate()
        .fadeIn(delay: 260.ms, duration: 350.ms)
        .slideY(begin: 0.05, end: 0, duration: 350.ms);
  }

  Widget _buildContactRow({
    required IconData icon,
    required String label,
    required String desc,
    required VoidCallback onTap,
  }) {
    return ScalePressable(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.safetyBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: AppColors.safetyBlue, size: 17),
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
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppColors.inkMuted,
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
    );
  }

  // --- Footer ---
  Widget _buildFooterNote() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 12),
      child: Column(
        children: [
          const Icon(
                LucideIcons.lifeBuoy,
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
            "Can't find what you need? We're one tap away.",
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.inkMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Nexus Help Center',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: const Color(0xFFCBD5E1),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 340.ms, duration: 400.ms);
  }
}
