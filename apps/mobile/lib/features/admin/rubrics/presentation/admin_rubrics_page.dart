import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/theme/app_motion.dart';
import '../../../../shared/widgets/eyebrow_tag.dart';
import '../../../../shared/widgets/stagger_reveal.dart';
import '../../editions/application/admin_editions_controller.dart';
import '../../editions/data/edition_models.dart';
import '../application/admin_rubrics_controller.dart';
import '../data/admin_rubrics_repository.dart';
import '../data/rubric_models.dart';
import 'rubric_editor_page.dart';
import 'widgets/rubric_detail_dialog.dart';

class AdminRubricsPage extends ConsumerWidget {
  const AdminRubricsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filtered = ref.watch(filteredRubricsProvider);
    final raw = ref.watch(adminRubricsControllerProvider);

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
              ref.read(adminRubricsControllerProvider.notifier).refresh(),
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
                    visible: filtered.asData?.value.length,
                    onNew: () => _newRubric(context, ref),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(padX, 24, padX, 16),
                  child: const _FilterBar(),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(padX, 0, padX, 60),
                sliver: filtered.when(
                  data: (items) {
                    if (items.isEmpty) {
                      return const SliverToBoxAdapter(child: _EmptyState());
                    }
                    return dense
                        ? _RubricsTable(items: items)
                        : _RubricsList(items: items);
                  },
                  loading: () => const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 60),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
                  error: (e, _) => SliverToBoxAdapter(
                    child: _ErrorBanner(
                      message: e is RubricFailure ? e.message : e.toString(),
                      onRetry: () => ref
                          .read(adminRubricsControllerProvider.notifier)
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
    required this.visible,
    required this.onNew,
  });
  final int? total;
  final int? visible;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final summary = total == null
        ? 'Cargando…'
        : visible == total
            ? '$total ${total == 1 ? "rúbrica" : "rúbricas"} registradas'
            : '$visible de $total visibles tras los filtros';

    return LayoutBuilder(
      builder: (context, constraints) {
        final stack = constraints.maxWidth < 560;
        final left = Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const StaggerReveal(
                child: EyebrowTag(label: 'Administración · Rúbricas'),
              ),
              const SizedBox(height: 16),
              StaggerReveal(
                delay: const Duration(milliseconds: 80),
                child: Text(
                  'Plantillas de evaluación',
                  style:
                      text.displaySmall?.copyWith(fontSize: 36, height: 1.05),
                ),
              ),
              const SizedBox(height: 6),
              StaggerReveal(
                delay: const Duration(milliseconds: 140),
                child: Text(
                  summary,
                  style:
                      text.bodyMedium?.copyWith(color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(height: 6),
              StaggerReveal(
                delay: const Duration(milliseconds: 200),
                child: Text(
                  'Crea y edita rúbricas mientras la edición esté en '
                  'preparación. Al iniciar la evaluación quedan congeladas.',
                  style:
                      text.bodySmall?.copyWith(color: AppColors.textTertiary),
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
            label: const Text('Nueva rúbrica'),
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
                  Row(children: [left]),
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
//  Filter bar
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
    _searchCtrl.text = ref.read(rubricsFilterProvider).query;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(rubricsFilterProvider);
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
                .read(rubricsFilterProvider.notifier)
                .set(filter.copyWith(query: v)),
            style: const TextStyle(fontSize: 13.5),
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.search_rounded,
                  size: 18, color: AppColors.textTertiary),
              hintText: 'Buscar por nombre…',
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
        _Chip(
          label: 'Todas',
          selected: filter.tipo == null,
          onTap: () => ref
              .read(rubricsFilterProvider.notifier)
              .set(filter.copyWith(tipo: null)),
        ),
        _Chip(
          label: 'Exhibición',
          selected: filter.tipo == RubricType.exhibicion,
          onTap: () => ref
              .read(rubricsFilterProvider.notifier)
              .set(filter.copyWith(tipo: RubricType.exhibicion)),
        ),
        _Chip(
          label: 'Memoria',
          selected: filter.tipo == RubricType.memoria,
          onTap: () => ref
              .read(rubricsFilterProvider.notifier)
              .set(filter.copyWith(tipo: RubricType.memoria)),
        ),
        const SizedBox(width: 4),
        _Chip(
          label: 'Solo activas',
          selected: filter.activo == true,
          onTap: () => ref.read(rubricsFilterProvider.notifier).set(
                filter.copyWith(
                    activo: filter.activo == true ? null : true),
              ),
        ),
        _Chip(
          label: 'Solo archivadas',
          selected: filter.activo == false,
          onTap: () => ref.read(rubricsFilterProvider.notifier).set(
                filter.copyWith(
                    activo: filter.activo == false ? null : false),
              ),
        ),
        const SizedBox(width: 4),
        _Chip(
          label: 'Todas las ediciones',
          selected: filter.editionId == null,
          onTap: () => ref
              .read(rubricsFilterProvider.notifier)
              .set(filter.copyWith(editionId: null)),
        ),
        ...editions.maybeWhen(
          data: (list) => list.map(
            (e) => _Chip(
              label: '${e.year}${e.active ? " • activa" : ""}',
              selected: filter.editionId == e.id,
              onTap: () => ref
                  .read(rubricsFilterProvider.notifier)
                  .set(filter.copyWith(editionId: e.id)),
            ),
          ),
          orElse: () => const <Widget>[],
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
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
//  Dense table (≥ 760)
// ──────────────────────────────────────────────────────────────────────────

class _RubricsTable extends ConsumerWidget {
  const _RubricsTable({required this.items});
  final List<RubricSummary> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editions =
        ref.watch(adminEditionsControllerProvider).asData?.value ?? const [];
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
              _RubricRow(
                rubric: items[i],
                edition: _findEdition(editions, items[i].editionId),
                divider: i < items.length - 1,
              ),
          ],
        ),
      ),
    );
  }
}

Edition? _findEdition(List<Edition> editions, String id) {
  for (final e in editions) {
    if (e.id == id) return e;
  }
  return null;
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
          Expanded(flex: 38, child: Text('NOMBRE', style: style)),
          Expanded(flex: 16, child: Text('TIPO', style: style)),
          Expanded(flex: 18, child: Text('ESTRUCTURA', style: style)),
          Expanded(flex: 14, child: Text('EDICIÓN', style: style)),
          Expanded(flex: 14, child: Text('ESTADO', style: style)),
          SizedBox(
            width: 176,
            child: Text('ACCIONES', style: style, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

class _RubricRow extends ConsumerStatefulWidget {
  const _RubricRow({
    required this.rubric,
    required this.edition,
    required this.divider,
  });

  final RubricSummary rubric;
  final Edition? edition;
  final bool divider;

  @override
  ConsumerState<_RubricRow> createState() => _RubricRowState();
}

class _RubricRowState extends ConsumerState<_RubricRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.rubric;
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
            Expanded(
              flex: 38,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.nombre,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (r.descripcion != null &&
                      r.descripcion!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      r.descripcion!,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(flex: 16, child: _TipoBadge(tipo: r.tipo)),
            Expanded(
              flex: 18,
              child: Text(
                '${r.sectionCount} secc · ${r.criterionCount} crit',
                style:
                    TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
            Expanded(
              flex: 14,
              child: Text(
                widget.edition?.year.toString() ?? '—',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            Expanded(flex: 14, child: _ActivoBadge(active: r.activo)),
            SizedBox(
              width: 176,
              child: _RowActions(rubric: r),
            ),
          ],
        ),
      ),
    );
  }
}

class _RowActions extends ConsumerWidget {
  const _RowActions({required this.rubric});
  final RubricSummary rubric;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (rubric.editable)
          Tooltip(
            message: 'Editar',
            child: IconButton(
              onPressed: () => _editRubric(context, ref, rubric),
              icon: const Icon(Icons.edit_outlined, size: 16),
              color: AppColors.textSecondary,
              visualDensity: VisualDensity.compact,
            ),
          )
        else
          Tooltip(
            message: 'Congelada: la edición ya está en evaluación',
            child: IconButton(
              onPressed: null,
              icon: const Icon(Icons.lock_outline_rounded, size: 15),
              color: AppColors.textTertiary,
              visualDensity: VisualDensity.compact,
            ),
          ),
        Tooltip(
          message: 'Ver árbol',
          child: IconButton(
            onPressed: () => RubricDetailDialog.show(context, rubric: rubric),
            icon: const Icon(Icons.account_tree_outlined, size: 16),
            color: AppColors.textSecondary,
            visualDensity: VisualDensity.compact,
          ),
        ),
        Tooltip(
          message: rubric.activo ? 'Archivar' : 'Activar',
          child: IconButton(
            onPressed: () => _toggleActivo(context, ref, rubric),
            icon: Icon(
              rubric.activo
                  ? Icons.toggle_off_outlined
                  : Icons.toggle_on_outlined,
              size: 18,
            ),
            color: rubric.activo
                ? AppColors.textSecondary
                : AppColors.success,
            visualDensity: VisualDensity.compact,
          ),
        ),
        Tooltip(
          message: 'Eliminar',
          child: IconButton(
            onPressed: () => _confirmDelete(context, ref, rubric),
            icon: const Icon(Icons.delete_outline_rounded, size: 16),
            color: AppColors.textSecondary,
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
//  Mobile list (< 760)
// ──────────────────────────────────────────────────────────────────────────

class _RubricsList extends ConsumerWidget {
  const _RubricsList({required this.items});
  final List<RubricSummary> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editions =
        ref.watch(adminEditionsControllerProvider).asData?.value ?? const [];
    return SliverList.builder(
      itemCount: items.length,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _RubricCard(
          rubric: items[i],
          edition: _findEdition(editions, items[i].editionId),
        ),
      ),
    );
  }
}

class _RubricCard extends ConsumerWidget {
  const _RubricCard({required this.rubric, required this.edition});
  final RubricSummary rubric;
  final Edition? edition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: () => RubricDetailDialog.show(context, rubric: rubric),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _TipoBadge(tipo: rubric.tipo),
                const SizedBox(width: 8),
                _ActivoBadge(active: rubric.activo),
                const Spacer(),
                _MoreMenuMobile(rubric: rubric),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              rubric.nombre,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            if (rubric.descripcion != null &&
                rubric.descripcion!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                rubric.descripcion!,
                style:
                    TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _MetaPill(
                    icon: Icons.account_tree_outlined,
                    text:
                        '${rubric.sectionCount} sec · ${rubric.criterionCount} crit'),
                if (edition != null)
                  _MetaPill(
                      icon: Icons.event_outlined,
                      text: edition!.year.toString()),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MoreMenuMobile extends ConsumerWidget {
  const _MoreMenuMobile({required this.rubric});
  final RubricSummary rubric;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'Acciones',
      color: AppColors.surface1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppColors.hairline),
      ),
      icon: Icon(Icons.more_vert_rounded,
          size: 18, color: AppColors.textSecondary),
      onSelected: (v) {
        if (v == 'edit') {
          _editRubric(context, ref, rubric);
        } else if (v == 'tree') {
          RubricDetailDialog.show(context, rubric: rubric);
        } else if (v == 'toggle') {
          _toggleActivo(context, ref, rubric);
        } else if (v == 'delete') {
          _confirmDelete(context, ref, rubric);
        }
      },
      itemBuilder: (_) => [
        if (rubric.editable)
          const PopupMenuItem<String>(value: 'edit', child: Text('Editar')),
        const PopupMenuItem<String>(value: 'tree', child: Text('Ver árbol')),
        PopupMenuItem<String>(
          value: 'toggle',
          child: Text(rubric.activo ? 'Archivar' : 'Activar'),
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem<String>(
          value: 'delete',
          child:
              Text('Eliminar', style: TextStyle(color: AppColors.danger)),
        ),
      ],
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.textTertiary),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
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

class _TipoBadge extends StatelessWidget {
  const _TipoBadge({required this.tipo});
  final RubricType tipo;

  @override
  Widget build(BuildContext context) {
    final isExhibicion = tipo == RubricType.exhibicion;
    final color = isExhibicion ? AppColors.accent : AppColors.success;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: color.withValues(alpha: 0.32)),
        ),
        child: Text(
          tipo.label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

class _ActivoBadge extends StatelessWidget {
  const _ActivoBadge({required this.active});
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
            active ? 'Activa' : 'Archivada',
            style:
                TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
//  Side-effects: toggle + delete + confirm
// ──────────────────────────────────────────────────────────────────────────

Future<void> _newRubric(BuildContext context, WidgetRef ref) async {
  final saved = await RubricEditorPage.show(context);
  if (saved == true && context.mounted) _toast(context, 'Rúbrica creada.');
}

Future<void> _editRubric(
  BuildContext context,
  WidgetRef ref,
  RubricSummary r,
) async {
  // El editor necesita el árbol completo (secciones + categorías).
  try {
    final detail = await ref.read(adminRubricsRepositoryProvider).getById(r.id);
    if (!context.mounted) return;
    final saved = await RubricEditorPage.show(context, initial: detail);
    if (saved == true && context.mounted) {
      _toast(context, 'Rúbrica actualizada.');
    }
  } on RubricFailure catch (e) {
    if (context.mounted) _toast(context, e.message, isError: true);
  }
}

Future<void> _toggleActivo(
  BuildContext context,
  WidgetRef ref,
  RubricSummary r,
) async {
  try {
    await ref
        .read(adminRubricsControllerProvider.notifier)
        .toggleActivo(r);
    if (context.mounted) {
      _toast(context, r.activo ? 'Rúbrica archivada.' : 'Rúbrica activada.');
    }
  } on RubricFailure catch (e) {
    if (context.mounted) _toast(context, e.message, isError: true);
  }
}

Future<void> _confirmDelete(
  BuildContext context,
  WidgetRef ref,
  RubricSummary r,
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
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Eliminar rúbrica',
                  style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Se eliminará permanentemente "${r.nombre}". '
                'Si ya tiene evaluaciones registradas el API rechazará la acción; '
                'en ese caso, archívala desactivándola.',
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
  if (confirmed != true) return;
  try {
    await ref.read(adminRubricsControllerProvider.notifier).delete(r.id);
    if (context.mounted) _toast(context, 'Rúbrica eliminada.');
  } on RubricFailure catch (e) {
    if (context.mounted) _toast(context, e.message, isError: true);
  }
}

// ──────────────────────────────────────────────────────────────────────────
//  Empty / error / toast
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
              child: Icon(Icons.account_tree_outlined,
                  color: AppColors.textTertiary, size: 24),
            ),
            const SizedBox(height: 16),
            Text('Sin rúbricas registradas',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Las plantillas se siembran desde el backend. Ajusta los filtros para verlas.',
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
