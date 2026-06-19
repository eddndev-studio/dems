import '../../rubrics/data/rubric_models.dart';

/// Resultado consolidado por categoría — ranking de prototipos según el
/// promedio de los `total` de las evaluaciones submitted.
class CategoriaResults {
  const CategoriaResults({
    required this.categoria,
    required this.editionId,
    required this.rubricType,
    required this.maxTotal,
    required this.prototipos,
  });

  final CategoriaRef categoria;
  final String editionId;
  final RubricType rubricType;
  final int maxTotal;
  final List<PrototipoResult> prototipos;

  factory CategoriaResults.fromJson(Map<String, dynamic> json) =>
      CategoriaResults(
        categoria: CategoriaRef.fromJson(
            json['categoria'] as Map<String, dynamic>),
        editionId: json['edition_id'] as String,
        rubricType: RubricType.fromApi(json['rubric_type'] as String),
        maxTotal: (json['max_total'] as num).toInt(),
        prototipos: (json['prototipos'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(PrototipoResult.fromJson)
            .toList(growable: false),
      );
}

class CategoriaRef {
  const CategoriaRef({
    required this.id,
    required this.slug,
    required this.nombre,
  });

  final String id;
  final String slug;
  final String nombre;

  factory CategoriaRef.fromJson(Map<String, dynamic> json) => CategoriaRef(
        id: json['id'] as String,
        slug: json['slug'] as String,
        nombre: json['nombre'] as String,
      );
}

class PrototipoResult {
  const PrototipoResult({
    required this.prototipoId,
    required this.folio,
    required this.nombre,
    required this.nJurados,
    required this.promedio,
    required this.evaluaciones,
  });

  final String prototipoId;
  final String folio;
  final String nombre;
  final int nJurados;
  final double? promedio;
  final List<EvaluacionResult> evaluaciones;

  factory PrototipoResult.fromJson(Map<String, dynamic> json) =>
      PrototipoResult(
        prototipoId: json['prototipo_id'] as String,
        folio: json['folio'] as String,
        nombre: json['nombre'] as String,
        nJurados: (json['n_jurados'] as num).toInt(),
        promedio: (json['promedio'] as num?)?.toDouble(),
        evaluaciones: (json['evaluaciones'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(EvaluacionResult.fromJson)
            .toList(growable: false),
      );

  /// Promedio normalizado a [0, 1] respecto del [maxTotal] dado por la rúbrica.
  double? normalized(int maxTotal) {
    if (promedio == null || maxTotal <= 0) return null;
    return (promedio! / maxTotal).clamp(0.0, 1.0);
  }
}

class EvaluacionResult {
  const EvaluacionResult({
    required this.evaluacionId,
    required this.juradoId,
    required this.juradoNombre,
    required this.total,
    required this.submittedAt,
  });

  final String evaluacionId;
  final String juradoId;
  final String juradoNombre;
  final int total;
  final DateTime submittedAt;

  factory EvaluacionResult.fromJson(Map<String, dynamic> json) =>
      EvaluacionResult(
        evaluacionId: json['evaluacion_id'] as String,
        juradoId: json['jurado_id'] as String,
        juradoNombre: json['jurado_nombre'] as String,
        total: (json['total'] as num).toInt(),
        submittedAt: DateTime.parse(json['submitted_at'] as String),
      );
}

// ──────────────────────────────────────────────────────────────────────────
//  CSV export
// ──────────────────────────────────────────────────────────────────────────

class ExcelExport {
  const ExcelExport({required this.body, required this.filename});
  final List<int> body;
  final String filename;
}

// ──────────────────────────────────────────────────────────────────────────
//  Failures
// ──────────────────────────────────────────────────────────────────────────

sealed class ResultsFailure implements Exception {
  const ResultsFailure();
  String get message;
}

class ResultsNetwork extends ResultsFailure {
  const ResultsNetwork();
  @override
  String get message => 'No se pudo contactar al servidor.';
}

class ResultsUnauthorized extends ResultsFailure {
  const ResultsUnauthorized();
  @override
  String get message => 'Sesión expirada. Vuelve a iniciar sesión.';
}

class ResultsBadRequest extends ResultsFailure {
  const ResultsBadRequest(this.detail);
  final String detail;
  @override
  String get message => 'Parámetros inválidos: $detail';
}

class ResultsNotFound extends ResultsFailure {
  const ResultsNotFound();
  @override
  String get message => 'Categoría o edición no encontrada.';
}

class ResultsUnexpected extends ResultsFailure {
  const ResultsUnexpected(this.detail);
  final String detail;
  @override
  String get message => 'Error inesperado: $detail';
}
