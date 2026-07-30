import 'package:flutter/material.dart';
import 'package:nexus/core/theme/app_colors.dart';

class GhostColors extends ThemeExtension<GhostColors> {
  const GhostColors({
    this.brandPrimary = AppColors.pulsarPink,
    this.brandAccent = AppColors.primaryTeal,
    this.successGreen = AppColors.success,
    this.warningYellow = AppColors.warning,
    this.dangerRed = AppColors.error,
  });

  final Color brandPrimary;
  final Color brandAccent;
  final Color successGreen;
  final Color warningYellow;
  final Color dangerRed;

  @override
  GhostColors copyWith({
    Color? brandPrimary,
    Color? brandAccent,
    Color? successGreen,
    Color? warningYellow,
    Color? dangerRed,
  }) {
    return GhostColors(
      brandPrimary: brandPrimary ?? this.brandPrimary,
      brandAccent: brandAccent ?? this.brandAccent,
      successGreen: successGreen ?? this.successGreen,
      warningYellow: warningYellow ?? this.warningYellow,
      dangerRed: dangerRed ?? this.dangerRed,
    );
  }

  @override
  GhostColors lerp(ThemeExtension<GhostColors>? other, double t) {
    if (other is! GhostColors) return this;
    return GhostColors(
      brandPrimary: Color.lerp(brandPrimary, other.brandPrimary, t)!,
      brandAccent: Color.lerp(brandAccent, other.brandAccent, t)!,
      successGreen: Color.lerp(successGreen, other.successGreen, t)!,
      warningYellow: Color.lerp(warningYellow, other.warningYellow, t)!,
      dangerRed: Color.lerp(dangerRed, other.dangerRed, t)!,
    );
  }
}
