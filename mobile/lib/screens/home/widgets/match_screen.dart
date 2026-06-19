import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/screens/home/tabs/profile/widgets/storage_image.dart';

// Full-screen match celebration pushed onto the root navigator.
// Pop with true → "send a message", false → "keep browsing".
class MatchScreen extends StatefulWidget {
  const MatchScreen({
    required this.matchedName,
    this.matchedProfilePic,
    this.titleText = "It's a Match! 💘",
    this.subtitleText,
    this.themeColor = const Color(0xFFFF4F81),
    this.badgeIcon = LucideIcons.heart,
    super.key,
  });

  final String matchedName;
  final String? matchedProfilePic;
  final String titleText;
  final String? subtitleText;
  final Color themeColor;
  final IconData badgeIcon;

  @override
  State<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends State<MatchScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _avatarScale;
  late final Animation<double> _contentFade;
  late final Animation<Offset> _contentSlide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    _avatarScale = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0, 0.65, curve: Curves.elasticOut),
    );
    _contentFade = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.4, 1, curve: Curves.easeOut),
    );
    _contentSlide = Tween<Offset>(
      begin: const Offset(0, 0.18),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.4, 1, curve: Curves.easeOut),
      ),
    );
    unawaited(_ctrl.forward());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = widget.themeColor;

    return Scaffold(
      backgroundColor: const Color(0xFF090D1A),
      body: Stack(
        children: [
          // Radial glow background
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.2),
                  radius: 0.85,
                  colors: [
                    themeColor.withValues(alpha: 0.22),
                    const Color(0xFF090D1A),
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 2),

                // Avatars row
                ScaleTransition(
                  scale: _avatarScale,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const _ProfileCircle(
                        profilePic: null,
                        label: 'You',
                        ringColor: Color(0xFFA78BFA),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 30),
                        child: _HeartBadge(
                          color: themeColor,
                          icon: widget.badgeIcon,
                        ),
                      ),
                      _ProfileCircle(
                        profilePic: widget.matchedProfilePic,
                        label: widget.matchedName,
                        ringColor: themeColor,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 36),

                // Title + subtitle
                FadeTransition(
                  opacity: _contentFade,
                  child: SlideTransition(
                    position: _contentSlide,
                    child: Column(
                      children: [
                        Text(
                          widget.titleText,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.3,
                            shadows: [
                              Shadow(
                                color: themeColor.withValues(alpha: 0.75),
                                blurRadius: 28,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 44),
                          child: Text(
                            widget.subtitleText ??
                                'You and ${widget.matchedName} liked each other.\nPerhaps the stars aligned.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.55),
                              fontSize: 14.5,
                              height: 1.65,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const Spacer(flex: 3),

                // Buttons
                FadeTransition(
                  opacity: _contentFade,
                  child: SlideTransition(
                    position: _contentSlide,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(28, 0, 28, 42),
                      child: Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    themeColor,
                                    Color.lerp(
                                      themeColor,
                                      const Color(0xFF7C3AED),
                                      0.48,
                                    )!,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: [
                                  BoxShadow(
                                    color: themeColor.withValues(alpha: 0.42),
                                    blurRadius: 24,
                                    offset: const Offset(0, 7),
                                  ),
                                ],
                              ),
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 17),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                                onPressed: () => Navigator.pop(context, true),
                                icon: const Icon(
                                  LucideIcons.messageCircle,
                                  size: 18,
                                ),
                                label: const Text(
                                  'Send a message',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: Text(
                              'Keep browsing',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.45),
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileCircle extends StatelessWidget {
  const _ProfileCircle({
    required this.profilePic,
    required this.label,
    required this.ringColor,
  });

  final String? profilePic;
  final String label;
  final Color ringColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 108,
          height: 108,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: ringColor, width: 3),
            boxShadow: [
              BoxShadow(
                color: ringColor.withValues(alpha: 0.48),
                blurRadius: 28,
                spreadRadius: 2,
              ),
            ],
          ),
          child: ClipOval(
            child: profilePic != null && profilePic!.isNotEmpty
                ? StorageImage(
                    imagePath: profilePic!,
                    errorWidget: ColoredBox(
                      color: ringColor.withValues(alpha: 0.15),
                      child: const Center(
                        child: Icon(
                          LucideIcons.user,
                          color: Colors.white38,
                          size: 46,
                        ),
                      ),
                    ),
                  )
                : ColoredBox(
                    color: ringColor.withValues(alpha: 0.15),
                    child: const Center(
                      child: Icon(
                        LucideIcons.user,
                        color: Colors.white38,
                        size: 46,
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white60,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _HeartBadge extends StatelessWidget {
  const _HeartBadge({required this.color, this.icon = LucideIcons.heart});
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.6),
            blurRadius: 16,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Center(
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}
