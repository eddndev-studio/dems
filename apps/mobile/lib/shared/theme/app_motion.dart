import 'package:flutter/animation.dart';

/// Custom cubic-beziers and durations — real-world mass, never `linear`/`easeInOut`.
class AppMotion {
  const AppMotion._();

  /// Heavy, cinematic curve for entry animations (mass that settles).
  static const Curve entry = Cubic(0.32, 0.72, 0, 1);

  /// Snappy press feedback for interactive elements.
  static const Curve press = Cubic(0.25, 1.2, 0.5, 1);

  /// Subtle hover/state transitions.
  static const Curve smooth = Cubic(0.4, 0, 0.2, 1);

  static const Duration fast = Duration(milliseconds: 180);
  static const Duration medium = Duration(milliseconds: 320);
  static const Duration slow = Duration(milliseconds: 640);
  static const Duration cinematic = Duration(milliseconds: 900);
}
