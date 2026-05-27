import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/admin/admin_shell.dart';
import '../features/admin/editions/presentation/admin_editions_page.dart';
import '../features/admin/sections/admin_assignments_page.dart';
import '../features/admin/sections/admin_prototipos_page.dart';
import '../features/admin/sections/admin_results_page.dart';
import '../features/admin/sections/admin_rubrics_page.dart';
import '../features/admin/users/presentation/admin_users_page.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/auth/data/auth_models.dart';
import '../features/auth/login_page.dart';
import '../features/auth/splash_page.dart';
import '../features/evaluaciones/presentation/evaluacion_page.dart';
import '../features/home/home_page.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final listenable = _RouterListenable(ref);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: listenable,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final loc = state.matchedLocation;
      final onSplash = loc == '/splash';
      final onLogin = loc == '/login';

      if (auth.isLoading || !auth.hasValue) {
        return onSplash ? null : '/splash';
      }

      final value = auth.requireValue;
      if (value is! AuthAuthenticated) {
        return onLogin ? null : '/login';
      }

      final isAdmin = value.user.role == UserRole.admin;
      final landing = isAdmin ? '/admin/users' : '/';

      if (onLogin || onSplash) return landing;

      // Cross-role guards: a jurado cannot reach /admin/*, and an admin
      // landing on '/' jumps straight into the panel.
      if (!isAdmin && loc.startsWith('/admin')) return '/';
      if (isAdmin && loc == '/') return landing;

      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashPage()),
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(path: '/', builder: (_, _) => const HomePage()),
      GoRoute(
        path: '/evaluaciones/:prototipoId/:templateId',
        builder: (_, state) => EvaluacionPage(
          prototipoId: state.pathParameters['prototipoId']!,
          templateId: state.pathParameters['templateId']!,
        ),
      ),
      ShellRoute(
        builder: (context, state, child) => AdminShell(child: child),
        routes: [
          GoRoute(
            path: '/admin',
            redirect: (_, _) => '/admin/users',
          ),
          GoRoute(
            path: '/admin/users',
            builder: (_, _) => const AdminUsersPage(),
          ),
          GoRoute(
            path: '/admin/editions',
            builder: (_, _) => const AdminEditionsPage(),
          ),
          GoRoute(
            path: '/admin/prototipos',
            builder: (_, _) => const AdminPrototiposPage(),
          ),
          GoRoute(
            path: '/admin/assignments',
            builder: (_, _) => const AdminAssignmentsPage(),
          ),
          GoRoute(
            path: '/admin/rubric-templates',
            builder: (_, _) => const AdminRubricsPage(),
          ),
          GoRoute(
            path: '/admin/results',
            builder: (_, _) => const AdminResultsPage(),
          ),
        ],
      ),
    ],
  );
});

/// Bridges Riverpod's [authControllerProvider] to GoRouter's
/// [refreshListenable] hook so route guards re-run on sign-in / sign-out.
class _RouterListenable extends ChangeNotifier {
  _RouterListenable(this._ref) {
    _ref.listen<AsyncValue<AuthState>>(
      authControllerProvider,
      (_, _) => notifyListeners(),
      fireImmediately: false,
    );
  }

  final Ref _ref;
}
