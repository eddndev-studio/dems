import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Ethereal Glass mesh: deep OLED base with two soft radial glows
/// (guinda + violet) that suggest depth without any GPU blur cost.
/// Non-scrolling, fixed layer — safe for mobile frame rate.
class MeshBackdrop extends StatelessWidget {
  const MeshBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            const ColoredBox(color: AppColors.bg),
            _Orb(
              alignment: const Alignment(-1.1, -0.9),
              color: AppColors.accentGlowA,
              size: 780,
              intensity: 0.55,
            ),
            _Orb(
              alignment: const Alignment(1.15, 0.35),
              color: AppColors.accentGlowB,
              size: 820,
              intensity: 0.48,
            ),
            _Orb(
              alignment: const Alignment(0.2, 1.1),
              color: AppColors.accentDeep,
              size: 560,
              intensity: 0.35,
            ),
            const _VignetteOverlay(),
          ],
        ),
      ),
    );
  }
}

class _Orb extends StatelessWidget {
  const _Orb({
    required this.alignment,
    required this.color,
    required this.size,
    required this.intensity,
  });

  final Alignment alignment;
  final Color color;
  final double size;
  final double intensity;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color.withValues(alpha: intensity),
                color.withValues(alpha: intensity * 0.35),
                color.withValues(alpha: 0),
              ],
              stops: const [0, 0.45, 1],
            ),
          ),
        ),
      ),
    );
  }
}

/// Edge vignette — subtly darkens corners so content pops.
class _VignetteOverlay extends StatelessWidget {
  const _VignetteOverlay();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            radius: 1.1,
            colors: [
              Colors.transparent,
              Colors.black.withValues(alpha: 0.45),
            ],
            stops: const [0.55, 1],
          ),
        ),
      ),
    );
  }
}
