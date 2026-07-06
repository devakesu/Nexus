import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:nexus/widgets/nexus_toast.dart';
import 'package:nexus/widgets/scale_pressable.dart';
import 'package:url_launcher/url_launcher.dart';

class CrisisHelplinesPage extends StatelessWidget {
  const CrisisHelplinesPage({super.key});

  static const _accent = Color(0xFF0284C7);

  Future<void> _launchUrlHelper(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (context.mounted) {
        NexusToast.show(
          context,
          'Could not launch helpline dialer',
          type: NexusToastType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: _buildAppBar(context),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        children: [
          Text(
            "If you are in immediate physical danger, dial 112 (India's national emergency number) or contact your local police. For support services, reach out to these hotlines:",
            style: GoogleFonts.inter(
              fontSize: 13,
              color: const Color(0xFF64748B),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 20),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: helplines.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final h = helplines[index];
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
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
                      onTap: () =>
                          _launchUrlHelper(context, h['url']! as String),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 14,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
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
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
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
            'Crisis Helplines',
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
}
