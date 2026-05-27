import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../shared/theme/app_colors.dart';
import '../../../editions/application/admin_editions_controller.dart';
import '../../../editions/data/edition_models.dart';
import '../../application/admin_prototipos_controller.dart';
import '../../data/prototipo_models.dart';

/// Modal for create + edit.
///
/// Notes:
/// - In edit mode, the **edition** and **folio** are locked (the API treats
///   `(edition_id, folio)` as the natural key and PATCH cannot change either).
/// - The PATCH endpoint does not accept categorías or integrantes, so those
///   editors are hidden in edit mode and the values shown come from the
///   detail endpoint.
class PrototipoFormDialog extends ConsumerStatefulWidget {
  const PrototipoFormDialog({super.key, this.initial});

  final PrototipoSummary? initial;

  static Future<PrototipoDetail?> show(
    BuildContext context, {
    PrototipoSummary? initial,
  }) {
    return showDialog<PrototipoDetail>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (_) => PrototipoFormDialog(initial: initial),
    );
  }

  @override
  ConsumerState<PrototipoFormDialog> createState() =>
      _PrototipoFormDialogState();
}

class _PrototipoFormDialogState extends ConsumerState<PrototipoFormDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _folio;
  late final TextEditingController _nombre;
  late final TextEditingController _plantel;
  late final TextEditingController _descripcion;
  String? _editionId;
  bool _ejeTransversal = false;
  final Set<String> _selectedCategorias = {};
  final List<IntegranteInput> _integrantes = [];
  bool _busy = false;
  bool _initializedFromDetail = false;
  String? _error;

  bool get _isEdit => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final p = widget.initial;
    _folio = TextEditingController(text: p?.folio ?? '');
    _nombre = TextEditingController(text: p?.nombre ?? '');
    _plantel = TextEditingController(text: p?.plantel ?? '');
    _descripcion = TextEditingController(text: '');
    _editionId = p?.editionId;
    _ejeTransversal = p?.ejeTransversal ?? false;
  }

  @override
  void dispose() {
    _folio.dispose();
    _nombre.dispose();
    _plantel.dispose();
    _descripcion.dispose();
    super.dispose();
  }

  /// In edit mode, fetch the full detail to populate descripción + integrantes.
  void _hydrateFromDetail(PrototipoDetail detail) {
    if (_initializedFromDetail) return;
    _initializedFromDetail = true;
    _descripcion.text = detail.descripcion ?? '';
    _selectedCategorias
      ..clear()
      ..addAll(detail.categorias);
    _integrantes
      ..clear()
      ..addAll(detail.integrantes
          .map((i) => IntegranteInput(nombre: i.nombre, rol: i.rol)));
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (_editionId == null) {
      setState(() => _error = 'Selecciona una edición.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ctrl = ref.read(adminPrototiposControllerProvider.notifier);
      final result = _isEdit
          ? await ctrl.patch(
              widget.initial!.id,
              nombre: _nombre.text.trim(),
              plantel: _plantel.text.trim(),
              ejeTransversal: _ejeTransversal,
              descripcion: _descripcion.text.trim(),
            )
          : await ctrl.create(
              editionId: _editionId!,
              folio: _folio.text.trim(),
              nombre: _nombre.text.trim(),
              plantel: _plantel.text.trim().isEmpty
                  ? null
                  : _plantel.text.trim(),
              ejeTransversal: _ejeTransversal,
              descripcion: _descripcion.text.trim().isEmpty
                  ? null
                  : _descripcion.text.trim(),
              categorias: _selectedCategorias.toList(),
              integrantes: _integrantes,
            );
      if (mounted) Navigator.of(context).pop(result);
    } on PrototipoFailure catch (e) {
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

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final editions = ref.watch(adminEditionsControllerProvider);
    final categorias = ref.watch(categoriasCatalogProvider);

    // Hydrate descripción + categorías + integrantes from detail in edit mode.
    if (_isEdit && !_initializedFromDetail) {
      final detailAsync =
          ref.watch(prototipoDetailProvider(widget.initial!.id));
      detailAsync.whenData(_hydrateFromDetail);
    }

    return Dialog(
      backgroundColor: AppColors.surface1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(compact ? 20 : 24),
        side: BorderSide(color: AppColors.hairline),
      ),
      insetPadding:
          EdgeInsets.symmetric(horizontal: compact ? 16 : 40, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(compact ? 22 : 28),
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(
                  isEdit: _isEdit,
                  onClose:
                      _busy ? null : () => Navigator.of(context).pop(),
                ),
                const SizedBox(height: 18),
                _Labeled(
                  label: 'Edición',
                  child: _EditionSelector(
                    editions: editions.asData?.value ?? const [],
                    selectedId: _editionId,
                    enabled: !_isEdit,
                    onChanged: (id) => setState(() => _editionId = id),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _Labeled(
                        label: 'Folio',
                        child: TextFormField(
                          controller: _folio,
                          enabled: !_isEdit,
                          decoration:
                              _decoration(hint: 'CECYT-01-2024', readOnly: _isEdit),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Requerido'
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: _Labeled(
                        label: 'Nombre',
                        child: TextFormField(
                          controller: _nombre,
                          decoration: _decoration(hint: 'Nombre del prototipo'),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Requerido'
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _Labeled(
                  label: 'Plantel (opcional)',
                  child: TextFormField(
                    controller: _plantel,
                    decoration: _decoration(hint: 'CECyT 9'),
                  ),
                ),
                const SizedBox(height: 14),
                _Labeled(
                  label: 'Descripción (opcional)',
                  child: TextFormField(
                    controller: _descripcion,
                    maxLines: 3,
                    decoration:
                        _decoration(hint: 'Resumen breve del prototipo'),
                  ),
                ),
                const SizedBox(height: 16),
                _EjeSwitch(
                  value: _ejeTransversal,
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _ejeTransversal = v),
                ),
                if (!_isEdit) ...[
                  const SizedBox(height: 18),
                  _Labeled(
                    label: 'Categorías',
                    child: _CategoriasSelector(
                      catalog: categorias,
                      selected: _selectedCategorias,
                      onToggle: (id) => setState(() {
                        if (_selectedCategorias.contains(id)) {
                          _selectedCategorias.remove(id);
                        } else {
                          _selectedCategorias.add(id);
                        }
                      }),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _IntegrantesEditor(
                    integrantes: _integrantes,
                    onAdd: (nombre, rol) {
                      setState(() => _integrantes
                          .add(IntegranteInput(nombre: nombre, rol: rol)));
                    },
                    onRemove: (i) =>
                        setState(() => _integrantes.removeAt(i)),
                  ),
                ] else ...[
                  const SizedBox(height: 18),
                  _ReadonlyChips(
                    label: 'Categorías (lectura)',
                    selected: _selectedCategorias,
                    catalog: categorias,
                  ),
                  const SizedBox(height: 12),
                  _ReadonlyIntegrantes(integrantes: _integrantes),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  _ErrorBanner(message: _error!),
                ],
                const SizedBox(height: 22),
                _Footer(
                  busy: _busy,
                  isEdit: _isEdit,
                  onCancel:
                      _busy ? null : () => Navigator.of(context).pop(),
                  onSubmit: _busy ? null : _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration({String? hint, bool readOnly = false}) =>
      InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: AppColors.textTertiary),
        filled: true,
        fillColor: readOnly ? AppColors.surface0 : AppColors.surface2,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.hairline),
        ),
        disabledBorder: OutlineInputBorder(
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
}

// ──────────────────────────────────────────────────────────────────────────
//  Composable widgets
// ──────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.isEdit, required this.onClose});
  final bool isEdit;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            isEdit ? 'Editar prototipo' : 'Nuevo prototipo',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        IconButton(
          onPressed: onClose,
          icon: const Icon(Icons.close_rounded, size: 18),
          color: AppColors.textTertiary,
        ),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.busy,
    required this.isEdit,
    required this.onCancel,
    required this.onSubmit,
  });
  final bool busy;
  final bool isEdit;
  final VoidCallback? onCancel;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: onCancel,
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
            onPressed: onSubmit,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              padding: const EdgeInsets.symmetric(vertical: 14),
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
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(isEdit ? 'Guardar' : 'Crear'),
          ),
        ),
      ],
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

class _EditionSelector extends StatelessWidget {
  const _EditionSelector({
    required this.editions,
    required this.selectedId,
    required this.enabled,
    required this.onChanged,
  });

  final List<Edition> editions;
  final String? selectedId;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (editions.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Text(
          'Crea una edición antes de registrar prototipos.',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: enabled ? AppColors.surface2 : AppColors.surface0,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.hairline),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedId,
          isExpanded: true,
          dropdownColor: AppColors.surface1,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          icon: Icon(Icons.expand_more_rounded,
              color: AppColors.textTertiary, size: 18),
          style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
          hint: Text('Selecciona una edición',
              style: TextStyle(color: AppColors.textTertiary)),
          onChanged: enabled ? onChanged : null,
          items: [
            for (final e in editions)
              DropdownMenuItem(
                value: e.id,
                child: Row(
                  children: [
                    Text('${e.year} · ${e.name}'),
                    if (e.active) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'activa',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.success,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EjeSwitch extends StatelessWidget {
  const _EjeSwitch({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Eje transversal',
                    style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 2),
                Text(
                  value
                      ? 'Marca proyectos que cruzan varias categorías.'
                      : 'Activa si el proyecto aplica a múltiples categorías.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: AppColors.accent,
          ),
        ],
      ),
    );
  }
}

class _CategoriasSelector extends StatelessWidget {
  const _CategoriasSelector({
    required this.catalog,
    required this.selected,
    required this.onToggle,
  });

  final AsyncValue<List<Categoria>> catalog;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return catalog.when(
      data: (cats) {
        if (cats.isEmpty) {
          return Text(
            'No hay categorías registradas todavía.',
            style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
          );
        }
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: cats.map((c) {
            final isSelected = selected.contains(c.id);
            return GestureDetector(
              onTap: () => onToggle(c.id),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.accent.withValues(alpha: 0.16)
                      : AppColors.surface2,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.accent.withValues(alpha: 0.45)
                        : AppColors.hairline,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isSelected
                          ? Icons.check_rounded
                          : Icons.add_rounded,
                      size: 14,
                      color: isSelected
                          ? AppColors.accent
                          : AppColors.textTertiary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      c.nombre,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w500,
                        color: isSelected
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
      loading: () => const SizedBox(
        height: 28,
        child: Center(
          child: SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 1.4),
          ),
        ),
      ),
      error: (e, _) => Text(
        'No se pudo cargar el catálogo de categorías.',
        style: TextStyle(fontSize: 12, color: AppColors.danger),
      ),
    );
  }
}

class _ReadonlyChips extends StatelessWidget {
  const _ReadonlyChips({
    required this.label,
    required this.selected,
    required this.catalog,
  });

  final String label;
  final Set<String> selected;
  final AsyncValue<List<Categoria>> catalog;

  @override
  Widget build(BuildContext context) {
    return _Labeled(
      label: label,
      child: catalog.maybeWhen(
        data: (cats) {
          final picked = cats.where((c) => selected.contains(c.id)).toList();
          if (picked.isEmpty) {
            return Text(
              'Sin categorías asignadas.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textTertiary),
            );
          }
          return Wrap(
            spacing: 6,
            runSpacing: 6,
            children: picked
                .map((c) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: AppColors.hairline),
                      ),
                      child: Text(
                        c.nombre,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ))
                .toList(),
          );
        },
        orElse: () => const SizedBox(height: 14),
      ),
    );
  }
}

class _IntegrantesEditor extends StatefulWidget {
  const _IntegrantesEditor({
    required this.integrantes,
    required this.onAdd,
    required this.onRemove,
  });

  final List<IntegranteInput> integrantes;
  final void Function(String nombre, String? rol) onAdd;
  final ValueChanged<int> onRemove;

  @override
  State<_IntegrantesEditor> createState() => _IntegrantesEditorState();
}

class _IntegrantesEditorState extends State<_IntegrantesEditor> {
  final _nombre = TextEditingController();
  final _rol = TextEditingController();

  @override
  void dispose() {
    _nombre.dispose();
    _rol.dispose();
    super.dispose();
  }

  void _add() {
    final n = _nombre.text.trim();
    if (n.isEmpty) return;
    widget.onAdd(n, _rol.text.trim().isEmpty ? null : _rol.text.trim());
    _nombre.clear();
    _rol.clear();
  }

  @override
  Widget build(BuildContext context) {
    return _Labeled(
      label: 'Integrantes (opcional)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < widget.integrantes.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textPrimary,
                          ),
                          children: [
                            TextSpan(text: widget.integrantes[i].nombre),
                            if ((widget.integrantes[i].rol ?? '').isNotEmpty)
                              TextSpan(
                                text: '  ·  ${widget.integrantes[i].rol}',
                                style: TextStyle(
                                  color: AppColors.textTertiary,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => widget.onRemove(i),
                      icon: Icon(Icons.close_rounded,
                          size: 14, color: AppColors.textTertiary),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
            ),
          LayoutBuilder(builder: (ctx, constraints) {
            final stack = constraints.maxWidth < 420;
            final nombreField = TextField(
              controller: _nombre,
              decoration: _decoration(hint: 'Nombre'),
              onSubmitted: (_) => _add(),
            );
            final rolField = TextField(
              controller: _rol,
              decoration: _decoration(hint: 'Rol (opcional)'),
              onSubmitted: (_) => _add(),
            );
            final addBtn = IconButton.filled(
              onPressed: _add,
              icon: const Icon(Icons.add_rounded, size: 18),
              style: IconButton.styleFrom(
                backgroundColor: AppColors.accent.withValues(alpha: 0.18),
                foregroundColor: AppColors.accent,
                padding: const EdgeInsets.all(12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            );
            return stack
                ? Column(children: [
                    nombreField,
                    const SizedBox(height: 6),
                    rolField,
                    const SizedBox(height: 6),
                    Align(alignment: Alignment.centerRight, child: addBtn),
                  ])
                : Row(children: [
                    Expanded(child: nombreField),
                    const SizedBox(width: 6),
                    Expanded(child: rolField),
                    const SizedBox(width: 6),
                    addBtn,
                  ]);
          }),
        ],
      ),
    );
  }

  InputDecoration _decoration({String? hint}) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 12.5),
        filled: true,
        fillColor: AppColors.surface2,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
          borderSide: BorderSide(
            color: AppColors.accent.withValues(alpha: 0.55),
          ),
        ),
      );
}

class _ReadonlyIntegrantes extends StatelessWidget {
  const _ReadonlyIntegrantes({required this.integrantes});
  final List<IntegranteInput> integrantes;

  @override
  Widget build(BuildContext context) {
    return _Labeled(
      label: 'Integrantes (lectura)',
      child: integrantes.isEmpty
          ? Text(
              'Sin integrantes registrados.',
              style:
                  TextStyle(fontSize: 12.5, color: AppColors.textTertiary),
            )
          : Column(
              children: [
                for (final i in integrantes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.hairline),
                      ),
                      child: Text(
                        (i.rol ?? '').isEmpty
                            ? i.nombre
                            : '${i.nombre}  ·  ${i.rol}',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textPrimary,
                        ),
                      ),
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
        border: Border.all(
          color: AppColors.danger.withValues(alpha: 0.32),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded,
              size: 16, color: AppColors.danger),
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
