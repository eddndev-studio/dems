import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_motion.dart';
import '../../shared/widgets/bezel_card.dart';
import '../../shared/widgets/eyebrow_tag.dart';
import '../../shared/widgets/mesh_backdrop.dart';
import '../../shared/widgets/primary_cta.dart';
import '../../shared/widgets/stagger_reveal.dart';
import 'application/auth_controller.dart';
import 'data/auth_models.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _pwCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await ref.read(authControllerProvider.notifier).login(
          email: _emailCtrl.text.trim(),
          password: _pwCtrl.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final busy = authState.isLoading;
    final failure =
        authState.hasError ? authState.error as AuthFailure? : null;

    return Scaffold(
      body: Stack(
        children: [
          const MeshBackdrop(),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final bool wide = constraints.maxWidth >= 980;
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1320),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: wide ? 64 : 24,
                        vertical: wide ? 48 : 32,
                      ),
                      child: wide
                          ? _WideLayout(
                              formKey: _formKey,
                              emailCtrl: _emailCtrl,
                              pwCtrl: _pwCtrl,
                              obscure: _obscure,
                              onToggleObscure: () =>
                                  setState(() => _obscure = !_obscure),
                              busy: busy,
                              failure: failure,
                              onSubmit: _submit,
                            )
                          : _StackedLayout(
                              formKey: _formKey,
                              emailCtrl: _emailCtrl,
                              pwCtrl: _pwCtrl,
                              obscure: _obscure,
                              onToggleObscure: () =>
                                  setState(() => _obscure = !_obscure),
                              busy: busy,
                              failure: failure,
                              onSubmit: _submit,
                            ),
                    ),
                  ),
                );
              },
            ),
          ),
          const _FloatingBrandPill(),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
//  Layouts
// ──────────────────────────────────────────────────────────────────────────

class _WideLayout extends StatelessWidget {
  const _WideLayout({
    required this.formKey,
    required this.emailCtrl,
    required this.pwCtrl,
    required this.obscure,
    required this.onToggleObscure,
    required this.busy,
    required this.failure,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController emailCtrl;
  final TextEditingController pwCtrl;
  final bool obscure;
  final VoidCallback onToggleObscure;
  final bool busy;
  final AuthFailure? failure;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(flex: 6, child: _EditorialSide()),
        const SizedBox(width: 64),
        Expanded(
          flex: 5,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: StaggerReveal(
              delay: const Duration(milliseconds: 280),
              child: _LoginCard(
                formKey: formKey,
                emailCtrl: emailCtrl,
                pwCtrl: pwCtrl,
                obscure: obscure,
                onToggleObscure: onToggleObscure,
                busy: busy,
                failure: failure,
                onSubmit: onSubmit,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StackedLayout extends StatelessWidget {
  const _StackedLayout({
    required this.formKey,
    required this.emailCtrl,
    required this.pwCtrl,
    required this.obscure,
    required this.onToggleObscure,
    required this.busy,
    required this.failure,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController emailCtrl;
  final TextEditingController pwCtrl;
  final bool obscure;
  final VoidCallback onToggleObscure;
  final bool busy;
  final AuthFailure? failure;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            _EditorialSide(compact: true),
            const SizedBox(height: 36),
            StaggerReveal(
              delay: const Duration(milliseconds: 240),
              child: _LoginCard(
                formKey: formKey,
                emailCtrl: emailCtrl,
                pwCtrl: pwCtrl,
                obscure: obscure,
                onToggleObscure: onToggleObscure,
                busy: busy,
                failure: failure,
                onSubmit: onSubmit,
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
//  Editorial side — massive typography + supporting copy
// ──────────────────────────────────────────────────────────────────────────

class _EditorialSide extends StatelessWidget {
  const _EditorialSide({this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final display = Theme.of(context).textTheme;
    final double titleSize = compact ? 64 : 120;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const StaggerReveal(
          child: EyebrowTag(label: 'IPN · Concurso de prototipos 2026'),
        ),
        SizedBox(height: compact ? 24 : 40),
        StaggerReveal(
          delay: const Duration(milliseconds: 80),
          child: _GradientHeading(
            text: 'DEMS.',
            fontSize: titleSize,
          ),
        ),
        SizedBox(height: compact ? 16 : 28),
        StaggerReveal(
          delay: const Duration(milliseconds: 160),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Text(
              'Plataforma de evaluación para jurados del concurso IPN-DEMS. '
              'Rúbrica asistida, sincronización offline y resultados '
              'transparentes en una sola herramienta.',
              style: display.bodyLarge?.copyWith(
                fontSize: compact ? 15 : 17,
                color: AppColors.textSecondary,
                height: 1.55,
              ),
            ),
          ),
        ),
        if (!compact) ...[
          const SizedBox(height: 56),
          StaggerReveal(
            delay: const Duration(milliseconds: 240),
            child: const _FeatureRow(),
          ),
        ],
      ],
    );
  }
}

class _GradientHeading extends StatelessWidget {
  const _GradientHeading({required this.text, required this.fontSize});
  final String text;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (rect) => LinearGradient(
        colors: [
          Colors.white.withValues(alpha: 0.96),
          Colors.white.withValues(alpha: 0.65),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(rect),
      blendMode: BlendMode.srcIn,
      child: Text(
        text,
        style: Theme.of(context).textTheme.displayLarge?.copyWith(
              fontSize: fontSize,
              fontWeight: FontWeight.w500,
              letterSpacing: -fontSize * 0.045,
              height: 0.95,
            ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow();

  @override
  Widget build(BuildContext context) {
    const items = <(IconData, String, String)>[
      (
        Icons.draw_outlined,
        'Rúbrica oficial',
        '7 categorías · escala 0-3 por rubro'
      ),
      (
        Icons.cloud_off_outlined,
        'Offline-first',
        'Evalúa sin red, sincroniza al volver'
      ),
      (
        Icons.lock_outline_rounded,
        'Cuenta verificada',
        'Acceso por invitación del comité'
      ),
    ];
    return Wrap(
      spacing: 24,
      runSpacing: 20,
      children: [
        for (final (icon, title, subtitle) in items)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.hairline),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon,
                      size: 16, color: AppColors.textPrimary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.textTertiary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
//  Login card (Double-Bezel)
// ──────────────────────────────────────────────────────────────────────────

class _LoginCard extends StatelessWidget {
  const _LoginCard({
    required this.formKey,
    required this.emailCtrl,
    required this.pwCtrl,
    required this.obscure,
    required this.onToggleObscure,
    required this.busy,
    required this.failure,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController emailCtrl;
  final TextEditingController pwCtrl;
  final bool obscure;
  final VoidCallback onToggleObscure;
  final bool busy;
  final AuthFailure? failure;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BezelCard(
      outerRadius: 32,
      shellPadding: 6,
      corePadding: const EdgeInsets.fromLTRB(32, 34, 32, 30),
      child: Form(
        key: formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const EyebrowTag(label: 'Acceso jurado'),
            const SizedBox(height: 20),
            Text(
              'Inicia sesión',
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 10),
            Text(
              'Accede con el correo institucional asignado por el comité. Si es tu primera vez, la contraseña temporal fue enviada por correo.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 28),
            AnimatedSwitcher(
              duration: AppMotion.medium,
              switchInCurve: AppMotion.smooth,
              switchOutCurve: AppMotion.smooth,
              child: failure != null
                  ? _ErrorBanner(message: failure!.message)
                  : const SizedBox.shrink(),
            ),
            TextFormField(
              controller: emailCtrl,
              autofillHints: const [AutofillHints.email, AutofillHints.username],
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              style: theme.textTheme.bodyLarge,
              decoration: const InputDecoration(
                labelText: 'Correo',
                hintText: 'correo@dems.local',
                prefixIcon: Icon(Icons.alternate_email_rounded, size: 18),
              ),
              validator: (v) {
                final value = v?.trim() ?? '';
                if (value.isEmpty) return 'Ingresa tu correo.';
                if (!value.contains('@') || !value.contains('.')) {
                  return 'Formato de correo inválido.';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: pwCtrl,
              autofillHints: const [AutofillHints.password],
              obscureText: obscure,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => onSubmit(),
              style: theme.textTheme.bodyLarge,
              decoration: InputDecoration(
                labelText: 'Contraseña',
                hintText: '••••••••',
                prefixIcon:
                    const Icon(Icons.lock_outline_rounded, size: 18),
                suffixIcon: IconButton(
                  onPressed: onToggleObscure,
                  splashRadius: 18,
                  icon: Icon(
                    obscure
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 18,
                  ),
                ),
              ),
              validator: (v) {
                if ((v ?? '').isEmpty) return 'Ingresa tu contraseña.';
                return null;
              },
            ),
            const SizedBox(height: 22),
            LayoutBuilder(
              builder: (context, constraints) {
                final forgot = TextButton(
                  onPressed: busy ? null : () {},
                  child: const Text('¿Olvidaste la contraseña?'),
                );
                final cta = PrimaryCta(
                  label: busy ? 'Entrando…' : 'Entrar',
                  busy: busy,
                  onPressed: busy ? null : onSubmit,
                );
                if (constraints.maxWidth < 360) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [cta, const SizedBox(height: 4), forgot],
                  );
                }
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [forgot, cta],
                );
              },
            ),
            const SizedBox(height: 10),
            Divider(color: AppColors.hairline, height: 32),
            Row(
              children: [
                Icon(Icons.support_agent_rounded,
                    size: 16, color: AppColors.textTertiary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '¿Problemas de acceso? Escribe a concurso@ipn.mx',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
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
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.danger.withValues(alpha: 0.4),
          width: 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded,
              size: 16, color: AppColors.danger),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textPrimary,
                    height: 1.5,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
//  Floating brand pill (top-center)
// ──────────────────────────────────────────────────────────────────────────

class _FloatingBrandPill extends StatelessWidget {
  const _FloatingBrandPill();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 28,
      left: 0,
      right: 0,
      child: Center(
        child: StaggerReveal(
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 18, 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [AppColors.accent, AppColors.accentDeep],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'DEMS · Jurado',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    letterSpacing: 0.1,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    'v0.1',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
