import 'package:flutter/material.dart';

/// Central source of truth for Nexus's design tokens (DESIGN.md).
///
/// Screens should reference these instead of hard-coding hex literals.
/// Hard-coding is how mode/safety colors drift from the documented system —
/// e.g. the Professional filter panel once reintroduced a "close enough"
/// teal (`#00C4AB`) instead of the canonical `#007E6D`, and several settings
/// pages borrowed the Safety Duo despite not being safety surfaces. Importing
/// from here instead of retyping hex makes that class of drift structurally
/// harder to reintroduce.
abstract final class AppColors {
  // ── Primary ──────────────────────────────────────────────────────────
  /// Seed/system color; the neutral "always-on" accent (Profile tab, sliders).
  static const Color primaryTeal = Color(0xFF0891B2);

  /// The app's signature brand accent — primary CTAs, onboarding, focus glows.
  static const Color pulsarPink = Color(0xFFFF7597);

  // ── Mode Signal Rule ─────────────────────────────────────────────────
  // One color per relationship mode, identical across nav, chat, home
  // header, and filter panel for that mode. Never mix two of these (or with
  // pulsarPink / the Safety Duo) on the same screen — see DESIGN.md's
  // "One Signal Rule".
  static const Color modeDating = Color(0xFFFF4F81);
  static const Color modeFriends = Color(0xFFA45E00);
  static const Color modeProfessional = Color(0xFF007E6D);
  static const Color modeSettings = Color(0xFF4EA8DE);

  // ── Safety Duo ───────────────────────────────────────────────────────
  /// Reserved exclusively for Safety Center, meetup-safety, check-in, and
  /// crisis-helpline surfaces. Never reused elsewhere (including other
  /// Settings sub-pages), so it stays recognizable as "you're safe here".
  static const Color safetyBlue = Color(0xFF0284C7);
  static const Color safetyTeal = Color(0xFF0D9488);

  // ── Neutral ──────────────────────────────────────────────────────────
  static const Color ink = Color(0xFF0F172A);
  static const Color inkMuted = Color(0xFF64748B);
  static const Color inkFaint = Color(0xFF94A3B8);
  static const Color borderNeutral = Color(0xFFE2E8F0);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color canvas = Color(0xFFF4F6FA);

  // ── Status ───────────────────────────────────────────────────────────
  /// Reserved for toast/status feedback and validation states — never used
  /// as decorative accents.
  static const Color success = Color(0xFF10B981);
  static const Color error = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);
  static const Color info = Color(0xFF60A5FA);

  /// Blends [base] toward white — the standard way this system derives a
  /// lighter gradient "far stop" from a signal color (see the per-mode
  /// tints in chat_theme.dart, which follow the same ~35% blend).
  static Color tint(Color base, [double amount = 0.35]) =>
      Color.lerp(base, Colors.white, amount)!;
}
