import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart' as share_plus;

import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/theme/app_motion.dart';
import '../../../../shared/widgets/eyebrow_tag.dart';
import '../../../../shared/widgets/stagger_reveal.dart';
import '../../editions/application/admin_editions_controller.dart';
import '../../prototipos/application/admin_prototipos_controller.dart';
import '../../rubrics/data/rubric_models.dart';
import '../application/admin_results_controller.dart';
import '../data/admin_results_repository.dart';
import '../data/result_models.dart';
import 'widgets/jurado_breakdown_dialog.dart';

class AdminResultsPage extends ConsumerWidget {
  const AdminResultsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(resultsFilterProvider);
    final filtered = ref.watch(filteredResultsProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final padX = w >= 1100
            ? 56.0
            : w >= 760
                ? 32.0
                : 18.0;
        final dense = w >= 760;

        return CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(padX, 28, padX, 0),
                child: const _Header(),
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
              sliver: !filter.isComplete
                  ? const SliverToBoxAdapter(child: _PromptState())
                  : filtered.when(
                      data: (data) {
                        if (data == null) {
                          return const SliverToBoxAdapter(
                            child: _PromptState(),
                          );
                        }
                        if (data.prototipos.isEmpty) {
                          return SliverToBoxAdapter(
                            child: _EmptyResults(categoria: data.categoria),
                          );
                        }
                        return dense
                            ? _ResultsTable(data: data)
                            : _ResultsList(data: data);
                      },
                      loading: () => const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 60),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      ),
                      error: (e, _) => SliverToBoxAdapter(
                        child: _ErrorBanner(
                          message: e is ResultsFailure
                              ? e.message
                              : e.toString(),
                          onRetry: () =>
                              ref.invalidate(categoriaResultsProvider),
                        ),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
//  Header
// ──────────────────────────────────────────────────────────────────────────

class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final filter = ref.watch(resultsFilterProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const StaggerReveal(
                    child: EyebrowTag(label: 'Administración · Resultados'),
                  ),
                  const SizedBox(height: 16),
                  StaggerReveal(
                    delay: const Duration(milliseconds: 80),
                    child: Text(
                      'Ranking del concurso',
                      style: text.displaySmall
                          ?.copyWith(fontSize: 36, height: 1.05),
                    ),
                  ),
                  const SizedBox(height: 6),
                  StaggerReveal(
                    delay: const Duration(milliseconds: 140),
                    child: Text(
                      'Promedio = media aritmética de los puntajes de '
                      'las evaluaciones entregadas. Los borradores no cuentan.',
                      style: text.bodyMedium
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            if (filter.editionId != null)
              StaggerReveal(
                delay: const Duration(milliseconds: 200),
                child: _ExportCsvButton(
                  editionId: filter.editionId!,
                  rubricType: filter.rubricType,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
//  Filter bar (edition + rubric type + categoria)
// ──────────────────────────────────────────────────────────────────────────

class _FilterBar extends ConsumerWidget {
  const _FilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(resultsFilterProvider);
    final editions = ref.watch(adminEditionsControllerProvider);
    final categorias = ref.watch(categoriasCatalogProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FilterRowLabel(label: 'EDICIÓN'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: editions.maybeWhen(
            data: (list) => list
                .map((e) => _Chip(
                      label: '${e.year}${e.active ? " • activa" : ""}',
                      selected: filter.editionId == e.id,
                      onTap: () => ref
                          .read(resultsFilterProvider.notifier)
                          .set(filter.copyWith(editionId: e.id)),
                    ))
                .toList(),
            orElse: () => const [_LoadingChip()],
          ),
        ),
        const SizedBox(height: 18),
        _FilterRowLabel(label: 'RÚBRICA'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _Chip(
              label: 'Exhibición',
              selected: filter.rubricType == RubricType.exhibicion,
              onTap: () => ref
                  .read(resultsFilterProvider.notifier)
                  .set(filter.copyWith(rubricType: RubricType.exhibicion)),
            ),
            _Chip(
              label: 'Memoria técnica',
              selected: filter.rubricType == RubricType.memoria,
              onTap: () => ref
                  .read(resultsFilterProvider.notifier)
                  .set(filter.copyWith(rubricType: RubricType.memoria)),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _FilterRowLabel(label: 'CATEGORÍA'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: categorias.maybeWhen(
            data: (list) {
              final sorted = [...list]..sort((a, b) => a.orden.compareTo(b.orden));
              return sorted
                  .map((c) => _Chip(
                        label: c.nombre,
                        selected: filter.categoriaSlug == c.slug,
                        onTap: () => ref
                            .read(resultsFilterProvider.notifier)
                            .set(filter.copyWith(categoriaSlug: c.slug)),
                      ))
                  .toList();
            },
            orElse: () => const [_LoadingChip()],
          ),
        ),
      ],
    );
  }
}

class _FilterRowLabel extends StatelessWidget {
  const _FilterRowLabel({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.4,
        color: AppColors.textTertiary,
      ),
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

class _LoadingChip extends StatelessWidget {
  const _LoadingChip();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: AppColors.hairline),
      ),
      child: SizedBox(
        height: 14,
        width: 14,
        child: CircularProgressIndicator(
          strokeWidth: 1.6,
          color: AppColors.textTertiary,
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
//  CSV export button
// ──────────────────────────────────────────────────────────────────────────

class _ExportCsvButton extends ConsumerStatefulWidget {
  const _ExportCsvButton({
    required this.editionId,
    required this.rubricType,
  });

  final String editionId;
  final RubricType rubricType;

  @override
  ConsumerState<_ExportCsvButton> createState() => _ExportCsvButtonState();
}

class _ExportCsvButtonState extends ConsumerState<_ExportCsvButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: _busy ? null : _export,
      icon: _busy
          ? SizedBox(
              height: 14,
              width: 14,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                color: AppColors.textPrimary,
              ),
            )
          : const Icon(Icons.download_rounded, size: 16),
      label: Text(_busy ? 'Exportando…' : 'Exportar CSV'),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent.withValues(alpha: 0.20),
        foregroundColor: AppColors.textPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(99),
          side: BorderSide(color: AppColors.accent.withValues(alpha: 0.45)),
        ),
      ),
    );
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final repo = ref.read(adminResultsRepositoryProvider);
      final exp = await repo.exportCsv(
        editionId: widget.editionId,
        rubricType: widget.rubricType,
      );
      final path = await repo.saveCsvToDisk(exp);
      if (mounted) {
        _toast(context, 'CSV generado. Abriendo opciones de compartir...');
        await share_plus.Share.shareXFiles([share_plus.XFile(path)], subject: exp.filename);
      }
    } on ResultsFailure catch (e) {
      if (mounted) _toast(context, e.message, isError: true);
    } catch (e) {
      if (mounted) _toast(context, 'Error al exportar: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

// ──────────────────────────────────────────────────────────────────────────
//  Dense table (≥ 760)
// ──────────────────────────────────────────────────────────────────────────

class _ResultsTable extends ConsumerWidget {
  const _ResultsTable({required this.data});
  final CategoriaResults data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CategoriaSummaryCard(data: data),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface1,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Column(
              children: [
                const _TableHeader(),
                for (var i = 0; i < data.prototipos.length; i++)
                  _RankRow(
                    rank: i + 1,
                    prototipo: data.prototipos[i],
                    maxTotal: data.maxTotal,
                    divider: i < data.prototipos.length - 1,
                  ),
              ],
            ),
          ),
        ],
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
          SizedBox(width: 56, child: Text('LUGAR', style: style)),
          Expanded(flex: 40, child: Text('PROTOTIPO', style: style)),
          Expanded(flex: 14, child: Text('FOLIO', style: style)),
          Expanded(flex: 14, child: Text('JURADOS', style: style)),
          Expanded(
            flex: 28,
            child: Text('PROMEDIO', style: style),
          ),
        ],
      ),
    );
  }
}

class _RankRow extends ConsumerStatefulWidget {
  const _RankRow({
    required this.rank,
    required this.prototipo,
    required this.maxTotal,
    required this.divider,
  });

  final int rank;
  final PrototipoResult prototipo;
  final int maxTotal;
  final bool divider;

  @override
  ConsumerState<_RankRow> createState() => _RankRowState();
}

class _RankRowState extends ConsumerState<_RankRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.prototipo;
    return MouseRegion(
      cursor: p.evaluaciones.isEmpty
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: p.evaluaciones.isEmpty
            ? null
            : () => JuradoBreakdownDialog.show(
                  context,
                  prototipo: p,
                  maxTotal: widget.maxTotal,
                ),
        child: AnimatedContainer(
          duration: AppMotion.fast,
          padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
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
              SizedBox(width: 56, child: _RankBadge(rank: widget.rank)),
              Expanded(
                flex: 40,
                child: Text(
                  p.nombre,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Expanded(
                flex: 14,
                child: Text(
                  p.folio,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Expanded(
                flex: 14,
                child: Text(
                  '${p.nJurados}',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Expanded(
                flex: 28,
                child: _PromedioGauge(
                  promedio: p.promedio,
                  maxTotal: widget.maxTotal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
//  Mobile list (< 760)
// ──────────────────────────────────────────────────────────────────────────

class _ResultsList extends ConsumerWidget {
  const _ResultsList({required this.data});
  final CategoriaResults data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (_, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _CategoriaSummaryCard(data: data),
            );
          }
          final p = data.prototipos[i - 1];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _RankCard(
              rank: i,
              prototipo: p,
              maxTotal: data.maxTotal,
            ),
          );
        },
        childCount: data.prototipos.length + 1,
      ),
    );
  }
}

class _RankCard extends StatelessWidget {
  const _RankCard({
    required this.rank,
    required this.prototipo,
    required this.maxTotal,
  });

  final int rank;
  final PrototipoResult prototipo;
  final int maxTotal;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: prototipo.evaluaciones.isEmpty
          ? null
          : () => JuradoBreakdownDialog.show(
                context,
                prototipo: prototipo,
                maxTotal: maxTotal,
              ),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
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
                _RankBadge(rank: rank),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        prototipo.nombre,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Folio ${prototipo.folio} · ${prototipo.nJurados} ${prototipo.nJurados == 1 ? "jurado" : "jurados"}',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _PromedioGauge(
              promedio: prototipo.promedio,
              maxTotal: maxTotal,
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
//  Shared pieces (badge, gauge, summary card)
// ──────────────────────────────────────────────────────────────────────────

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});
  final int rank;

  @override
  Widget build(BuildContext context) {
    final palette = switch (rank) {
      1 => (AppColors.warning, '🥇'),
      2 => (Color(0xFFB8B8C2), '🥈'),
      3 => (Color(0xFFCD9764), '🥉'),
      _ => (AppColors.textTertiary, null),
    };
    final color = palette.$1;
    final emoji = palette.$2;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      alignment: Alignment.center,
      child: emoji != null
          ? Text(emoji, style: const TextStyle(fontSize: 18))
          : Text(
              '$rank',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
    );
  }
}

class _PromedioGauge extends StatelessWidget {
  const _PromedioGauge({required this.promedio, required this.maxTotal});
  final double? promedio;
  final int maxTotal;

  @override
  Widget build(BuildContext context) {
    if (promedio == null) {
      return Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Text(
              'Sin evaluaciones',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textTertiary,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      );
    }

    final pct = maxTotal > 0
        ? (promedio! / maxTotal).clamp(0.0, 1.0)
        : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              _fmt(promedio!),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '/ $maxTotal',
              style: TextStyle(
                fontSize: 11.5,
                color: AppColors.textTertiary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${(pct * 100).toStringAsFixed(1)} %',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppColors.accent,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: Stack(
            children: [
              Container(
                height: 5,
                color: Colors.white.withValues(alpha: 0.06),
              ),
              FractionallySizedBox(
                widthFactor: pct,
                child: Container(
                  height: 5,
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
    );
  }

  String _fmt(double v) {
    if ((v.fract()).abs() < 1e-9) return v.toInt().toString();
    return v.toStringAsFixed(2);
  }
}

extension on double {
  double fract() => this - truncateToDouble();
}

class _CategoriaSummaryCard extends StatelessWidget {
  const _CategoriaSummaryCard({required this.data});
  final CategoriaResults data;

  @override
  Widget build(BuildContext context) {
    final n = data.prototipos.length;
    final withEval =
        data.prototipos.where((p) => p.evaluaciones.isNotEmpty).length;
    final promedios = data.prototipos
        .map((p) => p.promedio)
        .whereType<double>()
        .toList();
    final media = promedios.isEmpty
        ? null
        : promedios.reduce((a, b) => a + b) / promedios.length;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.hairline),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.accent.withValues(alpha: 0.06),
            AppColors.surface1,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.32)),
                ),
                child: Icon(Icons.emoji_events_outlined,
                    color: AppColors.accent, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.categoria.nombre,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      data.rubricType.label,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 24,
            runSpacing: 10,
            children: [
              _SummaryStat(
                label: 'Prototipos',
                value: '$n',
              ),
              _SummaryStat(
                label: 'Con evaluación',
                value: '$withEval / $n',
              ),
              _SummaryStat(
                label: 'Promedio global',
                value: media == null
                    ? '—'
                    : '${media.toStringAsFixed(2)} / ${data.maxTotal}',
              ),
              _SummaryStat(
                label: 'Máx. alcanzable',
                value: '${data.maxTotal} pts',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.4,
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
//  Empty / prompt / error / toast
// ──────────────────────────────────────────────────────────────────────────

class _PromptState extends StatelessWidget {
  const _PromptState();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56),
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
              child: Icon(Icons.tune_rounded,
                  color: AppColors.textTertiary, size: 24),
            ),
            const SizedBox(height: 16),
            Text(
              'Selecciona edición y categoría',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'El ranking se calcula sobre los prototipos de la categoría '
                'que tengan evaluaciones entregadas para la rúbrica elegida.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyResults extends StatelessWidget {
  const _EmptyResults({required this.categoria});
  final CategoriaRef categoria;
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
              child: Icon(Icons.inbox_outlined,
                  color: AppColors.textTertiary, size: 24),
            ),
            const SizedBox(height: 16),
            Text('Sin prototipos en ${categoria.nombre}',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'No hay prototipos registrados en esta categoría para la '
                'edición seleccionada.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
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
                  Text('No se pudieron obtener resultados',
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
      duration: const Duration(seconds: 4),
    ),
  );
}
