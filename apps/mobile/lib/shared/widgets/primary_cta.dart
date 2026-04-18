import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';

/// "Button-in-Button" CTA — pill button with a nested icon circle that
/// performs magnetic hover physics (diagonal translate + scale) and a press
/// scale-down for haptic feedback. Never render the arrow naked next to text.
class PrimaryCta extends StatefulWidget {
  const PrimaryCta({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon = Icons.arrow_outward_rounded,
    this.minWidth,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData icon;
  final double? minWidth;

  @override
  State<PrimaryCta> createState() => _PrimaryCtaState();
}

class _PrimaryCtaState extends State<PrimaryCta> {
  bool _hover = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onPressed != null && !widget.busy;
    final double scale = _pressed ? 0.97 : 1.0;

    final Widget content = AnimatedScale(
      scale: scale,
      duration: AppMotion.fast,
      curve: AppMotion.press,
      child: AnimatedContainer(
        duration: AppMotion.medium,
        curve: AppMotion.smooth,
        constraints: BoxConstraints(minWidth: widget.minWidth ?? 0),
        padding: const EdgeInsets.fromLTRB(24, 10, 10, 10),
        decoration: BoxDecoration(
          color: enabled
              ? (_hover
                  ? AppColors.accent
                  : AppColors.accent.withValues(alpha: 0.95))
              : AppColors.accent.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(99),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.35),
                    blurRadius: _hover ? 42 : 28,
                    spreadRadius: _hover ? 1 : 0,
                    offset: const Offset(0, 12),
                  ),
                ]
              : const [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Text(
                  widget.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
            ),
            AnimatedSlide(
              duration: AppMotion.medium,
              curve: AppMotion.smooth,
              offset: _hover
                  ? const Offset(0.1, -0.025)
                  : Offset.zero,
              child: AnimatedScale(
                duration: AppMotion.medium,
                curve: AppMotion.smooth,
                scale: _hover ? 1.06 : 1.0,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.22),
                      width: 0.8,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: widget.busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.6,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Icon(widget.icon, color: Colors.white, size: 18),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: enabled ? widget.onPressed : null,
        behavior: HitTestBehavior.opaque,
        child: content,
      ),
    );
  }
}
