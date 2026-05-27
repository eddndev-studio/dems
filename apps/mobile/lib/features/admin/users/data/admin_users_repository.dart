import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/api/api_client.dart';
import 'admin_user_models.dart';

class AdminUsersRepository {
  AdminUsersRepository(this._dio);
  final Dio _dio;

  Future<List<AdminUser>> list({UserRole? role, bool? isActive}) async {
    try {
      final params = <String, dynamic>{};
      if (role != null) params['role'] = _roleParam(role);
      if (isActive != null) params['is_active'] = isActive;
      final response = await _dio.get<List<dynamic>>(
        '/admin/users',
        queryParameters: params,
      );
      return response.data!
          .cast<Map<String, dynamic>>()
          .map(AdminUser.fromJson)
          .toList(growable: false);
    } on DioException catch (e) {
      throw _map(e);
    } catch (e) {
      throw AdminUsersUnexpected(e.toString());
    }
  }

  Future<AdminUser> create({
    required String email,
    required String fullName,
    required UserRole role,
    required String password,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/admin/users',
        data: {
          'email': email,
          'full_name': fullName,
          'role': _roleParam(role),
          'password': password,
        },
      );
      return AdminUser.fromJson(response.data!);
    } on DioException catch (e) {
      throw _map(e);
    } catch (e) {
      throw AdminUsersUnexpected(e.toString());
    }
  }

  Future<AdminUser> patch(
    String id, {
    String? fullName,
    UserRole? role,
    bool? isActive,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (fullName != null) body['full_name'] = fullName;
      if (role != null) body['role'] = _roleParam(role);
      if (isActive != null) body['is_active'] = isActive;
      final response = await _dio.patch<Map<String, dynamic>>(
        '/admin/users/$id',
        data: body,
      );
      return AdminUser.fromJson(response.data!);
    } on DioException catch (e) {
      throw _map(e);
    } catch (e) {
      throw AdminUsersUnexpected(e.toString());
    }
  }

  Future<void> resetPassword(String id, String password) async {
    try {
      await _dio.put<void>(
        '/admin/users/$id/password',
        data: {'password': password},
      );
    } on DioException catch (e) {
      throw _map(e);
    } catch (e) {
      throw AdminUsersUnexpected(e.toString());
    }
  }

  Future<void> delete(String id) async {
    try {
      await _dio.delete<void>('/admin/users/$id');
    } on DioException catch (e) {
      throw _map(e);
    } catch (e) {
      throw AdminUsersUnexpected(e.toString());
    }
  }

  // ────────────────────────────────────────────────────────────────────────

  String _roleParam(UserRole r) => switch (r) {
        UserRole.admin => 'admin',
        UserRole.jurado => 'jurado',
      };

  AdminUsersFailure _map(DioException e) {
    final status = e.response?.statusCode;
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return const AdminUsersNetwork();
    }
    switch (status) {
      case 401:
        return const AdminUsersUnauthorized();
      case 404:
        return const AdminUsersNotFound();
      case 409:
        final detail = _detail(e.response?.data);
        if (detail != null && detail.contains('evaluations')) {
          return const AdminUsersHasEvaluations();
        }
        return const AdminUsersEmailTaken();
      case 422:
      case 400:
        return AdminUsersValidation(_detail(e.response?.data) ?? 'inválido');
      default:
        return AdminUsersUnexpected(e.message ?? 'HTTP $status');
    }
  }

  String? _detail(dynamic data) {
    if (data is Map<String, dynamic>) {
      final m = data['message'];
      if (m is String) return m;
    }
    return null;
  }
}

final adminUsersRepositoryProvider = Provider<AdminUsersRepository>((ref) {
  return AdminUsersRepository(ref.watch(apiClientProvider));
});
