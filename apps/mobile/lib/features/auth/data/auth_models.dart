enum UserRole {
  admin,
  jurado;

  static UserRole fromApi(String raw) {
    switch (raw) {
      case 'admin':
        return UserRole.admin;
      case 'jurado':
        return UserRole.jurado;
      default:
        throw StateError('UserRole desconocido: $raw');
    }
  }
}

class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
  });

  final String id;
  final String email;
  final String fullName;
  final UserRole role;

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] as String,
        email: json['email'] as String,
        fullName: json['full_name'] as String,
        role: UserRole.fromApi(json['role'] as String),
      );
}

class AuthTokens {
  const AuthTokens({required this.access, required this.refresh});

  final String access;
  final String refresh;
}

class LoginResult {
  const LoginResult({required this.tokens, required this.user});

  final AuthTokens tokens;
  final AuthUser user;

  factory LoginResult.fromJson(Map<String, dynamic> json) => LoginResult(
        tokens: AuthTokens(
          access: json['access_token'] as String,
          refresh: json['refresh_token'] as String,
        ),
        user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
      );
}

/// Typed auth failures so the UI can render Spanish copy per cause.
sealed class AuthFailure implements Exception {
  const AuthFailure();
  String get message;
}

class InvalidCredentials extends AuthFailure {
  const InvalidCredentials();
  @override
  String get message => 'Correo o contraseña incorrectos.';
}

class UserInactive extends AuthFailure {
  const UserInactive();
  @override
  String get message => 'Cuenta desactivada. Contacta al administrador.';
}

class NetworkUnreachable extends AuthFailure {
  const NetworkUnreachable();
  @override
  String get message => 'Sin conexión con el servidor.';
}

class UnexpectedAuthError extends AuthFailure {
  const UnexpectedAuthError(this.detail);
  final String detail;
  @override
  String get message => 'Error inesperado: $detail';
}
