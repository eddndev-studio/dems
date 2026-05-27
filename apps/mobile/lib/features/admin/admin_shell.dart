import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_motion.dart';
import '../../shared/widgets/mesh_backdrop.dart';
import '../auth/application/auth_controller.dart';

/// Sections rendered inside the admin shell. The shell owns the responsive
/// chrome (drawer / rail / extended rail); each section is a routed body.
enum AdminSection {
  users('/admin/users', 'Usuarios', Icons.group_outlined),
  editions('/admin/editions', 'Ediciones', Icons.event_outlined),
  prototipos('/admin/prototipos', 'Prototipos', Icons.inventory_2_outlined),
  assignments(
    '/admin/assignments',
    'Asignaciones',
    Icons.assignment_ind_outlined,
  ),
  rubrics('/admin/rubric-templates', 'Rúbricas', Icons.rule_outlined),
  results('/admin/results', 'Resultados', Icons.leaderboard_outlined);

  const AdminSection(this.path, this.label, this.icon);
  final String path;
  final String label;
  final IconData icon;

  static AdminSection fromLocation(String location) {
    for (final s in AdminSection.values) {
      if (location == s.path || location.startsWith('${s.path}/')) return s;
    }
    return AdminSection.users;
  }
}

/// Responsive chrome wrapping every admin route. Three layouts:
///  - mobile  (<760px)         : AppBar + Drawer + full-bleed body
///  - tablet  (760–1199px)     : compact NavigationRail (collapsed)
///  - desktop (≥1200px)        : extended NavigationRail with section labels
class AdminShell extends ConsumerWidget {
  const AdminShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final current = AdminSection.fromLocation(location);

    final authValue = ref.watch(authControllerProvider).asData?.value;
    final user = authValue is AuthAuthenticated ? authValue.user : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final bool isMobile = w < 760;
        final bool isExtended = w >= 1200;
        return Scaffold(
          backgroundColor: AppColors.bg,
          drawer: isMobile
              ? _AdminDrawer(
                  current: current,
                  fullName: user?.fullName ?? 'Admin',
                  email: user?.email ?? '',
                  onSelect: (s) {
                    Navigator.of(context).pop();
                    context.go(s.path);
                  },
                  onLogout: () => ref
                      .read(authControllerProvider.notifier)
                      .logout(),
                )
              : null,
          appBar: isMobile
              ? AppBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  title: _BrandPill(label: current.label),
                  iconTheme: IconThemeData(color: AppColors.textPrimary),
                )
              : null,
          body: Stack(
            children: [
              const MeshBackdrop(),
              SafeArea(
                child: Row(
                  children: [
                    if (!isMobile)
                      _AdminRail(
                        current: current,
                        extended: isExtended,
                        fullName: user?.fullName ?? 'Admin',
                        email: user?.email ?? '',
                        onSelect: (s) => context.go(s.path),
                        onLogout: () => ref
                            .read(authControllerProvider.notifier)
                            .logout(),
                      ),
                    Expanded(child: child),
                  ],
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
//  Rail (tablet / desktop)
// ──────────────────────────────────────────────────────────────────────────

class _AdminRail extends StatelessWidget {
  const _AdminRail({
    required this.current,
    required this.extended,
    required this.fullName,
    required this.email,
    required this.onSelect,
    required this.onLogout,
  });

  final AdminSection current;
  final bool extended;
  final String fullName;
  final String email;
  final void Function(AdminSection) onSelect;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final double width = extended ? 232 : 88;
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: AppColors.hairline),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BrandPill(label: extended ? 'DEMS · Admin' : null),
          const SizedBox(height: 28),
          ...AdminSection.values.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _RailItem(
                  section: s,
                  selected: s == current,
                  extended: extended,
                  onTap: () => onSelect(s),
                ),
              )),
          const Spacer(),
          _AccountTile(
            fullName: fullName,
            email: email,
            extended: extended,
            onLogout: onLogout,
          ),
        ],
      ),
    );
  }
}

class _RailItem extends StatefulWidget {
  const _RailItem({
    required this.section,
    required this.selected,
    required this.extended,
    required this.onTap,
  });

  final AdminSection section;
  final bool selected;
  final bool extended;
  final VoidCallback onTap;

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final bgAlpha = selected ? 0.10 : (_hover ? 0.05 : 0.0);
    final iconColor =
        selected ? AppColors.accent : AppColors.textSecondary;
    final textColor =
        selected ? AppColors.textPrimary : AppColors.textSecondary;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.smooth,
          padding: EdgeInsets.symmetric(
            horizontal: widget.extended ? 14 : 0,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: bgAlpha),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? AppColors.accent.withValues(alpha: 0.32)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisAlignment: widget.extended
                ? MainAxisAlignment.start
                : MainAxisAlignment.center,
            children: [
              Icon(widget.section.icon, color: iconColor, size: 20),
              if (widget.extended) ...[
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    widget.section.label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w500,
                      color: textColor,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.fullName,
    required this.email,
    required this.extended,
    required this.onLogout,
  });

  final String fullName;
  final String email;
  final bool extended;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final initials = _initialsFrom(fullName);
    return Tooltip(
      message: 'Cerrar sesión · $email',
      child: InkWell(
        onTap: onLogout,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Row(
            mainAxisAlignment: extended
                ? MainAxisAlignment.start
                : MainAxisAlignment.center,
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
              if (extended) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fullName,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        email,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.logout_rounded,
                  size: 14,
                  color: AppColors.textTertiary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
//  Drawer (mobile)
// ──────────────────────────────────────────────────────────────────────────

class _AdminDrawer extends StatelessWidget {
  const _AdminDrawer({
    required this.current,
    required this.fullName,
    required this.email,
    required this.onSelect,
    required this.onLogout,
  });

  final AdminSection current;
  final String fullName;
  final String email;
  final void Function(AdminSection) onSelect;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.surface0,
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _BrandPill(label: 'DEMS · Admin'),
              const SizedBox(height: 28),
              ...AdminSection.values.map((s) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _RailItem(
                      section: s,
                      selected: s == current,
                      extended: true,
                      onTap: () => onSelect(s),
                    ),
                  )),
              const Spacer(),
              _AccountTile(
                fullName: fullName,
                email: email,
                extended: true,
                onLogout: onLogout,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
//  Brand pill (top of rail / appbar)
// ──────────────────────────────────────────────────────────────────────────

class _BrandPill extends StatelessWidget {
  const _BrandPill({this.label});
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Row(
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
        if (label != null) ...[
          const SizedBox(width: 10),
          Text(
            label!,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ],
    );
  }
}

String _initialsFrom(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  final letters =
      parts.take(2).map((p) => p.isEmpty ? '' : p[0].toUpperCase()).join();
  return letters.isEmpty ? '·' : letters;
}
