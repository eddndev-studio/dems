import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../data/api/api_client.dart';
import 'auth_models.dart';

const _kAccessKey = 'access_token';
const _kRefreshKey = 'refresh_token';
const _kUserIdKey = 'user_id';
const _kUserEmailKey = 'user_email';
const _kUserNameKey = 'user_name';
const _kUserRoleKey = 'user_role';

/// Wrapper around FlutterSecureStorage that keeps tokens + the cached
/// user profile together. The cached profile lets the app render the
/// shell immediately on cold boot while `/me` is re-validated in the background.
class AuthStorage {
  AuthStorage(this._storage);

  final FlutterSecureStorage _storage;

  Future<void> saveTokens(AuthTokens tokens) async {
    await _storage.write(key: _kAccessKey, value: tokens.access);
    await _storage.write(key: _kRefreshKey, value: tokens.refresh);
  }

  Future<void> saveUser(AuthUser user) async {
    await _storage.write(key: _kUserIdKey, value: user.id);
    await _storage.write(key: _kUserEmailKey, value: user.email);
    await _storage.write(key: _kUserNameKey, value: user.fullName);
    await _storage.write(key: _kUserRoleKey, value: user.role.name);
  }

  Future<AuthTokens?> readTokens() async {
    final access = await _storage.read(key: _kAccessKey);
    final refresh = await _storage.read(key: _kRefreshKey);
    if (access == null || refresh == null) return null;
    return AuthTokens(access: access, refresh: refresh);
  }

  Future<AuthUser?> readUser() async {
    final id = await _storage.read(key: _kUserIdKey);
    final email = await _storage.read(key: _kUserEmailKey);
    final name = await _storage.read(key: _kUserNameKey);
    final role = await _storage.read(key: _kUserRoleKey);
    if (id == null || email == null || name == null || role == null) {
      return null;
    }
    return AuthUser(
      id: id,
      email: email,
      fullName: name,
      role: UserRole.fromApi(role),
    );
  }

  Future<void> clear() async {
    await _storage.delete(key: _kAccessKey);
    await _storage.delete(key: _kRefreshKey);
    await _storage.delete(key: _kUserIdKey);
    await _storage.delete(key: _kUserEmailKey);
    await _storage.delete(key: _kUserNameKey);
    await _storage.delete(key: _kUserRoleKey);
  }
}

final authStorageProvider = Provider<AuthStorage>((ref) {
  return AuthStorage(ref.watch(secureStorageProvider));
});
