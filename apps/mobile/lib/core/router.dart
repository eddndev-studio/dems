import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/application/auth_controller.dart';
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

      // Still reading secure storage — park on splash.
      if (auth.isLoading || !auth.hasValue) {
        return onSplash ? null : '/splash';
      }

      final value = auth.requireValue;
      final authed = value is AuthAuthenticated;

      if (!authed) {
        return onLogin ? null : '/login';
      }
      if (onLogin || onSplash) return '/';
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
