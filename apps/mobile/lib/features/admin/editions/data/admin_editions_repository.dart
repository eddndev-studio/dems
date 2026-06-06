import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/api/api_client.dart';
import 'edition_models.dart';

class AdminEditionsRepository {
  AdminEditionsRepository(this._dio);
  final Dio _dio;

  Future<List<Edition>> list() async {
    try {
      final response = await _dio.get<List<dynamic>>('/admin/editions');
      return response.data!
          .cast<Map<String, dynamic>>()
          .map(Edition.fromJson)
          .toList(growable: false);
    } on DioException catch (e) {
      throw _map(e);
    } catch (e) {
      throw EditionsUnexpected(e.toString());
    }
  }

  Future<Edition> create({
    required int year,
    required String name,
    required bool active,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/admin/editions',
        data: {'year': year, 'name': name, 'active': active},
      );
      return Edition.fromJson(response.data!);
    } on DioException catch (e) {
      throw _map(e);
    } catch (e) {
      throw EditionsUnexpected(e.toString());
    }
  }

  Future<Edition> patch(
    String id, {
    String? name,
    bool? active,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (name != null) body['name'] = name;
      if (active != null) body['active'] = active;
      final response = await _dio.patch<Map<String, dynamic>>(
        '/admin/editions/$id',
        data: body,
      );
      return Edition.fromJson(response.data!);
    } on DioException catch (e) {
      throw _map(e);
    } catch (e) {
      throw EditionsUnexpected(e.toString());
    }
  }

  Future<Edition> setPhase(String id, EditionPhase phase) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/admin/editions/$id/phase',
        data: {'phase': phase.apiValue},
      );
      return Edition.fromJson(response.data!);
    } on DioException catch (e) {
      throw _map(e);
    } catch (e) {
      throw EditionsUnexpected(e.toString());
    }
  }

  Future<void> delete(String id) async {
    try {
      await _dio.delete<void>('/admin/editions/$id');
    } on DioException catch (e) {
      throw _map(e);
    } catch (e) {
      throw EditionsUnexpected(e.toString());
    }
  }

  EditionsFailure _map(DioException e) {
    final status = e.response?.statusCode;
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return const EditionsNetwork();
    }
    switch (status) {
      case 401:
        return const EditionsUnauthorized();
      case 404:
        return const EditionsNotFound();
      case 409:
        final detail = _detail(e.response?.data);
        if (detail != null && detail.contains('year')) {
          return const EditionsYearTaken();
        }
        if (detail != null && detail.contains('evaluaciones')) {
          return const EditionsPhaseLocked();
        }
        return const EditionsHasReferences();
      case 400:
      case 422:
        return EditionsValidation(_detail(e.response?.data) ?? 'inválido');
      default:
        return EditionsUnexpected(e.message ?? 'HTTP $status');
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

final adminEditionsRepositoryProvider = Provider<AdminEditionsRepository>((ref) {
  return AdminEditionsRepository(ref.watch(apiClientProvider));
});
