import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/api/api_client.dart';
import 'prototipo_models.dart';

class AdminPrototiposRepository {
  AdminPrototiposRepository(this._dio);
  final Dio _dio;

  Future<List<PrototipoSummary>> list({String? editionId}) async {
    try {
      final params = <String, dynamic>{};
      if (editionId != null) params['edition_id'] = editionId;
      final response = await _dio.get<List<dynamic>>(
        '/admin/prototipos',
        queryParameters: params,
      );
      return response.data!
          .cast<Map<String, dynamic>>()
          .map(PrototipoSummary.fromJson)
          .toList(growable: false);
    } on DioException catch (e) {
      throw _map(e);
    } catch (e) {
      throw PrototipoUnexpected(e.toString());
    }
  }

  Future<PrototipoDetail> getById(String id) async {
    try {
      final response =
          await _dio.get<Map<String, dynamic>>('/admin/prototipos/$id');
      return PrototipoDetail.fromJson(response.data!);
    } on DioException catch (e) {
      throw _map(e);
    } catch (e) {
      throw PrototipoUnexpected(e.toString());
    }
  }

  Future<PrototipoDetail> create({
    required String editionId,
    required String folio,
    required String nombre,
    bool ejeTransversal = false,
    String? descripcion,
    List<String> categorias = const [],
    List<IntegranteInput> integrantes = const [],
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/admin/prototipos',
        data: {
          'edition_id': editionId,
          'folio': folio,
          'nombre': nombre,
          'eje_transversal': ejeTransversal,
          if (descripcion != null && descripcion.isNotEmpty)
            'descripcion': descripcion,
          'categorias': categorias,
          'integrantes': integrantes.map((i) => i.toJson()).toList(),
        },
      );
      return PrototipoDetail.fromJson(response.data!);
    } on DioException catch (e) {
      throw _map(e);
    } catch (e) {
      throw PrototipoUnexpected(e.toString());
    }
  }

  Future<PrototipoDetail> patch(
    String id, {
    String? nombre,
    bool? ejeTransversal,
    String? descripcion,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (nombre != null) body['nombre'] = nombre;
      if (ejeTransversal != null) body['eje_transversal'] = ejeTransversal;
      if (descripcion != null) body['descripcion'] = descripcion;
      final response = await _dio.patch<Map<String, dynamic>>(
        '/admin/prototipos/$id',
        data: body,
      );
      return PrototipoDetail.fromJson(response.data!);
    } on DioException catch (e) {
      throw _map(e);
    } catch (e) {
      throw PrototipoUnexpected(e.toString());
    }
  }

  Future<void> delete(String id) async {
    try {
      await _dio.delete<void>('/admin/prototipos/$id');
    } on DioException catch (e) {
      throw _map(e);
    } catch (e) {
      throw PrototipoUnexpected(e.toString());
    }
  }

  Future<List<Categoria>> listCategorias() async {
    try {
      final response =
          await _dio.get<List<dynamic>>('/admin/categorias');
      return response.data!
          .cast<Map<String, dynamic>>()
          .map(Categoria.fromJson)
          .toList(growable: false);
    } on DioException catch (e) {
      throw _map(e);
    } catch (e) {
      throw PrototipoUnexpected(e.toString());
    }
  }

  PrototipoFailure _map(DioException e) {
    final status = e.response?.statusCode;
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return const PrototipoNetwork();
    }
    final detail = _detail(e.response?.data);
    switch (status) {
      case 401:
        return const PrototipoUnauthorized();
      case 404:
        return const PrototipoNotFound();
      case 409:
        if (detail != null && detail.contains('evaluation')) {
          return const PrototipoHasEvaluations();
        }
        return const PrototipoFolioTaken();
      case 400:
      case 422:
        return PrototipoValidation(detail ?? 'inválido');
      default:
        return PrototipoUnexpected(e.message ?? 'HTTP $status');
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

final adminPrototiposRepositoryProvider =
    Provider<AdminPrototiposRepository>((ref) {
  return AdminPrototiposRepository(ref.watch(apiClientProvider));
});
