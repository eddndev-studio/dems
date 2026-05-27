import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/admin_prototipos_repository.dart';
import '../data/prototipo_models.dart';

/// Filter applied to the prototipos list. `null` means "todas las ediciones".
class PrototiposFilter {
  const PrototiposFilter({this.editionId, this.query = ''});

  final String? editionId;
  final String query;

  PrototiposFilter copyWith({
    Object? editionId = _sentinel,
    String? query,
  }) =>
      PrototiposFilter(
        editionId:
            identical(editionId, _sentinel) ? this.editionId : editionId as String?,
        query: query ?? this.query,
      );

  static const Object _sentinel = Object();
}

class PrototiposFilterNotifier extends Notifier<PrototiposFilter> {
  @override
  PrototiposFilter build() => const PrototiposFilter();

  void set(PrototiposFilter next) => state = next;
}

final prototiposFilterProvider =
    NotifierProvider<PrototiposFilterNotifier, PrototiposFilter>(
  PrototiposFilterNotifier.new,
);

class AdminPrototiposController extends AsyncNotifier<List<PrototipoSummary>> {
  @override
  Future<List<PrototipoSummary>> build() async {
    return ref.read(adminPrototiposRepositoryProvider).list();
  }

  Future<void> refresh() async {
    state = const AsyncLoading<List<PrototipoSummary>>();
    state = await AsyncValue.guard(
      () => ref.read(adminPrototiposRepositoryProvider).list(),
    );
  }

  Future<PrototipoDetail> create({
    required String editionId,
    required String folio,
    required String nombre,
    String? plantel,
    bool ejeTransversal = false,
    String? descripcion,
    List<String> categorias = const [],
    List<IntegranteInput> integrantes = const [],
  }) async {
    final detail = await ref.read(adminPrototiposRepositoryProvider).create(
          editionId: editionId,
          folio: folio,
          nombre: nombre,
          plantel: plantel,
          ejeTransversal: ejeTransversal,
          descripcion: descripcion,
          categorias: categorias,
          integrantes: integrantes,
        );
    final current = state.asData?.value ?? const <PrototipoSummary>[];
    final next = [...current, detail.toSummary()]
      ..sort((a, b) => a.folio.compareTo(b.folio));
    state = AsyncData(next);
    return detail;
  }

  Future<PrototipoDetail> patch(
    String id, {
    String? nombre,
    String? plantel,
    bool? ejeTransversal,
    String? descripcion,
  }) async {
    final detail = await ref.read(adminPrototiposRepositoryProvider).patch(
          id,
          nombre: nombre,
          plantel: plantel,
          ejeTransversal: ejeTransversal,
          descripcion: descripcion,
        );
    final current = state.asData?.value ?? const <PrototipoSummary>[];
    state = AsyncData([
      for (final p in current)
        if (p.id == id) detail.toSummary() else p,
    ]);
    return detail;
  }

  Future<void> delete(String id) async {
    await ref.read(adminPrototiposRepositoryProvider).delete(id);
    final current = state.asData?.value ?? const <PrototipoSummary>[];
    state = AsyncData(current.where((p) => p.id != id).toList(growable: false));
  }
}

final adminPrototiposControllerProvider = AsyncNotifierProvider<
    AdminPrototiposController, List<PrototipoSummary>>(
  AdminPrototiposController.new,
);

/// Cached catalog of categorías for the form's multi-select.
final categoriasCatalogProvider =
    FutureProvider<List<Categoria>>((ref) async {
  return ref.read(adminPrototiposRepositoryProvider).listCategorias();
});

/// Loads the full detail of a prototipo (categorías + integrantes).
final prototipoDetailProvider =
    FutureProvider.family<PrototipoDetail, String>((ref, id) async {
  return ref.read(adminPrototiposRepositoryProvider).getById(id);
});

/// Filtered view by edition + query.
final filteredPrototiposProvider =
    Provider<AsyncValue<List<PrototipoSummary>>>((ref) {
  final filter = ref.watch(prototiposFilterProvider);
  final items = ref.watch(adminPrototiposControllerProvider);
  return items.whenData((list) {
    Iterable<PrototipoSummary> r = list;
    if (filter.editionId != null) {
      r = r.where((p) => p.editionId == filter.editionId);
    }
    if (filter.query.isNotEmpty) {
      final q = filter.query.toLowerCase();
      r = r.where((p) =>
          p.folio.toLowerCase().contains(q) ||
          p.nombre.toLowerCase().contains(q));
    }
    return r.toList(growable: false);
  });
});
