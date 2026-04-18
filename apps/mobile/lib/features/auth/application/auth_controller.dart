import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_models.dart';
import '../data/auth_repository.dart';
import '../data/auth_storage.dart';

sealed class AuthState {
  const AuthState();
  const factory AuthState.unauthenticated() = AuthUnauthenticated;
  const factory AuthState.authenticated({required AuthUser user}) =
      AuthAuthenticated;
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

class AuthAuthenticated extends AuthState {
  const AuthAuthenticated({required this.user});
  final AuthUser user;
}

class AuthController extends AsyncNotifier<AuthState> {
  @override
  Future<AuthState> build() async {
    final storage = ref.watch(authStorageProvider);
    final tokens = await storage.readTokens();
    final user = await storage.readUser();
    if (tokens == null || user == null) {
      return const AuthState.unauthenticated();
    }
    return AuthState.authenticated(user: user);
  }

  Future<void> login({
    required String email,
    required String password,
  }) async {
    state = const AsyncLoading<AuthState>();
    try {
      final result = await ref.read(authRepositoryProvider).login(
            email: email,
            password: password,
          );
      final storage = ref.read(authStorageProvider);
      await storage.saveTokens(result.tokens);
      await storage.saveUser(result.user);
      state = AsyncData(AuthState.authenticated(user: result.user));
    } on AuthFailure catch (e, st) {
      state = AsyncError(e, st);
    } catch (e, st) {
      state = AsyncError(UnexpectedAuthError(e.toString()), st);
    }
  }

  Future<void> logout() async {
    await ref.read(authStorageProvider).clear();
    state = const AsyncData(AuthState.unauthenticated());
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthState>(AuthController.new);
