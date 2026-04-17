import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

// ---------------------------------------------------------------------------
// Tablas locales (offline-first). Espejo mínimo del modelo del API.
// ---------------------------------------------------------------------------

class Prototipos extends Table {
  TextColumn get id => text()();
  TextColumn get folio => text()();
  TextColumn get nombre => text()();
  TextColumn get plantel => text().nullable()();
  BoolColumn get ejeTransversal => boolean().withDefault(const Constant(false))();
  TextColumn get descripcion => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class RubricTemplates extends Table {
  TextColumn get id => text()();
  TextColumn get nombre => text()();
  TextColumn get tipo => text()(); // exhibicion | memoria
  TextColumn get editionId => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class RubricSections extends Table {
  TextColumn get id => text()();
  TextColumn get templateId => text()();
  TextColumn get nombre => text()();
  IntColumn get orden => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class RubricCriteria extends Table {
  TextColumn get id => text()();
  TextColumn get sectionId => text()();
  TextColumn get texto => text()();
  IntColumn get orden => integer()();
  IntColumn get maxScore => integer()();
  TextColumn get kind => text()(); // scale | boolean | text_key

  @override
  Set<Column> get primaryKey => {id};
}

/// Evaluaciones locales. Se sincronizan al servidor cuando [submittedAt] no es null
/// y [syncedAt] es null.
class Evaluaciones extends Table {
  TextColumn get id => text()(); // client-generated UUID
  TextColumn get prototipoId => text()();
  TextColumn get templateId => text()();
  TextColumn get juradoId => text()();
  DateTimeColumn get submittedAt => dateTime().nullable()();
  DateTimeColumn get syncedAt => dateTime().nullable()();
  TextColumn get observaciones => text().nullable()();
  BoolColumn get acompanamientoAsesor => boolean().nullable()();
  IntColumn get opinionPersonal => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class EvaluacionScores extends Table {
  TextColumn get evaluacionId => text()();
  TextColumn get criterionId => text()();
  IntColumn get score => integer().nullable()();
  TextColumn get textAnswer => text().nullable()();

  @override
  Set<Column> get primaryKey => {evaluacionId, criterionId};
}

@DriftDatabase(
  tables: [
    Prototipos,
    RubricTemplates,
    RubricSections,
    RubricCriteria,
    Evaluaciones,
    EvaluacionScores,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'dems.sqlite'));
    return NativeDatabase(file);
  });
}
