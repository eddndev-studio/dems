import 'package:flutter/material.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/theme/app_motion.dart';

/// Selector 0..max_score para criterios `scale` y `boolean`.
/// - Cada valor es un pill Double-Bezel miniatura con glow cuando está activo.
/// - Si `locked` (evaluación enviada) se muestra en readonly.
class ScaleSelector extends StatelessWidget {
  const ScaleSelector({
    super.key,
    required this.max,
    required this.value,
    required this.onChanged,
    this.locked = false,
  });

  final int max;
  final int? value;
  final ValueChanged<int> onChanged;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (int v = 0; v <= max; v++)
          _Chip(
            value: v,
            active: value == v,
            locked: locked,
            onTap: locked ? null : () => onChanged(v),
          ),
      ],
    );
  }
}

class _Chip extends StatefulWidget {
  const _Chip({
    required this.value,
    required this.active,
    required this.locked,
    required this.onTap,
  });

  final int value;
  final bool active;
  final bool locked;
  final VoidCallback? onTap;

  @override
  State<_Chip> createState() => _ChipState();
}

class _ChipState extends State<_Chip> {
  bool _hover = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bool active = widget.active;
    final double scale = _pressed ? 0.94 : (_hover && !active ? 1.03 : 1.0);

    final Color background = active
        ? AppColors.accent.withValues(alpha: 0.18)
        : Colors.white.withValues(alpha: _hover ? 0.06 : 0.03);
    final Color borderColor = active
        ? AppColors.accent.withValues(alpha: 0.55)
        : (_hover ? AppColors.hairlineStrong : AppColors.hairline);
    final Color textColor = active
        ? AppColors.accent
        : (widget.locked ? AppColors.textTertiary : AppColors.textPrimary);

    return MouseRegion(
      cursor: widget.onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown:
            widget.onTap == null ? null : (_) => setState(() => _pressed = true),
        onTapUp: widget.onTap == null
            ? null
            : (_) => setState(() => _pressed = false),
        onTapCancel: widget.onTap == null
            ? null
            : () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: scale,
          duration: AppMotion.fast,
          curve: AppMotion.press,
          child: AnimatedContainer(
            duration: AppMotion.medium,
            curve: AppMotion.smooth,
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor, width: active ? 1.2 : 0.8),
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: AppColors.accent.withValues(alpha: 0.32),
                        blurRadius: 20,
                        spreadRadius: -4,
                      ),
                    ]
                  : const [],
            ),
            alignment: Alignment.center,
            child: Text(
              '${widget.value}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: textColor,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
