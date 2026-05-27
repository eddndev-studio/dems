import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/admin_user_models.dart';
import '../data/admin_users_repository.dart';

/// Filter is owned by the page; the controller exposes a filtered view of
/// the cached user list so applying a filter is a local-only operation
/// (no extra network round trip).
class AdminUsersFilterNotifier extends Notifier<AdminUsersFilter> {
  @override
  AdminUsersFilter build() => const AdminUsersFilter();

  // ignore: use_setters_to_change_properties
  void set(AdminUsersFilter next) => state = next;
}

final adminUsersFilterProvider =
    NotifierProvider<AdminUsersFilterNotifier, AdminUsersFilter>(
  AdminUsersFilterNotifier.new,
);

class AdminUsersController extends AsyncNotifier<List<AdminUser>> {
  @override
  Future<List<AdminUser>> build() async {
    return ref.read(adminUsersRepositoryProvider).list();
  }

  Future<void> refresh() async {
    state = const AsyncLoading<List<AdminUser>>();
    state = await AsyncValue.guard(
      () => ref.read(adminUsersRepositoryProvider).list(),
    );
  }

  /// Inserts the new user into the cached list without a roundtrip.
  Future<AdminUser> create({
    required String email,
    required String fullName,
    required UserRole role,
    required String password,
  }) async {
    final created = await ref.read(adminUsersRepositoryProvider).create(
          email: email,
          fullName: fullName,
          role: role,
          password: password,
        );
    final current = state.asData?.value ?? const <AdminUser>[];
    final next = [...current, created]..sort(
        (a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
    state = AsyncData(next);
    return created;
  }

  Future<AdminUser> patch(
    String id, {
    String? fullName,
    UserRole? role,
    bool? isActive,
  }) async {
    final updated = await ref.read(adminUsersRepositoryProvider).patch(
          id,
          fullName: fullName,
          role: role,
          isActive: isActive,
        );
    final current = state.asData?.value ?? const <AdminUser>[];
    final next = [
      for (final u in current)
        if (u.id == id) updated else u,
    ];
    state = AsyncData(next);
    return updated;
  }

  Future<void> toggleActive(AdminUser user) =>
      patch(user.id, isActive: !user.isActive);

  Future<void> resetPassword(String id, String password) =>
      ref.read(adminUsersRepositoryProvider).resetPassword(id, password);

  Future<void> delete(String id) async {
    await ref.read(adminUsersRepositoryProvider).delete(id);
    final current = state.asData?.value ?? const <AdminUser>[];
    state = AsyncData(current.where((u) => u.id != id).toList(growable: false));
  }
}

final adminUsersControllerProvider =
    AsyncNotifierProvider<AdminUsersController, List<AdminUser>>(
  AdminUsersController.new,
);

/// Filtered slice of the cached user list, derived purely client-side from
/// [adminUsersControllerProvider] + [adminUsersFilterProvider].
final filteredAdminUsersProvider = Provider<AsyncValue<List<AdminUser>>>((ref) {
  final users = ref.watch(adminUsersControllerProvider);
  final filter = ref.watch(adminUsersFilterProvider);
  return users.whenData((items) {
    final q = filter.query.trim().toLowerCase();
    return items.where((u) {
      if (filter.role != null && u.role != filter.role) return false;
      if (filter.activeOnly && !u.isActive) return false;
      if (q.isNotEmpty &&
          !u.fullName.toLowerCase().contains(q) &&
          !u.email.toLowerCase().contains(q)) {
        return false;
      }
      return true;
    }).toList(growable: false);
  });
});
