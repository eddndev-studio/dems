import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../rubrics/data/rubric_models.dart';
import '../data/admin_results_repository.dart';
import '../data/result_models.dart';

class ResultsFilter {
  const ResultsFilter({
    this.editionId,
    this.categoriaSlug,
    this.rubricType = RubricType.exhibicion,
  });

  final String? editionId;
  final String? categoriaSlug;
  final RubricType rubricType;

  bool get isComplete => editionId != null && categoriaSlug != null;

  ResultsFilter copyWith({
    Object? editionId = _sentinel,
    Object? categoriaSlug = _sentinel,
    RubricType? rubricType,
  }) =>
      ResultsFilter(
        editionId: identical(editionId, _sentinel)
            ? this.editionId
            : editionId as String?,
        categoriaSlug: identical(categoriaSlug, _sentinel)
            ? this.categoriaSlug
            : categoriaSlug as String?,
        rubricType: rubricType ?? this.rubricType,
      );

  static const Object _sentinel = Object();
}

class ResultsFilterNotifier extends Notifier<ResultsFilter> {
  @override
  ResultsFilter build() => const ResultsFilter();

  void set(ResultsFilter next) => state = next;
}

final resultsFilterProvider =
    NotifierProvider<ResultsFilterNotifier, ResultsFilter>(
  ResultsFilterNotifier.new,
);

/// Tupla normalizada para el provider family. Riverpod sólo permite tipos
/// con equality estable; este record cumple sin boilerplate.
typedef ResultsQuery = ({
  String editionId,
  String categoriaSlug,
  RubricType rubricType,
});

final categoriaResultsProvider =
    FutureProvider.family<CategoriaResults, ResultsQuery>((ref, q) async {
  return ref.read(adminResultsRepositoryProvider).fetchByCategoria(
        slug: q.categoriaSlug,
        editionId: q.editionId,
        rubricType: q.rubricType,
      );
});

/// Resultado del filtro actual: `AsyncValue<CategoriaResults?>`. Devuelve null
/// si el filtro está incompleto (sin edición o sin categoría seleccionada).
final filteredResultsProvider =
    Provider<AsyncValue<CategoriaResults?>>((ref) {
  final filter = ref.watch(resultsFilterProvider);
  if (!filter.isComplete) {
    return const AsyncData<CategoriaResults?>(null);
  }
  final r = ref.watch(categoriaResultsProvider((
    editionId: filter.editionId!,
    categoriaSlug: filter.categoriaSlug!,
    rubricType: filter.rubricType,
  )));
  return r.whenData<CategoriaResults?>((d) => d);
});
