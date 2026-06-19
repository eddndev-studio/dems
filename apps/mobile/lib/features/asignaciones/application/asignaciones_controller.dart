import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/asignacion_models.dart';
import '../data/asignaciones_repository.dart';

class AsignacionesController extends AsyncNotifier<List<AsignacionItem>> {
  @override
  Future<List<AsignacionItem>> build() async {
    return orderAsignaciones(
      await ref.read(asignacionesRepositoryProvider).list(),
    );
  }

  Future<void> refresh() async {
    state = const AsyncLoading<List<AsignacionItem>>();
    state = await AsyncValue.guard(
      () async => orderAsignaciones(
        await ref.read(asignacionesRepositoryProvider).list(),
      ),
    );
  }
}

final asignacionesControllerProvider =
    AsyncNotifierProvider<AsignacionesController, List<AsignacionItem>>(
  AsignacionesController.new,
);
