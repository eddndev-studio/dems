import 'package:flutter/material.dart';

import '../../../shared/theme/app_colors.dart';
import '../../../shared/theme/app_motion.dart';
import '../../../shared/widgets/bezel_card.dart';
import '../data/asignacion_models.dart';

class AsignacionCard extends StatefulWidget {
  const AsignacionCard({
    super.key,
    required this.item,
    required this.onOpen,
  });

  final AsignacionItem item;
  final VoidCallback onOpen;

  @override
  State<AsignacionCard> createState() => _AsignacionCardState();
}

class _AsignacionCardState extends State<AsignacionCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final item = widget.item;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onOpen,
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _hover ? 1.012 : 1.0,
          duration: AppMotion.medium,
          curve: AppMotion.smooth,
          child: BezelCard(
            outerRadius: 28,
            shellPadding: 5,
            corePadding: const EdgeInsets.all(22),
            shellColor: _hover
                ? Colors.white.withValues(alpha: 0.07)
                : Colors.white.withValues(alpha: 0.04),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    _FolioBadge(folio: item.prototipo.folio),
                    const Spacer(),
                    _RubricChip(tipo: item.rubric.tipo),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  item.prototipo.nombre,
                  style: text.titleLarge?.copyWith(height: 1.25),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  item.prototipo.plantel ?? 'Plantel no asignado',
                  style: text.bodySmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 18),
                Divider(color: AppColors.hairline, height: 1),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _StatusPill(status: item.status),
                    const Spacer(),
                    _OpenArrow(
                      label: _ctaLabel(item.status),
                      hovered: _hover,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _ctaLabel(EvaluacionStatus s) => switch (s) {
        EvaluacionStatus.pendiente => 'Iniciar',
        EvaluacionStatus.enProgreso => 'Continuar',
        EvaluacionStatus.enviada => 'Revisar',
      };
}

// ──────────────────────────────────────────────────────────────────────────
//  Sub-components
// ──────────────────────────────────────────────────────────────────────────

class _FolioBadge extends StatelessWidget {
  const _FolioBadge({required this.folio});
  final String folio;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Text(
        folio,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _RubricChip extends StatelessWidget {
  const _RubricChip({required this.tipo});
  final RubricType tipo;

  @override
  Widget build(BuildContext context) {
    final bool isExhib = tipo == RubricType.exhibicion;
    final Color tint =
        isExhib ? AppColors.accent : const Color(0xFF7B7AE0); // guinda / violet
    final IconData icon = isExhib
        ? Icons.view_in_ar_outlined
        : Icons.article_outlined;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 5, 12, 5),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: tint.withValues(alpha: 0.35), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: tint),
          const SizedBox(width: 7),
          Text(
            tipo.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
              color: tint,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final EvaluacionStatus status;

  @override
  Widget build(BuildContext context) {
    final Color dot = switch (status) {
      EvaluacionStatus.pendiente => AppColors.textTertiary,
      EvaluacionStatus.enProgreso => AppColors.warning,
      EvaluacionStatus.enviada => AppColors.success,
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: dot,
            boxShadow: [
              BoxShadow(
                color: dot.withValues(alpha: 0.5),
                blurRadius: 6,
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          status.label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _OpenArrow extends StatelessWidget {
  const _OpenArrow({required this.label, required this.hovered});
  final String label;
  final bool hovered;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedDefaultTextStyle(
          duration: AppMotion.medium,
          curve: AppMotion.smooth,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
            color: hovered ? AppColors.accent : AppColors.textPrimary,
          ),
          child: Text(label),
        ),
        const SizedBox(width: 10),
        AnimatedSlide(
          duration: AppMotion.medium,
          curve: AppMotion.smooth,
          offset: hovered ? const Offset(0.18, -0.05) : Offset.zero,
          child: AnimatedContainer(
            duration: AppMotion.medium,
            curve: AppMotion.smooth,
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: hovered
                  ? AppColors.accent.withValues(alpha: 0.18)
                  : Colors.white.withValues(alpha: 0.05),
              border: Border.all(
                color: hovered
                    ? AppColors.accent.withValues(alpha: 0.45)
                    : AppColors.hairline,
                width: 0.8,
              ),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.arrow_outward_rounded,
              size: 14,
              color: hovered ? AppColors.accent : AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
