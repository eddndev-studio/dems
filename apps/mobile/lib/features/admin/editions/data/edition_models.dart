class Edition {
  const Edition({
    required this.id,
    required this.year,
    required this.name,
    required this.active,
    required this.createdAt,
  });

  final String id;
  final int year;
  final String name;
  final bool active;
  final DateTime createdAt;

  factory Edition.fromJson(Map<String, dynamic> json) => Edition(
        id: json['id'] as String,
        year: json['year'] as int,
        name: json['name'] as String,
        active: json['active'] as bool,
        createdAt: DateTime.parse(json['created_at'] as String),
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
