import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_database_provider.dart';
import 'database.dart';

part 'evaluaciones_dao.g.dart';

@DriftAccessor(tables: [Evaluaciones, EvaluacionScoresLocal])
class EvaluacionesDao extends DatabaseAccessor<AppDatabase>
    with _$EvaluacionesDaoMixin {
  EvaluacionesDao(super.db);

  // ---------------------------------------------------------------------
  //  Lookup
  // ---------------------------------------------------------------------

  Future<EvaluacionLocalBundle?> findByKey({
    required String prototipoId,
    required String templateId,
    required String juradoId,
  }) async {
    final row = await (select(evaluaciones)
          ..where((e) =>
              e.prototipoId.equals(prototipoId) &
              e.templateId.equals(templateId) &
              e.juradoId.equals(juradoId))
          ..limit(1))
        .getSingleOrNull();
    if (row == null) return null;
    final scores = await loadScores(row.id);
    return EvaluacionLocalBundle(row: row, scores: scores);
  }

  Stream<EvaluacionLocalBundle?> watchByLocalId(String localId) {
    final rowStream = (select(evaluaciones)..where((e) => e.id.equals(localId)))
        .watchSingleOrNull();
    return rowStream.asyncMap((row) async {
      if (row == null) return null;
      final scores = await loadScores(row.id);
      return EvaluacionLocalBundle(row: row, scores: scores);
    });
  }

  Future<List<Evaluacione>> dirtyOrPending() {
    return (select(evaluaciones)
          ..where((e) =>
              e.dirty.equals(true) |
              e.submitRequested.equals(true) |
              e.serverId.isNull()))
        .get();
  }

  Future<List<EvaluacionScoresLocalData>> loadScores(String localId) {
    return (select(evaluacionScoresLocal)
          ..where((s) => s.evaluacionLocalId.equals(localId)))
        .get();
  }

  Future<Evaluacione?> getById(String localId) {
    return (select(evaluaciones)..where((e) => e.id.equals(localId)))
        .getSingleOrNull();
  }

  // ---------------------------------------------------------------------
  //  Writes (snapshot upsert)
  // ---------------------------------------------------------------------

  Future<void> upsertEvaluacion(EvaluacionesCompanion companion) {
    return into(evaluaciones).insertOnConflictUpdate(companion);
  }

  Future<void> markDirty(String localId) async {
    await (update(evaluaciones)..where((e) => e.id.equals(localId))).write(
      EvaluacionesCompanion(
        dirty: const Value(true),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  Future<void> setScore(
      String localId, String criterionId, int? score, String? textAnswer) async {
    await transaction(() async {
      if (score == null && (textAnswer == null || textAnswer.isEmpty)) {
        await (delete(evaluacionScoresLocal)
              ..where((s) =>
                  s.evaluacionLocalId.equals(localId) &
                  s.criterionId.equals(criterionId)))
            .go();
      } else {
        await into(evaluacionScoresLocal).insertOnConflictUpdate(
          EvaluacionScoresLocalCompanion(
            evaluacionLocalId: Value(localId),
            criterionId: Value(criterionId),
            score: Value(score),
            textAnswer: Value(textAnswer),
          ),
        );
      }
      await (update(evaluaciones)..where((e) => e.id.equals(localId))).write(
        EvaluacionesCompanion(
          dirty: const Value(true),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
    });
  }

  Future<void> setMeta({
    required String localId,
    String? observaciones,
    Object? acompanamientoAsesor = _noChange,
    Object? opinionPersonal = _noChange,
  }) async {
    await (update(evaluaciones)..where((e) => e.id.equals(localId))).write(
      EvaluacionesCompanion(
        observaciones: observaciones != null ? Value(observaciones) : const Value.absent(),
        acompanamientoAsesor: acompanamientoAsesor == _noChange
            ? const Value.absent()
            : Value(acompanamientoAsesor as bool?),
        opinionPersonal: opinionPersonal == _noChange
            ? const Value.absent()
            : Value(opinionPersonal as int?),
        dirty: const Value(true),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  Future<void> requestSubmit(String localId) {
    return (update(evaluaciones)..where((e) => e.id.equals(localId))).write(
      EvaluacionesCompanion(
        submitRequested: const Value(true),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  // ---------------------------------------------------------------------
  //  Sync callbacks
  // ---------------------------------------------------------------------

  Future<void> onCreatedRemote({
    required String localId,
    required String serverId,
  }) {
    return (update(evaluaciones)..where((e) => e.id.equals(localId))).write(
      EvaluacionesCompanion(
        serverId: Value(serverId),
        dirty: const Value(false),
        syncedAt: Value(DateTime.now().toUtc()),
        lastError: const Value(null),
      ),
    );
  }

  /// Fija el [serverId] tras un CREATE pero CONSERVA el flag dirty. Se usa en el
  /// camino de replay idempotente (#3): primero asociamos el id del servidor y
  /// luego empujamos los scores con un PATCH; si ese PATCH falla por red, la
  /// fila sigue dirty y se reintenta (no se pierden scores).
  Future<void> onCreatedRemoteKeepDirty({
    required String localId,
    required String serverId,
  }) {
    return (update(evaluaciones)..where((e) => e.id.equals(localId))).write(
      EvaluacionesCompanion(
        serverId: Value(serverId),
        lastError: const Value(null),
      ),
    );
  }

  Future<void> onPatchedRemote(String localId) {
    return (update(evaluaciones)..where((e) => e.id.equals(localId))).write(
      EvaluacionesCompanion(
        dirty: const Value(false),
        syncedAt: Value(DateTime.now().toUtc()),
        lastError: const Value(null),
      ),
    );
  }

  Future<void> onSubmittedRemote({
    required String localId,
    required DateTime submittedAt,
  }) {
    return (update(evaluaciones)..where((e) => e.id.equals(localId))).write(
      EvaluacionesCompanion(
        submittedAt: Value(submittedAt),
        submitRequested: const Value(false),
        dirty: const Value(false),
        syncedAt: Value(DateTime.now().toUtc()),
        lastError: const Value(null),
      ),
    );
  }

  /// Reconcilia la fila local con el estado autoritativo del servidor tras un
  /// 409 (p.ej. PATCH sobre una evaluación ya enviada): fija el [submittedAt]
  /// remoto, deja de pedir submit y limpia el flag dirty (el servidor manda).
  /// Tras esto la fila ya no debe quedar pending.
  Future<void> onReconciledFromRemote({
    required String localId,
    required DateTime? submittedAt,
  }) {
    return (update(evaluaciones)..where((e) => e.id.equals(localId))).write(
      EvaluacionesCompanion(
        submittedAt: Value(submittedAt),
        submitRequested: const Value(false),
        dirty: const Value(false),
        syncedAt: Value(DateTime.now().toUtc()),
        lastError: const Value(null),
      ),
    );
  }

  Future<void> onSyncError(String localId, String error) {
    return (update(evaluaciones)..where((e) => e.id.equals(localId))).write(
      EvaluacionesCompanion(lastError: Value(error)),
    );
  }
}

/// Sentinel for "don't touch this field" in nullable updates.
const Object _noChange = Object();

class EvaluacionLocalBundle {
  const EvaluacionLocalBundle({required this.row, required this.scores});
  final Evaluacione row;
  final List<EvaluacionScoresLocalData> scores;
}

final evaluacionesDaoProvider = Provider<EvaluacionesDao>((ref) {
  return EvaluacionesDao(ref.watch(appDatabaseProvider));
});
