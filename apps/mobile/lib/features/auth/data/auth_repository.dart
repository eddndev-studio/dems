import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/api_client.dart';
import 'auth_models.dart';

class AuthRepository {
  AuthRepository(this._dio);
  final Dio _dio;

  Future<LoginResult> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/login',
        data: {'email': email, 'password': password},
      );
      return LoginResult.fromJson(response.data!);
    } on DioException catch (e) {
      throw _mapDioError(e);
    } catch (e) {
      throw UnexpectedAuthError(e.toString());
    }
  }

  Future<AuthTokens> refresh(String refreshToken) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
      );
      return AuthTokens(
        access: response.data!['access_token'] as String,
        refresh: response.data!['refresh_token'] as String,
      );
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  Future<AuthUser> me() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/me');
      return AuthUser.fromJson(response.data!);
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  AuthFailure _mapDioError(DioException e) {
    final status = e.response?.statusCode;
    if (status == 401) return const InvalidCredentials();
    if (status == 403) return const UserInactive();
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return const NetworkUnreachable();
    }
    return UnexpectedAuthError(e.message ?? 'Error HTTP $status');
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(apiClientProvider));
});
