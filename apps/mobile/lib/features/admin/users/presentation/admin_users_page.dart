import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/theme/app_motion.dart';
import '../../../../shared/widgets/eyebrow_tag.dart';
import '../../../../shared/widgets/stagger_reveal.dart';
import '../application/admin_users_controller.dart';
import '../data/admin_user_models.dart';
import 'widgets/reset_password_dialog.dart';
import 'widgets/user_form_dialog.dart';

class AdminUsersPage extends ConsumerWidget {
  const AdminUsersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filtered = ref.watch(filteredAdminUsersProvider);
    final raw = ref.watch(adminUsersControllerProvider);

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
              ref.read(adminUsersControllerProvider.notifier).refresh(),
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
                    onNew: () => UserFormDialog.show(context),
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
                        ? _UsersTable(items: items)
                        : _UsersList(items: items);
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
                          e is AdminUsersFailure ? e.message : e.toString(),
                      onRetry: () => ref
                          .read(adminUsersControllerProvider.notifier)
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
            ? '$total ${total == 1 ? "usuario registrado" : "usuarios registrados"}'
            : '$visible de $total visibles tras los filtros';

    return LayoutBuilder(
      builder: (context, constraints) {
        final stack = constraints.maxWidth < 520;
        final headerRow = [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const StaggerReveal(
                  child: EyebrowTag(label: 'Administración · Usuarios'),
                ),
                const SizedBox(height: 16),
                StaggerReveal(
                  delay: const Duration(milliseconds: 80),
                  child: Text(
                    'Gestión de usuarios',
                    style: text.displaySmall
                        ?.copyWith(fontSize: 36, height: 1.05),
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
          ),
          if (!stack) const SizedBox(width: 18),
          StaggerReveal(
            delay: const Duration(milliseconds: 180),
            child: FilledButton.icon(
              onPressed: onNew,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Nuevo usuario'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ];

        return stack
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  headerRow.first,
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: headerRow.last,
                  ),
                ],
              )
            : Row(crossAxisAlignment: CrossAxisAlignment.start, children: headerRow);
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
    _searchCtrl.text = ref.read(adminUsersFilterProvider).query;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(adminUsersFilterProvider);
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
                  .read(adminUsersFilterProvider.notifier)
                  .set(filter.copyWith(query: v));
            },
            style: const TextStyle(fontSize: 13.5),
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.search_rounded,
                  size: 18, color: AppColors.textTertiary),
              hintText: 'Buscar por nombre o correo…',
              hintStyle: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 13.5,
              ),
              filled: true,
              fillColor: AppColors.surface1,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 12,
              ),
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
        _FilterChip(
          label: 'Todos',
          selected: filter.role == null,
          onTap: () => ref
              .read(adminUsersFilterProvider.notifier)
              .set(filter.copyWith(role: null)),
        ),
        _FilterChip(
          label: 'Admins',
          selected: filter.role == UserRole.admin,
          onTap: () => ref
              .read(adminUsersFilterProvider.notifier)
              .set(filter.copyWith(role: UserRole.admin)),
        ),
        _FilterChip(
          label: 'Jurados',
          selected: filter.role == UserRole.jurado,
          onTap: () => ref
              .read(adminUsersFilterProvider.notifier)
              .set(filter.copyWith(role: UserRole.jurado)),
        ),
        const SizedBox(width: 6),
        _FilterChip(
          label: 'Solo activos',
          selected: filter.activeOnly,
          onTap: () => ref
              .read(adminUsersFilterProvider.notifier)
              .set(filter.copyWith(activeOnly: !filter.activeOnly)),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
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

class _UsersTable extends StatelessWidget {
  const _UsersTable({required this.items});
  final List<AdminUser> items;

  @override
  Widget build(BuildContext context) {
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
              _UserRow(user: items[i], divider: i < items.length - 1),
          ],
        ),
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
        border: Border(
          bottom: BorderSide(color: AppColors.hairline),
        ),
      ),
      child: Row(
        children: [
          Expanded(flex: 30, child: Text('NOMBRE'.toUpperCase(), style: style)),
          Expanded(flex: 32, child: Text('CORREO', style: style)),
          Expanded(flex: 14, child: Text('ROL', style: style)),
          Expanded(flex: 14, child: Text('ESTADO', style: style)),
          SizedBox(
            width: 130,
            child: Text(
              'ACCIONES',
              style: style,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _UserRow extends ConsumerStatefulWidget {
  const _UserRow({required this.user, required this.divider});

  final AdminUser user;
  final bool divider;

  @override
  ConsumerState<_UserRow> createState() => _UserRowState();
}

class _UserRowState extends ConsumerState<_UserRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
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
              flex: 30,
              child: Row(
                children: [
                  _Avatar(name: user.fullName),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      user.fullName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 32,
              child: Text(
                user.email,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            Expanded(flex: 14, child: _RoleBadge(role: user.role)),
            Expanded(flex: 14, child: _StatusBadge(active: user.isActive)),
            SizedBox(
              width: 130,
              child: _RowActions(user: user, ref: ref),
            ),
          ],
        ),
      ),
    );
  }
}

class _RowActions extends StatelessWidget {
  const _RowActions({required this.user, required this.ref});

  final AdminUser user;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Tooltip(
          message: 'Editar',
          child: IconButton(
            onPressed: () => UserFormDialog.show(context, initial: user),
            icon: const Icon(Icons.edit_outlined, size: 16),
            color: AppColors.textSecondary,
            visualDensity: VisualDensity.compact,
          ),
        ),
        Tooltip(
          message: 'Restablecer contraseña',
          child: IconButton(
            onPressed: () =>
                ResetPasswordDialog.show(context, user: user).then((ok) {
              if (ok == true && context.mounted) {
                _toast(context, 'Contraseña actualizada.');
              }
            }),
            icon: const Icon(Icons.key_outlined, size: 16),
            color: AppColors.textSecondary,
            visualDensity: VisualDensity.compact,
          ),
        ),
        _MoreMenu(user: user, ref: ref),
      ],
    );
  }
}

class _MoreMenu extends StatelessWidget {
  const _MoreMenu({required this.user, required this.ref});

  final AdminUser user;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Más',
      color: AppColors.surface1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppColors.hairline),
      ),
      onSelected: (v) async {
        if (v == 'toggle') {
          try {
            await ref
                .read(adminUsersControllerProvider.notifier)
                .toggleActive(user);
            if (context.mounted) {
              _toast(
                context,
                user.isActive ? 'Cuenta desactivada.' : 'Cuenta activada.',
              );
            }
          } on AdminUsersFailure catch (e) {
            if (context.mounted) _toast(context, e.message, isError: true);
          }
        } else if (v == 'delete') {
          final confirmed = await _confirmDelete(context, user);
          if (confirmed != true) return;
          try {
            await ref
                .read(adminUsersControllerProvider.notifier)
                .delete(user.id);
            if (context.mounted) _toast(context, 'Usuario eliminado.');
          } on AdminUsersFailure catch (e) {
            if (context.mounted) _toast(context, e.message, isError: true);
          }
        }
      },
      icon: Icon(Icons.more_horiz_rounded,
          size: 16, color: AppColors.textSecondary),
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          value: 'toggle',
          child: Row(
            children: [
              Icon(
                user.isActive
                    ? Icons.toggle_off_outlined
                    : Icons.toggle_on_outlined,
                size: 14,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 10),
              Text(user.isActive ? 'Desactivar' : 'Activar'),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline_rounded,
                  size: 14, color: AppColors.danger),
              const SizedBox(width: 10),
              Text(
                'Eliminar',
                style: TextStyle(color: AppColors.danger),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
//  Mobile list (< 760)
// ──────────────────────────────────────────────────────────────────────────

class _UsersList extends StatelessWidget {
  const _UsersList({required this.items});
  final List<AdminUser> items;

  @override
  Widget build(BuildContext context) {
    return SliverList.builder(
      itemCount: items.length,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _UserCard(user: items[i]),
      ),
    );
  }
}

class _UserCard extends ConsumerWidget {
  const _UserCard({required this.user});
  final AdminUser user;

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
        leading: _Avatar(name: user.fullName),
        title: Text(
          user.fullName,
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user.email,
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _RoleBadge(role: user.role),
                  const SizedBox(width: 8),
                  _StatusBadge(active: user.isActive),
                ],
              ),
            ],
          ),
        ),
        trailing: _MoreMenuMobile(user: user, ref: ref),
        onTap: () => UserFormDialog.show(context, initial: user),
      ),
    );
  }
}

class _MoreMenuMobile extends StatelessWidget {
  const _MoreMenuMobile({required this.user, required this.ref});

  final AdminUser user;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Acciones',
      color: AppColors.surface1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppColors.hairline),
      ),
      icon: Icon(Icons.more_vert_rounded,
          size: 18, color: AppColors.textSecondary),
      onSelected: (v) async {
        switch (v) {
          case 'edit':
            UserFormDialog.show(context, initial: user);
            break;
          case 'reset':
            final ok = await ResetPasswordDialog.show(context, user: user);
            if (ok == true && context.mounted) {
              _toast(context, 'Contraseña actualizada.');
            }
            break;
          case 'toggle':
            try {
              await ref
                  .read(adminUsersControllerProvider.notifier)
                  .toggleActive(user);
              if (context.mounted) {
                _toast(
                  context,
                  user.isActive ? 'Cuenta desactivada.' : 'Cuenta activada.',
                );
              }
            } on AdminUsersFailure catch (e) {
              if (context.mounted) _toast(context, e.message, isError: true);
            }
            break;
          case 'delete':
            final confirmed = await _confirmDelete(context, user);
            if (confirmed != true) return;
            try {
              await ref
                  .read(adminUsersControllerProvider.notifier)
                  .delete(user.id);
              if (context.mounted) _toast(context, 'Usuario eliminado.');
            } on AdminUsersFailure catch (e) {
              if (context.mounted) _toast(context, e.message, isError: true);
            }
            break;
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem<String>(value: 'edit', child: Text('Editar')),
        const PopupMenuItem<String>(
          value: 'reset',
          child: Text('Restablecer contraseña'),
        ),
        PopupMenuItem<String>(
          value: 'toggle',
          child: Text(user.isActive ? 'Desactivar' : 'Activar'),
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem<String>(
          value: 'delete',
          child: Text(
            'Eliminar',
            style: TextStyle(color: AppColors.danger),
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
//  Shared atoms
// ──────────────────────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final initials = _initialsFrom(name);
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.accent.withValues(alpha: 0.16),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.4),
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
    );
  }
}

String _initialsFrom(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  final letters =
      parts.take(2).map((p) => p.isEmpty ? '' : p[0].toUpperCase()).join();
  return letters.isEmpty ? '·' : letters;
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});
  final UserRole role;

  @override
  Widget build(BuildContext context) {
    final isAdmin = role == UserRole.admin;
    final color = isAdmin ? AppColors.accent : AppColors.success;
    final label = isAdmin ? 'Admin' : 'Jurado';
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: color.withValues(alpha: 0.32)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.success : AppColors.textTertiary;
    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.6),
                        blurRadius: 6,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            active ? 'Activo' : 'Inactivo',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
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
              child: Icon(Icons.search_off_rounded,
                  color: AppColors.textTertiary, size: 24),
            ),
            const SizedBox(height: 16),
            Text(
              'Sin coincidencias',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Ajusta los filtros o crea un nuevo usuario.',
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
                  Text(
                    'No se pudo cargar la lista',
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

void _toast(BuildContext context, String message, {bool isError = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor:
          isError ? AppColors.danger.withValues(alpha: 0.92) : AppColors.surface2,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 3),
    ),
  );
}

Future<bool?> _confirmDelete(BuildContext context, AdminUser user) {
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
              Text(
                'Eliminar usuario',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Se eliminará permanentemente a ${user.fullName} (${user.email}). '
                'Si ya tiene evaluaciones registradas, el API rechazará la acción y '
                'deberás desactivarlo en su lugar.',
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
