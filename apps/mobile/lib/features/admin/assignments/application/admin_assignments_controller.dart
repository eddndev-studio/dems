import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/admin_assignments_repository.dart';
import '../data/assignment_models.dart';

/// AsyncNotifier keyed by prototipoId; one instance per expanded prototipo card.
class PrototipoAssignmentsController
    extends AsyncNotifier<List<Assignment>> {
  PrototipoAssignmentsController(this.prototipoId);
  final String prototipoId;

  @override
  Future<List<Assignment>> build() {
    return ref
        .read(adminAssignmentsRepositoryProvider)
        .listForPrototipo(prototipoId);
  }

  Future<void> refresh() async {
    state = const AsyncLoading<List<Assignment>>();
    state = await AsyncValue.guard(
      () => ref
          .read(adminAssignmentsRepositoryProvider)
          .listForPrototipo(prototipoId),
    );
  }

  Future<void> assignJurado({
    required JuradoOption jurado,
    required TemplateOption template,
  }) async {
    final result =
        await ref.read(adminAssignmentsRepositoryProvider).create(
              juradoId: jurado.id,
              prototipoId: prototipoId,
              templateId: template.id,
            );
    final current = state.asData?.value ?? const <Assignment>[];
    // The API may return an existing assignment (idempotent); avoid dupes.
    final exists = current.any(
      (a) => a.juradoId == jurado.id && a.templateId == template.id,
    );
    if (exists) return;
    final merged = Assignment(
      prototipoId: result.prototipoId,
      juradoId: result.juradoId,
      juradoFullName: jurado.fullName,
      juradoEmail: jurado.email,
      templateId: result.templateId,
      assignedAt: result.assignedAt,
    );
    final next = [...current, merged]
      ..sort((a, b) => a.juradoFullName.compareTo(b.juradoFullName));
    state = AsyncData(next);
  }

  Future<void> unassign(Assignment a) async {
    await ref.read(adminAssignmentsRepositoryProvider).delete(
          juradoId: a.juradoId,
          prototipoId: a.prototipoId,
          templateId: a.templateId,
        );
    final current = state.asData?.value ?? const <Assignment>[];
    state = AsyncData(
      current
          .where((x) =>
              !(x.juradoId == a.juradoId &&
                  x.templateId == a.templateId &&
                  x.prototipoId == a.prototipoId))
          .toList(growable: false),
    );
  }
}

final prototipoAssignmentsControllerProvider = AsyncNotifierProvider.family<
    PrototipoAssignmentsController, List<Assignment>, String>(
  PrototipoAssignmentsController.new,
);

/// Catalog of active jurados (cacheado para todo el panel).
final activeJuradosProvider = FutureProvider<List<JuradoOption>>((ref) async {
  return ref.read(adminAssignmentsRepositoryProvider).listActiveJurados();
});

/// Templates de una edición. Cada prototipo usa el de su propia edition_id.
final templatesByEditionProvider =
    FutureProvider.family<List<TemplateOption>, String>((ref, editionId) async {
  return ref
      .read(adminAssignmentsRepositoryProvider)
      .listTemplatesByEdition(editionId);
});
