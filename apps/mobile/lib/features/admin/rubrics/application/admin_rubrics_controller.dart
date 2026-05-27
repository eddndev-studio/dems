import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/admin_rubrics_repository.dart';
import '../data/rubric_models.dart';

class RubricsFilter {
  const RubricsFilter({
    this.editionId,
    this.tipo,
    this.activo,
    this.query = '',
  });

  final String? editionId;
  final RubricType? tipo;
  final bool? activo;
  final String query;

  RubricsFilter copyWith({
    Object? editionId = _sentinel,
    Object? tipo = _sentinel,
    Object? activo = _sentinel,
    String? query,
  }) =>
      RubricsFilter(
        editionId: identical(editionId, _sentinel)
            ? this.editionId
            : editionId as String?,
        tipo: identical(tipo, _sentinel) ? this.tipo : tipo as RubricType?,
        activo: identical(activo, _sentinel) ? this.activo : activo as bool?,
        query: query ?? this.query,
      );

  static const Object _sentinel = Object();
}

class RubricsFilterNotifier extends Notifier<RubricsFilter> {
  @override
  RubricsFilter build() => const RubricsFilter();

  void set(RubricsFilter next) => state = next;
}

final rubricsFilterProvider =
    NotifierProvider<RubricsFilterNotifier, RubricsFilter>(
  RubricsFilterNotifier.new,
);

class AdminRubricsController extends AsyncNotifier<List<RubricSummary>> {
  @override
  Future<List<RubricSummary>> build() {
    return ref.read(adminRubricsRepositoryProvider).list();
  }

  Future<void> refresh() async {
    state = const AsyncLoading<List<RubricSummary>>();
    state = await AsyncValue.guard(
      () => ref.read(adminRubricsRepositoryProvider).list(),
    );
  }

  Future<RubricDetail> toggleActivo(RubricSummary r) async {
    final detail = await ref
        .read(adminRubricsRepositoryProvider)
        .patch(r.id, activo: !r.activo);
    final current = state.asData?.value ?? const <RubricSummary>[];
    state = AsyncData([
      for (final s in current)
        if (s.id == r.id) s.copyWith(activo: detail.activo) else s,
    ]);
    return detail;
  }

  Future<void> delete(String id) async {
    await ref.read(adminRubricsRepositoryProvider).delete(id);
    final current = state.asData?.value ?? const <RubricSummary>[];
    state = AsyncData(current.where((r) => r.id != id).toList(growable: false));
  }
}

final adminRubricsControllerProvider =
    AsyncNotifierProvider<AdminRubricsController, List<RubricSummary>>(
  AdminRubricsController.new,
);

/// Lazy detail view (sections + criteria) for the inspector dialog.
final rubricDetailProvider =
    FutureProvider.family<RubricDetail, String>((ref, id) async {
  return ref.read(adminRubricsRepositoryProvider).getById(id);
});

/// Derived filtered list.
final filteredRubricsProvider =
    Provider<AsyncValue<List<RubricSummary>>>((ref) {
  final filter = ref.watch(rubricsFilterProvider);
  final items = ref.watch(adminRubricsControllerProvider);
  return items.whenData((list) {
    Iterable<RubricSummary> r = list;
    if (filter.editionId != null) {
      r = r.where((s) => s.editionId == filter.editionId);
    }
    if (filter.tipo != null) r = r.where((s) => s.tipo == filter.tipo);
    if (filter.activo != null) r = r.where((s) => s.activo == filter.activo);
    if (filter.query.isNotEmpty) {
      final q = filter.query.toLowerCase();
      r = r.where((s) => s.nombre.toLowerCase().contains(q));
    }
    return r.toList(growable: false);
  });
});
