import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/evaluaciones/data/evaluacion_models.dart';
import '../../features/evaluaciones/data/evaluaciones_repository.dart';
import '../db/database.dart';
import '../db/evaluaciones_dao.dart';

enum SyncPhase { idle, syncing, offline, error }

/// Clasificación de un 409 de evaluación por su `code` máquina (con fallback a
/// substring cuando el backend no manda `code`). Ver contrato en sync_worker.
enum _ConflictKind {
  alreadySubmitted,
  editionClosed,
  clientIdReused,

  /// Sin `code` reconocido: el llamador decide con el fallback por substring.
  unknown,
}

@immutable
class SyncReport {
  const SyncReport({
    required this.phase,
    this.pending = 0,
    this.lastError,
    this.lastSyncedAt,
  });
  final SyncPhase phase;
  final int pending;
  final String? lastError;
  final DateTime? lastSyncedAt;
}

/// Pushes local evaluaciones (dirty / submitRequested / sin serverId) al backend
/// usando el `client_id` como clave de idempotencia.
///
/// Detona sync cuando:
///  - recupera conectividad
///  - el controlador llama [sync] tras un write local
///  - al arranque (via [start])
class SyncWorker {
  SyncWorker({
    required EvaluacionesDao dao,
    required EvaluacionesRepository repo,
    required Stream<List<ConnectivityResult>> connectivity,
  })  : _dao = dao,
        _repo = repo,
        _connectivity = connectivity;

  final EvaluacionesDao _dao;
  final EvaluacionesRepository _repo;
  final Stream<List<ConnectivityResult>> _connectivity;

  final StreamController<SyncReport> _reports =
      StreamController<SyncReport>.broadcast();
  Stream<SyncReport> get reports => _reports.stream;

  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _running = false;
  bool _rescheduled = false;
  bool _online = true;
  DateTime? _lastSyncedAt;

  void start() {
    _sub ??= _connectivity.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      final wasOnline = _online;
      _online = online;
      if (online && !wasOnline) {
        unawaited(sync());
      } else if (!online) {
        _emit(SyncPhase.offline);
      }
    });
    unawaited(sync());
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await _reports.close();
  }

  Future<void> sync() async {
    if (_running) {
      _rescheduled = true;
      return;
    }
    _running = true;
    _rescheduled = false;
    try {
      await _drainOnce();
    } finally {
      _running = false;
      if (_rescheduled) {
        unawaited(sync());
      }
    }
  }

  Future<void> _drainOnce() async {
    final rows = await _dao.dirtyOrPending();
    if (rows.isEmpty) {
      _emit(SyncPhase.idle, pending: 0);
      return;
    }
    _emit(SyncPhase.syncing, pending: rows.length);

    String? fatalError;
    for (final row in rows) {
      try {
        await _syncRow(row);
      } on EvaluacionNetworkFailure {
        _emit(SyncPhase.offline, pending: rows.length);
        return;
      } on EvaluacionFailure catch (e) {
        await _dao.onSyncError(row.id, e.message);
        fatalError = e.message;
      } catch (e) {
        await _dao.onSyncError(row.id, e.toString());
        fatalError = e.toString();
      }
    }

    final remaining = await _dao.dirtyOrPending();
    if (fatalError != null) {
      _emit(SyncPhase.error,
          pending: remaining.length, lastError: fatalError);
    } else {
      _lastSyncedAt = DateTime.now().toUtc();
      _emit(SyncPhase.idle, pending: remaining.length);
    }
  }

  Future<void> _syncRow(Evaluacione row) async {
    // #4: el cliente siempre envía el SET COMPLETO de scores locales; el server
    // hace replace-all, así que no hay merge parcial que se pierda.
    final scores = await _dao.loadScores(row.id);
    final payload = scores
        .map((s) => EvaluacionScore(
              criterionId: s.criterionId,
              score: s.score,
              textAnswer: s.textAnswer,
            ))
        .toList(growable: false);

    var serverId = row.serverId;

    // Un 409 en el PATCH puede dejar la fila TOTALMENTE manejada (reconciliada a
    // enviada, o edición cerrada con el trabajo local preservado). En ese caso
    // saltamos el bloque de submit para no disparar un submit+fetch redundante
    // con un snapshot stale (#4/#5).
    var skipSubmit = false;

    if (serverId == null) {
      // CREATE. Un 409 aquí sólo puede venir de:
      //  - client_id_reused (#7): el client_id se reusó para otra terna →
      //    error terminal, no reintentar en loop.
      //  - edition_closed: el admin cerró la edición ANTES de que este create
      //    offline llegara. La fila NO tiene serverId (nunca se guardó), así
      //    que NO podemos reconciliar contra el remoto. La conservamos con un
      //    lastError suave y la tratamos como MANEJADA (no envenenamos ni
      //    disparamos SyncPhase.error); el admin puede reabrir la edición.
      final CreateEvaluacionResult created;
      try {
        created = await _repo.createEvaluacion(
          prototipoId: row.prototipoId,
          templateId: row.templateId,
          clientId: row.id,
          scores: payload,
          observaciones: row.observaciones,
          acompanamientoAsesor: row.acompanamientoAsesor,
          opinionPersonal: row.opinionPersonal,
        );
      } on EvaluacionConflict catch (e) {
        await _handleCreateConflict(row, e);
        return;
      }
      serverId = created.view.id;

      // #3: si el create fue un REPLAY idempotente (200) — la evaluación ya
      // existía en el server — y la fila local está dirty, sus scores nuevos
      // pueden no haber llegado nunca al backend (la creación original no los
      // incluyó). Empujamos un PATCH con el set completo para no perderlos.
      //
      // Importante: asociamos el serverId CONSERVANDO dirty. Si el PATCH falla
      // por red, la fila sigue dirty (y con serverId) → se reintenta por el
      // camino normal de patch. Sólo al patchear con éxito se limpia dirty.
      if (created.replayed && row.dirty && created.view.submittedAt == null) {
        await _dao.onCreatedRemoteKeepDirty(localId: row.id, serverId: serverId);
        skipSubmit = await _patchScores(
          row: row,
          serverId: serverId,
          payload: payload,
        );
      } else {
        await _dao.onCreatedRemote(localId: row.id, serverId: serverId);
      }
    } else if (row.dirty) {
      skipSubmit =
          await _patchScores(row: row, serverId: serverId, payload: payload);
    }

    // Si un 409 ya manejó la fila por completo (reconciliada a enviada, o
    // edición cerrada con el trabajo local preservado), no intentamos submit.
    if (skipSubmit) return;

    if (row.submitRequested && row.submittedAt == null) {
      try {
        final submitted = await _repo.submitEvaluacion(serverId);
        await _dao.onSubmittedRemote(
          localId: row.id,
          submittedAt: submitted.submittedAt ?? DateTime.now().toUtc(),
        );
      } on EvaluacionConflict catch (e) {
        await _handleSubmitConflict(row, serverId, e);
      }
    }
  }

  /// Maneja un 409 en el CREATE (la fila aún no tiene serverId).
  Future<void> _handleCreateConflict(
      Evaluacione row, EvaluacionConflict e) async {
    switch (_classify(e)) {
      case _ConflictKind.clientIdReused:
        // #7: no debería pasar. Error terminal — lastError claro, sin reintentar
        // en loop. Manejado: no disparamos SyncPhase.error espurio.
        await _dao.onSyncError(
          row.id,
          'No se pudo enviar: el identificador local se reusó para otra '
          'evaluación. Contacta a soporte.',
        );
      case _ConflictKind.editionClosed:
      case _ConflictKind.alreadySubmitted:
      case _ConflictKind.unknown:
        // Sin serverId no hay nada que reconciliar (la eval nunca se guardó):
        // conservamos la fila y sus datos con un lastError suave y lo tratamos
        // como manejado. El admin puede reabrir la edición para que sincronice.
        await _dao.onSyncError(
          row.id,
          'La edición está cerrada; estos puntajes no se enviaron.',
        );
    }
  }

  /// Maneja un 409 en el SUBMIT (la fila ya tiene serverId).
  Future<void> _handleSubmitConflict(
      Evaluacione row, String serverId, EvaluacionConflict e) async {
    switch (_classify(e)) {
      case _ConflictKind.alreadySubmitted:
        // #2: replay del submit. Traemos el estado remoto y lo tratamos como
        // éxito para que la fila deje de estar pending.
        final remote = await _repo.fetchEvaluacion(serverId);
        await _dao.onSubmittedRemote(
          localId: row.id,
          submittedAt: remote.submittedAt ?? DateTime.now().toUtc(),
        );
      case _ConflictKind.editionClosed:
        // La edición se cerró pero la fila SÍ está guardada (tiene serverId).
        // Si el remoto ya está enviado, reconciliamos; si sigue borrador,
        // preservamos el trabajo local para re-sincronizar al reabrir.
        await _reconcileEditionClosed(row, serverId);
      case _ConflictKind.clientIdReused:
        await _dao.onSyncError(
          row.id,
          'No se pudo enviar: el identificador local se reusó para otra '
          'evaluación. Contacta a soporte.',
        );
      case _ConflictKind.unknown:
        // Fallback de compat (sin code): "already submitted" → replay del
        // submit. Cualquier otro 409 desconocido es un error real → rethrow.
        if (_isAlreadySubmitted(e.detail)) {
          final remote = await _repo.fetchEvaluacion(serverId);
          await _dao.onSubmittedRemote(
            localId: row.id,
            submittedAt: remote.submittedAt ?? DateTime.now().toUtc(),
          );
        } else {
          throw e;
        }
    }
  }

  /// PATCH de scores con reconciliación ante 409 (#5).
  ///
  /// Devuelve `true` si el 409 dejó la fila TOTALMENTE manejada (reconciliada a
  /// enviada, o edición cerrada con el trabajo local preservado): el llamador
  /// debe saltar el bloque de submit. Devuelve `false` cuando el PATCH tuvo
  /// éxito y aún puede proceder un submit pendiente.
  Future<bool> _patchScores({
    required Evaluacione row,
    required String serverId,
    required List<EvaluacionScore> payload,
  }) async {
    try {
      await _repo.patchEvaluacion(
        id: serverId,
        scores: payload,
        observaciones: row.observaciones,
        acompanamientoAsesor: row.acompanamientoAsesor,
        opinionPersonal: row.opinionPersonal,
      );
      await _dao.onPatchedRemote(row.id);
      return false;
    } on EvaluacionConflict catch (e) {
      switch (_classify(e)) {
        case _ConflictKind.alreadySubmitted:
          // El remoto está enviado (estado final). El server es autoritativo:
          // reconciliamos y limpiamos dirty en vez de envenenar la fila.
          final remote = await _repo.fetchEvaluacion(serverId);
          await _dao.onReconciledFromRemote(
            localId: row.id,
            submittedAt: remote.submittedAt,
          );
          return true;
        case _ConflictKind.editionClosed:
          return _reconcileEditionClosed(row, serverId);
        case _ConflictKind.clientIdReused:
          await _dao.onSyncError(
            row.id,
            'No se pudo enviar: el identificador local se reusó para otra '
            'evaluación. Contacta a soporte.',
          );
          return true;
        case _ConflictKind.unknown:
          // Fallback de compat (sin code): "already submitted" / "cannot edit"
          // → reconciliar (#2/#5). Cualquier otro 409 desconocido → rethrow.
          if (_isCannotEdit(e.detail) || _isAlreadySubmitted(e.detail)) {
            final remote = await _repo.fetchEvaluacion(serverId);
            await _dao.onReconciledFromRemote(
              localId: row.id,
              submittedAt: remote.submittedAt,
            );
            return true;
          }
          rethrow;
      }
    }
  }

  /// Reconcilia una fila CON serverId cuyo 409 fue `edition_closed`.
  ///
  /// - Si el remoto YA está enviado (estado final) → reconciliar y limpiar.
  /// - Si el remoto sigue BORRADOR (submittedAt == null) → nuestras ediciones
  ///   offline NO llegaron al server; NO limpiamos dirty/submitRequested para
  ///   no perderlas. Las conservamos con un lastError suave; re-sincronizarán
  ///   cuando el admin reabra la edición.
  ///
  /// Devuelve siempre `true`: la fila quedó manejada (saltar el submit — con la
  /// edición cerrada un submit también daría 409).
  Future<bool> _reconcileEditionClosed(Evaluacione row, String serverId) async {
    final remote = await _repo.fetchEvaluacion(serverId);
    if (remote.submittedAt != null) {
      await _dao.onReconciledFromRemote(
        localId: row.id,
        submittedAt: remote.submittedAt,
      );
    } else {
      await _dao.onSyncError(
        row.id,
        'La edición está cerrada; tus cambios se enviarán cuando se reabra.',
      );
    }
    return true;
  }

  /// Clasifica un 409 por su `code` máquina; cae a substring (compat) cuando el
  /// backend aún no manda `code`.
  _ConflictKind _classify(EvaluacionConflict e) {
    switch (e.code) {
      case 'already_submitted':
        return _ConflictKind.alreadySubmitted;
      case 'edition_closed':
        return _ConflictKind.editionClosed;
      case 'client_id_reused':
        return _ConflictKind.clientIdReused;
    }
    // Sin code (o code desconocido como `incomplete`): el llamador decide
    // usando el fallback por substring.
    return _ConflictKind.unknown;
  }

  bool _isAlreadySubmitted(String detail) =>
      detail.toLowerCase().contains('already submitted');

  bool _isCannotEdit(String detail) =>
      detail.toLowerCase().contains('cannot edit');

  void _emit(SyncPhase phase, {int pending = 0, String? lastError}) {
    _reports.add(SyncReport(
      phase: phase,
      pending: pending,
      lastError: lastError,
      lastSyncedAt: _lastSyncedAt,
    ));
  }
}

// ---------------------------------------------------------------------------
//  Providers
// ---------------------------------------------------------------------------

final _connectivityStreamProvider =
    Provider<Stream<List<ConnectivityResult>>>((ref) {
  return Connectivity().onConnectivityChanged;
});

final syncWorkerProvider = Provider<SyncWorker>((ref) {
  final worker = SyncWorker(
    dao: ref.watch(evaluacionesDaoProvider),
    repo: ref.watch(evaluacionesRepositoryProvider),
    connectivity: ref.watch(_connectivityStreamProvider),
  );

  // Arranca sólo cuando el usuario está autenticado. Al hacer logout, lo
  // detenemos para que no pushée requests huérfanas.
  final sub = ref.listen<AsyncValue<AuthState>>(
    authControllerProvider,
    (previous, next) {
      final authed = next.value is AuthAuthenticated;
      if (authed) {
        worker.start();
      }
    },
    fireImmediately: true,
  );

  ref.onDispose(() {
    sub.close();
    unawaited(worker.dispose());
  });

  return worker;
});

final syncReportProvider = StreamProvider<SyncReport>((ref) {
  final worker = ref.watch(syncWorkerProvider);
  return worker.reports;
});
