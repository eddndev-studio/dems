import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/login_page.dart';
import '../features/home/home_page.dart';
import '../features/evaluations/evaluation_page.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(path: '/', builder: (_, _) => const HomePage()),
      GoRoute(
        path: '/evaluaciones/:id',
        builder: (_, state) =>
            EvaluationPage(prototipoId: state.pathParameters['id']!),
      ),
    ],
  );
});
