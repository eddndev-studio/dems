import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/theme/app_motion.dart';
import '../../../../shared/widgets/eyebrow_tag.dart';
import '../../../../shared/widgets/stagger_reveal.dart';
import '../../editions/application/admin_editions_controller.dart';
import '../../editions/data/edition_models.dart';
import '../../prototipos/application/admin_prototipos_controller.dart';
import '../../prototipos/data/prototipo_models.dart';
import '../application/admin_assignments_controller.dart';
import '../data/admin_assignments_repository.dart';
import '../data/assignment_models.dart';
import 'widgets/assign_jurado_sheet.dart';
import 'widgets/bulk_assign_sheet.dart';

class AdminAssignmentsPage extends ConsumerWidget {
  const AdminAssignmentsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prototipos = ref.watch(filteredPrototiposProvider);
    final raw = ref.watch(adminPrototiposControllerProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final padX = w >= 1100
            ? 56.0
            : w >= 760
                ? 32.0
                : 18.0;

        return RefreshIndicator.adaptive(
          onRefresh: () =>
              ref.read(adminPrototiposControllerProvider.notifier).refresh(),
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
                    total: raw.asData?.value.length,
                    visible: prototipos.asData?.value.length,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(padX, 20, padX, 0),
                  child: const _BulkAssignBar(),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(padX, 16, padX, 16),
                  child: const _FilterBar(),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(padX, 0, padX, 60),
                sliver: prototipos.when(
                  data: (items) {
                    if (items.isEmpty) {
                      return const SliverToBoxAdapter(child: _EmptyState());
                    }
                    return SliverList.builder(
                      itemCount: items.length,
                      itemBuilder: (_, i) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _PrototipoExpansion(prototipo: items[i]),
                      ),
                    );
                  },
                  loading: () => const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 60),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
                  error: (e, _) => SliverToBoxAdapter(
                    child: _ErrorBanner(
                      message: e.toString(),
                      onRetry: () => ref
                          .read(adminPrototiposControllerProvider.notifier)
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
  const _Header({required this.total, required this.visible});
  final int? total;
  final int? visible;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final summary = total == null
        ? 'Cargando…'
        : visible == total
            ? '$total ${total == 1 ? "prototipo" : "prototipos"} en este panel'
            : '$visible de $total visibles tras los filtros';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const StaggerReveal(
          child: EyebrowTag(label: 'Administración · Asignaciones'),
        ),
        const SizedBox(height: 16),
        StaggerReveal(
          delay: const Duration(milliseconds: 80),
          child: Text(
            'Asignar jurados a prototipos',
            style: text.displaySmall?.copyWith(fontSize: 36, height: 1.05),
          ),
        ),
        const SizedBox(height: 6),
        StaggerReveal(
          delay: const Duration(milliseconds: 140),
          child: Text(
            summary,
            style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
//  Bulk assign by categoría (= área)
// ──────────────────────────────────────────────────────────────────────────

class _BulkAssignBar extends ConsumerStatefulWidget {
  const _BulkAssignBar();
  @override
  ConsumerState<_BulkAssignBar> createState() => _BulkAssignBarState();
}

class _BulkAssignBarState extends ConsumerState<_BulkAssignBar> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: FilledButton.icon(
        onPressed: _busy ? null : _open,
        icon: _busy
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 1.6),
              )
            : const Icon(Icons.groups_2_outlined, size: 16),
        label: Text(_busy ? 'Asignando…' : 'Asignar jurados por categoría'),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent.withValues(alpha: 0.20),
          foregroundColor: AppColors.textPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle:
              const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: AppColors.accent.withValues(alpha: 0.45)),
          ),
        ),
      ),
    );
  }

  Future<void> _open() async {
    final filter = ref.read(prototiposFilterProvider);
    final sel = await BulkAssignSheet.show(
      context,
      initialEditionId: filter.editionId,
    );
    if (sel == null || !mounted) return;
    // Capturamos el container ANTES del await: si el sheet/página se desmonta
    // mientras la petición está en vuelo, invalidar vía `ref` (ligado al State)
    // lanzaría StateError; el container sigue vivo, así que la invalidación
    // corre igual — la escritura en el servidor ya ocurrió y las cachés quedan
    // obsoletas de todos modos.
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() => _busy = true);
    try {
      final res = await ref.read(adminAssignmentsRepositoryProvider).bulkAssign(
            juradoIds: sel.juradoIds,
            categoriaId: sel.categoriaId,
            templateId: sel.templateId,
          );
      // Las cachés por prototipo y el listado quedan obsoletas tras la
      // asignación masiva: invalidamos para que los conteos se refresquen.
      container.invalidate(prototipoAssignmentsControllerProvider);
      container.invalidate(adminPrototiposControllerProvider);
      if (mounted) {
        final msg = res.prototipos == 0
            ? 'La categoría no tiene prototipos en esta edición.'
            : '${res.created} asignaciones creadas'
                '${res.skipped > 0 ? " · ${res.skipped} ya existían" : ""} '
                '(${res.jurados} jurados × ${res.prototipos} prototipos).';
        _toast(context, msg, isError: res.prototipos == 0);
      }
    } on AssignmentFailure catch (e) {
      if (mounted) _toast(context, e.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

// ──────────────────────────────────────────────────────────────────────────
//  Filter bar (reusa el filtro de prototipos)
// ──────────────────────────────────────────────────────────────────────────

class _FilterBar extends ConsumerStatefulWidget {
  const _FilterBar();

  @override
  ConsumerState<_FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends ConsumerState<_FilterBar> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = ref.read(prototiposFilterProvider).query;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(prototiposFilterProvider);
    final editions = ref.watch(adminEditionsControllerProvider);
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 220, maxWidth: 360),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => ref
                .read(prototiposFilterProvider.notifier)
                .set(filter.copyWith(query: v)),
            style: const TextStyle(fontSize: 13.5),
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.search_rounded,
                  size: 18, color: AppColors.textTertiary),
              hintText: 'Buscar por folio o nombre…',
              hintStyle:
                  TextStyle(color: AppColors.textTertiary, fontSize: 13.5),
              filled: true,
              fillColor: AppColors.surface1,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(99),
                borderSide: BorderSide(color: AppColors.hairline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(99),
                borderSide: BorderSide(color: AppColors.hairline),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(99),
                borderSide: BorderSide(
                  color: AppColors.accent.withValues(alpha: 0.55),
                ),
              ),
            ),
          ),
        ),
        _EditionChip(
          label: 'Todas las ediciones',
          selected: filter.editionId == null,
          onTap: () => ref
              .read(prototiposFilterProvider.notifier)
              .set(filter.copyWith(editionId: null)),
        ),
        ...editions.maybeWhen(
          data: (list) => list.map(
            (e) => _EditionChip(
              label: '${e.year} ${e.active ? "• activa" : ""}'.trim(),
              selected: filter.editionId == e.id,
              onTap: () => ref
                  .read(prototiposFilterProvider.notifier)
                  .set(filter.copyWith(editionId: e.id)),
            ),
          ),
          orElse: () => const <Widget>[],
        ),
      ],
    );
  }
}

class _EditionChip extends StatelessWidget {
  const _EditionChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.smooth,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accent.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: selected
                ? AppColors.accent.withValues(alpha: 0.45)
                : AppColors.hairline,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? AppColors.textPrimary : AppColors.textSecondary,
            letterSpacing: 0.1,
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
//  Expansion por prototipo
// ──────────────────────────────────────────────────────────────────────────

class _PrototipoExpansion extends ConsumerStatefulWidget {
  const _PrototipoExpansion({required this.prototipo});
  final PrototipoSummary prototipo;

  @override
  ConsumerState<_PrototipoExpansion> createState() =>
      _PrototipoExpansionState();
}

class _PrototipoExpansionState extends ConsumerState<_PrototipoExpansion> {
  bool _open = false;

  Edition? _findEdition(List<Edition> list) {
    for (final e in list) {
      if (e.id == widget.prototipo.editionId) return e;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final editions =
        ref.watch(adminEditionsControllerProvider).asData?.value ?? const [];
    final edition = _findEdition(editions);
    final compact = MediaQuery.sizeOf(context).width < 760;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _open
              ? AppColors.accent.withValues(alpha: 0.32)
              : AppColors.hairline,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 14 : 20,
                14,
                compact ? 10 : 16,
                14,
              ),
              child: Row(
                children: [
                  _FolioPill(text: widget.prototipo.folio),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.prototipo.nombre,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          edition != null ? "Edición: ${edition.year}" : "Sin edición",
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _AssignmentsCountBadge(prototipoId: widget.prototipo.id),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    duration: AppMotion.fast,
                    turns: _open ? 0.5 : 0,
                    child: Icon(
                      Icons.expand_more_rounded,
                      color: AppColors.textTertiary,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_open) const Divider(height: 1),
          AnimatedSize(
            duration: AppMotion.medium,
            curve: AppMotion.smooth,
            child: _open
                ? _AssignmentsPanel(
                    prototipo: widget.prototipo,
                    edition: edition,
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _AssignmentsCountBadge extends ConsumerWidget {
  const _AssignmentsCountBadge({required this.prototipoId});
  final String prototipoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignments =
        ref.watch(prototipoAssignmentsControllerProvider(prototipoId));
    final count = assignments.asData?.value.length;
    final label = count == null ? '…' : count.toString();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.groups_outlined,
              size: 13, color: AppColors.textTertiary),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _AssignmentsPanel extends ConsumerWidget {
  const _AssignmentsPanel({required this.prototipo, required this.edition});
  final PrototipoSummary prototipo;
  final Edition? edition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignments =
        ref.watch(prototipoAssignmentsControllerProvider(prototipo.id));
    final compact = MediaQuery.sizeOf(context).width < 760;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 14 : 20,
        14,
        compact ? 14 : 20,
        18,
      ),
      child: assignments.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(
              child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 1.6),
          )),
        ),
        error: (e, _) {
          final msg = e is AssignmentFailure ? e.message : e.toString();
          return _PanelError(
            message: msg,
            onRetry: () => ref
                .read(prototipoAssignmentsControllerProvider(prototipo.id)
                    .notifier)
                .refresh(),
          );
        },
        data: (list) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Aún no hay jurados asignados a este prototipo.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textTertiary,
                  ),
                ),
              )
            else
              ...list.map(
                (a) => _AssignmentRow(assignment: a, compact: compact),
              ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: () => _openAssignSheet(context, ref),
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                label: const Text('Asignar jurado'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  textStyle: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAssignSheet(BuildContext context, WidgetRef ref) async {
    if (edition == null) {
      _toast(context,
          'No se pudo resolver la edición del prototipo.', isError: true);
      return;
    }
    final pair = await AssignJuradoSheet.show(
      context,
      prototipo: prototipo,
      editionId: edition!.id,
    );
    if (pair == null) return;
    try {
      await ref
          .read(prototipoAssignmentsControllerProvider(prototipo.id).notifier)
          .assignJurado(jurado: pair.jurado, template: pair.template);
      if (context.mounted) {
        _toast(context, '${pair.jurado.fullName} asignado(a).');
      }
    } on AssignmentFailure catch (e) {
      if (context.mounted) _toast(context, e.message, isError: true);
    }
  }
}

class _AssignmentRow extends ConsumerWidget {
  const _AssignmentRow({required this.assignment, required this.compact});
  final Assignment assignment;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          _MiniAvatar(name: assignment.juradoFullName),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  assignment.juradoFullName.isEmpty
                      ? assignment.juradoEmail
                      : assignment.juradoFullName,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (!compact || assignment.juradoFullName.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    assignment.juradoEmail,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          _TemplateChip(
            templateId: assignment.templateId,
            editionId: _editionForAssignment(ref, assignment.prototipoId),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Quitar asignación',
            onPressed: () => _confirmUnassign(context, ref, assignment),
            icon: const Icon(Icons.close_rounded, size: 16),
            color: AppColors.textTertiary,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _TemplateChip extends ConsumerWidget {
  const _TemplateChip({required this.templateId, required this.editionId});
  final String templateId;
  final String? editionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String tipoLabel = 'Plantilla';
    if (editionId != null) {
      final templates = ref.watch(templatesByEditionProvider(editionId!));
      final tpl = templates.asData?.value;
      if (tpl != null) {
        final match = tpl.where((t) => t.id == templateId);
        if (match.isNotEmpty) tipoLabel = _humanTipo(match.first.tipo);
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Text(
        tipoLabel,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

String? _editionForAssignment(WidgetRef ref, String prototipoId) {
  final list =
      ref.read(adminPrototiposControllerProvider).asData?.value ?? const [];
  for (final p in list) {
    if (p.id == prototipoId) return p.editionId;
  }
  return null;
}

String _humanTipo(String tipo) => switch (tipo) {
      'exhibicion' => 'Exhibición',
      'memoria_tecnica' => 'Memoria',
      _ => 'Plantilla',
    };

class _MiniAvatar extends StatelessWidget {
  const _MiniAvatar({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final initials = _initialsFrom(name.isEmpty ? '·' : name);
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.accent.withValues(alpha: 0.16),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.4),
          width: 0.8,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AppColors.accent,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

String _initialsFrom(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  final letters =
      parts.take(2).map((p) => p.isEmpty ? '' : p[0].toUpperCase()).join();
  return letters.isEmpty ? '·' : letters;
}

class _FolioPill extends StatelessWidget {
  const _FolioPill({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
//  Empty / error / toast / confirm
// ──────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
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
              child: Icon(Icons.assignment_ind_outlined,
                  color: AppColors.textTertiary, size: 24),
            ),
            const SizedBox(height: 16),
            Text('Sin prototipos para asignar',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Registra prototipos y rúbricas antes de configurar asignaciones.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
              textAlign: TextAlign.center,
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
                  Text('No se pudo cargar la lista',
                      style: Theme.of(context).textTheme.titleMedium),
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

class _PanelError extends StatelessWidget {
  const _PanelError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.32)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded,
              size: 16, color: AppColors.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12, color: AppColors.textPrimary),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text('Reintentar'),
          ),
        ],
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

Future<void> _confirmUnassign(
  BuildContext context,
  WidgetRef ref,
  Assignment a,
) async {
  final confirmed = await showDialog<bool>(
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
              Text('Quitar asignación',
                  style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Se eliminará la asignación de '
                '${a.juradoFullName.isEmpty ? a.juradoEmail : a.juradoFullName}. '
                'Si ya tiene evaluación en esta combinación, el API rechazará la acción.',
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
                      child: const Text('Quitar'),
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
  if (confirmed != true) return;
  try {
    await ref
        .read(prototipoAssignmentsControllerProvider(a.prototipoId).notifier)
        .unassign(a);
    if (context.mounted) _toast(context, 'Asignación eliminada.');
  } on AssignmentFailure catch (e) {
    if (context.mounted) _toast(context, e.message, isError: true);
  }
}
