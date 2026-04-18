import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_motion.dart';
import '../../shared/widgets/bezel_card.dart';
import '../../shared/widgets/eyebrow_tag.dart';
import '../../shared/widgets/mesh_backdrop.dart';
import '../../shared/widgets/stagger_reveal.dart';
import '../asignaciones/application/asignaciones_controller.dart';
import '../asignaciones/data/asignacion_models.dart';
import '../asignaciones/presentation/asignacion_card.dart';
import '../auth/application/auth_controller.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final authValue =
        authState is AsyncData<AuthState> ? authState.value : null;
    final user = authValue is AuthAuthenticated ? authValue.user : null;

    final async = ref.watch(asignacionesControllerProvider);

    return Scaffold(
      body: Stack(
        children: [
          const MeshBackdrop(),
          SafeArea(
            child: RefreshIndicator.adaptive(
              onRefresh: () =>
                  ref.read(asignacionesControllerProvider.notifier).refresh(),
              backgroundColor: AppColors.surface1,
              color: AppColors.accent,
              edgeOffset: 24,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  final int cols = w >= 1200
                      ? 3
                      : w >= 760
                          ? 2
                          : 1;
                  final double horizontalPadding = w >= 960 ? 56 : 24;
                  return CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            horizontalPadding,
                            28,
                            horizontalPadding,
                            0,
                          ),
                          child: _TopBar(
                            fullName: user?.fullName ?? 'Jurado',
                            email: user?.email ?? '',
                            onLogout: () => ref
                                .read(authControllerProvider.notifier)
                                .logout(),
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            horizontalPadding,
                            40,
                            horizontalPadding,
                            36,
                          ),
                          child: _Hero(
                            fullName: user?.fullName ?? 'jurado',
                            total: async.asData?.value.length,
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: EdgeInsets.symmetric(
                          horizontal: horizontalPadding,
                        ),
                        sliver: async.when(
                          data: (items) => items.isEmpty
                              ? const SliverToBoxAdapter(
                                  child: _EmptyState())
                              : _AsignacionesGrid(
                                  items: items,
                                  cols: cols,
                                  onOpen: (it) =>
                                      context.go(
                                        '/evaluaciones/${it.prototipo.id}/${it.rubric.id}',
                                      ),
                                ),
                          loading: () => SliverToBoxAdapter(
                            child: _SkeletonGrid(cols: cols),
                          ),
                          error: (e, _) => SliverToBoxAdapter(
                            child: _ErrorBanner(
                              message: e is AsignacionesFailure
                                  ? e.message
                                  : e.toString(),
                              onRetry: () => ref
                                  .read(asignacionesControllerProvider
                                      .notifier)
                                  .refresh(),
                            ),
                          ),
                        ),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 60)),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
//  Top bar — brand pill on left, user chip on right
// ──────────────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.fullName,
    required this.email,
    required this.onLogout,
  });

  final String fullName;
  final String email;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return StaggerReveal(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
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
              ],
            ),
          ),
          const Spacer(),
          _UserChip(
            fullName: fullName,
            email: email,
            onLogout: onLogout,
          ),
        ],
      ),
    );
  }
}

class _UserChip extends StatefulWidget {
  const _UserChip({
    required this.fullName,
    required this.email,
    required this.onLogout,
  });

  final String fullName;
  final String email;
  final VoidCallback onLogout;

  @override
  State<_UserChip> createState() => _UserChipState();
}

class _UserChipState extends State<_UserChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final initials = _initialsFrom(widget.fullName);

    return PopupMenuButton<String>(
      tooltip: 'Cuenta',
      offset: const Offset(0, 48),
      color: AppColors.surface1,
      elevation: 10,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.hairline),
      ),
      onSelected: (v) {
        if (v == 'logout') widget.onLogout();
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          value: 'info',
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.fullName,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 2),
              Text(
                widget.email,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem<String>(
          value: 'logout',
          child: Row(
            children: [
              Icon(Icons.logout_rounded,
                  size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 12),
              Text(
                'Cerrar sesión',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ],
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: AppMotion.medium,
          curve: AppMotion.smooth,
          padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: _hover ? 0.07 : 0.04),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accent.withValues(alpha: 0.18),
                  border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.45),
                    width: 0.8,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  initials,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  widget.fullName,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.keyboard_arrow_down_rounded,
                  size: 14, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  String _initialsFrom(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    final letters =
        parts.take(2).map((p) => p.isEmpty ? '' : p[0].toUpperCase()).join();
    return letters.isEmpty ? '·' : letters;
  }
}

// ──────────────────────────────────────────────────────────────────────────
//  Hero — greeting + assignment summary
// ──────────────────────────────────────────────────────────────────────────

class _Hero extends StatelessWidget {
  const _Hero({required this.fullName, required this.total});

  final String fullName;
  final int? total;

  @override
  Widget build(BuildContext context) {
    final first = fullName.split(RegExp(r'\s+')).first;
    final text = Theme.of(context).textTheme;
    final String summary = total == null
        ? 'Cargando asignaciones…'
        : total == 0
            ? 'No tienes asignaciones activas por ahora.'
            : total == 1
                ? '1 prototipo pendiente de evaluar.'
                : '$total prototipos pendientes de evaluar.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const StaggerReveal(
          child: EyebrowTag(label: 'Panel del jurado'),
        ),
        const SizedBox(height: 18),
        StaggerReveal(
          delay: const Duration(milliseconds: 80),
          child: Text(
            'Hola, $first.',
            style: text.displaySmall?.copyWith(fontSize: 48, height: 1.05),
          ),
        ),
        const SizedBox(height: 10),
        StaggerReveal(
          delay: const Duration(milliseconds: 160),
          child: Text(
            summary,
            style: text.bodyLarge?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
//  Grid + skeletons + empty + error
// ──────────────────────────────────────────────────────────────────────────

class _AsignacionesGrid extends StatelessWidget {
  const _AsignacionesGrid({
    required this.items,
    required this.cols,
    required this.onOpen,
  });

  final List<AsignacionItem> items;
  final int cols;
  final void Function(AsignacionItem) onOpen;

  @override
  Widget build(BuildContext context) {
    return SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisSpacing: 18,
        crossAxisSpacing: 18,
        mainAxisExtent: 246,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, i) => StaggerReveal(
          delay: Duration(milliseconds: 60 * (i % 6)),
          child: AsignacionCard(
            item: items[i],
            onOpen: () => onOpen(items[i]),
          ),
        ),
        childCount: items.length,
      ),
    );
  }
}

class _SkeletonGrid extends StatelessWidget {
  const _SkeletonGrid({required this.cols});
  final int cols;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisSpacing: 18,
        crossAxisSpacing: 18,
        mainAxisExtent: 246,
      ),
      itemCount: cols * 2,
      itemBuilder: (_, _) => const _SkeletonCard(),
    );
  }
}

class _SkeletonCard extends StatefulWidget {
  const _SkeletonCard();
  @override
  State<_SkeletonCard> createState() => _SkeletonCardState();
}

class _SkeletonCardState extends State<_SkeletonCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final double a = 0.03 + (_c.value * 0.05);
        return BezelCard(
          outerRadius: 28,
          shellPadding: 5,
          corePadding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _SkeletonBar(
                      width: 90, height: 22, alpha: a, radius: 8),
                  const Spacer(),
                  _SkeletonBar(
                      width: 100, height: 22, alpha: a, radius: 99),
                ],
              ),
              const SizedBox(height: 24),
              _SkeletonBar(width: 200, height: 18, alpha: a, radius: 6),
              const SizedBox(height: 10),
              _SkeletonBar(width: 140, height: 12, alpha: a, radius: 6),
              const SizedBox(height: 22),
              Divider(color: AppColors.hairline, height: 1),
              const SizedBox(height: 18),
              Row(
                children: [
                  _SkeletonBar(width: 90, height: 14, alpha: a, radius: 8),
                  const Spacer(),
                  _SkeletonBar(width: 90, height: 30, alpha: a, radius: 99),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({
    required this.width,
    required this.height,
    required this.alpha,
    required this.radius,
  });

  final double width;
  final double height;
  final double alpha;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: alpha),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return StaggerReveal(
      delay: const Duration(milliseconds: 120),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.hairline),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.inbox_outlined,
                    color: AppColors.textTertiary,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  'Sin asignaciones activas',
                  style: text.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Cuando el comité te asigne prototipos, aparecerán aquí. '
                  'Si esperabas ver asignaciones, pide a tu coordinador que '
                  'las registre en el panel de administración.',
                  style: text.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
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
      child: BezelCard(
        corePadding: const EdgeInsets.all(24),
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
                  Text(
                    'No se pudieron cargar tus asignaciones',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
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
