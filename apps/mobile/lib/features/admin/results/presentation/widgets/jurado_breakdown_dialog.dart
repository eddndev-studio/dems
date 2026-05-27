import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../../shared/theme/app_colors.dart';
import '../../data/result_models.dart';

/// Lista de evaluaciones individuales (un jurado por fila) que componen el
/// promedio de un prototipo. Útil para auditar disparidades entre jurados.
class JuradoBreakdownDialog extends StatelessWidget {
  const JuradoBreakdownDialog({
    super.key,
    required this.prototipo,
    required this.maxTotal,
  });

  final PrototipoResult prototipo;
  final int maxTotal;

  static Future<void> show(
    BuildContext context, {
    required PrototipoResult prototipo,
    required int maxTotal,
  }) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (_) => JuradoBreakdownDialog(
        prototipo: prototipo,
        maxTotal: maxTotal,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final evals = [...prototipo.evaluaciones]
      ..sort((a, b) => b.total.compareTo(a.total));
    final fmt = DateFormat('dd/MM/yyyy · HH:mm');

    return Dialog(
      backgroundColor: AppColors.surface1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(compact ? 20 : 24),
        side: BorderSide(color: AppColors.hairline),
      ),
      insetPadding:
          EdgeInsets.symmetric(horizontal: compact ? 16 : 40, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 640),
        child: Padding(
          padding: EdgeInsets.all(compact ? 20 : 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Folio ${prototipo.folio}',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textTertiary,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          prototipo.nombre,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${prototipo.nJurados} ${prototipo.nJurados == 1 ? "evaluación entregada" : "evaluaciones entregadas"}',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    color: AppColors.textTertiary,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (prototipo.promedio != null)
                _AveragePill(
                  promedio: prototipo.promedio!,
                  maxTotal: maxTotal,
                ),
              const SizedBox(height: 18),
              Expanded(
                child: ListView.separated(
                  itemCount: evals.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _JuradoRow(
                    eval: evals[i],
                    maxTotal: maxTotal,
                    formatter: fmt,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AveragePill extends StatelessWidget {
  const _AveragePill({required this.promedio, required this.maxTotal});
  final double promedio;
  final int maxTotal;
  @override
  Widget build(BuildContext context) {
    final pct = maxTotal > 0 ? (promedio / maxTotal * 100) : 0.0;
    final formatted = (promedio.truncateToDouble() == promedio)
        ? promedio.toInt().toString()
        : promedio.toStringAsFixed(2);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.32)),
      ),
      child: Row(
        children: [
          Icon(Icons.functions_rounded,
              size: 16, color: AppColors.accent),
          const SizedBox(width: 8),
          Text(
            'Promedio',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
              letterSpacing: 0.2,
            ),
          ),
          const Spacer(),
          Text(
            '$formatted / $maxTotal',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '(${pct.toStringAsFixed(1)} %)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _JuradoRow extends StatelessWidget {
  const _JuradoRow({
    required this.eval,
    required this.maxTotal,
    required this.formatter,
  });

  final EvaluacionResult eval;
  final int maxTotal;
  final DateFormat formatter;

  @override
  Widget build(BuildContext context) {
    final pct = maxTotal > 0
        ? (eval.total / maxTotal).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  _initials(eval.juradoNombre),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      eval.juradoNombre,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatter.format(eval.submittedAt.toLocal()),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${eval.total}',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '/ $maxTotal',
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: Stack(
              children: [
                Container(
                  height: 4,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
                FractionallySizedBox(
                  widthFactor: pct,
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.accentDeep,
                          AppColors.accent,
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first +
            parts.last.characters.first)
        .toUpperCase();
  }
}
