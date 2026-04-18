import 'package:flutter/material.dart';

/// Ethereal Glass palette — OLED near-black base, IPN guinda as accent.
/// All values referenced through AppColors to keep the visual language consistent.
class AppColors {
  const AppColors._();

  static const Color bg = Color(0xFF050505);
  static const Color surface0 = Color(0xFF0A0A0A);
  static const Color surface1 = Color(0xFF0F0F0F);
  static const Color surface2 = Color(0xFF141414);

  static Color hairline = Colors.white.withValues(alpha: 0.08);
  static Color hairlineStrong = Colors.white.withValues(alpha: 0.14);
  static Color innerHighlight = Colors.white.withValues(alpha: 0.06);

  static Color textPrimary = Colors.white.withValues(alpha: 0.92);
  static Color textSecondary = Colors.white.withValues(alpha: 0.55);
  static Color textTertiary = Colors.white.withValues(alpha: 0.38);
  static Color textDisabled = Colors.white.withValues(alpha: 0.22);

  static const Color accent = Color(0xFFD23C5C);
  static const Color accentDeep = Color(0xFF7B1532);
  static const Color accentGlowA = Color(0xFF8B1A3D);
  static const Color accentGlowB = Color(0xFF2E1A3F);

  static const Color success = Color(0xFF38D39F);
  static const Color danger = Color(0xFFFF4C6B);
  static const Color warning = Color(0xFFF5B841);
}
