/// Plain view of an assignment row returned by GET /admin/prototipos/:id/assignments.
class Assignment {
  const Assignment({
    required this.prototipoId,
    required this.juradoId,
    required this.juradoFullName,
    required this.juradoEmail,
    required this.templateId,
    required this.assignedAt,
  });

  final String prototipoId;
  final String juradoId;
  final String juradoFullName;
  final String juradoEmail;
  final String templateId;
  final DateTime assignedAt;

  /// Parses one element of the prototipo-scoped list response.
  factory Assignment.fromJsonForPrototipo(
    String prototipoId,
    Map<String, dynamic> json,
  ) {
    final jurado = json['jurado'] as Map<String, dynamic>;
    return Assignment(
      prototipoId: prototipoId,
      juradoId: jurado['id'] as String,
      juradoFullName: jurado['full_name'] as String,
      juradoEmail: jurado['email'] as String,
      templateId: json['template_id'] as String,
      assignedAt: DateTime.parse(json['assigned_at'] as String),
    );
  }
}

/// Minimal jurado picker option (active jurados only).
class JuradoOption {
  const JuradoOption({
    required this.id,
    required this.fullName,
    required this.email,
  });

  final String id;
  final String fullName;
  final String email;

  factory JuradoOption.fromJson(Map<String, dynamic> json) => JuradoOption(
        id: json['id'] as String,
        fullName: json['full_name'] as String,
        email: json['email'] as String,
      );
}

/// Minimal template picker option scoped to a single edición.
class TemplateOption {
  const TemplateOption({
    required this.id,
    required this.editionId,
    required this.nombre,
    required this.tipo,
    required this.activo,
  });

  final String id;
  final String editionId;
  final String nombre;
  final String tipo; // 'exhibicion' | 'memoria_tecnica' (verbatim from API enum)
  final bool activo;

  factory TemplateOption.fromJson(Map<String, dynamic> json) => TemplateOption(
        id: json['id'] as String,
        editionId: json['edition_id'] as String,
        nombre: json['nombre'] as String,
        tipo: json['tipo'] as String,
        activo: json['activo'] as bool,
      );
}

// ──────────────────────────────────────────────────────────────────────────
//  Failures
// ──────────────────────────────────────────────────────────────────────────

sealed class AssignmentFailure implements Exception {
  const AssignmentFailure();
  String get message;
}

class AssignmentNetwork extends AssignmentFailure {
  const AssignmentNetwork();
  @override
  String get message => 'No se pudo contactar al servidor.';
}

class AssignmentUnauthorized extends AssignmentFailure {
  const AssignmentUnauthorized();
  @override
  String get message => 'Sesión expirada. Vuelve a iniciar sesión.';
}

/// 422: el usuario seleccionado no tiene rol jurado.
class AssignmentUserNotJurado extends AssignmentFailure {
  const AssignmentUserNotJurado();
  @override
  String get message => 'El usuario seleccionado no es jurado.';
}

/// 422: prototipo y template pertenecen a ediciones distintas.
class AssignmentEditionMismatch extends AssignmentFailure {
  const AssignmentEditionMismatch();
  @override
  String get message =>
      'El prototipo y la rúbrica pertenecen a ediciones distintas.';
}

/// 422 genérico (otra causa).
class AssignmentValidation extends AssignmentFailure {
  const AssignmentValidation(this.detail);
  final String detail;
  @override
  String get message => 'Datos inválidos: $detail';
}

/// 409: ya hay evaluación; quitar la asignación rompería la cadena.
class AssignmentHasEvaluation extends AssignmentFailure {
  const AssignmentHasEvaluation();
  @override
  String get message =>
      'Ya existe una evaluación para esta combinación; primero debe reabrirse.';
}

class AssignmentNotFound extends AssignmentFailure {
  const AssignmentNotFound();
  @override
  String get message => 'Asignación no encontrada.';
}

class AssignmentUnexpected extends AssignmentFailure {
  const AssignmentUnexpected(this.detail);
  final String detail;
  @override
  String get message => 'Error inesperado: $detail';
}
