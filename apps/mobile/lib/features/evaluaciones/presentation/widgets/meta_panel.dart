import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/theme/app_motion.dart';
import '../../../../shared/widgets/bezel_card.dart';
import '../../../../shared/widgets/eyebrow_tag.dart';

/// Panel de cierre — observaciones libres + opinión personal 0-100 + switch
/// de acompañamiento del asesor. Renderizado al final de la última sección.
class MetaPanel extends StatelessWidget {
  const MetaPanel({
    super.key,
    required this.observaciones,
    required this.opinionPersonal,
    required this.acompanamiento,
    required this.onObservacionesChanged,
    required this.onOpinionChanged,
    required this.onAcompanamientoChanged,
    required this.locked,
  });

  final String? observaciones;
  final int? opinionPersonal;
  final bool? acompanamiento;
  final ValueChanged<String> onObservacionesChanged;
  final ValueChanged<int?> onOpinionChanged;
  final ValueChanged<bool?> onAcompanamientoChanged;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 28),
        EyebrowTag(label: 'Cierre · Notas finales', dotColor: AppColors.warning),
        const SizedBox(height: 12),
        Text(
          'Antes de enviar',
          style: theme.textTheme.headlineSmall?.copyWith(height: 1.15),
        ),
        const SizedBox(height: 8),
        Text(
          'Campos opcionales; complementan el puntaje pero no cambian el total.',
          style: TextStyle(color: AppColors.textTertiary, height: 1.45),
        ),
        const SizedBox(height: 22),
        _ObservacionesCard(
          initial: observaciones,
          onChanged: onObservacionesChanged,
          locked: locked,
        ),
        const SizedBox(height: 14),
        _OpinionCard(
          value: opinionPersonal,
          onChanged: onOpinionChanged,
          locked: locked,
        ),
        const SizedBox(height: 14),
        _AcompanamientoCard(
          value: acompanamiento,
          onChanged: onAcompanamientoChanged,
          locked: locked,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Observaciones — textarea con autosave debounced
// ---------------------------------------------------------------------------

class _ObservacionesCard extends StatefulWidget {
  const _ObservacionesCard({
    required this.initial,
    required this.onChanged,
    required this.locked,
  });
  final String? initial;
  final ValueChanged<String> onChanged;
  final bool locked;

  @override
  State<_ObservacionesCard> createState() => _ObservacionesCardState();
}

class _ObservacionesCardState extends State<_ObservacionesCard> {
  late final TextEditingController _controller;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      widget.onChanged(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool hasContent = _controller.text.trim().isNotEmpty;
    return BezelCard(
      outerRadius: 26,
      shellPadding: 5,
      corePadding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
      shellColor: hasContent
          ? Colors.white.withValues(alpha: 0.055)
          : Colors.white.withValues(alpha: 0.035),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit_note_rounded,
                  size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 10),
              Text(
                'Observaciones',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              _OptionalChip(),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            readOnly: widget.locked,
            minLines: 3,
            maxLines: 8,
            onChanged: _onChanged,
            style: Theme.of(context).textTheme.bodyMedium,
            decoration: InputDecoration(
              hintText:
                  'Aspectos relevantes, sugerencias al equipo, puntos a destacar…',
              hintStyle: TextStyle(color: AppColors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Opinión personal — slider 0-100 con display grande
// ---------------------------------------------------------------------------

class _OpinionCard extends StatefulWidget {
  const _OpinionCard({
    required this.value,
    required this.onChanged,
    required this.locked,
  });
  final int? value;
  final ValueChanged<int?> onChanged;
  final bool locked;

  @override
  State<_OpinionCard> createState() => _OpinionCardState();
}

class _OpinionCardState extends State<_OpinionCard> {
  double? _preview;

  double _current() => _preview ?? (widget.value?.toDouble() ?? 50);
  bool get _isSet => widget.value != null || _preview != null;

  void _commit(double v) {
    final int rounded = v.round();
    setState(() => _preview = rounded.toDouble());
    widget.onChanged(rounded);
  }

  void _clear() {
    setState(() => _preview = null);
    widget.onChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final double v = _current();
    return BezelCard(
      outerRadius: 26,
      shellPadding: 5,
      corePadding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
      shellColor: _isSet
          ? Colors.white.withValues(alpha: 0.055)
          : Colors.white.withValues(alpha: 0.035),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights_rounded,
                  size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 10),
              Text(
                'Opinión personal',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              _OptionalChip(),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Qué tanto te convence el prototipo, más allá de la rúbrica.',
            style: TextStyle(color: AppColors.textTertiary, height: 1.4),
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: v),
                duration: AppMotion.fast,
                curve: AppMotion.smooth,
                builder: (_, value, _) => Text(
                  _isSet ? value.round().toString() : '—',
                  style: theme.textTheme.displayMedium?.copyWith(
                    fontSize: 48,
                    fontWeight: FontWeight.w700,
                    height: 1,
                    color: _isSet ? AppColors.accent : AppColors.textTertiary,
                  ),
                ),
              ),
              if (_isSet)
                Padding(
                  padding: const EdgeInsets.only(left: 6, bottom: 8),
                  child: Text(
                    '/ 100',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textTertiary,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              const Spacer(),
              if (_isSet && !widget.locked)
                _TextButton(label: 'Quitar', onTap: _clear),
            ],
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              activeTrackColor: AppColors.accent,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.08),
              thumbColor: AppColors.accent,
              overlayColor: AppColors.accent.withValues(alpha: 0.12),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              valueIndicatorShape: const PaddleSliderValueIndicatorShape(),
              valueIndicatorColor: AppColors.accent,
              showValueIndicator: ShowValueIndicator.onDrag,
            ),
            child: Slider(
              value: v.clamp(0, 100),
              min: 0,
              max: 100,
              divisions: 100,
              label: v.round().toString(),
              onChanged: widget.locked ? null : (x) => _commit(x),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _ScaleTick(label: '0 · bajo'),
              _ScaleTick(label: '50'),
              _ScaleTick(label: '100 · alto'),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScaleTick extends StatelessWidget {
  const _ScaleTick({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontFamily: 'monospace',
          letterSpacing: 0.6,
          color: AppColors.textTertiary,
        ),
      );
}

// ---------------------------------------------------------------------------
// Acompañamiento del asesor — tri-state pill group
// ---------------------------------------------------------------------------

class _AcompanamientoCard extends StatelessWidget {
  const _AcompanamientoCard({
    required this.value,
    required this.onChanged,
    required this.locked,
  });
  final bool? value;
  final ValueChanged<bool?> onChanged;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final bool answered = value != null;
    return BezelCard(
      outerRadius: 26,
      shellPadding: 5,
      corePadding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
      shellColor: answered
          ? Colors.white.withValues(alpha: 0.055)
          : Colors.white.withValues(alpha: 0.035),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.groups_2_rounded,
                  size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Acompañamiento del asesor',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              _OptionalChip(),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '¿Se observó al equipo respaldado por un asesor durante la evaluación?',
            style: TextStyle(color: AppColors.textTertiary, height: 1.4),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _Pill(
                  label: 'Sí',
                  icon: Icons.check_rounded,
                  tone: AppColors.success,
                  selected: value == true,
                  onTap: locked
                      ? null
                      : () => onChanged(value == true ? null : true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Pill(
                  label: 'No',
                  icon: Icons.close_rounded,
                  tone: AppColors.danger,
                  selected: value == false,
                  onTap: locked
                      ? null
                      : () => onChanged(value == false ? null : false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatefulWidget {
  const _Pill({
    required this.label,
    required this.icon,
    required this.tone,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color tone;
  final bool selected;
  final VoidCallback? onTap;

  @override
  State<_Pill> createState() => _PillState();
}

class _PillState extends State<_Pill> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onTap != null;
    final bool sel = widget.selected;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppMotion.medium,
          curve: AppMotion.smooth,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: sel
                ? widget.tone.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: _hover && enabled ? 0.06 : 0.03),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: sel
                  ? widget.tone.withValues(alpha: 0.55)
                  : AppColors.hairline,
              width: sel ? 1 : 0.8,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.icon,
                size: 16,
                color: sel ? widget.tone : AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                  color: sel ? widget.tone : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

class _OptionalChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Text(
        'opcional',
        style: TextStyle(
          fontSize: 9.5,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w600,
          color: AppColors.textTertiary,
        ),
      ),
    );
  }
}

class _TextButton extends StatefulWidget {
  const _TextButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  State<_TextButton> createState() => _TextButtonState();
}

class _TextButtonState extends State<_TextButton> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
              color: _hover ? AppColors.textPrimary : AppColors.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}
