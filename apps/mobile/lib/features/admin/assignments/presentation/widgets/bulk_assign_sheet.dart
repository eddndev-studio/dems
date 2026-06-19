import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../shared/theme/app_colors.dart';
import '../../../editions/application/admin_editions_controller.dart';
import '../../../prototipos/application/admin_prototipos_controller.dart';
import '../../application/admin_assignments_controller.dart';
import '../../data/assignment_models.dart';

/// Selección devuelta por [BulkAssignSheet]: una categoría + una rúbrica + el
/// conjunto de jurados a asignar a todos los prototipos de esa categoría.
class BulkAssignSelection {
  const BulkAssignSelection({
    required this.editionId,
    required this.categoriaId,
    required this.templateId,
    required this.juradoIds,
  });

  /// Edición elegida. Sólo se usa en la UI para acotar la lista de rúbricas;
  /// la API NO la recibe (deriva la edición del `template_id`).
  final String editionId;
  final String categoriaId;
  final String templateId;
  final List<String> juradoIds;
}

/// Hoja para asignar VARIOS jurados a TODOS los prototipos de una categoría.
/// Resuelve la queja de "demasiados jurados por prototipo": en vez de asignar
/// uno por uno, se cubre el área (categoría) completa de golpe.
class BulkAssignSheet extends ConsumerStatefulWidget {
  const BulkAssignSheet({super.key, this.initialEditionId});

  /// Edición preseleccionada (la del filtro de la página, si hay).
  final String? initialEditionId;

  static Future<BulkAssignSelection?> show(
    BuildContext context, {
    String? initialEditionId,
  }) {
    return showDialog<BulkAssignSelection>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (_) => BulkAssignSheet(initialEditionId: initialEditionId),
    );
  }

  @override
  ConsumerState<BulkAssignSheet> createState() => _BulkAssignSheetState();
}

class _BulkAssignSheetState extends ConsumerState<BulkAssignSheet> {
  String? _editionId;
  String? _categoriaId;
  String? _templateId;
  final Set<String> _juradoIds = {};
  String _juradoQuery = '';

  @override
  void initState() {
    super.initState();
    _editionId = widget.initialEditionId;
  }

  bool get _canSubmit =>
      _editionId != null &&
      _categoriaId != null &&
      _templateId != null &&
      _juradoIds.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final editions = ref.watch(adminEditionsControllerProvider);
    final categorias = ref.watch(categoriasCatalogProvider);
    final jurados = ref.watch(activeJuradosProvider);

    // Resolver edición por defecto: la activa si no hay ninguna elegida.
    editions.whenData((list) {
      if (_editionId == null && list.isNotEmpty) {
        final active = list.where((e) => e.active);
        _editionId = (active.isNotEmpty ? active.first : list.first).id;
      }
    });

    final templates = _editionId == null
        ? const AsyncValue<List<TemplateOption>>.data([])
        : ref.watch(templatesByEditionProvider(_editionId!));

    return Dialog(
      backgroundColor: AppColors.surface1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(compact ? 20 : 24),
        side: BorderSide(color: AppColors.hairline),
      ),
      insetPadding:
          EdgeInsets.symmetric(horizontal: compact ? 16 : 40, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 720),
        child: Padding(
          padding: EdgeInsets.all(compact ? 20 : 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Asignar por categoría',
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 4),
                        Text(
                          'Los jurados elegidos evaluarán TODOS los prototipos '
                          'de la categoría.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppColors.textSecondary),
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
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Labeled(
                        label: 'Edición',
                        child: editions.when(
                          loading: () => const _Loading(),
                          error: (e, _) => _Err('No se pudieron cargar las ediciones.'),
                          data: (list) {
                            if (list.isEmpty) {
                              return _Err('No hay ediciones registradas.');
                            }
                            return _ChipRow(
                              options: [
                                for (final e in list)
                                  (e.id, '${e.year}${e.active ? " • activa" : ""}')
                              ],
                              selectedId: _editionId,
                              onSelect: (id) => setState(() {
                                _editionId = id;
                                _templateId = null; // rúbricas dependen de la edición
                              }),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 14),
                      _Labeled(
                        label: 'Categoría',
                        child: categorias.when(
                          loading: () => const _Loading(),
                          error: (e, _) => _Err('No se pudieron cargar las categorías.'),
                          data: (list) {
                            final sorted = [...list]
                              ..sort((a, b) => a.orden.compareTo(b.orden));
                            if (sorted.isEmpty) {
                              return _Err('No hay categorías registradas.');
                            }
                            return _ChipRow(
                              options: [for (final c in sorted) (c.id, c.nombre)],
                              selectedId: _categoriaId,
                              onSelect: (id) => setState(() => _categoriaId = id),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 14),
                      _Labeled(
                        label: 'Rúbrica',
                        child: templates.when(
                          loading: () => const _Loading(),
                          error: (e, _) => _Err('No se pudieron cargar las rúbricas.'),
                          data: (list) {
                            if (list.isEmpty) {
                              return _Err(
                                  'Esta edición no tiene rúbricas activas.');
                            }
                            return _ChipRow(
                              options: [
                                for (final t in list) (t.id, _tipoLabel(t.tipo))
                              ],
                              selectedId: _templateId,
                              onSelect: (id) => setState(() => _templateId = id),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 14),
                      _JuradosMultiPicker(
                        async: jurados,
                        selected: _juradoIds,
                        query: _juradoQuery,
                        onQuery: (v) => setState(() => _juradoQuery = v),
                        onToggle: (id) => setState(() {
                          _juradoIds.contains(id)
                              ? _juradoIds.remove(id)
                              : _juradoIds.add(id);
                        }),
                        onSelectAll: (ids) => setState(() {
                          final allSelected = ids.every(_juradoIds.contains);
                          if (allSelected) {
                            _juradoIds.removeAll(ids);
                          } else {
                            _juradoIds.addAll(ids);
                          }
                        }),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
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
                      onPressed: _canSubmit
                          ? () => Navigator.of(context).pop(
                                BulkAssignSelection(
                                  editionId: _editionId!,
                                  categoriaId: _categoriaId!,
                                  templateId: _templateId!,
                                  juradoIds: _juradoIds.toList(),
                                ),
                              )
                          : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(_juradoIds.isEmpty
                          ? 'Asignar'
                          : 'Asignar (${_juradoIds.length})'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _tipoLabel(String tipo) => switch (tipo) {
        'exhibicion' => 'Exhibición',
        'memoria_tecnica' || 'memoria' => 'Memoria técnica',
        _ => tipo,
      };
}

// ──────────────────────────────────────────────────────────────────────────
//  Subwidgets
// ──────────────────────────────────────────────────────────────────────────

class _Labeled extends StatelessWidget {
  const _Labeled({required this.label, required this.child});
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

/// Fila de chips de selección única. `options` es (id, label).
class _ChipRow extends StatelessWidget {
  const _ChipRow({
    required this.options,
    required this.selectedId,
    required this.onSelect,
  });

  final List<(String, String)> options;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((o) {
        final selected = o.$1 == selectedId;
        return GestureDetector(
          onTap: () => onSelect(o.$1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.accent.withValues(alpha: 0.16)
                  : AppColors.surface2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? AppColors.accent.withValues(alpha: 0.45)
                    : AppColors.hairline,
              ),
            ),
            child: Text(
              o.$2,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _JuradosMultiPicker extends StatelessWidget {
  const _JuradosMultiPicker({
    required this.async,
    required this.selected,
    required this.query,
    required this.onQuery,
    required this.onToggle,
    required this.onSelectAll,
  });

  final AsyncValue<List<JuradoOption>> async;
  final Set<String> selected;
  final String query;
  final ValueChanged<String> onQuery;
  final ValueChanged<String> onToggle;
  final ValueChanged<List<String>> onSelectAll;

  @override
  Widget build(BuildContext context) {
    return async.when(
      loading: () => const _Loading(),
      error: (e, _) => _Err('No se pudieron cargar los jurados.'),
      data: (all) {
        if (all.isEmpty) {
          return _Err('No hay jurados activos. Crea uno en "Usuarios".');
        }
        final filtered = query.isEmpty
            ? all
            : all
                .where((j) =>
                    j.fullName.toLowerCase().contains(query.toLowerCase()) ||
                    j.email.toLowerCase().contains(query.toLowerCase()))
                .toList();
        final filteredIds = [for (final j in filtered) j.id];
        final allFilteredSelected =
            filteredIds.isNotEmpty && filteredIds.every(selected.contains);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Jurados  (${selected.length} seleccionados)',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: filteredIds.isEmpty
                      ? null
                      : () => onSelectAll(filteredIds),
                  child: Text(allFilteredSelected
                      ? 'Quitar todos'
                      : 'Seleccionar todos'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            TextField(
              onChanged: onQuery,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                prefixIcon: Icon(Icons.search_rounded,
                    size: 16, color: AppColors.textTertiary),
                hintText: 'Buscar por nombre o correo…',
                hintStyle:
                    TextStyle(color: AppColors.textTertiary, fontSize: 12.5),
                filled: true,
                fillColor: AppColors.surface2,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.hairline),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.hairline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      BorderSide(color: AppColors.accent.withValues(alpha: 0.55)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: filtered.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text('Sin coincidencias',
                            style: TextStyle(
                                color: AppColors.textTertiary, fontSize: 13)),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (_, i) {
                        final j = filtered[i];
                        final isSel = selected.contains(j.id);
                        return InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => onToggle(j.id),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
                            decoration: BoxDecoration(
                              color: isSel
                                  ? AppColors.accent.withValues(alpha: 0.14)
                                  : AppColors.surface2,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSel
                                    ? AppColors.accent.withValues(alpha: 0.45)
                                    : AppColors.hairline,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isSel
                                      ? Icons.check_box_rounded
                                      : Icons.check_box_outline_blank_rounded,
                                  size: 18,
                                  color: isSel
                                      ? AppColors.accent
                                      : AppColors.textTertiary,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        j.fullName.isEmpty ? j.email : j.fullName,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: isSel
                                              ? FontWeight.w600
                                              : FontWeight.w500,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        j.email,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: AppColors.textTertiary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 1.6),
          ),
        ),
      );
}

class _Err extends StatelessWidget {
  const _Err(this.message);
  final String message;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Text(
        message,
        style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
      ),
    );
  }
}
