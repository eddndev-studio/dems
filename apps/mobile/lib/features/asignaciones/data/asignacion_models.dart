enum RubricType {
  exhibicion,
  memoria;

  static RubricType fromApi(String raw) => switch (raw) {
        'exhibicion' => RubricType.exhibicion,
        'memoria' => RubricType.memoria,
        _ => throw StateError('RubricType desconocido: $raw'),
      };

  String get label => switch (this) {
        RubricType.exhibicion => 'Exhibición',
        RubricType.memoria => 'Memoria técnica',
      };
}

class PrototipoSummary {
  const PrototipoSummary({
    required this.id,
    required this.folio,
    required this.nombre,
  });

  final String id;
  final String folio;
  final String nombre;
  // No plantel

  factory PrototipoSummary.fromJson(Map<String, dynamic> json) =>
      PrototipoSummary(
        id: json['id'] as String,
        folio: json['folio'] as String,
        nombre: json['nombre'] as String,
      );
}

class RubricSummary {
  const RubricSummary({
    required this.id,
    required this.nombre,
    required this.tipo,
  });

  final String id;
  final String nombre;
  final RubricType tipo;

  factory RubricSummary.fromJson(Map<String, dynamic> json) => RubricSummary(
        id: json['id'] as String,
        nombre: json['nombre'] as String,
        tipo: RubricType.fromApi(json['tipo'] as String),
      );
}

enum EvaluacionStatus {
  pendiente,
  enProgreso,
  enviada;

  String get label => switch (this) {
        EvaluacionStatus.pendiente => 'Pendiente',
        EvaluacionStatus.enProgreso => 'En progreso',
        EvaluacionStatus.enviada => 'Enviada',
      };
}

class AsignacionItem {
  const AsignacionItem({
    required this.prototipo,
    required this.rubric,
    required this.evaluacionId,
    required this.submitted,
  });

  final PrototipoSummary prototipo;
  final RubricSummary rubric;
  final String? evaluacionId;
  final bool submitted;

  EvaluacionStatus get status {
    if (submitted) return EvaluacionStatus.enviada;
    if (evaluacionId != null) return EvaluacionStatus.enProgreso;
    return EvaluacionStatus.pendiente;
  }

  factory AsignacionItem.fromJson(Map<String, dynamic> json) => AsignacionItem(
        prototipo:
            PrototipoSummary.fromJson(json['prototipo'] as Map<String, dynamic>),
        rubric: RubricSummary.fromJson(json['rubric'] as Map<String, dynamic>),
        evaluacionId: json['evaluacion_id'] as String?,
        submitted: json['submitted'] as bool,
      );
}

sealed class AsignacionesFailure implements Exception {
  const AsignacionesFailure();
  String get message;
}

class AsignacionesNetworkFailure extends AsignacionesFailure {
  const AsignacionesNetworkFailure();
  @override
  String get message => 'No se pudo contactar al servidor.';
}

class AsignacionesUnauthorized extends AsignacionesFailure {
  const AsignacionesUnauthorized();
  @override
  String get message => 'Sesión expirada. Vuelve a iniciar sesión.';
}

class AsignacionesUnexpected extends AsignacionesFailure {
  const AsignacionesUnexpected(this.detail);
  final String detail;
  @override
  String get message => 'Error inesperado: $detail';
}
