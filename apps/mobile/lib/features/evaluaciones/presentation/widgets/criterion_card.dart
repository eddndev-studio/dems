import 'package:flutter/material.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/widgets/bezel_card.dart';
import '../../data/evaluacion_models.dart';
import 'scale_selector.dart';

/// Card Double-Bezel para un criterio individual de la rúbrica.
/// Renderiza input según el `kind`:
///   - scale / boolean → [ScaleSelector] 0..max
///   - text_key → textarea
class CriterionCard extends StatelessWidget {
  const CriterionCard({
    super.key,
    required this.index,
    required this.criterion,
    required this.scoreValue,
    required this.textValue,
    required this.onScore,
    required this.onText,
    required this.locked,
  });

  final int index; // 1-based for display
  final RubricCriterion criterion;
  final int? scoreValue;
  final String? textValue;
  final ValueChanged<int> onScore;
  final ValueChanged<String> onText;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    final bool answered = switch (criterion.kind) {
      CriterionKind.scale => scoreValue != null,
      CriterionKind.boolean => scoreValue != null,
      CriterionKind.textKey => (textValue ?? '').trim().isNotEmpty,
    };

    return BezelCard(
      outerRadius: 28,
      shellPadding: 5,
      corePadding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
      shellColor: answered
          ? Colors.white.withValues(alpha: 0.055)
          : Colors.white.withValues(alpha: 0.035),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _IndexBadge(index: index, answered: answered),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  criterion.texto,
                  style: text.bodyLarge?.copyWith(height: 1.4),
                ),
              ),
              if (criterion.kind != CriterionKind.textKey) ...[
                const SizedBox(width: 12),
                _MaxChip(max: criterion.maxScore),
              ],
            ],
          ),
          const SizedBox(height: 18),
          _Input(
            criterion: criterion,
            scoreValue: scoreValue,
            textValue: textValue,
            onScore: onScore,
            onText: onText,
            locked: locked,
          ),
        ],
      ),
    );
  }
}

class _Input extends StatelessWidget {
  const _Input({
    required this.criterion,
    required this.scoreValue,
    required this.textValue,
    required this.onScore,
    required this.onText,
    required this.locked,
  });

  final RubricCriterion criterion;
  final int? scoreValue;
  final String? textValue;
  final ValueChanged<int> onScore;
  final ValueChanged<String> onText;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    switch (criterion.kind) {
      case CriterionKind.scale:
      case CriterionKind.boolean:
        return ScaleSelector(
          max: criterion.maxScore,
          value: scoreValue,
          onChanged: onScore,
          locked: locked,
        );
      case CriterionKind.textKey:
        return _TextArea(
          initial: textValue,
          onChanged: onText,
          locked: locked,
        );
    }
  }
}

class _TextArea extends StatefulWidget {
  const _TextArea({
    required this.initial,
    required this.onChanged,
    required this.locked,
  });

  final String? initial;
  final ValueChanged<String> onChanged;
  final bool locked;

  @override
  State<_TextArea> createState() => _TextAreaState();
}

class _TextAreaState extends State<_TextArea> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      readOnly: widget.locked,
      minLines: 2,
      maxLines: 6,
      onChanged: widget.onChanged,
      style: Theme.of(context).textTheme.bodyMedium,
      decoration: InputDecoration(
        hintText: 'Respuesta…',
        hintStyle: TextStyle(color: AppColors.textTertiary),
      ),
    );
  }
}

class _IndexBadge extends StatelessWidget {
  const _IndexBadge({required this.index, required this.answered});
  final int index;
  final bool answered;

  @override
  Widget build(BuildContext context) {
    final Color fill = answered
        ? AppColors.accent.withValues(alpha: 0.15)
        : Colors.white.withValues(alpha: 0.05);
    final Color border = answered
        ? AppColors.accent.withValues(alpha: 0.5)
        : AppColors.hairline;
    final Color text = answered ? AppColors.accent : AppColors.textSecondary;
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(color: border, width: 0.8),
      ),
      child: Text(
        '$index',
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: text,
        ),
      ),
    );
  }
}

class _MaxChip extends StatelessWidget {
  const _MaxChip({required this.max});
  final int max;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Text(
        'máx $max',
        style: TextStyle(
          fontSize: 10,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w600,
          color: AppColors.textTertiary,
        ),
      ),
    );
  }
}
