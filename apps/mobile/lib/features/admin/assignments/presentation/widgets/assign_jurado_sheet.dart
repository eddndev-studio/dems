import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../shared/theme/app_colors.dart';
import '../../../prototipos/data/prototipo_models.dart';
import '../../application/admin_assignments_controller.dart';
import '../../data/assignment_models.dart';

class AssignSelection {
  const AssignSelection({required this.jurado, required this.template});
  final JuradoOption jurado;
  final TemplateOption template;
}

class AssignJuradoSheet extends ConsumerStatefulWidget {
  const AssignJuradoSheet({
    super.key,
    required this.prototipo,
    required this.editionId,
  });

  final PrototipoSummary prototipo;
  final String editionId;

  static Future<AssignSelection?> show(
    BuildContext context, {
    required PrototipoSummary prototipo,
    required String editionId,
  }) {
    return showDialog<AssignSelection>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (_) =>
          AssignJuradoSheet(prototipo: prototipo, editionId: editionId),
    );
  }

  @override
  ConsumerState<AssignJuradoSheet> createState() => _AssignJuradoSheetState();
}

class _AssignJuradoSheetState extends ConsumerState<AssignJuradoSheet> {
  JuradoOption? _selectedJurado;
  TemplateOption? _selectedTemplate;
  String _juradoQuery = '';

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final jurados = ref.watch(activeJuradosProvider);
    final templates = ref.watch(templatesByEditionProvider(widget.editionId));

    return Dialog(
      backgroundColor: AppColors.surface1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(compact ? 20 : 24),
        side: BorderSide(color: AppColors.hairline),
      ),
      insetPadding:
          EdgeInsets.symmetric(horizontal: compact ? 16 : 40, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: EdgeInsets.all(compact ? 22 : 28),
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
                        Text(
                          'Asignar jurado',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${widget.prototipo.folio}  ·  ${widget.prototipo.nombre}',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
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
              const SizedBox(height: 18),

              // -- Plantilla --
              _Labeled(
                label: 'Rúbrica',
                child: templates.when(
                  loading: () => const _LoadingPicker(),
                  error: (e, _) => _ErrorBanner(
                    message: e is AssignmentFailure
                        ? e.message
                        : 'No se pudo cargar las rúbricas.',
                  ),
                  data: (list) {
                    if (list.isEmpty) {
                      return _InfoBox(
                        message:
                            'Esta edición aún no tiene rúbricas activas. Crea una antes de asignar jurados.',
                      );
                    }
                    return _TemplatePicker(
                      options: list,
                      selected: _selectedTemplate,
                      onChange: (t) => setState(() => _selectedTemplate = t),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              // -- Jurado --
              _Labeled(
                label: 'Jurado',
                child: jurados.when(
                  loading: () => const _LoadingPicker(),
                  error: (e, _) => _ErrorBanner(
                    message: e is AssignmentFailure
                        ? e.message
                        : 'No se pudo cargar los jurados.',
                  ),
                  data: (all) {
                    final filtered = _juradoQuery.isEmpty
                        ? all
                        : all
                            .where((j) =>
                                j.fullName
                                    .toLowerCase()
                                    .contains(_juradoQuery.toLowerCase()) ||
                                j.email
                                    .toLowerCase()
                                    .contains(_juradoQuery.toLowerCase()))
                            .toList();
                    if (all.isEmpty) {
                      return _InfoBox(
                        message:
                            'No hay jurados activos. Crea uno en "Usuarios" y vuelve.',
                      );
                    }
                    return _JuradoPicker(
                      jurados: filtered,
                      selected: _selectedJurado,
                      onQuery: (v) => setState(() => _juradoQuery = v),
                      onChange: (j) => setState(() => _selectedJurado = j),
                    );
                  },
                ),
              ),

              const SizedBox(height: 22),
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
                      onPressed:
                          (_selectedJurado != null && _selectedTemplate != null)
                              ? () => Navigator.of(context).pop(
                                    AssignSelection(
                                      jurado: _selectedJurado!,
                                      template: _selectedTemplate!,
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
                      child: const Text('Asignar'),
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

class _TemplatePicker extends StatelessWidget {
  const _TemplatePicker({
    required this.options,
    required this.selected,
    required this.onChange,
  });

  final List<TemplateOption> options;
  final TemplateOption? selected;
  final ValueChanged<TemplateOption> onChange;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((t) {
        final isSelected = selected?.id == t.id;
        final tipoLabel = switch (t.tipo) {
          'exhibicion' => 'Exhibición',
          'memoria_tecnica' => 'Memoria técnica',
          _ => t.tipo,
        };
        return GestureDetector(
          onTap: () => onChange(t),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.accent.withValues(alpha: 0.16)
                  : AppColors.surface2,
              borderRadius: BorderRadius.circular(12),
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
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 14,
                  color: isSelected
                      ? AppColors.accent
                      : AppColors.textTertiary,
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tipoLabel,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textTertiary,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      t.nombre,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _JuradoPicker extends StatelessWidget {
  const _JuradoPicker({
    required this.jurados,
    required this.selected,
    required this.onQuery,
    required this.onChange,
  });

  final List<JuradoOption> jurados;
  final JuradoOption? selected;
  final ValueChanged<String> onQuery;
  final ValueChanged<JuradoOption> onChange;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
              borderSide: BorderSide(
                color: AppColors.accent.withValues(alpha: 0.55),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: jurados.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'Sin coincidencias',
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: jurados.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (_, i) {
                    final j = jurados[i];
                    final isSelected = selected?.id == j.id;
                    return InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => onChange(j),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.accent.withValues(alpha: 0.14)
                              : AppColors.surface2,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.accent.withValues(alpha: 0.45)
                                : AppColors.hairline,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isSelected
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              size: 14,
                              color: isSelected
                                  ? AppColors.accent
                                  : AppColors.textTertiary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    j.fullName,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    j.email,
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
  }
}

class _LoadingPicker extends StatelessWidget {
  const _LoadingPicker();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 1.6,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
          ),
        ),
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.message});
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded,
              size: 16, color: AppColors.textTertiary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
                height: 1.4,
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
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.32)),
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
              style: TextStyle(fontSize: 12.5, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
