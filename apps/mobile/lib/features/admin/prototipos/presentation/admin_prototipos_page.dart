import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/theme/app_motion.dart';
import '../../../../shared/widgets/eyebrow_tag.dart';
import '../../../../shared/widgets/stagger_reveal.dart';
import '../../editions/application/admin_editions_controller.dart';
import '../../editions/data/edition_models.dart';
import '../application/admin_prototipos_controller.dart';
import '../data/prototipo_models.dart';
import 'widgets/prototipo_form_dialog.dart';

class AdminPrototiposPage extends ConsumerWidget {
  const AdminPrototiposPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filtered = ref.watch(filteredPrototiposProvider);
    final raw = ref.watch(adminPrototiposControllerProvider);

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
                    visible: filtered.asData?.value.length,
                    onNew: () => PrototipoFormDialog.show(context),
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
                        ? _PrototiposTable(items: items)
                        : _PrototiposList(items: items);
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
                          e is PrototipoFailure ? e.message : e.toString(),
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
            ? '$total ${total == 1 ? "prototipo registrado" : "prototipos registrados"}'
            : '$visible de $total visibles tras los filtros';

    return LayoutBuilder(
      builder: (context, constraints) {
        final stack = constraints.maxWidth < 520;
        final headerColumn = Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const StaggerReveal(
                child: EyebrowTag(label: 'Administración · Prototipos'),
              ),
              const SizedBox(height: 16),
              StaggerReveal(
                delay: const Duration(milliseconds: 80),
                child: Text(
                  'Catálogo de prototipos',
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
            label: const Text('Nuevo prototipo'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
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
                  headerColumn,
                  const SizedBox(height: 16),
                  Align(alignment: Alignment.centerLeft, child: cta),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [headerColumn, const SizedBox(width: 18), cta],
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
            onChanged: (v) {
              ref
                  .read(prototiposFilterProvider.notifier)
                  .set(filter.copyWith(query: v));
            },
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
//  Dense table (≥ 760)
// ──────────────────────────────────────────────────────────────────────────

class _PrototiposTable extends ConsumerWidget {
  const _PrototiposTable({required this.items});
  final List<PrototipoSummary> items;

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
              _PrototipoRow(
                prototipo: items[i],
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
          Expanded(flex: 16, child: Text('FOLIO', style: style)),
          Expanded(flex: 36, child: Text('NOMBRE', style: style)),
          Expanded(flex: 30, child: Text('EJE TRANSVERSAL', style: style)),
          SizedBox(
            width: 120,
            child: Text('ACCIONES', style: style, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

class _PrototipoRow extends ConsumerStatefulWidget {
  const _PrototipoRow({
    required this.prototipo,
    required this.edition,
    required this.divider,
  });

  final PrototipoSummary prototipo;
  final Edition? edition;
  final bool divider;

  @override
  ConsumerState<_PrototipoRow> createState() => _PrototipoRowState();
}

class _PrototipoRowState extends ConsumerState<_PrototipoRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.prototipo;
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
              flex: 16,
              child: Text(
                p.folio,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            Expanded(
              flex: 36,
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      p.nombre,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 30,
              child: Text(
                p.ejeTransversal ? 'Sí' : 'No',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            SizedBox(
              width: 120,
              child: _RowActions(prototipo: p),
            ),
          ],
        ),
      ),
    );
  }
}

class _RowActions extends ConsumerWidget {
  const _RowActions({required this.prototipo});
  final PrototipoSummary prototipo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Tooltip(
          message: 'Editar',
          child: IconButton(
            onPressed: () =>
                PrototipoFormDialog.show(context, initial: prototipo),
            icon: const Icon(Icons.edit_outlined, size: 16),
            color: AppColors.textSecondary,
            visualDensity: VisualDensity.compact,
          ),
        ),
        Tooltip(
          message: 'Eliminar',
          child: IconButton(
            onPressed: () => _handleDelete(context, ref, prototipo),
            icon: const Icon(Icons.delete_outline_rounded, size: 16),
            color: AppColors.textSecondary,
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );
  }
}

class _EjeBadge extends StatelessWidget {
  const _EjeBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.32)),
      ),
      child: Text(
        'Eje transversal',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: AppColors.accent,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
//  Mobile list (< 760)
// ──────────────────────────────────────────────────────────────────────────

class _PrototiposList extends ConsumerWidget {
  const _PrototiposList({required this.items});
  final List<PrototipoSummary> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editions =
        ref.watch(adminEditionsControllerProvider).asData?.value ?? const [];
    return SliverList.builder(
      itemCount: items.length,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _PrototipoCard(
          prototipo: items[i],
          edition: _findEdition(editions, items[i].editionId),
        ),
      ),
    );
  }
}

class _PrototipoCard extends ConsumerWidget {
  const _PrototipoCard({required this.prototipo, required this.edition});
  final PrototipoSummary prototipo;
  final Edition? edition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.hairline),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        title: Row(
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.hairline),
              ),
              child: Text(
                prototipo.folio,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                prototipo.nombre,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Folio ${prototipo.folio}'
                '${edition != null ? "  ·  ${edition!.year}" : ""}',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              if (prototipo.ejeTransversal) ...[
                const SizedBox(height: 8),
                const _EjeBadge(),
              ],
            ],
          ),
        ),
        trailing: _MoreMenuMobile(prototipo: prototipo),
        onTap: () => PrototipoFormDialog.show(context, initial: prototipo),
      ),
    );
  }
}

class _MoreMenuMobile extends ConsumerWidget {
  const _MoreMenuMobile({required this.prototipo});
  final PrototipoSummary prototipo;

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
          PrototipoFormDialog.show(context, initial: prototipo);
        } else if (v == 'delete') {
          _handleDelete(context, ref, prototipo);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem<String>(value: 'edit', child: Text('Editar')),
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

Future<void> _handleDelete(
  BuildContext context,
  WidgetRef ref,
  PrototipoSummary p,
) async {
  final confirmed = await _confirmDelete(context, p);
  if (confirmed != true) return;
  try {
    await ref.read(adminPrototiposControllerProvider.notifier).delete(p.id);
    if (context.mounted) _toast(context, 'Prototipo eliminado.');
  } on PrototipoFailure catch (e) {
    if (context.mounted) _toast(context, e.message, isError: true);
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
              child: Icon(Icons.inventory_2_outlined,
                  color: AppColors.textTertiary, size: 24),
            ),
            const SizedBox(height: 16),
            Text('Sin prototipos',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Ajusta los filtros o registra el primer prototipo.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
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

Future<bool?> _confirmDelete(BuildContext context, PrototipoSummary p) {
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
              Text('Eliminar prototipo',
                  style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Se eliminará permanentemente el prototipo "${p.folio} · ${p.nombre}". '
                'Si ya tiene evaluaciones registradas, el API rechazará la acción.',
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
