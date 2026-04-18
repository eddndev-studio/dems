import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Double-Bezel (Doppelrand) container.
///
/// Outer shell + inner core with *concentric* radii. The inner radius is
/// computed as `outerRadius - shellPadding` so the curves breathe as a single
/// machined object, not two rectangles stacked.
class BezelCard extends StatelessWidget {
  const BezelCard({
    super.key,
    required this.child,
    this.outerRadius = 32,
    this.shellPadding = 6,
    this.corePadding = const EdgeInsets.all(28),
    this.coreColor,
    this.shellColor,
  });

  final Widget child;
  final double outerRadius;
  final double shellPadding;
  final EdgeInsets corePadding;
  final Color? coreColor;
  final Color? shellColor;

  @override
  Widget build(BuildContext context) {
    final double innerRadius = outerRadius - shellPadding;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: shellColor ?? Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(outerRadius),
        border: Border.all(color: AppColors.hairline, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 60,
            spreadRadius: -10,
            offset: const Offset(0, 40),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(shellPadding),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: coreColor ?? AppColors.surface1,
            borderRadius: BorderRadius.circular(innerRadius),
            border: Border.all(
              color: AppColors.hairlineStrong,
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.innerHighlight,
                offset: const Offset(0, 1),
                blurRadius: 0,
                spreadRadius: 0,
                blurStyle: BlurStyle.inner,
              ),
            ],
          ),
          child: Padding(
            padding: corePadding,
            child: child,
          ),
        ),
      ),
    );
  }
}
