import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/theme/app_colors.dart';
import '../../../shared/theme/app_motion.dart';
import '../../../shared/widgets/bezel_card.dart';
import '../../../shared/widgets/eyebrow_tag.dart';
import '../../../shared/widgets/mesh_backdrop.dart';
import '../../../shared/widgets/primary_cta.dart';
import '../../../data/sync/sync_worker.dart';
import '../../asignaciones/application/asignaciones_controller.dart';
import '../../asignaciones/data/asignacion_models.dart';
import '../application/evaluacion_controller.dart';
import '../data/evaluacion_models.dart';
import 'widgets/criterion_card.dart';
import 'widgets/meta_panel.dart';

class EvaluacionPage extends ConsumerStatefulWidget {
  const EvaluacionPage({
    super.key,
    required this.prototipoId,
    required this.templateId,
  });

  final String prototipoId;
  final String templateId;

  @override
  ConsumerState<EvaluacionPage> createState() => _EvaluacionPageState();
}

class _EvaluacionPageState extends ConsumerState<EvaluacionPage> {
  int _sectionIndex = 0;
  bool _saving = false;
  bool _submitting = false;
  final ScrollController _scroll = ScrollController();

  EvaluacionKey get _key => EvaluacionKey(
        prototipoId: widget.prototipoId,
        templateId: widget.templateId,
      );

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _snack(String msg, {bool danger = false}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor:
            danger ? AppColors.danger : Colors.white.withValues(alpha: 0.12),
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _onSave() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(evaluacionControllerProvider(_key).notifier)
          .saveDraft();
      if (mounted) _snack('Borrador guardado');
    } on EvaluacionFailure catch (e) {
      if (mounted) _snack(e.message, danger: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _onSubmit() async {
    final state = ref.read(evaluacionControllerProvider(_key)).value;
    if (state == null) return;
    if (!state.isComplete) {
      _snack('Faltan criterios por responder.', danger: true);
      return;
    }

    final confirm = await _ConfirmSubmitDialog.show(context);
    if (confirm != true) return;

    setState(() => _submitting = true);
    try {
      await ref
          .read(evaluacionControllerProvider(_key).notifier)
          .requestSubmit();
      if (mounted) {
        _snack('Evaluación enviada');
        context.go('/');
      }
    } on EvaluacionFailure catch (e) {
      if (mounted) _snack(e.message, danger: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(evaluacionControllerProvider(_key));
    final asignacion = _findAsignacion();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          const MeshBackdrop(),
          SafeArea(
            child: async.when(
              loading: () => const _Loader(),
              error: (e, _) => _ErrorView(
                message: e is EvaluacionFailure
                    ? e.message
                    : 'No se pudo cargar la rúbrica.',
                onRetry: () =>
                    ref.invalidate(evaluacionControllerProvider(_key)),
                onBack: () => context.go('/'),
              ),
              data: (state) => _Body(
                state: state,
                asignacion: asignacion,
                sectionIndex: _sectionIndex.clamp(
                  0,
                  math.max(0, state.rubric.sections.length - 1),
                ),
                scroll: _scroll,
                onSectionTap: (i) {
                  setState(() => _sectionIndex = i);
                  _scroll.animateTo(0,
                      duration: AppMotion.medium, curve: AppMotion.entry);
                },
                onPrev: _sectionIndex > 0
                    ? () {
                        setState(() => _sectionIndex -= 1);
                        _scroll.jumpTo(0);
                      }
                    : null,
                onNext: _sectionIndex < state.rubric.sections.length - 1
                    ? () {
                        setState(() => _sectionIndex += 1);
                        _scroll.jumpTo(0);
                      }
                    : null,
                onScore: (cid, v) => ref
                    .read(evaluacionControllerProvider(_key).notifier)
                    .setScore(cid, v),
                onText: (cid, v) => ref
                    .read(evaluacionControllerProvider(_key).notifier)
                    .setText(cid, v),
                onObservaciones: (v) => ref
                    .read(evaluacionControllerProvider(_key).notifier)
                    .setObservaciones(v),
                onOpinion: (v) => ref
                    .read(evaluacionControllerProvider(_key).notifier)
                    .setOpinionPersonal(v),
                onAcompanamiento: (v) => ref
                    .read(evaluacionControllerProvider(_key).notifier)
                    .setAcompanamiento(v),
                onBack: () => context.go('/'),
                saving: _saving,
                submitting: _submitting,
                onSave: _onSave,
                onSubmit: _onSubmit,
              ),
            ),
          ),
        ],
      ),
    );
  }

  AsignacionItem? _findAsignacion() {
    final list = ref.watch(asignacionesControllerProvider).value;
    if (list == null) return null;
    for (final a in list) {
      if (a.prototipo.id == widget.prototipoId &&
          a.rubric.id == widget.templateId) {
        return a;
      }
    }
    return null;
  }
}

// -----------------------------------------------------------------------------
//  Body
// -----------------------------------------------------------------------------

class _Body extends StatelessWidget {
  const _Body({
    required this.state,
    required this.asignacion,
    required this.sectionIndex,
    required this.scroll,
    required this.onSectionTap,
    required this.onPrev,
    required this.onNext,
    required this.onScore,
    required this.onText,
    required this.onObservaciones,
    required this.onOpinion,
    required this.onAcompanamiento,
    required this.onBack,
    required this.saving,
    required this.submitting,
    required this.onSave,
    required this.onSubmit,
  });

  final EvaluacionFormState state;
  final AsignacionItem? asignacion;
  final int sectionIndex;
  final ScrollController scroll;
  final ValueChanged<int> onSectionTap;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final void Function(String, int) onScore;
  final void Function(String, String) onText;
  final ValueChanged<String> onObservaciones;
  final ValueChanged<int?> onOpinion;
  final ValueChanged<bool?> onAcompanamiento;
  final VoidCallback onBack;
  final bool saving;
  final bool submitting;
  final VoidCallback onSave;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final section = state.rubric.sections[sectionIndex];

    return LayoutBuilder(
      builder: (context, constraints) {
        final double horizontal = constraints.maxWidth >= 1200
            ? (constraints.maxWidth - 1100) / 2
            : constraints.maxWidth >= 800
                ? 48
                : 20;

        return Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(horizontal, 24, horizontal, 0),
              child: _TopBar(
                state: state,
                asignacion: asignacion,
                onBack: onBack,
              ),
            ),
            const SizedBox(height: 20),
            _SectionTabs(
              sections: state.rubric.sections,
              activeIndex: sectionIndex,
              onTap: onSectionTap,
              scores: state.scores,
              textAnswers: state.textAnswers,
              horizontalPadding: horizontal,
            ),
            const SizedBox(height: 4),
            Expanded(
              child: SingleChildScrollView(
                controller: scroll,
                padding: EdgeInsets.fromLTRB(horizontal, 28, horizontal, 140),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionHeader(section: section, index: sectionIndex),
                    const SizedBox(height: 22),
                    ..._criterionCards(section, state),
                    if (sectionIndex == state.rubric.sections.length - 1)
                      MetaPanel(
                        observaciones: state.observaciones,
                        opinionPersonal: state.opinionPersonal,
                        acompanamiento: state.acompanamientoAsesor,
                        onObservacionesChanged: onObservaciones,
                        onOpinionChanged: onOpinion,
                        onAcompanamientoChanged: onAcompanamiento,
                        locked: state.submitted,
                      ),
                  ],
                ),
              ),
            ),
            _Footer(
              state: state,
              horizontal: horizontal,
              onPrev: onPrev,
              onNext: onNext,
              saving: saving,
              submitting: submitting,
              onSave: onSave,
              onSubmit: onSubmit,
            ),
          ],
        );
      },
    );
  }

  List<Widget> _criterionCards(RubricSection section, EvaluacionFormState s) {
    final widgets = <Widget>[];
    for (int i = 0; i < section.criteria.length; i++) {
      final c = section.criteria[i];
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: CriterionCard(
            index: i + 1,
            criterion: c,
            scoreValue: s.scores[c.id],
            textValue: s.textAnswers[c.id],
            onScore: (v) => onScore(c.id, v),
            onText: (v) => onText(c.id, v),
            locked: s.submitted,
          ),
        ),
      );
    }
    return widgets;
  }
}

// -----------------------------------------------------------------------------
//  Top bar — prototipo + progress ring + close
// -----------------------------------------------------------------------------

class _TopBar extends ConsumerWidget {
  const _TopBar({
    required this.state,
    required this.asignacion,
    required this.onBack,
  });

  final EvaluacionFormState state;
  final AsignacionItem? asignacion;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final String title = asignacion?.prototipo.nombre ?? 'Evaluación';
    final String subtitle = asignacion?.prototipo.plantel ??
        (asignacion?.rubric.nombre ?? state.rubric.nombre);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _BackPill(onTap: onBack),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  EyebrowTag(
                    label: state.rubric.tipo == 'exhibicion'
                        ? 'Rúbrica · Exhibición'
                        : 'Rúbrica · Memoria técnica',
                  ),
                  const SizedBox(width: 10),
                  if (state.submitted)
                    _StatusBadge(
                      label: 'Enviada',
                      color: AppColors.success,
                    )
                  else if (state.serverId != null)
                    _StatusBadge(
                      label: 'En progreso',
                      color: AppColors.warning,
                    )
                  else
                    _StatusBadge(
                      label: 'Sin iniciar',
                      color: AppColors.textTertiary,
                    ),
                  const SizedBox(width: 8),
                  _SyncPill(state: state, report: ref.watch(syncReportProvider)),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: theme.textTheme.headlineSmall?.copyWith(height: 1.15),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textTertiary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 18),
        _ProgressRing(progress: state.progress, state: state),
      ],
    );
  }
}

class _BackPill extends StatefulWidget {
  const _BackPill({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_BackPill> createState() => _BackPillState();
}

class _BackPillState extends State<_BackPill> {
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
        child: AnimatedContainer(
          duration: AppMotion.medium,
          curve: AppMotion.smooth,
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white
                .withValues(alpha: _hover ? 0.08 : 0.04),
            shape: BoxShape.circle,
            border: Border.all(
              color: _hover ? AppColors.hairlineStrong : AppColors.hairline,
              width: 0.8,
            ),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.arrow_back_rounded,
            size: 20,
            color: _hover ? AppColors.accent : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncPill extends StatelessWidget {
  const _SyncPill({required this.state, required this.report});
  final EvaluacionFormState state;
  final AsyncValue<SyncReport> report;

  ({String label, Color color, bool spinning}) _resolve() {
    // La fila local ya no tiene cambios pendientes.
    final clean = !state.dirty && !state.submitRequested && state.serverId != null;
    if (state.submitted) {
      return (label: 'Sincronizada', color: AppColors.success, spinning: false);
    }

    final r = report.value;
    final phase = r?.phase ?? SyncPhase.idle;

    if (phase == SyncPhase.syncing) {
      return (label: 'Sincronizando', color: AppColors.warning, spinning: true);
    }
    if (phase == SyncPhase.offline) {
      return (
        label: clean ? 'Offline' : 'Offline · cambios locales',
        color: AppColors.textTertiary,
        spinning: false,
      );
    }
    if (phase == SyncPhase.error && state.dirty) {
      return (label: 'Reintentando', color: AppColors.danger, spinning: false);
    }
    if (state.dirty || state.serverId == null) {
      return (label: 'Guardado local', color: AppColors.textTertiary, spinning: false);
    }
    return (label: 'Sincronizada', color: AppColors.success, spinning: false);
  }

  @override
  Widget build(BuildContext context) {
    final r = _resolve();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: r.color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: r.color.withValues(alpha: 0.30), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (r.spinning)
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.4,
                valueColor: AlwaysStoppedAnimation(r.color),
              ),
            )
          else
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: r.color,
                boxShadow: [
                  BoxShadow(color: r.color.withValues(alpha: 0.5), blurRadius: 5),
                ],
              ),
            ),
          const SizedBox(width: 8),
          Text(
            r.label,
            style: TextStyle(
              color: r.color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressRing extends StatelessWidget {
  const _ProgressRing({required this.progress, required this.state});
  final double progress;
  final EvaluacionFormState state;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 74,
      height: 74,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 74,
            height: 74,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress),
              duration: AppMotion.slow,
              curve: AppMotion.entry,
              builder: (_, value, _) => CircularProgressIndicator(
                value: value,
                strokeWidth: 3,
                backgroundColor: Colors.white.withValues(alpha: 0.06),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppColors.accent),
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${state.completedCount}/${state.rubric.scoringCount}',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'criterios',
                style: TextStyle(
                  fontSize: 9,
                  letterSpacing: 1.3,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
//  Section tabs (horizontal scroll)
// -----------------------------------------------------------------------------

class _SectionTabs extends StatelessWidget {
  const _SectionTabs({
    required this.sections,
    required this.activeIndex,
    required this.onTap,
    required this.scores,
    required this.textAnswers,
    required this.horizontalPadding,
  });

  final List<RubricSection> sections;
  final int activeIndex;
  final ValueChanged<int> onTap;
  final Map<String, int> scores;
  final Map<String, String> textAnswers;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        itemCount: sections.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final s = sections[i];
          final int answered = _countAnswered(s);
          final int total = s.criteria
              .where((c) =>
                  c.kind == CriterionKind.scale ||
                  c.kind == CriterionKind.boolean ||
                  c.kind == CriterionKind.textKey)
              .length;
          return _SectionTab(
            index: i + 1,
            name: s.nombre,
            answered: answered,
            total: total,
            active: i == activeIndex,
            onTap: () => onTap(i),
          );
        },
      ),
    );
  }

  int _countAnswered(RubricSection s) {
    int n = 0;
    for (final c in s.criteria) {
      switch (c.kind) {
        case CriterionKind.scale:
        case CriterionKind.boolean:
          if (scores.containsKey(c.id)) n++;
          break;
        case CriterionKind.textKey:
          if ((textAnswers[c.id] ?? '').isNotEmpty) n++;
          break;
      }
    }
    return n;
  }
}

class _SectionTab extends StatefulWidget {
  const _SectionTab({
    required this.index,
    required this.name,
    required this.answered,
    required this.total,
    required this.active,
    required this.onTap,
  });

  final int index;
  final String name;
  final int answered;
  final int total;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_SectionTab> createState() => _SectionTabState();
}

class _SectionTabState extends State<_SectionTab> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bool complete = widget.total > 0 && widget.answered >= widget.total;
    final bool active = widget.active;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppMotion.medium,
          curve: AppMotion.smooth,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: active
                ? AppColors.accent.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: _hover ? 0.06 : 0.03),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: active
                  ? AppColors.accent.withValues(alpha: 0.55)
                  : AppColors.hairline,
              width: active ? 1 : 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: complete
                      ? AppColors.success.withValues(alpha: 0.22)
                      : Colors.white.withValues(alpha: 0.07),
                  border: Border.all(
                    color: complete
                        ? AppColors.success.withValues(alpha: 0.55)
                        : AppColors.hairline,
                    width: 0.6,
                  ),
                ),
                child: complete
                    ? Icon(
                        Icons.check_rounded,
                        size: 11,
                        color: AppColors.success,
                      )
                    : Text(
                        '${widget.index}',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 190),
                child: Text(
                  widget.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1,
                    color: active ? AppColors.accent : AppColors.textPrimary,
                  ),
                ),
              ),
              if (widget.total > 0) ...[
                const SizedBox(width: 10),
                Text(
                  '${widget.answered}/${widget.total}',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10.5,
                    letterSpacing: 0.3,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
//  Section header
// -----------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.section, required this.index});
  final RubricSection section;
  final int index;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SECCIÓN ${index + 1}',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 10.5,
            letterSpacing: 2.4,
            fontWeight: FontWeight.w600,
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          section.nombre,
          style: theme.textTheme.displaySmall?.copyWith(
            fontSize: 30,
            height: 1.1,
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
//  Footer — prev/next + save + submit
// -----------------------------------------------------------------------------

class _Footer extends StatelessWidget {
  const _Footer({
    required this.state,
    required this.horizontal,
    required this.onPrev,
    required this.onNext,
    required this.saving,
    required this.submitting,
    required this.onSave,
    required this.onSubmit,
  });

  final EvaluacionFormState state;
  final double horizontal;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final bool saving;
  final bool submitting;
  final VoidCallback onSave;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final bool canSubmit = state.isComplete && !state.submitted && !submitting;
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontal, 12, horizontal, 24),
      child: BezelCard(
        outerRadius: 28,
        shellPadding: 5,
        corePadding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
        shellColor: Colors.white.withValues(alpha: 0.055),
        child: Row(
          children: [
            _NavIcon(
              icon: Icons.chevron_left_rounded,
              onTap: onPrev,
            ),
            const SizedBox(width: 8),
            _NavIcon(
              icon: Icons.chevron_right_rounded,
              onTap: onNext,
            ),
            const SizedBox(width: 18),
            if (!state.submitted)
              _GhostButton(
                label: saving ? 'Guardando…' : 'Guardar borrador',
                onTap: saving || submitting ? null : onSave,
              ),
            const Spacer(),
            if (!state.submitted)
              PrimaryCta(
                label: submitting ? 'Enviando…' : 'Enviar evaluación',
                icon: Icons.send_rounded,
                busy: submitting,
                onPressed: canSubmit ? onSubmit : null,
              )
            else
              _GhostButton(
                label: 'Evaluación enviada',
                onTap: null,
              ),
          ],
        ),
      ),
    );
  }
}

class _NavIcon extends StatefulWidget {
  const _NavIcon({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  State<_NavIcon> createState() => _NavIconState();
}

class _NavIconState extends State<_NavIcon> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onTap != null;
    return MouseRegion(
      cursor:
          enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppMotion.medium,
          curve: AppMotion.smooth,
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: _hover && enabled ? 0.08 : 0.03),
            shape: BoxShape.circle,
            border: Border.all(
              color: _hover && enabled
                  ? AppColors.hairlineStrong
                  : AppColors.hairline,
              width: 0.8,
            ),
          ),
          child: Icon(
            widget.icon,
            size: 18,
            color: enabled ? AppColors.textPrimary : AppColors.textDisabled,
          ),
        ),
      ),
    );
  }
}

class _GhostButton extends StatefulWidget {
  const _GhostButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  State<_GhostButton> createState() => _GhostButtonState();
}

class _GhostButtonState extends State<_GhostButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onTap != null;
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
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: _hover && enabled ? 0.08 : 0.04),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: _hover && enabled
                  ? AppColors.hairlineStrong
                  : AppColors.hairline,
              width: 0.8,
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
              color: enabled ? AppColors.textPrimary : AppColors.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
//  Loader / Error / Confirm dialog
// -----------------------------------------------------------------------------

class _Loader extends StatelessWidget {
  const _Loader();

  @override
  Widget build(BuildContext context) => Center(
        child: SizedBox(
          width: 36,
          height: 36,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
          ),
        ),
      );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.onRetry,
    required this.onBack,
  });
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: BezelCard(
            outerRadius: 28,
            shellPadding: 5,
            corePadding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No se pudo cargar la rúbrica',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    _GhostButton(label: 'Volver', onTap: onBack),
                    const SizedBox(width: 10),
                    PrimaryCta(
                      label: 'Reintentar',
                      icon: Icons.refresh_rounded,
                      onPressed: onRetry,
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
}

class _ConfirmSubmitDialog extends StatelessWidget {
  const _ConfirmSubmitDialog();

  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (_) => const _ConfirmSubmitDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: BezelCard(
          outerRadius: 30,
          shellPadding: 6,
          corePadding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EyebrowTag(label: 'Confirmar envío', dotColor: AppColors.warning),
              const SizedBox(height: 14),
              Text(
                '¿Enviar la evaluación?',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 10),
              Text(
                'Una vez enviada no se podrá editar. Si necesitas corregirla después, un admin puede reabrirla.',
                style: TextStyle(color: AppColors.textSecondary, height: 1.45),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  _GhostButton(
                    label: 'Cancelar',
                    onTap: () => Navigator.of(context).pop(false),
                  ),
                  const Spacer(),
                  PrimaryCta(
                    label: 'Enviar',
                    icon: Icons.send_rounded,
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
