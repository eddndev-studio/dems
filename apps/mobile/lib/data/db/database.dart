import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

// ---------------------------------------------------------------------------
//  Rubric cache (read-only, refreshed desde API)
// ---------------------------------------------------------------------------

class RubricTemplates extends Table {
  TextColumn get id => text()();
  TextColumn get nombre => text()();
  TextColumn get tipo => text()(); // exhibicion | memoria
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class RubricSections extends Table {
  TextColumn get id => text()();
  TextColumn get templateId => text()();
  TextColumn get nombre => text()();
  IntColumn get orden => integer()();
  RealColumn get pesoPct => real().nullable()();

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

// ---------------------------------------------------------------------------
//  Evaluaciones locales — fuente de verdad offline.
//
//  - [id]              UUID generado localmente (= client_id al API).
//  - [serverId]        UUID asignado por el backend tras CREATE.
//  - [dirty]           hay cambios sin pushear (scores/observaciones/etc).
//  - [submitRequested] el usuario pidió enviar; el worker ejecutará submit.
//  - [submittedAt]     timestamp server-side de submit confirmado.
//  - [syncedAt]        última vez que la fila se sincronizó con éxito.
// ---------------------------------------------------------------------------

class Evaluaciones extends Table {
  TextColumn get id => text()(); // client_id (UUID local)
  TextColumn get serverId => text().nullable()();
  TextColumn get prototipoId => text()();
  TextColumn get templateId => text()();
  TextColumn get juradoId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get submittedAt => dateTime().nullable()();
  DateTimeColumn get syncedAt => dateTime().nullable()();
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();
  BoolColumn get submitRequested =>
      boolean().withDefault(const Constant(false))();
  TextColumn get observaciones => text().nullable()();
  BoolColumn get acompanamientoAsesor => boolean().nullable()();
  IntColumn get opinionPersonal => integer().nullable()();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class EvaluacionScoresLocal extends Table {
  TextColumn get evaluacionLocalId => text()();
  TextColumn get criterionId => text()();
  IntColumn get score => integer().nullable()();
  TextColumn get textAnswer => text().nullable()();

  @override
  Set<Column> get primaryKey => {evaluacionLocalId, criterionId};
}

@DriftDatabase(
  tables: [
    RubricTemplates,
    RubricSections,
    RubricCriteria,
    Evaluaciones,
    EvaluacionScoresLocal,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.forTesting(super.e);

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
