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
    final scores = await _dao.loadScores(row.id);
    final payload = scores
        .map((s) => EvaluacionScore(
              criterionId: s.criterionId,
              score: s.score,
              textAnswer: s.textAnswer,
            ))
        .toList(growable: false);

    var serverId = row.serverId;

    if (serverId == null) {
      final created = await _repo.createEvaluacion(
        prototipoId: row.prototipoId,
        templateId: row.templateId,
        clientId: row.id,
        scores: payload,
        observaciones: row.observaciones,
        acompanamientoAsesor: row.acompanamientoAsesor,
        opinionPersonal: row.opinionPersonal,
      );
      serverId = created.id;
      await _dao.onCreatedRemote(localId: row.id, serverId: serverId);
    } else if (row.dirty) {
      await _repo.patchEvaluacion(
        id: serverId,
        scores: payload,
        observaciones: row.observaciones,
        acompanamientoAsesor: row.acompanamientoAsesor,
        opinionPersonal: row.opinionPersonal,
      );
      await _dao.onPatchedRemote(row.id);
    }

    if (row.submitRequested && row.submittedAt == null) {
      final submitted = await _repo.submitEvaluacion(serverId);
      await _dao.onSubmittedRemote(
        localId: row.id,
        submittedAt: submitted.submittedAt ?? DateTime.now().toUtc(),
      );
    }
  }

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
