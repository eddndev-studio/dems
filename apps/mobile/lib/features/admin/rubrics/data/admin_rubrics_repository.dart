import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/api/api_client.dart';
import 'rubric_models.dart';

class AdminRubricsRepository {
  AdminRubricsRepository(this._dio);
  final Dio _dio;

  Future<List<RubricSummary>> list({
    String? editionId,
    RubricType? tipo,
    bool? activo,
  }) async {
    try {
      final params = <String, dynamic>{};
      if (editionId != null) params['edition_id'] = editionId;
      if (tipo != null) params['tipo'] = tipo.apiValue;
      if (activo != null) params['activo'] = activo;
      final response = await _dio.get<List<dynamic>>(
        '/admin/rubric-templates',
        queryParameters: params,
      );
      return response.data!
          .cast<Map<String, dynamic>>()
          .map(RubricSummary.fromJson)
          .toList(growable: false);
    } on DioException catch (e) {
      throw _map(e);
    } catch (e) {
      throw RubricUnexpected(e.toString());
    }
  }

  Future<RubricDetail> create({
    required String editionId,
    required String nombre,
    required RubricType tipo,
    String? descripcion,
    required List<String> categorias,
    required List<Map<String, dynamic>> sections,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/admin/rubric-templates',
        data: {
          'edition_id': editionId,
          'nombre': nombre,
          'tipo': tipo.apiValue,
          if (descripcion != null && descripcion.isNotEmpty)
            'descripcion': descripcion,
          'categorias': categorias,
          'sections': sections,
        },
      );
      return RubricDetail.fromJson(response.data!);
    } on DioException catch (e) {
      throw _map(e);
    } catch (e) {
      throw RubricUnexpected(e.toString());
    }
  }

  /// Reemplaza por completo el árbol (categorías + secciones + criterios) de una
  /// rúbrica. Solo permitido si la edición está en preparación (si no, 409).
  Future<RubricDetail> replaceStructure(
    String id, {
    required List<String> categorias,
    required List<Map<String, dynamic>> sections,
  }) async {
    try {
      final response = await _dio.put<Map<String, dynamic>>(
        '/admin/rubric-templates/$id/structure',
        data: {'categorias': categorias, 'sections': sections},
      );
      return RubricDetail.fromJson(response.data!);
    } on DioException catch (e) {
      throw _map(e);
    } catch (e) {
      throw RubricUnexpected(e.toString());
    }
  }

  Future<RubricDetail> getById(String id) async {
    try {
      final response =
          await _dio.get<Map<String, dynamic>>('/admin/rubric-templates/$id');
      return RubricDetail.fromJson(response.data!);
    } on DioException catch (e) {
      throw _map(e);
    } catch (e) {
      throw RubricUnexpected(e.toString());
    }
  }

  Future<RubricDetail> patch(
    String id, {
    String? nombre,
    String? descripcion,
    bool? activo,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (nombre != null) body['nombre'] = nombre;
      if (descripcion != null) body['descripcion'] = descripcion;
      if (activo != null) body['activo'] = activo;
      final response = await _dio.patch<Map<String, dynamic>>(
        '/admin/rubric-templates/$id',
        data: body,
      );
      return RubricDetail.fromJson(response.data!);
    } on DioException catch (e) {
      throw _map(e);
    } catch (e) {
      throw RubricUnexpected(e.toString());
    }
  }

  Future<void> delete(String id) async {
    try {
      await _dio.delete<void>('/admin/rubric-templates/$id');
    } on DioException catch (e) {
      throw _map(e);
    } catch (e) {
      throw RubricUnexpected(e.toString());
    }
  }

  RubricFailure _map(DioException e) {
    final status = e.response?.statusCode;
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return const RubricNetwork();
    }
    final detail = _detail(e.response?.data);
    switch (status) {
      case 401:
        return const RubricUnauthorized();
      case 404:
        return const RubricNotFound();
      case 409:
        if (detail != null && detail.contains('preparacion')) {
          return const RubricLocked();
        }
        return const RubricHasEvaluations();
      case 400:
      case 422:
        return RubricValidation(detail ?? 'inválido');
      default:
        return RubricUnexpected(e.message ?? 'HTTP $status');
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

final adminRubricsRepositoryProvider =
    Provider<AdminRubricsRepository>((ref) {
  return AdminRubricsRepository(ref.watch(apiClientProvider));
});
