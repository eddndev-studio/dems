/// Fase del flujo de una edición (espejo del enum `edition_phase` del API).
/// La estructura de rúbricas solo es editable en [preparacion].
enum EditionPhase {
  preparacion,
  evaluacion,
  cerrada;

  String get apiValue => switch (this) {
        EditionPhase.preparacion => 'preparacion',
        EditionPhase.evaluacion => 'evaluacion',
        EditionPhase.cerrada => 'cerrada',
      };

  String get label => switch (this) {
        EditionPhase.preparacion => 'Preparación',
        EditionPhase.evaluacion => 'Evaluación',
        EditionPhase.cerrada => 'Cerrada',
      };

  static EditionPhase fromApi(String s) => switch (s) {
        'preparacion' => EditionPhase.preparacion,
        'evaluacion' => EditionPhase.evaluacion,
        'cerrada' => EditionPhase.cerrada,
        _ => throw FormatException('Unknown edition phase: $s'),
      };
}

class Edition {
  const Edition({
    required this.id,
    required this.year,
    required this.name,
    required this.active,
    required this.phase,
    required this.createdAt,
  });

  final String id;
  final int year;
  final String name;
  final bool active;
  final EditionPhase phase;
  final DateTime createdAt;

  factory Edition.fromJson(Map<String, dynamic> json) => Edition(
        id: json['id'] as String,
        year: json['year'] as int,
        name: json['name'] as String,
        active: json['active'] as bool,
        phase: EditionPhase.fromApi(json['phase'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Edition copyWith({bool? active, String? name, EditionPhase? phase}) => Edition(
        id: id,
        year: year,
        name: name ?? this.name,
        active: active ?? this.active,
        phase: phase ?? this.phase,
        createdAt: createdAt,
      );
}

sealed class EditionsFailure implements Exception {
  const EditionsFailure();
  String get message;
}

class EditionsNetwork extends EditionsFailure {
  const EditionsNetwork();
  @override
  String get message => 'No se pudo contactar al servidor.';
}

class EditionsUnauthorized extends EditionsFailure {
  const EditionsUnauthorized();
  @override
  String get message => 'Sesión expirada. Vuelve a iniciar sesión.';
}

class EditionsYearTaken extends EditionsFailure {
  const EditionsYearTaken();
  @override
  String get message => 'Ya existe una edición con ese año.';
}

class EditionsHasReferences extends EditionsFailure {
  const EditionsHasReferences();
  @override
  String get message =>
      'No se puede eliminar: tiene rúbricas o prototipos asociados. '
      'Desactívala en su lugar.';
}

/// 409 al intentar reabrir una edición que ya tiene evaluaciones: descongelar
/// la rúbrica corrompería los puntajes capturados.
class EditionsPhaseLocked extends EditionsFailure {
  const EditionsPhaseLocked();
  @override
  String get message =>
      'No se puede regresar a preparación: ya hay evaluaciones registradas.';
}

class EditionsNotFound extends EditionsFailure {
  const EditionsNotFound();
  @override
  String get message => 'Edición no encontrada.';
}

class EditionsValidation extends EditionsFailure {
  const EditionsValidation(this.detail);
  final String detail;
  @override
  String get message => 'Datos inválidos: $detail';
}

class EditionsUnexpected extends EditionsFailure {
  const EditionsUnexpected(this.detail);
  final String detail;
  @override
  String get message => 'Error inesperado: $detail';
}
