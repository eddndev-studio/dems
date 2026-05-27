/// RubricType enum mirrored from the API (`exhibicion` | `memoria`).
enum RubricType {
  exhibicion,
  memoria;

  String get apiValue => switch (this) {
        RubricType.exhibicion => 'exhibicion',
        RubricType.memoria => 'memoria',
      };

  String get label => switch (this) {
        RubricType.exhibicion => 'Exhibición',
        RubricType.memoria => 'Memoria técnica',
      };

  static RubricType fromApi(String s) => switch (s) {
        'exhibicion' => RubricType.exhibicion,
        'memoria' => RubricType.memoria,
        _ => throw FormatException('Unknown rubric type: $s'),
      };
}

class RubricSummary {
  const RubricSummary({
    required this.id,
    required this.editionId,
    required this.nombre,
    required this.tipo,
    required this.descripcion,
    required this.activo,
    required this.sectionCount,
    required this.criterionCount,
  });

  final String id;
  final String editionId;
  final String nombre;
  final RubricType tipo;
  final String? descripcion;
  final bool activo;
  final int sectionCount;
  final int criterionCount;

  factory RubricSummary.fromJson(Map<String, dynamic> json) => RubricSummary(
        id: json['id'] as String,
        editionId: json['edition_id'] as String,
        nombre: json['nombre'] as String,
        tipo: RubricType.fromApi(json['tipo'] as String),
        descripcion: json['descripcion'] as String?,
        activo: json['activo'] as bool,
        sectionCount: (json['section_count'] as num).toInt(),
        criterionCount: (json['criterion_count'] as num).toInt(),
      );

  RubricSummary copyWith({
    String? nombre,
    String? descripcion,
    bool? activo,
  }) =>
      RubricSummary(
        id: id,
        editionId: editionId,
        nombre: nombre ?? this.nombre,
        tipo: tipo,
        descripcion: descripcion ?? this.descripcion,
        activo: activo ?? this.activo,
        sectionCount: sectionCount,
        criterionCount: criterionCount,
      );
}

class RubricSection {
  const RubricSection({
    required this.id,
    required this.nombre,
    required this.orden,
    required this.pesoPct,
    required this.criteria,
  });

  final String id;
  final String nombre;
  final int orden;
  final double? pesoPct;
  final List<RubricCriterion> criteria;

  factory RubricSection.fromJson(Map<String, dynamic> json) => RubricSection(
        id: json['id'] as String,
        nombre: json['nombre'] as String,
        orden: (json['orden'] as num).toInt(),
        pesoPct: (json['peso_pct'] as num?)?.toDouble(),
        criteria: (json['criteria'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(RubricCriterion.fromJson)
            .toList(),
      );
}

class RubricCriterion {
  const RubricCriterion({
    required this.id,
    required this.texto,
    required this.orden,
    required this.maxScore,
    required this.kind,
  });

  final String id;
  final String texto;
  final int orden;
  final int maxScore;
  final String kind; // 'scale' | 'boolean' | 'text_key'

  factory RubricCriterion.fromJson(Map<String, dynamic> json) =>
      RubricCriterion(
        id: json['id'] as String,
        texto: json['texto'] as String,
        orden: (json['orden'] as num).toInt(),
        maxScore: (json['max_score'] as num).toInt(),
        kind: json['kind'] as String,
      );

  String get kindLabel => switch (kind) {
        'scale' => 'Escala',
        'boolean' => 'Sí/No',
        'text_key' => 'Texto clave',
        _ => kind,
      };
}

class RubricDetail {
  const RubricDetail({
    required this.id,
    required this.editionId,
    required this.nombre,
    required this.tipo,
    required this.descripcion,
    required this.activo,
    required this.categorias,
    required this.sections,
  });

  final String id;
  final String editionId;
  final String nombre;
  final RubricType tipo;
  final String? descripcion;
  final bool activo;
  final List<String> categorias;
  final List<RubricSection> sections;

  factory RubricDetail.fromJson(Map<String, dynamic> json) => RubricDetail(
        id: json['id'] as String,
        editionId: json['edition_id'] as String,
        nombre: json['nombre'] as String,
        tipo: RubricType.fromApi(json['tipo'] as String),
        descripcion: json['descripcion'] as String?,
        activo: json['activo'] as bool,
        categorias: (json['categorias'] as List<dynamic>).cast<String>(),
        sections: (json['sections'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(RubricSection.fromJson)
            .toList(),
      );

  int get totalMaxScore => sections.fold(
        0,
        (sum, s) => sum + s.criteria.fold(0, (a, c) => a + c.maxScore),
      );
}

// ──────────────────────────────────────────────────────────────────────────
//  Failures
// ──────────────────────────────────────────────────────────────────────────

sealed class RubricFailure implements Exception {
  const RubricFailure();
  String get message;
}

class RubricNetwork extends RubricFailure {
  const RubricNetwork();
  @override
  String get message => 'No se pudo contactar al servidor.';
}

class RubricUnauthorized extends RubricFailure {
  const RubricUnauthorized();
  @override
  String get message => 'Sesión expirada. Vuelve a iniciar sesión.';
}

/// 409: la rúbrica ya tiene evaluaciones registradas; la opción correcta es
/// archivarla (PATCH activo=false) en lugar de eliminarla.
class RubricHasEvaluations extends RubricFailure {
  const RubricHasEvaluations();
  @override
  String get message =>
      'No se puede eliminar: ya tiene evaluaciones. Archívala desactivándola.';
}

class RubricValidation extends RubricFailure {
  const RubricValidation(this.detail);
  final String detail;
  @override
  String get message => 'Datos inválidos: $detail';
}

class RubricNotFound extends RubricFailure {
  const RubricNotFound();
  @override
  String get message => 'Rúbrica no encontrada.';
}

class RubricUnexpected extends RubricFailure {
  const RubricUnexpected(this.detail);
  final String detail;
  @override
  String get message => 'Error inesperado: $detail';
}
