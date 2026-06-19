/// Compara folios con orden "natural": las secuencias de dígitos se comparan
/// por valor numérico, no carácter a carácter. Así "P-2" va antes que "P-10"
/// y "ABC9" antes que "ABC10", aunque no estén rellenados con ceros. Si los
/// folios ya vienen con padding fijo el resultado coincide con el orden
/// lexicográfico; el comparador es robusto en ambos casos.
int compareFoliosNatural(String a, String b) {
  final ra = _folioTokens(a);
  final rb = _folioTokens(b);
  final n = ra.length < rb.length ? ra.length : rb.length;
  for (var i = 0; i < n; i++) {
    final ta = ra[i];
    final tb = rb[i];
    final na = int.tryParse(ta);
    final nb = int.tryParse(tb);
    final int cmp;
    if (na != null && nb != null) {
      cmp = na.compareTo(nb);
    } else {
      cmp = ta.toLowerCase().compareTo(tb.toLowerCase());
    }
    if (cmp != 0) return cmp;
  }
  return ra.length.compareTo(rb.length);
}

/// Parte el folio en tokens alternando dígitos / no-dígitos.
List<String> _folioTokens(String s) =>
    RegExp(r'\d+|\D+').allMatches(s).map((m) => m.group(0)!).toList();

/// Orden del panel del jurado: primero lo que falta por evaluar
/// (pendiente / en progreso), luego lo ya enviado. Dentro de cada grupo, por
/// folio con orden natural (P-2 antes que P-10). Así el jurado siempre ve
/// arriba lo que le queda pendiente y abajo lo que ya entregó. No muta la
/// lista de entrada.
List<AsignacionItem> orderAsignaciones(List<AsignacionItem> items) {
  final sorted = [...items]..sort((a, b) {
      final aDone = a.submitted ? 1 : 0;
      final bDone = b.submitted ? 1 : 0;
      if (aDone != bDone) return aDone - bDone;
      final byFolio =
          compareFoliosNatural(a.prototipo.folio, b.prototipo.folio);
      if (byFolio != 0) return byFolio;
      return a.rubric.tipo.index.compareTo(b.rubric.tipo.index);
    });
  return List.unmodifiable(sorted);
}

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
