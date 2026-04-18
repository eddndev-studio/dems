// -----------------------------------------------------------------------------
//  Rubric tree (fetched from GET /me/rubric-templates/:id)
// -----------------------------------------------------------------------------

enum CriterionKind {
  scale,
  boolean,
  textKey;

  static CriterionKind fromApi(String raw) => switch (raw) {
        'scale' => CriterionKind.scale,
        'boolean' => CriterionKind.boolean,
        'text_key' => CriterionKind.textKey,
        _ => throw StateError('CriterionKind desconocido: $raw'),
      };
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
  final CriterionKind kind;

  factory RubricCriterion.fromJson(Map<String, dynamic> j) => RubricCriterion(
        id: j['id'] as String,
        texto: j['texto'] as String,
        orden: j['orden'] as int,
        maxScore: j['max_score'] as int,
        kind: CriterionKind.fromApi(j['kind'] as String),
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

  bool get isScoring =>
      criteria.any((c) => c.kind == CriterionKind.scale || c.kind == CriterionKind.boolean);

  factory RubricSection.fromJson(Map<String, dynamic> j) => RubricSection(
        id: j['id'] as String,
        nombre: j['nombre'] as String,
        orden: j['orden'] as int,
        pesoPct: (j['peso_pct'] as num?)?.toDouble(),
        criteria: (j['criteria'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(RubricCriterion.fromJson)
            .toList(growable: false),
      );
}

class RubricTemplateDetail {
  const RubricTemplateDetail({
    required this.id,
    required this.nombre,
    required this.tipo,
    required this.sections,
  });

  final String id;
  final String nombre;
  final String tipo;
  final List<RubricSection> sections;

  int get scoringCount => sections
      .expand((s) => s.criteria)
      .where((c) => c.kind == CriterionKind.scale || c.kind == CriterionKind.boolean)
      .length;

  factory RubricTemplateDetail.fromJson(Map<String, dynamic> j) =>
      RubricTemplateDetail(
        id: j['id'] as String,
        nombre: j['nombre'] as String,
        tipo: j['tipo'] as String,
        sections: (j['sections'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(RubricSection.fromJson)
            .toList(growable: false),
      );
}

// -----------------------------------------------------------------------------
//  Evaluation view (from POST/GET/PATCH /evaluaciones)
// -----------------------------------------------------------------------------

class EvaluacionScore {
  const EvaluacionScore({
    required this.criterionId,
    this.score,
    this.textAnswer,
  });

  final String criterionId;
  final int? score;
  final String? textAnswer;

  Map<String, dynamic> toJson() => {
        'criterion_id': criterionId,
        if (score != null) 'score': score,
        if (textAnswer != null) 'text_answer': textAnswer,
      };

  factory EvaluacionScore.fromJson(Map<String, dynamic> j) => EvaluacionScore(
        criterionId: j['criterion_id'] as String,
        score: j['score'] as int?,
        textAnswer: j['text_answer'] as String?,
      );
}

class EvaluacionView {
  const EvaluacionView({
    required this.id,
    required this.prototipoId,
    required this.templateId,
    required this.jurado,
    required this.submittedAt,
    required this.scores,
    this.observaciones,
    this.acompanamientoAsesor,
    this.opinionPersonal,
  });

  final String id;
  final String prototipoId;
  final String templateId;
  final String jurado;
  final DateTime? submittedAt;
  final String? observaciones;
  final bool? acompanamientoAsesor;
  final int? opinionPersonal;
  final List<EvaluacionScore> scores;

  bool get isSubmitted => submittedAt != null;

  factory EvaluacionView.fromJson(Map<String, dynamic> j) => EvaluacionView(
        id: j['id'] as String,
        prototipoId: j['prototipo_id'] as String,
        templateId: j['template_id'] as String,
        jurado: j['jurado_id'] as String,
        submittedAt: j['submitted_at'] == null
            ? null
            : DateTime.parse(j['submitted_at'] as String),
        observaciones: j['observaciones'] as String?,
        acompanamientoAsesor: j['acompanamiento_asesor'] as bool?,
        opinionPersonal: j['opinion_personal'] as int?,
        scores: (j['scores'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(EvaluacionScore.fromJson)
            .toList(growable: false),
      );
}

// -----------------------------------------------------------------------------
//  Failures
// -----------------------------------------------------------------------------

sealed class EvaluacionFailure implements Exception {
  const EvaluacionFailure();
  String get message;
}

class EvaluacionNetworkFailure extends EvaluacionFailure {
  const EvaluacionNetworkFailure();
  @override
  String get message => 'Sin conexión con el servidor.';
}

class EvaluacionForbidden extends EvaluacionFailure {
  const EvaluacionForbidden();
  @override
  String get message => 'No estás asignado a esta rúbrica.';
}

class EvaluacionNotFound extends EvaluacionFailure {
  const EvaluacionNotFound();
  @override
  String get message => 'Evaluación no encontrada.';
}

class EvaluacionConflict extends EvaluacionFailure {
  const EvaluacionConflict(this.detail);
  final String detail;
  @override
  String get message => detail;
}

class EvaluacionValidation extends EvaluacionFailure {
  const EvaluacionValidation(this.detail);
  final String detail;
  @override
  String get message => detail;
}

class EvaluacionUnexpected extends EvaluacionFailure {
  const EvaluacionUnexpected(this.detail);
  final String detail;
  @override
  String get message => 'Error inesperado: $detail';
}
