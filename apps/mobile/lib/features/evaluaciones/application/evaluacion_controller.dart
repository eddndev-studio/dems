import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../data/db/database.dart';
import '../../../data/db/evaluaciones_dao.dart';
import '../../../data/db/rubrics_dao.dart';
import '../../../data/sync/sync_worker.dart';
import '../../asignaciones/application/asignaciones_controller.dart';
import '../../auth/application/auth_controller.dart';
import '../data/evaluacion_models.dart';
import '../data/evaluaciones_repository.dart';

@immutable
class EvaluacionKey {
  const EvaluacionKey({required this.prototipoId, required this.templateId});
  final String prototipoId;
  final String templateId;

  @override
  bool operator ==(Object other) =>
      other is EvaluacionKey &&
      other.prototipoId == prototipoId &&
      other.templateId == templateId;

  @override
  int get hashCode => Object.hash(prototipoId, templateId);
}

@immutable
class EvaluacionFormState {
  const EvaluacionFormState({
    required this.rubric,
    required this.scores,
    required this.textAnswers,
    required this.localId,
    required this.serverId,
    required this.submitted,
    required this.submitRequested,
    required this.dirty,
    this.observaciones,
    this.acompanamientoAsesor,
    this.opinionPersonal,
    this.lastError,
  });

  final RubricTemplateDetail rubric;

  /// criterion_id → score
  final Map<String, int> scores;

  /// criterion_id → text_answer
  final Map<String, String> textAnswers;

  final String localId;
  final String? serverId;
  final bool submitted;
  final bool submitRequested;
  final bool dirty;
  final String? observaciones;
  final bool? acompanamientoAsesor;
  final int? opinionPersonal;
  final String? lastError;

  int get completedCount => scores.length;

  double get progress {
    final total = rubric.scoringCount;
    if (total == 0) return 1.0;
    return (completedCount / total).clamp(0.0, 1.0);
  }

  bool get isComplete => completedCount >= rubric.scoringCount;
}

class EvaluacionController extends AsyncNotifier<EvaluacionFormState> {
  EvaluacionController(this.key);
  final EvaluacionKey key;

  static const _uuid = Uuid();

  /// #8: decide si reconciliar la fila local con el estado remoto al abrir.
  /// Sólo reconciliamos filas YA creadas en el server, SIN cambios sucios y SIN
  /// un submit offline pendiente (submitRequested=true con submittedAt local
  /// null): ese caso indica una intención de envío que aún no llegó al servidor
  /// y que reconciliar borraría (el server devolvería submitted_at=NULL).
  static bool shouldReconcileOnOpen(Evaluacione row) {
    if (row.serverId == null) return false;
    if (row.dirty) return false;
    if (row.submitRequested && row.submittedAt == null) return false;
    return true;
  }

  @override
  Future<EvaluacionFormState> build() async {
    final auth = ref.read(authControllerProvider).value;
    if (auth is! AuthAuthenticated) {
      throw const EvaluacionForbidden();
    }
    final juradoId = auth.user.id;

    final rubricsDao = ref.read(rubricsDaoProvider);
    final dao = ref.read(evaluacionesDaoProvider);
    final repo = ref.read(evaluacionesRepositoryProvider);

    // 1. Rubric: API → cache local. Fallback a Drift si no hay red.
    RubricTemplateDetail rubric;
    try {
      rubric = await repo.fetchRubric(key.templateId);
      await rubricsDao.upsertTree(rubric);
    } on EvaluacionNetworkFailure {
      final cached = await rubricsDao.loadTree(key.templateId);
      if (cached == null) rethrow;
      rubric = cached;
    }

    // 2. Buscar evaluación local por (prototipo, template, jurado).
    var bundle = await dao.findByKey(
      prototipoId: key.prototipoId,
      templateId: key.templateId,
      juradoId: juradoId,
    );

    // 3. Si el server ya la tiene (asignación cacheada), hidratamos el local
    //    con el estado remoto autoritativo antes de abrir el formulario.
    final asignaciones = ref.read(asignacionesControllerProvider).value;
    String? serverId;
    if (asignaciones != null) {
      for (final a in asignaciones) {
        if (a.prototipo.id == key.prototipoId &&
            a.rubric.id == key.templateId) {
          serverId = a.evaluacionId;
          break;
        }
      }
    }

    if (serverId != null && (bundle == null || bundle.row.serverId == null)) {
      try {
        final remote = await repo.fetchEvaluacion(serverId);
        bundle = await _hydrateFromRemote(
          dao: dao,
          juradoId: juradoId,
          existing: bundle,
          remote: remote,
        );
      } on EvaluacionNetworkFailure {
        // OK: trabajamos con lo que haya en local, sin hidratación.
      }
    } else if (bundle != null && shouldReconcileOnOpen(bundle.row)) {
      // #8: ya tenemos el server id y la fila NO tiene cambios pendientes.
      // Reconciliamos con el estado remoto autoritativo al abrir: p.ej. un
      // reopen del admin (submitted_at = NULL) debe reflejarse localmente
      // (submittedAt → null, submitRequested → false). Conservador: sólo
      // reconciliamos filas limpias sin mutaciones pendientes; nunca pisamos
      // datos locales aún no sincronizados.
      try {
        final remote = await repo.fetchEvaluacion(bundle.row.serverId!);
        bundle = await _hydrateFromRemote(
          dao: dao,
          juradoId: juradoId,
          existing: bundle,
          remote: remote,
        );
      } on EvaluacionFailure {
        // Sin red o error transitorio: seguimos con el estado local.
      }
    }

    // 4. Si aún no hay fila local, crea placeholder pero sin tocar el servidor.
    bundle ??= await _createLocalPlaceholder(
      dao: dao,
      juradoId: juradoId,
    );

    return _toState(rubric: rubric, bundle: bundle);
  }

  Future<EvaluacionLocalBundle> _hydrateFromRemote({
    required EvaluacionesDao dao,
    required String juradoId,
    EvaluacionLocalBundle? existing,
    required EvaluacionView remote,
  }) async {
    final localId = existing?.row.id ?? _uuid.v4();
    await dao.upsertEvaluacion(EvaluacionesCompanion(
      id: Value(localId),
      serverId: Value(remote.id),
      prototipoId: Value(remote.prototipoId),
      templateId: Value(remote.templateId),
      juradoId: Value(juradoId),
      createdAt: Value(existing?.row.createdAt ?? DateTime.now().toUtc()),
      updatedAt: Value(DateTime.now().toUtc()),
      submittedAt: Value(remote.submittedAt),
      syncedAt: Value(DateTime.now().toUtc()),
      dirty: const Value(false),
      // #3 (cosmético): al hidratar un remoto YA enviado NO dejamos
      // submitRequested=true. El estado "enviado" ya lo cubre submittedAt; con
      // submitRequested=true la fila contaría como pending para siempre en
      // dirtyOrPending() y el badge nunca llegaría a 0.
      submitRequested: const Value(false),
      observaciones: Value(remote.observaciones),
      acompanamientoAsesor: Value(remote.acompanamientoAsesor),
      opinionPersonal: Value(remote.opinionPersonal),
      lastError: const Value(null),
    ));
    // Re-escribe scores según el servidor.
    for (final s in remote.scores) {
      await dao.setScore(localId, s.criterionId, s.score, s.textAnswer);
    }
    // setScore marca dirty=true; lo re-limpiamos porque venimos del servidor.
    await dao.onPatchedRemote(localId);

    final bundle = await dao.findByKey(
      prototipoId: remote.prototipoId,
      templateId: remote.templateId,
      juradoId: juradoId,
    );
    return bundle!;
  }

  Future<EvaluacionLocalBundle> _createLocalPlaceholder({
    required EvaluacionesDao dao,
    required String juradoId,
  }) async {
    final localId = _uuid.v4();
    final now = DateTime.now().toUtc();
    await dao.upsertEvaluacion(EvaluacionesCompanion(
      id: Value(localId),
      prototipoId: Value(key.prototipoId),
      templateId: Value(key.templateId),
      juradoId: Value(juradoId),
      createdAt: Value(now),
      updatedAt: Value(now),
      dirty: const Value(false), // sin cambios todavía → no pushea nada
      submitRequested: const Value(false),
    ));
    final bundle = await dao.findByKey(
      prototipoId: key.prototipoId,
      templateId: key.templateId,
      juradoId: juradoId,
    );
    return bundle!;
  }

  EvaluacionFormState _toState({
    required RubricTemplateDetail rubric,
    required EvaluacionLocalBundle bundle,
  }) {
    final scores = <String, int>{};
    final textAnswers = <String, String>{};
    for (final s in bundle.scores) {
      if (s.score != null) scores[s.criterionId] = s.score!;
      if (s.textAnswer != null && s.textAnswer!.isNotEmpty) {
        textAnswers[s.criterionId] = s.textAnswer!;
      }
    }
    return EvaluacionFormState(
      rubric: rubric,
      scores: scores,
      textAnswers: textAnswers,
      localId: bundle.row.id,
      serverId: bundle.row.serverId,
      submitted: bundle.row.submittedAt != null,
      submitRequested: bundle.row.submitRequested,
      dirty: bundle.row.dirty,
      observaciones: bundle.row.observaciones,
      acompanamientoAsesor: bundle.row.acompanamientoAsesor,
      opinionPersonal: bundle.row.opinionPersonal,
      lastError: bundle.row.lastError,
    );
  }

  // ---------------------------------------------------------------------
  //  Mutaciones (write-through + kick sync)
  // ---------------------------------------------------------------------

  Future<void> _refresh() async {
    final current = state.value;
    if (current == null) return;
    final dao = ref.read(evaluacionesDaoProvider);
    final bundle = await dao.findByKey(
      prototipoId: key.prototipoId,
      templateId: key.templateId,
      juradoId: _juradoId()!,
    );
    if (bundle == null) return;
    state = AsyncData(_toState(rubric: current.rubric, bundle: bundle));
  }

  String? _juradoId() {
    final auth = ref.read(authControllerProvider).value;
    return auth is AuthAuthenticated ? auth.user.id : null;
  }

  void _kickSync() {
    unawaited(ref.read(syncWorkerProvider).sync());
  }

  Future<void> setScore(String criterionId, int value) async {
    final current = state.value;
    if (current == null || current.submitted) return;
    await ref
        .read(evaluacionesDaoProvider)
        .setScore(current.localId, criterionId, value, null);
    await _refresh();
    _kickSync();
  }

  Future<void> setText(String criterionId, String value) async {
    final current = state.value;
    if (current == null || current.submitted) return;
    await ref.read(evaluacionesDaoProvider).setScore(
          current.localId,
          criterionId,
          null,
          value.isEmpty ? null : value,
        );
    await _refresh();
    _kickSync();
  }

  Future<void> setObservaciones(String value) async {
    final current = state.value;
    if (current == null || current.submitted) return;
    await ref
        .read(evaluacionesDaoProvider)
        .setMeta(localId: current.localId, observaciones: value);
    await _refresh();
    _kickSync();
  }

  Future<void> setAcompanamiento(bool? value) async {
    final current = state.value;
    if (current == null || current.submitted) return;
    await ref.read(evaluacionesDaoProvider).setMeta(
          localId: current.localId,
          acompanamientoAsesor: value,
        );
    await _refresh();
    _kickSync();
  }

  Future<void> setOpinionPersonal(int? value) async {
    final current = state.value;
    if (current == null || current.submitted) return;
    await ref.read(evaluacionesDaoProvider).setMeta(
          localId: current.localId,
          opinionPersonal: value,
        );
    await _refresh();
    _kickSync();
  }

  /// Marca la fila para submit. El [SyncWorker] ejecuta el POST /submit
  /// cuando haya red. Invalida asignaciones al completar.
  Future<void> requestSubmit() async {
    final current = state.value;
    if (current == null || current.submitted) return;
    final dao = ref.read(evaluacionesDaoProvider);
    await dao.requestSubmit(current.localId);
    await _refresh();
    await ref.read(syncWorkerProvider).sync();
    await _refresh();
    ref.invalidate(asignacionesControllerProvider);
  }

  /// Empuja el borrador actual sin marcar submit.
  Future<void> saveDraft() async {
    await ref.read(syncWorkerProvider).sync();
    await _refresh();
  }
}

final evaluacionControllerProvider = AsyncNotifierProvider.family<
    EvaluacionController, EvaluacionFormState, EvaluacionKey>(
  EvaluacionController.new,
);
