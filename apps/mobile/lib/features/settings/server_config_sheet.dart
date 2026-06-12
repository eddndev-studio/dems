import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/server_config.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/eyebrow_tag.dart';
import '../../shared/widgets/primary_cta.dart';
import '../auth/application/auth_controller.dart';

/// Abre el formulario de servidor (esquema + IP/dominio + puerto). Se usa
/// tanto desde el login (antes de tener sesión) como desde el menú de
/// cuenta y el panel admin.
Future<void> showServerConfigSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const ServerConfigSheet(),
  );
}

class ServerConfigSheet extends ConsumerStatefulWidget {
  const ServerConfigSheet({super.key});

  @override
  ConsumerState<ServerConfigSheet> createState() => _ServerConfigSheetState();
}

enum _TestStatus { idle, running, ok, failed }

class _ServerConfigSheetState extends ConsumerState<ServerConfigSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;
  late bool _https;

  _TestStatus _test = _TestStatus.idle;
  String? _testMessage;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final current = ServerEndpoint.tryParse(ref.read(serverConfigProvider));
    _https = current?.https ?? false;
    _hostCtrl = TextEditingController(text: current?.host ?? '');
    _portCtrl = TextEditingController(text: current?.port?.toString() ?? '');
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  ServerEndpoint? get _endpoint => ServerEndpoint.fromForm(
    https: _https,
    host: _hostCtrl.text,
    port: _portCtrl.text,
  );

  void _invalidateTest() {
    if (_test != _TestStatus.idle) {
      setState(() {
        _test = _TestStatus.idle;
        _testMessage = null;
      });
    }
  }

  Future<void> _probe() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final endpoint = _endpoint;
    if (endpoint == null) return;

    setState(() {
      _test = _TestStatus.running;
      _testMessage = null;
    });

    final dio = Dio(
      BaseOptions(
        baseUrl: endpoint.baseUrl,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
      ),
    );
    try {
      await dio.get<void>('/healthz');
      if (!mounted) return;
      setState(() {
        _test = _TestStatus.ok;
        _testMessage = 'Conexión exitosa con ${endpoint.baseUrl}';
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _test = _TestStatus.failed;
        _testMessage = switch (e.type) {
          DioExceptionType.connectionTimeout ||
          DioExceptionType.receiveTimeout =>
            'El servidor no respondió (timeout). Verifica la IP y que estés en la misma red.',
          DioExceptionType.connectionError =>
            'No se pudo conectar. Verifica la dirección, el puerto y el esquema.',
          DioExceptionType.badResponse =>
            'El servidor respondió, pero no parece ser el API de DEMS '
                '(HTTP ${e.response?.statusCode}).',
          _ => 'Error de conexión: ${e.message}',
        };
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _test = _TestStatus.failed;
        _testMessage = 'Error de conexión: $e';
      });
    } finally {
      dio.close(force: true);
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final endpoint = _endpoint;
    if (endpoint == null) return;

    final newUrl = endpoint.baseUrl;
    final currentUrl = ref.read(serverConfigProvider);
    if (newUrl == currentUrl) {
      Navigator.of(context).pop();
      return;
    }

    final auth = ref.read(authControllerProvider).asData?.value;
    final isAuthenticated = auth is AuthAuthenticated;
    if (isAuthenticated) {
      final confirmed = await _confirmLogout(newUrl);
      if (confirmed != true || !mounted) return;
    }

    setState(() => _saving = true);
    await ref.read(serverConfigProvider.notifier).setBaseUrl(newUrl);
    if (isAuthenticated) {
      // Los tokens son del servidor anterior; en el nuevo serían rechazados.
      await ref.read(authControllerProvider.notifier).logout();
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Servidor actualizado: $newUrl')));
  }

  Future<bool?> _confirmLogout(String newUrl) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppColors.hairline),
        ),
        title: const Text('¿Cambiar de servidor?'),
        content: Text(
          'Tu sesión actual pertenece a otro servidor y se cerrará. '
          'Las evaluaciones guardadas en este dispositivo no se pierden: '
          'se sincronizarán cuando vuelvas a iniciar sesión.\n\n'
          'Nuevo servidor: $newUrl',
          style: TextStyle(color: AppColors.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Cambiar y cerrar sesión'),
          ),
        ],
      ),
    );
  }

  Future<void> _resetToDefault() async {
    await ref.read(serverConfigProvider.notifier).resetToDefault();
    if (!mounted) return;
    final url = ref.read(serverConfigProvider);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Servidor restaurado: $url')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = _endpoint?.baseUrl;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            decoration: BoxDecoration(
              color: AppColors.surface1,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: AppColors.hairlineStrong),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
              child: Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const EyebrowTag(label: 'Red local'),
                    const SizedBox(height: 16),
                    Text(
                      'Servidor del API',
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Configura la dirección del servidor DEMS en tu red. '
                      'En un servidor de área local lo habitual es HTTP con '
                      'la IP del equipo que corre el API.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        _SchemePill(
                          label: 'HTTP',
                          selected: !_https,
                          onTap: () {
                            setState(() => _https = false);
                            _invalidateTest();
                          },
                        ),
                        const SizedBox(width: 10),
                        _SchemePill(
                          label: 'HTTPS',
                          selected: _https,
                          onTap: () {
                            setState(() => _https = true);
                            _invalidateTest();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _hostCtrl,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.next,
                      style: theme.textTheme.bodyLarge,
                      decoration: const InputDecoration(
                        labelText: 'IP o dominio',
                        hintText: '192.168.1.100',
                        prefixIcon: Icon(Icons.dns_outlined, size: 18),
                      ),
                      validator: (v) => ServerEndpoint.validateHost(v ?? ''),
                      onChanged: (_) {
                        setState(() {});
                        _invalidateTest();
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _portCtrl,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      style: theme.textTheme.bodyLarge,
                      decoration: InputDecoration(
                        labelText: 'Puerto (opcional)',
                        hintText: _https ? '443' : '8080',
                        prefixIcon: const Icon(Icons.numbers_rounded, size: 18),
                      ),
                      validator: (v) => ServerEndpoint.validatePort(v ?? ''),
                      onChanged: (_) {
                        setState(() {});
                        _invalidateTest();
                      },
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Icon(
                          Icons.link_rounded,
                          size: 14,
                          color: AppColors.textTertiary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            preview ?? 'Completa la dirección…',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: preview == null
                                  ? AppColors.textTertiary
                                  : AppColors.textSecondary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 180),
                      alignment: Alignment.topCenter,
                      child: _testMessage == null
                          ? const SizedBox(width: double.infinity)
                          : Padding(
                              padding: const EdgeInsets.only(top: 14),
                              child: _TestBanner(
                                ok: _test == _TestStatus.ok,
                                message: _testMessage!,
                              ),
                            ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: _test == _TestStatus.running || _saving
                              ? null
                              : _probe,
                          icon: _test == _TestStatus.running
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.wifi_tethering_rounded,
                                  size: 16,
                                ),
                          label: Text(
                            _test == _TestStatus.running
                                ? 'Probando…'
                                : 'Probar conexión',
                          ),
                        ),
                        const Spacer(),
                        PrimaryCta(
                          label: _saving ? 'Guardando…' : 'Guardar',
                          busy: _saving,
                          onPressed: _saving ? null : _save,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Center(
                      child: TextButton(
                        onPressed: _saving ? null : _resetToDefault,
                        child: const Text('Restaurar servidor por defecto'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SchemePill extends StatelessWidget {
  const _SchemePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accent.withValues(alpha: 0.14)
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
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppColors.accent : AppColors.textSecondary,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}

class _TestBanner extends StatelessWidget {
  const _TestBanner({required this.ok, required this.message});

  final bool ok;
  final String message;

  @override
  Widget build(BuildContext context) {
    final color = ok ? AppColors.success : AppColors.danger;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok
                ? Icons.check_circle_outline_rounded
                : Icons.error_outline_rounded,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textPrimary,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
