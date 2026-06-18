import 'dart:ffi';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';

import 'package:dems_mobile/data/db/database.dart';
import 'package:dems_mobile/data/db/evaluaciones_dao.dart';
import 'package:dems_mobile/data/sync/sync_worker.dart';
import 'package:dems_mobile/features/evaluaciones/data/evaluacion_models.dart';
import 'package:dems_mobile/features/evaluaciones/data/evaluaciones_repository.dart';

/// Fake repo: registra llamadas y permite programar respuestas/errores por
/// método sin tocar Dio real.
class _FakeRepo extends EvaluacionesRepository {
  _FakeRepo() : super(Dio());

  // Programables
  CreateEvaluacionResult Function(String clientId, List<EvaluacionScore> scores)?
      onCreate;
  void Function(String id, List<EvaluacionScore>? scores)? onPatch;
  EvaluacionView Function(String id)? onSubmit;
  EvaluacionView Function(String id)? onFetch;

  // Espías
  final List<String> calls = [];

  @override
  Future<CreateEvaluacionResult> createEvaluacion({
    required String prototipoId,
    required String templateId,
    required String clientId,
    List<EvaluacionScore> scores = const [],
    String? observaciones,
    bool? acompanamientoAsesor,
    int? opinionPersonal,
  }) async {
    calls.add('create');
    return onCreate!(clientId, scores);
  }

  @override
  Future<EvaluacionView> patchEvaluacion({
    required String id,
    List<EvaluacionScore>? scores,
    String? observaciones,
    bool? acompanamientoAsesor,
    int? opinionPersonal,
  }) async {
    calls.add('patch');
    onPatch?.call(id, scores);
    // El handler puede lanzar; si no, devuelve algo neutro.
    return _view(id, submittedAt: null);
  }

  @override
  Future<EvaluacionView> submitEvaluacion(String id) async {
    calls.add('submit');
    return onSubmit!(id);
  }

  @override
  Future<EvaluacionView> fetchEvaluacion(String id) async {
    calls.add('fetch');
    return onFetch!(id);
  }
}

EvaluacionView _view(String id,
        {DateTime? submittedAt, List<EvaluacionScore> scores = const []}) =>
    EvaluacionView(
      id: id,
      prototipoId: 'proto-1',
      templateId: 'tmpl-1',
      jurado: 'jur-1',
      submittedAt: submittedAt,
      scores: scores,
    );

/// El VM de tests no trae `libsqlite3.so` (eso lo aporta sqlite3_flutter_libs
/// en el dispositivo). Apuntamos al sqlite del sistema para tests hermético.
void _useSystemSqlite() {
  if (!Platform.isLinux) return;
  for (final candidate in [
    'libsqlite3.so',
    '/lib64/libsqlite3.so.0',
    '/usr/lib/x86_64-linux-gnu/libsqlite3.so.0',
    '/usr/lib64/libsqlite3.so.0',
  ]) {
    try {
      final lib = DynamicLibrary.open(candidate);
      open.overrideFor(OperatingSystem.linux, () => lib);
      return;
    } catch (_) {
      // probar el siguiente candidato
    }
  }
}

void main() {
  _useSystemSqlite();

  late AppDatabase db;
  late EvaluacionesDao dao;
  late _FakeRepo repo;

  Future<SyncWorker> makeWorker() async {
    return SyncWorker(
      dao: dao,
      repo: repo,
      connectivity: const Stream.empty(),
    );
  }

  Future<void> seedRow({
    required String localId,
    String? serverId,
    bool dirty = false,
    bool submitRequested = false,
    DateTime? submittedAt,
    Map<String, int> scores = const {},
  }) async {
    final now = DateTime.utc(2026, 6, 17);
    await dao.upsertEvaluacion(EvaluacionesCompanion(
      id: Value(localId),
      serverId: Value(serverId),
      prototipoId: const Value('proto-1'),
      templateId: const Value('tmpl-1'),
      juradoId: const Value('jur-1'),
      createdAt: Value(now),
      updatedAt: Value(now),
      submittedAt: Value(submittedAt),
      dirty: Value(dirty),
      submitRequested: Value(submitRequested),
    ));
    for (final e in scores.entries) {
      await dao.setScore(localId, e.key, e.value, null);
    }
    // setScore marca dirty; respetamos el flag pedido.
    await (db.update(db.evaluaciones)..where((t) => t.id.equals(localId)))
        .write(EvaluacionesCompanion(dirty: Value(dirty)));
  }

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dao = EvaluacionesDao(db);
    repo = _FakeRepo();
  });

  tearDown(() async {
    await db.close();
  });

  test('#2: submit 409 "already submitted" se trata como éxito (no error)',
      () async {
    final submittedAt = DateTime.utc(2026, 6, 17, 10);
    await seedRow(
      localId: 'L1',
      serverId: 'S1',
      submitRequested: true,
    );
    repo.onSubmit = (_) => throw const EvaluacionConflict(
        '{error: evaluation already submitted}');
    repo.onFetch = (id) => _view(id, submittedAt: submittedAt);

    final worker = await makeWorker();
    await worker.sync();

    final row = await dao.getById('L1');
    expect(row!.submittedAt!.toUtc(), submittedAt,
        reason: 'debe tomar el submitted_at del servidor');
    expect(row.submitRequested, isFalse);
    expect(row.lastError, isNull, reason: 'no debe envenenar la fila');
    expect(repo.calls, contains('fetch'));
    // La fila ya no debe quedar pending.
    expect(await dao.dirtyOrPending(), isEmpty);
  });

  test('#5: PATCH 409 "cannot edit" reconcilia con submitted_at del server',
      () async {
    final submittedAt = DateTime.utc(2026, 6, 17, 9);
    await seedRow(
      localId: 'L2',
      serverId: 'S2',
      dirty: true,
      scores: {'crit-1': 2},
    );
    repo.onPatch = (id, scores) => throw const EvaluacionConflict(
        '{error: evaluation already submitted; cannot edit}');
    repo.onFetch = (id) => _view(id, submittedAt: submittedAt);

    final worker = await makeWorker();
    await worker.sync();

    final row = await dao.getById('L2');
    expect(row!.submittedAt!.toUtc(), submittedAt);
    expect(row.dirty, isFalse, reason: 'el server es autoritativo');
    expect(row.lastError, isNull);
    expect(repo.calls, contains('fetch'));
    expect(await dao.dirtyOrPending(), isEmpty);
  });

  test('#3: create replay (200) con scores dirty encadena PATCH', () async {
    await seedRow(
      localId: 'L3',
      dirty: true,
      scores: {'crit-1': 3},
    );
    List<EvaluacionScore>? patchedScores;
    repo.onCreate = (clientId, scores) => CreateEvaluacionResult(
          view: _view('S3', submittedAt: null),
          replayed: true, // 200 → ya existía
        );
    repo.onPatch = (_, scores) => patchedScores = scores;

    final worker = await makeWorker();
    await worker.sync();

    expect(repo.calls, ['create', 'patch'],
        reason: 'replay dirty debe encadenar un patch de scores');
    expect(patchedScores, isNotNull);
    expect(patchedScores!.single.criterionId, 'crit-1');
    expect(patchedScores!.single.score, 3);

    final row = await dao.getById('L3');
    expect(row!.serverId, 'S3');
    expect(row.dirty, isFalse);
  });

  test('#3: replay + patch falla por red → la fila SIGUE dirty (no se pierde)',
      () async {
    await seedRow(
      localId: 'L5',
      dirty: true,
      scores: {'crit-1': 2},
    );
    repo.onCreate = (clientId, scores) => CreateEvaluacionResult(
          view: _view('S5', submittedAt: null),
          replayed: true,
        );
    repo.onPatch = (id, scores) => throw const EvaluacionNetworkFailure();

    final worker = await makeWorker();
    await worker.sync();

    final row = await dao.getById('L5');
    expect(row!.serverId, 'S5', reason: 'el serverId sí se asocia');
    expect(row.dirty, isTrue,
        reason: 'si el patch falla por red, dirty se conserva para reintento');
    // Sigue pendiente de sincronizar.
    expect(await dao.dirtyOrPending(), isNotEmpty);
  });

  test('#3: create nuevo (201) NO encadena patch', () async {
    await seedRow(
      localId: 'L4',
      dirty: true,
      scores: {'crit-1': 1},
    );
    repo.onCreate = (clientId, scores) => CreateEvaluacionResult(
          view: _view('S4', submittedAt: null),
          replayed: false, // 201 → recién creada con sus scores
        );

    final worker = await makeWorker();
    await worker.sync();

    expect(repo.calls, ['create'],
        reason: 'una creación 201 ya incluye los scores; sin patch extra');
    final row = await dao.getById('L4');
    expect(row!.serverId, 'S4');
    expect(row.dirty, isFalse);
  });

  // -------------------------------------------------------------------------
  //  #1 (regresión): un 409 edition_closed durante el sync NO debe envenenar
  //  la fila (error fatal / SyncPhase.error). Ramifica por el campo `code`.
  // -------------------------------------------------------------------------

  test(
      '#1: PATCH 409 edition_closed CON serverId → reconcilia (no envenena, '
      'no SyncPhase.error)', () async {
    final submittedAt = DateTime.utc(2026, 6, 17, 11);
    await seedRow(
      localId: 'E1',
      serverId: 'SE1',
      dirty: true,
      scores: {'crit-1': 2},
    );
    repo.onPatch = (id, scores) => throw const EvaluacionConflict(
          '{error: edition is closed}',
          code: 'edition_closed',
        );
    repo.onFetch = (id) => _view(id, submittedAt: submittedAt);

    final worker = await makeWorker();
    final phases = <SyncPhase>[];
    final sub = worker.reports.listen((r) => phases.add(r.phase));

    await worker.sync();
    await pumpEventQueue();
    await sub.cancel();

    final row = await dao.getById('E1');
    expect(row!.submittedAt!.toUtc(), submittedAt,
        reason: 'la fila guardada se reconcilia con el remoto autoritativo');
    expect(row.dirty, isFalse);
    expect(row.lastError, isNull, reason: 'no envenenada');
    expect(repo.calls, contains('fetch'));
    expect(await dao.dirtyOrPending(), isEmpty);
    expect(phases, isNot(contains(SyncPhase.error)),
        reason: 'no debe emitir SyncPhase.error');
  });

  test(
      '#1: PATCH 409 edition_closed CON serverId pero remoto BORRADOR → '
      'preserva el trabajo local (no lo descarta)', () async {
    await seedRow(
      localId: 'E1b',
      serverId: 'SE1b',
      dirty: true,
      submitRequested: true,
      scores: {'crit-1': 2},
    );
    repo.onPatch = (id, scores) => throw const EvaluacionConflict(
          '{error: edition is closed}',
          code: 'edition_closed',
        );
    // El remoto sigue siendo BORRADOR: las ediciones offline nunca llegaron.
    repo.onFetch = (id) => _view(id, submittedAt: null);

    final worker = await makeWorker();
    final phases = <SyncPhase>[];
    final sub = worker.reports.listen((r) => phases.add(r.phase));

    await worker.sync();
    await pumpEventQueue();
    await sub.cancel();

    final row = await dao.getById('E1b');
    expect(row!.submittedAt, isNull, reason: 'el remoto sigue borrador');
    expect(row.dirty, isTrue,
        reason: 'NO se descartan las ediciones offline: dirty se conserva');
    expect(row.submitRequested, isTrue,
        reason: 'la intención de submit se conserva para re-sincronizar');
    expect(row.lastError, isNotNull,
        reason: 'lastError suave (edición cerrada)');
    expect(row.lastError, contains('reabra'));
    // El trabajo sigue pendiente: re-sincronizará cuando el admin reabra.
    expect(await dao.dirtyOrPending(), isNotEmpty);
    expect(repo.calls, contains('fetch'));
    // No se intentó submit (la edición está cerrada).
    expect(repo.calls, isNot(contains('submit')));
    expect(phases, isNot(contains(SyncPhase.error)),
        reason: 'manejado: sin SyncPhase.error');
  });

  test(
      '#1: CREATE 409 edition_closed SIN serverId → lastError suave, datos '
      'preservados, no SyncPhase.error', () async {
    await seedRow(
      localId: 'E2',
      dirty: true,
      scores: {'crit-1': 3, 'crit-2': 1},
    );
    repo.onCreate = (clientId, scores) => throw const EvaluacionConflict(
          '{error: edition is closed}',
          code: 'edition_closed',
        );

    final worker = await makeWorker();
    final phases = <SyncPhase>[];
    final sub = worker.reports.listen((r) => phases.add(r.phase));

    await worker.sync();
    await pumpEventQueue();
    await sub.cancel();

    final row = await dao.getById('E2');
    expect(row, isNotNull, reason: 'la fila NO se borra');
    expect(row!.serverId, isNull, reason: 'sigue sin serverId (no se guardó)');
    expect(row.lastError, isNotNull,
        reason: 'lastError suave explicando que la edición está cerrada');
    expect(row.lastError, contains('cerrada'));
    // Los datos locales se preservan.
    final scores = await dao.loadScores('E2');
    expect(scores, hasLength(2), reason: 'los puntajes se conservan');
    expect(phases, isNot(contains(SyncPhase.error)),
        reason: 'manejado: no debe disparar SyncPhase.error espurio');

    // No spamea SyncPhase.error en ticks subsiguientes (la fila sigue pending
    // porque serverId es null, pero el reintento se vuelve a manejar suave).
    final phases2 = <SyncPhase>[];
    final sub2 = worker.reports.listen((r) => phases2.add(r.phase));
    await worker.sync();
    await pumpEventQueue();
    await sub2.cancel();
    expect(phases2, isNot(contains(SyncPhase.error)),
        reason: 'el reintento tampoco debe envenenar');
  });

  test('#1: 409 client_id_reused → lastError terminal, no SyncPhase.error',
      () async {
    await seedRow(
      localId: 'E3',
      dirty: true,
      scores: {'crit-1': 1},
    );
    repo.onCreate = (clientId, scores) => throw const EvaluacionConflict(
          '{error: client_id already used}',
          code: 'client_id_reused',
        );

    final worker = await makeWorker();
    final phases = <SyncPhase>[];
    final sub = worker.reports.listen((r) => phases.add(r.phase));

    await worker.sync();
    await pumpEventQueue();
    await sub.cancel();

    final row = await dao.getById('E3');
    expect(row!.lastError, isNotNull);
    expect(phases, isNot(contains(SyncPhase.error)),
        reason: 'error terminal manejado, no SyncPhase.error');
  });

  test(
      '#4: PATCH 409 already_submitted reconcilia a enviado → SALTA submit '
      'redundante', () async {
    final submittedAt = DateTime.utc(2026, 6, 17, 12);
    await seedRow(
      localId: 'E4',
      serverId: 'SE4',
      dirty: true,
      submitRequested: true, // pediría submit tras el patch...
      scores: {'crit-1': 2},
    );
    repo.onPatch = (id, scores) => throw const EvaluacionConflict(
          '{error: evaluation already submitted; cannot edit}',
          code: 'already_submitted',
        );
    repo.onFetch = (id) => _view(id, submittedAt: submittedAt);
    // submit NO debe llamarse; si se llamara, esto fallaría el test con NPE.

    final worker = await makeWorker();
    await worker.sync();

    expect(repo.calls, isNot(contains('submit')),
        reason: 'la reconciliación ya fijó submittedAt; submit es redundante');
    final row = await dao.getById('E4');
    expect(row!.submittedAt!.toUtc(), submittedAt);
    expect(row.submitRequested, isFalse);
    expect(await dao.dirtyOrPending(), isEmpty);
  });
}
