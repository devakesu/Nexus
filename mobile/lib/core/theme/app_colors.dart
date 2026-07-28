import 'package:flutter/material.dart';

/// Central source of truth for Nexus's design tokens (DESIGN.md).
///
/// Screens should reference these instead of hard-coding hex literals.
abstract final class AppColors {
  // ── Primary ──────────────────────────────────────────────────────────
  /// Seed/system color; the neutral "always-on" accent (Profile tab, sliders).
  static const Color primaryTeal = Color(0xFF0891B2);

  /// The app's signature brand accent - primary CTAs, onboarding, focus glows.
  static const Color pulsarPink = Color(0xFFFF7597);

  // ── Mode Signal Rule ─────────────────────────────────────────────────
  static const Color modeDating = Color(0xFFFF4F81);
  static const Color modeFriends = Color(0xFFA45E00);
  static const Color modeProfessional = Color(0xFF007E6D);
  static const Color modeSettings = Color(0xFF4EA8DE);

  // ── Safety Duo ───────────────────────────────────────────────────────
  static const Color safetyBlue = Color(0xFF0284C7);
  static const Color safetyTeal = Color(0xFF0D9488);

  // ── Neutral & Surfaces ───────────────────────────────────────────────
  static const Color ink = Color(0xFF0F172A);
  static const Color inkMuted = Color(0xFF64748B);
  static const Color inkFaint = Color(0xFF94A3B8);
  static const Color borderNeutral = Color(0xFFE2E8F0);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF0F172A);
  static const Color backgroundDark = Color(0xFF0F172A);
  static const Color canvas = Color(0xFFF4F6FA);

  // ── Status ───────────────────────────────────────────────────────────
  static const Color success = Color(0xFF10B981);
  static const Color error = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);
  static const Color info = Color(0xFF60A5FA);

  /// Blends [base] toward white.
  static Color tint(Color base, [double amount = 0.35]) =>
      Color.lerp(base, Colors.white, amount)!;

  /// Picks whichever of pure black/white has higher WCAG contrast against [background].
  static Color foregroundFor(Color background) =>
      ThemeData.estimateBrightnessForColor(background) == Brightness.dark
      ? Colors.white
      : Colors.black;
}
