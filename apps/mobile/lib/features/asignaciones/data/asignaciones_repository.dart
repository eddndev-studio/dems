import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/api_client.dart';
import 'asignacion_models.dart';

class AsignacionesRepository {
  AsignacionesRepository(this._dio);
  final Dio _dio;

  Future<List<AsignacionItem>> list() async {
    try {
      final response = await _dio.get<List<dynamic>>('/me/asignaciones');
      return response.data!
          .cast<Map<String, dynamic>>()
          .map(AsignacionItem.fromJson)
          .toList(growable: false);
    } on DioException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw AsignacionesUnexpected(e.toString());
    }
  }

  AsignacionesFailure _mapError(DioException e) {
    final status = e.response?.statusCode;
    if (status == 401) return const AsignacionesUnauthorized();
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return const AsignacionesNetworkFailure();
    }
    return AsignacionesUnexpected(e.message ?? 'HTTP $status');
  }
}

final asignacionesRepositoryProvider = Provider<AsignacionesRepository>((ref) {
  return AsignacionesRepository(ref.watch(apiClientProvider));
});
