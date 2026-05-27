import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../shared/theme/app_colors.dart';
import '../../application/admin_editions_controller.dart';
import '../../data/edition_models.dart';

/// Modal for create + edit. Year is locked in edit mode because the API
/// treats it as immutable (only one row per year).
class EditionFormDialog extends ConsumerStatefulWidget {
  const EditionFormDialog({super.key, this.initial});

  final Edition? initial;

  static Future<Edition?> show(BuildContext context, {Edition? initial}) {
    return showDialog<Edition>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (_) => EditionFormDialog(initial: initial),
    );
  }

  @override
  ConsumerState<EditionFormDialog> createState() => _EditionFormDialogState();
}

class _EditionFormDialogState extends ConsumerState<EditionFormDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _year;
  late final TextEditingController _name;
  late bool _active;
  bool _busy = false;
  String? _error;

  bool get _isEdit => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final e = widget.initial;
    _year = TextEditingController(
      text: e != null ? e.year.toString() : DateTime.now().year.toString(),
    );
    _name = TextEditingController(text: e?.name ?? '');
    _active = e?.active ?? false;
  }

  @override
  void dispose() {
    _year.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ctrl = ref.read(adminEditionsControllerProvider.notifier);
      final result = _isEdit
          ? await ctrl.patch(
              widget.initial!.id,
              name: _name.text.trim(),
              active: _active,
            )
          : await ctrl.create(
              year: int.parse(_year.text.trim()),
              name: _name.text.trim(),
              active: _active,
            );
      if (mounted) Navigator.of(context).pop(result);
    } on EditionsFailure catch (e) {
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

    return Dialog(
      backgroundColor: AppColors.surface1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(compact ? 20 : 24),
        side: BorderSide(color: AppColors.hairline),
      ),
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 16 : 40,
        vertical: 32,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(compact ? 22 : 28),
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _isEdit ? 'Editar edición' : 'Nueva edición',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      onPressed: _busy ? null : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      color: AppColors.textTertiary,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _Labeled(
                  label: 'Año',
                  child: TextFormField(
                    controller: _year,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    enabled: !_isEdit,
                    decoration: _decoration(
                      hint: '2024',
                      readOnly: _isEdit,
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Requerido';
                      final y = int.tryParse(v.trim());
                      if (y == null || y < 2000 || y > 2100) {
                        return 'Entre 2000 y 2100';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 14),
                _Labeled(
                  label: 'Nombre',
                  child: TextFormField(
                    controller: _name,
                    decoration: _decoration(
                      hint: '33° Premio NMS 2024',
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                  ),
                ),
                const SizedBox(height: 16),
                _ActiveSwitch(
                  value: _active,
                  onChanged: _busy ? null : (v) => setState(() => _active = v),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  _ErrorBanner(message: _error!),
                ],
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            _busy ? null : () => Navigator.of(context).pop(),
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
                        onPressed: _busy ? null : _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.6,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              )
                            : Text(_isEdit ? 'Guardar' : 'Crear'),
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

class _ActiveSwitch extends StatelessWidget {
  const _ActiveSwitch({required this.value, required this.onChanged});
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
                Text(
                  'Edición activa',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  value
                      ? 'Marcará a las demás como inactivas.'
                      : 'No impacta la edición vigente.',
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
