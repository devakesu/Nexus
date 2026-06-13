import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class UniverseSection extends StatelessWidget {
  const UniverseSection({
    required this.icon,
    required this.title,
    required this.description,
    required this.child,
    this.cardColor,
    this.borderColor,
    this.accentColor,
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget child;
  final Color? cardColor;
  final Color? borderColor;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const defaultCardColor = Color(0xFF111420);
    const defaultAccentColor = Color(0xFFFF7597); // pulsarPink
    final effectiveCardColor = cardColor ?? defaultCardColor;
    final effectiveBorderColor = borderColor ?? Colors.white.withValues(alpha: 0.08);
    final effectiveAccentColor = accentColor ?? defaultAccentColor;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: effectiveCardColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: effectiveBorderColor,
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 18,
              spreadRadius: 1,
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
                    shape: BoxShape.circle,
                    color: effectiveAccentColor.withValues(alpha: 0.08),
                    border: Border.all(
                      color: effectiveAccentColor.withValues(alpha: 0.3),
                      width: 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: effectiveAccentColor.withValues(alpha: 0.15),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Icon(
                    icon,
                    color: effectiveAccentColor,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.plusJakartaSans(
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                          fontSize: 16,
                          letterSpacing: 0.3,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: GoogleFonts.plusJakartaSans(
                          color: isDark ? Colors.white.withValues(alpha: 0.45) : Colors.black.withValues(alpha: 0.5),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    );
  }
}
