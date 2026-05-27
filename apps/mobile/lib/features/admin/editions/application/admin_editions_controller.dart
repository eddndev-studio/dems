import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/admin_editions_repository.dart';
import '../data/edition_models.dart';

class AdminEditionsController extends AsyncNotifier<List<Edition>> {
  @override
  Future<List<Edition>> build() async {
    return ref.read(adminEditionsRepositoryProvider).list();
  }

  Future<void> refresh() async {
    state = const AsyncLoading<List<Edition>>();
    state = await AsyncValue.guard(
      () => ref.read(adminEditionsRepositoryProvider).list(),
    );
  }

  Future<Edition> create({
    required int year,
    required String name,
    required bool active,
  }) async {
    final created = await ref
        .read(adminEditionsRepositoryProvider)
        .create(year: year, name: name, active: active);
    final current = state.asData?.value ?? const <Edition>[];
    // When the new edition is active, every other edition is now inactive.
    final withFlip = active
        ? current
            .map((e) => Edition(
                  id: e.id,
                  year: e.year,
                  name: e.name,
                  active: false,
                  createdAt: e.createdAt,
                ))
            .toList()
        : List<Edition>.from(current);
    final next = [created, ...withFlip]..sort((a, b) => b.year.compareTo(a.year));
    state = AsyncData(next);
    return created;
  }

  Future<Edition> patch(
    String id, {
    String? name,
    bool? active,
  }) async {
    final updated = await ref
        .read(adminEditionsRepositoryProvider)
        .patch(id, name: name, active: active);

    final current = state.asData?.value ?? const <Edition>[];
    // If we just activated `id`, every other edition must reflect inactive.
    final next = [
      for (final e in current)
        if (e.id == id)
          updated
        else if (active == true && e.active)
          Edition(
            id: e.id,
            year: e.year,
            name: e.name,
            active: false,
            createdAt: e.createdAt,
          )
        else
          e,
    ];
    state = AsyncData(next);
    return updated;
  }

  Future<void> toggleActive(Edition edition) =>
      patch(edition.id, active: !edition.active);

  Future<void> delete(String id) async {
    await ref.read(adminEditionsRepositoryProvider).delete(id);
    final current = state.asData?.value ?? const <Edition>[];
    state = AsyncData(current.where((e) => e.id != id).toList(growable: false));
  }
}

final adminEditionsControllerProvider =
    AsyncNotifierProvider<AdminEditionsController, List<Edition>>(
  AdminEditionsController.new,
);
