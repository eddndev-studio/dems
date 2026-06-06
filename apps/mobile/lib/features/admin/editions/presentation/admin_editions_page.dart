import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/theme/app_motion.dart';
import '../../../../shared/widgets/eyebrow_tag.dart';
import '../../../../shared/widgets/stagger_reveal.dart';
import '../application/admin_editions_controller.dart';
import '../data/edition_models.dart';
import 'widgets/edition_form_dialog.dart';

class AdminEditionsPage extends ConsumerWidget {
  const AdminEditionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminEditionsControllerProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final padX = w >= 1100
            ? 56.0
            : w >= 760
                ? 32.0
                : 18.0;
        final dense = w >= 760;

        return RefreshIndicator.adaptive(
          onRefresh: () =>
              ref.read(adminEditionsControllerProvider.notifier).refresh(),
          backgroundColor: AppColors.surface1,
          color: AppColors.accent,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(padX, 28, padX, 0),
                  child: _Header(
                    total: async.asData?.value.length,
                    active: async.asData?.value
                        .where((e) => e.active)
                        .firstOrNull,
                    onNew: () => EditionFormDialog.show(context),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 28)),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(padX, 0, padX, 60),
                sliver: async.when(
                  data: (items) {
                    if (items.isEmpty) {
                      return SliverToBoxAdapter(
                        child: _EmptyState(
                          onNew: () => EditionFormDialog.show(context),
                        ),
                      );
                    }
                    return dense
                        ? _EditionsTable(items: items)
                        : _EditionsList(items: items);
                  },
                  loading: () => const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 60),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
                  error: (e, _) => SliverToBoxAdapter(
                    child: _ErrorBanner(
                      message:
                          e is EditionsFailure ? e.message : e.toString(),
                      onRetry: () => ref
                          .read(adminEditionsControllerProvider.notifier)
                          .refresh(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
//  Header
// ──────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.total,
    required this.active,
    required this.onNew,
  });

  final int? total;
  final Edition? active;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final summary = total == null
        ? 'Cargando…'
        : active == null
            ? '${total ?? 0} ediciones · ninguna activa'
            : '${total ?? 0} ediciones · vigente ${active!.year} (${active!.name})';

    return LayoutBuilder(
      builder: (context, constraints) {
        final stack = constraints.maxWidth < 520;
        final left = Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const StaggerReveal(
                child: EyebrowTag(label: 'Administración · Ediciones'),
              ),
              const SizedBox(height: 16),
              StaggerReveal(
                delay: const Duration(milliseconds: 80),
                child: Text(
                  'Ediciones del concurso',
                  style:
                      text.displaySmall?.copyWith(fontSize: 36, height: 1.05),
                ),
              ),
              const SizedBox(height: 6),
              StaggerReveal(
                delay: const Duration(milliseconds: 140),
                child: Text(
                  summary,
                  style: text.bodyMedium
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        );
        final cta = StaggerReveal(
          delay: const Duration(milliseconds: 180),
          child: FilledButton.icon(
            onPressed: onNew,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Nueva edición'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        );

        return stack
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  left,
                  const SizedBox(height: 16),
                  Align(alignment: Alignment.centerLeft, child: cta),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [left, const SizedBox(width: 18), cta],
              );
      },
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
//  Table (≥ 760)
// ──────────────────────────────────────────────────────────────────────────

class _EditionsTable extends StatelessWidget {
  const _EditionsTable({required this.items});
  final List<Edition> items;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Column(
          children: [
            const _TableHeader(),
            for (var i = 0; i < items.length; i++)
              _EditionRow(edition: items[i], divider: i < items.length - 1),
          ],
        ),
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.4,
      color: AppColors.textTertiary,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.hairline)),
      ),
      child: Row(
        children: [
          SizedBox(width: 92, child: Text('AÑO', style: style)),
          Expanded(child: Text('NOMBRE', style: style)),
          SizedBox(width: 140, child: Text('FASE', style: style)),
          SizedBox(width: 120, child: Text('ESTADO', style: style)),
          SizedBox(
            width: 130,
            child:
                Text('ACCIONES', style: style, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

class _EditionRow extends ConsumerStatefulWidget {
  const _EditionRow({required this.edition, required this.divider});

  final Edition edition;
  final bool divider;

  @override
  ConsumerState<_EditionRow> createState() => _EditionRowState();
}

class _EditionRowState extends ConsumerState<_EditionRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.edition;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: AppMotion.fast,
        padding: const EdgeInsets.fromLTRB(20, 14, 14, 14),
        decoration: BoxDecoration(
          color: _hover ? Colors.white.withValues(alpha: 0.025) : null,
          border: Border(
            bottom: BorderSide(
              color: widget.divider ? AppColors.hairline : Colors.transparent,
            ),
          ),
        ),
        child: Row(
          children: [
            SizedBox(width: 92, child: _YearChip(year: e.year)),
            Expanded(
              child: Text(
                e.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            SizedBox(width: 140, child: _PhaseBadge(phase: e.phase)),
            SizedBox(width: 120, child: _StatusBadge(active: e.active)),
            SizedBox(
              width: 130,
              child: _RowActions(edition: e, ref: ref),
            ),
          ],
        ),
      ),
    );
  }
}

class _RowActions extends StatelessWidget {
  const _RowActions({required this.edition, required this.ref});

  final Edition edition;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Tooltip(
          message: 'Editar',
          child: IconButton(
            onPressed: () => EditionFormDialog.show(context, initial: edition),
            icon: const Icon(Icons.edit_outlined, size: 16),
            color: AppColors.textSecondary,
            visualDensity: VisualDensity.compact,
          ),
        ),
        if (!edition.active)
          Tooltip(
            message: 'Marcar como activa',
            child: IconButton(
              onPressed: () async {
                try {
                  await ref
                      .read(adminEditionsControllerProvider.notifier)
                      .toggleActive(edition);
                  if (context.mounted) {
                    _toast(context, 'Edición ${edition.year} activada.');
                  }
                } on EditionsFailure catch (e) {
                  if (context.mounted) _toast(context, e.message, isError: true);
                }
              },
              icon: const Icon(Icons.power_settings_new_rounded, size: 16),
              color: AppColors.success,
              visualDensity: VisualDensity.compact,
            ),
          ),
        _MoreMenu(edition: edition, ref: ref),
      ],
    );
  }
}

class _MoreMenu extends StatelessWidget {
  const _MoreMenu({required this.edition, required this.ref});

  final Edition edition;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Más',
      color: AppColors.surface1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppColors.hairline),
      ),
      icon: Icon(Icons.more_horiz_rounded,
          size: 16, color: AppColors.textSecondary),
      onSelected: (v) async {
        if (v.startsWith('phase:')) {
          final target = EditionPhase.fromApi(v.substring('phase:'.length));
          await _changePhase(context, ref, edition, target);
        } else if (v == 'deactivate') {
          try {
            await ref
                .read(adminEditionsControllerProvider.notifier)
                .toggleActive(edition);
            if (context.mounted) _toast(context, 'Edición desactivada.');
          } on EditionsFailure catch (e) {
            if (context.mounted) _toast(context, e.message, isError: true);
          }
        } else if (v == 'delete') {
          final confirmed = await _confirmDelete(context, edition);
          if (confirmed != true) return;
          try {
            await ref
                .read(adminEditionsControllerProvider.notifier)
                .delete(edition.id);
            if (context.mounted) _toast(context, 'Edición eliminada.');
          } on EditionsFailure catch (e) {
            if (context.mounted) _toast(context, e.message, isError: true);
          }
        }
      },
      itemBuilder: (_) => [
        for (final target in _nextPhases(edition.phase))
          PopupMenuItem<String>(
            value: 'phase:${target.apiValue}',
            child: Row(
              children: [
                Icon(_phaseActionIcon(edition.phase, target),
                    size: 14, color: AppColors.accent),
                const SizedBox(width: 10),
                Text(_phaseActionLabel(edition.phase, target)),
              ],
            ),
          ),
        if (edition.active)
          PopupMenuItem<String>(
            value: 'deactivate',
            child: Row(
              children: [
                Icon(Icons.toggle_off_outlined,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 10),
                const Text('Desactivar'),
              ],
            ),
          ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline_rounded,
                  size: 14, color: AppColors.danger),
              const SizedBox(width: 10),
              Text('Eliminar', style: TextStyle(color: AppColors.danger)),
            ],
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
//  Mobile list (< 760)
// ──────────────────────────────────────────────────────────────────────────

class _EditionsList extends StatelessWidget {
  const _EditionsList({required this.items});
  final List<Edition> items;

  @override
  Widget build(BuildContext context) {
    return SliverList.builder(
      itemCount: items.length,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _EditionCard(edition: items[i]),
      ),
    );
  }
}

class _EditionCard extends ConsumerWidget {
  const _EditionCard({required this.edition});
  final Edition edition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          _YearChip(year: edition.year, big: true),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  edition.name,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _PhaseBadge(phase: edition.phase),
                    _StatusBadge(active: edition.active),
                  ],
                ),
              ],
            ),
          ),
          _MoreMenuMobile(edition: edition, ref: ref),
        ],
      ),
    );
  }
}

class _MoreMenuMobile extends StatelessWidget {
  const _MoreMenuMobile({required this.edition, required this.ref});

  final Edition edition;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Acciones',
      color: AppColors.surface1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppColors.hairline),
      ),
      icon: Icon(Icons.more_vert_rounded,
          size: 18, color: AppColors.textSecondary),
      onSelected: (v) async {
        if (v.startsWith('phase:')) {
          final target = EditionPhase.fromApi(v.substring('phase:'.length));
          await _changePhase(context, ref, edition, target);
          return;
        }
        switch (v) {
          case 'edit':
            EditionFormDialog.show(context, initial: edition);
            break;
          case 'toggle':
            try {
              await ref
                  .read(adminEditionsControllerProvider.notifier)
                  .toggleActive(edition);
              if (context.mounted) {
                _toast(
                  context,
                  edition.active
                      ? 'Edición desactivada.'
                      : 'Edición ${edition.year} activada.',
                );
              }
            } on EditionsFailure catch (e) {
              if (context.mounted) _toast(context, e.message, isError: true);
            }
            break;
          case 'delete':
            final ok = await _confirmDelete(context, edition);
            if (ok != true) return;
            try {
              await ref
                  .read(adminEditionsControllerProvider.notifier)
                  .delete(edition.id);
              if (context.mounted) _toast(context, 'Edición eliminada.');
            } on EditionsFailure catch (e) {
              if (context.mounted) _toast(context, e.message, isError: true);
            }
            break;
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem<String>(value: 'edit', child: Text('Editar')),
        for (final target in _nextPhases(edition.phase))
          PopupMenuItem<String>(
            value: 'phase:${target.apiValue}',
            child: Text(_phaseActionLabel(edition.phase, target)),
          ),
        PopupMenuItem<String>(
          value: 'toggle',
          child: Text(edition.active ? 'Desactivar' : 'Marcar como activa'),
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem<String>(
          value: 'delete',
          child: Text('Eliminar', style: TextStyle(color: AppColors.danger)),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
//  Shared atoms
// ──────────────────────────────────────────────────────────────────────────

class _YearChip extends StatelessWidget {
  const _YearChip({required this.year, this.big = false});
  final int year;
  final bool big;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: big ? 64 : 72,
      padding: EdgeInsets.symmetric(vertical: big ? 12 : 8),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(big ? 14 : 10),
        border: Border.all(color: AppColors.hairline),
      ),
      alignment: Alignment.center,
      child: Text(
        '$year',
        style: TextStyle(
          fontSize: big ? 20 : 15,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _PhaseBadge extends StatelessWidget {
  const _PhaseBadge({required this.phase});
  final EditionPhase phase;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (phase) {
      EditionPhase.preparacion => (AppColors.accent, Icons.edit_note_rounded),
      EditionPhase.evaluacion => (AppColors.success, Icons.how_to_vote_outlined),
      EditionPhase.cerrada => (AppColors.textTertiary, Icons.lock_outline_rounded),
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: color.withValues(alpha: 0.32)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 6),
            Text(
              phase.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fases alcanzables en un paso desde [p] (adyacencia preparacion ↔ evaluacion
/// ↔ cerrada), espejo del backend.
List<EditionPhase> _nextPhases(EditionPhase p) => switch (p) {
      EditionPhase.preparacion => const [EditionPhase.evaluacion],
      EditionPhase.evaluacion =>
        const [EditionPhase.cerrada, EditionPhase.preparacion],
      EditionPhase.cerrada => const [EditionPhase.evaluacion],
    };

String _phaseActionLabel(EditionPhase from, EditionPhase to) {
  if (to == EditionPhase.evaluacion && from == EditionPhase.preparacion) {
    return 'Iniciar evaluación';
  }
  if (to == EditionPhase.cerrada) return 'Cerrar edición';
  if (to == EditionPhase.preparacion) return 'Reabrir preparación';
  return 'Reabrir evaluación';
}

IconData _phaseActionIcon(EditionPhase from, EditionPhase to) {
  if (to == EditionPhase.cerrada) return Icons.lock_outline_rounded;
  if (to == EditionPhase.preparacion) return Icons.undo_rounded;
  return Icons.play_arrow_rounded; // → evaluacion
}

/// Confirma (cuando aplica) y aplica una transición de fase.
Future<void> _changePhase(
  BuildContext context,
  WidgetRef ref,
  Edition edition,
  EditionPhase target,
) async {
  // Iniciar evaluación congela las rúbricas: pedir confirmación explícita.
  if (edition.phase == EditionPhase.preparacion &&
      target == EditionPhase.evaluacion) {
    final ok = await _confirmStartEvaluation(context, edition);
    if (ok != true) return;
  }
  try {
    await ref
        .read(adminEditionsControllerProvider.notifier)
        .setPhase(edition.id, target);
    if (context.mounted) {
      _toast(context, 'Edición ${edition.year}: ${target.label}.');
    }
  } on EditionsFailure catch (e) {
    if (context.mounted) _toast(context, e.message, isError: true);
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.success : AppColors.textTertiary;
    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.6),
                        blurRadius: 6,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            active ? 'Activa' : 'Inactiva',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
//  Empty / error / toast / confirm
// ──────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onNew});
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.hairline),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.event_outlined,
                  color: AppColors.textTertiary, size: 24),
            ),
            const SizedBox(height: 16),
            Text('Sin ediciones registradas', style: text.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Crea la primera edición para empezar a registrar prototipos y rúbricas.',
              style:
                  text.bodyMedium?.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onNew,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Crear edición'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: AppColors.danger.withValues(alpha: 0.32),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(Icons.error_outline_rounded,
                  color: AppColors.danger, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No se pudieron cargar las ediciones',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    message,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

void _toast(BuildContext context, String message, {bool isError = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: isError
          ? AppColors.danger.withValues(alpha: 0.92)
          : AppColors.surface2,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 3),
    ),
  );
}

Future<bool?> _confirmStartEvaluation(BuildContext context, Edition edition) {
  return showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (ctx) => Dialog(
      backgroundColor: AppColors.surface1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AppColors.hairline),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Iniciar evaluación',
                  style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'La edición ${edition.year} pasará a fase de evaluación. '
                'Las rúbricas quedarán congeladas: ya no podrás crear, editar '
                'ni borrar su estructura. Podrás reabrir a preparación solo '
                'mientras no existan evaluaciones.',
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: AppColors.hairlineStrong),
                        foregroundColor: AppColors.textSecondary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Iniciar evaluación'),
                    ),
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

Future<bool?> _confirmDelete(BuildContext context, Edition edition) {
  return showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (ctx) => Dialog(
      backgroundColor: AppColors.surface1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AppColors.hairline),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Eliminar edición',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Se eliminará la edición ${edition.year} (${edition.name}). '
                'Si tiene rúbricas o prototipos asociados, el API rechazará la '
                'acción — desactívala en su lugar.',
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: AppColors.hairlineStrong),
                        foregroundColor: AppColors.textSecondary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.danger,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Eliminar'),
                    ),
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
