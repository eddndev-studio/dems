import '../../../auth/data/auth_models.dart' show UserRole;

export '../../../auth/data/auth_models.dart' show UserRole;

class AdminUser {
  const AdminUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String email;
  final String fullName;
  final UserRole role;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory AdminUser.fromJson(Map<String, dynamic> json) => AdminUser(
        id: json['id'] as String,
        email: json['email'] as String,
        fullName: json['full_name'] as String,
        role: UserRole.fromApi(json['role'] as String),
        isActive: json['is_active'] as bool,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  AdminUser copyWith({
    String? fullName,
    UserRole? role,
    bool? isActive,
    DateTime? updatedAt,
  }) =>
      AdminUser(
        id: id,
        email: email,
        fullName: fullName ?? this.fullName,
        role: role ?? this.role,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

/// Filters applied to the user list.
class AdminUsersFilter {
  const AdminUsersFilter({this.role, this.activeOnly = false, this.query = ''});

  final UserRole? role;
  final bool activeOnly;
  final String query;

  AdminUsersFilter copyWith({
    Object? role = _sentinel,
    bool? activeOnly,
    String? query,
  }) =>
      AdminUsersFilter(
        role: identical(role, _sentinel) ? this.role : role as UserRole?,
        activeOnly: activeOnly ?? this.activeOnly,
        query: query ?? this.query,
      );

  static const Object _sentinel = Object();
}

// ──────────────────────────────────────────────────────────────────────────
//  Failures
// ──────────────────────────────────────────────────────────────────────────

sealed class AdminUsersFailure implements Exception {
  const AdminUsersFailure();
  String get message;
}

class AdminUsersNetwork extends AdminUsersFailure {
  const AdminUsersNetwork();
  @override
  String get message => 'No se pudo contactar al servidor.';
}

class AdminUsersUnauthorized extends AdminUsersFailure {
  const AdminUsersUnauthorized();
  @override
  String get message => 'Sesión expirada. Vuelve a iniciar sesión.';
}

class AdminUsersEmailTaken extends AdminUsersFailure {
  const AdminUsersEmailTaken();
  @override
  String get message => 'Ese correo ya está registrado.';
}

class AdminUsersHasEvaluations extends AdminUsersFailure {
  const AdminUsersHasEvaluations();
  @override
  String get message =>
      'No se puede eliminar: ya tiene evaluaciones. Desactívalo en su lugar.';
}

class AdminUsersValidation extends AdminUsersFailure {
  const AdminUsersValidation(this.detail);
  final String detail;
  @override
  String get message => 'Datos inválidos: $detail';
}

class AdminUsersNotFound extends AdminUsersFailure {
  const AdminUsersNotFound();
  @override
  String get message => 'Usuario no encontrado.';
}

class AdminUsersUnexpected extends AdminUsersFailure {
  const AdminUsersUnexpected(this.detail);
  final String detail;
  @override
  String get message => 'Error inesperado: $detail';
}
