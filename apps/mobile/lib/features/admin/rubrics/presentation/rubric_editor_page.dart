import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../editions/application/admin_editions_controller.dart';
import '../../editions/data/edition_models.dart';
import '../../prototipos/application/admin_prototipos_controller.dart'
    show categoriasCatalogProvider;
import '../../prototipos/data/prototipo_models.dart' show Categoria;
import '../application/admin_rubrics_controller.dart';
import '../data/admin_rubrics_repository.dart';
import '../data/rubric_models.dart';

/// Full-screen editor to create a rubric or replace an existing one's tree.
/// Only reachable while the edition is in `preparacion`; the structure freezes
/// once the contest enters evaluación.
class RubricEditorPage extends ConsumerStatefulWidget {
  const RubricEditorPage({super.key, this.initial});

  /// `null` → create mode. Otherwise edit the given rubric's structure.
  final RubricDetail? initial;

  static Future<bool?> show(BuildContext context, {RubricDetail? initial}) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RubricEditorPage(initial: initial),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  ConsumerState<RubricEditorPage> createState() => _RubricEditorPageState();
}

class _RubricEditorPageState extends ConsumerState<RubricEditorPage> {
  late final TextEditingController _nombre;
  late final TextEditingController _descripcion;
  late RubricType _tipo;
  String? _editionId;
  final Set<String> _categorias = {};
  final List<_SectionDraft> _sections = [];

  bool _busy = false;
  String? _error;

  bool get _isEdit => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final r = widget.initial;
    _nombre = TextEditingController(text: r?.nombre ?? '');
    _descripcion = TextEditingController(text: r?.descripcion ?? '');
    _tipo = r?.tipo ?? RubricType.exhibicion;
    _editionId = r?.editionId;
    if (r != null) {
      _categorias.addAll(r.categorias);
      for (final s in r.sections) {
        _sections.add(_SectionDraft.fromModel(s));
      }
    }
  }

  @override
  void dispose() {
    _nombre.dispose();
    _descripcion.dispose();
    for (final s in _sections) {
      s.dispose();
    }
    super.dispose();
  }

  // ── Mutations ───────────────────────────────────────────────────────────

  void _addSection() => setState(() => _sections.add(_SectionDraft.empty()));

  void _removeSection(_SectionDraft s) => setState(() {
        _sections.remove(s);
        s.dispose();
      });

  void _moveSection(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _sections.length) return;
    setState(() {
      final s = _sections.removeAt(index);
      _sections.insert(target, s);
    });
  }

  // ── Weight summary ──────────────────────────────────────────────────────

  double get _weightSum {
    var sum = 0.0;
    for (final s in _sections) {
      final v = double.tryParse(s.peso.text.trim().replaceAll(',', '.'));
      if (v != null) sum += v;
    }
    return sum;
  }

  bool get _anyWeightSet =>
      _sections.any((s) => s.peso.text.trim().isNotEmpty);

  int get _maxScoreTotal {
    var total = 0;
    for (final s in _sections) {
      for (final c in s.criteria) {
        total += int.tryParse(c.maxScore.text.trim()) ?? 0;
      }
    }
    return total;
  }

  // ── Payload + save ──────────────────────────────────────────────────────

  String? _validate() {
    if (_nombre.text.trim().isEmpty) return 'El nombre es obligatorio.';
    if (!_isEdit && _editionId == null) return 'Selecciona una edición.';
    for (final s in _sections) {
      if (s.nombre.text.trim().isEmpty) {
        return 'Cada sección necesita un nombre.';
      }
      for (final c in s.criteria) {
        if (c.texto.text.trim().isEmpty) {
          return 'Cada criterio necesita un texto.';
        }
        final ms = int.tryParse(c.maxScore.text.trim());
        if (ms == null || ms < 0 || ms > 100) {
          return 'El puntaje máximo debe estar entre 0 y 100.';
        }
      }
    }
    return null;
  }

  List<Map<String, dynamic>> _sectionsPayload() {
    return [
      for (var i = 0; i < _sections.length; i++)
        () {
          final s = _sections[i];
          final peso =
              double.tryParse(s.peso.text.trim().replaceAll(',', '.'));
          return <String, dynamic>{
            'nombre': s.nombre.text.trim(),
            'orden': i + 1,
            'peso_pct': ?peso,
            'criteria': [
              for (var j = 0; j < s.criteria.length; j++)
                {
                  'texto': s.criteria[j].texto.text.trim(),
                  'orden': j + 1,
                  'max_score':
                      int.tryParse(s.criteria[j].maxScore.text.trim()) ?? 0,
                  'kind': s.criteria[j].kind,
                },
            ],
          };
        }(),
    ];
  }

  Future<void> _save() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    final ctrl = ref.read(adminRubricsControllerProvider.notifier);
    final sections = _sectionsPayload();
    final categorias = _categorias.toList();
    try {
      if (_isEdit) {
        final r = widget.initial!;
        // Metadata (nombre/descripcion) viaja por PATCH; el tipo es inmutable.
        if (_nombre.text.trim() != r.nombre ||
            (_descripcion.text.trim()) != (r.descripcion ?? '')) {
          await ref.read(adminRubricsRepositoryProvider).patch(
                r.id,
                nombre: _nombre.text.trim(),
                descripcion: _descripcion.text.trim(),
              );
        }
        await ctrl.saveStructure(r.id,
            categorias: categorias, sections: sections);
      } else {
        await ctrl.createRubric(
          editionId: _editionId!,
          nombre: _nombre.text.trim(),
          tipo: _tipo,
          descripcion: _descripcion.text.trim(),
          categorias: categorias,
          sections: sections,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on RubricFailure catch (e) {
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _error = 'Error inesperado: $e';
      });
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final editions = ref.watch(adminEditionsControllerProvider);
    final categorias = ref.watch(categoriasCatalogProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface0,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
        ),
        title: Text(_isEdit ? 'Editar rúbrica' : 'Nueva rúbrica'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 28),
            children: [
              _MetaCard(
                nombre: _nombre,
                descripcion: _descripcion,
                tipo: _tipo,
                onTipo: _isEdit ? null : (t) => setState(() => _tipo = t),
                isEdit: _isEdit,
                editionId: _editionId,
                editions: editions,
                onEdition: (id) => setState(() => _editionId = id),
              ),
              const SizedBox(height: 16),
              _CategoriasCard(
                catalog: categorias,
                selected: _categorias,
                onToggle: (id) => setState(() {
                  if (!_categorias.remove(id)) _categorias.add(id);
                }),
              ),
              const SizedBox(height: 16),
              _SectionsHeader(onAdd: _addSection),
              const SizedBox(height: 10),
              if (_sections.isEmpty)
                const _EmptySections()
              else
                for (var i = 0; i < _sections.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _SectionCard(
                      key: ObjectKey(_sections[i]),
                      index: i,
                      total: _sections.length,
                      draft: _sections[i],
                      onRemove: () => _removeSection(_sections[i]),
                      onMoveUp: () => _moveSection(i, -1),
                      onMoveDown: () => _moveSection(i, 1),
                      onChanged: () => setState(() {}),
                    ),
                  ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                _ErrorBanner(message: _error!),
              ],
            ],
          ),
        ),
      ),
      bottomNavigationBar: _BottomBar(
        weightSum: _weightSum,
        showWeight: _anyWeightSet,
        maxScoreTotal: _maxScoreTotal,
        busy: _busy,
        onCancel: () => Navigator.of(context).pop(),
        onSave: _save,
        saveLabel: _isEdit ? 'Guardar cambios' : 'Crear rúbrica',
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
//  Draft models (mutable, own their controllers)
// ────────────────────────────────────────────────────────────────────────────

class _SectionDraft {
  _SectionDraft({
    required this.nombre,
    required this.peso,
    required this.criteria,
  });

  final TextEditingController nombre;
  final TextEditingController peso;
  final List<_CriterionDraft> criteria;

  factory _SectionDraft.empty() => _SectionDraft(
        nombre: TextEditingController(),
        peso: TextEditingController(),
        criteria: [],
      );

  factory _SectionDraft.fromModel(RubricSection s) => _SectionDraft(
        nombre: TextEditingController(text: s.nombre),
        peso: TextEditingController(
          text: s.pesoPct != null ? _trimDouble(s.pesoPct!) : '',
        ),
        criteria: s.criteria.map(_CriterionDraft.fromModel).toList(),
      );

  void dispose() {
    nombre.dispose();
    peso.dispose();
    for (final c in criteria) {
      c.dispose();
    }
  }
}

class _CriterionDraft {
  _CriterionDraft({
    required this.texto,
    required this.maxScore,
    required this.kind,
  });

  final TextEditingController texto;
  final TextEditingController maxScore;
  String kind;

  factory _CriterionDraft.empty() => _CriterionDraft(
        texto: TextEditingController(),
        maxScore: TextEditingController(text: '3'),
        kind: 'scale',
      );

  factory _CriterionDraft.fromModel(RubricCriterion c) => _CriterionDraft(
        texto: TextEditingController(text: c.texto),
        maxScore: TextEditingController(text: c.maxScore.toString()),
        kind: c.kind,
      );

  void dispose() {
    texto.dispose();
    maxScore.dispose();
  }
}

String _trimDouble(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

// ────────────────────────────────────────────────────────────────────────────
//  Metadata card
// ────────────────────────────────────────────────────────────────────────────

class _MetaCard extends StatelessWidget {
  const _MetaCard({
    required this.nombre,
    required this.descripcion,
    required this.tipo,
    required this.onTipo,
    required this.isEdit,
    required this.editionId,
    required this.editions,
    required this.onEdition,
  });

  final TextEditingController nombre;
  final TextEditingController descripcion;
  final RubricType tipo;
  final ValueChanged<RubricType>? onTipo;
  final bool isEdit;
  final String? editionId;
  final AsyncValue<List<Edition>> editions;
  final ValueChanged<String?> onEdition;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Datos de la plantilla',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Labeled(
            label: 'Nombre',
            child: TextField(
              controller: nombre,
              decoration: _decoration(hint: 'Rúbrica de exhibición 2024'),
            ),
          ),
          const SizedBox(height: 14),
          _Labeled(
            label: 'Descripción (opcional)',
            child: TextField(
              controller: descripcion,
              maxLines: 2,
              decoration: _decoration(hint: 'Notas internas para el jurado…'),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Labeled(
                  label: 'Tipo',
                  child: DropdownButtonFormField<RubricType>(
                    initialValue: tipo,
                    dropdownColor: AppColors.surface1,
                    decoration: _decoration(),
                    onChanged:
                        onTipo == null ? null : (v) => v != null ? onTipo!(v) : null,
                    items: [
                      for (final t in RubricType.values)
                        DropdownMenuItem(value: t, child: Text(t.label)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _Labeled(
                  label: 'Edición',
                  child: isEdit
                      ? _ReadonlyField(
                          text: editions.maybeWhen(
                            data: (list) {
                              for (final e in list) {
                                if (e.id == editionId) {
                                  return '${e.year} · ${e.name}';
                                }
                              }
                              return '—';
                            },
                            orElse: () => '…',
                          ),
                        )
                      : editions.when(
                          data: (list) {
                            final prep = list
                                .where((e) =>
                                    e.phase == EditionPhase.preparacion)
                                .toList();
                            if (prep.isEmpty) {
                              return _ReadonlyField(
                                text: 'Ninguna edición en preparación',
                              );
                            }
                            return DropdownButtonFormField<String>(
                              initialValue: editionId,
                              isExpanded: true,
                              dropdownColor: AppColors.surface1,
                              decoration: _decoration(hint: 'Selecciona…'),
                              onChanged: onEdition,
                              items: [
                                for (final e in prep)
                                  DropdownMenuItem(
                                    value: e.id,
                                    child: Text('${e.year} · ${e.name}',
                                        overflow: TextOverflow.ellipsis),
                                  ),
                              ],
                            );
                          },
                          loading: () => _ReadonlyField(text: 'Cargando…'),
                          error: (_, _) =>
                              _ReadonlyField(text: 'Error al cargar'),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
//  Categorías card
// ────────────────────────────────────────────────────────────────────────────

class _CategoriasCard extends StatelessWidget {
  const _CategoriasCard({
    required this.catalog,
    required this.selected,
    required this.onToggle,
  });

  final AsyncValue<List<Categoria>> catalog;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Categorías',
      subtitle: 'Vacío = aplica a todas las categorías.',
      child: catalog.when(
        data: (cats) => Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in cats)
              _ChoiceChip(
                label: c.nombre,
                selected: selected.contains(c.id),
                onTap: () => onToggle(c.id),
              ),
          ],
        ),
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Text(
          'No se pudieron cargar las categorías.',
          style: TextStyle(color: AppColors.textTertiary, fontSize: 12.5),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
//  Sections
// ────────────────────────────────────────────────────────────────────────────

class _SectionsHeader extends StatelessWidget {
  const _SectionsHeader({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'Secciones y criterios',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
            color: AppColors.textPrimary,
          ),
        ),
        const Spacer(),
        TextButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded, size: 16),
          label: const Text('Agregar sección'),
        ),
      ],
    );
  }
}

class _EmptySections extends StatelessWidget {
  const _EmptySections();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Center(
        child: Text(
          'Sin secciones aún. Agrega la primera para construir la rúbrica.',
          style: TextStyle(color: AppColors.textTertiary, fontSize: 12.5),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    super.key,
    required this.index,
    required this.total,
    required this.draft,
    required this.onRemove,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onChanged,
  });

  final int index;
  final int total;
  final _SectionDraft draft;
  final VoidCallback onRemove;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: draft.nombre,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                  decoration: _decoration(hint: 'Nombre de la sección'),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 92,
                child: TextField(
                  controller: draft.peso,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  onChanged: (_) => onChanged(),
                  decoration: _decoration(hint: 'peso %'),
                ),
              ),
              _IconBtn(
                icon: Icons.arrow_upward_rounded,
                tooltip: 'Subir',
                onTap: index > 0 ? onMoveUp : null,
              ),
              _IconBtn(
                icon: Icons.arrow_downward_rounded,
                tooltip: 'Bajar',
                onTap: index < total - 1 ? onMoveDown : null,
              ),
              _IconBtn(
                icon: Icons.delete_outline_rounded,
                tooltip: 'Eliminar sección',
                color: AppColors.danger,
                onTap: onRemove,
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var j = 0; j < draft.criteria.length; j++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _CriterionRow(
                key: ObjectKey(draft.criteria[j]),
                number: j + 1,
                draft: draft.criteria[j],
                onRemove: () {
                  draft.criteria[j].dispose();
                  draft.criteria.removeAt(j);
                  onChanged();
                },
                onKind: (k) {
                  draft.criteria[j].kind = k;
                  onChanged();
                },
                onScoreChanged: onChanged,
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                draft.criteria.add(_CriterionDraft.empty());
                onChanged();
              },
              icon: const Icon(Icons.add_rounded, size: 15),
              label: const Text('Agregar criterio'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CriterionRow extends StatelessWidget {
  const _CriterionRow({
    super.key,
    required this.number,
    required this.draft,
    required this.onRemove,
    required this.onKind,
    required this.onScoreChanged,
  });

  final int number;
  final _CriterionDraft draft;
  final VoidCallback onRemove;
  final ValueChanged<String> onKind;
  final VoidCallback onScoreChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          Text(
            '$number.',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: draft.texto,
              style: const TextStyle(fontSize: 13),
              decoration: _decoration(hint: 'Texto del criterio'),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 64,
            child: TextField(
              controller: draft.maxScore,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(3),
              ],
              onChanged: (_) => onScoreChanged(),
              textAlign: TextAlign.center,
              decoration: _decoration(hint: 'máx'),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 120,
            child: DropdownButtonFormField<String>(
              initialValue: draft.kind,
              isExpanded: true,
              dropdownColor: AppColors.surface1,
              decoration: _decoration(),
              style: TextStyle(fontSize: 12.5, color: AppColors.textPrimary),
              onChanged: (k) => k != null ? onKind(k) : null,
              items: [
                for (final k in kCriterionKinds)
                  DropdownMenuItem(value: k, child: Text(labelForKind(k))),
              ],
            ),
          ),
          _IconBtn(
            icon: Icons.close_rounded,
            tooltip: 'Quitar criterio',
            color: AppColors.danger,
            onTap: onRemove,
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
//  Bottom bar with live weight summary
// ────────────────────────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.weightSum,
    required this.showWeight,
    required this.maxScoreTotal,
    required this.busy,
    required this.onCancel,
    required this.onSave,
    required this.saveLabel,
  });

  final double weightSum;
  final bool showWeight;
  final int maxScoreTotal;
  final bool busy;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  final String saveLabel;

  @override
  Widget build(BuildContext context) {
    final off = showWeight && (weightSum - 100).abs() > 0.01;
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface0,
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      child: Row(
        children: [
          if (showWeight)
            _Pill(
              icon: off
                  ? Icons.warning_amber_rounded
                  : Icons.check_circle_outline_rounded,
              text: 'Pesos: ${_trimDouble(weightSum)}% / 100%',
              color: off ? AppColors.danger : AppColors.success,
            ),
          if (showWeight) const SizedBox(width: 8),
          _Pill(
            icon: Icons.scoreboard_outlined,
            text: 'Máx total: $maxScoreTotal',
            color: AppColors.textSecondary,
          ),
          const Spacer(),
          OutlinedButton(
            onPressed: busy ? null : onCancel,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              side: BorderSide(color: AppColors.hairlineStrong),
              foregroundColor: AppColors.textSecondary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Cancelar'),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: busy ? null : onSave,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(saveLabel),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
//  Small shared atoms
// ────────────────────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  const _Card({required this.title, this.subtitle, required this.child});
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: AppColors.textPrimary,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(
              subtitle!,
              style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
            ),
          ],
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

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

class _ReadonlyField extends StatelessWidget {
  const _ReadonlyField({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      decoration: BoxDecoration(
        color: AppColors.surface0,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Text(
        text,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 13.5, color: AppColors.textSecondary),
      ),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
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
      child: Container(
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              Icon(Icons.check_rounded, size: 14, color: AppColors.accent),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color:
                    selected ? AppColors.textPrimary : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      icon: Icon(icon, size: 16),
      color: color ?? AppColors.textSecondary,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text, required this.color});
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.32)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 16, color: AppColors.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.textPrimary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

InputDecoration _decoration({String? hint}) => InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 13),
      filled: true,
      fillColor: AppColors.surface2,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: AppColors.accent.withValues(alpha: 0.55),
          width: 1.2,
        ),
      ),
    );
