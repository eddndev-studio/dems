// ──────────────────────────────────────────────────────────────────────────
//  Catalogs
// ──────────────────────────────────────────────────────────────────────────

class Categoria {
  const Categoria({
    required this.id,
    required this.slug,
    required this.nombre,
    required this.orden,
  });

  final String id;
  final String slug;
  final String nombre;
  final int orden;

  factory Categoria.fromJson(Map<String, dynamic> json) => Categoria(
        id: json['id'] as String,
        slug: json['slug'] as String,
        nombre: json['nombre'] as String,
        orden: (json['orden'] as num).toInt(),
      );
}

// ──────────────────────────────────────────────────────────────────────────
//  Prototipos
// ──────────────────────────────────────────────────────────────────────────

class PrototipoSummary {
  const PrototipoSummary({
    required this.id,
    required this.editionId,
    required this.folio,
    required this.nombre,
    required this.plantel,
    required this.ejeTransversal,
    required this.createdAt,
  });

  final String id;
  final String editionId;
  final String folio;
  final String nombre;
  final String? plantel;
  final bool ejeTransversal;
  final DateTime createdAt;

  factory PrototipoSummary.fromJson(Map<String, dynamic> json) =>
      PrototipoSummary(
        id: json['id'] as String,
        editionId: json['edition_id'] as String,
        folio: json['folio'] as String,
        nombre: json['nombre'] as String,
        plantel: json['plantel'] as String?,
        ejeTransversal: json['eje_transversal'] as bool,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  PrototipoSummary copyWith({
    String? nombre,
    String? plantel,
    bool? ejeTransversal,
  }) =>
      PrototipoSummary(
        id: id,
        editionId: editionId,
        folio: folio,
        nombre: nombre ?? this.nombre,
        plantel: plantel ?? this.plantel,
        ejeTransversal: ejeTransversal ?? this.ejeTransversal,
        createdAt: createdAt,
      );
}

class Integrante {
  const Integrante({required this.id, required this.nombre, required this.rol});
  final String id;
  final String nombre;
  final String? rol;

  factory Integrante.fromJson(Map<String, dynamic> json) => Integrante(
        id: json['id'] as String,
        nombre: json['nombre'] as String,
        rol: json['rol'] as String?,
      );
}

class IntegranteInput {
  const IntegranteInput({required this.nombre, this.rol});
  final String nombre;
  final String? rol;

  Map<String, dynamic> toJson() => {
        'nombre': nombre,
        if (rol != null && rol!.trim().isNotEmpty) 'rol': rol,
      };
}

class PrototipoDetail {
  const PrototipoDetail({
    required this.id,
    required this.editionId,
    required this.folio,
    required this.nombre,
    required this.plantel,
    required this.ejeTransversal,
    required this.descripcion,
    required this.categorias,
    required this.integrantes,
    required this.createdAt,
  });

  final String id;
  final String editionId;
  final String folio;
  final String nombre;
  final String? plantel;
  final bool ejeTransversal;
  final String? descripcion;
  final List<String> categorias;
  final List<Integrante> integrantes;
  final DateTime createdAt;

  factory PrototipoDetail.fromJson(Map<String, dynamic> json) =>
      PrototipoDetail(
        id: json['id'] as String,
        editionId: json['edition_id'] as String,
        folio: json['folio'] as String,
        nombre: json['nombre'] as String,
        plantel: json['plantel'] as String?,
        ejeTransversal: json['eje_transversal'] as bool,
        descripcion: json['descripcion'] as String?,
        categorias: (json['categorias'] as List<dynamic>).cast<String>(),
        integrantes: (json['integrantes'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(Integrante.fromJson)
            .toList(),
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  PrototipoSummary toSummary() => PrototipoSummary(
        id: id,
        editionId: editionId,
        folio: folio,
        nombre: nombre,
        plantel: plantel,
        ejeTransversal: ejeTransversal,
        createdAt: createdAt,
      );
}

// ──────────────────────────────────────────────────────────────────────────
//  Failures
// ──────────────────────────────────────────────────────────────────────────

sealed class PrototipoFailure implements Exception {
  const PrototipoFailure();
  String get message;
}

class PrototipoNetwork extends PrototipoFailure {
  const PrototipoNetwork();
  @override
  String get message => 'No se pudo contactar al servidor.';
}

class PrototipoUnauthorized extends PrototipoFailure {
  const PrototipoUnauthorized();
  @override
  String get message => 'Sesión expirada. Vuelve a iniciar sesión.';
}

class PrototipoFolioTaken extends PrototipoFailure {
  const PrototipoFolioTaken();
  @override
  String get message => 'Ese folio ya existe en la edición seleccionada.';
}

class PrototipoHasEvaluations extends PrototipoFailure {
  const PrototipoHasEvaluations();
  @override
  String get message =>
      'No se puede eliminar: ya tiene evaluaciones registradas.';
}

class PrototipoValidation extends PrototipoFailure {
  const PrototipoValidation(this.detail);
  final String detail;
  @override
  String get message => 'Datos inválidos: $detail';
}

class PrototipoNotFound extends PrototipoFailure {
  const PrototipoNotFound();
  @override
  String get message => 'Prototipo no encontrado.';
}

class PrototipoUnexpected extends PrototipoFailure {
  const PrototipoUnexpected(this.detail);
  final String detail;
  @override
  String get message => 'Error inesperado: $detail';
}
